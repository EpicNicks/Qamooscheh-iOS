import SwiftUI
import QDesign
import QFeatures

enum AppTab: String, CaseIterable, Identifiable {
    case learn
    case library
    case review
    case leagues
    case profile

    var id: String { rawValue }

    var title: String {
        switch self {
        case .learn: return "Learn"
        case .library: return "Library"
        case .review: return "Review"
        case .leagues: return "Leagues"
        case .profile: return "Profile"
        }
    }

    var systemImage: String {
        switch self {
        case .learn: return "map"
        case .library: return "books.vertical"
        case .review: return "arrow.triangle.2.circlepath"
        case .leagues: return "trophy"
        case .profile: return "person"
        }
    }
}

struct RootTabView: View {
    private let lessons: LessonEnvironment?
    @StateObject private var shell: SignedInShell
    @State private var selection: AppTab
    @State private var lessonRoute: LessonRoute?
    @Environment(\.scenePhase) private var scenePhase

    /// - Parameters:
    ///   - app: the production services; nil renders every tab's empty state (previews, snapshot tests).
    ///   - onboarding: the service behind the Learn tab's course switcher.
    ///   - onSignedOut: called after sign-out or an expired session, so the app can show login again.
    init(
        lessons: LessonEnvironment? = nil,
        app: AppEnvironment? = nil,
        onboarding: OnboardingService? = nil,
        onSignedOut: @escaping @MainActor @Sendable () -> Void = {},
        initialTab: AppTab = .learn
    ) {
        self.lessons = lessons
        _shell = StateObject(wrappedValue: SignedInShell(app: app, onboarding: onboarding, onSignedOut: onSignedOut))
        _selection = State(initialValue: initialTab)
    }

    @ViewBuilder
    private func content(for tab: AppTab) -> some View {
        switch tab {
        case .learn: LearnTab(shell: shell)
        case .library: LibraryTab(shell: shell)
        case .review: ReviewTab(shell: shell)
        case .leagues: LeaguesTab(shell: shell)
        case .profile: ProfileTab(shell: shell)
        }
    }

    private var tabs: some View {
        TabView(selection: $selection) {
            ForEach(AppTab.allCases) { tab in
                content(for: tab)
                    .tabItem { Label(tab.title, systemImage: tab.systemImage) }
                    .tag(tab)
            }
        }
        .environment(\.startLesson, { lessonRoute = $0 })
        .task { await shell.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: CheckpointRefresh.notification)) { _ in
            Task { await shell.refresh() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await shell.refresh() } }
        }
    }

    var body: some View {
        if let lessons = lessons {
            tabs.lessonCover(route: $lessonRoute, environment: lessons, remixHost: { shell.makeRemixHost(route: $0, environment: lessons) })
        } else {
            tabs
        }
    }
}
