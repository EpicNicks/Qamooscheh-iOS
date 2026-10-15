import Foundation
import QModel
import QDomain
import QNetwork
import QData
#if canImport(AVFoundation)
import AVFoundation
#endif

/// The production services behind the signed-in screens, all built on one ApiClient and one content store.
/// UI wiring reads these; nothing here touches SwiftUI.
public struct AppEnvironment: @unchecked Sendable {
    public let profile: ProfileService
    public let streak: StreakService
    public let friends: FriendsService
    public let leagues: LeagueService
    public let vocabulary: VocabularySource
    public let flashcards: FlashcardSubmitter
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
    /// The voice sample player; nil in tests.
    public let previewer: VoicePreviewing?

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
        previewer: VoicePreviewing? = nil
    ) {
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
        scheduler: ReminderScheduling = StubReminderScheduler(),
        afterSignOut: (@Sendable () async -> Void)? = nil
    ) -> SettingsModel {
        let signOutAction = signOut
        return SettingsModel(
            userId: userId, courseCode: course.code,
            sync: makePrefsSync(userId, course.code), localStore: localStore,
            scheduler: scheduler, streakService: streak,
            voices: settingsVoices(course), accountName: accountName,
            signOut: {
                await signOutAction()
                await afterSignOut?()
            },
            previewer: previewer)
    }

    /// The app's environment: one ApiClient on `sessions`, course files and the card mirror under Application Support/content
    /// (where the lesson pipeline keeps them), and a voice previewer when the platform has speech.
    public static func live(baseURL: URL, clientHeader: String, sessions: SessionStore) -> AppEnvironment {
        let client = ApiClient(baseURL: baseURL, clientHeader: clientHeader, store: sessions)
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let store = FileContentStore(root: support.appendingPathComponent("content", isDirectory: true))
        #if canImport(AVFoundation)
        let previewer: VoicePreviewing? = SpeechVoicePreviewer(speech: SpeechService(synthesizer: AVSpeechSynthesizerAdapter()))
        #else
        let previewer: VoicePreviewing? = nil
        #endif
        return live(client: client, sessions: sessions, contentStore: store, previewer: previewer)
    }

    /// Builds the environment on `client`, reading course files and the card mirror from `contentStore`.
    public static func live(
        client: ApiClient,
        sessions: SessionStore,
        contentStore: ContentFileStore,
        afterFlashcardSubmit: (@Sendable () async -> Void)? = nil,
        previewer: VoicePreviewing? = nil
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
                let uid = await userId()
                await auth.logout()
                // Forget the signed-out user's prefs and card mirror so the next account starts clean.
                if let uid, !uid.isEmpty {
                    await prefsProvider.clear(userId: uid)
                    try? await cardStore.clear(userId: uid)
                }
            },
            previewer: previewer)
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
