import XCTest
import QModel
@testable import QDomain

final class BaseVerbTests: XCTestCase {
    private func verb(_ form: String, lemma: String?) -> LexemeIndexEntry {
        return LexemeIndexEntry(gloss: form, pos: "verb", verbForm: form, lemma: lemma, romanizationIsAuthored: false)
    }

    private lazy var lexemes: [String: LexemeIndexEntry] = [
        "kharidam<v>": verb("conjugated", lemma: "kharidan"),
        "kharidan<v>": verb("infinitive", lemma: "kharidan"),
        "bayad<v>": verb("modal", lemma: "bayestan"),
        "bayestan<v>": verb("infinitive", lemma: "bayestan"),
        "raftam<v>": verb("conjugated", lemma: "raftan"),
        "hastam<v>": verb("copula", lemma: nil),
        "kharid<n>": LexemeIndexEntry(gloss: "purchase", pos: "noun", lemma: "kharidan", romanizationIsAuthored: false),
    ]

    func testAnyVerbFormWithALemmaFindsItsInfinitive() {
        let index = baseVerbIndex(lexemes)
        XCTAssertEqual(baseVerbTag(of: "kharidam<v>", lexemes: lexemes, index: index), "kharidan<v>")
        XCTAssertEqual(baseVerbTag(of: "bayad<v>", lexemes: lexemes, index: index), "bayestan<v>")
    }

    func testNothingToOfferForTheInfinitiveItselfOrWithoutOne() {
        let index = baseVerbIndex(lexemes)
        XCTAssertNil(baseVerbTag(of: "kharidan<v>", lexemes: lexemes, index: index))
        XCTAssertNil(baseVerbTag(of: "raftam<v>", lexemes: lexemes, index: index))
        XCTAssertNil(baseVerbTag(of: "hastam<v>", lexemes: lexemes, index: index))
        XCTAssertNil(baseVerbTag(of: "kharid<n>", lexemes: lexemes, index: index))
        XCTAssertNil(baseVerbTag(of: "missing", lexemes: lexemes, index: index))
    }

    func testTwoInfinitivesForOneLemmaKeepTheFirstByTag() {
        var both = lexemes
        both["kharidan<v><spoken>"] = verb("infinitive", lemma: "kharidan")
        XCTAssertEqual(baseVerbIndex(both)["kharidan"], "kharidan<v>")
    }

    func testOnlyAnInfinitiveVerbIsABaseVerb() {
        XCTAssertTrue(isBaseVerb(lexemes["kharidan<v>"]))
        XCTAssertFalse(isBaseVerb(lexemes["kharidam<v>"]))
        XCTAssertFalse(isBaseVerb(lexemes["kharid<n>"]))
        XCTAssertFalse(isBaseVerb(nil))
    }
}
