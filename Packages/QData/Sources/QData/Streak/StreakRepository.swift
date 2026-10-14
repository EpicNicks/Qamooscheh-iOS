import Foundation
import QModel
import QNetwork

/// The `v1/streak` routes (API_SPEC.md 2.12). Always fetched fresh; each call answers the whole streak.
public struct StreakRepository: Sendable {
    private let client: ApiClient

    public init(client: ApiClient) {
        self.client = client
    }

    /// GET /v1/streak.
    public func streak() async throws -> StreakResponse {
        try await client.send(.get, "/v1/streak")
    }

    /// POST /v1/streak/pause. A 400 (invalid window) or 409 (a pause already booked) throws an `ApiError`.
    public func bookPause(_ request: StreakPauseRequest) async throws -> StreakResponse {
        try await client.send(.post, "/v1/streak/pause", body: request)
    }

    /// DELETE /v1/streak/pause. A 404 means there is no pause left to cancel, so it answers nil
    /// (a no-op); the caller refetches to learn the real state.
    public func endPause() async throws -> StreakResponse? {
        do {
            let response: StreakResponse = try await client.send(.delete, "/v1/streak/pause")
            return response
        } catch let error as ApiError where error.status == 404 {
            return nil
        }
    }
}
