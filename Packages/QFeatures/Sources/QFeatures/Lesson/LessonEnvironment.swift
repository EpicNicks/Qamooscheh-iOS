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
    /// A test-out to this skill: the loader plans it (`CheckpointRepository.plan`, then `CheckpointLogic.setup`) instead of the cursor's lesson.
    public var checkpoint: Bool
    /// Non-nil for a remix: the topics to blend (the loader picks the lessons).
    public var remixThemeIds: [String]?
    /// Non-nil for saved-words practice: the exact exercises to play, in order (the server picked them).
    public var exerciseRefs: [StarredPracticeExercise]?
    /// The course version the server picked `exerciseRefs` against; the loader refuses a different one.
    public var exerciseCourseVersion: Int?
    /// Non-nil for a Deep Dive remix: the standard lesson to blend more of (the loader finds its topics and picks the other lessons).
    public var deepDiveLessonKey: String?
    /// What a remix holds, once the learner has chosen; nil until then (the cover asks first).
    public var remixContents: RemixContents?
    /// Fill in the blank without typo tolerance; only read when the remix holds cloze cards.
    public var hardcore: Bool

    public init(id: UUID = UUID(), unitKey: String? = nil, skillKey: String, practice: Bool = false, checkpointSummary: String? = nil, checkpoint: Bool = false, remixThemeIds: [String]? = nil, exerciseRefs: [StarredPracticeExercise]? = nil, exerciseCourseVersion: Int? = nil, deepDiveLessonKey: String? = nil, remixContents: RemixContents? = nil, hardcore: Bool = false) {
        self.id = id
        self.unitKey = unitKey
        self.skillKey = skillKey
        self.practice = practice
        self.checkpointSummary = checkpointSummary
        self.checkpoint = checkpoint
        self.remixThemeIds = remixThemeIds
        self.exerciseRefs = exerciseRefs
        self.exerciseCourseVersion = exerciseCourseVersion
        self.deepDiveLessonKey = deepDiveLessonKey
        self.remixContents = remixContents
        self.hardcore = hardcore
    }

    /// Whether this route is a remix of topics, picked or found from a lesson (a Deep Dive).
    public var isRemix: Bool { return remixThemeIds != nil || deepDiveLessonKey != nil }

    /// A remix whose contents the learner hasn't chosen yet: the cover shows the contents picker first.
    public var needsContentsChoice: Bool { return isRemix && remixContents == nil }

    /// This remix route with what it holds chosen.
    public func choosing(_ contents: RemixContents, hardcore: Bool) -> LessonRoute {
        var chosen = self
        chosen.remixContents = contents
        chosen.hardcore = hardcore
        return chosen
    }

    /// The route the saved-words practice's "Continue" leads to.
    public static func forSavedPractice(_ picked: SavedPracticeExercises) -> LessonRoute {
        // The picked set is part of the skill key, so an abandoned run's draft is only offered for the same set (the draft key has no other room for it).
        let skillKey = "saved-practice-v\(picked.courseVersion)-" + stableDigest(picked.exercises)
        return LessonRoute(skillKey: skillKey, exerciseRefs: picked.refs, exerciseCourseVersion: picked.courseVersion)
    }

    /// The route the Library's remix picker leads to.
    public static func forRemix(themeIds: [String], contents: RemixContents? = nil, hardcore: Bool = false) -> LessonRoute {
        return LessonRoute(skillKey: "remix", remixThemeIds: themeIds, remixContents: contents, hardcore: hardcore)
    }

    /// The route a Deep Dive sheet's "Remix all topics" leads to: more like `lessonKey`, from the topics it touches.
    public static func forDeepDive(lessonKey: String, contents: RemixContents? = nil, hardcore: Bool = false) -> LessonRoute {
        return LessonRoute(skillKey: "remix-" + lessonKey, deepDiveLessonKey: lessonKey, remixContents: contents, hardcore: hardcore)
    }

    /// The route a path node's "Test out" leads to: `unitKey`/`skillKey` name the position to jump to.
    public static func forCheckpoint(unitKey: String, skillKey: String) -> LessonRoute {
        return LessonRoute(unitKey: unitKey, skillKey: skillKey, checkpoint: true)
    }

    /// The route a path node's "Start" or "Practice" leads to.
    public static func forNode(_ node: PathCurrentNode, practice: Bool = false) -> LessonRoute {
        return LessonRoute(unitKey: node.unitKey, skillKey: node.skillKey, practice: practice)
    }
}

/// FNV-1a over the UTF-8 bytes, in hex: stable across launches (unlike `Hasher`), so it can name a draft.
func stableDigest(_ text: String) -> String {
    var hash: UInt64 = 0xcbf29ce484222325
    for byte in text.utf8 {
        hash ^= UInt64(byte)
        hash = hash &* 0x100000001b3
    }
    return String(hash, radix: 16)
}

/// Turns a route into a playable lesson: the session plan, the skills' content from disk and the learner's cards (`buildInstances`).
public protocol LessonSetupLoading: Sendable {
    /// nil when there is nothing to play.
    func setup(for route: LessonRoute) async throws -> LessonSetup?
    /// What a remix route's fill-in-the-blank round is cut from; nil when the route isn't a remix.
    func remixCloze(for route: LessonRoute) async throws -> RemixClozePool?
    func serverPrefs() async -> LessonServerPrefs
    func saveScriptMode(_ mode: ScriptMode) async
}

public extension LessonSetupLoading {
    func remixCloze(for route: LessonRoute) async throws -> RemixClozePool? { return nil }
}

/// The exercises of a remix's lessons and the words its fill-in-the-blank cards are cut from, due words first (`remixClozeTags`).
public struct RemixClozePool: Equatable, Sendable {
    public var courseCode: String
    public var exercises: [ExerciseArtifact]
    public var tags: [String]

    public init(courseCode: String, exercises: [ExerciseArtifact], tags: [String]) {
        self.courseCode = courseCode
        self.exercises = exercises
        self.tags = tags
    }
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

/// Submit and write-ahead functions that take the user the lesson was started for (resolved once, before the lesson begins).
public typealias LessonUserSubmitFunction = @Sendable (String, SubmittedSession) async throws -> LessonSubmitResult
public typealias LessonUserEnqueueFunction = @Sendable (String, SubmittedSession) async throws -> Void
public typealias CheckpointUserSubmitFunction = @Sendable (String, SubmitCheckpointRequest) async throws -> CheckpointSubmitResponse

public struct LessonEnvironment {
    public var loader: LessonSetupLoading
    public var userId: @Sendable () async -> String?
    public var prefsStore: LocalPrefsStore
    public var submit: LessonUserSubmitFunction
    public var enqueue: LessonUserEnqueueFunction
    /// Sends a checkpoint for the user it was started for; nil leaves checkpoints unable to submit.
    public var submitCheckpoint: CheckpointUserSubmitFunction?
    /// Where in-progress lessons are kept; nil keeps none.
    public var draftDirectory: URL?
    public var loadExtras: @Sendable () async -> LessonResultsExtras
    /// PLACEHOLDER until M1 decides the grader runtime (JavaScriptCore vs a hidden WKWebView over the shared grader build): nil grades nothing, so answers are "checked when you sync".
    public var grader: Grader?
    public var gradingOnDevice: Bool
    public var speech: SpeechService?
    public var courseHints: [String: WordHint]
    public var onFeedback: (FeedbackEvent) -> Void
    /// Sounds and haptics for feedback events; nil plays none.
    public var effects: FeedbackEffects?
    public var onInstallVoice: () -> Void
    public var makeReportModel: ((FeedbackReview) -> ReportIssueModel)?

    public init(
        loader: LessonSetupLoading,
        userId: @escaping @Sendable () async -> String?,
        prefsStore: LocalPrefsStore = LocalPrefsStore(),
        submit: @escaping LessonUserSubmitFunction,
        enqueue: @escaping LessonUserEnqueueFunction = { _, _ in },
        submitCheckpoint: CheckpointUserSubmitFunction? = nil,
        draftDirectory: URL? = nil,
        loadExtras: @escaping @Sendable () async -> LessonResultsExtras = { LessonResultsExtras.none },
        grader: Grader? = PlaceholderGraderSource.grader,
        gradingOnDevice: Bool = PlaceholderGraderSource.gradingOnDevice,
        speech: SpeechService? = nil,
        courseHints: [String: WordHint] = emptyHintMap,
        onFeedback: @escaping (FeedbackEvent) -> Void = { _ in },
        effects: FeedbackEffects? = nil,
        onInstallVoice: @escaping () -> Void = {},
        makeReportModel: ((FeedbackReview) -> ReportIssueModel)? = nil
    ) {
        self.loader = loader
        self.userId = userId
        self.prefsStore = prefsStore
        self.submit = submit
        self.enqueue = enqueue
        self.submitCheckpoint = submitCheckpoint
        self.draftDirectory = draftDirectory
        self.loadExtras = loadExtras
        self.grader = grader
        self.gradingOnDevice = gradingOnDevice
        self.speech = speech
        self.courseHints = courseHints
        self.onFeedback = onFeedback
        self.effects = effects
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
        effects: FeedbackEffects? = .shared,
        onInstallVoice: @escaping () -> Void = {},
        onCheckpointSubmitted: @escaping @Sendable (CheckpointSubmitResponse) async -> Void = { _ in }
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
        let checkpoints = CheckpointRepository(client: client)
        return LessonEnvironment(
            loader: loader,
            userId: { await store.load()?.userId },
            submit: { userId, session in
                try await submitter.submit(userId: userId, session: session)
            },
            enqueue: { userId, session in
                _ = try await queue.enqueue(userId: userId, session: session)
            },
            submitCheckpoint: { userId, request in
                let response = try await checkpoints.submit(request)
                // The server moved the learner's cards; a pass also moves the cursor (the caller refreshes the bootstrap).
                _ = try? await cards.merge(userId: userId, cards: response.cards)
                await onCheckpointSubmitted(response)
                return response
            },
            draftDirectory: support.appendingPathComponent("lesson-drafts", isDirectory: true),
            speech: speech,
            onFeedback: onFeedback,
            effects: effects,
            onInstallVoice: onInstallVoice
        )
    }

    /// A ready session for the route, or nil when there is nothing to play. Throws when the lesson can't be set up.
    public func makeSession(for route: LessonRoute) async throws -> LessonSession? {
        // The queue is per user: with nobody signed in the lesson must not start, because its answers would have nowhere to be saved.
        guard let id = await userId(), !id.isEmpty else { throw LessonEnvironmentError.signedOut }
        guard var setup = try await loader.setup(for: route) else { return nil }
        // A checkpoint with nothing left to test is still submitted, to move the learner on.
        if setup.instances.isEmpty && setup.checkpoint?.requiresTest != false { return nil }
        if route.practice { setup.practice = true }
        if route.checkpointSummary != nil { setup.checkpointSummary = route.checkpointSummary }
        let prefs = prefsStore.current(userId: id)
        let server = await loader.serverPrefs()
        let store = prefsStore
        let loader = self.loader
        let submit = self.submit
        let enqueue = self.enqueue
        var checkpointSend: CheckpointSubmitFunction?
        if let send = self.submitCheckpoint {
            checkpointSend = { request in try await send(id, request) }
        }
        var draft = LessonDraftStore.none
        var practiceDraft: LessonDraftStore?
        if let directory = draftDirectory {
            let key = LessonDraftStore.key(
                userId: id, courseCode: setup.courseCode, unitKey: route.unitKey, skillKey: route.skillKey,
                practice: setup.practice, checkpoint: setup.isCheckpoint
            )
            draft = LessonDraftStore.file(directory: directory, key: key)
            if !setup.practice {
                let practiceKey = LessonDraftStore.key(
                    userId: id, courseCode: setup.courseCode, unitKey: route.unitKey, skillKey: route.skillKey,
                    practice: true, checkpoint: setup.isCheckpoint
                )
                practiceDraft = LessonDraftStore.file(directory: directory, key: practiceKey)
            }
        }
        let deps = LessonDependencies(
            grader: grader,
            gradingOnDevice: gradingOnDevice,
            submit: { session in try await submit(id, session) },
            enqueue: { session in try await enqueue(id, session) },
            draft: draft,
            practiceDraft: practiceDraft,
            onLessonCounted: { _ = store.update(userId: id) { $0.lessonsCompleted += 1 } },
            loadExtras: loadExtras,
            savePrefs: { next in _ = store.update(userId: id) { $0 = next } },
            saveScriptMode: { mode in Task { await loader.saveScriptMode(mode) } },
            speech: speech,
            courseHints: courseHints,
            onFeedback: onFeedback,
            effects: effects,
            onInstallVoice: onInstallVoice,
            makeReportModel: makeReportModel,
            submitCheckpoint: checkpointSend
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
    /// A remix asks what it should hold first, through the model `remixHost` makes for it.
    func lessonCover(route: Binding<LessonRoute?>, environment: LessonEnvironment, remixHost: ((LessonRoute) -> RemixHostModel)? = nil) -> some View {
        fullScreenCover(item: route) { current in
            if current.needsContentsChoice, let make = remixHost {
                RemixHostView(model: make(current), onExit: { route.wrappedValue = nil })
            } else {
                LessonHostView(
                    load: { try await environment.makeSession(for: current) },
                    onExit: { route.wrappedValue = nil }
                )
            }
        }
    }
}
#endif
