import Foundation
import QModel
import QNetwork

/// The `v1/friends` routes (API_SPEC.md 2.6). Always fetched fresh, as the web and Android do.
public struct FriendsRepository: Sendable {
    /// The backend's FriendsService.MinQueryLength.
    public static let minQueryLength = 2

    private let client: ApiClient

    public init(client: ApiClient) {
        self.client = client
    }

    /// GET /v1/friends.
    public func friends() async throws -> [FriendRefResponse] {
        try await client.send(.get, "/v1/friends")
    }

    /// GET /v1/friends/requests: incoming requests only; the backend lists none we sent.
    public func incomingRequests() async throws -> [FriendRefResponse] {
        try await client.send(.get, "/v1/friends/requests")
    }

    /// GET /v1/friends/search. Skips the round trip for a query the server would answer with [] anyway.
    public func search(_ query: String) async throws -> [UserSearchResultResponse] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= FriendsRepository.minQueryLength else { return [] }
        return try await client.send(.get, "/v1/friends/search?query=\(FriendsRepository.queryValue(trimmed))")
    }

    /// POST /v1/friends/{userId}. `.accepted` when this completed a request they had already sent us.
    public func request(_ userId: String) async throws -> FriendshipStatus {
        let response: FriendRequestResponse = try await client.send(.post, "/v1/friends/\(FriendsRepository.segment(userId))")
        return response.status
    }

    /// POST /v1/friends/{userId}/accept (204).
    public func accept(_ userId: String) async throws {
        try await client.sendNoContent(.post, "/v1/friends/\(FriendsRepository.segment(userId))/accept")
    }

    /// POST /v1/friends/{userId}/decline (204).
    public func decline(_ userId: String) async throws {
        try await client.sendNoContent(.post, "/v1/friends/\(FriendsRepository.segment(userId))/decline")
    }

    static func segment(_ value: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    static func queryValue(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=#?/")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}
