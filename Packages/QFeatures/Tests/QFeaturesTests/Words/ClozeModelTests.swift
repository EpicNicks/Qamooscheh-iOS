import XCTest
import QModel
import QDomain
import QNetwork
import QData
@testable import QFeatures

private let man = "\u{0645}\u{0646}<pron>"
private let chai = "\u{0686}\u{0627}\u{06CC}<n>"
private let khaneh = "\u{062E}\u{0627}\u{0646}\u{0647}<n>"
private let chaiWord = "\u{0686}\u{0627}\u{06CC}"
private let sentence = "\u{0645}\u{0646} \u{0686}\u{0627}\u{06CC}"

private let clozeContent = VocabContent(
    courseCode: "fa",
    units: [UnitVocab(unitKey: "u1", title: "Greetings", lessons: [
        LessonVocab(unitKey: "u1", skillKey: "s1", title: "Tea", tags: [man, chai, khaneh]),
    ])],
    lexemes: [
        man: LexemeIndexEntry(gloss: "I / me", romanizationIsAuthored: false),
        chai: LexemeIndexEntry(gloss: "tea", romanizationIsAuthored: false),
        khaneh: LexemeIndexEntry(gloss: "home", romanizationIsAuthored: false),
    ])

private func teaExercise() -> ExerciseArtifact {
    return ExerciseArtifact(type: .typeIn, scriptMode: .native, prompt: "I like tea", answer: [sentence], tags: [man, chai])
}

private func teaCard() -> ClozeCard {
    return buildClozeCard(
        exercise: teaExercise(), tag: chai, hintMap: ClozeRoundModel.hintMap(clozeContent.lexemes), lexemeIndex: clozeContent.lexemes)!
}

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

private final class ClozeSubmitter: FlashcardSubmitter, @unchecked Sendable {
    private let lock = NSLock()
    private var log: [SubmitFlashcardsRequest] = []
    var failures = 0
    var requests: [SubmitFlashcardsRequest] {
        lock.lock()
        defer { lock.unlock() }
        return log
    }

    func submit(_ request: SubmitFlashcardsRequest) async throws -> SubmitFlashcardsResponse {
        lock.lock()
        log.append(request)
        let fail = failures > 0
        if fail { failures -= 1 }
        lock.unlock()
        if fail { throw ApiError(status: 503, body: ApiErrorBody(error: "Try later")) }
        return SubmitFlashcardsResponse(alreadyProcessed: false, xp: 8)
    }
}

@MainActor
final class ClozeCardModelTests: XCTestCase {
    private func make(
        hardcore: Bool = false, courseCode: String = "xx", clock: @escaping () -> TimeInterval = { 0 },
        onEffect: @escaping (FeedbackEvent) -> Void = { _ in }
    ) -> ClozeCardModel {
        return ClozeCardModel(
            card: teaCard(), courseCode: courseCode, hardcore: hardcore, prefs: LocalPrefs(), keyboardMode: nil,
            clock: clock, onEffect: onEffect)
    }

    func testRightFirstTryIsAnsweredAndFinishesOnContinue() {
        var effects: [FeedbackEvent] = []
        let model = make(onEffect: { effects.append($0) })
        XCTAssertEqual(model.status, "Worth up to 5 XP.")
        model.setTyped(chaiWord)
        var results: [ClozeResult] = []
        model.check { results.append($0) }
        XCTAssertTrue(model.answered)
        XCTAssertTrue(model.correct)
        XCTAssertFalse(model.typo)
        XCTAssertEqual(model.status, "Correct! First try.")
        XCTAssertEqual(effects, [.correct])
        XCTAssertTrue(results.isEmpty)
        model.check { results.append($0) }
        XCTAssertEqual(results, [ClozeResult(tag: chai, correct: true, attempt: 1, elapsedMs: 0)])
        model.check { results.append($0) }
        XCTAssertEqual(results.count, 1)
    }

    func testAWrongAnswerIsTriedAgainAndPaysLess() {
        var effects: [FeedbackEvent] = []
        let model = make(onEffect: { effects.append($0) })
        model.setTyped("\u{0646}\u{0627}\u{0646}")
        model.check { _ in XCTFail("finished early") }
        XCTAssertFalse(model.answered)
        XCTAssertEqual(model.attempt, 2)
        XCTAssertEqual(model.typed, "")
        XCTAssertEqual(model.caret, 0)
        XCTAssertEqual(model.status, "Not quite. Now worth up to 3 XP.")
        XCTAssertTrue(model.canGiveUp)
        XCTAssertEqual(effects, [.incorrect])
        model.setTyped(chaiWord)
        var results: [ClozeResult] = []
        model.check { _ in }
        model.check { results.append($0) }
        XCTAssertEqual(results.map { $0.attempt }, [2])
        XCTAssertEqual(model.status, "Correct!")
    }

    func testShowingTheAnswerCountsAsGivenUpOnTheAttemptItReached() {
        let model = make()
        XCTAssertFalse(model.canGiveUp)
        model.setTyped("x")
        model.check { _ in }
        model.setTyped("y")
        model.check { _ in }
        XCTAssertEqual(model.attempt, 3)
        model.giveUp()
        XCTAssertTrue(model.answered)
        XCTAssertFalse(model.correct)
        XCTAssertEqual(model.status, "Here's the word.")
        var results: [ClozeResult] = []
        model.check { results.append($0) }
        XCTAssertEqual(results, [ClozeResult(tag: chai, correct: false, attempt: 3, elapsedMs: 0)])
    }

    func testATypoIsForgivenInARegularRoundButNotInHardcore() {
        let house = ClozeCard(
            tag: "house", before: "I live in a ", after: ".", blankText: "house", accepted: ["house"],
            gapLabel: "house", english: "I live in a house.", contextTags: [])
        let regular = ClozeCardModel(card: house, courseCode: "xx", hardcore: false, prefs: LocalPrefs(), keyboardMode: nil)
        regular.setTyped("hous")
        regular.check { _ in }
        XCTAssertTrue(regular.answered)
        XCTAssertTrue(regular.correct)
        XCTAssertTrue(regular.typo)
        XCTAssertEqual(regular.status, "Close, a small typo. It's spelled house.")

        let hardcore = ClozeCardModel(card: house, courseCode: "xx", hardcore: true, prefs: LocalPrefs(), keyboardMode: nil)
        hardcore.setTyped("hous")
        hardcore.check { _ in }
        XCTAssertFalse(hardcore.answered)
        XCTAssertEqual(hardcore.attempt, 2)
    }

    func testNoTypoIsForgivenInAShortWord() {
        let model = make()
        model.setTyped(chaiWord + "\u{0627}")
        model.check { _ in }
        XCTAssertFalse(model.answered)
    }

    func testBlankInputIsIgnored() {
        let model = make()
        model.setTyped("   ")
        model.check { _ in XCTFail("finished") }
        XCTAssertFalse(model.answered)
        XCTAssertEqual(model.attempt, 1)
        XCTAssertFalse(model.canCheck(keyboardPending: nil))
        model.setTyped(chaiWord)
        XCTAssertTrue(model.canCheck(keyboardPending: nil))
    }

    func testElapsedTimeIsMeasuredFromWhenTheCardAppearedAndClamped() {
        var now: TimeInterval = 100
        let model = make(clock: { now })
        model.setTyped(chaiWord)
        model.check { _ in }
        now = 104.2
        var results: [ClozeResult] = []
        model.check { results.append($0) }
        XCTAssertEqual(results[0].elapsedMs, 4200)

        now = 100
        let slow = make(clock: { now })
        slow.setTyped(chaiWord)
        slow.check { _ in }
        now = 100 + 99_999
        slow.check { results.append($0) }
        XCTAssertEqual(results[1].elapsedMs, 600_000)
    }

    func testThePersianCourseGetsAnInAppKeyboardUntilThePhoneOneIsChosen() {
        var saved: [LocalPrefs] = []
        let model = ClozeCardModel(
            card: teaCard(), courseCode: "fa", hardcore: false, prefs: LocalPrefs(), keyboardMode: "contextual",
            onPrefsChange: { saved.append($0) })
        XCTAssertNotNil(model.keyboard)
        XCTAssertTrue(model.inAppKeyboard)
        model.updatePrefs { $0.deviceInputEnabled = true }
        XCTAssertFalse(model.inAppKeyboard)
        XCTAssertEqual(saved.count, 1)
        XCTAssertTrue(saved[0].deviceInputEnabled)
        model.updatePrefs { $0.deviceInputEnabled = true }
        XCTAssertEqual(saved.count, 1)
    }
}

@MainActor
final class ClozeRoundModelTests: XCTestCase {
    private func makeStore() -> VocabularyStore {
        let source = FakeVocabSource()
        source.loadHandler = { .ready(clozeContent) }
        return VocabularyStore(source: source)
    }

    private func makeModel(
        practice: PracticeFake, sentences: SentencesFake, submitter: ClozeSubmitter?, hardcore: Bool = false, handed: ClozeDeck? = nil
    ) -> ClozeRoundModel {
        return ClozeRoundModel(
            store: makeStore(), services: ClozeServices(practice: practice, sentences: sentences), submitter: submitter,
            hardcore: hardcore, handed: handed, pick: { _ in 0 }, newId: { "sub-1" }, now: { Date(timeIntervalSince1970: 7) })
    }

    private func teaPractice() -> (PracticeFake, SentencesFake) {
        let practice = PracticeFake()
        practice.handler = { _ in
            StarredPracticeResponse(courseVersion: 4, words: [
                StarredPracticeWord(tag: chai, exercises: [ref(0)]),
                StarredPracticeWord(tag: khaneh, exercises: [ref(0)]),
                StarredPracticeWord(tag: man, exercises: []),
            ])
        }
        let sentences = SentencesFake()
        sentences.handler = { _, _ in ["u1/s1/0": teaExercise()] }
        return (practice, sentences)
    }

    func testLoadBuildsOneCardPerWordWithASentenceAndAsksForTheVersionItWasPickedAgainst() async {
        let (practice, sentences) = teaPractice()
        let asked = Box<(refs: [StarredPracticeExercise], version: Int)>()
        sentences.handler = { refs, version in
            asked.set((refs, version))
            return ["u1/s1/0": teaExercise()]
        }
        let model = makeModel(practice: practice, sentences: sentences, submitter: ClozeSubmitter())
        XCTAssertEqual(model.phase, .loading)
        await model.load()
        XCTAssertEqual(model.phase, .playing)
        XCTAssertEqual(model.deck.map { $0.tag }, [chai])
        XCTAssertEqual(model.courseCode, "fa")
        XCTAssertEqual(model.current?.tag, chai)
        XCTAssertEqual(asked.value?.refs, [ref(0)])
        XCTAssertEqual(asked.value?.version, 4)
        XCTAssertFalse(model.repack)
    }

    func testNoUsableSentenceIsAnEmptyRound() async {
        let (practice, sentences) = teaPractice()
        sentences.handler = { _, _ in [:] }
        let model = makeModel(practice: practice, sentences: sentences, submitter: ClozeSubmitter())
        await model.load()
        XCTAssertEqual(model.phase, .empty)
    }

    func testAFailureToPickOrReadSentencesFailsTheRound() async {
        let (practice, sentences) = teaPractice()
        practice.handler = { _ in throw ApiError(status: 503, body: ApiErrorBody(error: "Try later")) }
        let model = makeModel(practice: practice, sentences: sentences, submitter: ClozeSubmitter())
        await model.load()
        guard case .failed = model.phase else { return XCTFail("\(model.phase)") }

        practice.handler = { _ in StarredPracticeResponse(courseVersion: 4, words: [StarredPracticeWord(tag: chai, exercises: [ref(0)])]) }
        sentences.handler = { _, _ in throw LessonLoadError.courseVersionMismatch }
        await model.load()
        guard case .failed = model.phase else { return XCTFail("\(model.phase)") }
    }

    func testTheLastCardSendsTheRoundOnceAsClozeWithAttemptAndTime() async {
        let (practice, sentences) = teaPractice()
        let submitter = ClozeSubmitter()
        let model = makeModel(practice: practice, sentences: sentences, submitter: submitter, hardcore: true)
        await model.load()
        XCTAssertNil(model.xp)
        await model.finished(ClozeResult(tag: chai, correct: true, attempt: 2, elapsedMs: 3100))
        XCTAssertEqual(model.xp, .saved(8))
        XCTAssertNil(model.current)
        XCTAssertEqual(submitter.requests.count, 1)
        let request = submitter.requests[0]
        XCTAssertEqual(request.submissionId, "sub-1")
        XCTAssertEqual(request.courseCode, "fa")
        XCTAssertEqual(request.occurredAt, Date(timeIntervalSince1970: 7))
        XCTAssertFalse(request.inRemix)
        XCTAssertEqual(request.hardcore, true)
        XCTAssertEqual(request.cards, [SubmittedFlashcard(tag: chai, kind: .cloze, correct: true, attempt: 2, elapsedMs: 3100)])
        // A card past the end is ignored.
        await model.finished(ClozeResult(tag: chai, correct: true, attempt: 1, elapsedMs: 1))
        XCTAssertEqual(submitter.requests.count, 1)
    }

    func testAFailedSendKeepsTheRoundForARetryUnderTheSameSubmissionId() async {
        let (practice, sentences) = teaPractice()
        let submitter = ClozeSubmitter()
        submitter.failures = 1
        let model = makeModel(practice: practice, sentences: sentences, submitter: submitter)
        await model.load()
        await model.finished(ClozeResult(tag: chai, correct: false, attempt: 1, elapsedMs: 900))
        XCTAssertEqual(model.xp, .failed)
        XCTAssertTrue(model.isSettlingXp)
        await model.retrySubmit()
        XCTAssertEqual(model.xp, .saved(8))
        XCTAssertFalse(model.isSettlingXp)
        XCTAssertEqual(submitter.requests.map { $0.submissionId }, ["sub-1", "sub-1"])
    }

    func testARepackRoundPlaysTheHandedDeckWithoutAskingTheServerForWords() async {
        let practice = PracticeFake()
        practice.handler = { _ in XCTFail("asked for practice words"); return StarredPracticeResponse(courseVersion: 1, words: []) }
        let submitter = ClozeSubmitter()
        let handed = ClozeDeck(courseCode: "fa", cards: [teaCard()])
        let model = makeModel(practice: practice, sentences: SentencesFake(), submitter: submitter, handed: handed)
        await model.load()
        XCTAssertTrue(model.repack)
        XCTAssertEqual(model.phase, .playing)
        XCTAssertEqual(model.deck, [teaCard()])
        await model.finished(ClozeResult(tag: chai, correct: true, attempt: 1, elapsedMs: 2000))
        XCTAssertEqual(submitter.requests.count, 1)
        XCTAssertEqual(submitter.requests[0].courseCode, "fa")
    }

    func testAnEmptyHandedDeckIsAnInterruptedRound() async {
        let model = makeModel(
            practice: PracticeFake(), sentences: SentencesFake(), submitter: nil, handed: ClozeDeck(courseCode: "fa", cards: []))
        await model.load()
        guard case .failed(let message) = model.phase else { return XCTFail("\(model.phase)") }
        XCTAssertTrue(message.contains("interrupted"))
    }

    func testWithNoSubmitterTheRoundEndsWithFailedXp() async {
        let (practice, sentences) = teaPractice()
        let model = makeModel(practice: practice, sentences: sentences, submitter: nil)
        await model.load()
        await model.finished(ClozeResult(tag: chai, correct: true, attempt: 1, elapsedMs: 1000))
        XCTAssertEqual(model.xp, .failed)
    }

    func testFlashcardsFillInHandsOverToAClozeRound() async {
        let source = FakeVocabSource()
        source.loadHandler = { .ready(clozeContent) }
        source.starredHandler = { StarredVocabResponse(tags: [chai], limit: 100, refused: []) }
        let (practice, sentences) = teaPractice()
        let model = FlashcardsModel(
            store: VocabularyStore(source: source), submitter: ClozeSubmitter(),
            cloze: ClozeServices(practice: practice, sentences: sentences))
        await model.refresh()
        XCTAssertTrue(model.canPlayCloze)
        model.setKind(.cloze)
        model.hardcore = true
        model.start()
        XCTAssertNil(model.deck)
        let round = model.clozeRound
        XCTAssertNotNil(round)
        XCTAssertEqual(round?.hardcore, true)
        model.leaveCloze()
        XCTAssertNil(model.clozeRound)
    }

    func testFillInIsNotOfferedWithoutTheServices() async {
        let model = FlashcardsModel(store: VocabularyStore(source: FakeVocabSource()), submitter: nil)
        XCTAssertFalse(model.canPlayCloze)
        model.setKind(.cloze)
        model.start()
        XCTAssertNil(model.clozeRound)
    }
}

private final class Box<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: T?
    func set(_ value: T) { lock.lock(); stored = value; lock.unlock() }
    var value: T? { lock.lock(); defer { lock.unlock() }; return stored }
}

@MainActor
final class SavedPracticeClozeTests: XCTestCase {
    private func makeModel(_ practice: PracticeFake, _ sentences: SentencesFake, submitter: ClozeSubmitter? = ClozeSubmitter()) -> SavedPracticeModel {
        let source = FakeVocabSource()
        source.loadHandler = { .ready(clozeContent) }
        return SavedPracticeModel(
            store: VocabularyStore(source: source), source: practice, submitter: submitter,
            cloze: ClozeServices(practice: practice, sentences: sentences), newId: { "sub-1" })
    }

    private func teaWords() -> (PracticeFake, SentencesFake) {
        let practice = PracticeFake()
        practice.handler = { _ in StarredPracticeResponse(courseVersion: 4, words: [StarredPracticeWord(tag: chai, exercises: [ref(0)])]) }
        let sentences = SentencesFake()
        sentences.handler = { _, _ in ["u1/s1/0": teaExercise()] }
        return (practice, sentences)
    }

    func testFillInTheBlankHandsItsDeckToARoundPlayedUnderTheChosenHardcore() async {
        let (practice, sentences) = teaWords()
        let model = makeModel(practice, sentences)
        await model.load()
        model.selectContents(.cloze)
        model.setHardcore(true)
        await model.start()
        guard let round = model.clozeRound else { return XCTFail("\(model.state)") }
        XCTAssertTrue(round.hardcore)
        XCTAssertTrue(round.repack)
        await round.load()
        XCTAssertEqual(round.phase, .playing)
        XCTAssertEqual(round.deck.map { $0.tag }, [chai])
        XCTAssertEqual(round.courseCode, "fa")
        model.leaveCloze()
        XCTAssertNil(model.clozeRound)
    }

    func testWordsWithNoUsableSentenceLeaveTheChoiceWithAMessage() async {
        let (practice, sentences) = teaWords()
        sentences.handler = { _, _ in [:] }
        let model = makeModel(practice, sentences)
        await model.load()
        model.selectContents(.cloze)
        await model.start()
        XCTAssertNil(model.clozeRound)
        guard case .choosing(_, let selected, let none, _) = model.state else { return XCTFail("\(model.state)") }
        XCTAssertEqual(selected, .cloze)
        XCTAssertTrue(none)
    }

    private func settings(saved: String?, log: Box<LocalPrefs>) -> ClozeSettings {
        var prefs = LocalPrefs()
        prefs.savedRemixContents = saved
        return ClozeSettings(load: { (prefs, LessonServerPrefs()) }, save: { log.set($0) })
    }

    func testOpensOnWhatTheLastRepackHeldWhenThisOneOffersItAndRemembersTheNewChoice() async {
        let (practice, sentences) = teaWords()
        let log = Box<LocalPrefs>()
        let source = FakeVocabSource()
        source.loadHandler = { .ready(clozeContent) }
        let model = SavedPracticeModel(
            store: VocabularyStore(source: source), source: practice, submitter: nil,
            cloze: ClozeServices(practice: practice, sentences: sentences, settings: settings(saved: "type_in", log: log)), newId: { "sub-1" })
        await model.load()
        guard case .choosing(_, let selected, _, _) = model.state else { return XCTFail("\(model.state)") }
        XCTAssertEqual(selected, .typeIn)
        model.selectContents(.all)
        await model.start()
        for _ in 0..<50 where log.value == nil { await Task.yield() }
        XCTAssertEqual(log.value?.savedRemixContents, "all")
    }

    func testARememberedChoiceThisRepackDoesNotOfferFallsBack() async {
        let (practice, sentences) = teaWords()
        let source = FakeVocabSource()
        source.loadHandler = { .ready(clozeContent) }
        // Flashcards only needs flashcards, and the remembered choice is not offered when there are none.
        practice.handler = { _ in StarredPracticeResponse(courseVersion: 4, words: [StarredPracticeWord(tag: "gone", exercises: [ref(0)])]) }
        let model = SavedPracticeModel(
            store: VocabularyStore(source: source), source: practice, submitter: nil,
            cloze: ClozeServices(practice: practice, sentences: sentences, settings: settings(saved: "flashcards", log: Box<LocalPrefs>())),
            newId: { "sub-1" })
        await model.load()
        guard case .choosing(_, let selected, _, _) = model.state else { return XCTFail("\(model.state)") }
        XCTAssertEqual(selected, .all)
    }

    func testAComposingExerciseIsJudgedByTheLearnersCard() async {
        let (practice, sentences) = teaWords()
        let composite = ExerciseArtifact(type: .typeIn, scriptMode: .native, prompt: "I like tea", tiles: ["a"], answer: [sentence], tags: [man, chai])
        sentences.handler = { _, _ in ["u1/s1/0": composite] }
        let source = FakeVocabSource()
        source.loadHandler = { .ready(clozeContent) }
        source.cards = [man: CardState(lexemeTag: man, stability: 5, difficulty: 5, reviewCount: 6, lapseCount: 0)]
        let model = SavedPracticeModel(
            store: VocabularyStore(source: source), source: practice, submitter: nil,
            cloze: ClozeServices(practice: practice, sentences: sentences), newId: { "sub-1" })
        await model.load()
        // A well-known first word shows the exercise as typing, not as a word bank.
        model.selectContents(.wordBank)
        await model.start()
        guard case .choosing(_, _, let none, _) = model.state else { return XCTFail("\(model.state)") }
        XCTAssertTrue(none)
        model.selectContents(.typeIn)
        await model.start()
        XCTAssertEqual(model.state, .cardsDone(
            known: 0, total: 0, xp: 0, exercises: SavedPracticeExercises(courseVersion: 4, exercises: "u1/s1/0", count: 1)))
    }

    func testTheFilteredChoicesReadTheLessonsToTellWhichExercisesAreTyped() async {
        let (practice, sentences) = teaWords()
        let model = makeModel(practice, sentences)
        await model.load()
        // teaExercise is a plain typed exercise, so Typing only keeps it and Word bank only finds nothing.
        model.selectContents(.wordBank)
        await model.start()
        guard case .choosing(_, _, let none, _) = model.state else { return XCTFail("\(model.state)") }
        XCTAssertTrue(none)
        model.selectContents(.typeIn)
        await model.start()
        XCTAssertEqual(model.state, .cardsDone(
            known: 0, total: 0, xp: 0, exercises: SavedPracticeExercises(courseVersion: 4, exercises: "u1/s1/0", count: 1)))
    }
}
