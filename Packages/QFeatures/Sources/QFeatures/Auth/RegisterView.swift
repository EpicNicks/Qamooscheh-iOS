import SwiftUI
import QDesign

/// Create-account screen bound to RegisterViewModel (Android RegisterScreen). Fields are
/// disabled while sign-ups are closed. Passwords are never logged or persisted by the UI.
public struct RegisterView: View {
    private enum Field { case email, password, confirm }

    @ObservedObject private var viewModel: RegisterViewModel
    private let onSignIn: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var focus: Field?

    public init(viewModel: RegisterViewModel, onSignIn: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onSignIn = onSignIn
    }

    private var palette: AppPalette { colorScheme == .dark ? .dark : .light }
    private var closed: Bool { viewModel.registrationEnabled == false }
    private var fieldsEnabled: Bool { !viewModel.isSubmitting && !closed }

    public var body: some View {
        AuthLayout {
            VStack(spacing: Spacing.standard.s3) {
                if closed {
                    AuthNotice(
                        message: "ParsLing is in alpha and closed to new sign-ups right now. Already have an account? Sign in below.",
                        background: palette.warningBg,
                        foreground: palette.text
                    )
                }
                if case .error(let message) = viewModel.state {
                    AuthErrorBanner(message: message, palette: palette)
                }
                AuthFieldBox(label: "Email", palette: palette) {
                    TextField("", text: $viewModel.email)
                        .keyboardType(.emailAddress)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .submitLabel(.next)
                        .focused($focus, equals: .email)
                        .onSubmit { focus = .password }
                        .disabled(!fieldsEnabled)
                        .accessibilityLabel("Email")
                }
                AuthFieldBox(label: "Password", palette: palette) {
                    SecureField("", text: $viewModel.password)
                        .textContentType(.newPassword)
                        .submitLabel(.next)
                        .focused($focus, equals: .password)
                        .onSubmit { focus = .confirm }
                        .disabled(!fieldsEnabled)
                        .accessibilityLabel("Password")
                }
                AuthFieldBox(label: "Confirm password", palette: palette) {
                    SecureField("", text: $viewModel.confirmPassword)
                        .textContentType(.newPassword)
                        .submitLabel(.done)
                        .focused($focus, equals: .confirm)
                        .onSubmit { submit() }
                        .disabled(!fieldsEnabled)
                        .accessibilityLabel("Confirm password")
                }
                AuthPrimaryButton(
                    title: viewModel.isSubmitting ? "Creating account…" : "Create account",
                    palette: palette,
                    enabled: fieldsEnabled && viewModel.canSubmit,
                    action: submit
                )
                AuthFooterLink(prompt: "Already have an account?", action: "Sign in", palette: palette, onTap: onSignIn)
            }
        }
        .task { await viewModel.loadRegistrationStatus() }
    }

    private func submit() {
        focus = nil
        Task { await viewModel.submit() }
    }
}
