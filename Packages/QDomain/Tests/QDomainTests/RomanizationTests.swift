import XCTest
import QModel
@testable import QDomain

// Port of web romanization.test.ts (verbLemma), plus the hint map, register
// labels and gating, which have no web suite of their own (Android WordHintsTest).
final class RomanizationTests: XCTestCase {
    private func entry(
        _ gloss: String,
        register: Register? = nil,
        pos: String? = nil,
        verbForm: String? = nil,
        lemma: String? = nil,
        romanization: String? = nil,
        authored: Bool = false,
        forms: [String]? = nil
    ) -> LexemeIndexEntry {
        return LexemeIndexEntry(
            gloss: gloss, register: register, pos: pos, verbForm: verbForm, lemma: lemma,
            romanization: romanization, romanizationIsAuthored: authored, forms: forms
        )
    }

    // buildLexemeHintMap verbLemma

    func testCarriesAVerbLexemesLemmaAndNothingElses() {
        let map = buildLexemeHintMap([
            ("خریدم<v>", entry("I bought", pos: "verb", verbForm: "conjugated", lemma: "خریدن")),
            ("کتاب<n>", entry("book", pos: "noun", lemma: "کتاب")),
            ("سلام<interj>", entry("hello")),
        ])
        XCTAssertEqual(map["خریدم"]?.verbLemma, "خریدن")
        XCTAssertNil(map["کتاب"]?.verbLemma)
        XCTAssertNil(map["سلام"]?.verbLemma)
    }

    func testKeepsAVerbsLemmaWhenAHomographNounSharesTheSurface() {
        let map = buildLexemeHintMap([
            ("خرید<n>", entry("purchase", pos: "noun")),
            ("خرید<v>", entry("bought", pos: "verb", verbForm: "conjugated", lemma: "خریدن")),
        ])
        XCTAssertEqual(map["خرید"]?.verbLemma, "خریدن")
    }

    // buildLexemeHintMap

    func testMergesHomographsKeepingTheFirstRomanizationAndLabellingMixedRegistersBoth() {
        let map = buildLexemeHintMap([
            ("خانه<n><spoken>", entry("house", register: .spoken)),
            ("خانه<n><written>", entry("home", register: .written, romanization: "khāne", authored: true)),
        ])
        let hint = map["خانه"]
        XCTAssertEqual(hint?.translation, "house")
        XCTAssertEqual(hint?.romanization, "khāne")
        XCTAssertEqual(hint?.ruby, "khāne")
        XCTAssertEqual(hint?.register, .both)
        XCTAssertEqual(hint?.senses?.map { $0.pos }, ["<n><spoken>", "<n><written>"])
    }

    func testListsAnEntryUnderEachOfItsFormsAndSkipsATagWithNoSurface() {
        let map = buildLexemeHintMap([
            ("ـم<poss>", entry("my", romanization: "-am", authored: true, forms: ["ـام"])),
            ("<n>", entry("nothing")),
        ])
        XCTAssertEqual(Set(map.keys), ["ـم", "ـام"])
        XCTAssertEqual(map["ـام"]?.senses?.count, 1)
        XCTAssertEqual(map["ـام"]?.senses?.first?.tag, "ـم<poss>")
        XCTAssertEqual(buildLexemeHintMap(nil), [:])
    }

    func testKeepsASingleEntrysRegisterAsIs() {
        let map = buildLexemeHintMap([("سلام<interj><spoken>", entry("hello", register: .spoken))])
        XCTAssertEqual(map["سلام"]?.register, .spoken)
    }

    // registerLabel

    func testLabelsOnlyARegisterSpecificToOne() {
        XCTAssertEqual(registerLabel(.spoken), "informal")
        XCTAssertEqual(registerLabel(.written), "formal")
        XCTAssertNil(registerLabel(.both))
        XCTAssertNil(registerLabel(nil))
    }

    // gateLexemeHintMap

    func testGatesTheHintMapOnWhatsShownAndOnTheExercisesOwnScript() {
        let course = ["سلام": WordHint(translation: "hello", romanization: "salām", ruby: "salām")]
        var settings = TextDisplaySettings.plain
        XCTAssertEqual(gateLexemeHintMap(course, settings: settings, exerciseScriptMode: .native), emptyHintMap)

        settings = .plain
        settings.sentenceRomanization = true
        XCTAssertEqual(gateLexemeHintMap(course, settings: settings, exerciseScriptMode: .native), course)

        settings = .plain
        settings.display = .both
        XCTAssertEqual(gateLexemeHintMap(course, settings: settings, exerciseScriptMode: .native), course)

        settings = .plain
        settings.translationEnabled = true
        XCTAssertEqual(gateLexemeHintMap(course, settings: settings, exerciseScriptMode: .romanized), emptyHintMap)

        // English-side hovers need it whatever the exercise's script.
        settings = .plain
        settings.nativeEnabled = true
        XCTAssertEqual(gateLexemeHintMap(course, settings: settings, exerciseScriptMode: .romanized), course)
    }
}
