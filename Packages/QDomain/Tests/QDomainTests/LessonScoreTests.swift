import XCTest
@testable import QDomain

final class LessonScoreTests: XCTestCase {
    func testPassThresholdIsSeventyFivePercent() {
        XCTAssertEqual(lessonPassThreshold, 0.75)
    }

    func testVerdictWeights() {
        XCTAssertEqual(verdictWeight(.correct), 1)
        XCTAssertEqual(verdictWeight(.acceptedWithCorrection), 0.5)
        XCTAssertEqual(verdictWeight(.incorrect), 0)
    }

    func testPendingVerdictWeighsNothing() {
        XCTAssertEqual(verdictWeight(.pending), 0)
    }

    private func a(_ ordinal: Int, _ attempt: Int, _ verdict: AnswerVerdict) -> LessonAttempt {
        LessonAttempt(exerciseKey: "e\(ordinal)", attempt: attempt, verdict: verdict)
    }

    func testIssueExampleScoresFourteenPointTwoFiveOfSixteen() {
        var answers: [LessonAttempt] = []
        for i in 0..<13 { answers.append(a(i, 1, .correct)) }
        for i in 13..<16 { answers.append(a(i, 1, .incorrect)) }
        answers.append(a(13, 2, .correct))
        answers.append(a(14, 2, .correct))
        answers.append(a(15, 2, .incorrect))
        answers.append(a(15, 3, .correct))
        XCTAssertEqual(lessonScore(answers), 14.25 / 16, accuracy: 1e-10)
    }

    func testCreditHalvesPerAttemptBeforeTheRightOne() {
        let cases: [(Int, AnswerVerdict, Double)] = [
            (1, .correct, 1), (2, .correct, 0.5), (3, .correct, 0.25), (4, .correct, 0.125),
            (1, .acceptedWithCorrection, 0.5), (2, .acceptedWithCorrection, 0.25)
        ]
        for (attempt, verdict, expected) in cases {
            var answers: [LessonAttempt] = []
            if attempt > 1 { for n in 1..<attempt { answers.append(a(0, n, .incorrect)) } }
            answers.append(a(0, attempt, verdict))
            XCTAssertEqual(lessonScore(answers), expected, accuracy: 1e-12)
        }
    }

    func testExerciseNeverAnsweredRightIsWorthNothing() {
        XCTAssertEqual(lessonScore([a(0, 1, .incorrect), a(0, 2, .incorrect), a(0, 3, .incorrect)]), 0)
    }

    func testAttemptsAfterTheRightOneChangeNothingInAnyOrder() {
        XCTAssertEqual(lessonScore([a(0, 3, .correct), a(0, 2, .correct), a(0, 1, .incorrect)]), 0.5)
    }

    func testMultiTagExerciseIsOneVote() {
        let answers = [a(0, 1, .correct), a(0, 1, .correct), a(0, 1, .correct), a(1, 1, .incorrect)]
        XCTAssertEqual(lessonScore(answers), 0.5)
    }

    func testAttemptBelowOneIsIgnored() {
        XCTAssertEqual(lessonScore([a(0, 0, .correct)]), 0)
        XCTAssertEqual(lessonScore([a(0, 0, .correct), a(0, 1, .incorrect), a(0, 2, .correct)]), 0.5)
    }

    func testPendingEarnsNothingAndNoAnswersScoreZero() {
        XCTAssertEqual(lessonScore([a(0, 1, .pending)]), 0)
        XCTAssertEqual(lessonScore([]), 0)
    }
}
