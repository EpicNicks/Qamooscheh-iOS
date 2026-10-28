import Foundation
import CoreGraphics
import QModel
import QDomain
import QData
import QKeyboard

// The decisions behind the lesson screen, SwiftUI-free so swift test covers them. Port of
// the logic half of Android feature/lesson LessonScreen.kt and LessonSettings.kt (where web
// LessonPage / ExerciseSessionScreen differ, Android wins).

/// Everything needed to play one lesson, assembled by the caller (plan fetched, skills read from
/// disk, cards merged: `buildInstances`).
public struct LessonSetup: Equatable, Sendable {
    public var courseCode: String
    public var courseVersion: Int
    public var instances: [ExerciseInstance]
    /// Exercises per skill key, for the server's "every exercise answered" completion rule.
    public var exerciseCountBySkill: [String: Int]
    /// Practice: nothing is submitted.
    public var practice: Bool
    /// Non-nil makes this a checkpoint (a test-out): "Skipping 3 lessons." under the progress bar, "Next" instead of "Check", and its own leave warning.
    public var checkpointSummary: String?
    /// Non-nil for a real checkpoint: answers are not marked, and everything is sent once at the end.
    public var checkpoint: CheckpointPlanInfo?
    /// Non-nil makes this a story chapter: read once through, with the transcript of earlier lines above the current one.
    public var story: StoryChapter?

    public init(courseCode: String, courseVersion: Int, instances: [ExerciseInstance], exerciseCountBySkill: [String: Int] = [:], practice: Bool = false, checkpointSummary: String? = nil, checkpoint: CheckpointPlanInfo? = nil, story: StoryChapter? = nil) {
        self.courseCode = courseCode
        self.courseVersion = courseVersion
        self.instances = instances
        self.exerciseCountBySkill = exerciseCountBySkill
        self.practice = practice
        self.checkpointSummary = checkpointSummary
        self.checkpoint = checkpoint
        self.story = story
    }

    public var isCheckpoint: Bool { checkpointSummary != nil || checkpoint != nil }
}

/// The server-side prefs a lesson reads (the lesson settings' "Text mode" changes one of them).
public struct LessonServerPrefs: Equatable, Sendable {
    public var scriptMode: ScriptMode
    public var keyboardMode: KeyboardMode
    public var autoplayAudio: Bool

    public init(scriptMode: ScriptMode = .native, keyboardMode: KeyboardMode = .contextual, autoplayAudio: Bool = false) {
        self.scriptMode = scriptMode
        self.keyboardMode = keyboardMode
        self.autoplayAudio = autoplayAudio
    }
}

/// Streak and daily-goal numbers for the results screen; all optional (offline, or not loaded).
public struct LessonResultsExtras: Equatable, Sendable {
    public var streakDays: Int?
    public var goalXpToday: Int?
    public var goalXp: Int?

    public init(streakDays: Int? = nil, goalXpToday: Int? = nil, goalXp: Int? = nil) {
        self.streakDays = streakDays
        self.goalXpToday = goalXpToday
        self.goalXp = goalXp
    }

    public static let none = LessonResultsExtras()
}

public enum LessonScreenLogic {
    /// Why a lesson could not start, in words the learner can act on.
    public static func loadFailureMessage(for error: Error) -> String {
        if let known = error as? LessonEnvironmentError, known == .signedOut {
            return "You're signed out. Sign in again to start this lesson."
        }
        if error is UnwiredLessonSetupLoader.NotWired {
            return "This lesson isn't available in this version of the app yet."
        }
        if error is URLError {
            return "Check your connection and try again."
        }
        return "Something went wrong while opening this lesson. Try again in a moment."
    }

    public static let saveFailedTitle = "Couldn't save your lesson"
    public static let saveFailedBody = "Your answers are kept on this phone. Try saving again."
    public static let checkLabel = "Check"
    public static let nextLabel = "Next"
    public static let leaveLessonTitle = "Leave this lesson?"
    public static let leaveLessonBody = "Your answers so far won't be saved, and nothing you've done here will count toward your progress."
    public static let leaveCheckpointTitle = "Leave this checkpoint?"
    public static let leaveCheckpointBody = "Your answers so far won't be saved, and you'll go back to the path without skipping anything."
    public static let leaveConfirm = "Leave"
    public static let keepGoing = "Keep going"
    public static let syncNote = "Answers will be checked when you sync."
    public static let loadingTitle = "Loading your lesson\u{2026}"
    public static let failedTitle = "Couldn't start this lesson"
    public static let nothingDueTitle = "Nothing due right now"
    public static let nothingDueBody = "Nothing's scheduled here right now."
    public static let backToPath = "Back to path"
    public static let settingsTitle = "Lesson settings"

    /// Type-in, speak and listening share the typing field and keyboard; word bank and match share the tiles.
    public static func isTypeIn(_ type: ExerciseType) -> Bool {
        return type == .typeIn || type == .speak || type == .listenType
    }

    public static func checkButtonLabel(isCheckpoint: Bool) -> String {
        return isCheckpoint ? nextLabel : checkLabel
    }

    /// Check is enabled once there is an answer: typed text (or letters still pending in the keyboard), or a finished tile order.
    public static func canCheck(typeIn: Bool, typed: String, keyboardPending: String?, tileAnswer: String?) -> Bool {
        if typeIn {
            let blank = typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            return !blank || (keyboardPending?.isEmpty == false)
        }
        return tileAnswer != nil
    }

    /// The text submitted for Check: typed text must not be blank (Android `takeIf(isNotBlank)`).
    public static func submittableText(typeIn: Bool, typed: String, tileAnswer: String?) -> String? {
        if typeIn {
            return typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : typed
        }
        return tileAnswer
    }

    /// The in-app keyboard is used when the course has one for this exercise and the learner has not chosen the phone's own.
    public static func usesInAppKeyboard(method: InputMethod?, prefs: LocalPrefs) -> Bool {
        return method != nil && !prefs.deviceInputEnabled
    }

    /// The caret after a tap in the answer at `to` (an index into the text as shown): a half-typed letter was committed first, so a spot after the old caret moved with the text. Clamped into the text.
    public static func caretAfterTap(to: Int, oldCaret: Int, oldLength: Int, newLength: Int) -> Int {
        let moved = to > oldCaret ? to + newLength - oldLength : to
        return min(max(moved, 0), newLength)
    }

    /// One arrow-key step on a hardware keyboard: right moves forward unless the text runs right to left.
    public static func caretAfterArrow(caret: Int, length: Int, rightKey: Bool, rtl: Bool) -> Int {
        let forward = rightKey != rtl
        return min(max(caret + (forward ? 1 : -1), 0), length)
    }

    /// The text look for the lesson (Android `LessonTextLook` assembly in Session).
    public static func textLook(prefs: LocalPrefs, serverPrefs: LessonServerPrefs, courseCode: String, hints: [String: WordHint]) -> LessonTextLook {
        let language = Languages.languageInfo(courseCode)?.language
        let font = Languages.isPersian(courseCode) ? prefs.fontFa : prefs.fontJa
        return LessonTextLook(
            settings: TextDisplaySettings(
                display: resolveScriptDisplay(scriptMode: serverPrefs.scriptMode, language: language, showFurigana: prefs.showFurigana),
                translationEnabled: prefs.showTranslationHints,
                romanizationEnabled: prefs.showRomanizationHints,
                nativeEnabled: prefs.showNativeHints,
                vowelMarks: prefs.showVowelMarks,
                sentenceRomanization: prefs.showSentenceRomanization
            ),
            courseHints: hints,
            centerNative: prefs.nativeTextAlign == .center,
            nativeScale: CGFloat(font.sizePct) / 100
        )
    }

    /// What the results screen says, from the submit results of every session in the lesson (one per skill played).
    /// A server rejection wins; all answered by the server is saved (completion from the server, else the device's guess); anything still queued is offline.
    public static func endKind(results: [LessonSubmitResult], locallyCompleted: Bool?, practice: Bool) -> LessonEndKind {
        if practice || results.isEmpty { return .practice }
        var rejectedReason: String?
        var rejectedCount = 0
        var responses: [SubmittedSessionResponse] = []
        var anyQueued = false
        for result in results {
            switch result {
            case .submitted(let response):
                responses.append(response)
            case .queued, .queuedPermanentFailure:
                anyQueued = true
            case .rejected(let reason):
                rejectedCount += 1
                if rejectedReason == nil { rejectedReason = reason }
            }
        }
        if rejectedCount > 0 {
            return .rejected(partial: rejectedCount < results.count, reason: rejectedReason)
        }
        if anyQueued {
            return .queued(completed: locallyCompleted)
        }
        let flags = responses.compactMap { $0.lessonCompleted }
        var completed = locallyCompleted
        if flags.contains(true) {
            completed = true
        } else if flags.contains(false) {
            completed = false
        }
        let already = !responses.isEmpty && responses.allSatisfy { $0.outcome == .alreadyProcessed }
        return .saved(completed: completed, alreadyRecorded: already)
    }

    /// The language tag a play button speaks `text` in: the text's own, else the course's.
    public static func speechTag(courseCode: String, text: String) -> String? {
        return Languages.speechLang(courseCode, text) ?? Languages.languageInfo(courseCode)?.speechTag
    }
}

// MARK: Settings rows

/// One row of the lesson settings popover (Android LessonSettingsSheet), by course language.
public enum LessonSettingsRow: Equatable, Sendable {
    case textMode
    case textAlignment
    case furigana
    case romanizationTips
    case translationTips
    case nativeTips
    case vowelMarks
    case sentenceRomanization
    case keyboardMode
    /// The course script's font family and size (the same device-local pref as Settings; never synced).
    case font
}

/// One font family in the lesson's Font group.
public struct LessonFontOption: Equatable, Sendable {
    public let label: String
    /// The stored value (nil = default).
    public let family: String?
    /// False when the face is not installed on this device; the choice is shown greyed out.
    public let available: Bool
}

/// The lesson's compact Font group: family choices (Persian only) and the size percentage. No custom-font entry.
public struct LessonFontGroup: Equatable, Sendable {
    public let options: [LessonFontOption]
    public let selectedFamily: String?
    public let sizePct: Int
}

public enum LessonSettingsRows {
    /// Rows in display order. Furigana is Japanese's; alignment, vowel marks and sentence romanization are Persian's; the keyboard mode applies to the Persian layout keyboard.
    public static func rows(courseCode: String, prefs: LocalPrefs, hasServerPrefs: Bool) -> [LessonSettingsRow] {
        let language = Languages.languageInfo(courseCode)?.language
        let persian = language == "fa"
        var rows: [LessonSettingsRow] = []
        if hasServerPrefs { rows.append(.textMode) }
        if persian { rows.append(.textAlignment) }
        if language == "ja" { rows.append(.furigana) }
        rows.append(.romanizationTips)
        rows.append(.translationTips)
        rows.append(.nativeTips)
        if persian {
            rows.append(.vowelMarks)
            rows.append(.sentenceRomanization)
            if hasServerPrefs && prefs.persianInputMethod == .layout { rows.append(.keyboardMode) }
        }
        if persian || language == "ja" { rows.append(.font) }
        return rows
    }

    /// The Font group for the course script; nil for a course with no native-script font setting.
    public static func fontGroup(courseCode: String, prefs: LocalPrefs, isAvailable: (String) -> Bool) -> LessonFontGroup? {
        guard let language = Languages.languageInfo(courseCode)?.language, language == "fa" || language == "ja" else { return nil }
        let pref = language == "fa" ? prefs.fontFa : prefs.fontJa
        var options: [LessonFontOption] = []
        if language == "fa" {
            for choice in persianFontChoices {
                let available = choice.family.map { isAvailable($0) } ?? true
                options.append(LessonFontOption(label: choice.label, family: choice.family, available: available))
            }
        }
        let selected = options.contains(where: { $0.family == pref.family }) ? pref.family : nil
        return LessonFontGroup(options: options, selectedFamily: selected, sizePct: min(150, max(75, pref.sizePct)))
    }

    /// The prefs with the course script's font family set (what Settings stores).
    public static func settingFontFamily(_ family: String?, courseCode: String, in prefs: LocalPrefs) -> LocalPrefs {
        var next = prefs
        if Languages.isPersian(courseCode) { next.fontFa.family = family } else { next.fontJa.family = family }
        return next
    }

    /// The prefs with the course script's size set, snapped to 5-point steps within 75...150.
    public static func settingFontSize(_ value: Double, courseCode: String, in prefs: LocalPrefs) -> LocalPrefs {
        var next = prefs
        let pct = snapFontPercent(value)
        if Languages.isPersian(courseCode) { next.fontFa.sizePct = pct } else { next.fontJa.sizePct = pct }
        return next
    }

    public static func label(_ row: LessonSettingsRow, languageName: String) -> String {
        switch row {
        case .textMode: return "Text mode"
        case .textAlignment: return "Text alignment"
        case .furigana: return "Furigana over kanji"
        case .romanizationTips: return "Tap a word for its romanization"
        case .translationTips: return "Tap a word for its translation"
        case .nativeTips: return "Tap an English word for the \(languageName)"
        case .vowelMarks: return "Show vowel marks and the ezafe"
        case .sentenceRomanization: return "Show each sentence romanized above it"
        case .keyboardMode: return "Keyboard letter shapes"
        case .font: return "Font"
        }
    }

    public static let textModeHelp = "Applies to the text on screen right away, and to which exercises you get next."

    /// Reads a switch row from the prefs; nil for rows that are not switches.
    public static func isOn(_ row: LessonSettingsRow, prefs: LocalPrefs) -> Bool? {
        switch row {
        case .furigana: return prefs.showFurigana
        case .romanizationTips: return prefs.showRomanizationHints
        case .translationTips: return prefs.showTranslationHints
        case .nativeTips: return prefs.showNativeHints
        case .vowelMarks: return prefs.showVowelMarks
        case .sentenceRomanization: return prefs.showSentenceRomanization
        case .textMode, .textAlignment, .keyboardMode, .font: return nil
        }
    }

    /// The prefs with a switch row set; unchanged for rows that are not switches.
    public static func setting(_ row: LessonSettingsRow, to on: Bool, in prefs: LocalPrefs) -> LocalPrefs {
        var next = prefs
        switch row {
        case .furigana: next.showFurigana = on
        case .romanizationTips: next.showRomanizationHints = on
        case .translationTips: next.showTranslationHints = on
        case .nativeTips: next.showNativeHints = on
        case .vowelMarks: next.showVowelMarks = on
        case .sentenceRomanization: next.showSentenceRomanization = on
        case .textMode, .textAlignment, .keyboardMode, .font: break
        }
        return next
    }

    /// The three text modes, in the toggle's order.
    public static let textModes: [(mode: ScriptMode, label: String)] = [
        (.native, "Native"), (.both, "Both"), (.romanized, "Latin"),
    ]

    public static let alignments: [(align: NativeTextAlign, label: String)] = [
        (.start, "Start"), (.center, "Center"),
    ]

    public static let keyboardModes: [(mode: KeyboardMode, label: String)] = [
        (.contextual, "Connected"), (.isolated, "Separate"),
    ]
}
