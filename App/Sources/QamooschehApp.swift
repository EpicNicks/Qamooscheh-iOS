import SwiftUI
import QDesign
import QFeatures

@main
struct QamooschehApp: App {
    private let auth: AuthEnvironment

    private let onboarding: OnboardingEnvironment

    private let lessons: LessonEnvironment

    private let appEnvironment: AppEnvironment

    /// Bumped on sign-out or an expired session; recreates the gates so they read the cleared session and show login.
    @State private var sessionEpoch = 0

    init() {
        ScriptFonts.registerBundledFonts()
        let baseURL = URL(string: "https://api.parsling.com")!
        let clientHeader = "ios/0.1.0"
        let auth = AuthEnvironment.live(baseURL: baseURL, clientHeader: clientHeader)
        self.auth = auth
        self.onboarding = OnboardingEnvironment.live(baseURL: baseURL, clientHeader: clientHeader, store: auth.store)
        let appEnvironment = AppEnvironment.live(baseURL: baseURL, clientHeader: clientHeader, sessions: auth.store)
        self.appEnvironment = appEnvironment
        // The loader plans checkpoints, stories and remixes; other routes still reach the unwired placeholder until standard lessons
        // are wired. The grader is the placeholder (nothing graded on device) until M1 picks the runtime. Submit goes through the real offline queue.
        let loader = LiveLessonSetupLoader.live(
            baseURL: baseURL, clientHeader: clientHeader, store: auth.store, pinnedCourse: appEnvironment.pinnedCourse)
        var lessonEnvironment = LessonEnvironment.live(
            baseURL: baseURL, clientHeader: clientHeader, store: auth.store, loader: loader,
            onCheckpointSubmitted: { response in CheckpointRefresh.announce(response) })
        // A submitted lesson moves the cursor (and may clear a stowed lesson): tell the Learn tab.
        let submitLesson = lessonEnvironment.submit
        lessonEnvironment.submit = { userId, session in
            let result = try await submitLesson(userId, session)
            LessonSubmitRefresh.announce(result)
            return result
        }
        self.lessons = lessonEnvironment
    }

    var body: some Scene {
        WindowGroup {
            AuthGate(environment: auth) {
                OnboardingGate(environment: onboarding) {
                    RootTabView(
                        lessons: lessons, app: appEnvironment, onboarding: onboarding.service,
                        onSignedOut: { sessionEpoch += 1 })
                }
            }
            .id(sessionEpoch)
            .lowStorageAlert()
        }
    }
}
