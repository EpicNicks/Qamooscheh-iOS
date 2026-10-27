import Foundation
import QModel
import QNetwork
import QData

/// The one offline queue, flusher and submitter of the app. The lesson pipeline and the Stow flow both go through it, so
/// their flushes are single-flight on the same flusher and a queued session is never sent twice.
public struct SharedOfflineQueue: Sendable {
    public let queue: OfflineQueue
    public let flusher: QueueFlusher
    public let submitter: LessonSubmitter

    public init(queue: OfflineQueue, flusher: QueueFlusher) {
        self.queue = queue
        self.flusher = flusher
        self.submitter = LessonSubmitter(queue: queue, flusher: flusher)
    }

    /// The production queue on `baseURL`, kept under Application Support/offline-queue (where lessons always queued),
    /// merging the server's cards into the device's card store as each batch settles.
    public static func live(baseURL: URL, clientHeader: String, store: SessionStore) -> SharedOfflineQueue {
        let client = ApiClient(baseURL: baseURL, clientHeader: clientHeader, store: store)
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let queue = OfflineQueue(storage: FileOfflineQueueStorage(
            directory: support.appendingPathComponent("offline-queue", isDirectory: true)))
        let cards = CardStateStore(store: FileContentStore(root: support.appendingPathComponent("content", isDirectory: true)))
        let flusher = QueueFlusher(queue: queue, submitter: LessonRepository(client: client), onSettled: { userId, results in
            _ = try? await cards.merge(userId: userId, cards: results.flatMap { $0.cards })
        })
        return SharedOfflineQueue(queue: queue, flusher: flusher)
    }

    /// Sends the user's queued results (the Stow flow runs this before it stows). Failures stay queued.
    public var flush: @Sendable (String) async -> Void {
        let flusher = self.flusher
        return { userId in _ = try? await flusher.flush(userId: userId, reason: .manual) }
    }

    /// Points the lesson environment's submit, write-ahead and rejection handling at this queue instead of the one
    /// `LessonEnvironment.live` built for itself (which is then never used).
    public func install(into environment: inout LessonEnvironment) {
        let queue = self.queue
        let submitter = self.submitter
        let userId = environment.userId
        environment.submit = { user, session in try await submitter.submit(userId: user, session: session) }
        environment.enqueue = { user, session in _ = try await queue.enqueue(userId: user, session: session) }
        environment.dismissRejections = { user, ids in try? await queue.dismissRejected(userId: user, submissionIds: ids) }
        environment.rejections = QueueRejectionSource(queue: queue, userId: userId)
    }
}
