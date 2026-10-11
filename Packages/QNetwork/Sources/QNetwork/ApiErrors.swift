import Foundation

/// The controller error body: { "error": "...", "reason": "..." }.
public struct ApiErrorBody: Codable, Equatable, Sendable {
    public var error: String?
    public var reason: String?

    public init(error: String? = nil, reason: String? = nil) {
        self.error = error
        self.reason = reason
    }
}

/// Thrown for every non-2xx response.
public struct ApiError: Error, Equatable, LocalizedError, Sendable {
    public let status: Int
    public let body: ApiErrorBody?

    public init(status: Int, body: ApiErrorBody?) {
        self.status = status
        self.body = body
    }

    public var errorDescription: String? {
        if let text = body?.error, !text.isEmpty { return text }
        if status == 429 { return "Too many attempts. Wait a moment and try again." }
        return "Request failed with status \(status)"
    }
}

/// A refresh failed definitively and the session was cleared; callers show sign-in.
public struct SessionExpiredError: Error, Equatable, Sendable {
    public init() {}
}

/// A refresh resolved after the session it started from was replaced.
/// Not a sign-out: whoever is signed in now is fine.
public struct StaleRefreshError: Error, Equatable, Sendable {
    public init() {}
}

/// The response was not an HTTP response.
public struct InvalidResponseError: Error, Equatable, Sendable {
    public init() {}
}
