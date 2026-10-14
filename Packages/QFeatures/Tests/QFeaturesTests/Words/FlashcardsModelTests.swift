import XCTest
import QModel
import QNetwork
@testable import QFeatures

private final class FakeSubmitter: FlashcardSubmitter, @unchecked Sendable {
    private let lock = NSLock()
    private var log: [SubmitFlashcardsRequest] = []
    var failures = 0
    var gate: GateBox?
    var cancelNext = false

    var requests: [SubmitFlashcardsRequest] {
        lock.lock()
        defer { lock.unlock() }
        return log
    }

    func submit(_ request: SubmitFlashcardsRequest) async throws -> SubmitFlashcardsResponse {
        lock.lock()
        log.append(request)
        let cancel = cancelNext
        cancelNext = false
        let fail = failures > 0
        if fail { failures -= 1 }
        lock.unlock()
        if let gate = gate { await gate.wait() }
        if cancel { throw CancellationError() }
        if fail { throw ApiError(status: 503, body: ApiErrorBody(error: "Try later")) }
        return SubmitFlashcardsResponse(alreadyProcessed: false, xp: 10)
    }
}

@MainActor
final class FlashcardsModelTests: XCTestCase {
    private func makeModel(_ submitter: FakeSubmitter, content: VocabContent = sampleContent) async -> FlashcardsModel {
        let source = FakeVocabSource()
        source.loadHandler = { .ready(content) }
        source.starredHandler = { StarredVocabResponse(tags: ["a", "b", "zzz"], limit: 100, refused: []) }
        let store = VocabularyStore(source: source)
        let model = FlashcardsModel(
            store: store, submitter: submitter, shuffle: { $0 }, newId: { "sub-1" },
            now: { Date(timeIntervalSince1970: 5) })
        await model.refresh()
        return model
    }

    func testWordsAreSavedTagsInTheCourseIndex() async {
        let model = await makeModel(FakeSubmitter())
        XCTAssertEqual(model.words.map { $0.tag }, ["a", "b"])
    }

    func testTypedRoundSubmitsOnceAtTheEnd() async {
        let submitter = FakeSubmitter()
        let model = await makeModel(submitter)
        model.start()
        await model.answer(correct: true)
        XCTAssertTrue(submitter.requests.isEmpty)
        await model.answer(correct: false)
        XCTAssertEqual(submitter.requests.count, 1)
        let request = submitter.requests[0]
        XCTAssertEqual(request.submissionId, "sub-1")
        XCTAssertEqual(request.courseCode, "fa")
        XCTAssertFalse(request.inRemix)
        XCTAssertEqual(request.cards, [
            SubmittedFlashcard(tag: "a", kind: .translation, correct: true),
            SubmittedFlashcard(tag: "b", kind: .translation, correct: false),
        ])
        XCTAssertEqual(model.xp, .saved(10))
        XCTAssertNil(model.current)
    }

    func testFlipRoundEarnsNothingStandalone() async {
        let submitter = FakeSubmitter()
        let model = await makeModel(submitter)
        model.setKind(.selfRated)
        model.start()
        await model.answer(correct: true)
        await model.answer(correct: true)
        XCTAssertTrue(submitter.requests.isEmpty)
        XCTAssertEqual(model.xp, .idle)
    }

    func testFailedSubmitSurfacesServerMessageAndRetryReusesSubmissionId() async {
        let submitter = FakeSubmitter()
        submitter.failures = 1
        let model = await makeModel(submitter)
        model.start()
        await model.answer(correct: true)
        await model.answer(correct: true)
        XCTAssertEqual(model.xp, .failed("Try later"))
        await model.retrySubmit()
        XCTAssertEqual(model.xp, .saved(10))
        XCTAssertEqual(submitter.requests.map { $0.submissionId }, ["sub-1", "sub-1"])
        XCTAssertEqual(submitter.requests[0].cards, submitter.requests[1].cards)
    }

    func testCancelledSubmitDoesNotStickOnSavingAndRetries() async {
        let submitter = FakeSubmitter()
        submitter.cancelNext = true
        let model = await makeModel(submitter)
        model.start()
        await model.answer(correct: true)
        await model.answer(correct: true)
        XCTAssertNotEqual(model.xp, .saving)
        XCTAssertEqual(model.xp, .failed("Saving was interrupted. Try again."))
        await model.retrySubmit()
        XCTAssertEqual(model.xp, .saved(10))
        XCTAssertEqual(submitter.requests.map { $0.submissionId }, ["sub-1", "sub-1"])
    }

    func testKindCannotChangeMidRound() async {
        let model = await makeModel(FakeSubmitter())
        model.start()
        model.setKind(.selfRated)
        XCTAssertEqual(model.kind, .translation)
    }

    func testStaleResultDoesNotOverwriteANewRoundAndStillSubmits() async {
        let submitter = FakeSubmitter()
        let gate = GateBox()
        submitter.gate = gate
        let model = await makeModel(submitter)
        model.start()
        await model.answer(correct: true)
        let finishing = Task { await model.answer(correct: true) }
        while submitter.requests.isEmpty { await Task.yield() }
        model.stop()
        model.start()
        gate.open()
        await finishing.value
        XCTAssertEqual(model.xp, .idle)
        XCTAssertEqual(model.results.count, 0)
        XCTAssertEqual(submitter.requests.count, 1)
    }

    func testRoundKeepsItsCourseWhenTheCourseChanges() async {
        let submitter = FakeSubmitter()
        let source = FakeVocabSource()
        source.loadHandler = { .ready(sampleContent) }
        source.starredHandler = { StarredVocabResponse(tags: ["a", "b"], limit: 100, refused: []) }
        let store = VocabularyStore(source: source)
        let model = FlashcardsModel(store: store, submitter: submitter, shuffle: { $0 }, newId: { "sub-2" })
        await model.refresh()
        model.start()
        source.loadHandler = { .ready(VocabContent(courseCode: "ja", units: sampleContent.units, lexemes: sampleContent.lexemes)) }
        await model.refresh()
        XCTAssertEqual(store.content?.courseCode, "ja")
        await model.answer(correct: true)
        await model.answer(correct: true)
        XCTAssertEqual(submitter.requests.first?.courseCode, "fa")
    }

    func testFailedRoundStaysSettlingUntilDiscarded() async {
        let submitter = FakeSubmitter()
        submitter.failures = 1
        let model = await makeModel(submitter)
        model.start()
        await model.answer(correct: true)
        await model.answer(correct: true)
        XCTAssertTrue(model.isSettlingXp)
        XCTAssertEqual(model.xp, .failed("Try later"))
        model.discardRound()
        XCTAssertFalse(model.isSettlingXp)
        XCTAssertNil(model.deck)
        XCTAssertEqual(model.xp, .idle)
    }

    func testSavedRoundIsNotSettling() async {
        let model = await makeModel(FakeSubmitter())
        model.start()
        await model.answer(correct: true)
        await model.answer(correct: true)
        XCTAssertFalse(model.isSettlingXp)
    }

    func testRetryKeepsTheTimeTheRoundEnded() async {
        let submitter = FakeSubmitter()
        submitter.failures = 1
        let source = FakeVocabSource()
        source.loadHandler = { .ready(sampleContent) }
        source.starredHandler = { StarredVocabResponse(tags: ["a", "b"], limit: 100, refused: []) }
        let clock = ClockBox()
        let model = FlashcardsModel(
            store: VocabularyStore(source: source), submitter: submitter, shuffle: { $0 },
            newId: { "sub-1" }, now: { clock.value })
        await model.refresh()
        model.start()
        clock.value = Date(timeIntervalSince1970: 100)
        await model.answer(correct: true)
        clock.value = Date(timeIntervalSince1970: 200)
        await model.answer(correct: true)
        clock.value = Date(timeIntervalSince1970: 900)
        await model.retrySubmit()
        XCTAssertEqual(submitter.requests.map { $0.occurredAt }, [Date(timeIntervalSince1970: 200), Date(timeIntervalSince1970: 200)])
    }
}

private final class ClockBox: @unchecked Sendable {
    var value = Date(timeIntervalSince1970: 0)
}
