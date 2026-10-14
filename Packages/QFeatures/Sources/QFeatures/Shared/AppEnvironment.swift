import Foundation
import QModel
import QDomain
import QNetwork
import QData

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
        scheduler: ReminderScheduling = StubReminderScheduler()
    ) -> SettingsModel {
        let signOutAction = signOut
        return SettingsModel(
            userId: userId, courseCode: course.code,
            sync: makePrefsSync(userId, course.code), localStore: localStore,
            scheduler: scheduler, streakService: streak,
            voices: settingsVoices(course), accountName: accountName,
            signOut: { await signOutAction() },
            previewer: previewer)
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
        let pinned: @Sendable () async throws -> CourseRef? = {
            let response: BootstrapResponse = try await client.send(.get, "/v1/bootstrap")
            return response.course
        }
        return AppEnvironment(
            profile: LiveProfileService(client: client),
            streak: LiveStreakService(client: client),
            friends: FriendsRepository(client: client),
            leagues: LeagueRepository(client: client),
            vocabulary: LiveVocabularySource(
                repository: vocab, cards: CardStateStore(store: contentStore),
                reader: reader, course: pinned, userId: userId),
            flashcards: LiveFlashcardSubmitter(repository: vocab, afterSubmit: afterFlashcardSubmit),
            themes: LiveThemeLibrarySource(reader: reader, course: pinned),
            glossary: loadGlossary(),
            currentUserId: userId,
            pinnedCourse: pinned,
            makePrefsSync: { user, course in
                PrefsSync(userId: user, courseCode: course, api: PrefsRepository(client: client))
            },
            settingsVoices: { pinned in (try? reader.settingsVoices(pinned)) ?? [] },
            signOut: {
                await MainActor.run { previewer?.stop() }
                await auth.logout()
            },
            previewer: previewer)
    }
}
