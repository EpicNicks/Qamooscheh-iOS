import XCTest
import QModel
@testable import QDomain

// Port of web attachedEndings.test.ts (attached endings, ezafe marks, reading
// aids, romanizeSentence), plus tidyGloss.
final class AttachedEndingsTests: XCTestCase {
    private let fatha = "\u{064E}"

    private func lex(_ tag: String, _ gloss: String, _ romanization: String, register: Register? = nil, forms: [String]? = nil) -> (tag: String, entry: LexemeIndexEntry) {
        return (tag, LexemeIndexEntry(gloss: gloss, register: register, romanization: romanization, romanizationIsAuthored: true, forms: forms))
    }

    // Entries as content/fa/lexemes.yaml writes them (in that order), plus the
    // `forms` an ending's after-a-vowel spelling is published under.
    private lazy var hintMap: [String: WordHint] = buildLexemeHintMap([
        lex("من<pron>", "I / me", "man"),
        lex("مادر<n>", "mother", "mādar"),
        lex("کتاب<n>", "book", "ketāb"),
        lex("خانه<n>", "home", "khāne"),
        lex("هوا<n>", "weather / air", "havā"),
        lex("چای<n>", "tea", "chāy"),
        lex("خوب<adj>", "good", "khūb"),
        lex("خسته<adj>", "tired", "khaste"),
        lex("سر<n>", "head", "sar"),
        lex("سر<prep>", "at (a meal / table): سر سفره = at the sofreh", "sar-e"),
        lex("پا<n>", "leg / foot", "pā"),
        lex("سال<n>", "year", "sāl"),
        lex("نو<adj>", "new", "no"),
        lex("عمو<n>", "uncle (father's brother)", "amū"),
        lex("ـم<v><spoken>", "am (attached to a predicate)", "-am", register: .spoken, forms: ["ـام"]),
        lex("ـم<poss>", "my (attached to a noun: سرم = my head)", "-am", forms: ["ـام"]),
        lex("ـش<poss>", "his / her (attached to a noun: کیفش = his/her bag)", "-esh"),
        lex("ـش<obj>", "him / her / it, attached to a verb (دیدمش = I saw him / her)", "-esh"),
        lex("ـه<v><spoken>", "is (attached to a predicate)", "-e", register: .spoken),
        lex("ـها<pl>", "plural ending (کتاب‌ها = books)", "-hā"),
        lex("ـی<v><spoken>", "are (you; attached to a predicate)", "-ī", register: .spoken, forms: ["ـای"]),
        lex("ـی<rel>", "(attached before که: دوستی که = the friend who)", "-ī"),
        lex("ـی<indef>", "a / an / one (attached to a noun: کتابی = a book)", "-ī"),
    ])

    private func hintFor(_ word: String, _ tags: [String] = []) -> WordHint? {
        return segmentAnnotatedText(word, hintMap, tags: tags).first?.hint
    }

    // attached endings

    func testGivesAnEndingItsGeneralMeaningEverySenseNotAGuessAtOne() {
        XCTAssertEqual(hintFor("مادرم")?.translation, "mother + -am (am / my)")
        XCTAssertEqual(hintFor("مادرم")?.romanization, "mādaram")
        XCTAssertEqual(hintFor("خوبم")?.translation, "good + -am (am / my)")
    }

    func testFindsAnEndingsAfterAVowelSpellingBehindAHalfSpace() {
        XCTAssertEqual(hintFor("خسته\(ZWNJ)ام")?.translation, "tired + -am (am / my)")
    }

    func testSaysAMeaningTwoSensesShareOnce() {
        // ـش: "his / her" (possessive) and "him / her / it" (object).
        XCTAssertEqual(hintFor("سالش")?.translation, "year + -esh (his / her / him / it)")
    }

    func testStacksEndingsLongestOneNearestTheStem() {
        XCTAssertEqual(hintFor("سالشه")?.translation, "year + -esh (his / her / him / it) + -e (is)")
        XCTAssertEqual(hintFor("کتاب\(ZWNJ)هام")?.translation, "book + -hā (plural ending) + -am (am / my)")
    }

    func testDropsASenseWhoseGlossIsOnlyAnAuthoringNote() {
        // ـی's relative sense contributes nothing; its others do.
        XCTAssertEqual(hintFor("کتابی")?.translation, "book + -ī (are (you) / a / an / one)")
    }

    func testLeavesAWordAloneWhenItsStemWouldBeTooShortToTrust() {
        XCTAssertNil(hintFor("نون"))
    }

    func testSplitsAShortStemThatEndsInAConsonant() {
        XCTAssertEqual(hintFor("سرم")?.translation, "head + -am (am / my)")
        XCTAssertEqual(hintFor("سرم")?.romanization, "saram")
    }

    func testDoesntReadAYehWrittenOntoAVowelAsAnEndingThatsTheEzafe() {
        XCTAssertNil(hintFor("عموی"))
    }

    func testPrefersAWordsOwnEntryOverASplit() {
        XCTAssertEqual(hintFor("مادر")?.translation, "mother")
    }

    // attached endings the exercise's tags spell out

    func testNamesJustTheTaggedSenses() {
        let head = hintFor("سرم", ["سر<n>", "ـم<poss>"])
        XCTAssertEqual(head?.translation, "head + -am (my)")
        XCTAssertEqual(head?.romanization, "saram")
        XCTAssertEqual(hintFor("خسته\(ZWNJ)ام", ["خسته<adj>", "ـم<v><spoken>"])?.translation, "tired + -am (am)")
    }

    func testTrustsAShortVowelFinalStemTheTagsName() {
        XCTAssertNil(hintFor("پام"))
        let foot = hintFor("پام", ["پا<n>", "ـم<poss>"])
        XCTAssertEqual(foot?.translation, "leg / foot + -am (my)")
        XCTAssertEqual(foot?.romanization, "pām")
    }

    func testFallsBackToAnySplitForAWordTheTagsDontCover() {
        XCTAssertEqual(hintFor("خوبم", ["سر<n>", "ـم<poss>"])?.translation, "good + -am (am / my)")
    }

    // ezafe marks

    func testReadsAKasraOnAConsonantAsMinusE() {
        let hint = hintFor("کتاب\(KASRA)")
        XCTAssertEqual(hint?.translation, "book")
        XCTAssertEqual(hint?.romanization, "ketāb")
        XCTAssertEqual(hint?.ezafe, .e)
    }

    func testReadsAKasraOnTheLinkingYehAfterAVowelAsMinusYe() {
        let hint = hintFor("هوای\(KASRA)")
        XCTAssertEqual(hint?.translation, "weather / air")
        XCTAssertEqual(hint?.ezafe, .ye)
    }

    func testReadsAKasraOnAWordsOwnFinalYehAsMinusE() {
        let hint = hintFor("چای\(KASRA)")
        XCTAssertEqual(hint?.translation, "tea")
        XCTAssertEqual(hint?.ezafe, .e)
    }

    func testReadsAHamzaAboveASilentHehAsMinusYe() {
        let hint = hintFor("خانه\(HAMZA_ABOVE)")
        XCTAssertEqual(hint?.translation, "home")
        XCTAssertEqual(hint?.ezafe, .ye)
    }

    func testCarriesAnEzafeOnAWordWithEndings() {
        let hint = hintFor("مادرم\(KASRA)")
        XCTAssertEqual(hint?.translation, "mother + -am (am / my)")
        XCTAssertEqual(hint?.ezafe, .e)
    }

    func testLooksAVowelMarkedWordUpWithoutItsMarks() {
        XCTAssertEqual(hintFor("م\(fatha)ن")?.translation, "I / me")
        let book = hintFor("ک\(KASRA)تاب\(KASRA)")
        XCTAssertEqual(book?.translation, "book")
        XCTAssertEqual(book?.ezafe, .e)
    }

    // reading aids

    func testStripsVowelAndEzafeMarksAndNothingElse() {
        XCTAssertEqual(PersianNormalize.stripReadingAids("ک\(KASRA)تاب\(KASRA) م\(fatha)ن"), "کتاب من")
        XCTAssertEqual(PersianNormalize.stripReadingAids("خانه\(HAMZA_ABOVE)"), "خانه")
        XCTAssertEqual(PersianNormalize.stripReadingAids("لطفاً"), "لطفاً") // tanvin is spelling
    }

    func testGradesAMarkedAnswerTheSameAsTheUnmarkedOne() {
        XCTAssertEqual(
            PersianNormalize.normalizeStrict("ک\(KASRA)تاب\(KASRA) م\(fatha)ن"),
            PersianNormalize.normalizeStrict("کتاب من")
        )
    }

    // romanizeSentence

    func testRomanizesWordByWordEzafeIncluded() {
        XCTAssertEqual(romanizeSentence("کتاب\(KASRA) من", hintMap), "ketāb-e man")
        XCTAssertEqual(romanizeSentence("هوای\(KASRA) خوب؟", hintMap), "havā-ye khūb?")
    }

    func testRomanizeSentenceIsNilWhenNoWordIsKnown() {
        XCTAssertNil(romanizeSentence("سلام", hintMap))
    }

    func testRomanizeSentenceLeavesAnUnknownWordInNativeScript() {
        XCTAssertEqual(romanizeSentence("من سلام", hintMap), "man سلام")
    }

    // tidyGloss

    func testTidyGlossTrimsAuthoringNotesButKeepsWhatTellsSensesApart() {
        XCTAssertEqual(tidyGloss("are (you; attached to a predicate)"), "are (you)")
        XCTAssertEqual(tidyGloss("my (attached to a noun: سرم = my head)"), "my")
        XCTAssertEqual(tidyGloss("uncle (father's brother)"), "uncle (father's brother)")
        XCTAssertEqual(tidyGloss("him / her / it, attached to a verb (دیدمش = I saw him / her)"), "him / her / it")
        XCTAssertEqual(tidyGloss("(attached before که: دوستی که = the friend who)"), "")
    }
}
