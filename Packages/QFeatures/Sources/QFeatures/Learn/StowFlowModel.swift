import Foundation
import Combine
import QModel
import QNetwork

/// What the Stow flow talks to. `StowApi` is the production conformer.
public protocol StowService: Sendable {
    func stow(lessonKey: String) async throws -> StowResponse
    func snoozeStowage() async throws -> StowageResponse
    func muteStowage() async throws -> StowageResponse
}

extension StowApi: StowService {}

/// Sends queued lesson results before a stow (stow-online-only). The app wires this to `QueueFlusher`.
public protocol StowQueueFlushing: Sendable {
    func flushQueue() async
}

/// Where the Stowage and cursor live. `PathModel` is the production conformer.
@MainActor
public protocol StowStateHost: AnyObject {
    var stowage: [StowageUnit] { get }
    func applyStowage(_ stowage: [StowageUnit], position: PositionRef?)
}

/// Where the Stow dialogs are: the confirmation, then the popup for each answer.
public enum StowStep: Equatable, Sendable {
    case confirm
    /// Stowed: encouraging popup with Continue.
    case encouraged
    /// Declined: "You got this!" with Close and Retry Lesson.
    case declined
}

/// The Stow flow for one tapped lesson.
public struct StowFlowState: Equatable, Sendable {
    public var lessonKey: String
    public var step: StowStep = .confirm
    public var busy = false
    public var error: String?

    public init(lessonKey: String) {
        self.lessonKey = lessonKey
    }
}

/// The Stow dialogs (stow-dialogs) and the call behind them (stow-online-only). SwiftUI-free.
@MainActor
public final class StowFlowModel: ObservableObject {
    @Published public private(set) var flow: StowFlowState?

    private let service: StowService
    private let flusher: StowQueueFlushing
    private let host: StowStateHost
    private let refresh: () async -> Void

    /// `refresh` re-reads the bootstrap (which lessons are stowable now is the server's to say).
    public init(service: StowService, flusher: StowQueueFlushing, host: StowStateHost, refresh: @escaping () async -> Void = {}) {
        self.service = service
        self.flusher = flusher
        self.host = host
        self.refresh = refresh
    }

    public var busy: Bool { flow?.busy ?? false }
    public var error: String? { flow?.error }

    /// Stow was tapped on a lesson: open the confirmation.
    public func request(lessonKey: String) {
        flow = StowFlowState(lessonKey: lessonKey)
    }

    /// Confirm: queued results go first, then the server decides. `applied: false` (a repeat) is success.
    public func confirm() async {
        guard var current = flow, current.step == .confirm, !current.busy else { return }
        let key = current.lessonKey
        current.busy = true
        current.error = nil
        flow = current

        await flusher.flushQueue()
        do {
            let response = try await service.stow(lessonKey: key)
            host.applyStowage(response.stowage, position: response.position)
            await refresh()
            finish { $0.step = .encouraged }
        } catch {
            if StowCopy.staleState(error) { await refresh() }
            let message = StowCopy.message(for: error)
            finish { $0.error = message }
        }
    }

    /// "Not now" on the confirmation: nothing was stowed.
    public func decline() {
        guard var current = flow, current.step == .confirm, !current.busy else { return }
        current.step = .declined
        current.error = nil
        flow = current
    }

    /// Close, or Continue: the dialogs are done.
    public func dismiss() {
        flow = nil
    }

    /// Retry Lesson: closes the dialogs and returns the key of the tapped lesson for the caller to start.
    public func retryLesson() -> String? {
        guard let current = flow, current.step == .declined else { return nil }
        flow = nil
        return current.lessonKey
    }

    private func finish(_ change: (inout StowFlowState) -> Void) {
        guard var current = flow else { return }
        current.busy = false
        change(&current)
        flow = current
    }
}
