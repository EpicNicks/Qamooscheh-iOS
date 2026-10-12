import Foundation
import Combine
import QNetwork

/// Login (web LoginPage, Android AuthViewModel). Success only saves the session
/// (AuthApi does that); the app root observes the store and leaves the auth screens.
@MainActor
public final class LoginViewModel: ObservableObject {
    @Published public var email: String = "" {
        didSet { clearError() }
    }
    @Published public var password: String = "" {
        didSet { clearError() }
    }
    @Published public private(set) var state: AuthSubmitState = .idle
    /// nil until the status answers; false shows the closed-alpha notice. A failed check leaves nil.
    @Published public private(set) var registrationEnabled: Bool?

    private let service: AuthService

    public init(service: AuthService) {
        self.service = service
    }

    public var isSubmitting: Bool { state == .submitting }

    /// Android: blank email or empty password is a silent no-op.
    public var canSubmit: Bool {
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !password.isEmpty && !isSubmitting && state != .success
    }

    public func loadRegistrationStatus() async {
        if let enabled = try? await service.registrationEnabled() {
            registrationEnabled = enabled
        }
    }

    public func submit() async {
        guard canSubmit, state != .success else { return }
        if AuthRules.exceedsLimit(email: email, password: password) {
            state = .error(AuthRules.fieldTooLong)
            return
        }
        let email = self.email
        let password = self.password
        await run(fallback: AuthRules.loginFallback) {
            _ = try await self.service.login(email: email, password: password)
        }
    }

    public func signInWithGoogle(idToken: String) async {
        await run(fallback: AuthRules.googleFallback) {
            _ = try await self.service.signInWithGoogle(idToken: idToken)
        }
    }

    /// Only applies when idle or already showing an error; never overrides an in-flight submit or a success.
    public func reportGoogleError(_ message: String) {
        switch state {
        case .idle, .error:
            state = .error(message)
        case .submitting, .success:
            break
        }
    }

    /// The service reported success but the session store is empty (e.g. a failed Keychain write).
    /// Returns to a retryable error so the user is not stuck on a dead button.
    public func sessionNotSaved() {
        if state == .success { state = .error(AuthRules.sessionNotSaved) }
    }

    public func clearError() {
        if case .error = state { state = .idle }
    }

    private func run(fallback: String, _ action: () async throws -> Void) async {
        if state == .submitting || state == .success { return }
        state = .submitting
        do {
            try await action()
            state = .success
        } catch is CancellationError {
            state = .idle
        } catch {
            state = .error(AuthRules.message(for: error, fallback: fallback))
        }
    }
}
