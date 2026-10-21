import SwiftUI
import QData
import QNetwork

/// A queued lesson the server later refused.
public struct RejectedLesson: Equatable, Identifiable, Sendable {
    public var id: String
    public var reason: String

    public init(id: String, reason: String) {
        self.id = id
        self.reason = reason
    }
}

/// Where the banner reads a user's rejected lessons and dismisses them.
public protocol RejectionSource: Sendable {
    func rejected() async -> [RejectedLesson]
    func dismiss(_ ids: [String]) async
    /// Fires after the queue changes; nil when the source can't tell.
    func changes() async -> AsyncStream<Void>?
}

extension RejectionSource {
    public func changes() async -> AsyncStream<Void>? { nil }
}

/// Reads the signed-in user's rejected sessions from the offline queue.
public struct QueueRejectionSource: RejectionSource {
    private let queue: OfflineQueue
    private let userId: @Sendable () async -> String?

    public init(queue: OfflineQueue, userId: @escaping @Sendable () async -> String?) {
        self.queue = queue
        self.userId = userId
    }

    public func rejected() async -> [RejectedLesson] {
        guard let user = await userId(), let records = try? await queue.rejectedRecords(userId: user) else { return [] }
        return records.map { RejectedLesson(id: $0.submissionId, reason: $0.rejectionReason ?? "") }
    }

    public func dismiss(_ ids: [String]) async {
        guard let user = await userId() else { return }
        try? await queue.dismissRejected(userId: user, submissionIds: ids)
    }

    public func changes() async -> AsyncStream<Void>? { await queue.changes() }
}

/// The dismissible banner for lessons finished offline and refused later.
@MainActor
public final class RejectionBannerModel: ObservableObject {
    public static let message = "A Parsle you finished offline wasn't saved, so it won't count toward your review schedule."

    @Published public private(set) var items: [RejectedLesson] = []
    private let source: RejectionSource?

    public init(source: RejectionSource?) {
        self.source = source
    }

    public var isVisible: Bool { !items.isEmpty }
    /// The server's reason for the oldest refused lesson.
    public var reason: String? { items.first(where: { !$0.reason.isEmpty })?.reason }

    public func refresh() async {
        guard let source = source else { return }
        items = await source.rejected()
    }

    /// Follows the queue so a rejection found by a background flush appears without a restart.
    public func watch() async {
        guard let source = source else { return }
        await refresh()
        guard let changes = await source.changes() else { return }
        for await _ in changes { await refresh() }
    }

    public func dismiss() async {
        guard let source = source else { return }
        let ids = items.map { $0.id }
        items = []
        await source.dismiss(ids)
    }
}

public struct RejectionBannerView: View {
    @ObservedObject private var model: RejectionBannerModel

    public init(model: RejectionBannerModel) {
        self.model = model
    }

    public var body: some View {
        if model.isVisible {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(RejectionBannerModel.message)
                    if let reason = model.reason {
                        Text(reason).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                Button("Dismiss") { Task { await model.dismiss() } }
                    .accessibilityHint("Removes this notice")
            }
            .padding(12)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 16)
            .accessibilityElement(children: .contain)
        }
    }
}
