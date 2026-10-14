import Foundation
import Combine
import QModel
import QData
import QDomain

/// State for the Settings screen (web SettingsPage, Android SettingsViewModel).
/// Study/Input/Goals/Audio edit a draft of the server prefs that Save sends through
/// `PrefsSync` (per user and course); the rest write to `LocalPrefsStore` at once.
@MainActor
public final class SettingsModel: ObservableObject {
    @Published public private(set) var form: UpdatePrefsRequest?
    @Published public private(set) var local: LocalPrefs
    @Published public private(set) var reminders: ReminderSettings
    @Published public private(set) var loadError: String?
    @Published public private(set) var saving = false
    /// True while an edit has not reached the server (shown as a badge).
    @Published public private(set) var hasUnsyncedEdit = false
    @Published public private(set) var notice: SettingsNotice?
    /// The Streak section's state; its changes republish through this model.
    public let streakPause: StreakPauseModel
    public var streak: StreakResponse? { streakPause.streak }
    public var pauseBusy: Bool { streakPause.busy }
    public var pauseError: String? { streakPause.error }
    @Published public private(set) var signingOut = false
    @Published public private(set) var signOutError: String?
    @Published public private(set) var previewNotice: String?

    public let courseCode: String
    public let voices: [SettingsVoice]
    /// The signed-in name or email for the Account section; nil hides the line.
    public let accountName: String?
    /// Whether the Account section (Sign out) is shown.
    public var canSignOut: Bool { signOutAction != nil }

    private let userId: String
    private let sync: PrefsSync
    private let localStore: LocalPrefsStore
    private let scheduler: ReminderScheduling
    private var pauseObserver: AnyCancellable?
    private let signOutAction: (() async throws -> Void)?
    private let previewer: VoicePreviewing?
    private var dirty = false

    public init(
        userId: String,
        courseCode: String,
        sync: PrefsSync,
        localStore: LocalPrefsStore,
        scheduler: ReminderScheduling = StubReminderScheduler(),
        streakService: StreakService? = nil,
        voices: [SettingsVoice] = [],
        accountName: String? = nil,
        signOut: (() async throws -> Void)? = nil,
        previewer: VoicePreviewing? = nil
    ) {
        self.userId = userId
        self.courseCode = courseCode
        self.sync = sync
        self.localStore = localStore
        self.scheduler = scheduler
        self.streakPause = StreakPauseModel(service: streakService)
        self.voices = voices
        self.accountName = accountName
        self.signOutAction = signOut
        self.previewer = previewer
        let stored = localStore.current(userId: userId)
        self.local = stored
        var r = scheduler.current()
        r.enabled = stored.reminderEnabled
        r.hour = stored.reminderHour
        r.minute = stored.reminderMinute
        self.reminders = r
        scheduler.apply(r)
        self.pauseObserver = streakPause.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
    }

    /// Loads cached prefs at once, then syncs with the server.
    public func load() async {
        loadError = nil
        if form == nil, let cached = await sync.prefs {
            form = cached.updateRequest
        }
        do {
            let outcome = try await sync.sync()
            switch outcome {
            case .synced(let prefs):
                if !dirty { form = prefs.updateRequest }
            case .offline(let prefs):
                if form == nil, let prefs = prefs { form = prefs.updateRequest }
            case .rejected(_, let prefs):
                if !dirty, let prefs = prefs { form = prefs.updateRequest }
                notice = settingsNotice(for: outcome)
                await sync.dismissRejectedEdit()
            }
        } catch {
            // Falls through to the load error below when nothing is cached.
        }
        if form == nil {
            loadError = "Couldn't load your settings. Check your connection and try again."
        }
        hasUnsyncedEdit = await sync.hasPendingEdit
        await streakPause.load()
    }

    public func edit(_ change: (inout UpdatePrefsRequest) -> Void) {
        guard var next = form else { return }
        change(&next)
        form = next
        dirty = true
        notice = nil
    }

    public func save() async {
        guard let draft = form, !saving else { return }
        saving = true
        notice = nil
        do {
            let outcome = try await sync.update { prefs in
                prefs = PrefsResponse(
                    scriptMode: draft.scriptMode, register: draft.register,
                    autoplayAudio: draft.autoplayAudio, keyboardMode: draft.keyboardMode,
                    desiredRetention: draft.desiredRetention, dailyGoalXp: draft.dailyGoalXp,
                    preferredVoice: draft.preferredVoice)
            }
            if case .rejected = outcome {
                // Keep the draft in the form (like Android) and show the error.
                dirty = true
                notice = settingsNotice(for: outcome)
            } else if form == draft {
                dirty = false
                notice = settingsNotice(for: outcome)
            } else {
                // Edited while the PUT was in flight: stay dirty so the newer
                // edit is neither overwritten by a pull nor reported as saved.
                dirty = true
                notice = nil
            }
        } catch {
            // The edit is already stored pending in PrefsSync and will be retried.
            dirty = true
            notice = .failed("Couldn't reach the server just now. Your changes are kept and will sync later.")
        }
        hasUnsyncedEdit = await sync.hasPendingEdit
        saving = false
    }

    public func updateLocal(_ change: @escaping (inout LocalPrefs) -> Void) {
        local = localStore.update(userId: userId, change)
    }

    public func setRemindersEnabled(_ on: Bool) async {
        if on {
            let granted = await scheduler.requestPermission()
            if !granted { return }
        }
        updateReminders { $0.enabled = on }
    }

    public func updateReminders(_ change: (inout ReminderSettings) -> Void) {
        var next = reminders
        change(&next)
        reminders = next
        scheduler.apply(next)
        local = localStore.update(userId: userId) {
            $0.reminderEnabled = next.enabled
            $0.reminderHour = next.hour
            $0.reminderMinute = next.minute
        }
    }

    /// Signs out through the injected closure (the app wires AuthApi.logout plus the session clear).
    public func signOut() async {
        guard let action = signOutAction, !signingOut else { return }
        signingOut = true
        signOutError = nil
        do {
            try await action()
        } catch {
            signOutError = "Couldn't sign out. Try again."
        }
        signingOut = false
    }

    /// Plays a voice's sample so the learner can hear it before choosing it (Android previewVoice).
    public func previewVoice(_ voice: SettingsVoice) {
        guard let previewer = previewer, let text = voice.sampleText, let language = voice.sampleLanguage, voice.canPreview else { return }
        previewNotice = nil
        if !previewer.preview(text: text, languageTag: language) {
            previewNotice = "This device has no voice installed for that language, so the sample can't play."
        }
    }

    /// Books a pause of `days` days starting `startDay` ("yyyy-MM-dd").
    public func pauseStreak(startDay: String, days: Int) async {
        await streakPause.book(startDay: startDay, days: days)
    }

    public func cancelStreakPause() async {
        await streakPause.cancel()
    }

    /// Seeds a loaded screen without any network (snapshot showcases).
    public static func preview(form: UpdatePrefsRequest, local: LocalPrefs, reminders: ReminderSettings, streak: StreakResponse?, courseCode: String, voices: [SettingsVoice], accountName: String? = nil, canSignOut: Bool = false) -> SettingsModel {
        let suite = UserDefaults(suiteName: "qamooscheh.settings.preview") ?? .standard
        let store = LocalPrefsStore(defaults: suite)
        store.update(userId: "preview") { $0 = local }
        let scheduler = StubReminderScheduler()
        scheduler.apply(reminders)
        var signOutStub: (() async throws -> Void)?
        if canSignOut { signOutStub = { } }
        let model = SettingsModel(
            userId: "preview", courseCode: courseCode,
            sync: PrefsSync(userId: "preview", courseCode: courseCode, api: OfflinePrefsAPI(), defaults: suite),
            localStore: store, scheduler: scheduler, streakService: nil, voices: voices,
            accountName: accountName, signOut: signOutStub, previewer: nil)
        model.form = form
        model.streakPause.seed(streak)
        return model
    }
}

struct OfflinePrefsAPI: PrefsAPI {
    func fetch() async throws -> PrefsResponse { throw URLError(.notConnectedToInternet) }
    func save(_ request: UpdatePrefsRequest) async throws -> PrefsResponse { throw URLError(.notConnectedToInternet) }
}
