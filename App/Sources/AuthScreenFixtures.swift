import SwiftUI
import QFeatures

/// Builds the auth screens against a canned service, for snapshot tests.
@MainActor
enum AuthScreenFixtures {
    static func login(registrationOpen: Bool = true, errorAfterSubmit: Bool = false) async -> AnyView {
        let model = LoginViewModel(service: PreviewAuthService(registrationOpen: registrationOpen, failure: "Wrong email or password."))
        await model.loadRegistrationStatus()
        if errorAfterSubmit {
            model.email = "learner@example.com"
            model.password = "placeholder-secret"
            await model.submit()
        }
        return AnyView(LoginView(viewModel: model, onCreateAccount: {}))
    }

    static func register(registrationOpen: Bool = true) async -> AnyView {
        let model = RegisterViewModel(service: PreviewAuthService(registrationOpen: registrationOpen))
        await model.loadRegistrationStatus()
        return AnyView(RegisterView(viewModel: model, onSignIn: {}))
    }
}
