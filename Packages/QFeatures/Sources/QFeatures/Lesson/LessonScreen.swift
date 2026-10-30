import SwiftUI
import QDesign
import QDomain
import QModel
import QData
import QKeyboard

// The lesson screen (web LessonPage / ExerciseSessionScreen, matching Android LessonScreen.kt): a progress bar
// with the settings cog and the close button, the exercise, then either the verdict panel or the keyboard and
// Check. Binds `LessonSession` (which wraps the engine) to the exercise, feedback and results views.

private func screenPalette(_ scheme: ColorScheme) -> AppPalette {
    return scheme == .dark ? AppPalette.dark : AppPalette.light
}

/// Re-renders `content` as the keyboard's pending letters change (a view only observes what it holds).
struct PendingObserver<Content: View>: View {
    @ObservedObject var keyboard: KeyboardState
    let content: (String?) -> Content

    var body: some View {
        content(keyboard.pending)
    }
}

public struct LessonScreen: View {
    @ObservedObject private var session: LessonSession
    private let onExit: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    /// The report form for the exercise still being asked is open.
    @State private var reportingAsked = false

    public init(session: LessonSession, onExit: @escaping () -> Void) {
        self.session = session
        self.onExit = onExit
    }

    public var body: some View {
        let p = screenPalette(colorScheme)
        let leaving = session.confirmingLeave && (session.phase == .active || session.phase == .checkpointReady)
        let exit: () -> Void = { session.leave(); onExit() }
        ZStack {
            Color(argb: p.bg).ignoresSafeArea()
            Group {
                switch session.phase {
                case .active:
                    sessionView(p)
                case .saving:
                    LessonResultsView(
                        end: .saving,
                        stats: LessonResultsStats(correct: 0, total: 0, score: 0, xp: 0),
                        onBack: exit
                    )
                case .saveFailed:
                    saveFailedView(p, onBack: exit)
                case .checkpointReady, .checkpointSubmitting:
                    CheckpointReadyView(
                        noTest: session.checkpointNeedsNoTest,
                        summary: session.setup.checkpointSummary,
                        error: session.checkpointError,
                        submitting: session.phase == .checkpointSubmitting,
                        onSubmit: { session.submitCheckpoint() },
                        onExit: { session.confirmingLeave = true }
                    )
                case .checkpointDone(let outcome):
                    CheckpointResultView(outcome: outcome, onBack: exit)
                case .ended(let end):
                    LessonResultsView(
                        end: end,
                        stats: session.stats ?? LessonResultsStats(correct: 0, total: 0, score: 0, xp: 0),
                        onBack: exit,
                        onTryAgain: { session.tryAgain() },
                        onShare: nil,
                        onPracticeAgain: { session.practiceAgain() }
                    )
                }
            }
            // The dialog is the only thing VoiceOver can reach while it is up.
            .accessibilityHidden(leaving)
            if leaving {
                if session.setup.isCheckpoint {
                    LeaveCheckpointModal(onKeepGoing: { session.confirmingLeave = false }, onLeave: exit)
                } else {
                    SkipLessonModal(onKeepGoing: { session.confirmingLeave = false }, onLeave: exit)
                }
            }
        }
        .environment(\.lessonTextLook, session.textLook)
        .environment(\.practiceFocusTag, session.instance?.focusTag)
        .sheet(isPresented: $session.showingSettings) {
            LanguageSettingsPopover(
                courseCode: session.courseCode,
                prefs: session.prefs,
                serverPrefs: session.serverPrefs,
                onPrefsChange: { next in session.updatePrefs { $0 = next } },
                onScriptModeChange: { session.setScriptMode($0) },
                onKeyboardModeChange: { session.setKeyboardMode($0) },
                onDismiss: { session.showingSettings = false }
            )
            .presentationDetents([.medium, .large])
        }
        .task { session.exerciseShown() }
    }

    private func saveFailedView(_ p: AppPalette, onBack: @escaping () -> Void) -> some View {
        VStack(spacing: Spacing.standard.s3) {
            Text(LessonScreenLogic.saveFailedTitle)
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(Color(argb: p.text))
                .multilineTextAlignment(.center)
            Text(LessonScreenLogic.saveFailedBody)
                .font(.system(size: 16))
                .foregroundColor(Color(argb: p.textMuted))
                .multilineTextAlignment(.center)
            Button(action: { session.retrySave() }) {
                Text("Try again")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(Color(argb: p.primaryContrast))
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(RoundedRectangle(cornerRadius: Radii.standard.md, style: .continuous).fill(Color(argb: p.primary)))
            }
            .buttonStyle(.plain)
            .frame(maxWidth: 420)
            Button(action: onBack) {
                Text(LessonScreenLogic.backToPath)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(Color(argb: p.primary))
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: 420)
        }
        .padding(Spacing.standard.s4)
    }

    // MARK: Session

    @ViewBuilder
    private func sessionView(_ p: AppPalette) -> some View {
        if let instance = session.instance {
            VStack(spacing: 0) {
                topBar(p)
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.standard.s3) {
                        if let summary = session.setup.checkpointSummary {
                            Text(summary)
                                .font(.system(size: 13))
                                .foregroundColor(Color(argb: p.textMuted))
                        }
                        if session.showsSyncNote {
                            Text(LessonScreenLogic.syncNote)
                                .font(.system(size: 13))
                                .foregroundColor(Color(argb: p.textMuted))
                        }
                        if let chapter = session.setup.story {
                            StoryTranscriptView(chapter: chapter, upTo: instance.ordinal, results: session.storyResults)
                        }
                        // Report the exercise still being asked (Android Session's "Report"): a bad recording shows before any answer.
                        if session.askedReportForm != nil {
                            HStack {
                                Spacer()
                                Button("Report") { reportingAsked = true }
                                    .foregroundColor(Color(argb: p.textMuted))
                            }
                        }
                        if instance.listening && session.review == nil {
                            ListenPrompt(
                                playsLeft: instance.playsLeft,
                                locked: session.listenPlaying,
                                failed: session.listenFailed,
                                onPlay: { session.playListening(slow: false) },
                                onPlaySlow: { session.playListening(slow: true) }
                            )
                        } else {
                            ExercisePrompt(
                                exercise: instance.exercise,
                                courseCode: session.courseCode,
                                hasVoice: session.hasVoice,
                                onPlay: { session.playPrompt(slow: false) },
                                onInstallVoice: { session.installVoice() },
                                onPlaySlow: { session.playPrompt(slow: true) }
                            )
                        }
                        exerciseBody(instance)
                    }
                    .padding(.horizontal, Spacing.standard.s3)
                    .frame(maxWidth: 640)
                    .frame(maxWidth: .infinity)
                }
                bottomArea(p)
            }
            .sheet(isPresented: $reportingAsked) {
                if let form = session.askedReportForm {
                    ReportIssueHost(form: form, onClose: { reportingAsked = false })
                }
            }
        }
    }

    private func topBar(_ p: AppPalette) -> some View {
        HStack(spacing: Spacing.standard.s3) {
            SessionProgressBar(completed: session.state.completedCount, total: session.state.totalCount)
            Button(action: { session.showingSettings = true }) {
                Image(systemName: "gearshape")
                    .font(.system(size: 20))
                    .foregroundColor(Color(argb: p.textMuted))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Lesson settings")
            CloseLessonButton(isConfirming: session.confirmingLeave) { session.confirmingLeave = true }
        }
        .padding(.horizontal, Spacing.standard.s3)
        .padding(.vertical, Spacing.standard.s1)
    }

    @ViewBuilder
    private func exerciseBody(_ instance: ExerciseInstance) -> some View {
        let reviewedText: Reviewed? = session.review.map { Reviewed(text: $0.submittedText, correct: $0.feedback.verdict != .incorrect) }
        let reviewedTiles: ReviewedAnswer? = session.review.map { ReviewedAnswer(text: $0.submittedText, correct: $0.feedback.verdict != .incorrect) }
        let identity = "\(instance.key)#\(session.exerciseRound)"
        if LessonScreenLogic.isTypeIn(instance.renderType) {
            if let keyboard = session.keyboard, session.inAppKeyboard {
                PendingObserver(keyboard: keyboard) { pending in
                    typeInField(instance, reviewed: reviewedText, pending: pending)
                }
                .id(identity)
            } else {
                typeInField(instance, reviewed: reviewedText, pending: nil)
                    .id(identity)
            }
        } else {
            WordBankExercise(
                exercise: instance.exercise,
                courseCode: session.courseCode,
                reviewed: reviewedTiles,
                onTilePicked: { session.speakTile($0) },
                onAnswerChange: { session.setTileAnswer($0) }
            )
            .id(identity)
        }
    }

    @ViewBuilder
    private func typeInField(_ instance: ExerciseInstance, reviewed: Reviewed?, pending: String?) -> some View {
        let text = Binding<String>(get: { session.typed }, set: { session.setTyped($0) })
        let family = Languages.isPersian(session.courseCode) ? session.prefs.fontFa.family : session.prefs.fontJa.family
        let useInApp: (() -> Void)? = (session.keyboard != nil && !session.inAppKeyboard)
            ? { session.updatePrefs { $0.deviceInputEnabled = false } }
            : nil
        if instance.renderType == .speak {
            SpeakExercise(
                exercise: instance.exercise, courseCode: session.courseCode, instanceKey: instance.key,
                reviewed: reviewed, text: text, onDone: { session.check() },
                inAppKeyboard: session.inAppKeyboard, pending: pending, caret: session.caret,
                onUseInAppKeyboard: useInApp, onCaretTap: { session.tapCaret(to: $0) },
                onHintUsed: { session.markHintUsed() },
                vowelMarks: session.prefs.showVowelMarks, persianFamily: family
            )
        } else {
            TypeInExercise(
                exercise: instance.exercise, courseCode: session.courseCode, instanceKey: instance.key,
                reviewed: reviewed, text: text, onDone: { session.check() },
                inAppKeyboard: session.inAppKeyboard, pending: pending, caret: session.caret,
                onUseInAppKeyboard: useInApp, onCaretTap: { session.tapCaret(to: $0) },
                onHintUsed: { session.markHintUsed() },
                vowelMarks: session.prefs.showVowelMarks, persianFamily: family
            )
        }
    }

    // MARK: Bottom

    @ViewBuilder
    private func bottomArea(_ p: AppPalette) -> some View {
        if let review = session.review {
            AnswerFeedbackView(
                review: review,
                onContinue: { session.continueOn() },
                onPlayAnswer: session.canPlayAnswer ? { session.playAnswer() } : nil,
                reportForm: session.reportForm
            )
        } else if let keyboard = session.keyboard, session.inAppKeyboard {
            PendingObserver(keyboard: keyboard) { pending in
                VStack(spacing: 0) {
                    TypeInKeyboardPanel(
                        courseCode: session.courseCode,
                        prefs: session.prefs,
                        state: keyboard,
                        text: { String(String.UnicodeScalarView(session.typed.unicodeScalars.prefix(session.caret))) },
                        onEdit: { session.applyEdit($0) },
                        onPrefsChange: { next in session.updatePrefs { $0 = next } }
                    )
                    checkButton(p, pending: pending)
                }
            }
        } else {
            checkButton(p, pending: nil)
        }
    }

    private func checkButton(_ p: AppPalette, pending: String?) -> some View {
        let enabled = session.canCheck(keyboardPending: pending)
        return Button(action: { session.check() }) {
            Text(LessonScreenLogic.checkButtonLabel(isCheckpoint: session.setup.isCheckpoint))
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(Color(argb: enabled ? p.primaryContrast : p.textMuted))
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(
                    RoundedRectangle(cornerRadius: Radii.standard.md, style: .continuous)
                        .fill(Color(argb: enabled ? p.primary : p.border))
                )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .padding(.horizontal, Spacing.standard.s3)
        .padding(.top, Spacing.standard.s3)
        .padding(.bottom, Spacing.standard.s2)
    }
}

// MARK: Loading host

/// Loads a lesson, then plays it: a spinner while loading, an end screen when it fails or there is nothing to do
/// (Android LessonScreen's Loading / Failed / Nothing-due states). `load` returns nil for "nothing due".
public struct LessonHostView: View {
    private enum Load {
        case loading
        case failed(String)
        case empty
        case ready(LessonSession)
    }

    private let load: () async throws -> LessonSession?
    private let onExit: () -> Void
    @State private var state: Load = .loading
    @Environment(\.colorScheme) private var colorScheme

    public init(load: @escaping () async throws -> LessonSession?, onExit: @escaping () -> Void) {
        self.load = load
        self.onExit = onExit
    }

    public var body: some View {
        let p = screenPalette(colorScheme)
        ZStack {
            Color(argb: p.bg).ignoresSafeArea()
            switch state {
            case .loading:
                VStack(spacing: Spacing.standard.s3) {
                    ProgressView()
                    Text(LessonScreenLogic.loadingTitle)
                        .font(.system(size: 16))
                        .foregroundColor(Color(argb: p.textMuted))
                }
                .task { await run() }
            case .failed(let message):
                endScreen(p, title: LessonScreenLogic.failedTitle, body: message)
            case .empty:
                endScreen(p, title: LessonScreenLogic.nothingDueTitle, body: LessonScreenLogic.nothingDueBody)
            case .ready(let session):
                LessonScreen(session: session, onExit: onExit)
            }
        }
    }

    private func run() async {
        do {
            if let session = try await load() {
                state = .ready(session)
            } else {
                state = .empty
            }
        } catch {
            state = .failed(LessonScreenLogic.loadFailureMessage(for: error))
        }
    }

    private func endScreen(_ p: AppPalette, title: String, body: String) -> some View {
        VStack(spacing: Spacing.standard.s3) {
            Text(title)
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(Color(argb: p.text))
                .multilineTextAlignment(.center)
            Text(body)
                .font(.system(size: 16))
                .foregroundColor(Color(argb: p.textMuted))
                .multilineTextAlignment(.center)
            Button(action: onExit) {
                Text(LessonScreenLogic.backToPath)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(Color(argb: p.primaryContrast))
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(RoundedRectangle(cornerRadius: Radii.standard.md, style: .continuous).fill(Color(argb: p.primary)))
            }
            .buttonStyle(.plain)
            .frame(maxWidth: 420)
        }
        .padding(Spacing.standard.s4)
    }
}
