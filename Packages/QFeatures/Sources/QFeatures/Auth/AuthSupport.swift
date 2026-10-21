import Foundation
import QNetwork

/// The calls the login and register view models need; `AuthApi` conforms.
public protocol AuthService: Sendable {
    func registrationEnabled() async throws -> Bool
    func login(email: String, password: String) async throws -> StoredSession
    func register(email: String, password: String, confirmPassword: String) async throws -> StoredSession
    func signInWithGoogle(idToken: String) async throws -> StoredSession
}

extension AuthApi: AuthService {}

/// Where a submit stands. Editing a field after a failure returns to `idle`.
public enum AuthSubmitState: Equatable, Sendable {
    case idle
    case submitting
    case error(String)
    case success
}

/// Validation limits and user-visible strings (web pages, Android AuthViewModel, AuthContracts.cs).
public enum AuthRules {
    /// RegisterRequest's MinLength(8).
    public static let minPasswordLength = 8
    /// MaxLength(256) on email and password.
    public static let maxFieldLength = 256

    public static let loginFallback = "Couldn't sign in: check your email and password."
    public static let registerFallback = "Couldn't create an account: that email may already be registered."
    public static let googleFallback = "Couldn't sign in with Google."
    public static let passwordMismatch = "Passwords don't match."
    public static let passwordTooShort = "Use at least 8 characters for your password."
    public static let emailInvalid = "Enter a valid email address."
    public static let fieldTooLong = "Email and password must be at most 256 characters."
    public static let tooManyRequests = "Too many attempts. Wait a minute and try again."
    public static let sessionNotSaved = "Signed in, but this device couldn't save your session. Please try again."
    public static let offline = "Couldn't reach the server. Check your connection and try again."

    /// Lenient, like .NET's EmailAddressAttribute: one "@" with text on both sides, no spaces.
    public static func isPlausibleEmail(_ email: String) -> Bool {
        let value = email.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty || value.contains(where: { $0.isWhitespace }) { return false }
        let parts = value.split(separator: "@", omittingEmptySubsequences: false)
        return parts.count == 2 && !parts[0].isEmpty && !parts[1].isEmpty
    }

    static func exceedsLimit(email: String, password: String) -> Bool {
        email.count > maxFieldLength || password.count > maxFieldLength
    }

    /// Android `userMessage(fallback)`: the server's text, else the 429 text, else offline text, else `fallback`.
    public static func message(for error: Error, fallback: String) -> String {
        if let auth = error as? AuthError {
            switch auth {
            case .invalidCredentials(let m), .emailTaken(let m), .registrationClosed(let m), .validation(let m):
                return nonEmpty(m) ?? fallback
            case .tooManyAttempts(let m):
                return nonEmpty(m) ?? tooManyRequests
            case .sessionNotSaved:
                return sessionNotSaved
            case .other(let api):
                return message(for: api, fallback: fallback)
            }
        }
        if let api = error as? ApiError {
            if let text = nonEmpty(api.body?.error) { return text }
            return api.status == 429 ? tooManyRequests : fallback
        }
        if error is URLError { return offline }
        return fallback
    }

    private static func nonEmpty(_ s: String?) -> String? {
        guard let s = s, !s.isEmpty else { return nil }
        return s
    }
}
