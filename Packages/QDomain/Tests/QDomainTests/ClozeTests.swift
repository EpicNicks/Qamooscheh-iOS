import XCTest
import QModel
@testable import QDomain

// Port of web cloze.test.ts / Android ClozeTest, plus the backend's shared conformance table.
final class ClozeTests: XCTestCase {
    private func lex(_ tag: String, _ gloss: String, register: Register? = nil, forms: [String]? = nil) -> (tag: String, entry: LexemeIndexEntry) {
        return (tag, LexemeIndexEntry(gloss: gloss, register: register, romanizationIsAuthored: false, forms: forms))
    }

    private let man = "\u{0645}\u{0646}<pron>"
    private let chai = "\u{0686}\u{0627}\u{06CC}<n>"
    private let khaneh = "\u{062E}\u{0627}\u{0646}\u{0647}<n>"

    private lazy var lexemes: [(tag: String, entry: LexemeIndexEntry)] = [
        lex(man, "I / me"),
        lex(chai, "tea"),
        lex(khaneh, "home / house (informal)", register: .spoken),
    ]
    private lazy var index: [String: LexemeIndexEntry] = Dictionary(uniqueKeysWithValues: lexemes.map { ($0.tag, $0.entry) })
    private lazy var hints: [String: WordHint] = buildLexemeHintMap(lexemes)

    private func typeIn(_ prompt: String, _ answer: String, tags: [String]) -> ExerciseArtifact {
        return ExerciseArtifact(type: .typeIn, scriptMode: .native, prompt: prompt, answer: [answer], tags: tags)
    }

    // MARK: Conformance table

    /// `tools/Qamooscheh.GraderBuilder/verify/cloze-xp-vectors.json` in the backend repo: (name, attempt, correct, paidToday, xp, rating).
    /// The device only knows the table for a word's first payout of the day (paidToday 0); the server applies the cooldown after that.
    private let vectors: [(name: String, attempt: Int, correct: Bool, paidToday: Int, xp: Int, rating: String)] = [
        ("right first time, first payout of the day", 1, true, 0, 5, "Good"),
        ("right on the first retry", 2, true, 0, 3, "Hard"),
        ("right on the second retry", 3, true, 0, 1, "Again"),
        ("right on the third retry pays nothing", 4, true, 0, 0, "Again"),
        ("gave up on the first try", 1, false, 0, 0, "Again"),
        ("gave up after a retry", 2, false, 0, 0, "Again"),
        ("same word again today, first try", 1, true, 1, 1, "Good"),
        ("same word again today, first retry", 2, true, 1, 1, "Hard"),
        ("same word a third time today", 1, true, 2, 1, "Good"),
        ("same word a fourth time today", 1, true, 3, 0, "Good"),
        ("same word long after the cooldown is spent", 1, true, 10, 0, "Good"),
        ("wrong repeat pays nothing and does not use a payout", 1, false, 1, 0, "Again"),
    ]

    func testXpTableMatchesTheSharedVectorsForAFirstPayout() {
        for v in vectors where v.paidToday == 0 {
            XCTAssertEqual(clozeXp(attempt: v.attempt, correct: v.correct), v.xp, v.name)
        }
    }

    func testRatingMatchesTheSharedVectors() {
        for v in vectors {
            XCTAssertEqual(clozeRating(attempt: v.attempt, correct: v.correct).rawValue, v.rating, v.name)
        }
    }

    // MARK: Grading

    func testExactAnswerIgnoresReadingAidsAndArabicLetterVariants() {
        XCTAssertEqual(gradeCloze("\u{062E}\u{064E}\u{0627}\u{0646}\u{0647}", accepted: ["\u{062E}\u{0627}\u{0646}\u{0647}"], hardcore: false), .exact)
        // Arabic yeh typed for the Persian one.
        XCTAssertEqual(gradeCloze("\u{0686}\u{0627}\u{064A}", accepted: ["\u{0686}\u{0627}\u{06CC}"], hardcore: true), .exact)
        XCTAssertEqual(gradeCloze("  Tea ", accepted: ["tea"], hardcore: true), .exact)
    }

    func testAnyAcceptedSpellingCounts() {
        XCTAssertEqual(gradeCloze("books", accepted: ["book", "books"], hardcore: true), .exact)
    }

    func testOneLetterTypoIsForgivenInAWordOfFourOrMoreLetters() {
        XCTAssertEqual(gradeCloze("hous", accepted: ["house"], hardcore: false), .typo)
        XCTAssertEqual(gradeCloze("hosue", accepted: ["house"], hardcore: false), .typo)
        XCTAssertEqual(gradeCloze("houze", accepted: ["house"], hardcore: false), .typo)
        XCTAssertEqual(gradeCloze("housee", accepted: ["house"], hardcore: false), .typo)
        XCTAssertEqual(gradeCloze("hxuzz", accepted: ["house"], hardcore: false), .wrong)
    }

    func testNoTypoIsForgivenInAShortWord() {
        XCTAssertEqual(gradeCloze("tee", accepted: ["tea"], hardcore: false), .wrong)
        XCTAssertEqual(gradeCloze("\u{0645}\u{0646}\u{0627}", accepted: ["\u{0645}\u{0646}"], hardcore: false), .wrong)
    }

    func testHardcoreForgivesNoTypo() {
        XCTAssertEqual(gradeCloze("hous", accepted: ["house"], hardcore: true), .wrong)
        XCTAssertEqual(gradeCloze("house", accepted: ["house"], hardcore: true), .exact)
    }

    func testBlankAnswerIsWrong() {
        XCTAssertEqual(gradeCloze("   ", accepted: ["house"], hardcore: false), .wrong)
        XCTAssertEqual(gradeCloze("house", accepted: [], hardcore: false), .wrong)
    }

    // MARK: Cards

    func testCardCutsTheWordOutOfTheSentence() throws {
        let sentence = "\u{0645}\u{0646} \u{0686}\u{0627}\u{06CC}"
        let exercise = typeIn("I like tea", sentence, tags: [man, chai])
        let card = try XCTUnwrap(buildClozeCard(exercise: exercise, tag: chai, hintMap: hints, lexemeIndex: index))
        XCTAssertEqual(card.blankText, "\u{0686}\u{0627}\u{06CC}")
        XCTAssertEqual(card.before + card.blankText + card.after, sentence)
        XCTAssertEqual(card.accepted, ["\u{0686}\u{0627}\u{06CC}"])
        XCTAssertEqual(card.english, "I like tea")
        XCTAssertEqual(card.gapLabel, "tea")
        XCTAssertEqual(card.contextTags, [man])
    }

    func testAnEnglishAnswerSwapsTheSides() throws {
        let sentence = "\u{0645}\u{0646} \u{0686}\u{0627}\u{06CC}"
        let exercise = typeIn(sentence, "I like tea", tags: [man, chai])
        let card = try XCTUnwrap(buildClozeCard(exercise: exercise, tag: chai, hintMap: hints, lexemeIndex: index))
        XCTAssertEqual(card.english, "I like tea")
        XCTAssertEqual(card.before + card.blankText + card.after, sentence)
    }

    func testAWordBankExerciseIsJoinedIntoItsSentence() throws {
        let exercise = ExerciseArtifact(
            type: .wordBank, scriptMode: .native, prompt: "I like tea", tiles: nil,
            answer: ["\u{0645}\u{0646}", "\u{0686}\u{0627}\u{06CC}"], tags: [man, chai])
        let card = try XCTUnwrap(buildClozeCard(exercise: exercise, tag: chai, hintMap: hints, lexemeIndex: index))
        XCTAssertEqual(card.blankText, "\u{0686}\u{0627}\u{06CC}")
        XCTAssertEqual(card.before + card.blankText + card.after, "\u{0645}\u{0646} \u{0686}\u{0627}\u{06CC}")
    }

    func testNoCardWhenTheWordIsNotInTheSentenceOrIsWrittenTwice() {
        let once = typeIn("I like tea", "\u{0645}\u{0646} \u{0686}\u{0627}\u{06CC}", tags: [man, chai])
        XCTAssertNil(buildClozeCard(exercise: once, tag: khaneh, hintMap: hints, lexemeIndex: index))
        let twice = typeIn("tea and tea", "\u{0686}\u{0627}\u{06CC} \u{0648} \u{0686}\u{0627}\u{06CC}", tags: [chai])
        XCTAssertNil(buildClozeCard(exercise: twice, tag: chai, hintMap: hints, lexemeIndex: index))
    }

    func testNoCardForAnExerciseKindWithNoSentenceOrAnUnknownWord() {
        let match = ExerciseArtifact(type: .match, scriptMode: .native, prompt: "Match", answer: ["x"], tags: [chai])
        XCTAssertNil(buildClozeCard(exercise: match, tag: chai, hintMap: hints, lexemeIndex: index))
        let exercise = typeIn("I like tea", "\u{0645}\u{0646} \u{0686}\u{0627}\u{06CC}", tags: [man, chai])
        XCTAssertNil(buildClozeCard(exercise: exercise, tag: "nope<n>", hintMap: hints, lexemeIndex: index))
    }

    func testGapLabelPrefersTheMeaningInTheEnglishSentenceAndNamesAnInformalWord() {
        let entry = LexemeIndexEntry(gloss: "I / me", romanizationIsAuthored: false)
        XCTAssertEqual(clozeGapLabel(entry, english: "Give it to me"), "me")
        XCTAssertEqual(clozeGapLabel(entry, english: "Nothing relevant"), "I / me")
        let spoken = LexemeIndexEntry(gloss: "house (a home)", register: .spoken, romanizationIsAuthored: false)
        XCTAssertEqual(clozeGapLabel(spoken, english: "Nothing relevant"), "house [informal]")
    }

    // MARK: Decks

    func testDeckHasOneCardPerWordAndDropsWordsWithNoUsableSentence() {
        let sentence = typeIn("I like tea", "\u{0645}\u{0646} \u{0686}\u{0627}\u{06CC}", tags: [man, chai])
        let sources = [
            ClozeSource(tag: chai, exercises: [sentence]),
            ClozeSource(tag: khaneh, exercises: [sentence]),
            ClozeSource(tag: man, exercises: []),
        ]
        let deck = buildClozeDeck(sources: sources, hintMap: hints, lexemeIndex: index)
        XCTAssertEqual(deck.map { $0.tag }, [chai])
    }

    func testDeckPickChoosesAmongTheSentencesThatGiveABlank() {
        let first = typeIn("I like tea", "\u{0645}\u{0646} \u{0686}\u{0627}\u{06CC}", tags: [man, chai])
        let second = typeIn("Tea!", "\u{0686}\u{0627}\u{06CC}", tags: [chai])
        let source = ClozeSource(tag: chai, exercises: [first, second])
        XCTAssertEqual(buildClozeDeck(sources: [source], hintMap: hints, lexemeIndex: index)[0].english, "I like tea")
        let picked = buildClozeDeck(sources: [source], hintMap: hints, lexemeIndex: index, pick: { count in count - 1 })
        XCTAssertEqual(picked[0].english, "Tea!")
        let outOfRange = buildClozeDeck(sources: [source], hintMap: hints, lexemeIndex: index, pick: { _ in 99 })
        XCTAssertEqual(outOfRange[0].english, "Tea!")
    }

    func testSourcesForTagsKeepTheTagOrderAndDropWordsNoExerciseUses() {
        let a = typeIn("I like tea", "\u{0645}\u{0646} \u{0686}\u{0627}\u{06CC}", tags: [man, chai])
        let b = typeIn("Tea!", "\u{0686}\u{0627}\u{06CC}", tags: [chai])
        let sources = clozeSourcesForTags([chai, khaneh, man, chai], exercises: [a, b])
        XCTAssertEqual(sources.map { $0.tag }, [chai, man])
        XCTAssertEqual(sources[0].exercises, [a, b])
        XCTAssertEqual(sources[1].exercises, [a])
    }

    func testPracticeSourcesLookExercisesUpByTheirReference() {
        let a = typeIn("I like tea", "\u{0645}\u{0646} \u{0686}\u{0627}\u{06CC}", tags: [man, chai])
        let words = [
            StarredPracticeWord(tag: chai, exercises: [
                StarredPracticeExercise(unitKey: "u1", skillKey: "s1", ordinal: 2),
                StarredPracticeExercise(unitKey: "u1", skillKey: "s1", ordinal: 9),
            ]),
            StarredPracticeWord(tag: khaneh, exercises: []),
        ]
        let sources = clozeSourcesFromPractice(words, exercises: ["u1/s1/2": a])
        XCTAssertEqual(sources, [ClozeSource(tag: chai, exercises: [a]), ClozeSource(tag: khaneh, exercises: [])])
    }

    func testSavedVerbCardBlanksTheFormItsExercisePractises() {
        let khordan = "\u{062E}\u{0648}\u{0631}\u{062F}\u{0646}<v>"
        let khordam = "\u{062E}\u{0648}\u{0631}\u{062F}\u{0645}<v>"
        let entries = lexemes + [
            (tag: khordan, entry: LexemeIndexEntry(gloss: "to eat", pos: "verb", verbForm: "infinitive", lemma: "\u{062E}\u{0648}\u{0631}\u{062F}\u{0646}", romanizationIsAuthored: false)),
            (tag: khordam, entry: LexemeIndexEntry(gloss: "I ate", pos: "verb", verbForm: "conjugated", lemma: "\u{062E}\u{0648}\u{0631}\u{062F}\u{0646}", romanizationIsAuthored: false)),
        ]
        let byTag = Dictionary(uniqueKeysWithValues: entries.map { ($0.tag, $0.entry) })
        let a = typeIn("I ate tea", "\u{0686}\u{0627}\u{06CC} \u{062E}\u{0648}\u{0631}\u{062F}\u{0645}", tags: [chai, khordam])
        let words = [StarredPracticeWord(tag: khordan, exercises: [StarredPracticeExercise(unitKey: "u1", skillKey: "s1", ordinal: 0, form: khordam)])]
        let sources = clozeSourcesFromPractice(words, exercises: ["u1/s1/0": a])
        XCTAssertEqual(sources, [ClozeSource(tag: khordan, exercises: [a], forms: [khordam])])
        let deck = buildClozeDeck(sources: sources, hintMap: buildLexemeHintMap(entries), lexemeIndex: byTag)
        XCTAssertEqual(deck.map { $0.tag }, [khordam])
        XCTAssertEqual(deck.first?.blankText, "\u{062E}\u{0648}\u{0631}\u{062F}\u{0645}")
    }

    // MARK: Results

    func testSummaryCountsCardsByAttemptAndTotalsTheMostItCouldPay() {
        let results = [
            ClozeResult(tag: "a", correct: true, attempt: 1, elapsedMs: 1000),
            ClozeResult(tag: "b", correct: true, attempt: 2, elapsedMs: 1000),
            ClozeResult(tag: "c", correct: true, attempt: 3, elapsedMs: 1000),
            ClozeResult(tag: "d", correct: true, attempt: 5, elapsedMs: 1000),
            ClozeResult(tag: "e", correct: false, attempt: 2, elapsedMs: 1000),
        ]
        let summary = summarizeCloze(results)
        XCTAssertEqual([summary.firstTry, summary.secondTry, summary.thirdTry, summary.later, summary.gaveUp], [1, 1, 1, 1, 1])
        XCTAssertEqual(summary.maxXp, 9)
        XCTAssertFalse(summary.flawless)
        XCTAssertTrue(summarizeCloze([results[0]]).flawless)
        XCTAssertFalse(summarizeCloze([]).flawless)
    }

    func testSubmittedCardCarriesTheAttemptAndTime() {
        let card = ClozeResult(tag: "a", correct: false, attempt: 3, elapsedMs: 4200).submitted
        XCTAssertEqual(card, SubmittedFlashcard(tag: "a", kind: .cloze, correct: false, attempt: 3, elapsedMs: 4200))
    }

    func testAttemptWorthSaysWhatTheNextAnswerPays() {
        XCTAssertEqual(clozeAttemptWorth(1), "Worth up to 5 XP.")
        XCTAssertEqual(clozeAttemptWorth(2), "Not quite. Now worth up to 3 XP.")
        XCTAssertEqual(clozeAttemptWorth(3), "Not quite. Now worth up to 1 XP.")
        XCTAssertEqual(clozeAttemptWorth(4), "Not quite. This one no longer pays XP.")
    }

    func testResultLinesReportTheServersXp() {
        var summary = ClozeSummary()
        summary.firstTry = 2
        summary.gaveUp = 1
        summary.maxXp = 10
        let saved = clozeResultLines(summary, correct: 2, xp: .saved(10))
        XCTAssertEqual(saved.breakdown, "2 on the first try (5 XP each), 0 on the second (3 XP), 0 on the third (1 XP), 1 skipped.")
        XCTAssertEqual(saved.xp, "+10 XP")
        XCTAssertEqual(clozeResultLines(summary, correct: 2, xp: .saved(4)).xp, "+4 XP. Words you've practised a lot today pay less.")
        XCTAssertTrue(clozeResultLines(summary, correct: 2, xp: .saved(0)).xp.hasPrefix("No XP this round: those words"))
        XCTAssertEqual(clozeResultLines(summary, correct: 0, xp: .saved(0)).xp, "No XP this round.")
        XCTAssertEqual(clozeResultLines(summary, correct: 2, xp: .saving).xp, "Saving your XP\u{2026}")
        XCTAssertEqual(clozeResultLines(summary, correct: 2, xp: .failed).xp, "Couldn't save this round's XP.")
    }
}

final class RemixClozeTagsTests: XCTestCase {
    private func card(_ tag: String, due: Date?) -> CardState {
        return CardState(lexemeTag: tag, stability: 1, difficulty: 5, dueAt: due, reviewCount: 1, lapseCount: 0)
    }

    func testDueWordsComeBeforeNewOnesAndNotYetDueOnesAreLeftOut() {
        let now = Date(timeIntervalSince1970: 1_000)
        let cards = [
            "a": card("a", due: Date(timeIntervalSince1970: 2_000)),
            "b": card("b", due: Date(timeIntervalSince1970: 500)),
            "c": card("c", due: nil),
        ]
        XCTAssertEqual(remixClozeTags(["a", "n1", "b", "c", "n2", "b"], cards: cards, now: now), ["b", "c", "n1", "n2"])
    }
}
