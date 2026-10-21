import SwiftUI
import QData
import QDomain

/// What the re-enable prompt remembers for one learner: when they turned reminders off, when to ask again, and
/// whether they said "don't ask again". Kept per user, on this device only.
public final class ReenablePromptStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let lock = NSLock()

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public struct State: Codable, Equatable, Sendable {
        public var disabledAt: Int64?
        public var nextAskAt: Int64?
        public var neverAsk = false
        public init() {}
    }

    public func state(userId: String) -> State {
        lock.lock()
        defer { lock.unlock() }
        return read(userId)
    }

    /// Reminders were just turned off: start the day's wait, and ask afresh even after an earlier "tomorrow".
    public func recordDisabled(userId: String, nowMillis: Int64) {
        update(userId) {
            $0.disabledAt = nowMillis
            $0.nextAskAt = nil
        }
    }

    /// Reminders are on again: nothing to ask about. A "don't ask again" survives, so turning them off later stays quiet.
    public func recordEnabled(userId: String) {
        update(userId) {
            $0.disabledAt = nil
            $0.nextAskAt = nil
        }
    }

    public func postpone(userId: String, nowMillis: Int64) {
        update(userId) { $0.nextAskAt = nextReenableAsk(nowMillis: nowMillis) }
    }

    public func neverAskAgain(userId: String) {
        update(userId) { $0.neverAsk = true }
    }

    /// Sign-out cleanup.
    public func clear(userId: String) {
        lock.lock()
        defer { lock.unlock() }
        defaults.removeObject(forKey: key(userId))
    }

    private func update(_ userId: String, _ change: (inout State) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        var next = read(userId)
        change(&next)
        if let data = try? JSONEncoder().encode(next) { defaults.set(data, forKey: key(userId)) }
    }

    private func read(_ userId: String) -> State {
        guard let data = defaults.data(forKey: key(userId)),
              let stored = try? JSONDecoder().decode(State.self, from: data) else { return State() }
        return stored
    }

    private func key(_ userId: String) -> String { "reminders.reenable.\(userId)" }
}

/// Asks "Want daily reminders back on?" a day after the learner turned them off (Android's re-enable prompt).
@MainActor
public final class ReenablePromptModel: ObservableObject {
    public enum Outcome: Equatable, Sendable {
        case turnedOn
        /// Notifications are blocked for the app, so only Settings can turn them back on.
        case needsSettings
        /// The learner declined the system permission prompt.
        case declined
    }

    @Published public private(set) var isPresented = false

    private let userId: String
    private let service: ReminderService
    private let localStore: LocalPrefsStore
    private let store: ReenablePromptStore
    private let now: @Sendable () -> Date

    public init(
        userId: String,
        service: ReminderService,
        localStore: LocalPrefsStore = LocalPrefsStore(),
        store: ReenablePromptStore = ReenablePromptStore(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.userId = userId
        self.service = service
        self.localStore = localStore
        self.store = store
        self.now = now
    }

    private var nowMillis: Int64 { Int64(now().timeIntervalSince1970 * 1000) }

    /// Decides whether to ask now. Call when the app opens or comes back.
    public func check() {
        let state = store.state(userId: userId)
        isPresented = reenablePromptDue(
            enabled: localStore.current(userId: userId).reminderEnabled,
            disabledAt: state.disabledAt, nextAskAt: state.nextAskAt, neverAsk: state.neverAsk, nowMillis: nowMillis)
    }

    /// "Turn on". Asks for notification permission if it was never asked; when it was refused earlier, the caller
    /// sends the learner to Settings, so ask again tomorrow in case they don't come back with it enabled.
    @discardableResult
    public func turnOn() async -> Outcome {
        isPresented = false
        switch await service.authorization() {
        case .denied:
            store.postpone(userId: userId, nowMillis: nowMillis)
            return .needsSettings
        case .notDetermined:
            let granted = await service.requestPermission()
            if !granted {
                store.postpone(userId: userId, nowMillis: nowMillis)
                return .declined
            }
        case .granted:
            break
        }
        let prefs = localStore.update(userId: userId) { $0.reminderEnabled = true }
        var settings = service.settings(userId: userId)
        settings.enabled = true
        settings.hour = prefs.reminderHour
        settings.minute = prefs.reminderMinute
        await service.apply(settings, userId: userId)
        store.recordEnabled(userId: userId)
        return .turnedOn
    }

    /// "Tomorrow".
    public func askTomorrow() {
        isPresented = false
        store.postpone(userId: userId, nowMillis: nowMillis)
    }

    /// "Don't ask again".
    public func dontAskAgain() {
        isPresented = false
        store.neverAskAgain(userId: userId)
    }

    public func dismiss() { isPresented = false }
}

/// Shows the re-enable prompt over `content` for the signed-in learner.
public struct ReenablePromptHost<Content: View>: View {
    private let app: AppEnvironment?
    private let content: Content
    @StateObject private var holder = Holder()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    @MainActor
    final class Holder: ObservableObject {
        @Published var model: ReenablePromptModel?
        var userId: String?
    }

    public init(app: AppEnvironment?, @ViewBuilder content: () -> Content) {
        self.app = app
        self.content = content()
    }

    public var body: some View {
        content
            .task { await prepare() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await prepare() } }
            }
            .alert(
                "Turn daily reminders back on?",
                isPresented: Binding(
                    get: { holder.model?.isPresented ?? false },
                    set: { if !$0 { holder.model?.dismiss() } })
            ) {
                Button("Turn on") { run { await $0.turnOn() } }
                Button("Tomorrow") { holder.model?.askTomorrow() }
                Button("Don't ask again", role: .destructive) { holder.model?.dontAskAgain() }
            } message: {
                Text("A short reminder each day helps keep your streak going. You can change the time in Settings.")
            }
    }

    /// Builds the model for whoever is signed in (a different learner after sign-in gets their own), then checks.
    private func prepare() async {
        guard let app = app, let service = app.reminders, let uid = await app.currentUserId(), !uid.isEmpty else {
            holder.model = nil
            holder.userId = nil
            return
        }
        if holder.userId != uid {
            holder.userId = uid
            holder.model = ReenablePromptModel(userId: uid, service: service)
        }
        holder.model?.check()
    }

    private func run(_ action: @escaping @MainActor (ReenablePromptModel) async -> ReenablePromptModel.Outcome) {
        guard let model = holder.model else { return }
        Task { @MainActor in
            if await action(model) == .needsSettings, let url = ReminderSettingsLink.url { openURL(url) }
        }
    }
}
