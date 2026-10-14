import SwiftUI
import QDesign
import QDomain
import QModel
import QData
import QKeyboard

public enum LessonScreenScenario: Sendable {
    case wordBankActive
    case wordBankWrong
    case typeInPersianKeyboard
    case leaveLessonModal
    case leaveCheckpointModal
    case settingsPersian
    case settingsJapanese
    case gradingPending
    case checkpointReady
    case checkpointNoTest
    case checkpointPassed
    case checkpointFailedNotApplied
}

/// A grader that calls anything containing the first accepted answer correct, for screenshots.
final class ShowcaseGrader: Grader {
    func gradeEnvelope(_ request: GraderRequest) -> GraderResponse {
        let right = request.acceptedAnswers.contains(request.submitted)
        return GraderResponse(
            verdict: right ? "Correct" : "Incorrect",
            matchedAnswer: right ? request.submitted : nil,
            correct: right,
            xp: right ? 10 : 0
        )
    }

    func xp(verdict: String, attempt: Int, usedHint: Bool, retype: Bool, retypeNumber: Int?) -> Int { 0 }
}

/// Gallery for snapshot tests: the lesson screen driven to a state through its real session, and the settings popover. No network, no animation.
public struct LessonScreenShowcase: View {
    private let scenario: LessonScreenScenario
    @StateObject private var session: LessonSession
    @Environment(\.colorScheme) private var colorScheme

    public init(_ scenario: LessonScreenScenario) {
        self.scenario = scenario
        _session = StateObject(wrappedValue: LessonScreenShowcase.makeSession(scenario))
    }

    private static func instances() -> [ExerciseInstance] {
        let bank = ExerciseArtifact(
            type: .wordBank, scriptMode: .native, prompt: "Good morning",
            tiles: ["\u{0635}\u{0628}\u{062D}", "\u{0628}\u{062E}\u{06CC}\u{0631}", "\u{0633}\u{0644}\u{0627}\u{0645}"],
            answer: ["\u{0635}\u{0628}\u{062D} \u{0628}\u{062E}\u{06CC}\u{0631}"], tags: ["sobh-bekheyr"]
        )
        let typed = ExerciseArtifact(
            type: .typeIn, scriptMode: .native, prompt: "Hello",
            answer: ["\u{0633}\u{0644}\u{0627}\u{0645}"], tags: ["salam"]
        )
        return [
            ExerciseInstance(key: "u1/greetings/0", unitKey: "u1", skillKey: "greetings", ordinal: 0, exercise: bank, renderType: .wordBank),
            ExerciseInstance(key: "u1/greetings/1", unitKey: "u1", skillKey: "greetings", ordinal: 1, exercise: typed, renderType: .typeIn),
        ]
    }

    private static func makeSession(_ scenario: LessonScreenScenario) -> LessonSession {
        var all = instances()
        var prefs = LocalPrefs()
        var checkpoint: String?
        var plan: CheckpointPlanInfo?
        switch scenario {
        case .typeInPersianKeyboard:
            all.removeFirst()
            prefs.persianInputMethod = .layout
        case .leaveCheckpointModal:
            checkpoint = "Skipping 3 lessons \u{2014} 1 already done via deep dive."
        case .checkpointReady:
            checkpoint = "Skipping 3 lessons \u{2014} 1 already done via deep dive."
            plan = CheckpointPlanInfo(courseVersion: 1, targetUnitKey: "u2", targetSkillKey: "family", skippedCount: 3, alreadyCompletedCount: 1, requiresTest: true)
        case .checkpointNoTest:
            all = []
            checkpoint = "Skipping 2 lessons \u{2014} 2 already done via deep dive."
            plan = CheckpointPlanInfo(courseVersion: 1, targetUnitKey: "u2", targetSkillKey: "family", skippedCount: 2, alreadyCompletedCount: 2, requiresTest: false)
        default:
            break
        }
        let setup = LessonSetup(courseCode: "fa", courseVersion: 1, instances: all, exerciseCountBySkill: ["greetings": 2], checkpointSummary: checkpoint, checkpoint: plan)
        let grading = scenario != .gradingPending
        let deps = LessonDependencies(
            grader: grading ? ShowcaseGrader() : PlaceholderGraderSource.grader,
            gradingOnDevice: grading,
            submit: { _ in .queued }
        )
        let session = LessonSession(setup: setup, prefs: prefs, serverPrefs: LessonServerPrefs(), dependencies: deps)
        switch scenario {
        case .wordBankWrong:
            session.setTileAnswer("\u{0633}\u{0644}\u{0627}\u{0645}")
            session.check()
        case .gradingPending:
            session.setTileAnswer("\u{0635}\u{0628}\u{062D} \u{0628}\u{062E}\u{06CC}\u{0631}")
            session.check()
        case .checkpointReady:
            session.setTileAnswer("\u{0635}\u{0628}\u{062D} \u{0628}\u{062E}\u{06CC}\u{0631}")
            session.check()
            session.setTyped("\u{0633}\u{0644}\u{0627}\u{0645}")
            session.check()
        case .leaveLessonModal, .leaveCheckpointModal:
            session.confirmingLeave = true
        default:
            break
        }
        return session
    }

    public var body: some View {
        let p = colorScheme == .dark ? AppPalette.dark : AppPalette.light
        Group {
            switch scenario {
            case .settingsPersian:
                LanguageSettingsPopover(
                    courseCode: "fa", prefs: LocalPrefs(), serverPrefs: LessonServerPrefs(),
                    onPrefsChange: { _ in }, onScriptModeChange: { _ in }, onKeyboardModeChange: { _ in }, onDismiss: {}
                )
            case .settingsJapanese:
                LanguageSettingsPopover(
                    courseCode: "ja", prefs: LocalPrefs(), serverPrefs: LessonServerPrefs(scriptMode: .both),
                    onPrefsChange: { _ in }, onScriptModeChange: { _ in }, onKeyboardModeChange: { _ in }, onDismiss: {}
                )
            case .checkpointPassed:
                CheckpointResultView(outcome: CheckpointOutcome(passed: true, score: 0.85, applied: true), onBack: {})
            case .checkpointFailedNotApplied:
                CheckpointResultView(outcome: CheckpointOutcome(passed: false, score: 0.4, applied: false), onBack: {})
            default:
                LessonScreen(session: session, onExit: {})
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(argb: p.bg))
    }
}
