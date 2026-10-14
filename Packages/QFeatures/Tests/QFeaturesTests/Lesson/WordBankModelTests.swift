import XCTest
import CoreGraphics
import QModel
import QDomain
@testable import QFeatures

final class WordBankModelTests: XCTestCase {
    private let exercise = ExerciseArtifact(
        type: .wordBank, scriptMode: .native, prompt: "p",
        tiles: ["a", "b", "c", "d"], answer: ["a", "b", "c"]
    )

    func testTapMovesTileToAnswerAndBack() {
        var state = WordBankState(tileCount: 4, shuffled: [3, 1, 0, 2])
        XCTAssertTrue(state.tap(1))
        XCTAssertEqual(state.chosen, [1])
        XCTAssertEqual(state.bankOrder, [3, 0, 2])
        XCTAssertFalse(state.tap(1))
        XCTAssertEqual(state.chosen, [])
        XCTAssertEqual(state.bankOrder, [3, 1, 0, 2])
    }

    func testReinsertGoesBackToShufflePlace() {
        XCTAssertEqual(WordBankState.reinsert([3, 2], tile: 0, shuffled: [3, 1, 0, 2]), [3, 0, 2])
        XCTAssertEqual(WordBankState.reinsert([], tile: 0, shuffled: [3, 1, 0, 2]), [0])
    }

    func testAnswerJoinsTilesOrNilWhenEmpty() {
        var state = WordBankState(tileCount: 4, shuffled: [0, 1, 2, 3])
        XCTAssertNil(state.answer(tiles: ["a", "b", "c", "d"]))
        state.tap(2)
        state.tap(0)
        XCTAssertEqual(state.answer(tiles: ["a", "b", "c", "d"]), "c a")
    }

    func testReviewCorrectMarksAllRight() {
        let r = WordBankReview.make(exercise: exercise, shuffled: [3, 1, 0, 2], reviewed: ReviewedAnswer(text: "a b c", correct: true))
        XCTAssertEqual(r.placed, [0, 1, 2])
        XCTAssertEqual(r.bank, [3])
        XCTAssertEqual(r.marks, [.right, .right, .right])
        XCTAssertTrue(r.missing.isEmpty)
    }

    func testReviewWrongMarksAndMissing() {
        let r = WordBankReview.make(exercise: exercise, shuffled: [3, 1, 0, 2], reviewed: ReviewedAnswer(text: "a d", correct: false))
        XCTAssertEqual(r.placed, [0, 3])
        XCTAssertEqual(r.marks, [.right, .wrong])
        XCTAssertEqual(r.missing, [1, 2])
        XCTAssertEqual(r.bank, [1, 2])
    }

    func testTileLook() {
        XCTAssertEqual(TileLook.of(mark: .swapped, missing: true), .swapped)
        XCTAssertEqual(TileLook.of(mark: nil, missing: true), .missing)
        XCTAssertEqual(TileLook.of(mark: nil, missing: false), .plain)
    }

    func testRtlNeedsRtlCourseAndNativeTile() {
        XCTAssertTrue(wordBankIsRtl(courseCode: "fa", tiles: ["x", "کتاب"]))
        XCTAssertFalse(wordBankIsRtl(courseCode: "fa", tiles: ["book"]))
        XCTAssertFalse(wordBankIsRtl(courseCode: "ja", tiles: ["私"]))
    }

    func testFlowWrapsAndMirrorsInRtl() {
        let sizes = [CGSize(width: 40, height: 10), CGSize(width: 40, height: 10), CGSize(width: 40, height: 10)]
        let ltr = TileFlowGeometry.frames(sizes: sizes, width: 100, rtl: false, centered: false, spacing: 8)
        XCTAssertEqual(ltr[0].minX, 0)
        XCTAssertEqual(ltr[1].minX, 48)
        XCTAssertEqual(ltr[2].minY, 18)
        let rtl = TileFlowGeometry.frames(sizes: sizes, width: 100, rtl: true, centered: false, spacing: 8)
        XCTAssertEqual(rtl[0].minX, 60)
        XCTAssertEqual(rtl[1].minX, 12)
        XCTAssertEqual(TileFlowGeometry.height(of: ltr), 28)
    }

    func testFlowCentersLine() {
        let f = TileFlowGeometry.frames(sizes: [CGSize(width: 40, height: 10)], width: 100, rtl: false, centered: true, spacing: 8)
        XCTAssertEqual(f[0].minX, 30)
    }
}
