import XCTest
import QModel
@testable import QDomain

final class RaceScoringTests: XCTestCase {
    private func result(_ tag: String, correct: Bool = true, attempt: Int = 1) -> ClozeResult {
        return ClozeResult(tag: tag, correct: correct, attempt: attempt, elapsedMs: 1000)
    }

    func testAStrikeIsACardNotRightOnTheFirstAttempt() {
        XCTAssertFalse(RaceScoring.isStrike(result("a")))
        XCTAssertTrue(RaceScoring.isStrike(result("a", attempt: 2)))
        XCTAssertTrue(RaceScoring.isStrike(result("a", correct: false, attempt: 1)))
        XCTAssertEqual(RaceScoring.strikes([result("a"), result("b", attempt: 3), result("c", correct: false, attempt: 2)]), 2)
    }

    func testPerfectDeliveryEndsAtTheThirdStrikeAndEndlessPracticeNever() {
        let two = [result("a", attempt: 2), result("b", attempt: 2)]
        let three = two + [result("c", correct: false, attempt: 1)]
        XCTAssertFalse(RaceScoring.ended(.perfectDelivery, two))
        XCTAssertTrue(RaceScoring.ended(.perfectDelivery, three))
        XCTAssertFalse(RaceScoring.ended(.endlessPractice, three))
    }

    func testScoreSumsTheWeightsOfSolvedCardsOnAnyAttempt() {
        let weights = ["a": 1.5, "b": 1.25, "c": 2.0]
        let results = [result("a"), result("b", attempt: 3), result("c", correct: false, attempt: 4), result("unweighted")]
        XCTAssertEqual(RaceScoring.score(results, weights: weights), 2.75, accuracy: 0.0001)
        XCTAssertEqual(RaceScoring.solved(results), 3)
    }

    func testOnlyWeightedWordsAreDealt() {
        let dealt = RaceScoring.dealable(["a", "b", "c"], tagOf: { $0 }, weights: ["c": 1, "a": 1.2])
        XCTAssertEqual(dealt, ["a", "c"])
    }

    func testClockAndScoreText() {
        XCTAssertEqual(RaceScoring.clock(ms: 0), "0:00")
        XCTAssertEqual(RaceScoring.clock(ms: 65_400), "1:05")
        XCTAssertEqual(RaceScoring.clock(ms: 65_400, tenths: true), "1:05.4")
        XCTAssertEqual(RaceScoring.clock(ms: -5), "0:00")
        XCTAssertEqual(RaceScoring.scoreText(3.449), "3.4")
        XCTAssertEqual(RaceScoring.scoreText(12), "12.0")
    }

    func testHeldAndEndReasonCopy() {
        XCTAssertTrue(RaceScoring.heldMessage("answer_too_fast").contains("faster than a person"))
        XCTAssertTrue(RaceScoring.heldMessage("missing_timing").contains("faster than a person"))
        XCTAssertTrue(RaceScoring.heldMessage("claimed_time_exceeds_run").contains("timing"))
        XCTAssertTrue(RaceScoring.heldMessage("answers_after_end").contains("timing"))
        XCTAssertTrue(RaceScoring.heldMessage(nil).contains("didn't pass a check"))
        XCTAssertEqual(RaceScoring.endReasonText("third_strike"), "Ended at the third strike.")
        XCTAssertEqual(RaceScoring.endReasonText("deck_done"), "You cleared the whole deck.")
        XCTAssertEqual(RaceScoring.endReasonText("stopped"), "You stopped the run.")
    }
}
