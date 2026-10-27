import XCTest
import QModel
import QNetwork
import QData
@testable import QFeatures

private final class CountingSubmitter: SessionSubmitting, @unchecked Sendable {
    private let lock = NSLock()
    private var ids: [String] = []
    var submitted: [String] { lock.lock(); defer { lock.unlock() }; return ids }
    func submit(_ sessions: [SubmittedSession]) async throws -> SubmitSessionsResponse {
        lock.lock(); ids.append(contentsOf: sessions.map { $0.submissionId }); lock.unlock()
        try await Task.sleep(nanoseconds: 20_000_000)
        return SubmitSessionsResponse(sessions: sessions.map {
            SubmittedSessionResponse(submissionId: $0.submissionId, outcome: .processed, cards: [])
        })
    }
}

final class SharedOfflineQueueTests: XCTestCase {
    private func session(_ id: String) -> SubmittedSession {
        SubmittedSession(
            submissionId: id, courseCode: "fa", unitKey: "u1", skillKey: "s1", courseVersion: 3,
            occurredAt: Date(timeIntervalSince1970: 1_789_466_400), completed: true, items: [])
    }

    func testStowFlushAndLessonSubmitShareOneFlusherSoNothingIsSentTwice() async throws {
        let stub = CountingSubmitter()
        let queue = OfflineQueue(storage: InMemoryOfflineQueueStorage())
        let shared = SharedOfflineQueue(queue: queue, flusher: QueueFlusher(queue: queue, submitter: stub))
        var env = LessonEnvironment(loader: UnwiredLessonSetupLoader(), userId: { "u1" }, submit: { _, _ in .queued })
        shared.install(into: &env)

        try await env.enqueue("u1", session("a"))
        let submit = env.submit
        let flush = shared.flush
        async let stowFlush: Void = flush("u1")
        async let lessonSubmit = submit("u1", session("b"))
        _ = try await lessonSubmit
        await stowFlush
        await flush("u1")

        XCTAssertEqual(stub.submitted.sorted(), ["a", "b"])
        let left = try await queue.loadQueue(userId: "u1")
        XCTAssertTrue(left.isEmpty)
    }
}
