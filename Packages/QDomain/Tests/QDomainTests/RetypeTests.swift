import XCTest
import QModel
@testable import QDomain

/// Answers like the real grader: any accepted answer is right, "من کتاو دارم" is a forgiven typo of the first, and nothing else is.
private final class RetypeFakeGrader: Grader {
    func gradeEnvelope(_ request: GraderRequest) -> GraderResponse {
        if request.acceptedAnswers.contains(request.submitted) {
            return GraderResponse(verdict: "Correct", matchedAnswer: request.submitted, correct: true, xp: 10)
        }
        if request.submitted == "من کتاو دارم" {
            return GraderResponse(verdict: "AcceptedWithCorrection", matchedAnswer: request.acceptedAnswers[0], correct: true, acceptedWithCorrection: true, reasons: ["EditDistanceTypo"], xp: 7)
        }
        return GraderResponse()
    }

    func xp(verdict: String, attempt: Int, usedHint: Bool, retype: Bool, retypeNumber: Int?) -> Int { return 0 }
}

final class RetypeTests: XCTestCase {
    private let grader = RetypeFakeGrader()
    private let native = GradedExercise(type: .typeIn, scriptMode: .native, answer: ["من کتاب دارم", "کتاب دارم"])
    private let english = GradedExercise(type: .typeIn, scriptMode: .native, answer: ["I have a book", "I've got a book"])

    func testOffersARetypeOnlyAfterAWrongTypedAnswer() {
        XCTAssertTrue(needsRetype(renderType: .typeIn, correct: false))
        XCTAssertFalse(needsRetype(renderType: .typeIn, correct: true))
    }

    func testNeverOffersOneForAnExerciseThatIsntTyped() {
        for type in [ExerciseType.wordBank, .match, .speak] {
            XCTAssertFalse(needsRetype(renderType: type, correct: false))
        }
    }

    func testCreditedRetypesCap() {
        XCTAssertEqual(maxCreditedRetypes, 2)
    }

    func testAcceptsAnyAcceptedAnswerNotJustTheFirst() {
        XCTAssertTrue(retypeMatches(grader, courseCode: "fa", exercise: native, retyped: "من کتاب دارم"))
        XCTAssertTrue(retypeMatches(grader, courseCode: "fa", exercise: native, retyped: "کتاب دارم"))
        XCTAssertTrue(retypeMatches(grader, courseCode: "en", exercise: english, retyped: "I've got a book"))
    }

    func testRejectsAWrongRetypeAndAnEmptyOne() {
        XCTAssertFalse(retypeMatches(grader, courseCode: "fa", exercise: native, retyped: "تو کتاب داری"))
        XCTAssertFalse(retypeMatches(grader, courseCode: "en", exercise: english, retyped: "I have a cat"))
        XCTAssertFalse(retypeMatches(grader, courseCode: "fa", exercise: native, retyped: "   "))
    }

    func testComparesExactlyAsTheExerciseDoesForgivenTyposIncluded() {
        let verdict = checkAnswer(grader, courseCode: "fa", exercise: native, submittedText: "من کتاو دارم").verdict
        XCTAssertEqual(verdict, .acceptedWithCorrection)
        XCTAssertTrue(retypeMatches(grader, courseCode: "fa", exercise: native, retyped: "من کتاو دارم"))
    }

    func testLeavesTheOriginalAnswersGradingUntouched() {
        let before = checkAnswer(grader, courseCode: "fa", exercise: native, submittedText: "تو کتاب داری")
        _ = retypeMatches(grader, courseCode: "fa", exercise: native, retyped: "من کتاب دارم")
        XCTAssertEqual(checkAnswer(grader, courseCode: "fa", exercise: native, submittedText: "تو کتاب داری"), before)
        XCTAssertEqual(before.verdict, .incorrect)
    }

    func testNoGraderIsNotAMatch() {
        XCTAssertFalse(retypeMatches(nil, courseCode: "fa", exercise: native, retyped: "من کتاب دارم"))
    }
}
