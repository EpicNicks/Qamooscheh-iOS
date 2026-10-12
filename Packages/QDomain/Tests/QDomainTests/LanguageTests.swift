import XCTest
import QModel
@testable import QDomain

final class LanguageTests: XCTestCase {
    func testLanguageInfoLookup() {
        XCTAssertEqual(Languages.languageInfo("fa")?.displayName, "Persian")
        XCTAssertEqual(Languages.languageInfo("fa")?.direction, .rtl)
        XCTAssertEqual(Languages.languageInfo("fa")?.speechTag, "fa-IR")
        XCTAssertEqual(Languages.languageInfo("ja")?.nativeName, "日本語")
        XCTAssertEqual(Languages.languageInfo("ja")?.romanizedName, "Nihongo")
        XCTAssertNil(Languages.languageInfo("xx"))
        XCTAssertNil(Languages.languageInfo(nil))
    }

    func testIsPersianAndWritingDirection() {
        XCTAssertTrue(Languages.isPersian("fa"))
        XCTAssertFalse(Languages.isPersian("ja"))
        XCTAssertFalse(Languages.isPersian(nil))
        XCTAssertEqual(Languages.writingDirection("fa"), .rtl)
        XCTAssertEqual(Languages.writingDirection("ja"), .ltr)
        XCTAssertEqual(Languages.writingDirection(nil), .ltr)
    }

    func testIsNativeText() {
        XCTAssertTrue(Languages.isNativeText("fa", "سلام"))
        XCTAssertFalse(Languages.isNativeText("fa", "hello"))
        XCTAssertTrue(Languages.isNativeText("ja", "こんにちは"))
        XCTAssertTrue(Languages.isNativeText("ja", "漢字"))
        XCTAssertFalse(Languages.isNativeText("ja", "hello"))
        XCTAssertFalse(Languages.isNativeText("xx", "سلام"))
    }

    func testSpeechLang() {
        XCTAssertEqual(Languages.speechLang("fa", "سلام"), "fa-IR")
        XCTAssertEqual(Languages.speechLang("fa", "hello"), "en-US")
        XCTAssertEqual(Languages.speechLang("ja", "日本語"), "ja-JP")
        XCTAssertNil(Languages.speechLang("xx", "hello"))
    }

    func testDetectScriptDirection() {
        XCTAssertEqual(Languages.detectScriptDirection("سلام hello"), .rtl)
        XCTAssertEqual(Languages.detectScriptDirection("hello"), .ltr)
        XCTAssertEqual(Languages.detectScriptDirection(""), .ltr)
    }

    func testKeyboardKind() {
        XCTAssertNil(Languages.keyboardKind("fa", scriptMode: .romanized, fa: .layout, ja: .phonetic))
        XCTAssertNil(Languages.keyboardKind("xx", scriptMode: .native, fa: .layout, ja: .phonetic))
        XCTAssertEqual(Languages.keyboardKind("fa", scriptMode: .native, fa: .layout, ja: .phonetic), .persianLayout)
        XCTAssertEqual(Languages.keyboardKind("fa", scriptMode: .native, fa: .phonetic, ja: .phonetic), .persianPhonetic)
        XCTAssertEqual(Languages.keyboardKind("ja", scriptMode: .native, fa: .layout, ja: .phonetic), .japanesePhonetic)
        XCTAssertEqual(Languages.keyboardKind("ja", scriptMode: .native, fa: .layout, ja: .kana), .japaneseKana)
    }
}
