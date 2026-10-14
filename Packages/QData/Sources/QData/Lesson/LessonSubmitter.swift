import Foundation
import QModel
import QNetwork

/// What happened to a completed session handed to `LessonSubmitter`.
public enum LessonSubmitResult: Equatable, Sendable {
    /// The server answered for this session (processed or already processed).
    case submitted(SubmittedSessionResponse)
    /// Saved in the offline queue; a later flush delivers it (network, 5xx, 408, 429,
    /// unusable response, or still backing off).
    case queued
    /// The server refused the whole request with another 4xx (401, 403, 404, 413...).
    /// The session stays queued and is not retried automatically (Android worker
    /// `Result.failure`); a later manual flush or sign-in may deliver it.
    case queuedPermanentFailure(status: Int, message: String)
    /// The server answered with a rejected outcome. The session stays in the queue,
    /// flagged rejected, and is never retried.
    case rejected(reason: String?)
}

/// Submit-or-queue for a finished lesson session. Takes the already-built
/// `SubmittedSession` (no dependency on the lesson engine).
///
/// Android order: the session is written to the queue FIRST (so a kill mid-request
/// loses nothing), then the shared `QueueFlusher` sends every unsent item oldest
/// first in one single-flight batch. The flusher runs the `SettledHandler`
/// (cards merge, cache refresh) and removes settled items, so nothing is ever dropped.
public struct LessonSubmitter: Sendable {
    private let queue: OfflineQueue
    private let flusher: QueueFlusher

    public init(queue: OfflineQueue, flusher: QueueFlusher) {
        self.queue = queue
        self.flusher = flusher
    }

    /// Throws only when the session could not be persisted, or the flush hit
    /// `OfflineQueueError.undecodableEntries` / a storage error (the session is
    /// already saved in that case).
    public func submit(userId: String, session: SubmittedSession) async throws -> LessonSubmitResult {
        try await queue.enqueue(userId: userId, session: session)
        let report = try await flusher.flush(userId: userId, reason: .enqueued)
        let id = session.submissionId
        if let result = report.results.first(where: { $0.submissionId == id }) {
            if report.rejected.contains(id) {
                return .rejected(reason: result.rejectionReason)
            }
            if report.settled.contains(id) {
                return .submitted(result)
            }
        }
        if case .permanentFailure(let status, let message) = report.outcome {
            return .queuedPermanentFailure(status: status, message: message)
        }
        return .queued
    }
}
