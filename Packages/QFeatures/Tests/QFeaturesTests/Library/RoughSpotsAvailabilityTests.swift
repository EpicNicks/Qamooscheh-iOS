import XCTest
import QModel
@testable import QFeatures

private struct FakeRoughSpots: RoughSpotsSource {
    var response: StarredPracticeResponse?
    var error: Error?

    func roughSpots(count: Int) async throws -> StarredPracticeResponse {
        if let error { throw error }
        return response ?? StarredPracticeResponse(courseVersion: 1, words: [])
    }
}

@MainActor
final class RoughSpotsAvailabilityTests: XCTestCase {
    private func word(_ tag: String, exercises: Int) -> StarredPracticeWord {
        StarredPracticeWord(tag: tag, exercises: (0..<exercises).map { StarredPracticeExercise(unitKey: "u", skillKey: "s", ordinal: $0, form: nil) })
    }

    func testWordsWithExercisesMakeItAvailable() async {
        let model = RoughSpotsAvailability(source: FakeRoughSpots(response: StarredPracticeResponse(courseVersion: 1, words: [word("a", exercises: 2), word("b", exercises: 0)])))
        XCTAssertFalse(model.available)
        await model.refresh()
        XCTAssertTrue(model.available)
        XCTAssertEqual(model.wordCount, 1)
    }

    func testNoWordsOrOnlyFlashcardWordsIsNotAvailable() async {
        let empty = RoughSpotsAvailability(source: FakeRoughSpots())
        await empty.refresh()
        XCTAssertFalse(empty.available)
        let cardsOnly = RoughSpotsAvailability(source: FakeRoughSpots(response: StarredPracticeResponse(courseVersion: 1, words: [word("a", exercises: 0)])))
        await cardsOnly.refresh()
        XCTAssertFalse(cardsOnly.available)
    }

    func testAFailedLoadDisablesItAndNoSourceIsNone() async {
        let model = RoughSpotsAvailability(source: FakeRoughSpots(response: StarredPracticeResponse(courseVersion: 1, words: [word("a", exercises: 1)])))
        await model.refresh()
        XCTAssertTrue(model.available)
        let failing = RoughSpotsAvailability(source: FakeRoughSpots(error: URLError(.notConnectedToInternet)))
        await failing.refresh()
        XCTAssertFalse(failing.available)
        let none = RoughSpotsAvailability(source: nil)
        await none.refresh()
        XCTAssertFalse(none.available)
    }
}
