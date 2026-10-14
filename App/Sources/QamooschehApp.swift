import SwiftUI
import QDesign
import QFeatures

@main
struct QamooschehApp: App {
    private let auth: AuthEnvironment

    private let onboarding: OnboardingEnvironment

    private let lessons: LessonEnvironment

    init() {
        ScriptFonts.registerBundledFonts()
        let baseURL = URL(string: "https://api.parsling.com")!
        let clientHeader = "ios/0.1.0"
        let auth = AuthEnvironment.live(baseURL: baseURL, clientHeader: clientHeader)
        self.auth = auth
        self.onboarding = OnboardingEnvironment.live(baseURL: baseURL, clientHeader: clientHeader, store: auth.store)
        // The lesson's setup loader is the unwired placeholder until the path screen host reads course content; the grader is the
        // placeholder (nothing graded on device) until M1 picks the runtime. Submit goes through the real offline queue.
        self.lessons = LessonEnvironment.live(baseURL: baseURL, clientHeader: clientHeader, store: auth.store)
    }

    var body: some Scene {
        WindowGroup {
            AuthGate(environment: auth) {
                OnboardingGate(environment: onboarding) {
                    RootTabView(lessons: lessons)
                }
            }
        }
    }
}
