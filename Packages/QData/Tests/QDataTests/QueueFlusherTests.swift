import XCTest
import QModel
import QNetwork
@testable import QData

private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Int64 = 1_000_000
    var now: Int64 { lock.lock(); defer { lock.unlock() }; return value }
    func advance(_ ms: Int64) { lock.lock(); value += ms; lock.unlock() }
}

/// Suspends submit callers until opened; counts how many have arrived.
private actor TestGate {
    private var isOpen = false
    private var entered = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func pass() async {
        entered += 1
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        let all = waiters
        waiters = []
        for waiter in all { waiter.resume() }
    }

    func waitUntilEntered(_ count: Int = 1) async {
        while entered < count { try? await Task.sleep(nanoseconds: 5_000_000) }
    }
}

private final class MockSubmitter: SessionSubmitting, @unchecked Sendable {
    typealias Behavior = @Sendable (Int, [SubmittedSession]) async throws -> SubmitSessionsResponse

    private let lock = NSLock()
    private var recorded: [[String]] = []
    private let behavior: Behavior

    init(_ behavior: @escaping Behavior = { _, sessions in
        SubmitSessionsResponse(sessions: sessions.map {
            SubmittedSessionResponse(submissionId: $0.submissionId, outcome: .processed, cards: [])
        })
    }) {
        self.behavior = behavior
    }

    var calls: [[String]] { lock.lock(); defer { lock.unlock() }; return recorded }
    var allSentIds: [String] { calls.flatMap { $0 } }

    func submit(_ sessions: [SubmittedSession]) async throws -> SubmitSessionsResponse {
        lock.lock()
        recorded.append(sessions.map { $0.submissionId })
        let index = recorded.count - 1
        lock.unlock()
        return try await behavior(index, sessions)
    }
}

private func ok(_ sessions: [SubmittedSession]) -> SubmitSessionsResponse {
    SubmitSessionsResponse(sessions: sessions.map {
        SubmittedSessionResponse(submissionId: $0.submissionId, outcome: .processed, cards: [])
    })
}

final class QueueFlusherTests: XCTestCase {
    private let user = "u1"

    private func session(_ id: String) -> SubmittedSession {
        SubmittedSession(
            submissionId: id, courseCode: "fa", unitKey: "u1", skillKey: "s1", courseVersion: 3,
            occurredAt: Date(timeIntervalSince1970: 1_789_466_400), completed: true, items: [])
    }

    private func makeQueue(_ storage: OfflineQueueStorage = InMemoryOfflineQueueStorage(), clock: TestClock = TestClock()) -> OfflineQueue {
        OfflineQueue(storage: storage, nowMillis: { clock.now })
    }

    // MARK: single flight

    func testConcurrentFlushesSubmitEachSessionOnce() async throws {
        let queue = makeQueue()
        try await queue.enqueue(userId: user, sessions: [session("a"), session("b")])
        let gate = TestGate()
        let submitter = MockSubmitter { _, sessions in
            await gate.pass()
            return ok(sessions)
        }
        let flusher = QueueFlusher(queue: queue, submitter: submitter)

        let results: [FlushReport] = try await withThrowingTaskGroup(of: FlushReport.self) { group in
            for _ in 0..<10 {
                group.addTask { try await flusher.flush(userId: "u1") }
            }
            await gate.waitUntilEntered()
            try? await Task.sleep(nanoseconds: 50_000_000)
            await gate.open()
            var all: [FlushReport] = []
            for try await report in group { all.append(report) }
            return all
        }

        XCTAssertEqual(submitter.calls.count, 1)
        XCTAssertEqual(submitter.allSentIds.sorted(), ["a", "b"])
        XCTAssertEqual(results.count, 10)
        let remaining = try await queue.loadQueue(userId: user)
        XCTAssertEqual(remaining, [])
    }

    func testEnqueueDuringFlushIsDrainedByRerunWithoutResendingTheFirst() async throws {
        let queue = makeQueue()
        try await queue.enqueue(userId: user, session: session("a"))
        let gate = TestGate()
        let submitter = MockSubmitter { _, sessions in
            await gate.pass()
            return ok(sessions)
        }
        let flusher = QueueFlusher(queue: queue, submitter: submitter)

        let first = Task { try await flusher.flush(userId: "u1") }
        await gate.waitUntilEntered()
        try await queue.enqueue(userId: user, session: session("b"))
        let second = Task { try await flusher.flush(userId: "u1") }
        try? await Task.sleep(nanoseconds: 30_000_000)
        await gate.open()
        let r1 = try await first.value
        let r2 = try await second.value

        XCTAssertEqual(submitter.calls, [["a"], ["b"]])
        XCTAssertEqual(r1.settled.sorted(), ["a", "b"])
        XCTAssertEqual(r2.settled.sorted(), ["a", "b"])
        let remaining = try await queue.loadQueue(userId: user)
        XCTAssertEqual(remaining, [])
    }

    func testSequentialFlushAfterSuccessSendsNothing() async throws {
        let queue = makeQueue()
        try await queue.enqueue(userId: user, session: session("a"))
        let submitter = MockSubmitter()
        let flusher = QueueFlusher(queue: queue, submitter: submitter)
        _ = try await flusher.flush(userId: user)
        let again = try await flusher.flush(userId: user)
        XCTAssertEqual(again.outcome, .idle)
        XCTAssertEqual(submitter.calls, [["a"]])
    }

    // MARK: failures never drop

    func testServerErrorRetainsWithBackoffThenRetriesOnceEligible() async throws {
        let clock = TestClock()
        let queue = makeQueue(clock: clock)
        try await queue.enqueue(userId: user, session: session("a"))
        let submitter = MockSubmitter { index, sessions in
            if index == 0 { throw ApiError(status: 503, body: nil) }
            return ok(sessions)
        }
        let flusher = QueueFlusher(queue: queue, submitter: submitter)

        let failed = try await flusher.flush(userId: user)
        guard case .transientFailure = failed.outcome else { return XCTFail("expected transient, got \(failed.outcome)") }
        var records = try await queue.records(userId: user)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].attempts, 1)
        XCTAssertNil(records[0].rejectionReason)
        XCTAssertEqual(failed.nextRetryAtMillis, clock.now + 30_000)

        // Still backing off: nothing is sent.
        let early = try await flusher.flush(userId: user)
        XCTAssertEqual(early.outcome, .idle)
        XCTAssertEqual(submitter.calls.count, 1)

        clock.advance(30_000)
        let retried = try await flusher.flush(userId: user)
        XCTAssertEqual(retried.outcome, .completed)
        records = try await queue.records(userId: user)
        XCTAssertEqual(records, [])
        XCTAssertEqual(submitter.allSentIds, ["a", "a"])
    }

    func testBackoffDoublesOnRepeatedFailure() async throws {
        let clock = TestClock()
        let queue = makeQueue(clock: clock)
        try await queue.enqueue(userId: user, session: session("a"))
        let submitter = MockSubmitter { _, _ in throw ApiError(status: 500, body: nil) }
        let flusher = QueueFlusher(queue: queue, submitter: submitter)
        _ = try await flusher.flush(userId: user)
        clock.advance(30_000)
        let second = try await flusher.flush(userId: user)
        XCTAssertEqual(second.nextRetryAtMillis, clock.now + 60_000)
    }

    func testNetworkFailureRetainsAndForegroundIgnoresBackoff() async throws {
        let queue = makeQueue()
        try await queue.enqueue(userId: user, session: session("a"))
        let submitter = MockSubmitter { index, sessions in
            if index == 0 { throw URLError(.notConnectedToInternet) }
            return ok(sessions)
        }
        let flusher = QueueFlusher(queue: queue, submitter: submitter)
        let failed = try await flusher.flush(userId: user)
        guard case .transientFailure = failed.outcome else { return XCTFail("expected transient") }
        let kept = try await queue.loadQueue(userId: user)
        XCTAssertEqual(kept.map { $0.submissionId }, ["a"])

        let regained = try await flusher.flush(userId: user, reason: .reachabilityRegained)
        XCTAssertEqual(regained.outcome, .completed)
        let left = try await queue.loadQueue(userId: user)
        XCTAssertEqual(left, [])
    }

    func testRetryableStatusesAreTransient() async throws {
        for status in [408, 429, 500, 502, 503] {
            let queue = makeQueue()
            try await queue.enqueue(userId: user, session: session("a"))
            let submitter = MockSubmitter { _, _ in throw ApiError(status: status, body: nil) }
            let flusher = QueueFlusher(queue: queue, submitter: submitter)
            let report = try await flusher.flush(userId: user)
            guard case .transientFailure = report.outcome else { return XCTFail("\(status) should be transient") }
            let kept = try await queue.loadQueue(userId: user)
            XCTAssertEqual(kept.count, 1, "status \(status)")
        }
    }

    func testDefinitive4xxIsPermanentButNeverDropsTheSession() async throws {
        for status in [400, 401, 403, 404, 413, 422] {
            let queue = makeQueue()
            try await queue.enqueue(userId: user, session: session("a"))
            let submitter = MockSubmitter { _, _ in throw ApiError(status: status, body: nil) }
            let flusher = QueueFlusher(queue: queue, submitter: submitter)
            let report = try await flusher.flush(userId: user)
            guard case let .permanentFailure(code, _) = report.outcome else { return XCTFail("\(status) should be permanent") }
            XCTAssertEqual(code, status)
            let records = try await queue.records(userId: user)
            XCTAssertEqual(records.count, 1, "status \(status)")
            XCTAssertEqual(records[0].attempts, 1)
            XCTAssertEqual(submitter.calls.count, 1, "no in-flight retry loop")
        }
    }

    func testPerSessionRejectionIsKeptAndFlaggedOthersSettle() async throws {
        let queue = makeQueue()
        try await queue.enqueue(userId: user, sessions: [session("good"), session("bad"), session("again")])
        let submitter = MockSubmitter { _, sessions in
            SubmitSessionsResponse(sessions: sessions.map { s in
                switch s.submissionId {
                case "bad":
                    return SubmittedSessionResponse(submissionId: s.submissionId, outcome: .rejected, rejectionReason: "stale course version", cards: [])
                case "again":
                    return SubmittedSessionResponse(submissionId: s.submissionId, outcome: .alreadyProcessed, cards: [])
                default:
                    return SubmittedSessionResponse(submissionId: s.submissionId, outcome: .processed, cards: [])
                }
            })
        }
        let flusher = QueueFlusher(queue: queue, submitter: submitter)
        let report = try await flusher.flush(userId: user)

        XCTAssertEqual(report.settled.sorted(), ["again", "good"])
        XCTAssertEqual(report.rejected, ["bad"])
        let records = try await queue.records(userId: user)
        XCTAssertEqual(records.map { $0.submissionId }, ["bad"])
        XCTAssertEqual(records[0].rejectionReason, "stale course version")
        let unsent = try await queue.loadQueue(userId: user)
        XCTAssertEqual(unsent, [])

        // A rejected item is never resent.
        let again = try await flusher.flush(userId: user, reason: .appForeground)
        XCTAssertEqual(again.outcome, .idle)
        XCTAssertEqual(submitter.calls.count, 1)
    }

    func testSessionMissingFromResponseStaysQueuedAndIsReportedUnanswered() async throws {
        let queue = makeQueue()
        try await queue.enqueue(userId: user, sessions: [session("a"), session("b")])
        let submitter = MockSubmitter { _, sessions in ok(sessions.filter { $0.submissionId == "a" }) }
        let flusher = QueueFlusher(queue: queue, submitter: submitter)
        let report = try await flusher.flush(userId: user)
        XCTAssertEqual(report.settled, ["a"])
        XCTAssertEqual(report.unanswered, ["b"])
        guard case .transientFailure = report.outcome else { return XCTFail("expected transient") }
        let kept = try await queue.loadQueue(userId: user)
        XCTAssertEqual(kept.map { $0.submissionId }, ["b"])
    }

    func testUnknownIdsInResponseAreIgnored() async throws {
        let queue = makeQueue()
        try await queue.enqueue(userId: user, session: session("a"))
        let submitter = MockSubmitter { _, sessions in
            SubmitSessionsResponse(sessions: [
                SubmittedSessionResponse(submissionId: "zzz", outcome: .processed, cards: []),
                SubmittedSessionResponse(submissionId: "a", outcome: .processed, cards: []),
            ])
        }
        let flusher = QueueFlusher(queue: queue, submitter: submitter)
        let report = try await flusher.flush(userId: user)
        XCTAssertEqual(report.settled, ["a"])
    }

    // MARK: cancellation and kill

    func testCancellingTheCallerMidSubmitStillCompletesAndRemovesExactlyOnce() async throws {
        let queue = makeQueue()
        try await queue.enqueue(userId: user, session: session("a"))
        let gate = TestGate()
        let submitter = MockSubmitter { _, sessions in
            await gate.pass()
            return ok(sessions)
        }
        let flusher = QueueFlusher(queue: queue, submitter: submitter)

        let caller = Task { try await flusher.flush(userId: "u1") }
        await gate.waitUntilEntered()
        caller.cancel()
        await gate.open()
        _ = try? await caller.value
        // The flight is detached from the caller: wait for it to settle.
        for _ in 0..<200 {
            let left = try await queue.loadQueue(userId: user)
            if left.isEmpty { break }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        let left = try await queue.loadQueue(userId: user)
        XCTAssertEqual(left, [])
        XCTAssertEqual(submitter.calls, [["a"]])

        let after = try await flusher.flush(userId: user)
        XCTAssertEqual(after.outcome, .idle)
        XCTAssertEqual(submitter.calls.count, 1)
    }

    func testCancelledRequestErrorKeepsTheSession() async throws {
        let queue = makeQueue()
        try await queue.enqueue(userId: user, session: session("a"))
        let submitter = MockSubmitter { _, _ in throw CancellationError() }
        let flusher = QueueFlusher(queue: queue, submitter: submitter)
        let report = try await flusher.flush(userId: user)
        guard case .transientFailure = report.outcome else { return XCTFail("expected transient") }
        let kept = try await queue.loadQueue(userId: user)
        XCTAssertEqual(kept.map { $0.submissionId }, ["a"])
    }

    func testKilledMidSubmitResendsSameSubmissionIdFromDisk() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("qf-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = FileOfflineQueueStorage(directory: dir)

        // Process 1: the request goes out, the app dies before the response is handled.
        let queue1 = makeQueue(storage)
        try await queue1.enqueue(userId: user, session: session("a"))
        let dying = MockSubmitter { _, _ in throw URLError(.networkConnectionLost) }
        _ = try await QueueFlusher(queue: queue1, submitter: dying).flush(userId: user)

        // Process 2: fresh queue and flusher over the same files; the server says AlreadyProcessed.
        let queue2 = makeQueue(storage)
        let server = MockSubmitter { _, sessions in
            SubmitSessionsResponse(sessions: sessions.map {
                SubmittedSessionResponse(submissionId: $0.submissionId, outcome: .alreadyProcessed, cards: [])
            })
        }
        let report = try await QueueFlusher(queue: queue2, submitter: server).flush(userId: user, reason: .appForeground)
        XCTAssertEqual(server.calls, [["a"]])
        XCTAssertEqual(report.settled, ["a"])
        let left = try await queue2.loadQueue(userId: user)
        XCTAssertEqual(left, [])
    }

    // MARK: undecodable entries

    func testUndecodableEntriesFailLoudlyAndSendNothing() async throws {
        let storage = InMemoryOfflineQueueStorage()
        let queue = makeQueue(storage)
        try await queue.enqueue(userId: user, session: session("good"))
        let data = try XCTUnwrap(storage.read(OfflineQueue.fileName(user)))
        var array = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [Any])
        array.append(["submissionId": "weird", "session": ["nope": true]])
        try storage.write(OfflineQueue.fileName(user), JSONSerialization.data(withJSONObject: array))

        let submitter = MockSubmitter()
        let flusher = QueueFlusher(queue: queue, submitter: submitter)
        do {
            _ = try await flusher.flush(userId: user)
            XCTFail("expected undecodableEntries")
        } catch let error as OfflineQueueError {
            XCTAssertEqual(error, .undecodableEntries(count: 1, submissionIds: ["weird"]))
        }
        XCTAssertEqual(submitter.calls.count, 0)
        let count = try await queue.unsentCount(userId: user)
        XCTAssertEqual(count, 2)

        // The flight was cleaned up: a later flush fails the same way rather than hanging.
        do {
            _ = try await flusher.flush(userId: user)
            XCTFail("expected undecodableEntries again")
        } catch is OfflineQueueError {}
    }

    // MARK: settled handler

    func testSettledHandlerRunsBeforeRemovalWithResults() async throws {
        let queue = makeQueue()
        try await queue.enqueue(userId: user, session: session("a"))
        let seenWhileQueued = ResultBox()
        let flusher = QueueFlusher(queue: queue, submitter: MockSubmitter(), onSettled: { userId, results in
            let still = (try? await queue.loadQueue(userId: userId).count) ?? -1
            seenWhileQueued.set(ids: results.map { $0.submissionId }, queuedCount: still)
        })
        _ = try await flusher.flush(userId: user)
        XCTAssertEqual(seenWhileQueued.ids, ["a"])
        XCTAssertEqual(seenWhileQueued.queuedCount, 1)
        let left = try await queue.loadQueue(userId: user)
        XCTAssertEqual(left, [])
    }

    // MARK: users are independent

    func testDifferentUsersFlushIndependently() async throws {
        let queue = makeQueue()
        try await queue.enqueue(userId: "u1", session: session("a"))
        try await queue.enqueue(userId: "u2", session: session("b"))
        let submitter = MockSubmitter()
        let flusher = QueueFlusher(queue: queue, submitter: submitter)
        async let r1 = flusher.flush(userId: "u1")
        async let r2 = flusher.flush(userId: "u2")
        let (a, b) = try await (r1, r2)
        XCTAssertEqual(a.settled, ["a"])
        XCTAssertEqual(b.settled, ["b"])
        XCTAssertEqual(submitter.allSentIds.sorted(), ["a", "b"])
    }

    // MARK: triggers

    func testDriverFlushesOnStartAndOnTrigger() async throws {
        let queue = makeQueue()
        try await queue.enqueue(userId: user, session: session("a"))
        let submitter = MockSubmitter()
        let flusher = QueueFlusher(queue: queue, submitter: submitter)
        let trigger = ManualFlushTrigger()
        let driver = QueueFlushDriver(flusher: flusher)
        let errors = ResultBox()
        driver.start(userId: user, sources: [trigger], onError: { _ in errors.bump() })
        defer { driver.stop() }

        try await waitUntil { (try? await queue.loadQueue(userId: "u1").isEmpty) == true }
        try await queue.enqueue(userId: user, session: session("b"))
        // The stream may not be subscribed yet at the instant of start; fire until it lands.
        try await waitUntil {
            trigger.fire(.reachabilityRegained)
            return (try? await queue.loadQueue(userId: "u1").isEmpty) == true
        }
        XCTAssertEqual(submitter.allSentIds, ["a", "b"])
        XCTAssertEqual(errors.count, 0)
    }

    func testDriverReportsUndecodableErrorsToOnError() async throws {
        let storage = InMemoryOfflineQueueStorage()
        let queue = makeQueue(storage)
        try storage.write(OfflineQueue.fileName(user), JSONSerialization.data(withJSONObject: [["submissionId": "weird"]]))
        let submitter = MockSubmitter()
        let flusher = QueueFlusher(queue: queue, submitter: submitter)
        let driver = QueueFlushDriver(flusher: flusher)
        let errors = ResultBox()
        driver.start(userId: user, sources: [], onError: { _ in errors.bump() })
        defer { driver.stop() }
        try await waitUntil { errors.count >= 1 }
        XCTAssertEqual(submitter.calls.count, 0)
    }

    private func waitUntil(_ condition: @escaping () async -> Bool) async throws {
        for _ in 0..<300 {
            if await condition() { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("condition not met in time")
    }
}

private final class ResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _ids: [String] = []
    private var _queuedCount = -1
    private var _count = 0

    func set(ids: [String], queuedCount: Int) {
        lock.lock(); _ids = ids; _queuedCount = queuedCount; lock.unlock()
    }
    func bump() { lock.lock(); _count += 1; lock.unlock() }
    var ids: [String] { lock.lock(); defer { lock.unlock() }; return _ids }
    var queuedCount: Int { lock.lock(); defer { lock.unlock() }; return _queuedCount }
    var count: Int { lock.lock(); defer { lock.unlock() }; return _count }
}
