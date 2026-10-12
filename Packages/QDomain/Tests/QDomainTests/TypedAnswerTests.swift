import XCTest
@testable import QDomain

final class TypedAnswerTests: XCTestCase {
    private let z = "\u{200C}"

    /// How isolated mode writes a word: a ZWNJ after every letter.
    private func isolated(_ word: String) -> String {
        return word.unicodeScalars.map { String($0) + "\u{200C}" }.joined()
    }

    func testDropsIsolatedModeZwnjAfterEachLetter() {
        XCTAssertEqual(TypedAnswer.submittedSpelling(isolated("کتاب"), isolatedLetters: true), "کتاب")
        XCTAssertEqual(TypedAnswer.submittedSpelling("\(isolated("من")) \(isolated("رفتم"))", isolatedLetters: true), "من رفتم")
    }

    func testKeepsHalfSpaceTypedOnPurposeInIsolatedMode() {
        // می‌خرم: the ZWNJ key after ی adds a second one beside ی's own.
        let typed = "\(isolated("می"))\(z)\(isolated("خرم"))"
        XCTAssertEqual(TypedAnswer.submittedSpelling(typed, isolatedLetters: true), "می\(z)خرم")
    }

    func testLeavesContextualAnswersHalfSpacesAlone() {
        XCTAssertEqual(TypedAnswer.submittedSpelling("می\(z)خرم", isolatedLetters: false), "می\(z)خرم")
    }

    func testTrimsHalfSpaceAtEitherEndOrBesideSpace() {
        XCTAssertEqual(TypedAnswer.submittedSpelling("\(z)کتاب\(z)", isolatedLetters: false), "کتاب")
        XCTAssertEqual(TypedAnswer.submittedSpelling("من\(z) \(z)می\(z)خرم", isolatedLetters: false), "من می\(z)خرم")
    }

    func testKeepsWhitespaceRunsAsTyped() {
        XCTAssertEqual(TypedAnswer.submittedSpelling("a\(z)  \(z)b", isolatedLetters: false), "a  b")
    }

    func testEmptyAndZwnjOnly() {
        XCTAssertEqual(TypedAnswer.submittedSpelling("", isolatedLetters: true), "")
        XCTAssertEqual(TypedAnswer.submittedSpelling("\(z)\(z)", isolatedLetters: false), "")
    }
}
