import Foundation
import QModel
import QNetwork

/// What happened to a completed session handed to `LessonSubmitter`.
public enum LessonSubmitResult: Equatable, Sendable {
    /// The server answered for this session (processed or already processed).
    case submitted(SubmittedSessionResponse)
    /// Network, 5xx, 408, 429 or an unusable response: saved in the offline queue for a later flush.
    case queued
    /// The server refused the session (4xx, or a rejected outcome). Never queued.
    case rejected(status: Int?, reason: String?)
}

/// Submit-or-queue for a finished lesson session. Takes the already-built
/// `SubmittedSession` (no dependency on the lesson engine). Retry
/// classification matches `QueueFlusher.classify` (Android worker): a 4xx other
/// than 408/429 is a refusal; every other failure is queued.
public struct LessonSubmitter: Sendable {
    private let submitter: SessionSubmitting
    private let queue: OfflineQueue
    private let flusher: QueueFlusher?

    /// `flusher` (sharing `queue`) is asked to drain older entries after a success.
    public init(submitter: SessionSubmitting, queue: OfflineQueue, flusher: QueueFlusher? = nil) {
        self.submitter = submitter
        self.queue = queue
        self.flusher = flusher
    }

    public func submit(userId: String, session: SubmittedSession) async throws -> LessonSubmitResult {
        let response: SubmitSessionsResponse
        do {
            response = try await submitter.submit([session])
        } catch {
            if let api = error as? ApiError, LessonSubmitter.isRefusal(api.status) {
                return .rejected(status: api.status, reason: api.body?.reason ?? api.body?.error)
            }
            try await queue.enqueue(userId: userId, session: session)
            return .queued
        }

        guard let result = response.sessions.first(where: { $0.submissionId == session.submissionId }) else {
            try await queue.enqueue(userId: userId, session: session)
            return .queued
        }
        if result.outcome == .rejected {
            return .rejected(status: nil, reason: result.rejectionReason)
        }
        if let flusher = flusher {
            _ = try? await flusher.flush(userId: userId, reason: .enqueued)
        }
        return .submitted(result)
    }

    static func isRefusal(_ status: Int) -> Bool {
        (400...499).contains(status) && status != 408 && status != 429
    }
}
