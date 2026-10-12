import Foundation
import QNetwork

/// The session store and auth service the auth screens and gate run against.
public struct AuthEnvironment: Sendable {
    public let store: SessionStore
    public let service: AuthService

    public init(store: SessionStore, service: AuthService) {
        self.store = store
        self.service = service
    }

    /// Keychain-backed store and the real AuthApi.
    public static func live(baseURL: URL, clientHeader: String) -> AuthEnvironment {
        let store = KeychainSessionStore()
        let client = ApiClient(baseURL: baseURL, clientHeader: clientHeader, store: store)
        return AuthEnvironment(store: store, service: AuthApi(client: client, store: store))
    }
}

/// A canned service for previews and snapshot tests. Never touches the network.
public struct PreviewAuthService: AuthService {
    public var registrationOpen: Bool
    public var failure: String?

    public init(registrationOpen: Bool = true, failure: String? = nil) {
        self.registrationOpen = registrationOpen
        self.failure = failure
    }

    public func registrationEnabled() async throws -> Bool { registrationOpen }

    public func login(email: String, password: String) async throws -> StoredSession {
        throw AuthError.invalidCredentials(failure ?? "")
    }

    public func register(email: String, password: String, confirmPassword: String) async throws -> StoredSession {
        throw AuthError.invalidCredentials(failure ?? "")
    }

    public func signInWithGoogle(idToken: String) async throws -> StoredSession {
        throw AuthError.invalidCredentials(failure ?? "")
    }
}
