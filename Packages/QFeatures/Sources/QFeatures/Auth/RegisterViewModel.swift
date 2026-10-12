import Foundation
import Combine
import QNetwork

/// Registration (web RegisterPage, Android AuthViewModel.register).
@MainActor
public final class RegisterViewModel: ObservableObject {
    @Published public var email: String = "" {
        didSet { clearError() }
    }
    @Published public var password: String = "" {
        didSet { clearError() }
    }
    @Published public var confirmPassword: String = "" {
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

    public var canSubmit: Bool {
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !password.isEmpty && !isSubmitting
    }

    /// The first rule the current input breaks; nil when valid.
    public var validationError: String? {
        if !AuthRules.isPlausibleEmail(email) { return AuthRules.emailInvalid }
        if password != confirmPassword { return AuthRules.passwordMismatch }
        if password.count < AuthRules.minPasswordLength { return AuthRules.passwordTooShort }
        if AuthRules.exceedsLimit(email: email, password: password) { return AuthRules.fieldTooLong }
        return nil
    }

    public func loadRegistrationStatus() async {
        if let enabled = try? await service.registrationEnabled() {
            registrationEnabled = enabled
        }
    }

    public func submit() async {
        guard canSubmit, state != .success else { return }
        if let problem = validationError {
            state = .error(problem)
            return
        }
        let email = self.email
        let password = self.password
        let confirm = self.confirmPassword
        await run(fallback: AuthRules.registerFallback) {
            _ = try await self.service.register(email: email, password: password, confirmPassword: confirm)
        }
    }

    public func signInWithGoogle(idToken: String) async {
        await run(fallback: AuthRules.googleFallback) {
            _ = try await self.service.signInWithGoogle(idToken: idToken)
        }
    }

    public func reportGoogleError(_ message: String) {
        state = .error(message)
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
