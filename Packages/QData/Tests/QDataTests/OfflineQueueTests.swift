import XCTest
import QModel
@testable import QData

final class OfflineQueueTests: XCTestCase {
    private func session(_ id: String, _ courseCode: String = "fa", version: Int = 3) -> SubmittedSession {
        SubmittedSession(
            submissionId: id, courseCode: courseCode, unitKey: "u1", skillKey: "s1", courseVersion: version,
            occurredAt: Date(timeIntervalSince1970: 1_789_466_400.25), completed: true, items: [])
    }

    private func tempDir() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("oq-" + UUID().uuidString)
    }

    // Ported 1:1 from offlineQueue.test.ts

    func testRoundTripsQueuedSessionCourseCodeIncluded() async throws {
        let q = OfflineQueue(storage: InMemoryOfflineQueueStorage())
        try await q.enqueue(userId: "user-course-code", session: session("a", "fa"))
        try await q.enqueue(userId: "user-course-code", session: session("b", "ja"))
        let loaded = try await q.loadQueue(userId: "user-course-code")
        XCTAssertEqual(loaded.map { [$0.courseCode, $0.submissionId] }, [["fa", "a"], ["ja", "b"]])
    }

    func testDropsEntriesThatArentSessionShaped() async throws {
        let storage = InMemoryOfflineQueueStorage()
        let q = OfflineQueue(storage: storage)
        let userId = "user-corrupt"
        // One valid record built through the queue, then the file is rewritten with junk around it.
        try await q.enqueue(userId: userId, session: session("ok"))
        let good = try XCTUnwrap(storage.read(OfflineQueue.fileName(userId)))
        let goodArray = try XCTUnwrap(JSONSerialization.jsonObject(with: good) as? [Any])
        let mixed: [Any] = [goodArray[0], ["garbage": true], NSNull(), "x"]
        try storage.write(OfflineQueue.fileName(userId), JSONSerialization.data(withJSONObject: mixed))

        let loaded = try await q.loadQueue(userId: userId)
        XCTAssertEqual(loaded.map { $0.submissionId }, ["ok"])
    }

    func testNonArrayJSONIsUndecodableAndFlushFailsLoudly() async throws {
        let storage = InMemoryOfflineQueueStorage()
        let q = OfflineQueue(storage: storage)
        let userId = "user-non-array"
        let name = OfflineQueue.fileName(userId)
        let junk = Data("{\"not\":\"an array\"}".utf8)
        try storage.write(name, junk)
        let loaded = try await q.loadQueue(userId: userId)
        XCTAssertEqual(loaded, [])
        let undecodable = try await q.undecodableCount(userId: userId)
        XCTAssertEqual(undecodable, 1)
        let unsent = try await q.unsentCount(userId: userId)
        XCTAssertEqual(unsent, 1)
        do {
            _ = try await q.eligible(userId: userId)
            XCTFail("eligible should throw")
        } catch let error as OfflineQueueError {
            XCTAssertEqual(error, .undecodableEntries(count: 1, submissionIds: []))
        }
        XCTAssertEqual(try storage.read(name), junk)
        try await q.enqueue(userId: userId, session: session("a"))
        XCTAssertEqual(try storage.read(name + ".corrupt"), junk)
    }

    func testUnknownEntryFieldsSurviveRewrite() async throws {
        let storage = InMemoryOfflineQueueStorage()
        let q = OfflineQueue(storage: storage)
        let name = OfflineQueue.fileName("u")
        try await q.enqueue(userId: "u", session: session("a"))
        var array = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(storage.read(name))) as? [Any])
        var entry = try XCTUnwrap(array[0] as? [String: Any])
        entry["futureField"] = ["x": 1]
        array[0] = entry
        try storage.write(name, JSONSerialization.data(withJSONObject: array))

        try await q.recordFailure(userId: "u", submissionIds: ["a"], error: "boom")
        try await q.enqueue(userId: "u", session: session("b"))
        let after = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(storage.read(name))) as? [Any])
        let first = try XCTUnwrap(after[0] as? [String: Any])
        XCTAssertEqual((first["futureField"] as? [String: Any])?["x"] as? Int, 1)
        XCTAssertEqual(first["attempts"] as? Int, 1)
        XCTAssertEqual(first["lastError"] as? String, "boom")
    }

    func testLockKeyResolvesSymlinks() throws {
        let real = tempDir()
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        let link = tempDir()
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        defer {
            try? FileManager.default.removeItem(at: link)
            try? FileManager.default.removeItem(at: real)
        }
        let viaLink = FileOfflineQueueStorage(directory: link)
        let direct = FileOfflineQueueStorage(directory: real)
        XCTAssertEqual(viaLink.lockKey, direct.lockKey)
    }

    func testRemovesOnlySettledSubmissions() async throws {
        let q = OfflineQueue(storage: InMemoryOfflineQueueStorage())
        try await q.enqueue(userId: "user-remove", session: session("keep"))
        try await q.enqueue(userId: "user-remove", session: session("drop"))
        try await q.removeFromQueue(userId: "user-remove", submissionIds: ["drop"])
        let loaded = try await q.loadQueue(userId: "user-remove")
        XCTAssertEqual(loaded.map { $0.submissionId }, ["keep"])
    }

    func testNotifiesListenersOnEnqueueAndRemoval() async throws {
        let q = OfflineQueue(storage: InMemoryOfflineQueueStorage())
        let stream = await q.changes()
        try await q.enqueue(userId: "user-events", session: session("x"))
        try await q.removeFromQueue(userId: "user-events", submissionIds: ["x"])
        var iterator = stream.makeAsyncIterator()
        var fired = 0
        _ = await iterator.next(); fired += 1
        _ = await iterator.next(); fired += 1
        XCTAssertEqual(fired, 2)
    }

    func testHasUnknownSubmissionsTrueForSessionEnqueuedDuringFlush() {
        XCTAssertTrue(OfflineQueue.hasUnknownSubmissions([session("fa-2")], knownIds: ["fa-1"]))
    }

    func testHasUnknownSubmissionsFalseForKnownEntries() {
        XCTAssertFalse(OfflineQueue.hasUnknownSubmissions([session("ja-1", "ja")], knownIds: ["fa-1", "ja-1"]))
    }

    // Added: durability, isolation, ordering, retry metadata

    func testSurvivesRelaunchWithFileStorage() async throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let first = OfflineQueue(storage: FileOfflineQueueStorage(directory: dir))
        try await first.enqueue(userId: "u", session: session("a"))
        try await first.enqueue(userId: "u", session: session("b"))
        try await first.recordFailure(userId: "u", submissionIds: ["a"], error: "offline")

        let second = OfflineQueue(storage: FileOfflineQueueStorage(directory: dir))
        let records = try await second.records(userId: "u")
        XCTAssertEqual(records.map { $0.submissionId }, ["a", "b"])
        XCTAssertEqual(records[0].attempts, 1)
        XCTAssertEqual(records[0].lastError, "offline")
        XCTAssertEqual(records[0].session, session("a"))
    }

    func testPerUserIsolation() async throws {
        let q = OfflineQueue(storage: InMemoryOfflineQueueStorage())
        try await q.enqueue(userId: "alice", session: session("a1"))
        try await q.enqueue(userId: "bob", session: session("b1"))
        let aliceIds = try await q.loadQueue(userId: "alice").map { $0.submissionId }
        let bobIds = try await q.loadQueue(userId: "bob").map { $0.submissionId }
        XCTAssertEqual(aliceIds, ["a1"])
        XCTAssertEqual(bobIds, ["b1"])
        try await q.clear(userId: "alice")
        let aliceAfter = try await q.loadQueue(userId: "alice")
        let bobAfter = try await q.unsentCount(userId: "bob")
        XCTAssertEqual(aliceAfter, [])
        XCTAssertEqual(bobAfter, 1)
    }

    func testConcurrentEnqueueKeepsEverything() async throws {
        let q = OfflineQueue(storage: InMemoryOfflineQueueStorage())
        let sessions = (0..<60).map { session("s\($0)") }
        try await withThrowingTaskGroup(of: Void.self) { group in
            for s in sessions {
                group.addTask { try await q.enqueue(userId: "u", session: s) }
            }
            try await group.waitForAll()
        }
        let ids = try await q.loadQueue(userId: "u").map { $0.submissionId }
        XCTAssertEqual(ids.count, 60)
        XCTAssertEqual(Set(ids).count, 60)
    }

    func testEnqueueIsIdempotentBySubmissionId() async throws {
        let q = OfflineQueue(storage: InMemoryOfflineQueueStorage())
        let first = try await q.enqueue(userId: "u", session: session("a"))
        let second = try await q.enqueue(userId: "u", session: session("a", "ja"))
        XCTAssertTrue(first)
        XCTAssertFalse(second)
        let loaded = try await q.loadQueue(userId: "u")
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].courseCode, "fa")
    }

    func testFIFOOrderAndBatchEnqueue() async throws {
        let q = OfflineQueue(storage: InMemoryOfflineQueueStorage())
        let added = try await q.enqueue(userId: "u", sessions: [session("1"), session("2"), session("1"), session("3")])
        XCTAssertEqual(added, 3)
        let ids = try await q.loadQueue(userId: "u").map { $0.submissionId }
        XCTAssertEqual(ids, ["1", "2", "3"])
    }

    func testFailedWriteThrowsAndKeepsPreviousQueue() async throws {
        let storage = InMemoryOfflineQueueStorage()
        let q = OfflineQueue(storage: storage)
        try await q.enqueue(userId: "u", session: session("a"))
        storage.setFailWrites(true)
        do {
            try await q.enqueue(userId: "u", session: session("b"))
            XCTFail("expected throw")
        } catch {}
        storage.setFailWrites(false)
        let ids = try await q.loadQueue(userId: "u").map { $0.submissionId }
        XCTAssertEqual(ids, ["a"])
    }

    func testRejectedStaysQueuedButIsNotUnsent() async throws {
        let q = OfflineQueue(storage: InMemoryOfflineQueueStorage())
        try await q.enqueue(userId: "u", session: session("a"))
        try await q.enqueue(userId: "u", session: session("b"))
        try await q.markRejected(userId: "u", submissionId: "a", reason: "bad")
        let unsent = try await q.loadQueue(userId: "u").map { $0.submissionId }
        let count = try await q.unsentCount(userId: "u")
        let all = try await q.records(userId: "u")
        XCTAssertEqual(unsent, ["b"])
        XCTAssertEqual(count, 1)
        XCTAssertEqual(all.map { $0.submissionId }, ["a", "b"])
        XCTAssertEqual(all[0].rejectionReason, "bad")
    }

    func testRetryBackoffControlsEligibility() async throws {
        let clock = ClockBox(1_000_000)
        let q = OfflineQueue(storage: InMemoryOfflineQueueStorage(), nowMillis: { clock.value })
        try await q.enqueue(userId: "u", session: session("a"))
        try await q.enqueue(userId: "u", session: session("b"))
        try await q.recordFailure(userId: "u", submissionIds: ["a"], error: nil)
        var ids = try await q.eligible(userId: "u").map { $0.submissionId }
        XCTAssertEqual(ids, ["b"])
        clock.value += 30_000
        ids = try await q.eligible(userId: "u").map { $0.submissionId }
        XCTAssertEqual(ids, ["a", "b"])
        let total = try await q.unsentCount(userId: "u")
        XCTAssertEqual(total, 2)
    }

    func testBackoffGrowsAndCaps() {
        XCTAssertEqual(OfflineQueue.backoffMillis(attempts: 1), 30_000)
        XCTAssertEqual(OfflineQueue.backoffMillis(attempts: 2), 60_000)
        XCTAssertEqual(OfflineQueue.backoffMillis(attempts: 3), 120_000)
        XCTAssertEqual(OfflineQueue.backoffMillis(attempts: 50), 3_600_000)
    }

    func testUnreadableEntriesAreKeptOnDiskAcrossMutations() async throws {
        let storage = InMemoryOfflineQueueStorage()
        let q = OfflineQueue(storage: storage)
        let name = OfflineQueue.fileName("u")
        try storage.write(name, Data("[{\"garbage\":true}]".utf8))
        try await q.enqueue(userId: "u", session: session("a"))
        let data = try XCTUnwrap(storage.read(name))
        let array = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [Any])
        XCTAssertEqual(array.count, 2)
    }

    func testNonArrayFileIsQuarantinedBeforeOverwrite() async throws {
        let storage = InMemoryOfflineQueueStorage()
        let q = OfflineQueue(storage: storage)
        let name = OfflineQueue.fileName("u")
        try storage.write(name, Data("{\"not\":\"array\"}".utf8))
        try await q.enqueue(userId: "u", session: session("a"))
        XCTAssertEqual(try storage.read(name + ".corrupt"), Data("{\"not\":\"array\"}".utf8))
        let ids = try await q.loadQueue(userId: "u").map { $0.submissionId }
        XCTAssertEqual(ids, ["a"])
    }

    func testOccurredAtSurvivesRoundTripWithFraction() async throws {
        let q = OfflineQueue(storage: InMemoryOfflineQueueStorage())
        try await q.enqueue(userId: "u", session: session("a"))
        let loaded = try await q.loadQueue(userId: "u")
        XCTAssertEqual(loaded[0].occurredAt.timeIntervalSince1970, 1_789_466_400.25, accuracy: 0.001)
    }
    // Review fixes

    func testUndecodableEntriesCountAsUnsentAndFlushFailsLoudly() async throws {
        let storage = InMemoryOfflineQueueStorage()
        let q = OfflineQueue(storage: storage)
        try await q.enqueue(userId: "u", session: session("ok"))
        let name = OfflineQueue.fileName("u")
        let good = try XCTUnwrap(storage.read(name))
        var array = try XCTUnwrap(JSONSerialization.jsonObject(with: good) as? [Any])
        array.append(["submissionId": "stuck", "futureField": true])
        try storage.write(name, JSONSerialization.data(withJSONObject: array))

        let count = try await q.unsentCount(userId: "u")
        XCTAssertEqual(count, 2)
        let undecodable = try await q.undecodableCount(userId: "u")
        XCTAssertEqual(undecodable, 1)
        do {
            _ = try await q.eligible(userId: "u")
            XCTFail("eligible should throw")
        } catch let error as OfflineQueueError {
            XCTAssertEqual(error, .undecodableEntries(count: 1, submissionIds: ["stuck"]))
        }
        try await q.removeFromQueue(userId: "u", submissionIds: ["stuck", "ok"])
        let after = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(storage.read(name))) as? [Any])
        XCTAssertEqual(after.count, 1)
    }

    func testEnqueueDedupesAgainstUndecodableIds() async throws {
        let storage = InMemoryOfflineQueueStorage()
        let q = OfflineQueue(storage: storage)
        let name = OfflineQueue.fileName("u")
        try storage.write(name, JSONSerialization.data(withJSONObject: [["submissionId": "x", "futureField": 1]]))
        let added = try await q.enqueue(userId: "u", session: session("x"))
        XCTAssertFalse(added)
        let array = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(storage.read(name))) as? [Any])
        XCTAssertEqual(array.count, 1)
    }

    func testSeparateInstancesOnSameDirectoryDoNotLoseWrites() async throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = OfflineQueue(storage: FileOfflineQueueStorage(directory: dir))
        let b = OfflineQueue(storage: FileOfflineQueueStorage(directory: dir))
        let sessions = (0..<40).map { session("s\($0)") }
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<40 {
                let s = sessions[i]
                let q = i % 2 == 0 ? a : b
                group.addTask {
                    _ = try? await q.enqueue(userId: "u", session: s)
                }
            }
        }
        let ids = try await a.loadQueue(userId: "u").map { $0.submissionId }
        XCTAssertEqual(Set(ids).count, 40)
        XCTAssertEqual(ids.count, 40)
    }

    func testRepeatedCorruptionDoesNotOverwriteEarlierQuarantine() async throws {
        let storage = InMemoryOfflineQueueStorage()
        let q = OfflineQueue(storage: storage)
        let name = OfflineQueue.fileName("u")
        try storage.write(name, Data("{\"first\":1}".utf8))
        try await q.enqueue(userId: "u", session: session("a"))
        try storage.write(name, Data("{\"second\":2}".utf8))
        try await q.enqueue(userId: "u", session: session("b"))
        let corrupt = storage.names.filter { $0.hasPrefix(name + ".corrupt") }
        XCTAssertEqual(corrupt.count, 2)
        let blobs = try Set(corrupt.map { String(decoding: try XCTUnwrap(storage.read($0)), as: UTF8.self) })
        XCTAssertEqual(blobs, ["{\"first\":1}", "{\"second\":2}"])
    }

    func testClearRemovesCorruptLeftoversOfThatUserOnly() async throws {
        let storage = InMemoryOfflineQueueStorage()
        let q = OfflineQueue(storage: storage)
        let mine = OfflineQueue.fileName("u")
        let other = OfflineQueue.fileName("u2")
        try storage.write(mine, Data("[1".utf8))
        try await q.enqueue(userId: "u", session: session("a"))
        try storage.write(other, Data("{\"x\":1}".utf8))
        try await q.enqueue(userId: "u2", session: session("b"))
        try storage.write(mine, Data("{\"y\":1}".utf8))
        try await q.enqueue(userId: "u", session: session("c"))
        try await q.clear(userId: "u")
        XCTAssertTrue(storage.names.allSatisfy { !$0.hasPrefix(mine) })
        XCTAssertTrue(storage.names.contains(other + ".corrupt"))
        XCTAssertTrue(storage.names.contains(other))
    }

}

private final class ClockBox: @unchecked Sendable {
    var value: Int64
    init(_ value: Int64) { self.value = value }
}
