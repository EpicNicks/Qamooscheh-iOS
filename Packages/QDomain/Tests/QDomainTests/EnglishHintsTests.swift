import XCTest
import QModel
@testable import QDomain

// Port of web englishHints.test.ts.
final class EnglishHintsTests: XCTestCase {
    private func entry(_ gloss: String, _ romanization: String, register: Register? = nil) -> LexemeIndexEntry {
        return LexemeIndexEntry(gloss: gloss, register: register, romanization: romanization, romanizationIsAuthored: true)
    }

    private lazy var hintMap: [String: WordHint] = buildLexemeHintMap([
        ("مادر<n>", entry("mother", "mādar")),
        ("خسته<adj>", entry("tired", "khaste")),
        ("است<v>", entry("is", "ast")),
        ("ـم<v><spoken>", entry("am (attached to a predicate)", "-am", register: .spoken)),
        ("ـم<poss>", entry("my (attached to a noun: سرم = my head)", "-am")),
        ("ممنون<interj><spoken>", entry("thank you", "mamnūn", register: .spoken)),
        ("تو<pron>", entry("you", "to")),
        ("داشتن<v>", entry("to have", "dāshtan")),
        ("کتاب<n>", entry("book", "ketāb")),
        ("مامان<n>", entry("mom (everyday word: what you call your mother)", "māmān")),
        ("می‌خواد<v><spoken>", entry("he/she wants", "mīkhād", register: .spoken)),
        ("اومد<v><spoken>", entry("he / she came", "ūmad", register: .spoken)),
        ("یک<num>", entry("one", "yek")),
        ("من<pron>", entry("I", "man")),
        ("ـتر<comp>", entry("-er / more (comparative)", "-tar")),
        ("می‌خرم<v><spoken>", entry("I buy", "mīkharam", register: .spoken)),
        ("می‌خره<v><spoken>", entry("he / she buys", "mīkhare", register: .spoken)),
        ("خریدن<v><spoken>", entry("to buy", "kharīdan", register: .spoken)),
        ("کیف<n>", entry("bag", "kīf")),
        ("برای<prep>", entry("for", "barāye")),
    ])

    private func hintedIn(_ map: [String: WordHint], _ text: String, _ tags: [String]) -> [String] {
        return segmentEnglish(text, englishCandidates(tags, map)).compactMap { s in
            s.hint.map { "\(s.text)=\($0.native)" }
        }
    }

    private func hinted(_ text: String, _ tags: [String]) -> [String] {
        return hintedIn(hintMap, text, tags)
    }

    func testMatchesOnlyThisExercisesOwnLexemes() {
        XCTAssertEqual(
            hinted("My mother is tired.", ["مادر<n>", "خسته<adj>", "است<v>", "ـم<poss>"]),
            ["My=ـم", "mother=مادر", "is=است", "tired=خسته"]
        )
        // "you" is a lexeme, but not one this exercise drills.
        XCTAssertEqual(hinted("Are you tired?", ["خسته<adj>"]), ["tired=خسته"])
    }

    func testUsesTheTagsOwnSenseOfASharedSurface() {
        XCTAssertEqual(hinted("I am tired", ["خسته<adj>", "ـم<v><spoken>"]), ["am=ـم", "tired=خسته"])
    }

    func testPrefersTheLongestPhrase() {
        XCTAssertEqual(hinted("Thank you!", ["ممنون<interj><spoken>", "تو<pron>"]), ["Thank you=ممنون"])
    }

    func testMatchesPluralsAVerbWithoutItsToAndAGlossWithoutItsNote() {
        XCTAssertEqual(hinted("Books", ["کتاب<n>"]), ["Books=کتاب"])
        XCTAssertEqual(hinted("We have tea", ["داشتن<v>"]), ["have=داشتن"])
        XCTAssertEqual(hinted("Where is mom?", ["مامان<n>"]), ["mom=مامان"])
    }

    func testReadsAPresentTenseVerbGlossAsTheProgressiveToo() {
        let tags = ["من<pron>", "برای<prep>", "مادر<n>", "ـم<poss>", "یک<num>", "کیف<n>", "می‌خرم<v><spoken>"]
        XCTAssertEqual(
            hinted("I am buying a bag for my mother", tags),
            ["I am buying=می‌خرم", "a=یک", "bag=کیف", "for=برای", "my=ـم", "mother=مادر"]
        )
        XCTAssertEqual(hinted("I'm buying a bag", ["می‌خرم<v><spoken>", "کیف<n>"]), ["I'm buying=می‌خرم", "bag=کیف"])
        XCTAssertEqual(hinted("She is buying a bag", ["می‌خره<v><spoken>", "کیف<n>"]), ["She is buying=می‌خره", "bag=کیف"])
        XCTAssertEqual(hinted("I buy a bag", ["می‌خرم<v><spoken>", "کیف<n>"]), ["I buy=می‌خرم", "bag=کیف"])
    }

    func testPrefersAWordAsWrittenOverOneDerivedFromIt() {
        let map = buildLexemeHintMap([
            ("حتی<adv>", entry("even", "hattā")),
            ("عصر<n>", entry("evening", "asr")),
            ("ساختن<v>", entry("to build", "sākhtan")),
            ("ساختمان<n>", entry("building", "sākhtemān")),
        ])
        XCTAssertEqual(hintedIn(map, "Even in the evening", ["حتی<adv>", "عصر<n>"]), ["Even=حتی", "evening=عصر"])
        XCTAssertEqual(
            hintedIn(map, "They are building a building", ["ساختن<v>", "ساختمان<n>"]),
            ["are building=ساختن", "building=ساختمان"]
        )
    }

    func testReadsBePlusVerbAsTheProgressiveOnlyWhenTheVerbSaysIng() {
        let map = buildLexemeHintMap([
            ("در<n>", entry("door", "dar")),
            ("باز کردن<v>", entry("to open", "bāz kardan")),
            ("است<v>", entry("is", "ast")),
            ("باز<adj>", entry("open", "bāz")),
        ])
        let tags = ["در<n>", "باز کردن<v>", "است<v>", "باز<adj>"]
        // "is" stays the copula; which "open" the word itself gets is the tags' order, not this rule's.
        XCTAssertEqual(Array(hintedIn(map, "The door is open", tags).prefix(2)), ["door=در", "is=است"])
        XCTAssertEqual(hintedIn(map, "He is opening the door", tags), ["is opening=باز کردن", "door=در"])
    }

    func testTakesAnIngWordBackToItsVerb() {
        XCTAssertEqual(hinted("Buying books", ["خریدن<v><spoken>", "کتاب<n>"]), ["Buying=خریدن", "books=کتاب"])
        XCTAssertEqual(hinted("We are having tea", ["داشتن<v>"]), ["are having=داشتن"])
    }

    func testSkipsSuffixOnlyAlternativesButKeepsTheRest() {
        XCTAssertEqual(hinted("more expensive", ["ـتر<comp>"]), ["more=ـتر"])
    }

    func testExpandsSlashedGlossesWithoutMatchingHalfOfOne() {
        XCTAssertEqual(hinted("She wants tea", ["می‌خواد<v><spoken>"]), ["She wants=می‌خواد"])
        XCTAssertEqual(hinted("He wants tea", ["می‌خواد<v><spoken>"]), ["He wants=می‌خواد"])
        XCTAssertEqual(hinted("He came", ["اومد<v><spoken>"]), ["He came=اومد"])
    }

    func testReadsEitherHalfOfAContractionAndYekAsTheArticle() {
        XCTAssertEqual(hinted("I'm tired", ["من<pron>", "خسته<adj>"]), ["I'm=من", "tired=خسته"])
        XCTAssertEqual(hinted("It's tired", ["است<v>"]), ["It's=است"])
        XCTAssertEqual(hinted("a book", ["یک<num>", "کتاب<n>"]), ["a=یک", "book=کتاب"])
        // برادرِ من: the pronoun after an ezafe is the English possessive.
        XCTAssertEqual(hinted("My mother", ["مادر<n>", "من<pron>"]), ["My=من", "mother=مادر"])
    }

    func testCarriesTheRomanization() {
        let segment = segmentEnglish("mother", englishCandidates(["مادر<n>"], hintMap))[0]
        XCTAssertEqual(segment.hint, NativeHint(native: "مادر", romanization: "mādar"))
    }

    func testTellsEnglishPromptsFromNativeOnes() {
        XCTAssertTrue(isLatinText("My mother is tired."))
        XCTAssertTrue(isLatinText("ketāb-e man"))
        XCTAssertFalse(isLatinText("مادرم خسته است"))
        XCTAssertFalse(isLatinText("123"))
    }
}
