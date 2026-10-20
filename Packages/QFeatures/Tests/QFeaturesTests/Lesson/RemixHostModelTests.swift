import XCTest
import QModel
import QDomain
import QData
@testable import QFeatures

private let man = "\u{0645}\u{0646}<pron>"
private let chai = "\u{0686}\u{0627}\u{06CC}<n>"
private let sentence = "\u{0645}\u{0646} \u{0686}\u{0627}\u{06CC}"

private let content = VocabContent(
    courseCode: "fa",
    units: [UnitVocab(unitKey: "u1", title: "Greetings", lessons: [LessonVocab(unitKey: "u1", skillKey: "s1", title: "Tea", tags: [man, chai])])],
    lexemes: [
        man: LexemeIndexEntry(gloss: "I / me", romanizationIsAuthored: false),
        chai: LexemeIndexEntry(gloss: "tea", romanizationIsAuthored: false),
    ])

private struct RemixLoader: LessonSetupLoading {
    var lesson: LessonSetup?
    var pool: RemixClozePool?
    var failure: Error?

    func setup(for route: LessonRoute) async throws -> LessonSetup? {
        if let failure = failure { throw failure }
        return lesson
    }

    func remixCloze(for route: LessonRoute) async throws -> RemixClozePool? {
        if let failure = failure { throw failure }
        return pool
    }

    func serverPrefs() async -> LessonServerPrefs { LessonServerPrefs() }
    func saveScriptMode(_ mode: ScriptMode) async {}
}

@MainActor
final class RemixHostModelTests: XCTestCase {
    private func lesson() -> LessonSetup {
        let exercise = ExerciseArtifact(type: .wordBank, scriptMode: .native, prompt: "p", tiles: ["a"], answer: ["a"], tags: ["t"])
        let instance = ExerciseInstance(key: "u/s/0", unitKey: "u", skillKey: "s", ordinal: 0, exercise: exercise, renderType: .wordBank)
        return LessonSetup(courseCode: "fa", courseVersion: 1, instances: [instance], exerciseCountBySkill: ["s": 1])
    }

    private func teaPool(tags: [String]? = nil) -> RemixClozePool {
        let exercise = ExerciseArtifact(type: .typeIn, scriptMode: .native, prompt: "I like tea", answer: [sentence], tags: [man, chai])
        return RemixClozePool(courseCode: "fa", exercises: [exercise], tags: tags ?? [man, chai])
    }

    private func make(_ loader: RemixLoader) -> RemixHostModel {
        let defaults = UserDefaults(suiteName: "remix-host-test-" + UUID().uuidString) ?? UserDefaults.standard
        let environment = LessonEnvironment(
            loader: loader, userId: { "u1" }, prefsStore: LocalPrefsStore(defaults: defaults), submit: { _, _ in .queued })
        let source = FakeVocabSource()
        source.loadHandler = { .ready(content) }
        let store = VocabularyStore(source: source)
        return RemixHostModel(
            route: LessonRoute.forRemix(themeIds: ["food"]), environment: environment, store: store,
            makeRound: { deck, hardcore in
                ClozeRoundModel(
                    store: store, services: ClozeServices(practice: nil, sentences: nil), submitter: nil,
                    hardcore: hardcore, handed: deck)
            },
            pick: { _ in 0 })
    }

    func testOffersEveryChoiceButTheFlashcardOnesWithFillInTheBlankLast() {
        let model = make(RemixLoader())
        XCTAssertEqual(model.options, [.all, .typeIn, .wordBank, .cloze])
        guard case .choosing(let selected, let none, let hardcore) = model.stage else { return XCTFail("\(model.stage)") }
        XCTAssertEqual(selected, .all)
        XCTAssertFalse(none)
        XCTAssertFalse(hardcore)
    }

    func testStartingAnExerciseChoicePlaysTheLesson() async {
        let model = make(RemixLoader(lesson: lesson()))
        model.select(.typeIn)
        await model.start()
        guard case .lesson = model.stage else { return XCTFail("\(model.stage)") }
    }

    func testAChoiceWithNothingInItStaysOnTheChoiceWithAMessage() async {
        let model = make(RemixLoader())
        model.select(.wordBank)
        await model.start()
        guard case .choosing(let selected, let none, _) = model.stage else { return XCTFail("\(model.stage)") }
        XCTAssertEqual(selected, .wordBank)
        XCTAssertTrue(none)
        model.select(.all)
        guard case .choosing(_, let cleared, _) = model.stage else { return XCTFail("\(model.stage)") }
        XCTAssertFalse(cleared)
    }

    func testFillInTheBlankHandsItsDeckToARoundPlayedUnderHardcore() async {
        let model = make(RemixLoader(pool: teaPool()))
        model.select(.cloze)
        model.setHardcore(true)
        await model.start()
        guard case .cloze(let round) = model.stage else { return XCTFail("\(model.stage)") }
        XCTAssertTrue(round.hardcore)
        XCTAssertTrue(round.repack)
        await round.load()
        XCTAssertEqual(round.phase, .playing)
        XCTAssertEqual(round.deck.map { $0.tag }, [chai])
        XCTAssertEqual(round.courseCode, "fa")
    }

    func testFillInTheBlankWithNoUsableSentenceStaysOnTheChoice() async {
        let model = make(RemixLoader(pool: teaPool(tags: ["unknown"])))
        model.select(.cloze)
        await model.start()
        guard case .choosing(let selected, let none, _) = model.stage else { return XCTFail("\(model.stage)") }
        XCTAssertEqual(selected, .cloze)
        XCTAssertTrue(none)
    }

    func testALoadFailureIsReportedAndTheChoiceCanBeReopened() async {
        let model = make(RemixLoader(failure: URLError(.notConnectedToInternet)))
        await model.start()
        guard case .failed = model.stage else { return XCTFail("\(model.stage)") }
        model.retry()
        guard case .choosing = model.stage else { return XCTFail("\(model.stage)") }
    }
}
