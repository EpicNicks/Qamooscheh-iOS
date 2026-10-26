import Foundation
import QData

/// Sends the signed-in user's queued lesson results before a stow (stow-online-only). Failures stay
/// queued; the stow call itself then reports whether the server is reachable.
public struct QueueFlusherStowAdapter: StowQueueFlushing {
    private let provider: QueueFlusherProvider
    private let userId: String

    public init(provider: QueueFlusherProvider, userId: String) {
        self.provider = provider
        self.userId = userId
    }

    public func flushQueue() async {
        let flusher = await provider.flusher(for: userId)
        _ = try? await flusher.flush(userId: userId, reason: .manual)
    }
}
