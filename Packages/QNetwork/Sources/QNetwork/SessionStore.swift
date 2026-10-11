import Foundation

/// The stored credentials for the signed-in user.
public struct StoredSession: Equatable, Sendable {
    public var userId: String
    public var accessToken: String
    public var accessTokenExpiresAt: Date
    public var refreshToken: String

    public init(userId: String, accessToken: String, accessTokenExpiresAt: Date, refreshToken: String) {
        self.userId = userId
        self.accessToken = accessToken
        self.accessTokenExpiresAt = accessTokenExpiresAt
        self.refreshToken = refreshToken
    }
}

/// Persistence for the session (Keychain in the app, in-memory in tests).
public protocol SessionStore: Sendable {
    func load() async -> StoredSession?
    func save(_ session: StoredSession) async
    func clear() async
}

/// In-memory store, for tests and previews.
public actor InMemorySessionStore: SessionStore {
    private var session: StoredSession?

    public init(session: StoredSession? = nil) {
        self.session = session
    }

    public func load() async -> StoredSession? { session }
    public func save(_ session: StoredSession) async { self.session = session }
    public func clear() async { session = nil }
}
