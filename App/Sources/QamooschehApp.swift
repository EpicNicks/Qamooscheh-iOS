import SwiftUI
import QFeatures

@main
struct QamooschehApp: App {
    private let auth = AuthEnvironment.live(
        baseURL: URL(string: "https://api.parsling.com")!,
        clientHeader: "ios/0.1.0"
    )

    var body: some Scene {
        WindowGroup {
            AuthGate(environment: auth) {
                RootTabView()
            }
        }
    }
}
