import Foundation
import QModel
import QNetwork

/// GET /v1/leagues/current (API_SPEC.md 2.9). Always fetched fresh, as the web and Android do.
public struct LeagueRepository: Sendable {
    private let client: ApiClient

    public init(client: ApiClient) {
        self.client = client
    }

    /// The caller's current league, or nil on a 404: a new account, not yet active enough, or between a period's end and its rollover.
    public func current() async throws -> CurrentLeagueResponse? {
        do {
            let league: CurrentLeagueResponse = try await client.send(.get, "/v1/leagues/current")
            return league
        } catch let error as ApiError where error.status == 404 {
            return nil
        }
    }
}
