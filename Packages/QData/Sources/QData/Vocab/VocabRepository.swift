import Foundation
import QModel
import QNetwork

/// Starred (saved) words and saved-word flashcards (API_SPEC 2.8, VocabContracts.cs and
/// FlashcardContracts.cs). Errors surface as `ApiError` (HTTP) or `URLError` (network).
public struct VocabRepository: Sendable {
    private let client: ApiClient

    public init(client: ApiClient) {
        self.client = client
    }

    /// GET /v1/vocab/starred: every tag saved in any course, most recently saved first.
    public func starred() async throws -> StarredVocabResponse {
        try await client.send(.get, "/v1/vocab/starred")
    }

    /// PUT /v1/vocab/starred with absolute state (not a toggle), so a retry is harmless.
    public func setStarred(tag: String, starred: Bool) async throws -> StarredVocabResponse {
        try await client.send(.put, "/v1/vocab/starred", body: SetStarredRequest(tag: tag, starred: starred))
    }

    /// POST /v1/flashcards/submit. The request's submissionId makes a retry answer with the first award.
    public func submitFlashcards(_ request: SubmitFlashcardsRequest) async throws -> SubmitFlashcardsResponse {
        try await client.send(.post, "/v1/flashcards/submit", body: request)
    }
}
