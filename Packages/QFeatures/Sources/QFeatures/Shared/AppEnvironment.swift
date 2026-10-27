import Foundation
import QModel
import QDomain
import QNetwork
import QData
#if canImport(UserNotifications)
import UserNotifications
#endif
#if canImport(AVFoundation)
import AVFoundation
#endif

/// The production services behind the signed-in screens, all built on one ApiClient and one content store.
/// UI wiring reads these; nothing here touches SwiftUI.
public struct AppEnvironment: @unchecked Sendable {
    public let profile: ProfileService
    public let streak: StreakService
    public let friends: FriendsService
    /// The contacts-matching calls; nil in tests.
    public let contacts: ContactsService?
    /// The address-book reader; nil in tests.
    public let contactEmails: ContactEmailReading?
    public let leagues: LeagueService
    public let vocabulary: VocabularySource
    public let flashcards: FlashcardSubmitter
    /// The saved-words remix source; nil in tests.
    public let savedPractice: SavedPracticeSource?
    /// The lesson exercises a fill-in-the-blank round cuts its sentences from; nil in tests.
    public let clozeSentences: ClozeSentenceSource?
    /// The Repack race endpoints; nil in tests.
    public let race: RaceService?
    public let themes: ThemeLibrarySource
    /// The bundled glossary (QDomain); filter it with `Glossary.forCourse`.
    public let glossary: Glossary
    public let currentUserId: @Sendable () async -> String?
    /// The pinned course from GET /v1/bootstrap; nil with no active course.
    public let pinnedCourse: @Sendable () async throws -> CourseRef?
    /// GET /v1/bootstrap (the course switcher and the Path header read it); throws offline.
    public let bootstrap: @Sendable () async throws -> BootstrapResponse
    /// The course's activity days (GET /v1/activity/{code}); Profile and the Path header's Total XP sum them.
    public let activity: @Sendable (_ courseCode: String) async throws -> [ActivityDay]
    /// One PrefsSync per (user, course); keep and reuse the one for the active pair.
    public let makePrefsSync: @Sendable (_ userId: String, _ courseCode: String) -> PrefsSync
    /// The pinned course's voices for the Settings picker, with samples; empty when none.
    public let settingsVoices: @Sendable (_ course: CourseRef) -> [SettingsVoice]
    /// Stops any voice sample, then AuthApi.logout (best-effort server revoke; always clears the local session).
    public let signOut: @Sendable () async -> Void
    /// Forgets a user's prefs and card mirror on this device. Sign-out and an expired session both call it.
    public let forgetUser: @Sendable (_ userId: String) async -> Void
    /// The voice sample player; nil in tests.
    public let previewer: VoicePreviewing?
    /// Schedules the learner's reminders; nil in tests and previews.
    public let reminders: ReminderService?
    /// The Learn tab's content, download, Stow and roll-forward services; nil in tests and previews.
    public let path: PathServices?

    public init(
        profile: ProfileService,
        streak: StreakService,
        friends: FriendsService,
        leagues: LeagueService,
        vocabulary: VocabularySource,
        flashcards: FlashcardSubmitter,
        themes: ThemeLibrarySource,
        glossary: Glossary,
        currentUserId: @escaping @Sendable () async -> String?,
        pinnedCourse: @escaping @Sendable () async throws -> CourseRef?,
        makePrefsSync: @escaping @Sendable (String, String) -> PrefsSync,
        bootstrap: @escaping @Sendable () async throws -> BootstrapResponse = { throw URLError(.notConnectedToInternet) },
        activity: @escaping @Sendable (String) async throws -> [ActivityDay] = { _ in [] },
        settingsVoices: @escaping @Sendable (CourseRef) -> [SettingsVoice] = { _ in [] },
        signOut: @escaping @Sendable () async -> Void = {},
        forgetUser: @escaping @Sendable (String) async -> Void = { _ in },
        previewer: VoicePreviewing? = nil,
        savedPractice: SavedPracticeSource? = nil,
        contacts: ContactsService? = nil,
        contactEmails: ContactEmailReading? = nil,
        clozeSentences: ClozeSentenceSource? = nil,
        race: RaceService? = nil,
        reminders: ReminderService? = nil,
        path: PathServices? = nil
    ) {
        self.path = path
        self.reminders = reminders
        self.clozeSentences = clozeSentences
        self.race = race
        self.contacts = contacts
        self.contactEmails = contactEmails
        self.savedPractice = savedPractice
        self.profile = profile
        self.streak = streak
        self.friends = friends
        self.leagues = leagues
        self.vocabulary = vocabulary
        self.flashcards = flashcards
        self.themes = themes
        self.glossary = glossary
        self.currentUserId = currentUserId
        self.pinnedCourse = pinnedCourse
        self.makePrefsSync = makePrefsSync
        self.bootstrap = bootstrap
        self.activity = activity
        self.settingsVoices = settingsVoices
        self.signOut = signOut
        self.forgetUser = forgetUser
        self.previewer = previewer
    }

    /// Stops a playing voice sample. Call when Settings is left; sign-out calls it too.
    @MainActor
    public func stopVoicePreview() {
        previewer?.stop()
    }

    /// A Settings model wired for production: sign-out (so the Account section shows) and the voice previewer.
    @MainActor
    public func makeSettingsModel(
        userId: String,
        course: CourseRef,
        accountName: String?,
        localStore: LocalPrefsStore = LocalPrefsStore(),
        scheduler: ReminderScheduling? = nil,
        afterSignOut: (@Sendable () async -> Void)? = nil
    ) -> SettingsModel {
        let signOutAction = signOut
        let reminderScheduler: ReminderScheduling = scheduler
            ?? reminders.map { LiveReminderScheduler(userId: userId, service: $0) }
            ?? StubReminderScheduler()
        return SettingsModel(
            userId: userId, courseCode: course.code,
            sync: makePrefsSync(userId, course.code), localStore: localStore,
            scheduler: reminderScheduler, streakService: streak,
            voices: settingsVoices(course), accountName: accountName,
            signOut: {
                await signOutAction()
                await afterSignOut?()
            },
            previewer: previewer,
            reenable: reminders == nil ? nil : ReenablePromptStore())
    }

    /// The app's environment: one ApiClient on `sessions`, course files and the card mirror under Application Support/content
    /// (where the lesson pipeline keeps them), and a voice previewer when the platform has speech.
    public static func live(
        baseURL: URL, clientHeader: String, sessions: SessionStore,
        cdnBaseURL: URL = URL(string: "https://cdn.parsling.com")!,
        flushQueue: (@Sendable (String) async -> Void)? = nil
    ) -> AppEnvironment {
        let client = ApiClient(baseURL: baseURL, clientHeader: clientHeader, store: sessions)
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let store = FileContentStore(root: support.appendingPathComponent("content", isDirectory: true))
        #if canImport(AVFoundation)
        let previewer: VoicePreviewing? = SpeechVoicePreviewer(speech: SpeechService(synthesizer: AVSpeechSynthesizerAdapter()))
        #else
        let previewer: VoicePreviewing? = nil
        #endif
        return live(
            client: client, sessions: sessions, contentStore: store, previewer: previewer, cdnBaseURL: cdnBaseURL,
            reminders: systemReminders(currentUserId: { await sessions.load()?.userId }),
            flushQueue: flushQueue)
    }

    /// Builds the environment on `client`, reading course files and the card mirror from `contentStore`.
    public static func live(
        client: ApiClient,
        sessions: SessionStore,
        contentStore: ContentFileStore,
        afterFlashcardSubmit: (@Sendable () async -> Void)? = nil,
        previewer: VoicePreviewing? = nil,
        cdnBaseURL: URL = URL(string: "https://cdn.parsling.com")!,
        reminders: ReminderService? = nil,
        flushQueue: (@Sendable (String) async -> Void)? = nil
    ) -> AppEnvironment {
        let auth = AuthApi(client: client, store: sessions)
        let reader = CourseContentReader(store: contentStore)
        let vocab = VocabRepository(client: client)
        let userId: @Sendable () async -> String? = { await sessions.load()?.userId }
        let fetchBootstrap: @Sendable () async throws -> BootstrapResponse = {
            let uid = await userId()
            let response: BootstrapResponse = try await client.send(.get, "/v1/bootstrap")
            PinCache.save(response.course, userId: uid, store: contentStore)
            return response
        }
        let pinned: @Sendable () async throws -> CourseRef? = {
            let uid = await userId()
            do {
                return try await fetchBootstrap().course
            } catch {
                // Offline (or server down): fall back to the last pin this user saw, like Android.
                if let cached = PinCache.load(userId: uid, store: contentStore) { return cached }
                throw error
            }
        }
        let cardStore = CardStateStore(store: contentStore)
        let prefsProvider = PrefsSyncProvider(api: PrefsRepository(client: client))
        let forget: @Sendable (String) async -> Void = { uid in
            guard !uid.isEmpty else { return }
            await reminders?.cancelAll()
            await prefsProvider.clear(userId: uid)
            try? await cardStore.clear(userId: uid)
        }
        return AppEnvironment(
            profile: LiveProfileService(client: client),
            streak: StreakRepository(client: client),
            friends: FriendsRepository(client: client),
            leagues: LeagueRepository(client: client),
            vocabulary: LiveVocabularySource(
                repository: vocab, cards: cardStore,
                reader: reader, course: pinned, userId: userId),
            flashcards: LiveFlashcardSubmitter(repository: vocab, afterSubmit: afterFlashcardSubmit),
            themes: LiveThemeLibrarySource(reader: reader, course: pinned),
            glossary: loadGlossary(),
            currentUserId: userId,
            pinnedCourse: pinned,
            makePrefsSync: { user, course in prefsProvider.sync(userId: user, courseCode: course) },
            bootstrap: fetchBootstrap,
            activity: { code in
                let allowed = code.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
                guard allowed, !code.isEmpty else { return [] }
                let response: ActivityResponse = try await client.send(.get, "/v1/activity/\(code)")
                return response.days
            },
            settingsVoices: { pinned in (try? reader.settingsVoices(pinned)) ?? [] },
            signOut: {
                await MainActor.run { previewer?.stop() }
                // Detached so the cleanup finishes even if the screen that started it goes away.
                await Task.detached {
                    let uid = await userId()
                    await reminders?.cancelAll()
                    await auth.logout()
                    guard let uid else { return }
                    // Forget the signed-out user's prefs and card mirror so the next account starts clean.
                    await forget(uid)
                    let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                        ?? URL(fileURLWithPath: NSTemporaryDirectory())
                    let queue = OfflineQueue(storage: FileOfflineQueueStorage(
                        directory: support.appendingPathComponent("offline-queue", isDirectory: true)))
                    try? await queue.clear(userId: uid)
                    LessonDraftStore.removeAll(
                        directory: support.appendingPathComponent("lesson-drafts", isDirectory: true), userId: uid)
                }.value
            },
            forgetUser: forget,
            previewer: previewer,
            savedPractice: LiveSavedPracticeSource(repository: vocab),
            contacts: ContactsRepository(client: client),
            contactEmails: systemContactEmails(),
            clozeSentences: LiveClozeSentenceSource(reader: reader, course: pinned),
            race: LiveRaceService(repository: RaceRepository(client: client), afterFinish: afterFlashcardSubmit),
            reminders: reminders,
            path: PathServices.live(client: client, contentStore: contentStore, cdnBaseURL: cdnBaseURL, flushQueue: flushQueue))
    }
}

/// The last pinned course seen from /v1/bootstrap, per user, so offline loads still find the downloaded course.
enum PinCache {
    static func key(userId: String?) -> String? {
        guard let userId, !userId.isEmpty,
              userId.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }) else { return nil }
        return "pin/\(userId).json"
    }

    static func save(_ course: CourseRef?, userId: String?, store: ContentFileStore) {
        guard let key = key(userId: userId) else { return }
        if let course, let data = try? QJSON.makeEncoder().encode(course) {
            try? store.write(data, to: key)
        } else if course == nil {
            try? store.remove(key)
        }
    }

    static func load(userId: String?, store: ContentFileStore) -> CourseRef? {
        guard let key = key(userId: userId), let data = try? store.read(key) else { return nil }
        return try? QJSON.makeDecoder().decode(CourseRef.self, from: data)
    }
}

/// The real notification center with the account-checking delegate installed; nil where there is none.
private func systemReminders(currentUserId: @escaping @Sendable () async -> String?) -> ReminderService? {
    #if canImport(UserNotifications)
    let center = SystemReminderCenter()
    let delegate = ReminderNotificationDelegate(center: center, currentUserId: currentUserId)
    UNUserNotificationCenter.current().delegate = delegate
    return ReminderService(center: center, retaining: [delegate])
    #else
    return nil
    #endif
}

private func systemContactEmails() -> ContactEmailReading? {
    #if canImport(Contacts)
    return SystemContactEmails()
    #else
    return nil
    #endif
}
