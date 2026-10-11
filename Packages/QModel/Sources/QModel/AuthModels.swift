import Foundation


/// POST /v1/auth/register.
public struct RegisterRequest: Codable, Equatable, Sendable {
    public var email: String
    public var password: String
    public var confirmPassword: String

    public init(email: String, password: String, confirmPassword: String) {
        self.email = email
        self.password = password
        self.confirmPassword = confirmPassword
    }
}

/// POST /v1/auth/login.
public struct LoginRequest: Codable, Equatable, Sendable {
    public var email: String
    public var password: String

    public init(email: String, password: String) {
        self.email = email
        self.password = password
    }
}

/// POST /v1/auth/google.
public struct GoogleAuthRequest: Codable, Equatable, Sendable {
    public var idToken: String

    public init(idToken: String) {
        self.idToken = idToken
    }
}

/// POST /v1/auth/refresh.
public struct RefreshRequest: Codable, Equatable, Sendable {
    public var refreshToken: String

    public init(refreshToken: String) {
        self.refreshToken = refreshToken
    }
}

/// GET /v1/auth/registration-status.
public struct RegistrationStatusResponse: Codable, Equatable, Sendable {
    public var enabled: Bool

    public init(enabled: Bool) {
        self.enabled = enabled
    }
}

/// Login, register, Google and refresh response.
public struct AuthResponse: Codable, Equatable, Sendable {
    public var userId: String
    public var accessToken: String
    public var refreshToken: String
    public var accessTokenExpiresAt: Date

    public init(userId: String, accessToken: String, refreshToken: String, accessTokenExpiresAt: Date) {
        self.userId = userId
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.accessTokenExpiresAt = accessTokenExpiresAt
    }
}
