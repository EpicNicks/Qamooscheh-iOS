import XCTest
import QModel
@testable import QDomain

/// Port of web flashcards.test.ts.
final class FlashcardsTests: XCTestCase {
    func testNormalizingIgnoresCasePunctuationArticlesAndLeadingTo() {
        XCTAssertEqual(normalizeMeaning("  To the Bazaar! "), "bazaar")
        XCTAssertEqual(normalizeMeaning("I'm tired."), "im tired")
    }

    func testGlossSplitsIntoAlternativesWithoutAsides() {
        let answers = glossAnswers("after / later / next (\u{0628}\u{0639}\u{062F} \u{0627}\u{0632} = after)")
        for expected in ["after", "later", "next"] { XCTAssertTrue(answers.contains(expected), expected) }
        XCTAssertEqual(glossAnswers("uncle (father's brother)"), ["uncle"])
    }

    func testSlashBetweenSingleWordsExpandsInPlace() {
        let a = glossAnswers("he / she cooks")
        XCTAssertTrue(a.contains("he cooks"))
        XCTAssertTrue(a.contains("she cooks"))
        let b = glossAnswers("he/she has")
        XCTAssertTrue(b.contains("he has"))
        XCTAssertTrue(b.contains("she has"))
    }

    func testQuotesSomeGlossesAreWrittenInAreStripped() {
        XCTAssertEqual(glossAnswers("'I give (written: \u{0645}\u{06CC}\u{200C}\u{062F}\u{0647}\u{0645})'"), ["i give"])
    }

    func testAnyOfAGlossMeaningsIsAcceptedLoosely() {
        XCTAssertTrue(gradeTranslation("Thank you!", gloss: "thank you"))
        XCTAssertTrue(gradeTranslation("drink", gloss: "to eat / to drink"))
        XCTAssertTrue(gradeTranslation("she cooks", gloss: "he/she cooks"))
        XCTAssertTrue(gradeTranslation("you cook", gloss: "you (plural) cook"))
    }

    func testOneTypoForgivenInLongerAnswerNotShortOne() {
        XCTAssertTrue(gradeTranslation("goodbey", gloss: "goodbye"))
        XCTAssertFalse(gradeTranslation("tee", gloss: "tea"))
    }

    func testWrongOrEmptyAnswerIsRejected() {
        XCTAssertFalse(gradeTranslation("water", gloss: "bread"))
        XCTAssertFalse(gradeTranslation("  ", gloss: "bread"))
    }

    func testCardsKeepSavedTagsInOrderWithoutAttachedEndings() {
        let entry = LexemeIndexEntry(gloss: "x", romanizationIsAuthored: false)
        let tea = "\u{0686}\u{0627}\u{06CC}<n>"
        let water = "\u{0622}\u{0628}<n>"
        let my = "\u{0640}\u{0645}<poss>"
        let index = [tea: entry, my: entry, water: entry]
        let words = flashcardWords(savedTags: [water, my, "dog<n>", tea], lexemeIndex: index)
        XCTAssertEqual(words.map { $0.surface }, ["\u{0622}\u{0628}", "\u{0686}\u{0627}\u{06CC}"])
    }

    func testNoLexemeIndexGivesNoCards() {
        XCTAssertEqual(flashcardWords(savedTags: ["a<n>"], lexemeIndex: nil), [])
        XCTAssertEqual(flashcardXP, 5)
    }
}
