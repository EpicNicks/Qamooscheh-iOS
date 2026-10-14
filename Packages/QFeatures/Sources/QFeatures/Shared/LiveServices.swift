import Foundation
import QModel
import QNetwork
import QData

/// GET/PUT /v1/profile.
public struct LiveProfileService: ProfileService {
    private let client: ApiClient

    public init(client: ApiClient) {
        self.client = client
    }

    public func fetch() async throws -> ProfileResponse {
        try await client.send(.get, "/v1/profile")
    }

    public func save(_ request: UpdateProfileRequest) async throws -> ProfileResponse {
        try await client.send(.put, "/v1/profile", body: request)
    }
}

/// GET /v1/streak, POST/DELETE /v1/streak/pause. The pause calls answer with the new streak, which the screen refetches.
public struct LiveStreakService: StreakService {
    private let client: ApiClient

    public init(client: ApiClient) {
        self.client = client
    }

    public func fetch() async throws -> StreakResponse {
        try await client.send(.get, "/v1/streak")
    }

    public func pause(_ request: StreakPauseRequest) async throws {
        try await client.sendNoContent(.post, "/v1/streak/pause", body: request)
    }

    public func cancelPause() async throws {
        try await client.sendNoContent(.delete, "/v1/streak/pause")
    }
}

/// Submits flashcards, then runs `afterSubmit` so the caller can refresh the day's progress and streak.
public struct LiveFlashcardSubmitter: FlashcardSubmitter {
    private let repository: VocabRepository
    private let afterSubmit: (@Sendable () async -> Void)?

    public init(repository: VocabRepository, afterSubmit: (@Sendable () async -> Void)? = nil) {
        self.repository = repository
        self.afterSubmit = afterSubmit
    }

    public func submit(_ request: SubmitFlashcardsRequest) async throws -> SubmitFlashcardsResponse {
        let response = try await repository.submitFlashcards(request)
        await afterSubmit?()
        return response
    }
}

/// The vocabulary screens' source: the pinned course on disk, the user's card mirror, the starred endpoints.
public struct LiveVocabularySource: VocabularySource {
    private let repository: VocabRepository
    private let cards: CardStateStore
    private let reader: CourseContentReader
    private let course: @Sendable () async throws -> CourseRef?
    private let userId: @Sendable () async -> String?

    public init(
        repository: VocabRepository,
        cards: CardStateStore,
        reader: CourseContentReader,
        course: @escaping @Sendable () async throws -> CourseRef?,
        userId: @escaping @Sendable () async -> String?
    ) {
        self.repository = repository
        self.cards = cards
        self.reader = reader
        self.course = course
        self.userId = userId
    }

    public func load() async throws -> VocabLoad {
        guard let pinned = try await course() else { return .noCourse }
        guard reader.isDownloaded(pinned), let content = try reader.vocabContent(pinned) else { return .notDownloaded }
        return .ready(content)
    }

    public func cardStates() async -> [String: CardState] {
        guard let id = await userId() else { return [:] }
        return await cards.all(userId: id)
    }

    public func starred() async throws -> StarredVocabResponse {
        try await repository.starred()
    }

    public func setStarred(tag: String, starred: Bool) async throws -> StarredVocabResponse {
        try await repository.setStarred(tag: tag, starred: starred)
    }
}

/// The Library screens' source: themes.json and lesson headers from the pinned course on disk.
public struct LiveThemeLibrarySource: ThemeLibrarySource {
    private let reader: CourseContentReader
    private let course: @Sendable () async throws -> CourseRef?

    public init(reader: CourseContentReader, course: @escaping @Sendable () async throws -> CourseRef?) {
        self.reader = reader
        self.course = course
    }

    public func load() async throws -> ThemeLibraryData? {
        guard let pinned = try await course(), reader.isDownloaded(pinned) else { return nil }
        return try reader.themeLibrary(pinned)
    }
}
