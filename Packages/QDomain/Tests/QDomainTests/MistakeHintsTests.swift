import XCTest
@testable import QDomain

final class MistakeHintsTests: XCTestCase {
    private func kinds(_ course: String?, _ accepted: [String], _ submitted: String) -> [MistakeKind?] {
        let marked = TypedAnswerMarks.markTypedAnswer(courseCode: course, acceptedAnswers: accepted, submitted: submitted, correct: false)
        return marked.map { mistakeKind(courseCode: course, word: $0) }
    }

    func testNamesALeftOutRaInAPersianAnswer() {
        XCTAssertEqual(kinds("fa", ["کتاب را خواندم"], "کتاب خواندم"), [nil, .missingRa, nil])
    }

    func testIgnoresReadingAidsAndArabicCodepointsOnTheMissingWord() {
        XCTAssertEqual(mistakeKind(courseCode: "fa", text: "رَا", isMissing: true), .missingRa)
    }

    func testNoHintForARaTheLearnerTyped() {
        XCTAssertEqual(kinds("fa", ["کتاب را خواندم"], "کتاب را خواند"), [nil, nil, nil])
    }

    func testNoHintForAnyOtherMissingWord() {
        let marked = TypedAnswerMarks.markTypedAnswer(courseCode: "fa", acceptedAnswers: ["من کتاب را خواندم"], submitted: "کتاب را خواندم", correct: false)
        XCTAssertEqual(marked[0], MarkedWord(text: "من", mark: .missing))
        XCTAssertEqual(marked.map { mistakeKind(courseCode: "fa", word: $0) }, [nil, nil, nil, nil])
    }

    func testNamesALeftOutRaWordBankTileAndNothingForAPlacedOne() {
        XCTAssertEqual(mistakeKind(courseCode: "fa", text: "را", isMissing: true), .missingRa)
        XCTAssertNil(mistakeKind(courseCode: "fa", text: "را", isMissing: false))
        XCTAssertNil(mistakeKind(courseCode: "fa", word: MarkedWord(text: "را", mark: .wrong)))
        XCTAssertNil(mistakeKind(courseCode: "fa", word: MarkedWord(text: "را", mark: .right)))
    }

    func testNoHintOutsideAPersianCourse() {
        XCTAssertNil(mistakeKind(courseCode: "en", text: "را", isMissing: true))
        XCTAssertNil(mistakeKind(courseCode: nil, text: "را", isMissing: true))
    }

    func testHintTextExplainsRa() {
        XCTAssertTrue(MistakeKind.missingRa.hint.hasPrefix("را marks a specific"))
    }
}
