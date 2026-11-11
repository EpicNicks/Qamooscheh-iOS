import Foundation
import QDomain
import QData

/// Hands a finished read to the reading-completion queue: written first, then sent at once. A network failure or 5xx
/// leaves it queued for a later flush; a definitive refusal drops it. The caller neither waits nor sees failures.
public final class QueuedStoryReaderCompletionSubmitter: StoryReaderCompletionSubmitting, @unchecked Sendable {
    private let queue: ReadingCompletionQueue
    private let userId: @Sendable () async -> String?

    public init(queue: ReadingCompletionQueue, userId: @escaping @Sendable () async -> String?) {
        self.queue = queue
        self.userId = userId
    }

    public func submitCompletion(_ request: StoryReaderCompletionRequest) {
        Task { await self.submit(request) }
    }

    /// Enqueues then flushes every pending completion for the signed-in user. Without a user nothing is sent.
    func submit(_ request: StoryReaderCompletionRequest) async {
        guard let uid = await userId(), !uid.isEmpty else { return }
        do {
            try await queue.enqueue(userId: uid, submissionId: request.submissionId, request: QueuedStoryReaderCompletionSubmitter.wire(request))
            _ = try await queue.flush(userId: uid, ignoreBackoff: true)
        } catch {
            // Saved or not, the next flush retries; the reader has nothing to show for it.
        }
    }

    /// Sends whatever an earlier run left queued (app start, Stow, opening a reader). Failures stay queued.
    /// `ignoreBackoff` is true when the app just became active: the learner is back, so try now.
    public func flushPending(ignoreBackoff: Bool = false) async {
        guard let uid = await userId(), !uid.isEmpty else { return }
        _ = try? await queue.flush(userId: uid, ignoreBackoff: ignoreBackoff)
    }

    /// The wire body: an empty unit key is sent as absent, which the server resolves course-wide.
    static func wire(_ request: StoryReaderCompletionRequest) -> ReadingCompletionRequest {
        ReadingCompletionRequest(
            courseCode: request.courseCode, unitKey: request.unitKey.isEmpty ? nil : request.unitKey,
            skillKey: request.skillKey, occurredAt: request.occurredAt)
    }
}

/// Tells the Learn tab to reload its path after the server recorded a story completion, like `LessonSubmitRefresh`.
public enum ReaderCompletionRefresh {
    public static let notification = Notification.Name("QamooschehReaderCompletionRecorded")

    /// Posts `notification` on the main thread.
    public static func announce(center: NotificationCenter = .default) {
        DispatchQueue.main.async {
            center.post(name: notification, object: nil)
        }
    }
}
