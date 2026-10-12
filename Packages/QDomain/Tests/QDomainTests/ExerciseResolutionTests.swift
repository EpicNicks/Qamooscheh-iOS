import XCTest
import QModel
@testable import QDomain

final class ExerciseResolutionTests: XCTestCase {
    private func exercise(_ type: ExerciseType, tiles: [String]?) -> ExerciseArtifact {
        return ExerciseArtifact(type: type, scriptMode: .native, prompt: "p", tiles: tiles, answer: ["a"])
    }

    private func card(review: Int, lapse: Int) -> CardState {
        return CardState(lexemeTag: "t", stability: 1, difficulty: 5, reviewCount: review, lapseCount: lapse)
    }

    func testCompositeIsTypeInWithNonEmptyTiles() {
        XCTAssertTrue(isComposite(exercise(.typeIn, tiles: ["a", "b"])))
        XCTAssertFalse(isComposite(exercise(.typeIn, tiles: nil)))
        XCTAssertFalse(isComposite(exercise(.typeIn, tiles: [])))
        XCTAssertFalse(isComposite(exercise(.wordBank, tiles: ["a"])))
    }

    func testNonCompositeKeepsItsOwnType() {
        XCTAssertEqual(resolveExerciseType(exercise(.typeIn, tiles: nil), cardState: nil), .typeIn)
        XCTAssertEqual(resolveExerciseType(exercise(.wordBank, tiles: ["a"]), cardState: card(review: 9, lapse: 0)), .wordBank)
        XCTAssertEqual(resolveExerciseType(exercise(.speak, tiles: nil), cardState: nil), .speak)
    }

    func testCompositeIsWordBankForNewCard() {
        XCTAssertEqual(resolveExerciseType(exercise(.typeIn, tiles: ["a"]), cardState: nil), .wordBank)
    }

    func testCompositeIsWordBankForRecentlyLapsedCard() {
        XCTAssertEqual(resolveExerciseType(exercise(.typeIn, tiles: ["a"]), cardState: card(review: 2, lapse: 1)), .wordBank)
    }

    func testCompositeIsTypeInForEstablishedCard() {
        XCTAssertEqual(resolveExerciseType(exercise(.typeIn, tiles: ["a"]), cardState: card(review: 5, lapse: 1)), .typeIn)
        XCTAssertEqual(resolveExerciseType(exercise(.typeIn, tiles: ["a"]), cardState: card(review: 1, lapse: 0)), .typeIn)
    }
}
