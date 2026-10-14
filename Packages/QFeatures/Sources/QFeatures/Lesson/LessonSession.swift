import Foundation
import QModel
import QDomain
import QData
import QKeyboard

/// Hands one finished session to the offline queue and the server (production: `LessonSubmitter.submit`, which enqueues first, then flushes).
public typealias LessonSubmitFunction = @Sendable (SubmittedSession) async throws -> LessonSubmitResult

/// Writes one finished session to the offline queue before anything else happens to it (write-ahead).
public typealias LessonEnqueueFunction = @Sendable (SubmittedSession) async throws -> Void

/// Sends a finished checkpoint (all its answers at once) and returns the server's verdict. Online only: there is no queue.
public typealias CheckpointSubmitFunction = @Sendable (SubmitCheckpointRequest) async throws -> CheckpointSubmitResponse

/// What the lesson screen needs from the outside, as plain closures so tests and snapshots inject fakes.
public struct LessonDependencies {
    /// Grades answers on the device. nil (with `gradingOnDevice == false`) makes every answer "checked when you sync".
    /// The production grader (JavaScriptCore or a hidden WKWebView over the shared .NET WASM grader) is decided by item M1;
    /// until it lands the app injects `PlaceholderGraderSource`.
    public var grader: Grader?
    public var gradingOnDevice: Bool
    public var submit: LessonSubmitFunction
    /// Write-ahead persistence of a finished session; awaited before the submit. Production: `OfflineQueue.enqueue`.
    public var enqueue: LessonEnqueueFunction
    /// The lesson in progress, kept across a killed app and cleared once the lesson is saved or left.
    public var draft: LessonDraftStore
    /// Where a practice-again round of a counted lesson is kept, apart from the counted lesson's draft; nil uses `draft`.
    public var practiceDraft: LessonDraftStore?
    /// Called once when a counted lesson completes (Android bumps `localPrefs.lessonsCompleted`).
    public var onLessonCounted: @Sendable () -> Void
    /// Streak and daily goal after the lesson, for the results screen. Called once per finished lesson.
    public var loadExtras: @Sendable () async -> LessonResultsExtras
    /// Persists the device prefs the lesson changes (settings popover, switching keyboards).
    public var savePrefs: (LocalPrefs) -> Void
    /// Persists the one server pref the lesson changes (text mode).
    public var saveScriptMode: (ScriptMode) -> Void
    public var speech: SpeechService?
    public var courseHints: [String: WordHint]
    public var onFeedback: (FeedbackEvent) -> Void
    public var onInstallVoice: () -> Void
    /// Builds the report form for the answer under review; nil hides "Report".
    public var makeReportModel: ((FeedbackReview) -> ReportIssueModel)?
    /// The clock (latency, session timestamps).
    public var now: () -> Date
    /// Sends a checkpoint; nil (or a throw) leaves the answers in place with a retry.
    public var submitCheckpoint: CheckpointSubmitFunction?
    /// Mints a checkpoint's submission id (once per attempt; a retry after a failed send reuses it).
    public var newSubmissionId: () -> String

    public init(
        grader: Grader? = nil,
        gradingOnDevice: Bool = false,
        submit: @escaping LessonSubmitFunction,
        enqueue: @escaping LessonEnqueueFunction = { _ in },
        draft: LessonDraftStore = .none,
        practiceDraft: LessonDraftStore? = nil,
        onLessonCounted: @escaping @Sendable () -> Void = {},
        loadExtras: @escaping @Sendable () async -> LessonResultsExtras = { LessonResultsExtras.none },
        savePrefs: @escaping (LocalPrefs) -> Void = { _ in },
        saveScriptMode: @escaping (ScriptMode) -> Void = { _ in },
        speech: SpeechService? = nil,
        courseHints: [String: WordHint] = emptyHintMap,
        onFeedback: @escaping (FeedbackEvent) -> Void = { _ in },
        onInstallVoice: @escaping () -> Void = {},
        makeReportModel: ((FeedbackReview) -> ReportIssueModel)? = nil,
        now: @escaping () -> Date = { Date() },
        submitCheckpoint: CheckpointSubmitFunction? = nil,
        newSubmissionId: @escaping () -> String = { UUID().uuidString.lowercased() }
    ) {
        self.grader = grader
        self.gradingOnDevice = gradingOnDevice
        self.submit = submit
        self.enqueue = enqueue
        self.draft = draft
        self.practiceDraft = practiceDraft
        self.onLessonCounted = onLessonCounted
        self.loadExtras = loadExtras
        self.savePrefs = savePrefs
        self.saveScriptMode = saveScriptMode
        self.speech = speech
        self.courseHints = courseHints
        self.onFeedback = onFeedback
        self.onInstallVoice = onInstallVoice
        self.makeReportModel = makeReportModel
        self.now = now
        self.submitCheckpoint = submitCheckpoint
        self.newSubmissionId = newSubmissionId
    }
}

/// The grader the app uses until item M1 decides the runtime. PLACEHOLDER: it grades nothing, so every answer is
/// pending ("checked when you sync", the server grades on submit) exactly like Android with no grader loaded.
public enum PlaceholderGraderSource {
    public static var grader: Grader? { nil }
    public static var gradingOnDevice: Bool { false }
}

public enum LessonPhase: Equatable {
    /// Answering exercises (the review panel shows between an answer and Continue).
    case active
    /// Finished; submitting the sessions.
    case saving
    /// The finished lesson could not be written to the phone's queue; the draft is kept and "Try again" saves it again.
    case saveFailed
    case ended(LessonEndKind)
    /// A checkpoint with every question answered (or none to answer): "Ready to submit" / "No test needed".
    case checkpointReady
    /// The checkpoint's answers are being sent.
    case checkpointSubmitting
    /// The server's verdict on the checkpoint.
    case checkpointDone(CheckpointOutcome)
}

/// One lesson being played: the engine, what is typed or picked, the verdict under review, the keyboard,
/// and the hand-off of the finished sessions. Port of the Session state in Android LessonScreen plus
/// LessonViewModel's submit/continue/restart.
/// Not annotated `@MainActor` so view closures can call it freely on any SDK; every call comes from the main thread (views, and the finish task, which hops back to it).
public final class LessonSession: ObservableObject {
    public let setup: LessonSetup
    private let deps: LessonDependencies

    @Published public private(set) var engine: LessonEngine
    @Published public private(set) var review: FeedbackReview?
    @Published public private(set) var phase: LessonPhase = .active
    @Published public private(set) var stats: LessonResultsStats?
    @Published public private(set) var prefs: LocalPrefs
    @Published public private(set) var serverPrefs: LessonServerPrefs
    @Published public private(set) var keyboard: KeyboardState?
    /// The typing field's text and the caret in it (a Unicode-scalar offset).
    @Published public private(set) var typed: String = ""
    @Published public private(set) var caret: Int = 0
    /// Word bank / match: the built answer, or nil until every tile is placed.
    @Published public private(set) var tileAnswer: String?
    @Published public private(set) var usedHint = false
    /// A bumped value re-creates the exercise views, so a retry of the same exercise starts fresh.
    @Published public private(set) var exerciseRound = 0
    @Published public var showingSettings = false
    @Published public var confirmingLeave = false
    /// Why the last checkpoint submit failed; the answers are kept and the learner can try again.
    @Published public private(set) var checkpointError: String?

    private var keyboardMethod: InputMethod?
    private var shownAt: Date
    private var finishing = false
    private var pending: PendingDelivery?
    private var deliveryTask: Task<Void, Never>?
    /// A checkpoint's answers by instance key. Not marked and not saved to disk: all sent at the end, or lost on leaving.
    private var checkpointAnswers: [String: String] = [:]
    private let checkpointSubmissionId: String

    /// What `finish` hands to the delivery step, kept so a failed save can be retried.
    private struct PendingDelivery {
        var sessions: [SubmittedSession]
        var locallyCompleted: Bool?
        var state: LessonState
    }

    struct Delivery: Equatable {
        var results: [LessonSubmitResult]
        /// A session that is neither in the queue nor accepted by the server.
        var unsaved: Bool
    }

    public init(setup: LessonSetup, prefs: LocalPrefs = LocalPrefs(), serverPrefs: LessonServerPrefs = LessonServerPrefs(), dependencies: LessonDependencies) {
        self.setup = setup
        self.deps = dependencies
        self.prefs = prefs
        self.serverPrefs = serverPrefs
        self.checkpointSubmissionId = dependencies.newSubmissionId()
        var initial = LessonState(queue: setup.instances, practice: setup.practice)
        // A checkpoint keeps no draft: nothing is marked, and leaving drops the answers.
        let savedDraft = setup.checkpoint == nil ? dependencies.draft.load() : nil
        if let saved = savedDraft {
            // A finished draft is self-contained and may be the only copy of the answers: deliver it, whatever the setup is now.
            if saved.finished || LessonSession.isRestorable(saved, for: setup) {
                initial = saved
            } else {
                dependencies.draft.clear()
            }
        }
        self.engine = LessonEngine(
            state: initial,
            courseCode: setup.courseCode,
            grader: dependencies.grader,
            gradingOnDevice: dependencies.gradingOnDevice
        )
        self.shownAt = dependencies.now()
        rebuildKeyboard()
        // A draft saved at the very end (killed while saving): deliver it again; the queue dedupes by submission id.
        if setup.checkpoint == nil && engine.state.finished && !engine.state.items.isEmpty { finish(resumed: true) }
        // A checkpoint with nothing to ask is still submitted, to move the learner on.
        if setup.checkpoint != nil && engine.state.finished { phase = .checkpointReady }
    }

    /// A saved lesson belongs to this setup when it was cut from the same exercises.
    static func isRestorable(_ saved: LessonState, for setup: LessonSetup) -> Bool {
        if saved.totalCount != setup.instances.count { return false }
        let keys = Set(setup.instances.map { $0.key })
        return saved.queue.allSatisfy { keys.contains($0.key) }
    }

    /// The draft of the round on screen: a practice-again round of a counted lesson has its own, so a later counted start never resumes it.
    private var activeDraft: LessonDraftStore {
        if engine.state.practice && !setup.practice, let other = deps.practiceDraft { return other }
        return deps.draft
    }

    // MARK: Derived

    public var state: LessonState { engine.state }
    /// The exercise on screen: the one under review, else the next.
    public var instance: ExerciseInstance? { review?.instance ?? engine.state.current }
    public var courseCode: String { setup.courseCode }
    public var isTypeIn: Bool {
        guard let renderType = instance?.renderType else { return false }
        return LessonScreenLogic.isTypeIn(renderType)
    }
    public var inAppKeyboard: Bool { LessonScreenLogic.usesInAppKeyboard(method: keyboardMethod, prefs: prefs) && keyboard != nil }
    /// `keyboardPending` is the in-app keyboard's uncommitted letters (the view observes the keyboard, so it passes them in).
    public func canCheck(keyboardPending: String?) -> Bool {
        LessonScreenLogic.canCheck(typeIn: isTypeIn, typed: typed, keyboardPending: inAppKeyboard ? keyboardPending : nil, tileAnswer: tileAnswer)
    }
    public var showsSyncNote: Bool { !engine.gradingOnDevice && !setup.isCheckpoint }
    public var hasVoice: Bool {
        guard let speech = deps.speech, let info = Languages.languageInfo(setup.courseCode) else { return false }
        return speech.hasVoice(info.speechTag)
    }
    public var textLook: LessonTextLook {
        LessonScreenLogic.textLook(prefs: prefs, serverPrefs: serverPrefs, courseCode: setup.courseCode, hints: deps.courseHints)
    }
    public var canPlayAnswer: Bool { review != nil && deps.speech != nil }
    /// The report form for the answer under review; nil when there is nothing to report on or no report channel is wired.
    public var reportModelFactory: (() -> ReportIssueModel)? {
        guard let make = deps.makeReportModel, let shown = review else { return nil }
        return { make(shown) }
    }

    // MARK: Answering

    public func setTileAnswer(_ answer: String?) {
        tileAnswer = answer
        deps.onFeedback(.tilePlaced)
    }

    public func markHintUsed() { usedHint = true }

    /// The in-app keyboard (or the phone's, through the field's binding) changed the text.
    public func setTyped(_ text: String) {
        typed = text
        caret = text.unicodeScalars.count
    }

    public func applyEdit(_ edit: Edit) {
        let result = edit.applyAt(typed, caret: caret)
        typed = result.text
        caret = result.caret
    }

    /// Commits a half-typed letter where it was typed (web: finalize before a caret move or a tap).
    public func commitPending() {
        guard let board = keyboard else { return }
        applyEdit(board.finalize())
    }

    /// A tap in the answer at `to`, an index into the text as it was shown.
    public func tapCaret(to: Int) {
        let oldCaret = caret
        let oldLength = typed.unicodeScalars.count
        commitPending()
        caret = LessonScreenLogic.caretAfterTap(to: to, oldCaret: oldCaret, oldLength: oldLength, newLength: typed.unicodeScalars.count)
    }

    /// Commits a half-typed letter, then grades what is in the box or the built tile order. Nothing happens without an answer.
    public func check() {
        if review != nil || phase != .active { return }
        guard let current = engine.state.current else { return }
        if isTypeIn { commitPending() }
        guard let text = LessonScreenLogic.submittableText(typeIn: isTypeIn, typed: typed, tileAnswer: tileAnswer) else { return }
        if setup.checkpoint != nil {
            recordCheckpointAnswer(current, text)
            return
        }
        let latency = max(0, Int(deps.now().timeIntervalSince(shownAt) * 1000))
        guard let outcome = engine.submit(text, usedHint: usedHint, latencyMs: latency) else { return }
        let shown = FeedbackReview(feedback: outcome.feedback, instance: current, submittedText: text, xp: outcome.xpGained)
        review = shown
        switch outcome.feedback.verdict {
        case .correct, .acceptedWithCorrection: deps.onFeedback(.correct)
        case .incorrect: deps.onFeedback(.incorrect)
        case .pending: break
        }
        if prefs.speakAnswers { playAnswer() }
    }

    /// No marking mid-checkpoint (Android submit): record the answer and move straight on.
    private func recordCheckpointAnswer(_ current: ExerciseInstance, _ text: String) {
        checkpointAnswers[current.key] = text
        engine.advancePastCurrent()
        resetAnswer()
        if engine.state.finished {
            phase = .checkpointReady
        } else {
            rebuildKeyboard()
            exerciseShown()
        }
    }

    /// True when the checkpoint has nothing to ask (the plan needs no test), so the ready screen says "No test needed".
    public var checkpointNeedsNoTest: Bool { setup.checkpoint != nil && setup.instances.isEmpty }

    /// Sends every checkpoint answer at once; the server grades them and moves the cursor on a pass.
    public func submitCheckpoint() {
        guard phase == .checkpointReady, let info = setup.checkpoint else { return }
        phase = .checkpointSubmitting
        checkpointError = nil
        let request = CheckpointLogic.request(
            info: info, instances: setup.instances, answers: checkpointAnswers,
            submissionId: checkpointSubmissionId, occurredAt: deps.now()
        )
        let send = deps.submitCheckpoint
        deliveryTask = Task { @MainActor [weak self] in
            do {
                guard let send = send else { throw URLError(.notConnectedToInternet) }
                let response = try await send(request)
                guard let self = self else { return }
                let outcome = CheckpointOutcome(response)
                if outcome.passed { self.deps.onFeedback(.lessonComplete) }
                self.phase = .checkpointDone(outcome)
            } catch {
                self?.checkpointError = CheckpointLogic.submitFailure
                self?.phase = .checkpointReady
            }
        }
    }

    /// Leaves the verdict panel: on to the next exercise, or the end of the lesson.
    public func continueOn() {
        guard review != nil else { return }
        review = nil
        resetAnswer()
        if engine.state.finished {
            finish()
        } else {
            activeDraft.save(engine.state)
            rebuildKeyboard()
            exerciseShown()
        }
    }

    private func resetAnswer() {
        typed = ""
        caret = 0
        tileAnswer = nil
        usedHint = false
        exerciseRound += 1
        shownAt = deps.now()
    }

    /// Autoplay of the prompt, once per exercise shown (Android LaunchedEffect on instance.key).
    public func exerciseShown() {
        guard serverPrefs.autoplayAudio, let current = engine.state.current, review == nil else { return }
        if Languages.isNativeText(setup.courseCode, current.exercise.prompt) { playPrompt(slow: false) }
    }

    // MARK: Finish

    private func finish(resumed: Bool = false) {
        if finishing { return }
        finishing = true
        phase = .saving
        if !resumed { deps.onFeedback(.lessonComplete) }
        let completion = engine.completion(
            courseCode: setup.courseCode,
            courseVersion: setup.courseVersion,
            occurredAt: deps.now(),
            exerciseCountBySkill: setup.exerciseCountBySkill
        )
        let state = engine.state
        let sessions = completion?.sessions ?? []
        pending = PendingDelivery(sessions: sessions, locallyCompleted: completion?.locallyCompleted, state: state)
        if state.practice || sessions.isEmpty {
            activeDraft.clear()
        } else {
            // The finished state, with its submission ids, is on disk before the first await.
            activeDraft.save(state)
        }
        startDelivery()
    }

    /// Writes each session to the queue, then submits it; only then does the lesson end. A thrown submit after the
    /// session is queued is "saved offline", never a rejection (only the server can reject).
    static func deliver(sessions: [SubmittedSession], enqueue: LessonEnqueueFunction, submit: LessonSubmitFunction) async -> Delivery {
        var results: [LessonSubmitResult] = []
        var unsaved = false
        for session in sessions {
            var persisted = true
            do {
                try await enqueue(session)
            } catch {
                persisted = false
            }
            do {
                results.append(try await submit(session))
            } catch {
                if persisted {
                    results.append(.queued)
                } else {
                    unsaved = true
                }
            }
        }
        return Delivery(results: results, unsaved: unsaved)
    }

    private func startDelivery() {
        guard let work = pending else { return }
        let deps = self.deps
        deliveryTask = Task { @MainActor [weak self] in
            let delivery = await LessonSession.deliver(sessions: work.sessions, enqueue: deps.enqueue, submit: deps.submit)
            let practice = work.state.practice
            if delivery.unsaved {
                // Keep the draft: reopening the lesson delivers it again.
                self?.finishing = false
                self?.phase = .saveFailed
                return
            }
            deps.draft.clear()
            let end = LessonScreenLogic.endKind(results: delivery.results, locallyCompleted: work.locallyCompleted, practice: practice)
            if !practice && LessonSession.countsAsCompleted(end) { deps.onLessonCounted() }
            var extras = LessonResultsExtras.none
            if !practice { extras = await deps.loadExtras() }
            guard let self = self else { return }
            let state = work.state
            self.stats = LessonResultsStats(
                correct: state.firstTryCorrect, total: state.totalCount, score: state.score, xp: state.xp,
                streakDays: extras.streakDays, goalXpToday: extras.goalXpToday, goalXp: extras.goalXp
            )
            self.phase = .ended(end)
            self.finishing = false
            self.pending = nil
        }
    }

    /// Android: lessonsCompleted counts saved or queued lessons unless the device knows it was not completed.
    static func countsAsCompleted(_ end: LessonEndKind) -> Bool {
        switch end {
        case .saved(let completed, _): return completed != false
        case .queued(let completed): return completed != false
        default: return false
        }
    }

    /// "Try again" on the save-failed screen.
    public func retrySave() {
        guard phase == .saveFailed, !finishing else { return }
        finishing = true
        phase = .saving
        startDelivery()
    }

    /// Waits for the save-and-submit step started by the last Continue (tests, and callers that must not move on before it).
    public func waitForDelivery() async {
        await deliveryTask?.value
    }

    /// Leaving the lesson: stops speech, and drops the draft of a lesson abandoned part way.
    public func leave() {
        deps.speech?.stop()
        if phase == .active {
            deps.draft.clear()
            deps.practiceDraft?.clear()
        }
    }

    /// The same lesson again from the top, counting this time ("Try again" after a miss).
    public func tryAgain() { restart(practice: false) }

    /// The same lesson again as practice: nothing is submitted ("Practice again").
    public func practiceAgain() { restart(practice: true) }

    private func restart(practice: Bool) {
        engine.restart(setup.instances, practice: practice)
        // Only one of the two drafts is live: the round that just ended leaves none behind.
        if practice { deps.draft.clear() } else { deps.practiceDraft?.clear() }
        activeDraft.save(engine.state)
        review = nil
        stats = nil
        phase = .active
        resetAnswer()
        rebuildKeyboard()
        exerciseShown()
    }

    // MARK: Prefs

    public func updatePrefs(_ change: (inout LocalPrefs) -> Void) {
        commitPending()
        var next = prefs
        change(&next)
        if next == prefs { return }
        prefs = next
        deps.savePrefs(next)
        rebuildKeyboard()
    }

    public func setScriptMode(_ mode: ScriptMode) {
        if serverPrefs.scriptMode == mode { return }
        serverPrefs.scriptMode = mode
        deps.saveScriptMode(mode)
    }

    public func setKeyboardMode(_ mode: KeyboardMode) {
        if serverPrefs.keyboardMode == mode { return }
        serverPrefs.keyboardMode = mode
        rebuildKeyboard()
    }

    /// (Re)creates the in-app keyboard for the exercise on screen; kept when the method is unchanged so half-typed state survives.
    private func rebuildKeyboard() {
        guard let current = instance, LessonScreenLogic.isTypeIn(current.renderType) else {
            keyboard = nil
            keyboardMethod = nil
            return
        }
        let method = TypeInModel.inputMethod(
            courseCode: setup.courseCode,
            scriptMode: current.exercise.scriptMode,
            prefs: prefs,
            keyboardMode: serverPrefs.keyboardMode.rawValue
        )
        if method == keyboardMethod && (keyboard != nil) == (method != nil) { return }
        keyboardMethod = method
        if let method = method {
            keyboard = KeyboardState(method: method)
        } else {
            keyboard = nil
        }
    }

    // MARK: Audio

    public func playPrompt(slow: Bool) {
        guard let current = instance else { return }
        speak(current.exercise.prompt, slow: slow)
    }

    public func playAnswer() {
        guard let shown = review else { return }
        let lines = revealedAnswerLines(shown.instance.exercise, submittedText: shown.submittedText)
        guard let line = lines.first else { return }
        speak(line, slow: false)
    }

    public func speakTile(_ tile: String) {
        if prefs.speakWordBankTiles && Languages.isNativeText(setup.courseCode, tile) { speak(tile, slow: false) }
    }

    private func speak(_ text: String, slow: Bool) {
        guard let speech = deps.speech, let tag = LessonScreenLogic.speechTag(courseCode: setup.courseCode, text: text) else { return }
        _ = speech.speak(text, languageTag: tag, rate: slow ? SpeechService.slowRate : 1)
    }

    public func installVoice() { deps.onInstallVoice() }
}
