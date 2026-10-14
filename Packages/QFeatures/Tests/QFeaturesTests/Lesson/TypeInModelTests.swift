import XCTest
import QModel
import QDomain
import QData
import QKeyboard
@testable import QFeatures

final class TypeInModelTests: XCTestCase {
    private func exercise(_ answer: [String], mode: ExerciseScriptMode = .native) -> ExerciseArtifact {
        return ExerciseArtifact(type: .typeIn, scriptMode: mode, prompt: "p", answer: answer)
    }

    func testInAppKeyboardOnlyForNativePersianAndJapanese() {
        XCTAssertTrue(TypeInModel.hasInAppKeyboard(courseCode: "fa", scriptMode: .native))
        XCTAssertTrue(TypeInModel.hasInAppKeyboard(courseCode: "ja", scriptMode: .native))
        XCTAssertFalse(TypeInModel.hasInAppKeyboard(courseCode: "fa", scriptMode: .romanized))
        XCTAssertFalse(TypeInModel.hasInAppKeyboard(courseCode: "de", scriptMode: .native))
    }

    func testInputMethodFollowsPrefs() {
        var prefs = LocalPrefs()
        prefs.persianInputMethod = .layout
        XCTAssertEqual(TypeInModel.inputMethod(courseCode: "fa", scriptMode: .native, prefs: prefs, keyboardMode: "isolated"), .persianLayout(isolated: true))
        XCTAssertEqual(TypeInModel.inputMethod(courseCode: "fa", scriptMode: .native, prefs: prefs, keyboardMode: nil), .persianLayout(isolated: false))
        prefs.persianInputMethod = .phonetic
        XCTAssertEqual(TypeInModel.inputMethod(courseCode: "fa", scriptMode: .native, prefs: prefs, keyboardMode: nil), .persianPhonetic)
        prefs.japaneseInputMethod = .kana
        XCTAssertEqual(TypeInModel.inputMethod(courseCode: "ja", scriptMode: .native, prefs: prefs, keyboardMode: nil), .japaneseKana)
        prefs.japaneseInputMethod = .romaji
        XCTAssertEqual(TypeInModel.inputMethod(courseCode: "ja", scriptMode: .native, prefs: prefs, keyboardMode: nil), .japaneseRomaji)
        XCTAssertNil(TypeInModel.inputMethod(courseCode: "ja", scriptMode: .romanized, prefs: prefs, keyboardMode: nil))
        XCTAssertNil(TypeInModel.inputMethod(courseCode: "xx", scriptMode: .native, prefs: prefs, keyboardMode: nil))
    }

    func testReviewMarksCorrectAnswerAllRight() {
        let words = TypeInModel.reviewWords(courseCode: "ja", exercise: exercise(["a b"]), reviewed: Reviewed(text: "a b", correct: true), vowelMarks: true)
        XCTAssertEqual(words, [MarkedWord(text: "a", mark: .right), MarkedWord(text: "b", mark: .right)])
        XCTAssertNil(TypeInModel.missingWordsText(words))
    }

    func testReviewShowsMissingWord() {
        let words = TypeInModel.reviewWords(courseCode: "ja", exercise: exercise(["one two three"]), reviewed: Reviewed(text: "one two", correct: false), vowelMarks: true)
        XCTAssertEqual(TypeInModel.missingWordsText(words), "three")
        XCTAssertEqual(words.last, MarkedWord(text: "three", mark: .missing))
    }

    func testMissingWordLosesVowelMarksWhenOff() {
        let withMarks = "\u{0635}\u{064E}\u{0628}\u{062D}"
        let on = TypeInModel.reviewWords(courseCode: "fa", exercise: exercise(["x " + withMarks]), reviewed: Reviewed(text: "x", correct: false), vowelMarks: true)
        let off = TypeInModel.reviewWords(courseCode: "fa", exercise: exercise(["x " + withMarks]), reviewed: Reviewed(text: "x", correct: false), vowelMarks: false)
        XCTAssertEqual(TypeInModel.missingWordsText(on), withMarks)
        XCTAssertEqual(TypeInModel.missingWordsText(off), "\u{0635}\u{0628}\u{062D}")
    }

    func testShownTextSplitsAtCaret() {
        let s = TypeInModel.shownText(text: "abcd", caret: 2, pending: "x")
        XCTAssertEqual(s, TypeInShownText(before: "ab", pending: "x", after: "cd"))
        XCTAssertEqual(TypeInModel.shownText(text: "ab", caret: 99, pending: nil), TypeInShownText(before: "ab", pending: "", after: ""))
        XCTAssertEqual(TypeInModel.shownText(text: "ab", caret: -3, pending: nil).before, "")
    }

    func testShownTextCaretIsUnicodeScalarsWithZwnjAndVowelMarks() {
        // Letters with a fatha and a ZWNJ: Characters and scalars differ.
        let text = "\u{062E}\u{064E}\u{0627}\u{0646}\u{0647}\u{200C}\u{0647}\u{0627}"
        XCTAssertEqual(text.count, 6)
        XCTAssertEqual(text.unicodeScalars.count, 8)
        let s = TypeInModel.shownText(text: text, caret: 6, pending: nil)
        XCTAssertEqual(s.before, "\u{062E}\u{064E}\u{0627}\u{0646}\u{0647}\u{200C}")
        XCTAssertEqual(s.after, "\u{0647}\u{0627}")
        XCTAssertEqual(TypeInModel.shownText(text: text, caret: 8, pending: nil).after, "")
    }

    func testCaretForTapSnapsToLetterBoundaryInScalars() {
        let text = "\u{062E}\u{064E}\u{0627}\u{0646}"  // 3 Characters, 4 scalars
        XCTAssertEqual(TypeInModel.caretForTap(text: text, fraction: 0), 0)
        XCTAssertEqual(TypeInModel.caretForTap(text: text, fraction: 0.34), 2)
        XCTAssertEqual(TypeInModel.caretForTap(text: text, fraction: 1.5), 4)
        XCTAssertEqual(TypeInModel.caretForTap(text: "", fraction: 0.5), 0)
    }

    func testReviewAccessibilityValueSpeaksEveryMark() {
        let words = [
            MarkedWord(text: "a", mark: .right), MarkedWord(text: "b", mark: .wrong),
            MarkedWord(text: "c", mark: .swapped), MarkedWord(text: "d", mark: .missing)
        ]
        XCTAssertEqual(TypeInModel.reviewAccessibilityValue(words), "a, right. b, wrong. c, right word, wrong place. d, missing")
        XCTAssertEqual(TypeInModel.reviewAccessibilityValue([]), TypeInModel.nothingSubmitted)
    }

    func testArabicVariantNoteOnlyForNativePersian() {
        let arabicYeh = "\u{064A}"
        XCTAssertNotNil(TypeInModel.arabicVariantNote(courseCode: "fa", scriptMode: .native, text: arabicYeh))
        XCTAssertNil(TypeInModel.arabicVariantNote(courseCode: "fa", scriptMode: .romanized, text: arabicYeh))
        XCTAssertNil(TypeInModel.arabicVariantNote(courseCode: "ja", scriptMode: .native, text: arabicYeh))
        XCTAssertNil(TypeInModel.arabicVariantNote(courseCode: "fa", scriptMode: .native, text: "\u{06CC}"))
    }

    func testPlaceholderAndDirection() {
        XCTAssertEqual(TypeInModel.placeholder(scriptMode: .romanized, inAppKeyboard: false), "Type in Latin letters")
        XCTAssertEqual(TypeInModel.placeholder(scriptMode: .native, inAppKeyboard: false), "Type your answer")
        XCTAssertTrue(TypeInModel.fieldIsRtl(courseCode: "fa", scriptMode: .native))
        XCTAssertFalse(TypeInModel.fieldIsRtl(courseCode: "fa", scriptMode: .romanized))
        XCTAssertFalse(TypeInModel.fieldIsRtl(courseCode: "ja", scriptMode: .native))
        XCTAssertEqual(TypeInModel.answerDescription("", reviewing: false), "Your answer: empty")
        XCTAssertEqual(TypeInModel.answerDescription("", reviewing: true), "Your answer: nothing")
    }

    func testCanSpeak() {
        XCTAssertTrue(TypeInModel.canSpeak(hasVoice: true, hasPromptAudio: false))
        XCTAssertTrue(TypeInModel.canSpeak(hasVoice: false, hasPromptAudio: true))
        XCTAssertFalse(TypeInModel.canSpeak(hasVoice: false, hasPromptAudio: false))
    }
}
