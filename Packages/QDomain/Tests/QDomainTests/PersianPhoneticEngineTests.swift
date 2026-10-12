import XCTest
@testable import QDomain

final class PersianPhoneticEngineTests: XCTestCase {
    private struct Keystroke: Equatable {
        let char: Character
        let deleteCount: Int
        let insertText: String
        let candidates: [String]?
        let text: String
    }

    private func typeLatin(_ input: String) -> (text: String, state: PersianPhoneticState, keystrokes: [Keystroke]) {
        var state = PersianPhoneticState.initial
        var text = ""
        var keystrokes: [Keystroke] = []
        for char in input {
            let step = PersianPhoneticEngine.feedLatinChar(state, char)
            text = String(text.dropLast(step.deleteCount)) + step.insertText
            state = step.state
            keystrokes.append(Keystroke(char: char, deleteCount: step.deleteCount,
                                        insertText: step.insertText, candidates: step.candidates, text: text))
        }
        return (text, state, keystrokes)
    }

    func testDigraphsResolveBeforeSingles() {
        XCTAssertEqual(PersianPhoneticMap.resolveTrigger("sh"), ["ش"])
        XCTAssertEqual(PersianPhoneticMap.resolveTrigger("gh"), ["غ", "ق"])
        XCTAssertEqual(PersianPhoneticMap.resolveTrigger("s"), ["س", "ص", "ث"])
        XCTAssertNil(PersianPhoneticMap.resolveTrigger("c"))
        XCTAssertNil(PersianPhoneticMap.resolveTrigger("sx"))
    }

    func testEveryLetterAndApostropheHavePhoneticValue() {
        for scalar in UInt8(ascii: "a")...UInt8(ascii: "z") {
            let letter = String(UnicodeScalar(scalar))
            XCTAssertTrue(PersianPhoneticMap.hasPhoneticValue(letter), letter)
        }
        XCTAssertTrue(PersianPhoneticMap.hasPhoneticValue("C"))
        XCTAssertTrue(PersianPhoneticMap.hasPhoneticValue("'"))
        XCTAssertFalse(PersianPhoneticMap.hasPhoneticValue("1"))
        XCTAssertFalse(PersianPhoneticMap.hasPhoneticValue("-"))
    }

    func testEIsAliasOfA() {
        XCTAssertEqual(PersianPhoneticMap.singles["a"], PersianPhoneticMap.singles["e"])
    }

    func testAmbiguousLetterInsertsDefaultAndOffersCandidates() {
        let step = PersianPhoneticEngine.feedLatinChar(.initial, "s")
        XCTAssertEqual(step.insertText, "س")
        XCTAssertEqual(step.deleteCount, 0)
        XCTAssertEqual(step.candidates, ["س", "ص", "ث"])
        XCTAssertEqual(step.state, PersianPhoneticState(bufferedPrefix: "s"))
    }

    func testUnambiguousLetterOffersNoCandidates() {
        let step = PersianPhoneticEngine.feedLatinChar(.initial, "b")
        XCTAssertEqual(step, PersianPhoneticStep(state: .initial, deleteCount: 0, insertText: "ب", candidates: nil))
    }

    func testDigraphRetractsEagerGuess() {
        XCTAssertEqual(typeLatin("sh").keystrokes, [
            Keystroke(char: "s", deleteCount: 0, insertText: "س", candidates: ["س", "ص", "ث"], text: "س"),
            Keystroke(char: "h", deleteCount: 1, insertText: "ش", candidates: nil, text: "ش"),
        ])
    }

    func testAmbiguousDigraphOffersOwnCandidates() {
        XCTAssertEqual(typeLatin("gh").keystrokes, [
            Keystroke(char: "g", deleteCount: 0, insertText: "گ", candidates: nil, text: "گ"),
            Keystroke(char: "h", deleteCount: 1, insertText: "غ", candidates: ["غ", "ق"], text: "غ"),
        ])
    }

    func testCBuffersSilentlyAndChDeletesNothing() {
        XCTAssertEqual(typeLatin("ch").keystrokes, [
            Keystroke(char: "c", deleteCount: 0, insertText: "", candidates: nil, text: ""),
            Keystroke(char: "h", deleteCount: 0, insertText: "چ", candidates: nil, text: "چ"),
        ])
    }

    func testLoneCFollowedByNonHIsDropped() {
        let result = typeLatin("ca")
        XCTAssertEqual(result.text, "ا")
        XCTAssertEqual(result.keystrokes.last?.candidates, ["ا", "آ"])
    }

    func testStarterNotFollowedByHKeepsEagerGuess() {
        XCTAssertEqual(typeLatin("kt").text, "کت")
        XCTAssertEqual(typeLatin("ss").text, "سس")
        XCTAssertEqual(typeLatin("ss").state, PersianPhoneticState(bufferedPrefix: "s"))
    }

    func testWordsTypeThrough() {
        XCTAssertEqual(typeLatin("khub").text, "خوب")
        XCTAssertEqual(typeLatin("zhila").text, "ژیلا")
        XCTAssertEqual(typeLatin("zhaleh").text, "ژالاه")
        XCTAssertEqual(typeLatin("shir").text, "شیر")
        XCTAssertEqual(typeLatin("'").text, "ع")
    }

    func testInputIsLowercased() {
        XCTAssertEqual(typeLatin("SH").text, "ش")
    }

    func testUnmappedCharacterInsertsNothingAndClearsBuffer() {
        XCTAssertEqual(typeLatin("s1h").text, "سه")
        XCTAssertEqual(typeLatin("s1").state, .initial)
    }

    func testFinalizingIsNoOpEdit() {
        XCTAssertEqual(PersianPhoneticEngine.finalizeWord(),
                       PersianPhoneticStep(state: .initial, deleteCount: 0, insertText: "", candidates: nil))
    }
}
