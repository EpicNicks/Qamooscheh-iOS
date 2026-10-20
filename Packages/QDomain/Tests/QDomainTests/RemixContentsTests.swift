import XCTest
import QModel
@testable import QDomain

final class RemixContentsTests: XCTestCase {
    private struct Built: Equatable {
        var id: Int
        var renderType: ExerciseType
    }

    private func exercises(_ types: [ExerciseType]) -> [Built] {
        return types.enumerated().map { Built(id: $0.offset, renderType: $0.element) }
    }

    private func filter(_ list: [Built], _ contents: RemixContents, max: Int? = nil) -> [Built] {
        return filterRemixExercises(list, contents: contents, max: max, renderType: { $0.renderType })
    }

    private let built: [Built] = [
        Built(id: 0, renderType: .wordBank), Built(id: 1, renderType: .typeIn), Built(id: 2, renderType: .match),
        Built(id: 3, renderType: .wordBank), Built(id: 4, renderType: .speak), Built(id: 5, renderType: .typeIn),
    ]

    func testKeepsEverythingForAllExercises() {
        XCTAssertEqual(filter(built, .all), built)
        XCTAssertEqual(filter(built, .flashcardsAndAll), built)
    }

    func testKeepsOnlyTheChosenRenderType() {
        XCTAssertEqual(filter(built, .typeIn).map { $0.id }, [1, 5])
        XCTAssertEqual(filter(built, .wordBank).map { $0.id }, [0, 3])
    }

    func testKeepsNoExercisesForFlashcardsOnly() {
        XCTAssertEqual(filter(built, .flashcards), [])
    }

    func testFiltersBeforeCappingSoMatchesPastTheCapStillFillIt() {
        let many = exercises([.wordBank, .wordBank, .wordBank, .typeIn, .typeIn, .typeIn])
        XCTAssertEqual(filter(many, .typeIn, max: 2).map { $0.id }, [3, 4])
        XCTAssertEqual(filter(many, .all, max: 2).map { $0.id }, [0, 1])
    }

    func testCanLeaveNothing() {
        XCTAssertEqual(filter(exercises([.wordBank]), .typeIn, max: 20), [])
    }

    func testOffersTheFlashcardChoicesOnlyWhenTheRemixHasFlashcards() {
        XCTAssertEqual(remixContentsOptions(hasFlashcards: false), [.all, .typeIn, .wordBank, .cloze])
        XCTAssertEqual(remixContentsOptions(hasFlashcards: true), [.all, .typeIn, .wordBank, .flashcards, .flashcardsAndAll, .cloze])
    }

    func testFallsBackWhenTheRememberedChoiceIsNotOffered() {
        let options = remixContentsOptions(hasFlashcards: false)
        XCTAssertEqual(initialRemixContents(remembered: .flashcards, options: options, fallback: .all), .all)
        XCTAssertEqual(initialRemixContents(remembered: .typeIn, options: options, fallback: .all), .typeIn)
    }

    func testSaysWhichChoicesIncludeFlashcardsAndWhichExercises() {
        XCTAssertTrue(includesFlashcards(.flashcards))
        XCTAssertTrue(includesFlashcards(.flashcardsAndAll))
        XCTAssertFalse(includesFlashcards(.all))
        XCTAssertFalse(includesExercise(.typeIn, renderType: .match))
        XCTAssertTrue(includesExercise(.all, renderType: .speak))
    }

    func testFillInTheBlankHoldsNoExercisesAndNoFlashcards() {
        XCTAssertTrue(isClozeContents(.cloze))
        XCTAssertFalse(isClozeContents(.all))
        XCTAssertFalse(includesFlashcards(.cloze))
        XCTAssertFalse(includesExercise(.cloze, renderType: .typeIn))
        XCTAssertEqual(filter(built, .cloze), [])
    }

    func testRawValuesAndLabelsMatchTheWeb() {
        XCTAssertEqual(RemixContents.allCases.map { $0.rawValue }, ["all", "type_in", "word_bank", "flashcards", "flashcards_and_all", "cloze"])
        XCTAssertEqual(
            RemixContents.allCases.map { $0.label },
            ["All exercises", "Typing only", "Word bank only", "Flashcards only", "Flashcards + all exercises", "Fill in the blank"]
        )
    }
}

final class SavedRemixSelectionTests: XCTestCase {
    private let types: [String: ExerciseType] = ["a": .typeIn, "b": .wordBank]

    private func pick(_ contents: RemixContents, _ exercises: [String] = ["a", "b", "unknown"]) -> SavedRemixSelection<Int, String> {
        return selectSavedRemix(cards: [1, 2], exercises: exercises, contents: contents, renderType: { types[$0] })
    }

    func testKeepsCardsOnlyWhereTheChoiceIncludesThem() {
        XCTAssertEqual(pick(.flashcards).cards, [1, 2])
        XCTAssertEqual(pick(.flashcardsAndAll).cards, [1, 2])
        XCTAssertEqual(pick(.typeIn).cards, [])
        XCTAssertEqual(pick(.cloze).cards, [])
    }

    func testFiltersExercisesByTypeAndKeepsUnknownOnesOnlyWhereEverythingStays() {
        XCTAssertEqual(pick(.typeIn).exercises, ["a"])
        XCTAssertEqual(pick(.wordBank).exercises, ["b"])
        XCTAssertEqual(pick(.all).exercises, ["a", "b", "unknown"])
        XCTAssertEqual(pick(.flashcardsAndAll).exercises, ["a", "b", "unknown"])
        XCTAssertTrue(pick(.flashcards).exercises.isEmpty)
        XCTAssertTrue(pick(.wordBank, ["a"]).isEmpty)
    }
}
