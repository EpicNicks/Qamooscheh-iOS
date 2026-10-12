import XCTest
@testable import QDomain

final class AbjadSearchTests: XCTestCase {
    private func parse(_ text: String, _ tokens: [LetterSearchToken] = []) -> LetterSearchResult {
        parseLetterSearch(text, tokens)
    }

    private func labels(_ text: String, _ tokens: [LetterSearchToken] = []) -> [String] {
        parse(text, tokens).tokens.map { $0.label }
    }

    func testTurnsEachPersianLetterIntoItsOwnToken() {
        let tokens = parse("ثب").tokens
        XCTAssertEqual(tokens.map { $0.label }, ["ث", "ب"])
        XCTAssertEqual(tokens.map { $0.letters }, [["ث"], ["ب"]])
    }

    func testMapsALatinCharacterToEveryLetterWithThatSound() {
        XCTAssertEqual(parse("s").tokens[0].letters, ["ث", "س", "ص"])
        XCTAssertEqual(parse("z").tokens[0].letters, ["ذ", "ز", "ض", "ظ"])
        XCTAssertEqual(parse("H").tokens[0].letters, ["ح", "ه"])
    }

    func testDropsAnythingThatIsntALetterOrAMappedLatinCharacter() {
        XCTAssertEqual(labels("1 x!؟s"), ["s"])
    }

    func testBuildsDigraphsAsTheHArrivesIncludingAcrossSeparateKeystrokes() {
        XCTAssertEqual(labels("sh"), ["sh"])
        XCTAssertEqual(labels("h", parse("k").tokens), ["kh"])
        XCTAssertEqual(parse("gh").tokens[0].letters, ["غ", "ق"])
    }

    func testHoldsALoneCUntilItBecomesChAndDropsItOtherwise() {
        XCTAssertEqual(parse("c"), LetterSearchResult(tokens: [], pending: "c"))
        XCTAssertEqual(labels("ch"), ["ch"])
        XCTAssertEqual(labels("cb"), ["b"])
    }

    func testKeepsOneTokenPerSearchMovingARepeatToTheEnd() {
        XCTAssertEqual(labels("sbs"), ["b", "s"])
    }

    func testReadsArabicLookAlikesHamzaMaddeFormsAndMacronsAsTheirBaseLetter() {
        XCTAssertEqual(labels("يكآ"), ["ی", "ک", "ا"])
        XCTAssertEqual(labels("ؤئ"), ["و", "ی"])
        XCTAssertEqual(labels("ā"), ["a"])
    }

    func testTokensCarryKindAndAUniqueKey() {
        let tokens = parse("ثs").tokens
        XCTAssertEqual(tokens.map { $0.key }, ["fa:ث", "latin:s"])
        XCTAssertEqual(tokens.map { $0.kind }, [.persian, .latin])
    }

    func testQSelectsOnlyQaf() {
        XCTAssertEqual(parse("q").tokens[0].letters, ["ق"])
    }

    func testLettersMatchingIsNilWithNoTokensAndTheUnionOtherwise() {
        XCTAssertNil(lettersMatching([]))
        XCTAssertEqual(lettersMatching(parse("tث").tokens), ["ت", "ط", "ث"])
    }
}
