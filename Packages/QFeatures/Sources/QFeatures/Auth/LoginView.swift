import SwiftUI
import QDesign

/// Sign-in screen bound to LoginViewModel (Android LoginScreen). Passwords stay in the
/// view model's memory only; they are never logged or persisted by the UI.
public struct LoginView: View {
    private enum Field { case email, password }

    @ObservedObject private var viewModel: LoginViewModel
    private let onCreateAccount: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var focus: Field?

    public init(viewModel: LoginViewModel, onCreateAccount: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onCreateAccount = onCreateAccount
    }

    private var palette: AppPalette { colorScheme == .dark ? .dark : .light }

    public var body: some View {
        AuthLayout {
            VStack(spacing: Spacing.standard.s3) {
                if viewModel.registrationEnabled == false {
                    AuthNotice(
                        message: "ParsLing is in alpha. Sign-ups are closed for now: if you've been given an account, sign in below.",
                        background: palette.warningBg,
                        foreground: palette.text
                    )
                }
                if case .error(let message) = viewModel.state {
                    AuthErrorBanner(message: message, palette: palette)
                }
                AuthFieldBox(label: "Email", palette: palette) {
                    TextField("", text: $viewModel.email)
                        .authField(.email)
                        .submitLabel(.next)
                        .focused($focus, equals: .email)
                        .onSubmit { focus = .password }
                        .disabled(viewModel.isSubmitting)
                        .accessibilityLabel("Email")
                }
                AuthFieldBox(label: "Password", palette: palette) {
                    SecureField("", text: $viewModel.password)
                        .authField(.password)
                        .submitLabel(.done)
                        .focused($focus, equals: .password)
                        .onSubmit { submit() }
                        .disabled(viewModel.isSubmitting)
                        .accessibilityLabel("Password")
                }
                AuthPrimaryButton(
                    title: viewModel.isSubmitting ? "Signing in…" : "Sign in",
                    palette: palette,
                    enabled: viewModel.canSubmit,
                    action: submit
                )
                AuthFooterLink(prompt: "New here?", action: "Create an account", palette: palette, onTap: onCreateAccount)
            }
        }
        .task { await viewModel.loadRegistrationStatus() }
    }

    private func submit() {
        focus = nil
        Task { await viewModel.submit() }
    }
}
