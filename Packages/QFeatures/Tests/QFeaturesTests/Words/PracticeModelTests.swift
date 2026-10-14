import XCTest
import QModel
import QDomain
import QNetwork
@testable import QFeatures

private final class FakePracticeSource: SavedPracticeSource, @unchecked Sendable {
    var handler: @Sendable (Int) async throws -> StarredPracticeResponse = { _ in StarredPracticeResponse(courseVersion: 1, words: []) }
    func practice(count: Int) async throws -> StarredPracticeResponse { try await handler(count) }
}

private final class RecordingSubmitter: FlashcardSubmitter, @unchecked Sendable {
    private let lock = NSLock()
    private var log: [SubmitFlashcardsRequest] = []
    var fail = false
    var requests: [SubmitFlashcardsRequest] {
        lock.lock()
        defer { lock.unlock() }
        return log
    }

    func submit(_ request: SubmitFlashcardsRequest) async throws -> SubmitFlashcardsResponse {
        lock.lock()
        log.append(request)
        lock.unlock()
        if fail { throw ApiError(status: 503, body: ApiErrorBody(error: "Try later")) }
        return SubmitFlashcardsResponse(alreadyProcessed: false, xp: 15)
    }
}

private struct FixedGenerator: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}

private func ref(_ ordinal: Int) -> StarredPracticeExercise {
    StarredPracticeExercise(unitKey: "u1", skillKey: "s1", ordinal: ordinal)
}

@MainActor
final class SavedPracticeModelTests: XCTestCase {
    private func makeModel(_ source: FakePracticeSource, _ submitter: RecordingSubmitter?) -> SavedPracticeModel {
        let vocab = FakeVocabSource()
        vocab.loadHandler = { .ready(sampleContent) }
        let store = VocabularyStore(source: vocab)
        return SavedPracticeModel(store: store, source: source, submitter: submitter, newId: { "sub-1" })
    }

    func testBuildsCardsAndDistinctExerciseRefsInOrder() async {
        let source = FakePracticeSource()
        source.handler = { _ in
            StarredPracticeResponse(courseVersion: 4, words: [
                StarredPracticeWord(tag: "a", exercises: [ref(0), ref(1)]),
                StarredPracticeWord(tag: "gone", exercises: [ref(1)]),
                StarredPracticeWord(tag: "b", exercises: [ref(1), ref(2)]),
            ])
        }
        let model = makeModel(source, RecordingSubmitter())
        await model.load()
        guard case .cards(let code, let cards, let results) = model.state else { return XCTFail("\(model.state)") }
        XCTAssertEqual(code, "fa")
        XCTAssertEqual(cards.map { $0.tag }, ["a", "b"])
        XCTAssertTrue(results.isEmpty)
        await model.answer(knew: true)
        await model.answer(knew: false)
        XCTAssertEqual(model.state, .cardsDone(
            known: 1, total: 2, xp: 15,
            exercises: SavedPracticeExercises(courseVersion: 4, exercises: "u1/s1/0,u1/s1/1,u1/s1/2", count: 3)))
    }

    func testSubmitsOnceAsAnInRemixSelfRatedRound() async {
        let source = FakePracticeSource()
        source.handler = { _ in StarredPracticeResponse(courseVersion: 1, words: [StarredPracticeWord(tag: "a", exercises: []), StarredPracticeWord(tag: "b", exercises: [])]) }
        let submitter = RecordingSubmitter()
        let model = makeModel(source, submitter)
        await model.load()
        await model.answer(knew: true)
        XCTAssertTrue(submitter.requests.isEmpty)
        await model.answer(knew: false)
        XCTAssertEqual(submitter.requests.count, 1)
        let request = submitter.requests[0]
        XCTAssertTrue(request.inRemix)
        XCTAssertEqual(request.submissionId, "sub-1")
        XCTAssertEqual(request.courseCode, "fa")
        XCTAssertEqual(request.cards, [
            SubmittedFlashcard(tag: "a", kind: .selfRated, correct: true),
            SubmittedFlashcard(tag: "b", kind: .selfRated, correct: false),
        ])
        XCTAssertEqual(model.state, .cardsDone(known: 1, total: 2, xp: 15, exercises: nil))
    }

    func testAFailedSubmitStillFinishesWithNoXp() async {
        let source = FakePracticeSource()
        source.handler = { _ in StarredPracticeResponse(courseVersion: 1, words: [StarredPracticeWord(tag: "a", exercises: [])]) }
        let submitter = RecordingSubmitter()
        submitter.fail = true
        let model = makeModel(source, submitter)
        await model.load()
        await model.answer(knew: true)
        XCTAssertEqual(model.state, .cardsDone(known: 1, total: 1, xp: nil, exercises: nil))
    }

    func testNoWordsIsEmptyAndExercisesOnlySkipsTheCards() async {
        let source = FakePracticeSource()
        let model = makeModel(source, nil)
        await model.load()
        XCTAssertEqual(model.state, .empty)

        source.handler = { _ in StarredPracticeResponse(courseVersion: 2, words: [StarredPracticeWord(tag: "gone", exercises: [ref(0)])]) }
        await model.load()
        XCTAssertEqual(model.state, .cardsDone(
            known: 0, total: 0, xp: 0, exercises: SavedPracticeExercises(courseVersion: 2, exercises: "u1/s1/0", count: 1)))
    }

    func testALoadFailureIsReportedAndRetryable() async {
        let source = FakePracticeSource()
        source.handler = { _ in throw ApiError(status: 503, body: ApiErrorBody(error: "Try later")) }
        let model = makeModel(source, nil)
        await model.load()
        guard case .failed = model.state else { return XCTFail("\(model.state)") }
        source.handler = { _ in StarredPracticeResponse(courseVersion: 1, words: []) }
        await model.load()
        XCTAssertEqual(model.state, .empty)
    }

    func testSummaryText() {
        XCTAssertEqual(savedPracticeSummary(known: 1, total: 1, xp: nil), "You knew 1 of 1 flashcard.")
        XCTAssertEqual(savedPracticeSummary(known: 3, total: 5, xp: 15), "You knew 3 of 5 flashcards (+15 XP).")
        XCTAssertEqual(savedPracticeNext(count: 1), "Next: 1 exercise from lessons that use these words.")
    }
}

@MainActor
final class LettersPracticeModelTests: XCTestCase {
    func testAnswerShowsFeedbackThenContinueAdvances() {
        let model = LettersPracticeModel(random: FixedGenerator(state: 7))
        let first = model.state.session.current!
        XCTAssertNil(model.state.review)
        model.choose(first.answerIndex)
        XCTAssertEqual(model.state.review?.correct, true)
        XCTAssertEqual(model.state.question, first)
        // Ignored while feedback is up.
        model.choose((first.answerIndex + 1) % letterOptionCount)
        XCTAssertEqual(model.state.review?.correct, true)
        model.continueOn()
        XCTAssertNil(model.state.review)
        XCTAssertEqual(model.state.session.completedCount, 1)
    }

    func testPlayingThroughFinishesAndAgainStartsFresh() {
        let model = LettersPracticeModel(random: FixedGenerator(state: 11))
        while !model.state.finished {
            model.choose(model.state.question!.answerIndex)
            model.continueOn()
        }
        XCTAssertEqual(model.state.session.firstTryCorrect, lettersSessionSize)
        model.again()
        XCTAssertFalse(model.state.finished)
        XCTAssertEqual(model.state.session.completedCount, 0)
    }
}
