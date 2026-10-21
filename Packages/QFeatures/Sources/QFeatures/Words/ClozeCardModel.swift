import Foundation
import Combine
import QModel
import QDomain
import QData
import QKeyboard

/// One fill-in-the-blank card (web ClozeCard, Android ClozeCardView): the sentence has the word's English where it
/// belongs, and the learner types the word in the same field, on the same keyboards, a typed exercise has. A wrong
/// answer is tried again, each attempt paying less, until it is right or the learner shows the answer.
/// SwiftUI-free so swift test covers it; `ClozeCardView` binds it.
@MainActor
public final class ClozeCardModel: ObservableObject {
    public let card: ClozeCard
    public let courseCode: String
    public let hardcore: Bool

    @Published public private(set) var prefs: LocalPrefs
    @Published public private(set) var keyboard: KeyboardState?
    /// The typing field's text and the caret in it (a Unicode-scalar offset).
    @Published public private(set) var typed = ""
    @Published public private(set) var caret = 0
    @Published public private(set) var attempt = 1
    /// Set once the card is answered: right (maybe after forgiving a typo) or shown.
    @Published public private(set) var answered = false
    @Published public private(set) var correct = false
    @Published public private(set) var typo = false
    @Published public private(set) var answeredText = ""

    private var endedOn = 1
    private var keyboardMethod: InputMethod?
    private let keyboardMode: String?
    private let clock: () -> TimeInterval
    private let shownAt: TimeInterval
    private let onPrefsChange: (LocalPrefs) -> Void
    private let onEffect: (FeedbackEvent) -> Void
    private var finishedOnce = false

    public init(
        card: ClozeCard, courseCode: String, hardcore: Bool, prefs: LocalPrefs, keyboardMode: String?,
        clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        onPrefsChange: @escaping (LocalPrefs) -> Void = { _ in },
        onEffect: @escaping (FeedbackEvent) -> Void = { _ in }
    ) {
        self.card = card
        self.courseCode = courseCode
        self.hardcore = hardcore
        self.prefs = prefs
        self.keyboardMode = keyboardMode
        self.clock = clock
        self.shownAt = clock()
        self.onPrefsChange = onPrefsChange
        self.onEffect = onEffect
        rebuildKeyboard()
    }

    // MARK: Reading

    /// The typed-answer exercise the card plays through: its accepted spellings stand as the answer.
    public var exercise: ExerciseArtifact { card.asTypeIn }

    /// The in-app keyboard is used when the course has one and the learner has not chosen the phone's own, and not once answered.
    public var inAppKeyboard: Bool {
        return !answered && keyboard != nil && LessonScreenLogic.usesInAppKeyboard(method: keyboardMethod, prefs: prefs)
    }

    /// What the word reads as in the gap once answered: with its vowel marks only when the learner shows them.
    public var gapText: String {
        return prefs.showVowelMarks ? card.blankText : PersianNormalize.stripReadingAids(card.blankText)
    }

    /// The line above the sentence.
    public var status: String {
        if !answered { return clozeAttemptWorth(attempt) }
        if !correct { return "Here's the word." }
        if typo { return "Close, a small typo. It's spelled \(gapText)." }
        return endedOn == 1 ? "Correct! First try." : "Correct!"
    }

    /// Whether Check (or Continue) does anything: an answer is typed, or a letter is waiting on the keyboard.
    public func canCheck(keyboardPending: String?) -> Bool {
        if answered { return true }
        if !typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        return inAppKeyboard && keyboardPending != nil
    }

    /// "Show the answer" is offered from the second attempt on.
    public var canGiveUp: Bool { return !answered && attempt > 1 }

    // MARK: Typing

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

    /// Commits a half-typed letter where it was typed.
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

    public func updatePrefs(_ change: (inout LocalPrefs) -> Void) {
        commitPending()
        var next = prefs
        change(&next)
        if next == prefs { return }
        prefs = next
        onPrefsChange(next)
        rebuildKeyboard()
    }

    /// (Re)creates the in-app keyboard; kept when the method is unchanged so half-typed state survives.
    private func rebuildKeyboard() {
        let method = TypeInModel.inputMethod(courseCode: courseCode, scriptMode: .native, prefs: prefs, keyboardMode: keyboardMode)
        if method == keyboardMethod && (keyboard != nil) == (method != nil) { return }
        keyboardMethod = method
        keyboard = method.map { KeyboardState(method: $0) }
    }

    // MARK: Answering

    /// Grades what is typed, or, once answered, moves on: `onFinished` gets the card's result, once.
    public func check(onFinished: (ClozeResult) -> Void) {
        if answered {
            finish(onFinished)
            return
        }
        commitPending()
        if typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return }
        let text = typed
        switch gradeCloze(text, accepted: card.accepted, hardcore: hardcore) {
        case .exact:
            onEffect(.correct)
            settle(correct: true, text: text, typo: false)
        case .typo:
            onEffect(.correct)
            settle(correct: true, text: text, typo: true)
        case .wrong:
            onEffect(.incorrect)
            if attempt >= maxClozeAttempts {
                settle(correct: false, text: text, typo: false)
            } else {
                // A new attempt starts the field empty again.
                attempt += 1
                typed = ""
                caret = 0
            }
        }
    }

    /// Shows the word instead of trying again; the card counts as given up.
    public func giveUp() {
        if answered { return }
        settle(correct: false, text: "", typo: false)
    }

    private func settle(correct: Bool, text: String, typo: Bool) {
        answered = true
        self.correct = correct
        answeredText = text
        self.typo = typo
        endedOn = attempt
        keyboard = nil
        keyboardMethod = nil
    }

    private func finish(_ onFinished: (ClozeResult) -> Void) {
        if finishedOnce { return }
        finishedOnce = true
        let elapsed = Int(((clock() - shownAt) * 1000).rounded())
        onFinished(ClozeResult(tag: card.tag, correct: correct, attempt: endedOn, elapsedMs: min(max(elapsed, 0), 600_000)))
    }
}
