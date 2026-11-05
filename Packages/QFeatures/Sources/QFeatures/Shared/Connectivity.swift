import Foundation
import SwiftUI

/// Where the device's connection state comes from: `true` while online, a new value on every change.
public protocol ConnectivitySource: Sendable {
    func updates() -> AsyncStream<Bool>
}

/// Whether the device is online, for the offline strip (ledger `offline-strip-everywhere`).
/// Optimistic until the source reports, so a launch never flashes the strip.
@MainActor
public final class ConnectivityModel: ObservableObject {
    /// Ledger `offline-strip-everywhere`.
    public static let message = "You're offline. Finished Parsles sync when you're back."

    @Published public private(set) var isOnline = true
    private let source: ConnectivitySource?

    public init(source: ConnectivitySource?) {
        self.source = source
    }

    public var showsStrip: Bool { !isOnline }

    /// Follows the source until cancelled.
    public func watch() async {
        guard let source = source else { return }
        for await online in source.updates() {
            if online != isOnline { isOnline = online }
        }
    }
}

public extension ConnectivityModel {
    /// A model fixed at `online`, for previews and snapshots.
    static func fixed(online: Bool) -> ConnectivityModel {
        let model = ConnectivityModel(source: nil)
        model.isOnline = online
        return model
    }
}

/// The slim strip that says the device is offline. Pinned to the bottom of every screen, lessons included.
public struct OfflineStrip: View {
    @ObservedObject private var model: ConnectivityModel

    public init(model: ConnectivityModel) {
        self.model = model
    }

    public var body: some View {
        if model.showsStrip {
            Text(ConnectivityModel.message)
                .font(.footnote.weight(.semibold))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .padding(.horizontal, 16)
                .background(.regularMaterial)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isStaticText)
        }
    }
}

public extension View {
    /// Pins the offline strip under this view, above the home indicator.
    func offlineStrip(_ model: ConnectivityModel?) -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) {
            if let model = model { OfflineStrip(model: model) }
        }
    }
}

#if canImport(Network)
import Network

/// NWPathMonitor, rechecked on every system change and every `recheck` seconds (ledger `offline-strip-everywhere`).
/// A path is online only when it is satisfied; a satisfied path with no reachable internet is not detected here.
public struct NetworkPathSource: ConnectivitySource {
    private let recheck: TimeInterval

    public init(recheck: TimeInterval = 15) {
        self.recheck = recheck
    }

    public func updates() -> AsyncStream<Bool> {
        let interval = recheck
        return AsyncStream { continuation in
            let monitor = NWPathMonitor()
            monitor.pathUpdateHandler = { continuation.yield($0.status == .satisfied) }
            monitor.start(queue: DispatchQueue(label: "connectivity"))
            let timer = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                    continuation.yield(monitor.currentPath.status == .satisfied)
                }
            }
            continuation.onTermination = { _ in
                timer.cancel()
                monitor.cancel()
            }
        }
    }
}
#endif
