import XCTest
@testable import QDomain

final class KanaKeyboardTests: XCTestCase {
    // kanaTable

    func testEveryProperPrefixIsValid() {
        for key in kanaTable.keys {
            let chars = Array(key)
            if chars.count < 2 { continue }
            for length in 1..<chars.count {
                let prefix = String(chars[0..<length])
                XCTAssertTrue(validRomajiPrefixes.contains(prefix), prefix)
            }
        }
    }

    func testPrefixesCoverClustersOnly() {
        XCTAssertTrue(validRomajiPrefixes.contains("ky"))
        XCTAssertTrue(validRomajiPrefixes.contains("xts"))
        XCTAssertTrue(validRomajiPrefixes.contains("n"))
        XCTAssertFalse(validRomajiPrefixes.contains("ka"))
        XCTAssertFalse(validRomajiPrefixes.contains(""))
        XCTAssertFalse(validRomajiPrefixes.contains("q"))
    }

    func testAlternateSpellings() {
        XCTAssertEqual(kanaTable["shi"], kanaTable["si"])
        XCTAssertEqual(kanaTable["tsu"], kanaTable["tu"])
        XCTAssertEqual(kanaTable["xya"], "ゃ")
    }

    // kanaScript

    func testToKatakana() {
        XCTAssertEqual(toKatakana("きゃー"), "キャー")
        XCTAssertEqual(toKatakana("がっこう abc。"), "ガッコウ abc。")
        XCTAssertEqual(toKatakana("ぁゖ"), "ァヶ")
    }

    func testToHiragana() {
        XCTAssertEqual(toHiragana("キャー"), "きゃー")
        XCTAssertEqual(toHiragana("ァヶ"), "ぁゖ")
        XCTAssertEqual(toHiragana("ヷ"), "ヷ")
    }

    func testConvertKanaScript() {
        XCTAssertEqual(convertKanaScript("かナ", script: .katakana), "カナ")
        XCTAssertEqual(convertKanaScript("かナ", script: .hiragana), "かな")
    }

    // dakuten

    func testDakutenVoices() {
        XCTAssertEqual(applyDakuten("か"), "が")
        XCTAssertEqual(applyDakuten("つ"), "づ")
        XCTAssertEqual(applyDakuten("は"), "ば")
    }

    func testDakutenKeepsScript() {
        XCTAssertEqual(applyDakuten("カ"), "ガ")
        XCTAssertEqual(applyDakuten("ソ"), "ゾ")
    }

    func testHandakutenOnlyHaRow() {
        XCTAssertEqual(applyHandakuten("は"), "ぱ")
        XCTAssertEqual(applyHandakuten("ヘ"), "ペ")
        XCTAssertEqual(applyHandakuten("か"), "か")
    }

    func testMarkNoOps() {
        XCTAssertEqual(applyDakuten("あ"), "あ")
        XCTAssertEqual(applyDakuten("ー"), "ー")
        XCTAssertEqual(applyDakuten("ン"), "ン")
        XCTAssertEqual(applyDakuten("が"), "が")
    }

    // jisKanaLayout

    func testRowShapes() {
        XCTAssertEqual(jisKanaNumberRow.count, 12)
        XCTAssertEqual(jisKanaRows.map { $0.count }, [11, 12, 11])
        XCTAssertEqual(jisKanaNumberRow.map { $0.kana }.joined(), "ぬふあうえおやゆよわほへ")
        XCTAssertEqual(jisKanaRows[0].map { $0.kana }.joined(), "たていすかんなにらせー")
        XCTAssertEqual(jisKanaWo, "を")
    }

    func testOnlyRoHasNoPhysicalKey() {
        let all = jisKanaNumberRow + jisKanaRows.flatMap { $0 }
        XCTAssertEqual(all.filter { $0.physicalCode == nil }.map { $0.kana }, ["ろ"])
    }

    func testPhysicalCharMapping() {
        XCTAssertEqual(physicalCharToKana["t"], "か")
        XCTAssertEqual(physicalCharToKana["3"], "あ")
        XCTAssertEqual(physicalCharToKana["0"], "わ")
        XCTAssertEqual(physicalCharToKana["-"], "ほ")
        XCTAssertEqual(physicalCharToKana["="], "へ")
        XCTAssertEqual(physicalCharToKana["\\"], "ー")
        XCTAssertEqual(physicalCharToKana["z"], "つ")
    }

    func testOtherPunctuationUnmapped() {
        for ch in [";", "'", "[", ",", ".", "/"] as [Character] {
            XCTAssertNil(physicalCharToKana[ch], String(ch))
        }
        XCTAssertEqual(physicalCharToKana.count, 10 + 2 + 10 + 1 + 9 + 7)
    }
}
