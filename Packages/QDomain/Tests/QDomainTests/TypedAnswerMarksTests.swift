import XCTest
@testable import QDomain

final class TypedAnswerMarksTests: XCTestCase {
    private func mark(_ course: String, _ accepted: [String], _ submitted: String, _ correct: Bool = false) -> [MarkedWord] {
        return TypedAnswerMarks.markTypedAnswer(courseCode: course, acceptedAnswers: accepted, submitted: submitted, correct: correct)
    }

    func testCorrectAnswerAllGreenTyposIncluded() {
        XCTAssertEqual(mark("fa", ["man be madreseh miravam"], "man be madrese miravam", true).map { $0.mark }, [.right, .right, .right, .right])
    }

    func testMarksOnlyWordsOutsideBestAlignmentWrong() {
        XCTAssertEqual(mark("en", ["I go to school"], "I went to school"), [
            MarkedWord(text: "I", mark: .right),
            MarkedWord(text: "went", mark: .wrong),
            MarkedWord(text: "to", mark: .right),
            MarkedWord(text: "school", mark: .right),
        ])
    }

    func testIgnoresCaseAndPunctuationAndUsesClosestAnswer() {
        XCTAssertEqual(mark("en", ["Hello, how are you?", "Hi, how are you?"], "hi how is you").map { $0.mark }, [.right, .right, .wrong, .right])
    }

    func testForgivesArabicCodepointsButNotMissingHalfSpace() {
        let zw = "\u{200C}"
        // Arabic yeh for Persian yeh is forgiven; the verb typed without its ZWNJ is a misspelling.
        XCTAssertEqual(mark("fa", ["من می\(zw)روم"], "\u{0645}\u{0646}\u{064A} میروم").map { $0.mark }, [.wrong, .wrong])
        XCTAssertEqual(mark("fa", ["من می\(zw)روم"], "من \u{0645}\u{064A}\(zw)روم").map { $0.mark }, [.right, .right])
        XCTAssertEqual(mark("fa", ["\u{0639}\u{0644}\u{064A}"], "\u{0639}\u{0644}\u{06CC}")[0].mark, .right)
    }

    func testMarksSingleSwappedPair() {
        XCTAssertEqual(mark("en", ["I go to school"], "I to go school").map { $0.mark }, [.right, .swapped, .swapped, .right])
    }

    // missing words (issue #38)

    private func show(_ accepted: [String], _ submitted: String) -> [String] {
        return mark("en", accepted, submitted).map { $0.mark == .missing ? "+\($0.text)" : $0.text }
    }

    func testPutsLeftOutWordWhereItBelongs() {
        XCTAssertEqual(show(["I am buying a bag"], "I buying a bag"), ["I", "+am", "buying", "a", "bag"])
        XCTAssertEqual(show(["Hello, how are you?"], "how are you"), ["+Hello,", "how", "are", "you"])
        XCTAssertEqual(mark("en", ["I am buying a bag"], "I buying a bag")[1], MarkedWord(text: "am", mark: .missing))
    }

    func testMissingMeasuredAgainstClosestAnswer() {
        XCTAssertEqual(show(["Hello, how are you?", "Hi, how are you?"], "hi are you"), ["hi", "+how", "are", "you"])
    }

    func testAddsNothingForMisspelledWord() {
        XCTAssertEqual(show(["I am buying a bag"], "I am buying a cat"), ["I", "am", "buying", "a", "cat"])
        XCTAssertEqual(show(["I am buying a bag"], "I buying a cat"), ["I", "+am", "buying", "a", "cat"])
        // A missing half-space is a misspelling too.
        XCTAssertFalse(mark("fa", ["من می\u{200C}خرم"], "من میخرم").contains { $0.mark == .missing })
    }

    func testAddsNothingForSwappedPairCorrectAnswerOrTooFarOff() {
        XCTAssertEqual(show(["I go to school"], "I to go school"), ["I", "to", "go", "school"])
        XCTAssertFalse(mark("en", ["I go"], "I go", true).contains { $0.mark == .missing })
        XCTAssertEqual(show(["I am buying a bag"], "bag"), ["bag"])
    }

    // markSeparatorGaps

    private let matched = "من می\u{200C}خرم"

    func testCutsMatchedAnswerAroundFlaggedSeparators() {
        XCTAssertEqual(TypedAnswerMarks.markSeparatorGaps(matched, [SeparatorEdit(kind: .missingZwnj, index: 5, length: 1)]), [
            SeparatorSpan(text: "من می", gap: false),
            SeparatorSpan(text: "\u{200C}", gap: true),
            SeparatorSpan(text: "خرم", gap: false),
        ])
    }

    func testExtraSeparatorIsEmptyCaretInIndexOrder() {
        let spans = TypedAnswerMarks.markSeparatorGaps(matched, [
            SeparatorEdit(kind: .extraSpace, index: 1, length: 0),
            SeparatorEdit(kind: .missingZwnj, index: 5, length: 1),
        ])
        XCTAssertEqual(spans.map { $0.gap }, [false, true, false, true, false])
    }

    func testSkipsEditThatDoesNotFit() {
        XCTAssertEqual(TypedAnswerMarks.markSeparatorGaps("ab", [SeparatorEdit(kind: .missingSpace, index: 5, length: 1)]), [SeparatorSpan(text: "ab", gap: false)])
    }
}
