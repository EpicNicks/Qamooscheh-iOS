import Foundation
import QModel
import QDomain
import QData
import QKeyboard

// The decisions behind the type-in and speak exercises, SwiftUI-free so swift test
// covers them. Port of the logic half of Android feature/lesson Exercises.kt
// (TypeInExercise) and TypeInKeyboard.kt (engineFor, hasInAppKeyboard).

/// What a submitted answer looks like on review: the learner's text and whether it was right.
public struct Reviewed: Equatable, Sendable {
    public var text: String
    public var correct: Bool

    public init(text: String, correct: Bool) {
        self.text = text
        self.correct = correct
    }
}

/// The learner's text split around the caret, with the keyboard's uncommitted letters between.
public struct TypeInShownText: Equatable, Sendable {
    public var before: String
    public var pending: String
    public var after: String
}

public enum TypeInModel {
    /// A tap in the field moves the caret to the offset tapped; Android's 1.3x font scale is where the keyboard header stacks.
    public static let stackFontScale: Double = 1.3

    /// Whether this course has an in-app keyboard to switch to at all.
    public static func hasInAppKeyboard(courseCode: String?, scriptMode: ExerciseScriptMode) -> Bool {
        guard scriptMode == .native else { return false }
        let language = Languages.languageInfo(courseCode)?.language
        return language == "fa" || language == "ja"
    }

    /// The in-app keyboard for a type-in answer: only native-script exercises get one, and which one is this device's choice. `keyboardMode` is the server's "contextual"/"isolated" pref.
    public static func inputMethod(courseCode: String?, scriptMode: ExerciseScriptMode, prefs: LocalPrefs, keyboardMode: String?) -> InputMethod? {
        guard scriptMode == .native else { return nil }
        switch Languages.languageInfo(courseCode)?.language {
        case "fa":
            switch prefs.persianInputMethod {
            case .layout: return .persianLayout(isolated: keyboardMode == "isolated")
            case .phonetic: return .persianPhonetic
            }
        case "ja":
            switch prefs.japaneseInputMethod {
            case .kana: return .japaneseKana
            case .romaji: return .japaneseRomaji
            }
        default:
            return nil
        }
    }

    /// Whether `text` reads right to left in this course (native Persian does; romanized never does).
    public static func isRtl(courseCode: String?, text: String) -> Bool {
        return Languages.writingDirection(courseCode) == .rtl && Languages.isNativeText(courseCode, text)
    }

    /// Whether the typing field itself runs right to left: a native-script exercise in an RTL course.
    public static func fieldIsRtl(courseCode: String?, scriptMode: ExerciseScriptMode) -> Bool {
        return scriptMode == .native && Languages.writingDirection(courseCode) == .rtl
    }

    /// The typed words, marked against the closest accepted answer. A missing word is the accepted answer's own spelling, so it carries the vowel marks content writes: shown only when the learner has those on.
    public static func reviewWords(courseCode: String?, exercise: ExerciseArtifact, reviewed: Reviewed, vowelMarks: Bool) -> [MarkedWord] {
        let marked = TypedAnswerMarks.markTypedAnswer(
            courseCode: courseCode,
            acceptedAnswers: exercise.answer,
            submitted: reviewed.text,
            correct: reviewed.correct
        )
        return marked.map { word in
            if word.mark == .missing && !vowelMarks {
                return MarkedWord(text: PersianNormalize.stripReadingAids(word.text), mark: .missing)
            }
            return word
        }
    }

    /// The words the learner left out, space-joined, or nil when none.
    public static func missingWordsText(_ words: [MarkedWord]) -> String? {
        let missing = words.filter { $0.mark == .missing }.map { $0.text }
        if missing.isEmpty { return nil }
        return missing.joined(separator: " ")
    }

    public static let missingLabel = "Close. Missing words:"
    public static let nothingSubmitted = "(nothing submitted)"

    public static func answerDescription(_ text: String, reviewing: Bool) -> String {
        return "Your answer: " + (text.isEmpty ? (reviewing ? "nothing" : "empty") : text)
    }

    public static func placeholder(scriptMode: ExerciseScriptMode, inAppKeyboard: Bool) -> String {
        if !inAppKeyboard && scriptMode == .romanized { return "Type in Latin letters" }
        return "Type your answer"
    }

    /// Persian answers get a nudge for Arabic-only letters, never a block.
    public static func arabicVariantNote(courseCode: String?, scriptMode: ExerciseScriptMode, text: String) -> String? {
        guard Languages.isPersian(courseCode), scriptMode == .native else { return nil }
        return PersianNormalize.detectArabicVariants(text).first?.label
    }

    public static let romanizedPromptNote = "Type this one in Latin letters (romanized), not the native script."
    public static let speakNote = "Speech capture isn't wired up yet \u{2014} type what you'd say."
    public static let hintLink = "Use a hint"
    public static let phoneKeyboardLabel = "Phone keyboard"
    public static let inAppKeyboardLabel = "Use the in-app keyboard"

    /// The text split at the caret (a Unicode-scalar offset, clamped into the text, the same unit as the keyboard's `Edit.applyAt`), with the keyboard's pending letters shown between.
    public static func shownText(text: String, caret: Int, pending: String?) -> TypeInShownText {
        let scalars = Array(text.unicodeScalars)
        let at = min(max(caret, 0), scalars.count)
        var head = String.UnicodeScalarView()
        head.append(contentsOf: scalars[0..<at])
        var tail = String.UnicodeScalarView()
        tail.append(contentsOf: scalars[at...])
        return TypeInShownText(before: String(head), pending: pending ?? "", after: String(tail))
    }

    /// The caret (a scalar offset) for a tap `fraction` of the way along the text from its leading edge. Snaps to a letter boundary, so a letter with its vowel marks is never split.
    public static func caretForTap(text: String, fraction: Double) -> Int {
        let chars = Array(text)
        if chars.isEmpty { return 0 }
        let f = min(max(fraction.isNaN ? 1 : fraction, 0), 1)
        let index = min(max(Int((f * Double(chars.count)).rounded()), 0), chars.count)
        var scalarOffset = 0
        for c in chars[0..<index] { scalarOffset += c.unicodeScalars.count }
        return scalarOffset
    }

    /// Screen-reader text for one reviewed word: the mark is spoken, not only coloured.
    public static func markSpoken(_ word: MarkedWord) -> String {
        switch word.mark {
        case .right: return word.text + ", right"
        case .wrong: return word.text + ", wrong"
        case .swapped: return word.text + ", right word, wrong place"
        case .missing: return word.text + ", missing"
        }
    }

    /// The review answer's accessibility value: every word with its mark.
    public static func reviewAccessibilityValue(_ words: [MarkedWord]) -> String {
        if words.isEmpty { return nothingSubmitted }
        return words.map { markSpoken($0) }.joined(separator: ". ")
    }

    /// Play-button states (Android ExercisePrompt): with a voice or recorded audio it plays; with neither it points at installing a voice.
    public static func canSpeak(hasVoice: Bool, hasPromptAudio: Bool) -> Bool {
        return hasVoice || hasPromptAudio
    }

    public static let playLabel = "Play audio"
    public static let playSlowLabel = "Play slowly"
    public static let noVoiceLabel = "No voice installed for this language. Install one"
}
