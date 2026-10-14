import Foundation
import QModel
import QDomain
import QNetwork
import QData

/// The production services behind the signed-in screens, all built on one ApiClient and one content store.
/// UI wiring reads these; nothing here touches SwiftUI.
public struct AppEnvironment: Sendable {
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
        makePrefsSync: @escaping @Sendable (String, String) -> PrefsSync
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
    }

    /// Builds the environment on `client`, reading course files and the card mirror from `contentStore`.
    public static func live(
        client: ApiClient,
        sessions: SessionStore,
        contentStore: ContentFileStore,
        afterFlashcardSubmit: (@Sendable () async -> Void)? = nil
    ) -> AppEnvironment {
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
            })
    }
}
