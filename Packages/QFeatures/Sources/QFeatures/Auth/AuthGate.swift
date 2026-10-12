import SwiftUI
import QNetwork

/// Shows the app content when the SessionStore holds a session, else login (with a link to register).
/// A successful sign-in re-reads the store. Sign-out and session expiry are not observed yet.
public struct AuthGate<Content: View>: View {
    private enum Phase { case loading, signedOut, signedIn }

    private let environment: AuthEnvironment
    private let content: Content
    @State private var phase: Phase = .loading

    public init(environment: AuthEnvironment, @ViewBuilder content: () -> Content) {
        self.environment = environment
        self.content = content()
    }

    public var body: some View {
        switch phase {
        case .loading:
            ProgressView()
                .task { await refresh() }
        case .signedOut:
            AuthFlow(environment: environment, onSignedIn: { Task { await refresh() } })
        case .signedIn:
            content
        }
    }

    private func refresh() async {
        let session = await environment.store.load()
        phase = session == nil ? .signedOut : .signedIn
    }
}

/// Login and register, switching between them in place.
struct AuthFlow: View {
    @StateObject private var login: LoginViewModel
    @StateObject private var register: RegisterViewModel
    @State private var showingRegister = false
    private let onSignedIn: () -> Void

    init(environment: AuthEnvironment, onSignedIn: @escaping () -> Void) {
        _login = StateObject(wrappedValue: LoginViewModel(service: environment.service))
        _register = StateObject(wrappedValue: RegisterViewModel(service: environment.service))
        self.onSignedIn = onSignedIn
    }

    var body: some View {
        Group {
            if showingRegister {
                RegisterView(viewModel: register, onSignIn: { showingRegister = false })
            } else {
                LoginView(viewModel: login, onCreateAccount: { showingRegister = true })
            }
        }
        .onChange(of: login.state) { _, state in
            if state == .success { onSignedIn() }
        }
        .onChange(of: register.state) { _, state in
            if state == .success { onSignedIn() }
        }
    }
}
