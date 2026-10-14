import SwiftUI
import QModel
import QDomain
import QData
import QDesign
import QKeyboard

public enum TypeInShowcaseScenario: Sendable {
    case persianEmpty
    case persianTyped
    case japaneseTyped
    case persianMarkedWrong
    case japaneseMarkedWrong
    case persianMarkedCorrect
    case noVoice
    case speak
}

/// A synthesizer with no voices at all, so the no-voice state renders the same everywhere.
final class NoVoiceSynthesizer: SpeechSynthesizing {
    func installedVoiceLanguages() -> [String] { [] }
    var isSpeaking: Bool { false }
    func speak(text: String, voiceLanguage: String, rate: Double, onEnd: @escaping () -> Void) { onEnd() }
    func stop() {}
}

/// A synthesizer that has a Persian and a Japanese voice.
final class VoicedSynthesizer: SpeechSynthesizing {
    func installedVoiceLanguages() -> [String] { ["fa-IR", "ja-JP"] }
    var isSpeaking: Bool { false }
    func speak(text: String, voiceLanguage: String, rate: Double, onEnd: @escaping () -> Void) { onEnd() }
    func stop() {}
}

/// Gallery for snapshot tests: the prompt audio row, the answer field and (for typing states) the in-app keyboard, driven to a scenario by pressing real keys.
public struct TypeInShowcase: View {
    private let scenario: TypeInShowcaseScenario
    private let courseCode: String
    private let exercise: ExerciseArtifact
    private let state: KeyboardState?
    private let text: String
    private let reviewed: Reviewed?
    private let prefs: LocalPrefs

    @Environment(\.colorScheme) private var colorScheme

    public init(_ scenario: TypeInShowcaseScenario) {
        self.scenario = scenario
        var prefs = LocalPrefs()
        let persian = ExerciseArtifact(
            type: .typeIn, scriptMode: .native, prompt: "Good morning",
            answer: ["\u{0635}\u{0628}\u{062D} \u{0628}\u{062E}\u{06CC}\u{0631}"]
        )
        let japanese = ExerciseArtifact(
            type: .typeIn, scriptMode: .native, prompt: "I am a student",
            answer: ["\u{308F}\u{305F}\u{3057} \u{306F} \u{304C}\u{304F}\u{305B}\u{3044} \u{3067}\u{3059}"]
        )
        switch scenario {
        case .persianEmpty, .persianTyped, .persianMarkedWrong, .persianMarkedCorrect, .noVoice:
            self.courseCode = "fa"
            self.exercise = persian
        case .japaneseTyped, .japaneseMarkedWrong:
            self.courseCode = "ja"
            self.exercise = japanese
        case .speak:
            self.courseCode = "fa"
            self.exercise = ExerciseArtifact(type: .speak, scriptMode: .native, prompt: "Good morning", answer: persian.answer)
        }

        var typed = ""
        var keyboard: KeyboardState?
        var review: Reviewed?
        switch scenario {
        case .persianEmpty:
            prefs.persianInputMethod = .layout
            keyboard = KeyboardState(method: .persianLayout(isolated: false))
        case .persianTyped, .speak:
            prefs.persianInputMethod = .layout
            let k = KeyboardState(method: .persianLayout(isolated: false))
            typed = TypeInShowcase.press(k, labels: ["\u{0633}", "\u{0644}", "\u{0627}", "\u{0645}"], text: typed)
            keyboard = k
        case .japaneseTyped:
            prefs.japaneseInputMethod = .kana
            let k = KeyboardState(method: .japaneseKana)
            typed = TypeInShowcase.press(k, labels: ["\u{304B}", "\u{306A}"], text: typed)
            keyboard = k
        case .persianMarkedWrong:
            review = Reviewed(text: "\u{0635}\u{0628}\u{062D} \u{0634}\u{0628}", correct: false)
        case .japaneseMarkedWrong:
            review = Reviewed(text: "\u{308F}\u{305F}\u{3057} \u{304C} \u{304C}\u{304F}\u{305B}\u{3044}", correct: false)
        case .persianMarkedCorrect:
            review = Reviewed(text: persian.answer[0], correct: true)
        case .noVoice:
            break
        }
        self.state = keyboard
        self.text = typed
        self.reviewed = review
        self.prefs = prefs
    }

    private static func press(_ state: KeyboardState, labels: [String], text start: String) -> String {
        var text = start
        for label in labels {
            guard let id = KeyboardShowcase.keyId(state, label: label) else { continue }
            let parts = id.split(separator: ":").compactMap { Int($0) }
            guard parts.count == 2 else { continue }
            let key = state.layout.rows[parts[0]][parts[1]]
            text = state.press(key.action, keyId: id, textBefore: text).applyTo(text)
        }
        return text
    }

    public var body: some View {
        let p = colorScheme == .dark ? AppPalette.dark : AppPalette.light
        let synthesizer: SpeechSynthesizing = scenario == .noVoice ? NoVoiceSynthesizer() : VoicedSynthesizer()
        let speech = SpeechService(synthesizer: synthesizer)
        VStack(alignment: .leading, spacing: Spacing.standard.s3) {
            PromptAudioControls(
                speech: speech,
                languageTag: Languages.languageInfo(courseCode)?.speechTag ?? "en-US",
                hasRecording: false,
                palette: p,
                onPlay: {}, onPlaySlow: {}, onInstallVoice: {}
            )
            Text(exercise.prompt)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(Color(argb: p.text))
            field(p)
            Spacer(minLength: 0)
            if let state = state {
                TypeInKeyboardPanel(
                    courseCode: courseCode,
                    prefs: prefs,
                    state: state,
                    palette: p,
                    text: { text },
                    onEdit: { _ in },
                    onPrefsChange: { _ in }
                )
            }
        }
        .padding(.top, Spacing.standard.s3)
        .padding(.horizontal, Spacing.standard.s3)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(argb: p.bg))
    }

    @ViewBuilder
    private func field(_ p: AppPalette) -> some View {
        let binding = Binding<String>(get: { text }, set: { _ in })
        if scenario == .speak {
            SpeakExercise(exercise: exercise, courseCode: courseCode, instanceKey: "speak", text: binding, inAppKeyboard: true, palette: p)
        } else {
            TypeInExercise(
                exercise: exercise,
                courseCode: courseCode,
                instanceKey: "showcase",
                reviewed: reviewed,
                text: binding,
                inAppKeyboard: state != nil || scenario == .noVoice,
                palette: p
            )
        }
    }
}
