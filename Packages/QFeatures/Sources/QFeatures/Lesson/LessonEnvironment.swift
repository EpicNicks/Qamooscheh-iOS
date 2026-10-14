import SwiftUI
import QModel
import QDomain
import QNetwork
import QData

// How the app opens a lesson from the path: a route (which skill, practice or not), a loader that turns it into a
// playable setup, and the environment that wires the submit pipeline and the device prefs into a `LessonSession`.

/// Where the learner tapped on the path.
public struct LessonRoute: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var unitKey: String?
    public var skillKey: String
    /// "Practice": played, nothing submitted.
    public var practice: Bool
    /// A test-out of the skills before this one (Android checkpoint), with the "Skipping 3 lessons" line.
    public var checkpointSummary: String?

    public init(id: UUID = UUID(), unitKey: String? = nil, skillKey: String, practice: Bool = false, checkpointSummary: String? = nil) {
        self.id = id
        self.unitKey = unitKey
        self.skillKey = skillKey
        self.practice = practice
        self.checkpointSummary = checkpointSummary
    }

    /// The route a path node's "Start" or "Practice" leads to.
    public static func forNode(_ node: PathCurrentNode, practice: Bool = false) -> LessonRoute {
        return LessonRoute(unitKey: node.unitKey, skillKey: node.skillKey, practice: practice)
    }
}

/// Turns a route into a playable lesson: the session plan, the skills' content from disk and the learner's cards (`buildInstances`).
public protocol LessonSetupLoading: Sendable {
    /// nil when there is nothing to play.
    func setup(for route: LessonRoute) async throws -> LessonSetup?
    func serverPrefs() async -> LessonServerPrefs
    func saveScriptMode(_ mode: ScriptMode) async
}

/// PLACEHOLDER until the path screen host reads course content from disk: every lesson fails to start, visibly, rather than playing fake content.
public struct UnwiredLessonSetupLoader: LessonSetupLoading {
    public struct NotWired: Error, Equatable {}

    public init() {}

    public func setup(for route: LessonRoute) async throws -> LessonSetup? {
        throw NotWired()
    }

    public func serverPrefs() async -> LessonServerPrefs { LessonServerPrefs() }
    public func saveScriptMode(_ mode: ScriptMode) async {}
}

public struct LessonEnvironment {
    public var loader: LessonSetupLoading
    public var userId: @Sendable () async -> String?
    public var prefsStore: LocalPrefsStore
    public var submit: LessonSubmitFunction
    public var loadExtras: @Sendable () async -> LessonResultsExtras
    /// PLACEHOLDER until M1 decides the grader runtime (JavaScriptCore vs a hidden WKWebView over the shared grader build): nil grades nothing, so answers are "checked when you sync".
    public var grader: Grader?
    public var gradingOnDevice: Bool
    public var speech: SpeechService?
    public var courseHints: [String: WordHint]
    public var onFeedback: (FeedbackEvent) -> Void
    public var onInstallVoice: () -> Void
    public var makeReportModel: ((FeedbackReview) -> ReportIssueModel)?

    public init(
        loader: LessonSetupLoading,
        userId: @escaping @Sendable () async -> String?,
        prefsStore: LocalPrefsStore = LocalPrefsStore(),
        submit: @escaping LessonSubmitFunction,
        loadExtras: @escaping @Sendable () async -> LessonResultsExtras = { LessonResultsExtras.none },
        grader: Grader? = PlaceholderGraderSource.grader,
        gradingOnDevice: Bool = PlaceholderGraderSource.gradingOnDevice,
        speech: SpeechService? = nil,
        courseHints: [String: WordHint] = emptyHintMap,
        onFeedback: @escaping (FeedbackEvent) -> Void = { _ in },
        onInstallVoice: @escaping () -> Void = {},
        makeReportModel: ((FeedbackReview) -> ReportIssueModel)? = nil
    ) {
        self.loader = loader
        self.userId = userId
        self.prefsStore = prefsStore
        self.submit = submit
        self.loadExtras = loadExtras
        self.grader = grader
        self.gradingOnDevice = gradingOnDevice
        self.speech = speech
        self.courseHints = courseHints
        self.onFeedback = onFeedback
        self.onInstallVoice = onInstallVoice
        self.makeReportModel = makeReportModel
    }

    /// The real submit pipeline: each finished session is written to the offline queue first, then every unsent session is flushed (Android order), and the server's cards are merged into the device's card store.
    public static func live(
        baseURL: URL,
        clientHeader: String,
        store: SessionStore,
        loader: LessonSetupLoading = UnwiredLessonSetupLoader(),
        speech: SpeechService? = nil,
        onFeedback: @escaping (FeedbackEvent) -> Void = { _ in },
        onInstallVoice: @escaping () -> Void = {}
    ) -> LessonEnvironment {
        let client = ApiClient(baseURL: baseURL, clientHeader: clientHeader, store: store)
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let queue = OfflineQueue(storage: FileOfflineQueueStorage(directory: support.appendingPathComponent("offline-queue", isDirectory: true)))
        let cards = CardStateStore(store: FileContentStore(root: support.appendingPathComponent("content", isDirectory: true)))
        let flusher = QueueFlusher(queue: queue, submitter: LessonRepository(client: client), onSettled: { userId, results in
            _ = try? await cards.merge(userId: userId, cards: results.flatMap { $0.cards })
        })
        let submitter = LessonSubmitter(queue: queue, flusher: flusher)
        return LessonEnvironment(
            loader: loader,
            userId: { await store.load()?.userId },
            submit: { session in
                guard let userId = await store.load()?.userId else { throw LessonEnvironmentError.signedOut }
                return try await submitter.submit(userId: userId, session: session)
            },
            speech: speech,
            onFeedback: onFeedback,
            onInstallVoice: onInstallVoice
        )
    }

    /// A ready session for the route, or nil when there is nothing to play. Throws when the lesson can't be set up.
    public func makeSession(for route: LessonRoute) async throws -> LessonSession? {
        guard var setup = try await loader.setup(for: route), !setup.instances.isEmpty else { return nil }
        if route.practice { setup.practice = true }
        if route.checkpointSummary != nil { setup.checkpointSummary = route.checkpointSummary }
        let id = await userId() ?? ""
        let prefs = prefsStore.current(userId: id)
        let server = await loader.serverPrefs()
        let store = prefsStore
        let loader = self.loader
        let deps = LessonDependencies(
            grader: grader,
            gradingOnDevice: gradingOnDevice,
            submit: submit,
            loadExtras: loadExtras,
            savePrefs: { next in _ = store.update(userId: id) { $0 = next } },
            saveScriptMode: { mode in Task { await loader.saveScriptMode(mode) } },
            speech: speech,
            courseHints: courseHints,
            onFeedback: onFeedback,
            onInstallVoice: onInstallVoice,
            makeReportModel: makeReportModel
        )
        return LessonSession(setup: setup, prefs: prefs, serverPrefs: server, dependencies: deps)
    }
}

public enum LessonEnvironmentError: Error, Equatable, Sendable {
    case signedOut
}

private struct StartLessonKey: EnvironmentKey {
    static let defaultValue: (LessonRoute) -> Void = { _ in }
}

public extension EnvironmentValues {
    /// Called by a path node's Start / Practice / Test-out to open the lesson; the app's shell presents it.
    var startLesson: (LessonRoute) -> Void {
        get { self[StartLessonKey.self] }
        set { self[StartLessonKey.self] = newValue }
    }
}

#if os(iOS)
public extension View {
    /// Presents the lesson for `route` full screen; clearing the route (leave, or back to path) dismisses it.
    func lessonCover(route: Binding<LessonRoute?>, environment: LessonEnvironment) -> some View {
        fullScreenCover(item: route) { current in
            LessonHostView(
                load: { try await environment.makeSession(for: current) },
                onExit: { route.wrappedValue = nil }
            )
        }
    }
}
#endif
