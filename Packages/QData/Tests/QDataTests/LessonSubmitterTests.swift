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

    private func session(_ id: String) -> SubmittedSession {
        SubmittedSession(
            submissionId: id, courseCode: "fa", unitKey: "u1", skillKey: "s1", courseVersion: 3,
            occurredAt: Date(timeIntervalSince1970: 1_789_466_400), completed: true, items: [])
    }

    func testSuccessReturnsResultAndLeavesQueueEmpty() async throws {
        let queue = OfflineQueue(storage: InMemoryOfflineQueueStorage())
        let stub = StubSubmitter { processed($0) }
        let submitter = LessonSubmitter(submitter: stub, queue: queue)
        let result = try await submitter.submit(userId: user, session: session("a"))
        guard case .submitted(let response) = result else { return XCTFail("\(result)") }
        XCTAssertEqual(response.submissionId, "a")
        let queued = try await queue.loadQueue(userId: user)
        XCTAssertTrue(queued.isEmpty)
    }

    func testNetworkFailureQueues() async throws {
        let queue = OfflineQueue(storage: InMemoryOfflineQueueStorage())
        let stub = StubSubmitter { _ in throw URLError(.notConnectedToInternet) }
        let submitter = LessonSubmitter(submitter: stub, queue: queue)
        let result = try await submitter.submit(userId: user, session: session("a"))
        XCTAssertEqual(result, .queued)
        let queued = try await queue.loadQueue(userId: user)
        XCTAssertEqual(queued.map { $0.submissionId }, ["a"])
    }

    func testServerErrorsAndThrottleQueue() async throws {
        for status in [500, 503, 408, 429] {
            let queue = OfflineQueue(storage: InMemoryOfflineQueueStorage())
            let stub = StubSubmitter { _ in throw ApiError(status: status, body: nil) }
            let submitter = LessonSubmitter(submitter: stub, queue: queue)
            let result = try await submitter.submit(userId: user, session: session("a"))
            XCTAssertEqual(result, .queued, "status \(status)")
            let count = try await queue.unsentCount(userId: user)
            XCTAssertEqual(count, 1, "status \(status)")
        }
    }

    func testValidationFailureIsRejectedAndNeverQueued() async throws {
        let queue = OfflineQueue(storage: InMemoryOfflineQueueStorage())
        let stub = StubSubmitter { _ in throw ApiError(status: 422, body: ApiErrorBody(error: "bad", reason: "invalid")) }
        let submitter = LessonSubmitter(submitter: stub, queue: queue)
        let result = try await submitter.submit(userId: user, session: session("a"))
        XCTAssertEqual(result, .rejected(status: 422, reason: "invalid"))
        let count = try await queue.unsentCount(userId: user)
        XCTAssertEqual(count, 0)
    }

    func testRejectedOutcomeIsNotQueued() async throws {
        let queue = OfflineQueue(storage: InMemoryOfflineQueueStorage())
        let stub = StubSubmitter { sessions in
            SubmitSessionsResponse(sessions: sessions.map {
                SubmittedSessionResponse(submissionId: $0.submissionId, outcome: .rejected, rejectionReason: "stale", cards: [])
            })
        }
        let submitter = LessonSubmitter(submitter: stub, queue: queue)
        let result = try await submitter.submit(userId: user, session: session("a"))
        XCTAssertEqual(result, .rejected(status: nil, reason: "stale"))
        let count = try await queue.unsentCount(userId: user)
        XCTAssertEqual(count, 0)
    }

    func testMissingFromResponseQueues() async throws {
        let queue = OfflineQueue(storage: InMemoryOfflineQueueStorage())
        let stub = StubSubmitter { _ in SubmitSessionsResponse(sessions: []) }
        let submitter = LessonSubmitter(submitter: stub, queue: queue)
        let result = try await submitter.submit(userId: user, session: session("a"))
        XCTAssertEqual(result, .queued)
    }

    func testSuccessFlushesOlderEntries() async throws {
        let queue = OfflineQueue(storage: InMemoryOfflineQueueStorage())
        try await queue.enqueue(userId: user, session: session("old"))
        let stub = StubSubmitter { processed($0) }
        let flusher = QueueFlusher(queue: queue, submitter: stub)
        let submitter = LessonSubmitter(submitter: stub, queue: queue, flusher: flusher)
        let result = try await submitter.submit(userId: user, session: session("new"))
        guard case .submitted = result else { return XCTFail("\(result)") }
        XCTAssertEqual(stub.calls, [["new"], ["old"]])
        let queued = try await queue.loadQueue(userId: user)
        XCTAssertTrue(queued.isEmpty)
    }

    func testQueuedResultDoesNotFlush() async throws {
        let queue = OfflineQueue(storage: InMemoryOfflineQueueStorage())
        let stub = StubSubmitter { _ in throw URLError(.timedOut) }
        let flusher = QueueFlusher(queue: queue, submitter: stub)
        let submitter = LessonSubmitter(submitter: stub, queue: queue, flusher: flusher)
        _ = try await submitter.submit(userId: user, session: session("a"))
        XCTAssertEqual(stub.calls, [["a"]])
    }
}
