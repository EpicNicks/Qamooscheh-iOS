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
            AuthFlow(environment: environment, onSignedIn: { await refresh() })
        case .signedIn:
            content
        }
    }

    /// Re-reads the store; returns false when it is still empty.
    @discardableResult
    private func refresh() async -> Bool {
        let session = await environment.store.load()
        phase = session == nil ? .signedOut : .signedIn
        return session != nil
    }
}

/// Login and register, switching between them in place.
struct AuthFlow: View {
    @StateObject private var login: LoginViewModel
    @StateObject private var register: RegisterViewModel
    @State private var showingRegister = false
    /// Returns false when no session was stored after the sign-in.
    private let onSignedIn: () async -> Bool

    init(environment: AuthEnvironment, onSignedIn: @escaping () async -> Bool) {
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
            if state == .success { Task { let saved = await onSignedIn(); if !saved { login.sessionNotSaved() } } }
        }
        .onChange(of: register.state) { _, state in
            if state == .success { Task { let saved = await onSignedIn(); if !saved { register.sessionNotSaved() } } }
        }
    }
}
