import XCTest
import QModel
import QDomain
import QNetwork
@testable import QFeatures

final class FakeVocabSource: VocabularySource, @unchecked Sendable {
    var loadHandler: @Sendable () async throws -> VocabLoad = { .noCourse }
    var cards: [String: CardState] = [:]
    var starredHandler: @Sendable () async throws -> StarredVocabResponse = { StarredVocabResponse(tags: [], limit: 100, refused: []) }
    var setHandler: @Sendable (String, Bool) async throws -> StarredVocabResponse = { _, _ in
        StarredVocabResponse(tags: [], limit: 100, refused: [])
    }
    private(set) var setCalls: [String] = []

    func load() async throws -> VocabLoad { try await loadHandler() }
    func cardStates() async -> [String: CardState] { cards }
    func starred() async throws -> StarredVocabResponse { try await starredHandler() }
    func setStarred(tag: String, starred: Bool) async throws -> StarredVocabResponse {
        setCalls.append("\(tag)=\(starred)")
        return try await setHandler(tag, starred)
    }
}

let sampleContent = VocabContent(
    courseCode: "fa",
    units: [UnitVocab(unitKey: "u1", title: "Greetings", lessons: [
        LessonVocab(unitKey: "u1", skillKey: "s1", title: "Hello", tags: ["a", "b"]),
        LessonVocab(unitKey: "u1", skillKey: "s2", title: "Bread", tags: ["b", "c"]),
    ])],
    lexemes: [
        "a": LexemeIndexEntry(gloss: "alpha", romanizationIsAuthored: false),
        "b": LexemeIndexEntry(gloss: "bravo", romanizationIsAuthored: false),
        "c": LexemeIndexEntry(gloss: "charlie", romanizationIsAuthored: false),
    ])

@MainActor
final class VocabularyModelTests: XCTestCase {
    private func makeStore(_ source: FakeVocabSource, unauthorized: (@Sendable () -> Void)? = nil) -> VocabularyStore {
        source.loadHandler = { .ready(sampleContent) }
        return VocabularyStore(source: source, onUnauthorized: unauthorized)
    }

    func testCourseSwitchResetThenFailedReloadDoesNotKeepOldWords() async {
        let source = FakeVocabSource()
        source.cards = ["a": CardState(lexemeTag: "a", stability: 1, difficulty: 1, reviewCount: 1, lapseCount: 0)]
        let store = makeStore(source)
        await store.refresh()
        XCTAssertEqual(store.status, .ready)
        store.resetForCourseSwitch()
        source.cards = [:]
        source.loadHandler = { throw ApiError(status: 500, body: nil) }
        await store.refresh()
        XCTAssertNil(store.content)
        XCTAssertNotEqual(store.status, .ready)
    }

    func testRefreshLoadsContentCardsAndStars() async {
        let source = FakeVocabSource()
        source.cards = ["a": CardState(lexemeTag: "a", stability: 1, difficulty: 1, reviewCount: 1, lapseCount: 0)]
        source.starredHandler = { StarredVocabResponse(tags: ["b"], limit: 100, refused: []) }
        let store = makeStore(source)
        await store.refresh()
        XCTAssertEqual(store.status, .ready)
        XCTAssertEqual(store.content?.courseCode, "fa")
        XCTAssertEqual(store.cards.count, 1)
        XCTAssertEqual(store.starredTags, ["b"])
    }

    func testScopeAndSearchSurviveReappearAndFailedReloadKeepsContent() async {
        let source = FakeVocabSource()
        let store = makeStore(source)
        let model = SkillVocabularyModel(store: store, unitKey: "u1", skillKey: "s1")
        await model.refresh()
        XCTAssertEqual(model.scope, .lesson)
        XCTAssertEqual(model.terms.map { $0.tag }, ["a", "b"])
        model.setScope(.course)
        model.query = "char"
        source.loadHandler = { throw URLError(.notConnectedToInternet) }
        await model.refresh()
        XCTAssertEqual(store.status, .ready)
        XCTAssertEqual(model.scope, .course)
        XCTAssertEqual(model.query, "char")
        XCTAssertEqual(model.terms.map { $0.tag }, ["c"])
    }

    func testMissingLessonFallsThroughToWidestScope() async {
        let store = makeStore(FakeVocabSource())
        let model = SkillVocabularyModel(store: store, unitKey: "u1", skillKey: "gone")
        await model.refresh()
        XCTAssertEqual(model.scopes.map { $0.scope }, [.unit, .course])
        XCTAssertEqual(model.scope, .course)
        let missingUnit = SkillVocabularyModel(store: store, unitKey: "nope", skillKey: nil)
        XCTAssertEqual(missingUnit.scope, .course)
        XCTAssertEqual(missingUnit.terms.map { $0.tag }, ["a", "b", "c"])
    }

    func testServerErrorMessageIsSurfacedOnFirstLoad() async {
        let source = FakeVocabSource()
        let store = VocabularyStore(source: source)
        source.loadHandler = { throw ApiError(status: 500, body: ApiErrorBody(error: "Disk full")) }
        await store.refresh()
        XCTAssertEqual(store.status, .failed("Disk full"))
    }

    func testCancelledLoadIsNotAnErrorState() async {
        let source = FakeVocabSource()
        let store = VocabularyStore(source: source)
        source.loadHandler = { throw CancellationError() }
        await store.refresh()
        XCTAssertEqual(store.status, .loading)
        source.loadHandler = { throw URLError(.cancelled) }
        await store.refresh()
        XCTAssertEqual(store.status, .loading)
    }

    func testUnauthorizedIsReportedEvenFromSupersededLoad() async {
        let source = FakeVocabSource()
        let flag = Flag()
        let store = VocabularyStore(source: source, onUnauthorized: { flag.set() })
        let gate = GateBox()
        let entered = expectation(description: "first load entered")
        source.loadHandler = {
            entered.fulfill()
            await gate.wait()
            throw ApiError(status: 401, body: nil)
        }
        let first = Task { await store.refresh() }
        await fulfillment(of: [entered], timeout: 5)
        source.loadHandler = { .ready(sampleContent) }
        await store.refresh()
        gate.open()
        await first.value
        XCTAssertTrue(flag.value)
        XCTAssertEqual(store.status, .ready)
    }

    func testStarFillsAtOnceAndFailureRollsBackOnlyThatWord() async {
        let source = FakeVocabSource()
        source.starredHandler = { StarredVocabResponse(tags: ["a"], limit: 100, refused: []) }
        let store = makeStore(source)
        await store.refresh()
        source.setHandler = { tag, _ in
            if tag == "b" { throw ApiError(status: 409, body: ApiErrorBody(error: "You can save up to 1 words.")) }
            return StarredVocabResponse(tags: ["c", "a"], limit: 100, refused: [])
        }
        await store.toggleStar("c")
        XCTAssertEqual(store.starredTags, ["c", "a"])
        await store.toggleStar("b")
        XCTAssertEqual(store.starredTags, ["c", "a"])
        XCTAssertEqual(store.starMessage, "You can save up to 1 words.")
        await store.toggleStar("a")
        XCTAssertEqual(source.setCalls, ["c=true", "b=true", "a=false"])
    }

    func testStarRequestsGoOneAtATimeAndLatestChoiceShows() async {
        let source = FakeVocabSource()
        let store = makeStore(source)
        await store.refresh()
        let gate = GateBox()
        source.setHandler = { tag, starred in
            if starred { await gate.wait(); return StarredVocabResponse(tags: ["a"], limit: 100, refused: []) }
            return StarredVocabResponse(tags: [], limit: 100, refused: [])
        }
        let first = Task { await store.toggleStar("a") }
        for _ in 0..<200 where source.setCalls.isEmpty { await Task.yield() }
        let second = Task { await store.toggleStar("a") }
        for _ in 0..<50 { await Task.yield() }
        // The second tap is waiting its turn; the learner already sees their latest choice.
        XCTAssertEqual(source.setCalls, ["a=true"])
        XCTAssertEqual(store.starredTags, [])
        gate.open()
        await first.value
        await second.value
        XCTAssertEqual(source.setCalls, ["a=true", "a=false"])
        XCTAssertEqual(store.starredTags, [])
    }

    func testUnstarSendsAbsoluteStateAndClearsMessage() async {
        let source = FakeVocabSource()
        source.starredHandler = { StarredVocabResponse(tags: ["a", "b"], limit: 100, refused: []) }
        let store = makeStore(source)
        await store.refresh()
        source.setHandler = { _, _ in StarredVocabResponse(tags: ["b"], limit: 100, refused: []) }
        await store.toggleStar("a")
        XCTAssertEqual(source.setCalls, ["a=false"])
        XCTAssertEqual(store.starredTags, ["b"])
        XCTAssertNil(store.starMessage)
    }
}

final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false
    func set() { lock.lock(); flag = true; lock.unlock() }
    var value: Bool { lock.lock(); defer { lock.unlock() }; return flag }
}

final class GateBox: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Never>?
    private var opened = false

    func wait() async {
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            lock.lock()
            if opened {
                lock.unlock()
                c.resume()
            } else {
                continuation = c
                lock.unlock()
            }
        }
    }

    func open() {
        lock.lock()
        opened = true
        let c = continuation
        continuation = nil
        lock.unlock()
        c?.resume()
    }
}
