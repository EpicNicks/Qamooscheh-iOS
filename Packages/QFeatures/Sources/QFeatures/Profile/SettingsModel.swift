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
    @Published public private(set) var notice: SettingsNotice?
    @Published public private(set) var streak: StreakResponse?
    @Published public private(set) var pauseBusy = false
    @Published public private(set) var pauseError: String?

    public let courseCode: String
    public let voices: [SettingsVoice]

    private let userId: String
    private let sync: PrefsSync
    private let localStore: LocalPrefsStore
    private let scheduler: ReminderScheduling
    private let streakService: StreakService?
    private var dirty = false

    public init(
        userId: String,
        courseCode: String,
        sync: PrefsSync,
        localStore: LocalPrefsStore,
        scheduler: ReminderScheduling = StubReminderScheduler(),
        streakService: StreakService? = nil,
        voices: [SettingsVoice] = []
    ) {
        self.userId = userId
        self.courseCode = courseCode
        self.sync = sync
        self.localStore = localStore
        self.scheduler = scheduler
        self.streakService = streakService
        self.voices = voices
        self.local = localStore.current(userId: userId)
        self.reminders = scheduler.current()
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
        if let service = streakService {
            streak = try? await service.fetch()
        }
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
    }

    /// Books a pause of `days` days starting `startDay` ("yyyy-MM-dd").
    public func pauseStreak(startDay: String, days: Int) async {
        guard let service = streakService, !pauseBusy, days >= 1 else { return }
        pauseBusy = true
        pauseError = nil
        do {
            try await service.pause(StreakPauseRequest(startDay: startDay, endDay: addDays(startDay, days - 1)))
            streak = try? await service.fetch()
        } catch {
            pauseError = "Couldn't pause your streak. Try again."
        }
        pauseBusy = false
    }

    public func cancelStreakPause() async {
        guard let service = streakService, !pauseBusy else { return }
        pauseBusy = true
        pauseError = nil
        do {
            try await service.cancelPause()
            streak = try? await service.fetch()
        } catch {
            pauseError = "Couldn't change your pause. Try again."
        }
        pauseBusy = false
    }

    /// Seeds a loaded screen without any network (snapshot showcases).
    public static func preview(form: UpdatePrefsRequest, local: LocalPrefs, reminders: ReminderSettings, streak: StreakResponse?, courseCode: String, voices: [SettingsVoice]) -> SettingsModel {
        let suite = UserDefaults(suiteName: "qamooscheh.settings.preview") ?? .standard
        let store = LocalPrefsStore(defaults: suite)
        store.update(userId: "preview") { $0 = local }
        let scheduler = StubReminderScheduler()
        scheduler.apply(reminders)
        let model = SettingsModel(
            userId: "preview", courseCode: courseCode,
            sync: PrefsSync(userId: "preview", courseCode: courseCode, api: OfflinePrefsAPI(), defaults: suite),
            localStore: store, scheduler: scheduler, streakService: nil, voices: voices)
        model.form = form
        model.streak = streak
        return model
    }
}

struct OfflinePrefsAPI: PrefsAPI {
    func fetch() async throws -> PrefsResponse { throw URLError(.notConnectedToInternet) }
    func save(_ request: UpdatePrefsRequest) async throws -> PrefsResponse { throw URLError(.notConnectedToInternet) }
}
