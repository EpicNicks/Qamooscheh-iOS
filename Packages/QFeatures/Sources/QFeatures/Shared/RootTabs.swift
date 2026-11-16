import SwiftUI
import QModel
import QDomain
import QDesign
import Combine

// The five tab bodies behind the app's TabView. Each owns its NavigationStack path; pushes use `AppRoute`.

/// Learn: the Path (header, update banner, the road, Stow). Its buttons open lessons through the root's lesson cover and
/// push screens on this tab's stack.
public struct LearnTab: View {
    @ObservedObject private var shell: SignedInShell
    @StateObject private var host: PathHostModel
    @State private var switcher: CourseSwitcherModel?
    @State private var presenting = false
    @State private var path: [AppRoute] = []
    @Environment(\.startLesson) private var startLesson

    public init(shell: SignedInShell) {
        self.shell = shell
        _host = StateObject(wrappedValue: PathHostModel(shell: shell))
    }

    public var body: some View {
        NavigationStack(path: $path) {
            PathScreen(
                model: host.path,
                download: host.download,
                themeIndex: host.themeIndex,
                header: PathHeaderInfo(courseName: shell.courseName, streakDays: shell.streakDays, totalXp: shell.totalXp),
                updateBanner: host.banner,
                navigator: AppPathNavigator(startLesson: startLesson, push: { path.append($0) }),
                stowFlow: host.stowFlow,
                stowReminder: host.stowReminder,
                onRetryDownload: { host.retryDownload() },
                onPickCourse: openSwitcher,
                onUpdate: { Task { await host.openRollForward() } },
                onConfirmUpdate: { _ = host.confirmRollForward() })
                .navigationTitle("Learn")
                .navigationDestination(for: AppRoute.self) { route in
                    AppRouteDestination(route: route, shell: shell, path: $path)
                }
                .sheet(isPresented: $presenting) {
                    if let model = switcher {
                        CourseSwitcherView(model: model)
                    }
                }
        }
        .onReceive(shell.$bootstrap.compactMap { $0 }) { bootstrap in
            Task { await host.bootstrapChanged(bootstrap) }
        }
        .onReceive(NotificationCenter.default.publisher(for: ReaderCompletionRefresh.notification)) { _ in
            Task { await shell.refresh() }
        }
        .onReceive(NotificationCenter.default.publisher(for: LessonSubmitRefresh.notification)) { note in
            if let key = LessonSubmitRefresh.completedSkillKey(in: note) { host.lessonFinished(key) }
            if let key = LessonSubmitRefresh.stowCleared(in: note) {
                Task { await host.stowCleared(key) }
            }
        }
    }

    private func openSwitcher() {
        guard let model = shell.makeSwitcherModel(onSwitched: { presenting = false }) else { return }
        switcher = model
        presenting = true
    }
}

/// Library: Themes and Glossary.
public struct LibraryTab: View {
    @ObservedObject private var shell: SignedInShell
    @State private var path: [AppRoute] = []

    public init(shell: SignedInShell) {
        self.shell = shell
    }

    public var body: some View {
        NavigationStack(path: $path) {
            List(AppRoute.libraryEntries, id: \.self) { route in
                NavigationLink(value: route) { Text(route.title) }
                    .frame(minHeight: 44)
            }
            .navigationTitle("Library")
            .navigationDestination(for: AppRoute.self) { route in
                AppRouteDestination(route: route, shell: shell, path: $path)
            }
        }
    }
}

/// Review: Flashcards and Vocabulary.
public struct ReviewTab: View {
    @ObservedObject private var shell: SignedInShell
    @State private var path: [AppRoute] = []

    public init(shell: SignedInShell) {
        self.shell = shell
    }

    public var body: some View {
        NavigationStack(path: $path) {
            List(AppRoute.reviewEntries, id: \.self) { route in
                NavigationLink(value: route) { Text(route.title) }
                    .frame(minHeight: 44)
            }
            .navigationTitle("Review")
            .navigationDestination(for: AppRoute.self) { route in
                AppRouteDestination(route: route, shell: shell, path: $path)
            }
        }
    }
}

/// Leagues.
public struct LeaguesTab: View {
    @ObservedObject private var shell: SignedInShell

    public init(shell: SignedInShell) {
        self.shell = shell
    }

    public var body: some View {
        NavigationStack {
            LeaguesView(model: shell.leagues)
        }
    }
}

/// Profile, with links to Settings, Friends, Help, About and the streak share card.
public struct ProfileTab: View {
    @ObservedObject private var shell: SignedInShell
    @State private var path: [AppRoute] = []

    public init(shell: SignedInShell) {
        self.shell = shell
    }

    public var body: some View {
        NavigationStack(path: $path) {
            ProfileView(
                model: shell.profile,
                links: AppRoute.profileLinks.map { route in
                    ProfileLink(route.title) { path.append(route) }
                })
                .navigationDestination(for: AppRoute.self) { route in
                    AppRouteDestination(route: route, shell: shell, path: $path)
                }
        }
    }
}

/// The screen an `AppRoute` opens.
struct AppRouteDestination: View {
    let route: AppRoute
    @ObservedObject var shell: SignedInShell
    @Binding var path: [AppRoute]
    @Environment(\.startLesson) private var rootStartLesson

    /// Opens a lesson from this tab, first putting the stack where the lesson's origin returns to (a library page
    /// pops the story reader above it instead of leaving it behind the cover).
    private func startLesson(_ lesson: LessonRoute) {
        path = lesson.origin.stackForLesson(path)
        rootStartLesson(lesson)
    }

    var body: some View {
        switch route {
        case .themes:
            LibraryView(
                model: shell.library, onOpenTopic: { path.append(.topic($0)) },
                onRemix: { startLesson(LessonRoute.forRemix(themeIds: $0).from(.themes)) },
                onOpenSideLibrary: { path.append(.sideLibrary($0)) })
        case .sideLibrary(let kind):
            SideLibraryDestination(
                shell: shell, kind: kind,
                navigator: AppPathNavigator(origin: .sideLibrary(kind), startLesson: startLesson, push: { path.append($0) }))
        case .topic(let id):
            TopicDestination(themeId: id, shell: shell, startLesson: startLesson)
        case .glossary:
            GlossaryDestination(shell: shell)
        case .flashcards:
            FlashcardsScreen(model: shell.flashcards, onBack: { if !path.isEmpty { path.removeLast() } })
        case .vocabulary:
            VocabularyDestination(shell: shell, unitKey: "", skillKey: nil)
        case .skillVocabulary(let unitKey, let skillKey):
            VocabularyDestination(shell: shell, unitKey: unitKey, skillKey: skillKey)
        case .savedPractice:
            SavedPracticeDestination(
                shell: shell, onBack: { if !path.isEmpty { path.removeLast() } },
                onExercises: { startLesson(LessonRoute.forSavedPractice($0)) })
        case .settings:
            SettingsDestination(shell: shell, onOpenHelp: { path.append(.help) })
        case .friends:
            FriendsView(model: shell.friends, contacts: shell.contactsMatching)
        case .help:
            HelpView()
        case .about:
            AboutView(version: appVersion())
        case .storyReader(let unitKey, let skillKey, let practice, let origin):
            StoryReaderDestination(
                shell: shell, unitKey: unitKey, skillKey: skillKey, practice: practice, origin: origin,
                startLesson: startLesson)
        case .shareStreak:
            ShareCardPreview(content: ShareCardContent(kind: .streak, streakDays: shell.streakDays))
                .navigationTitle(route.title)
        }
    }

    private func appVersion() -> String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }
}

/// The story reader; its button opens the story's existing cloze lessons through the root's lesson cover.
struct StoryReaderDestination: View {
    @StateObject private var model: StoryReaderModel
    private let unitKey: String
    private let skillKey: String
    private let practice: Bool
    private let origin: LessonOrigin
    private let startLesson: (LessonRoute) -> Void

    init(
        shell: SignedInShell, unitKey: String, skillKey: String, practice: Bool = false, origin: LessonOrigin = .path,
        startLesson: @escaping (LessonRoute) -> Void
    ) {
        self.practice = practice
        self.origin = origin
        self.startLesson = startLesson
        self.unitKey = unitKey
        self.skillKey = skillKey
        let app = shell.app
        _model = StateObject(wrappedValue: StoryReaderModel(
            unitKey: unitKey, skillKey: skillKey, services: app?.storyReader, starred: shell.vocabulary,
            userId: { await app?.currentUserId() }))
    }

    var body: some View {
        StoryReaderScreen(model: model, onCloze: { startLesson(LessonRoute(unitKey: unitKey, skillKey: skillKey, practice: practice, origin: origin)) })
    }
}

/// A story or listening page. A lesson opens like a tap on the road: a story in its reader, a listening lesson in the
/// lesson player, a finished one as local practice. The library is unlocked by unit, so the rows it lets through are open.
struct SideLibraryDestination: View {
    @StateObject private var model: SideLibraryModel
    private let navigator: PathNavigator

    init(shell: SignedInShell, kind: SideLibraryKind, navigator: PathNavigator) {
        self.navigator = navigator
        _model = StateObject(wrappedValue: SideLibraryModel(
            kind: kind, repository: shell.app?.path?.repository, bootstrap: { [weak shell] in shell?.bootstrap }))
    }

    var body: some View {
        SideLibraryView(model: model, onOpen: { navigator.openSide($0, locked: false) })
    }
}

struct TopicDestination: View {
    @StateObject private var model: TopicModel
    private let startLesson: (LessonRoute) -> Void

    init(themeId: String, shell: SignedInShell, startLesson: @escaping (LessonRoute) -> Void) {
        self.startLesson = startLesson
        _model = StateObject(wrappedValue: TopicModel(themeId: themeId, source: shell.app?.themes))
    }

    var body: some View {
        TopicView(model: model, onStartLesson: { startLesson(LessonRoute(skillKey: $0, origin: .topic)) })
    }
}

struct GlossaryDestination: View {
    @StateObject private var model: GlossaryModel

    init(shell: SignedInShell) {
        _model = StateObject(wrappedValue: GlossaryModel(
            courseCode: shell.course?.code, glossary: shell.app?.glossary ?? loadGlossary()))
    }

    var body: some View {
        GlossaryScreen(model: model)
    }
}

struct VocabularyDestination: View {
    @StateObject private var model: SkillVocabularyModel

    /// An empty `unitKey` offers the whole course.
    init(shell: SignedInShell, unitKey: String, skillKey: String?) {
        _model = StateObject(wrappedValue: SkillVocabularyModel(store: shell.vocabulary, unitKey: unitKey, skillKey: skillKey))
    }

    var body: some View {
        SkillVocabularyScreen(model: model)
    }
}

/// Saved-words practice: the cards, then the picked exercises on the lesson screen.
struct SavedPracticeDestination: View {
    @StateObject private var model: SavedPracticeModel
    let onBack: () -> Void
    let onExercises: (SavedPracticeExercises) -> Void

    init(shell: SignedInShell, onBack: @escaping () -> Void, onExercises: @escaping (SavedPracticeExercises) -> Void) {
        self.onBack = onBack
        self.onExercises = onExercises
        _model = StateObject(wrappedValue: SavedPracticeModel(
            store: shell.vocabulary, source: shell.app?.savedPractice, submitter: shell.app?.flashcards,
            cloze: shell.app.map { ClozeServices.live(app: $0) },
            onUnauthorized: shell.unauthorizedHandler))
    }

    var body: some View {
        SavedPracticeScreen(model: model, onBack: onBack, onExercises: onExercises)
    }
}

/// Settings. The model is built once the user and course are known; leaving the screen stops any voice sample.
struct SettingsDestination: View {
    @ObservedObject var shell: SignedInShell
    let onOpenHelp: () -> Void
    @State private var model: SettingsModel?
    @State private var unavailable = false

    var body: some View {
        Group {
            if let model = model {
                SettingsView(model: model, onOpenHelp: onOpenHelp)
            } else if unavailable {
                Text("Pick a course to open settings.")
                    .font(.callout)
                    .padding(16)
            } else {
                ProgressView().accessibilityLabel("Loading")
            }
        }
        .task {
            if model == nil {
                model = await shell.makeSettingsModel()
                unavailable = model == nil
            }
        }
        .onDisappear { shell.stopVoicePreview() }
    }
}
