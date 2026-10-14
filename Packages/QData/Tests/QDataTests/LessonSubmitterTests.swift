import XCTest
import QModel
import QNetwork
@testable import QData

private final class StubSubmitter: SessionSubmitting, @unchecked Sendable {
    typealias Behavior = @Sendable ([SubmittedSession]) throws -> SubmitSessionsResponse
    private let lock = NSLock()
    private var recorded: [[String]] = []
    private let behavior: Behavior
    init(_ behavior: @escaping Behavior) { self.behavior = behavior }
    var calls: [[String]] { lock.lock(); defer { lock.unlock() }; return recorded }
    func submit(_ sessions: [SubmittedSession]) async throws -> SubmitSessionsResponse {
        lock.lock(); recorded.append(sessions.map { $0.submissionId }); lock.unlock()
        return try behavior(sessions)
    }
}

private func processed(_ sessions: [SubmittedSession]) -> SubmitSessionsResponse {
    SubmitSessionsResponse(sessions: sessions.map {
        SubmittedSessionResponse(submissionId: $0.submissionId, outcome: .processed, cards: [])
    })
}

final class LessonSubmitterTests: XCTestCase {
    private let user = "u1"

    private func make(_ stub: StubSubmitter, queue: OfflineQueue, onSettled: SettledHandler? = nil) -> LessonSubmitter {
        LessonSubmitter(queue: queue, flusher: QueueFlusher(queue: queue, submitter: stub, onSettled: onSettled))
    }

    private func session(_ id: String) -> SubmittedSession {
        SubmittedSession(
            submissionId: id, courseCode: "fa", unitKey: "u1", skillKey: "s1", courseVersion: 3,
            occurredAt: Date(timeIntervalSince1970: 1_789_466_400), completed: true, items: [])
    }

    func testSuccessReturnsResultAndLeavesQueueEmpty() async throws {
        let queue = OfflineQueue(storage: InMemoryOfflineQueueStorage())
        let submitter = make(StubSubmitter { processed($0) }, queue: queue)
        let result = try await submitter.submit(userId: user, session: session("a"))
        guard case .submitted(let response) = result else { return XCTFail("\(result)") }
        XCTAssertEqual(response.submissionId, "a")
        let queued = try await queue.loadQueue(userId: user)
        XCTAssertTrue(queued.isEmpty)
    }

    func testSessionIsOnDiskBeforeTheRequestIsSent() async throws {
        let queue = OfflineQueue(storage: InMemoryOfflineQueueStorage())
        let seen = LockedBox<[String]>([])
        let probe = ProbeSubmitter { [user] in
            // Simulates the app dying mid-request: what is persisted right now.
            seen.set(try await queue.loadQueue(userId: user).map { $0.submissionId })
        }
        let submitter = LessonSubmitter(queue: queue, flusher: QueueFlusher(queue: queue, submitter: probe))
        let result = try await submitter.submit(userId: user, session: session("a"))
        XCTAssertEqual(result, .queued)
        XCTAssertEqual(seen.get(), ["a"])
    }

    func testNetworkFailureQueues() async throws {
        let queue = OfflineQueue(storage: InMemoryOfflineQueueStorage())
        let stub = StubSubmitter { _ in throw URLError(.notConnectedToInternet) }
        let result = try await make(stub, queue: queue).submit(userId: user, session: session("a"))
        XCTAssertEqual(result, .queued)
        let queued = try await queue.loadQueue(userId: user)
        XCTAssertEqual(queued.map { $0.submissionId }, ["a"])
    }

    func testServerErrorsAndThrottleQueue() async throws {
        for status in [500, 503, 408, 429] {
            let queue = OfflineQueue(storage: InMemoryOfflineQueueStorage())
            let stub = StubSubmitter { _ in throw ApiError(status: status, body: nil) }
            let result = try await make(stub, queue: queue).submit(userId: user, session: session("a"))
            XCTAssertEqual(result, .queued, "status \(status)")
            let count = try await queue.unsentCount(userId: user)
            XCTAssertEqual(count, 1, "status \(status)")
        }
    }

    func testOther4xxKeepsTheSessionQueuedAsPermanentFailure() async throws {
        for status in [400, 401, 403, 404, 413, 422] {
            let queue = OfflineQueue(storage: InMemoryOfflineQueueStorage())
            let stub = StubSubmitter { _ in throw ApiError(status: status, body: nil) }
            let result = try await make(stub, queue: queue).submit(userId: user, session: session("a"))
            XCTAssertEqual(result, .queuedPermanentFailure(status: status, message: "HTTP \(status)"), "status \(status)")
            let queued = try await queue.loadQueue(userId: user)
            XCTAssertEqual(queued.map { $0.submissionId }, ["a"], "status \(status)")
        }
    }

    func testRejectedOutcomeStaysQueuedFlaggedRejected() async throws {
        let queue = OfflineQueue(storage: InMemoryOfflineQueueStorage())
        let stub = StubSubmitter { sessions in
            SubmitSessionsResponse(sessions: sessions.map {
                SubmittedSessionResponse(submissionId: $0.submissionId, outcome: .rejected, rejectionReason: "stale", cards: [])
            })
        }
        let result = try await make(stub, queue: queue).submit(userId: user, session: session("a"))
        XCTAssertEqual(result, .rejected(reason: "stale"))
        let records = try await queue.records(userId: user)
        XCTAssertEqual(records.map { $0.submissionId }, ["a"])
        XCTAssertEqual(records.first?.rejectionReason, "stale")
        let unsent = try await queue.unsentCount(userId: user)
        XCTAssertEqual(unsent, 0)
    }

    func testMissingFromResponseStaysQueued() async throws {
        let queue = OfflineQueue(storage: InMemoryOfflineQueueStorage())
        let stub = StubSubmitter { _ in SubmitSessionsResponse(sessions: []) }
        let result = try await make(stub, queue: queue).submit(userId: user, session: session("a"))
        XCTAssertEqual(result, .queued)
        let count = try await queue.unsentCount(userId: user)
        XCTAssertEqual(count, 1)
    }

    func testSettledHandlerRunsForTheSubmittedSession() async throws {
        let queue = OfflineQueue(storage: InMemoryOfflineQueueStorage())
        let handled = LockedBox<[String]>([])
        let handler: SettledHandler = { _, results in handled.set(results.map { $0.submissionId }) }
        let result = try await make(StubSubmitter { processed($0) }, queue: queue, onSettled: handler)
            .submit(userId: user, session: session("a"))
        guard case .submitted = result else { return XCTFail("\(result)") }
        XCTAssertEqual(handled.get(), ["a"])
    }

    func testOlderEntriesAreSentFirstInOneBatch() async throws {
        let queue = OfflineQueue(storage: InMemoryOfflineQueueStorage())
        try await queue.enqueue(userId: user, session: session("old"))
        let stub = StubSubmitter { processed($0) }
        let result = try await make(stub, queue: queue).submit(userId: user, session: session("new"))
        guard case .submitted = result else { return XCTFail("\(result)") }
        XCTAssertEqual(stub.calls, [["old", "new"]])
        let queued = try await queue.loadQueue(userId: user)
        XCTAssertTrue(queued.isEmpty)
    }

    func testRetryOfQueuedSessionLeavesNoDuplicate() async throws {
        let queue = OfflineQueue(storage: InMemoryOfflineQueueStorage())
        let fail = LockedBox<Bool>(true)
        let stub = StubSubmitter { sessions in
            if fail.get() { throw URLError(.timedOut) }
            return processed(sessions)
        }
        let submitter = make(stub, queue: queue)
        let first = try await submitter.submit(userId: user, session: session("a"))
        XCTAssertEqual(first, .queued)
        fail.set(false)
        let second = try await submitter.submit(userId: user, session: session("a"))
        guard case .submitted = second else { return XCTFail("\(second)") }
        let queued = try await queue.loadQueue(userId: user)
        XCTAssertTrue(queued.isEmpty)
    }
}

private final class LockedBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: T
    init(_ value: T) { self.value = value }
    func get() -> T { lock.lock(); defer { lock.unlock() }; return value }
    func set(_ new: T) { lock.lock(); value = new; lock.unlock() }
}

private struct ProbeSubmitter: SessionSubmitting {
    let onSubmit: @Sendable () async throws -> Void
    init(_ onSubmit: @escaping @Sendable () async throws -> Void) { self.onSubmit = onSubmit }
    func submit(_ sessions: [SubmittedSession]) async throws -> SubmitSessionsResponse {
        try await onSubmit()
        throw URLError(.networkConnectionLost)
    }
}
