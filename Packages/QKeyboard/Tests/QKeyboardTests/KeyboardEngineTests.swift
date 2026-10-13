import XCTest
@testable import QKeyboard

final class KeyboardEngineTests: XCTestCase {
    private func run(_ method: InputMethod, _ keys: [String]) -> KeyboardInputSession {
        var session = KeyboardInputSession(method: method)
        for key in keys { session.type(key) }
        return session
    }

    // MARK: Edit

    func testEditApplyDeletesScalarsNotClusters() {
        let text = "ب\u{200C}"
        XCTAssertEqual(Edit(delete: 1, insert: "").applyTo(text), "ب")
        XCTAssertEqual(Edit(delete: 9, insert: "x").applyTo("ab"), "x")
    }

    func testEditApplyAtCaret() {
        let result = Edit(delete: 1, insert: "XY").applyAt("abcd", caret: 2)
        XCTAssertEqual(result.text, "aXYcd")
        XCTAssertEqual(result.caret, 3)
    }

    // MARK: Persian phonetic

    func testPersianSingleLetterOffersCandidates() {
        let s = run(.persianPhonetic, ["s"])
        XCTAssertEqual(s.text, "س")
        XCTAssertEqual(s.candidates ?? [], ["س", "ص", "ث"])
    }

    func testPersianPickCandidate() {
        var s = run(.persianPhonetic, ["s"])
        s.pick(1)
        XCTAssertEqual(s.text, "ص")
        XCTAssertNil(s.candidates)
    }

    func testPersianNextKeyCommitsProvisionalLetter() {
        let s = run(.persianPhonetic, ["s", "d"])
        XCTAssertEqual(s.text, "سد")
        XCTAssertNil(s.candidates)
    }

    func testPersianDigraphs() {
        XCTAssertEqual(run(.persianPhonetic, ["s", "h"]).text, "ش")
        XCTAssertEqual(run(.persianPhonetic, ["k", "h", "a"]).text, "خا")
        var s = run(.persianPhonetic, ["g", "h"])
        XCTAssertEqual(s.text, "غ")
        XCTAssertEqual(s.candidates ?? [], ["غ", "ق"])
        s.pick(1)
        XCTAssertEqual(s.text, "ق")
    }

    func testPersianBackspaceOnVisibleLetter() {
        var s = run(.persianPhonetic, ["d", "s"])
        s.press(.backspace)
        XCTAssertEqual(s.text, "د")
        XCTAssertNil(s.candidates)
    }

    func testPersianBackspaceOnInvisibleDigraphStarter() {
        var s = run(.persianPhonetic, ["d", "c"])
        XCTAssertEqual(s.text, "د")
        s.press(.backspace)
        XCTAssertEqual(s.text, "د")
        s.type("a")
        XCTAssertEqual(s.text, "دا")
    }

    func testPersianBackspaceAfterDigraphResetsBuffer() {
        var s = run(.persianPhonetic, ["s", "h"])
        s.press(.backspace)
        XCTAssertEqual(s.text, "")
        s.type("h")
        XCTAssertEqual(s.text, "ه")
    }

    func testPersianSpaceAndZwnj() {
        var s = run(.persianPhonetic, ["b"])
        s.press(.space)
        XCTAssertEqual(s.text, "ب ")
        s.press(.zwnj)
        XCTAssertEqual(s.text, "ب \u{200C}")
        s.press(.zwnj)
        XCTAssertEqual(s.text, "ب ")
    }

    func testPersianUnmappedLetterIgnored() {
        var s = KeyboardInputSession(method: .persianPhonetic)
        s.type("1")
        XCTAssertEqual(s.text, "")
    }

    func testPersianScriptedWord() {
        var s = KeyboardInputSession(method: .persianPhonetic)
        for key in ["s", "h", "i", "r"] { s.type(key) }
        XCTAssertEqual(s.text, "شیر")
        s.press(.backspace)
        XCTAssertEqual(s.text, "شی")
        s.type("n")
        XCTAssertEqual(s.text, "شین")
    }

    func testPersianPhoneticLayoutHasZwnjAndRtlCandidates() {
        let layout = PersianPhoneticKeyboardEngine().layout
        XCTAssertTrue(layout.rtlCandidates)
        XCTAssertTrue(layout.rows.flatMap { $0 }.contains { $0.action == .zwnj })
    }

    // MARK: Persian ISIRI layout

    func testPersianLayoutIsolatedAddsZwnjAndBackspaceRemovesOneScalar() {
        var s = KeyboardInputSession(method: .persianLayout(isolated: true))
        s.type("ب")
        s.type("ا")
        XCTAssertEqual(s.text.unicodeScalars.count, 4)
        s.press(.backspace)
        XCTAssertEqual(s.text.unicodeScalars.count, 3)
    }

    func testPersianLayoutJoinedHasNoZwnj() {
        let s = run(.persianLayout(isolated: false), ["ب", "ا"])
        XCTAssertEqual(s.text, "با")
    }

    func testPersianLayoutShiftLayerResetsAfterLetter() {
        var engine = PersianLayoutEngine(isolated: false)
        _ = engine.press(.shift, textBefore: "")
        XCTAssertTrue(engine.layout.rows.flatMap { $0 }.contains { $0.label == "آ" })
        let edit = engine.press(.letter("آ"), textBefore: "")
        XCTAssertEqual(edit, Edit(delete: 0, insert: "آ"))
        XCTAssertFalse(engine.layout.rows.flatMap { $0 }.contains { $0.label == "آ" })
    }

    // MARK: Japanese romaji

    func testRomajiKanaAndPending() {
        var s = run(.japaneseRomaji, ["k"])
        XCTAssertEqual(s.text, "")
        XCTAssertEqual(s.pending, "k")
        s.type("a")
        XCTAssertEqual(s.text, "か")
        XCTAssertNil(s.pending)
    }

    func testRomajiCluster() {
        XCTAssertEqual(run(.japaneseRomaji, ["k", "y", "a"]).text, "きゃ")
    }

    func testRomajiSokuon() {
        XCTAssertEqual(run(.japaneseRomaji, ["t", "t", "a"]).text, "った")
    }

    func testRomajiBackspaceClearsInvisibleBuffer() {
        var s = run(.japaneseRomaji, ["k", "a", "k"])
        XCTAssertEqual(s.text, "か")
        s.press(.backspace)
        XCTAssertEqual(s.text, "か")
        XCTAssertNil(s.pending)
        s.press(.backspace)
        XCTAssertEqual(s.text, "")
    }

    func testRomajiLoneNPlaceholderBackspace() {
        var s = run(.japaneseRomaji, ["n"])
        XCTAssertEqual(s.text, "ｎ")
        s.press(.backspace)
        XCTAssertEqual(s.text, "")
    }

    func testRomajiNnAndNBeforeConsonant() {
        XCTAssertEqual(run(.japaneseRomaji, ["n", "n"]).text, "ん")
        XCTAssertEqual(run(.japaneseRomaji, ["n", "k", "a"]).text, "んか")
    }

    func testRomajiSpaceResolvesPendingN() {
        var s = run(.japaneseRomaji, ["n"])
        s.press(.space)
        XCTAssertEqual(s.text, "ん ")
    }

    func testRomajiSwitchMethodFinalizes() {
        var s = run(.japaneseRomaji, ["n"])
        s.switchMethod(.japaneseKana)
        XCTAssertEqual(s.text, "ん")
    }

    func testRomajiScriptedWord() {
        var s = KeyboardInputSession(method: .japaneseRomaji)
        for key in ["s", "h", "i", "n", "b", "u", "n"] { s.type(key) }
        s.finalize()
        XCTAssertEqual(s.text, "しんぶん")
    }

    // MARK: Japanese kana

    func testKanaDakutenAndHandakuten() {
        var s = run(.japaneseKana, ["か"])
        s.press(.dakuten)
        XCTAssertEqual(s.text, "が")
        s.press(.handakuten)
        XCTAssertEqual(s.text, "が")
        s.type("は")
        s.press(.handakuten)
        XCTAssertEqual(s.text, "がぱ")
    }

    func testKanaMarkOnNothingIsNoop() {
        var s = KeyboardInputSession(method: .japaneseKana)
        s.press(.dakuten)
        XCTAssertEqual(s.text, "")
    }

    func testKanaKatakanaToggleKeepsScriptOnMarks() {
        var s = KeyboardInputSession(method: .japaneseKana)
        s.press(.scriptToggle)
        s.type("か")
        XCTAssertEqual(s.text, "カ")
        s.press(.dakuten)
        XCTAssertEqual(s.text, "ガ")
    }

    func testKanaSmallModeUntilNextLetter() {
        var engine = JapaneseKanaEngine()
        _ = engine.press(.smallKana, textBefore: "")
        XCTAssertTrue(engine.layout.rows.flatMap { $0 }.contains { $0.action == .letter("っ") })
        let edit = engine.press(.letter("っ"), textBefore: "")
        XCTAssertEqual(edit, Edit(delete: 0, insert: "っ"))
        XCTAssertFalse(engine.layout.rows.flatMap { $0 }.contains { $0.action == .letter("っ") })
    }

    func testKanaBackspaceAndSpace() {
        var s = run(.japaneseKana, ["あ", "い"])
        s.press(.space)
        XCTAssertEqual(s.text, "あい ")
        s.press(.backspace)
        s.press(.backspace)
        XCTAssertEqual(s.text, "あ")
    }

    // MARK: Method toggle and Latin

    func testToggledLayout() {
        XCTAssertEqual(InputMethod.persianPhonetic.toggledLayout, .persianLayout(isolated: false))
        XCTAssertEqual(InputMethod.persianLayout(isolated: true).toggledLayout, .persianPhonetic)
        XCTAssertEqual(InputMethod.japaneseRomaji.toggledLayout, .japaneseKana)
        XCTAssertEqual(InputMethod.japaneseKana.toggledLayout, .japaneseRomaji)
        XCTAssertEqual(InputMethod.latin.toggledLayout, .latin)
    }

    func testLatinShiftAppliesOnce() {
        var s = KeyboardInputSession(method: .latin)
        s.press(.shift)
        s.type("a")
        s.type("b")
        XCTAssertEqual(s.text, "Ab")
    }

    func testSymbolsDigitsToggle() {
        var s = KeyboardInputSession(method: .symbols)
        s.type("1")
        s.press(.scriptToggle)
        XCTAssertTrue(s.layout.rows[0].contains { $0.label == "۱" })
    }
}
