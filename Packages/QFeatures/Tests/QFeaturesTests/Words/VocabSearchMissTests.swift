import XCTest
@testable import QFeatures

final class VocabSearchMissTests: XCTestCase {
    private let salam = "\u{0633}\u{0644}\u{0627}\u{0645}"

    func testWholeCourseMissReadsNotFoundAndOffersLookup() {
        let kind = vocabEmptyKind(query: "  xyz \n", scope: .course)
        XCTAssertEqual(kind, .notInCourse(query: "xyz"))
        XCTAssertEqual(kind.text, "Word not found in course.")
        XCTAssertEqual(kind.lookupQuery, "xyz")
    }

    func testLessonAndUnitMissesKeepNoWordsMatch() {
        for scope in [VocabScope.lesson, .unit] {
            let kind = vocabEmptyKind(query: " xyz ", scope: scope)
            XCTAssertEqual(kind, .noMatch(query: "xyz"))
            XCTAssertEqual(kind.text, "No words match \"xyz\".")
            XCTAssertNil(kind.lookupQuery)
        }
    }

    func testBlankQueryIsNothingYetInEveryScope() {
        for scope in [VocabScope.lesson, .unit, .course] {
            let kind = vocabEmptyKind(query: " \t\n", scope: scope)
            XCTAssertEqual(kind, .nothingYet)
            XCTAssertEqual(kind.text, "Nothing here yet.")
            XCTAssertNil(kind.lookupQuery)
        }
    }

    func testLookupHeadingUsesTrimmedQuery() {
        XCTAssertEqual(dictionaryLookupHeading(query: "  \(salam) "), "Look up \"\(salam)\" in:")
    }

    func testLinksAreWiktionaryThenVajehyabWithEncodedPersianQuery() {
        let links = dictionaryLinks(query: " \(salam)\n")
        XCTAssertEqual(links.map { $0.site }, [.wiktionary, .vajehyab])
        XCTAssertEqual(links.map { $0.site.name }, ["Wiktionary", "Vajehyab"])
        XCTAssertEqual(
            links[0].url.absoluteString,
            "https://en.wiktionary.org/w/index.php?search=%D8%B3%D9%84%D8%A7%D9%85&go=Go")
        XCTAssertEqual(links[1].url.absoluteString, "https://vajehyab.com/w/%D8%B3%D9%84%D8%A7%D9%85")
    }

    func testEncodingEscapesSpacesReservedCharactersAndZeroWidthNonJoiner() {
        XCTAssertEqual(dictionaryPercentEncode("a b&c=d/e?f#g+h"), "a%20b%26c%3Dd%2Fe%3Ff%23g%2Bh")
        XCTAssertEqual(dictionaryPercentEncode("Az-09._~"), "Az-09._~")
        // "mi" + ZWNJ: the joiner is passed through, encoded.
        XCTAssertEqual(dictionaryPercentEncode("\u{0645}\u{06CC}\u{200C}"), "%D9%85%DB%8C%E2%80%8C")
        XCTAssertEqual(
            DictionarySite.vajehyab.url(query: "  two words ")?.absoluteString, "https://vajehyab.com/w/two%20words")
    }

    func testBlankQueryHasNoLinks() {
        XCTAssertEqual(dictionaryLinks(query: "  "), [])
    }

    func testIconsAreBundled() {
        for site in DictionarySite.allCases {
            XCTAssertNotNil(site.iconURL, "\(site.rawValue) icon missing")
        }
    }
}

@MainActor
final class VocabSearchMissModelTests: XCTestCase {
    func testModelOffersLookupsOnlyForWholeCourseMiss() async {
        let source = FakeVocabSource()
        source.loadHandler = { .ready(sampleContent) }
        let store = VocabularyStore(source: source)
        let model = SkillVocabularyModel(store: store, unitKey: "u1", skillKey: "s1")
        await model.refresh()

        model.query = " zzz "
        XCTAssertEqual(model.terms, [])
        XCTAssertEqual(model.emptyText, "No words match \"zzz\".")
        XCTAssertEqual(model.dictionaryLookups, [])

        model.setScope(.unit)
        XCTAssertEqual(model.emptyText, "No words match \"zzz\".")
        XCTAssertEqual(model.dictionaryLookups, [])

        model.setScope(.course)
        XCTAssertEqual(model.terms, [])
        XCTAssertEqual(model.emptyText, "Word not found in course.")
        XCTAssertEqual(model.dictionaryLookups.map { $0.url.absoluteString }, [
            "https://en.wiktionary.org/w/index.php?search=zzz&go=Go",
            "https://vajehyab.com/w/zzz",
        ])

        model.query = ""
        XCTAssertEqual(model.emptyText, "Nothing here yet.")
        XCTAssertEqual(model.dictionaryLookups, [])
    }
}
