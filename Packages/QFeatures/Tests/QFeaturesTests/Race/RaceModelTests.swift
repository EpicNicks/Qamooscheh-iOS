import XCTest
import QModel
import QDomain
import QNetwork
@testable import QFeatures

private let man = "\u{0645}\u{0646}<pron>"
private let chai = "\u{0686}\u{0627}\u{06CC}<n>"
private let khaneh = "\u{062E}\u{0627}\u{0646}\u{0647}<n>"
private let sentence = "\u{0645}\u{0646} \u{0686}\u{0627}\u{06CC}"
private let houseSentence = "\u{0645}\u{0646} \u{062E}\u{0627}\u{0646}\u{0647}"

private let content = VocabContent(
    courseCode: "fa",
    units: [UnitVocab(unitKey: "u1", title: "Greetings", lessons: [
        LessonVocab(unitKey: "u1", skillKey: "s1", title: "Tea", tags: [man, chai, khaneh]),
    ])],
    lexemes: [
        man: LexemeIndexEntry(gloss: "I / me", romanizationIsAuthored: false),
        chai: LexemeIndexEntry(gloss: "tea", romanizationIsAuthored: false),
        khaneh: LexemeIndexEntry(gloss: "home", romanizationIsAuthored: false),
    ])

private func ref(_ ordinal: Int) -> StarredPracticeExercise {
    StarredPracticeExercise(unitKey: "u1", skillKey: "s1", ordinal: ordinal)
}

private final class PracticeFake: SavedPracticeSource, @unchecked Sendable {
    var handler: @Sendable (Int) async throws -> StarredPracticeResponse = { _ in StarredPracticeResponse(courseVersion: 1, words: []) }
    func practice(count: Int) async throws -> StarredPracticeResponse { try await handler(count) }
}

private final class SentencesFake: ClozeSentenceSource, @unchecked Sendable {
    var handler: @Sendable ([StarredPracticeExercise], Int) async throws -> [String: ExerciseArtifact] = { _, _ in [:] }
    func exercises(_ refs: [StarredPracticeExercise], courseVersion: Int) async throws -> [String: ExerciseArtifact] {
        try await handler(refs, courseVersion)
    }
}

private final class RaceFake: RaceService, @unchecked Sendable {
    private let lock = NSLock()
    private var started: [(course: String, mode: RaceMode, hardcore: Bool, tags: [String])] = []
    private var finished: [(runId: String, answers: [RaceAnswer], deckDone: Bool)] = []
    var weights: [String: Double] = [chai: 1.5, khaneh: 1.8]
    var startFailure: Error?
    var finishFailures = 0
    var response = FinishRaceResponse(score: 3.3, timeMs: 12_000, solved: 2, strikes: 0, endReason: "deck_done", xp: 8, rank: 4)
    var board = RaceBoardResponse(entries: [])
    var boardFailure: Error?
    private var asked: [(RaceScope, Bool)] = []

    var starts: [(course: String, mode: RaceMode, hardcore: Bool, tags: [String])] {
        lock.lock()
        defer { lock.unlock() }
        return started
    }

    var finishes: [(runId: String, answers: [RaceAnswer], deckDone: Bool)] {
        lock.lock()
        defer { lock.unlock() }
        return finished
    }

    var boardsAsked: [(RaceScope, Bool)] {
        lock.lock()
        defer { lock.unlock() }
        return asked
    }

    func start(courseCode: String, mode: RaceMode, hardcore: Bool, tags: [String]) async throws -> StartRaceResponse {
        lock.lock()
        started.append((courseCode, mode, hardcore, tags))
        let failure = startFailure
        lock.unlock()
        if let failure = failure { throw failure }
        return StartRaceResponse(runId: "run-1", serverStartedAt: "2026-03-01T12:30:45.123+00:00", weights: weights)
    }

    func finish(runId: String, answers: [RaceAnswer], deckDone: Bool) async throws -> FinishRaceResponse {
        lock.lock()
        finished.append((runId, answers, deckDone))
        let fail = finishFailures > 0
        if fail { finishFailures -= 1 }
        lock.unlock()
        if fail { throw ApiError(status: 503, body: ApiErrorBody(error: "Try later")) }
        return response
    }

    func board(courseCode: String, scope: RaceScope, hardcore: Bool) async throws -> RaceBoardResponse {
        lock.lock()
        asked.append((scope, hardcore))
        let failure = boardFailure
        lock.unlock()
        if let failure = failure { throw failure }
        return board
    }
}

@MainActor
final class RaceModelTests: XCTestCase {
    private func make(_ race: RaceFake, words: [String] = [chai, khaneh], uptime: Box = Box()) -> RaceModel {
        let source = FakeVocabSource()
        source.loadHandler = { .ready(content) }
        let practice = PracticeFake()
        practice.handler = { _ in
            StarredPracticeResponse(courseVersion: 4, words: words.map { StarredPracticeWord(tag: $0, exercises: [ref(words.firstIndex(of: $0) ?? 0)]) })
        }
        let sentences = SentencesFake()
        sentences.handler = { _, _ in
            [
                "u1/s1/0": ExerciseArtifact(type: .typeIn, scriptMode: .native, prompt: "I like tea", answer: [sentence], tags: [man, chai]),
                "u1/s1/1": ExerciseArtifact(type: .typeIn, scriptMode: .native, prompt: "I like home", answer: [houseSentence], tags: [man, khaneh]),
                "u1/s1/2": ExerciseArtifact(type: .typeIn, scriptMode: .native, prompt: "I like tea too", answer: [sentence], tags: [man, chai]),
            ]
        }
        return RaceModel(
            store: VocabularyStore(source: source), race: race,
            services: ClozeServices(practice: practice, sentences: sentences), pick: { _ in 0 }, clock: { uptime.value })
    }

    final class Box: @unchecked Sendable {
        var value: TimeInterval = 100
    }

    private func result(_ tag: String, correct: Bool = true, attempt: Int = 1) -> ClozeResult {
        return ClozeResult(tag: tag, correct: correct, attempt: attempt, elapsedMs: 2_000)
    }

    private func run(_ model: RaceModel) -> RaceRun? {
        if case .run(let run) = model.stage { return run }
        return nil
    }

    func testStartingDealsOnlyTheWordsTheServerWeighted() async {
        let race = RaceFake()
        race.weights = [khaneh: 1.8]
        let model = make(race)
        model.selectMode(.endlessPractice)
        model.setHardcore(true)
        await model.start()
        guard let run = run(model) else { return XCTFail("\(model.stage)") }
        XCTAssertEqual(run.deck.map { $0.tag }, [khaneh])
        XCTAssertEqual(run.runId, "run-1")
        XCTAssertEqual(run.mode, .endlessPractice)
        XCTAssertTrue(run.hardcore)
        XCTAssertEqual(race.starts.count, 1)
        XCTAssertEqual(race.starts[0].course, "fa")
        XCTAssertEqual(race.starts[0].tags, [chai, khaneh])
        XCTAssertEqual(race.starts[0].mode, .endlessPractice)
        XCTAssertTrue(race.starts[0].hardcore)
    }

    func testNothingWeightedOrNothingToCutIsTheLobbyWithAMessage() async {
        let race = RaceFake()
        race.weights = [:]
        let model = make(race)
        await model.start()
        XCTAssertEqual(model.stage, .lobby(mode: .perfectDelivery, hardcore: false, message: RaceModel.nothingToRace))

        let idle = RaceFake()
        let none = make(idle, words: [])
        await none.start()
        XCTAssertEqual(none.stage, .lobby(mode: .perfectDelivery, hardcore: false, message: RaceModel.nothingToRace))
        XCTAssertTrue(idle.starts.isEmpty)
    }

    func testAFailedStartReturnsToTheLobbyWithTheServersMessage() async {
        let race = RaceFake()
        race.startFailure = ApiError(status: 503, body: ApiErrorBody(error: "Try later"))
        let model = make(race)
        await model.start()
        guard case .lobby(_, _, let message) = model.stage else { return XCTFail("\(model.stage)") }
        XCTAssertNotNil(message)
    }

    func testPerfectDeliveryEndsAtTheThirdStrikeAndSendsEveryAnswer() async {
        let race = RaceFake()
        race.weights = [chai: 1.5, khaneh: 1.8, man: 1.2]
        let model = make(race, words: [chai, khaneh, man])
        await model.start()
        XCTAssertEqual(run(model)?.deck.map { $0.tag }, [chai, khaneh, man])
        await model.finished(result(chai, attempt: 2))
        XCTAssertEqual(run(model)?.strikes, 1)
        XCTAssertTrue(race.finishes.isEmpty)
        await model.finished(result(khaneh, correct: false, attempt: 2))
        XCTAssertTrue(race.finishes.isEmpty)
        await model.finished(result(man, attempt: 3))
        XCTAssertEqual(race.finishes.count, 1)
        XCTAssertEqual(race.finishes[0].runId, "run-1")
        XCTAssertEqual(race.finishes[0].answers.map { $0.tag }, [chai, khaneh, man])
        XCTAssertEqual(race.finishes[0].answers[1].correct, false)
        XCTAssertEqual(race.finishes[0].answers[2].attempt, 3)
        XCTAssertEqual(race.finishes[0].answers[0].elapsedMs, 2_000)
        guard case .done(let mode, _, let response) = model.stage else { return XCTFail("\(model.stage)") }
        XCTAssertEqual(mode, .perfectDelivery)
        XCTAssertEqual(response.rank, 4)
    }

    func testEndingBecauseTheDeckRanOutSaysSo() async {
        let race = RaceFake()
        let model = make(race)
        await model.start()
        await model.finished(result(chai))
        XCTAssertTrue(race.finishes.isEmpty)
        XCTAssertEqual(run(model)?.score ?? 0, 1.5, accuracy: 0.0001)
        await model.finished(result(khaneh))
        XCTAssertEqual(race.finishes.count, 1)
        XCTAssertTrue(race.finishes[0].deckDone)
    }

    func testEndlessPracticeOnlyEndsWhenTheLearnerStops() async {
        let race = RaceFake()
        race.weights = [chai: 1.5, khaneh: 1.8, man: 1.2]
        let model = make(race, words: [chai, khaneh, man])
        model.selectMode(.endlessPractice)
        await model.start()
        XCTAssertFalse(model.leavingBanksTheRun)
        await model.stop()
        XCTAssertTrue(race.finishes.isEmpty)
        await model.finished(result(chai, correct: false, attempt: 4))
        await model.finished(result(khaneh, correct: false, attempt: 4))
        XCTAssertTrue(race.finishes.isEmpty)
        XCTAssertTrue(model.leavingBanksTheRun)
        await model.stop()
        XCTAssertEqual(race.finishes.count, 1)
        XCTAssertEqual(race.finishes[0].answers.count, 2)
        XCTAssertFalse(race.finishes[0].deckDone)
    }

    func testAFailedFinishKeepsTheAnswersAndIsRetriedWithTheSameRun() async {
        let race = RaceFake()
        race.finishFailures = 1
        let model = make(race)
        await model.start()
        await model.finished(result(chai))
        await model.finished(result(khaneh))
        guard let failed = run(model) else { return XCTFail("\(model.stage)") }
        XCTAssertTrue(failed.finishing)
        XCTAssertNotNil(failed.sendFailed)
        XCTAssertEqual(failed.results.count, 2)
        XCTAssertNil(failed.current)
        await model.retrySend()
        XCTAssertEqual(race.finishes.count, 2)
        XCTAssertEqual(race.finishes[1].runId, race.finishes[0].runId)
        XCTAssertEqual(race.finishes[1].answers, race.finishes[0].answers)
        guard case .done = model.stage else { return XCTFail("\(model.stage)") }
    }

    func testRaceAgainReturnsToTheLobbyWithTheSameChoices() async {
        let race = RaceFake()
        let model = make(race)
        model.selectMode(.endlessPractice)
        model.setHardcore(true)
        await model.start()
        await model.finished(result(chai))
        await model.finished(result(khaneh))
        model.again()
        XCTAssertEqual(model.stage, .lobby(mode: .endlessPractice, hardcore: true, message: nil))
    }

    func testTheClockReadsTheInjectedUptime() async {
        let uptime = Box()
        let model = make(RaceFake(), uptime: uptime)
        await model.start()
        XCTAssertEqual(run(model)?.startedAt, 100)
        uptime.value = 107.5
        XCTAssertEqual(model.now(), 107.5)
    }
}

@MainActor
final class RaceBoardsModelTests: XCTestCase {
    private func make(_ race: RaceFake) -> RaceBoardsModel {
        let source = FakeVocabSource()
        source.loadHandler = { .ready(content) }
        return RaceBoardsModel(store: VocabularyStore(source: source), race: race)
    }

    func testLoadsTheGlobalBoardFirstThenFollowsTheScopeAndTheHardcoreSwitch() async {
        let race = RaceFake()
        race.board = RaceBoardResponse(entries: [RaceBoardEntry(rank: 1, userId: "u", score: 9.5, timeMs: 60_000, isYou: true)])
        let model = make(race)
        XCTAssertTrue(model.loading)
        await model.load()
        XCTAssertFalse(model.loading)
        XCTAssertEqual(model.entries.count, 1)
        await model.selectScope(.friends)
        await model.setHardcore(true)
        XCTAssertEqual(race.boardsAsked.map { "\($0.0.rawValue)/\($0.1)" }, ["global/false", "friends/false", "friends/true"])
    }

    func testAFailedLoadShowsAMessageAndNoRows() async {
        let race = RaceFake()
        race.boardFailure = ApiError(status: 503, body: ApiErrorBody(error: "Try later"))
        let model = make(race)
        await model.load()
        XCTAssertNotNil(model.error)
        XCTAssertTrue(model.entries.isEmpty)
        XCTAssertFalse(model.loading)
    }
}
