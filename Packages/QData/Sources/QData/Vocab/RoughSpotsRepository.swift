import Foundation
import QModel
import QNetwork

/// The words the learner keeps missing (API_SPEC 2.2a). The response has the saved-words practice's shape, so it is
/// decoded with `StarredPracticeResponse`. Errors surface as `ApiError` (HTTP) or `URLError` (network).
public struct RoughSpotsRepository: Sendable {
    private let client: ApiClient

    public init(client: ApiClient) {
        self.client = client
    }

    /// GET /v1/sessions/rough-spots?words=N&listening=exclude: words 1...30; 409 when the course isn't bootstrapped, 400 for a bad query.
    /// `words: []` in the response means nothing is rough. Listening exercises are excluded: a Repack has no listening toggle.
    public func roughSpots(words: Int) async throws -> StarredPracticeResponse {
        try await client.send(.get, "/v1/sessions/rough-spots?words=\(words)&listening=exclude")
    }
}
