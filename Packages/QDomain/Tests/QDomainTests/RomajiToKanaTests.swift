import XCTest
@testable import QDomain

final class RomajiToKanaTests: XCTestCase {
    private struct Keystroke: Equatable {
        let char: Character
        let deleteCount: Int
        let insertText: String
        let text: String
        let buffer: String
    }

    private func typeRomaji(_ input: String) -> (text: String, state: JapanesePhoneticState, keystrokes: [Keystroke]) {
        var state = JapanesePhoneticState.initial
        var text = ""
        var keystrokes: [Keystroke] = []
        for char in input {
            let step = feedRomajiChar(state, char)
            text = String(text.dropLast(step.deleteCount)) + step.insertText
            state = step.state
            keystrokes.append(Keystroke(char: char, deleteCount: step.deleteCount,
                                        insertText: step.insertText, text: text, buffer: state.buffer))
        }
        return (text, state, keystrokes)
    }

    private func typeAndFinalize(_ input: String) -> String {
        let typed = typeRomaji(input)
        let step = finalizeRomaji(typed.state)
        return String(typed.text.dropLast(step.deleteCount)) + step.insertText
    }

    private func assertTyped(_ input: String, _ text: String, _ buffer: String,
                             file: StaticString = #filePath, line: UInt = #line) {
        let result = typeRomaji(input)
        XCTAssertEqual(result.text, text, "text for \(input)", file: file, line: line)
        XCTAssertEqual(result.state.buffer, buffer, "buffer for \(input)", file: file, line: line)
    }

    func testBareVowel() { assertTyped("a", "あ", "") }
    func testSimpleCV() { assertTyped("ka", "か", "") }
    func testConsonantAloneStaysBuffered() { assertTyped("k", "", "k") }
    func testSokuonKitte() { assertTyped("kitte", "きって", "") }
    func testSokuonWholeWord() { assertTyped("gakkou", "がっこう", "") }
    func testYouon() { assertTyped("kya", "きゃ", "") }
    func testBareNShowsPlaceholder() { assertTyped("n", "ｎ", "n") }
    func testNnCommits() { assertTyped("nn", "ん", "") }
    func testNVowelIsNaRow() { assertTyped("na", "な", "") }
    func testNConsonantCommitsN() { assertTyped("nk", "ん", "k") }
    func testNConsonantCompleted() { assertTyped("nka", "んか", "") }
    func testAlternateSpelling() { assertTyped("sushi", "すし", "") }
    func testSiShiAlternate() { assertTyped("susi", "すし", "") }
    func testDakutenYouon() { assertTyped("zya", "じゃ", "") }
    func testXPrefixedSmallKana() { assertTyped("xtsu", "っ", "") }
    func testImpossibleClusterRestarts() { assertTyped("ktu", "つ", "") }
    func testUnresolvableClusterThenVowel() { assertTyped("kye", "え", "") }
    func testNnIsGreedy() { assertTyped("konnichiha", "こんいちは", "") }
    func testUppercaseLowercased() { assertTyped("KA", "か", "") }

    func testKitteKeystrokes() {
        XCTAssertEqual(typeRomaji("kitte").keystrokes, [
            Keystroke(char: "k", deleteCount: 0, insertText: "", text: "", buffer: "k"),
            Keystroke(char: "i", deleteCount: 0, insertText: "き", text: "き", buffer: ""),
            Keystroke(char: "t", deleteCount: 0, insertText: "", text: "き", buffer: "t"),
            Keystroke(char: "t", deleteCount: 0, insertText: "っ", text: "きっ", buffer: "t"),
            Keystroke(char: "e", deleteCount: 0, insertText: "て", text: "きって", buffer: ""),
        ])
    }

    func testPlaceholderReplacedOnNn() {
        XCTAssertEqual(typeRomaji("nn").keystrokes, [
            Keystroke(char: "n", deleteCount: 0, insertText: "ｎ", text: "ｎ", buffer: "n"),
            Keystroke(char: "n", deleteCount: 1, insertText: "ん", text: "ん", buffer: ""),
        ])
    }

    func testPlaceholderReplacedOnConsonant() {
        XCTAssertEqual(typeRomaji("nk").keystrokes, [
            Keystroke(char: "n", deleteCount: 0, insertText: "ｎ", text: "ｎ", buffer: "n"),
            Keystroke(char: "k", deleteCount: 1, insertText: "ん", text: "ん", buffer: "k"),
        ])
    }

    func testPlaceholderReplacedOnVowel() {
        XCTAssertEqual(typeRomaji("na").keystrokes, [
            Keystroke(char: "n", deleteCount: 0, insertText: "ｎ", text: "ｎ", buffer: "n"),
            Keystroke(char: "a", deleteCount: 1, insertText: "な", text: "な", buffer: ""),
        ])
    }

    func testKyaBuffersSilently() {
        XCTAssertEqual(typeRomaji("kya").keystrokes, [
            Keystroke(char: "k", deleteCount: 0, insertText: "", text: "", buffer: "k"),
            Keystroke(char: "y", deleteCount: 0, insertText: "", text: "", buffer: "ky"),
            Keystroke(char: "a", deleteCount: 0, insertText: "きゃ", text: "きゃ", buffer: ""),
        ])
    }

    func testFinalizeCommitsPendingN() {
        XCTAssertEqual(finalizeRomaji(JapanesePhoneticState(buffer: "n")),
                       RomajiStep(state: .initial, deleteCount: 1, insertText: "ん"))
        XCTAssertEqual(typeAndFinalize("nihon"), "にほん")
    }

    func testFinalizeDropsOtherBuffer() {
        XCTAssertEqual(finalizeRomaji(JapanesePhoneticState(buffer: "ky")),
                       RomajiStep(state: .initial, deleteCount: 0, insertText: ""))
        XCTAssertEqual(typeAndFinalize("nihonk"), "にほん")
    }

    func testFinalizeEmptyIsNoOp() {
        XCTAssertEqual(finalizeRomaji(.initial), RomajiStep(state: .initial, deleteCount: 0, insertText: ""))
    }
}
