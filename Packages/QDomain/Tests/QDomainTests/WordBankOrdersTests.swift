import XCTest
import QModel
@testable import QDomain

// "I go to school tomorrow": the pronoun is optional and the time word can
// sit either side of it.
final class WordBankOrdersTests: XCTestCase {
    private let zw = "\u{200C}"

    private var exercise: ExerciseArtifact {
        let verb = "\u{0645}\u{06CC}\(zw)\u{0631}\u{0648}\u{0645}"
        return ExerciseArtifact(
            type: .wordBank,
            scriptMode: .native,
            prompt: "I go to school tomorrow",
            tiles: ["من", "فردا", "به", "مدرسه", verb, "کتاب"],
            answer: ["من", "فردا", "به", "مدرسه", verb],
            tags: [],
            alternativeAnswers: [
                ["فردا", "من", "به", "مدرسه", verb],
                ["فردا", "به", "مدرسه", verb],
            ]
        )
    }

    private var verb: String { "\u{0645}\u{06CC}\(zw)\u{0631}\u{0648}\u{0645}" }

    // gradeTiles

    func testGradeMarksExactlyOneSwappedPair() {
        XCTAssertEqual(WordBankOrders.gradeTiles(["b", "a", "c"], ["a", "b", "c"]), [.swapped, .swapped, .right])
    }

    func testGradeMarksOnlyTilesOutsideLcsWrong() {
        XCTAssertEqual(WordBankOrders.gradeTiles(["x", "a", "b", "c"], ["a", "b", "c"]), [.wrong, .right, .right, .right])
    }

    func testGradeEmptySubmission() {
        XCTAssertEqual(WordBankOrders.gradeTiles([], ["a"]), [])
    }

    // closestTileOrder

    func testClosestPrefersAuthoredAnswerOnTie() {
        let result = WordBankOrders.closestTileOrder(["a"], [["a", "b"], ["a", "c"]])
        XCTAssertEqual(result.order, ["a", "b"])
    }

    func testClosestPicksAlternativeOneSwapAway() {
        // Swapping "به" and "مدرسه" in the first alternative.
        let submitted = ["فردا", "من", "مدرسه", "به", verb]
        let ex = exercise
        let result = WordBankOrders.closestTileOrder(submitted, WordBankOrders.acceptedTileOrders(ex))
        XCTAssertEqual(result.order, ex.alternativeAnswers![0])
        XCTAssertEqual(result.marks, [.right, .right, .swapped, .swapped, .right])
    }

    func testClosestMeasuresPronounlessSubmissionAgainstPronounlessOrder() {
        let submitted = ["فردا", "به", "مدرسه", "کتاب", verb]
        let ex = exercise
        let result = WordBankOrders.closestTileOrder(submitted, WordBankOrders.acceptedTileOrders(ex))
        XCTAssertEqual(result.order, ex.alternativeAnswers![1])
        XCTAssertEqual(result.marks, [.right, .right, .right, .wrong, .right])
    }

    // revealedTileOrder

    func testRevealedOrderIsClosestToSubmission() {
        let ex = exercise
        XCTAssertEqual(
            WordBankOrders.revealedTileOrder(ex, submittedText: "فردا من مدرسه به \(verb)"),
            ex.alternativeAnswers![0]
        )
    }

    func testRevealedFallsBackToAuthoredAnswer() {
        var ex = exercise
        let text = "فردا من مدرسه به \(verb)"
        ex.alternativeAnswers = nil
        XCTAssertEqual(WordBankOrders.revealedTileOrder(ex, submittedText: text), ex.answer)
        let full = exercise
        XCTAssertEqual(WordBankOrders.revealedTileOrder(full, submittedText: "nonsense"), full.answer)
        XCTAssertEqual(WordBankOrders.revealedTileOrder(full, submittedText: nil), full.answer)
    }

    // missingBankTiles

    func testMissingOutlinesBankTilesClosestOrderStillNeeded() {
        // Submitted "من به مدرسه": فردا and the verb were left in the bank, کتاب is a decoy.
        let ex = exercise
        let submitted = ["من", "به", "مدرسه"]
        let closest = WordBankOrders.closestTileOrder(submitted, WordBankOrders.acceptedTileOrders(ex))
        let missing = WordBankOrders.missingBankTiles(
            tiles: ex.tiles!, bankIndices: [1, 4, 5], submitted: submitted, marks: closest.marks, order: closest.order
        )
        XCTAssertEqual(missing, Set([1, 4]))
    }

    func testMissingOutlinesNothingOnceEveryNeededTileUsed() {
        let ex = exercise
        let marks = WordBankOrders.gradeTiles(ex.answer, ex.answer)
        let missing = WordBankOrders.missingBankTiles(
            tiles: ex.tiles!, bankIndices: [5], submitted: ex.answer, marks: marks, order: ex.answer
        )
        XCTAssertTrue(missing.isEmpty)
    }

    func testMissingStillOutlinesTileWhoseOnlySubmittedCopyWasWrong() {
        let repeated = ["a", "b", "a"]
        let submitted = ["b", "a"]
        let marks = WordBankOrders.gradeTiles(submitted, repeated)
        // One "a" of the two the order needs is placed; the other is in the bank.
        let missing = WordBankOrders.missingBankTiles(
            tiles: ["a", "b", "a"], bankIndices: [2], submitted: submitted, marks: marks, order: repeated
        )
        XCTAssertEqual(missing, Set([2]))
    }

    // tilesForSubmission and alignTiles (no web test)

    func testTilesForSubmissionRecoversIndices() {
        XCTAssertEqual(WordBankOrders.tilesForSubmission(["a", "b", "c"], "c a"), [2, 0])
    }

    func testTilesForSubmissionHandlesTileContainingSpace() {
        XCTAssertEqual(WordBankOrders.tilesForSubmission(["good morning", "good", "morning"], "good morning"), [0])
    }

    func testTilesForSubmissionBacktracks() {
        // "a" greedily matches first but "a b" is the only way to consume the rest.
        XCTAssertEqual(WordBankOrders.tilesForSubmission(["a", "a b", "c"], "a b c"), [1, 2])
    }

    func testTilesForSubmissionReusesNoTile() {
        XCTAssertEqual(WordBankOrders.tilesForSubmission(["a"], "a a"), [])
    }

    func testTilesForSubmissionNoMatchIsEmpty() {
        XCTAssertEqual(WordBankOrders.tilesForSubmission(["a", "b"], "nonsense"), [])
    }

    func testTilesForSubmissionUsesExactScalarMatch() {
        // U+00E9 and e + U+0301 are canonically equal in Swift but not in JS.
        XCTAssertEqual(WordBankOrders.tilesForSubmission(["\u{00E9}"], "e\u{0301}"), [])
    }

    func testAlignTilesWalksInReadingOrder() {
        XCTAssertEqual(
            WordBankOrders.alignTiles(["x", "a", "c"], ["a", "b", "c"]),
            [.extra(submitted: 0), .match(submitted: 1, answer: 0), .missing(answer: 1), .match(submitted: 2, answer: 2)]
        )
    }

    func testAlignTilesTrailingLeftovers() {
        XCTAssertEqual(
            WordBankOrders.alignTiles(["a", "x"], ["a", "b"]),
            [.match(submitted: 0, answer: 0), .extra(submitted: 1), .missing(answer: 1)]
        )
    }

    func testAcceptedTileOrdersAuthoredFirst() {
        let ex = exercise
        let orders = WordBankOrders.acceptedTileOrders(ex)
        XCTAssertEqual(orders.count, 3)
        XCTAssertEqual(orders[0], ex.answer)
    }
}
