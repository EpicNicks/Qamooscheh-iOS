import Foundation


/// A friend.
public struct FriendRefResponse: Codable, Equatable, Sendable {
    public var userId: String
    public var displayName: String?
    public var since: Date

    public init(userId: String, displayName: String? = nil, since: Date) {
        self.userId = userId
        self.displayName = displayName
        self.since = since
    }
}

/// Friend request result.
public struct FriendRequestResponse: Codable, Equatable, Sendable {
    public var status: FriendshipStatus

    public init(status: FriendshipStatus) {
        self.status = status
    }
}

/// User search hit.
public struct UserSearchResultResponse: Codable, Equatable, Sendable {
    public var userId: String
    public var displayName: String

    public init(userId: String, displayName: String) {
        self.userId = userId
        self.displayName = displayName
    }
}

/// One league row.
public struct LeagueStandingResponse: Codable, Equatable, Sendable {
    public var userId: String
    public var displayName: String?
    public var points: Int

    public init(userId: String, displayName: String? = nil, points: Int) {
        self.userId = userId
        self.displayName = displayName
        self.points = points
    }
}

/// GET /v1/leagues/current.
public struct CurrentLeagueResponse: Codable, Equatable, Sendable {
    public var tier: Int
    public var periodEndsAt: Date
    public var standings: [LeagueStandingResponse]

    public init(tier: Int, periodEndsAt: Date, standings: [LeagueStandingResponse]) {
        self.tier = tier
        self.periodEndsAt = periodEndsAt
        self.standings = standings
    }
}
