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

    func testScopeLabelShortensLongTitles() {
        XCTAssertEqual(scopeLabel("Short"), "Short")
        XCTAssertEqual(scopeLabel("A very long lesson title indeed"), "A very long lesso\u{2026}")
        XCTAssertEqual(scopeLabel("Exactly eighteen!!"), "Exactly eighteen!!")
    }
}
