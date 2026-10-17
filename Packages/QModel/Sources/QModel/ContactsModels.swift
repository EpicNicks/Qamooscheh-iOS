import Foundation

/// Qamooscheh.Domain.FriendRelationship: the caller's side of a pair.
public enum FriendRelationship: String, Codable, Equatable, Hashable, Sendable, CaseIterable {
    case none = "none"
    case requestSent = "request_sent"
    case requestReceived = "request_received"
    case friends = "friends"
}

/// PUT /v1/contacts/findable's body.
public struct SetContactsFindableRequest: Codable, Equatable, Sendable {
    public var findable: Bool

    public init(findable: Bool) {
        self.findable = findable
    }
}

/// GET/PUT /v1/contacts/findable. `canBeFound` is false for an account with no password credential (Google-only).
public struct ContactsFindableResponse: Codable, Equatable, Sendable {
    public var findable: Bool
    public var canBeFound: Bool

    public init(findable: Bool, canBeFound: Bool) {
        self.findable = findable
        self.canBeFound = canBeFound
    }
}

/// POST /v1/contacts/match's body: hex SHA-256 of each trimmed, lower-cased email, 1 to 500.
public struct ContactsMatchRequest: Codable, Equatable, Sendable {
    public var hashes: [String]

    public init(hashes: [String]) {
        self.hashes = hashes
    }
}

/// One matched user. No username, email or hash.
public struct ContactMatchResponse: Codable, Equatable, Sendable {
    public var userId: String
    public var displayName: String?
    public var relationship: FriendRelationship

    public init(userId: String, displayName: String? = nil, relationship: FriendRelationship) {
        self.userId = userId
        self.displayName = displayName
        self.relationship = relationship
    }
}

/// POST /v1/contacts/match's response.
public struct ContactsMatchResponse: Codable, Equatable, Sendable {
    public var matches: [ContactMatchResponse]

    public init(matches: [ContactMatchResponse]) {
        self.matches = matches
    }
}
