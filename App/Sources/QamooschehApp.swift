import SwiftUI
import QDesign
import QFeatures

@main
struct QamooschehApp: App {
    private let auth: AuthEnvironment

    private let onboarding: OnboardingEnvironment

    init() {
        ScriptFonts.registerBundledFonts()
        let baseURL = URL(string: "https://api.parsling.com")!
        let clientHeader = "ios/0.1.0"
        let auth = AuthEnvironment.live(baseURL: baseURL, clientHeader: clientHeader)
        self.auth = auth
        self.onboarding = OnboardingEnvironment.live(baseURL: baseURL, clientHeader: clientHeader, store: auth.store)
    }

    var body: some Scene {
        WindowGroup {
            AuthGate(environment: auth) {
                OnboardingGate(environment: onboarding) {
                    RootTabView()
                }
            }
        }
    }
}
