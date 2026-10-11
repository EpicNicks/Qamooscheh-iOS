import Foundation
import QModel

/// A failed sign-in, registration or Google call, mapped from the problem response.
public enum AuthError: Error, Equatable, LocalizedError, Sendable {
    /// 401: wrong email or password, or a Google token that did not verify.
    case invalidCredentials(message: String?)
    /// 409: the email is already registered.
    case emailTaken(message: String?)
    /// 403: new accounts are closed.
    case registrationClosed(message: String?)
    /// 400: the request failed server-side validation.
    case validation(message: String?)
    /// 429: too many attempts.
    case tooManyAttempts(message: String?)
    /// Any other non-2xx response.
    case other(ApiError)

    public var errorDescription: String? {
        switch self {
        case .invalidCredentials(let message):
            return AuthError.text(message, "Incorrect email or password.")
        case .emailTaken(let message):
            return AuthError.text(message, "That email is already registered.")
        case .registrationClosed(let message):
            return AuthError.text(message, "Registration is closed right now.")
        case .validation(let message):
            return AuthError.text(message, "Check your details and try again.")
        case .tooManyAttempts(let message):
            return AuthError.text(message, "Too many attempts. Wait a moment and try again.")
        case .other(let error):
            return error.errorDescription
        }
    }

    private static func text(_ message: String?, _ fallback: String) -> String {
        if let message = message, !message.isEmpty { return message }
        return fallback
    }

    static func from(_ error: ApiError) -> AuthError {
        let message = error.body?.error
        switch error.status {
        case 400: return .validation(message: message)
        case 401: return .invalidCredentials(message: message)
        case 403: return .registrationClosed(message: message)
        case 409: return .emailTaken(message: message)
        case 429: return .tooManyAttempts(message: message)
        default: return .other(error)
        }
    }
}

/// Typed calls for /v1/auth/*. Sign-in calls persist the session; logout always clears it.
public struct AuthApi: Sendable {
    private let client: ApiClient
    private let store: SessionStore

    public init(client: ApiClient, store: SessionStore) {
        self.client = client
        self.store = store
    }

    /// Whether new accounts can be created (GET /v1/auth/registration-status).
    public func registrationEnabled() async throws -> Bool {
        do {
            let status: RegistrationStatusResponse = try await client.send(
                .get, "/v1/auth/registration-status", anonymous: true)
            return status.enabled
        } catch let error as ApiError {
            throw AuthError.from(error)
        }
    }

    @discardableResult
    public func login(email: String, password: String) async throws -> StoredSession {
        let body = LoginRequest(email: AuthApi.trimmed(email), password: password)
        return try await signIn("/v1/auth/login", body)
    }

    @discardableResult
    public func register(email: String, password: String, confirmPassword: String) async throws -> StoredSession {
        let body = RegisterRequest(
            email: AuthApi.trimmed(email), password: password, confirmPassword: confirmPassword)
        return try await signIn("/v1/auth/register", body)
    }

    @discardableResult
    public func signInWithGoogle(idToken: String) async throws -> StoredSession {
        try await signIn("/v1/auth/google", GoogleAuthRequest(idToken: idToken))
    }

    /// Revokes the refresh token when the server is reachable, then always clears the store.
    public func logout() async {
        if let session = await store.load() {
            do {
                try await client.sendNoContent(
                    .post, "/v1/auth/logout",
                    body: RefreshRequest(refreshToken: session.refreshToken), anonymous: true)
            } catch {
                // Best effort: the local sign-out must not depend on the server.
            }
        }
        await store.clear()
    }

    // MARK: Internals

    private func signIn(_ path: String, _ body: any Encodable) async throws -> StoredSession {
        let auth: AuthResponse
        do {
            auth = try await client.send(.post, path, body: body, anonymous: true)
        } catch let error as ApiError {
            throw AuthError.from(error)
        }
        let session = StoredSession(
            userId: auth.userId,
            accessToken: auth.accessToken,
            accessTokenExpiresAt: auth.accessTokenExpiresAt,
            refreshToken: auth.refreshToken)
        await store.save(session)
        return session
    }

    private static func trimmed(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
