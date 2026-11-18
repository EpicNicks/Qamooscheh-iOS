import XCTest
import QModel
@testable import QFeatures

final class VocabTermsTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    private func card(stability: Double, due: TimeInterval?) -> CardState {
        CardState(
            lexemeTag: "x", stability: stability, difficulty: 5, lastReviewedAt: nil,
            dueAt: due.map { Date(timeIntervalSince1970: $0) }, reviewCount: 1, lapseCount: 0)
    }

    func testNoCardIsNew() {
        XCTAssertEqual(vocabStrength(nil, now: now), .new)
    }

    func testLevelFollowsStabilityAndClamps() {
        XCTAssertEqual(vocabStrength(card(stability: 0, due: nil), now: now), .practiced(level: 1, due: false))
        XCTAssertEqual(vocabStrength(card(stability: 8, due: nil), now: now), .practiced(level: 2, due: false))
        XCTAssertEqual(vocabStrength(card(stability: 30, due: nil), now: now), .practiced(level: 4, due: false))
        XCTAssertEqual(vocabStrength(card(stability: 900, due: nil), now: now), .practiced(level: 4, due: false))
    }

    func testDueWhenReviewDatePassed() {
        XCTAssertEqual(vocabStrength(card(stability: 1, due: 999_999), now: now), .practiced(level: 1, due: true))
        XCTAssertEqual(vocabStrength(card(stability: 1, due: 1_000_000), now: now), .practiced(level: 1, due: true))
        XCTAssertEqual(vocabStrength(card(stability: 1, due: 1_000_001), now: now), .practiced(level: 1, due: false))
    }

    func testTermsSkipUnglossedTagsAndKeepOrder() {
        let lexemes = [
            "b": LexemeIndexEntry(gloss: "bee", romanizationIsAuthored: false),
            "a<n>": LexemeIndexEntry(gloss: "ay", romanization: "ei", romanizationIsAuthored: true),
        ]
        let terms = vocabTerms(tags: ["a<n>", "missing", "b"], lexemes: lexemes, cards: [:], starred: ["b"], now: now)
        XCTAssertEqual(terms.map { $0.tag }, ["a<n>", "b"])
        XCTAssertEqual(terms[0].surface, "a")
        XCTAssertFalse(terms[0].starred)
        XCTAssertTrue(terms[1].starred)
    }

    func testVerbFormOffersItsInfinitiveAndTheInfinitiveIsABaseVerb() {
        let lexemes = [
            "kharidam<v>": LexemeIndexEntry(gloss: "I bought", pos: "verb", verbForm: "conjugated", lemma: "kharidan", romanizationIsAuthored: false),
            "kharidan<v>": LexemeIndexEntry(gloss: "to buy", register: .standard, pos: "verb", verbForm: "infinitive", lemma: "kharidan", romanizationIsAuthored: false),
            "raftam<v>": LexemeIndexEntry(gloss: "I went", pos: "verb", verbForm: "conjugated", lemma: "raftan", romanizationIsAuthored: false),
            "ketab<n>": LexemeIndexEntry(gloss: "book", pos: "noun", romanizationIsAuthored: false),
        ]
        let terms = vocabTerms(
            tags: ["kharidam<v>", "kharidan<v>", "raftam<v>", "ketab<n>"], lexemes: lexemes, cards: [:], starred: ["kharidan<v>"], now: now)
        XCTAssertEqual(terms[0].baseVerb, BaseVerbTerm(tag: "kharidan<v>", surface: "kharidan", gloss: "to buy", starred: true))
        XCTAssertFalse(terms[0].isBaseVerb)
        // The infinitive is the verb itself: highlighted when saved, with nothing further to offer.
        XCTAssertNil(terms[1].baseVerb)
        XCTAssertTrue(terms[1].isBaseVerb)
        // No infinitive entry for the lemma, and not a verb at all.
        XCTAssertNil(terms[2].baseVerb)
        XCTAssertNil(terms[3].baseVerb)
        XCTAssertFalse(terms[3].isBaseVerb)
    }

    func testFoldIgnoresCaseAccentsAndArabicLetters() {
        XCTAssertEqual(foldForSearch("  Caf\u{00E9}   AU  Lait "), "cafe au lait")
        XCTAssertEqual(foldForSearch("\u{0643}\u{062A}\u{0627}\u{0628}"), foldForSearch("\u{06A9}\u{062A}\u{0627}\u{0628}"))
        XCTAssertEqual(foldForSearch("\u{064A}\u{0627}"), foldForSearch("\u{06CC}\u{0627}"))
    }

    func testFoldKeepsJapaneseDakuten() {
        XCTAssertNotEqual(foldForSearch("\u{304B}"), foldForSearch("\u{304C}"))
        XCTAssertEqual(foldForSearch("\u{304C}"), "\u{304C}")
    }

    func testFilterMatchesSurfaceGlossOrRomanization() {
        let terms = [
            VocabTerm(tag: "1", surface: "salam", gloss: "hello", romanization: nil, starred: false, strength: .new),
            VocabTerm(tag: "2", surface: "nan", gloss: "Bread", romanization: "naan", starred: false, strength: .new),
        ]
        XCTAssertEqual(filterVocabTerms(terms, query: "  ").count, 2)
        XCTAssertEqual(filterVocabTerms(terms, query: "BREAD").map { $0.tag }, ["2"])
        XCTAssertEqual(filterVocabTerms(terms, query: "naa").map { $0.tag }, ["2"])
        XCTAssertEqual(filterVocabTerms(terms, query: "zzz").count, 0)
    }

    // vocab-search-verbs: a search also lists every course infinitive it matches.
    private let kharidan = "\u{062E}\u{0631}\u{06CC}\u{062F}\u{0646}<v>"
    private let kharidam = "\u{062E}\u{0631}\u{06CC}\u{062F}\u{0645}<v>"
    private let keshidan = "\u{06A9}\u{0634}\u{06CC}\u{062F}\u{0646}<v>"
    private let kharidanLemma = "\u{062E}\u{0631}\u{06CC}\u{062F}\u{0646}"

    private var verbLexemes: [String: LexemeIndexEntry] {
        [
            kharidan: LexemeIndexEntry(
                gloss: "to buy", pos: "verb", verbForm: "infinitive", lemma: kharidanLemma,
                romanization: "khar\u{012B}dan", romanizationIsAuthored: true),
            kharidam: LexemeIndexEntry(
                gloss: "I bought", pos: "verb", verbForm: "conjugated", lemma: kharidanLemma,
                romanization: "khar\u{012B}dam", romanizationIsAuthored: true),
            keshidan: LexemeIndexEntry(
                gloss: "to pull", pos: "verb", verbForm: "infinitive", lemma: "\u{06A9}\u{0634}\u{06CC}\u{062F}\u{0646}",
                romanization: "kesh\u{012B}dan", romanizationIsAuthored: true),
            "ketab<n>": LexemeIndexEntry(gloss: "book", pos: "noun", romanization: "ket\u{0101}b", romanizationIsAuthored: true),
        ]
    }

    /// verbs.json has only kharidan.
    private var verbIndex: [String: VerbIndexEntry] {
        [kharidanLemma: VerbIndexEntry(
            infinitive: kharidanLemma, presentStem: "\u{062E}\u{0631}",
            pastStem: "\u{062E}\u{0631}\u{06CC}\u{062F}", principalParts: [], table: [:], gloss: "to buy")]
    }

    private func search(taughtTags: [String], _ query: String) -> [VocabTerm] {
        let taught = vocabTerms(tags: taughtTags, lexemes: verbLexemes, cards: [:], starred: [], now: now, verbs: verbIndex)
        return searchVocabTerms(
            taught: taught, query: query, lexemes: verbLexemes, verbs: verbIndex, cards: [:], starred: [], now: now)
    }

    func testBlankSearchReturnsTaughtTermsUnchanged() {
        let taught = vocabTerms(tags: ["ketab<n>", kharidam], lexemes: verbLexemes, cards: [:], starred: [], now: now, verbs: verbIndex)
        XCTAssertEqual(search(taughtTags: ["ketab<n>", kharidam], ""), taught)
        XCTAssertEqual(search(taughtTags: ["ketab<n>", kharidam], "   "), taught)
    }

    func testGlossMatchAddsTheInfinitive() {
        XCTAssertEqual(search(taughtTags: ["ketab<n>"], "PULL").map { $0.tag }, [keshidan])
    }

    func testRomanizationMatchAddsOnlyInfinitivesAfterTaughtMatches() {
        // "kharid" matches both kharidam (a conjugated form, not added) and kharidan (added).
        XCTAssertEqual(search(taughtTags: ["ketab<n>"], "kharid").map { $0.tag }, [kharidan])
        // A taught match comes first; the infinitive follows it.
        XCTAssertEqual(search(taughtTags: ["ketab<n>", kharidam], "kharid").map { $0.tag }, [kharidam, kharidan])
    }

    func testWrittenFormMatchFoldsArabicLettersAndDiacritics() {
        // Arabic-keyboard kaf and yeh, with a fatha, find keshidan's written form.
        let query = "\u{0643}\u{064E}\u{0634}\u{064A}\u{062F}"
        XCTAssertEqual(search(taughtTags: [], query).map { $0.tag }, [keshidan])
    }

    func testInfinitiveAlreadyTaughtIsNotListedTwice() {
        XCTAssertEqual(search(taughtTags: [kharidan, "ketab<n>"], "buy").map { $0.tag }, [kharidan])
    }

    func testSearchAppendsInfinitivesInTagOrder() {
        XCTAssertEqual(search(taughtTags: [], "dan").map { $0.tag }, [kharidan, keshidan].sorted())
    }

    func testVerbKeyOnlyWhenVerbsJsonHasTheVerb() {
        let terms = vocabTerms(
            tags: [kharidan, kharidam, keshidan, "ketab<n>"], lexemes: verbLexemes, cards: [:], starred: [], now: now, verbs: verbIndex)
        XCTAssertEqual(terms[0].verbKey, kharidanLemma)
        // A conjugated form has no verbKey of its own; its base-verb row carries the infinitive's.
        XCTAssertNil(terms[1].verbKey)
        XCTAssertEqual(terms[1].baseVerb?.verbKey, kharidanLemma)
        // verbs.json lacks this lemma.
        XCTAssertNil(terms[2].verbKey)
        XCTAssertNil(terms[3].verbKey)
        // No verbs.json at all.
        let bare = vocabTerms(tags: [kharidan, kharidam], lexemes: verbLexemes, cards: [:], starred: [], now: now)
        XCTAssertNil(bare[0].verbKey)
        XCTAssertNotNil(bare[1].baseVerb)
        XCTAssertNil(bare[1].baseVerb?.verbKey)
        // An added infinitive carries its verbKey too.
        XCTAssertEqual(search(taughtTags: [], "buy").first?.verbKey, kharidanLemma)
    }

    func testScopeLabelShortensLongTitles() {
        XCTAssertEqual(scopeLabel("Short"), "Short")
        XCTAssertEqual(scopeLabel("A very long lesson title indeed"), "A very long lesso\u{2026}")
        XCTAssertEqual(scopeLabel("Exactly eighteen!!"), "Exactly eighteen!!")
    }
}
