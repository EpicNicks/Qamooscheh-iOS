import XCTest
import QModel
@testable import QDomain

// Port of web annotation.test.ts, plus displayDirection (documented behaviour).
final class AnnotationTests: XCTestCase {
    private func hint(_ romanization: String) -> WordHint {
        return WordHint(translation: romanization, romanization: romanization, ruby: romanization)
    }

    // resolveScriptDisplay

    func testMapsRomanizedAndBothStraightThroughRegardlessOfLanguage() {
        XCTAssertEqual(resolveScriptDisplay(scriptMode: .romanized, language: "fa", showFurigana: false), .romanized)
        XCTAssertEqual(resolveScriptDisplay(scriptMode: .both, language: "fa", showFurigana: false), .both)
        XCTAssertEqual(resolveScriptDisplay(scriptMode: .both, language: "ja", showFurigana: false), .both)
    }

    func testKeepsNativeAsNativeForALanguageWithNoFuriganaToggleOn() {
        XCTAssertEqual(resolveScriptDisplay(scriptMode: .native, language: "fa", showFurigana: false), .native)
        XCTAssertEqual(resolveScriptDisplay(scriptMode: .native, language: "ja", showFurigana: false), .native)
    }

    func testJapanesesLocalShowFuriganaToggleUpgradesNativeToBoth() {
        XCTAssertEqual(resolveScriptDisplay(scriptMode: .native, language: "ja", showFurigana: true), .both)
    }

    func testShowFuriganaHasNoEffectForALanguageOtherThanJapanese() {
        XCTAssertEqual(resolveScriptDisplay(scriptMode: .native, language: "fa", showFurigana: true), .native)
    }

    func testDefaultsToNativeWhenThereIsNoPreferenceYet() {
        XCTAssertEqual(resolveScriptDisplay(scriptMode: nil, language: "fa", showFurigana: false), .native)
    }

    // segmentWords

    func testKeepsAZWNJJoinedIsolatedLetterformSpellingInsideOneWordToken() {
        let isolated = ["\u{0645}\u{06CC}", "\u{0634}\u{0645}"].joined(separator: ZWNJ)
        let pieces = segmentWords(isolated)
        let words = pieces.filter { $0.isWord }.map { $0.text }
        XCTAssertEqual(words, [isolated])
    }

    // segmentAnnotatedText

    func testRendersAPlainWordWithNoHintAsAnUnannotatedSegment() {
        let segments = segmentAnnotatedText("\u{0633}\u{0644}\u{0627}\u{0645}", [:])
        XCTAssertEqual(segments, [AnnotatedSegment(text: "\u{0633}\u{0644}\u{0627}\u{0645}", isWord: true, hint: nil)])
    }

    func testPassesPunctuationAndWhitespaceThroughUnchangedUnannotated() {
        let map = ["\u{0633}\u{0644}\u{0627}\u{0645}": hint("sal\u{0101}m")]
        let segments = segmentAnnotatedText("\u{0633}\u{0644}\u{0627}\u{0645}\u{060C}", map)
        XCTAssertEqual(segments.map { $0.text }.joined(), "\u{0633}\u{0644}\u{0627}\u{0645}\u{060C}")
        XCTAssertEqual(segments.first { $0.text == "\u{060C}" }?.isWord, false)
    }

    func testPrefersTheLongestMultiWordPhraseMatchOverTheSingleWordFallback() {
        let map: [String: WordHint] = [
            "آخر": hint("ākhar"),
            "آخر هفته": hint("ākhar-e hafte"),
        ]
        let segments = segmentAnnotatedText("آخر هفته خوب است", map)
        // The phrase collapses into one segment with the phrase's own hint...
        XCTAssertEqual(segments[0], AnnotatedSegment(text: "آخر هفته", isWord: true, hint: hint("ākhar-e hafte")))
        // ...and the rest of the sentence continues normally, word by word.
        XCTAssertEqual(segments.dropFirst().map { $0.text }, [" ", "خوب", " ", "است"])
    }

    func testFallsBackToTheSingleWordWhenNoLongerPhraseMatches() {
        let map = ["هفته": hint("hafte")]
        let segments = segmentAnnotatedText("آخر هفته", map)
        XCTAssertEqual(segments[0], AnnotatedSegment(text: "آخر", isWord: true, hint: nil))
        XCTAssertEqual(segments[2], AnnotatedSegment(text: "هفته", isWord: true, hint: hint("hafte")))
    }

    // displayDirection

    func testRomanizedDisplayIsAlwaysLeftToRight() {
        XCTAssertEqual(displayDirection("سلام", display: .romanized), .ltr)
    }

    func testOtherDisplaysFollowTheTextsOwnScript() {
        XCTAssertEqual(displayDirection("سلام", display: .native), .rtl)
        XCTAssertEqual(displayDirection("سلام", display: .both), .rtl)
        XCTAssertEqual(displayDirection("hello", display: .native), .ltr)
    }
}
