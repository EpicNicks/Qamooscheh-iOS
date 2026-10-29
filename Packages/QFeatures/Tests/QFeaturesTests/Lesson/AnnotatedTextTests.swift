import XCTest
import CoreGraphics
import QModel
import QDomain
@testable import QFeatures

final class AnnotatedTextTests: XCTestCase {
    private let hints: [String: WordHint] = [
        "کتاب": WordHint(translation: "book", romanization: "ketāb", ruby: "ketāb"),
        "من": WordHint(translation: "my", romanization: "man", ruby: "man"),
    ]

    private func look(display: ScriptDisplay, translation: Bool = true, romanization: Bool = true, vowelMarks: Bool = true, centered: Bool = false) -> LessonTextLook {
        return LessonTextLook(
            settings: TextDisplaySettings(
                display: display,
                translationEnabled: translation,
                romanizationEnabled: romanization,
                nativeEnabled: false,
                vowelMarks: vowelMarks,
                sentenceRomanization: true
            ),
            courseHints: hints,
            centerNative: centered,
            nativeScale: 1.25
        )
    }

    func testTipLinesTranslationThenBracketedRomanization() {
        let hint = WordHint(translation: "book", romanization: "ketāb", ruby: nil)
        XCTAssertEqual(tipLines(hint, settings: look(display: .native).settings), ["book", "[ketāb]"])
    }

    func testTipLinesRomanizationAloneIsNotBracketed() {
        let hint = WordHint(translation: "book", romanization: "ketāb", ruby: nil)
        XCTAssertEqual(tipLines(hint, settings: look(display: .native, translation: false).settings), ["ketāb"])
    }

    func testTipLinesHideRomanizationWhenAlreadyOnScreen() {
        let hint = WordHint(translation: "book", romanization: "ketāb", ruby: nil)
        XCTAssertEqual(tipLines(hint, settings: look(display: .both).settings), ["book"])
    }

    func testTipLinesEzafeRidesTranslationOrGetsItsOwnLine() {
        let hint = WordHint(translation: "book", romanization: "ketāb", ruby: nil, ezafe: .e)
        XCTAssertEqual(tipLines(hint, settings: look(display: .native).settings), ["book  -e", "[ketāb-e]"])
        XCTAssertEqual(tipLines(hint, settings: look(display: .native, translation: false, romanization: false).settings), ["-e ezafe"])
    }

    func testTipLinesRegisterLabel() {
        let hint = WordHint(translation: "house", romanization: nil, ruby: nil, register: .spoken)
        XCTAssertEqual(tipLines(hint, settings: look(display: .native).settings), ["house [informal]"])
    }

    func testPersianPlanIsRtlInlineAndScaled() {
        let plan = planAnnotatedText("کتاب من", scriptMode: .native, tags: [], look: look(display: .native))
        XCTAssertEqual(plan.kind, .inline)
        XCTAssertTrue(plan.rtl)
        XCTAssertEqual(plan.fontScale, 1.25)
        XCTAssertEqual(plan.runs.filter { $0.isTappable }.count, 2)
    }

    func testFocusTagMarksOnlyTheWordsWrittenWithIt() {
        let khordam = "خوردم<v>"
        let chai = "چای<n>"
        let courseHints = buildLexemeHintMap([
            (tag: khordam, entry: LexemeIndexEntry(gloss: "I ate", pos: "verb", verbForm: "conjugated", lemma: "خوردن", romanizationIsAuthored: false)),
            (tag: chai, entry: LexemeIndexEntry(gloss: "tea", pos: "noun", romanizationIsAuthored: false)),
        ])
        var focused = look(display: .native)
        focused.courseHints = courseHints
        let plan = planAnnotatedText("چای خوردم", scriptMode: .native, tags: [chai, khordam], look: focused, focusTag: khordam)
        XCTAssertEqual(plan.runs.filter { $0.isFocus }.map { $0.source }, ["خوردم"])
        let unfocused = planAnnotatedText("چای خوردم", scriptMode: .native, tags: [chai, khordam], look: focused)
        XCTAssertTrue(unfocused.runs.allSatisfy { !$0.isFocus })
    }

    func testBothDisplayIsRubyWithBlankReadingWhereNone() {
        let plan = planAnnotatedText("کتاب سلام", scriptMode: .native, tags: [], look: look(display: .both))
        XCTAssertEqual(plan.kind, .ruby)
        let words = plan.runs.filter { $0.isWord }
        XCTAssertEqual(words.map { $0.reading }, ["ketāb", ""])
        XCTAssertEqual(plan.runs.first(where: { $0.isGap })?.reading, nil)
    }

    func testRomanizedDisplaySubstitutesRomanizationAndIsLtr() {
        let plan = planAnnotatedText("کتاب من", scriptMode: .native, tags: [], look: look(display: .romanized))
        XCTAssertFalse(plan.rtl)
        XCTAssertEqual(plan.runs.filter { $0.isWord }.map { $0.text }, ["ketāb", "man"])
        XCTAssertEqual(plan.fontScale, 1)
    }

    func testVowelMarksOffStripsThemOnKeepsThem() {
        let marked = "کِتاب"
        let off = planAnnotatedText(marked, scriptMode: .native, tags: [], look: look(display: .native, vowelMarks: false))
        let on = planAnnotatedText(marked, scriptMode: .native, tags: [], look: look(display: .native, vowelMarks: true))
        XCTAssertEqual(off.runs.first?.text, "کتاب")
        XCTAssertEqual(on.runs.first?.text, marked)
    }

    func testCenteredOnlyForNativeText() {
        let native = planAnnotatedText("کتاب", scriptMode: .native, tags: [], look: look(display: .native, centered: true))
        let roman = planAnnotatedText("کتاب", scriptMode: .native, tags: [], look: look(display: .romanized, centered: true))
        XCTAssertTrue(native.centered)
        XCTAssertFalse(roman.centered)
    }

    func testSentenceRomanizationAuthoredBuiltAndHidden() {
        XCTAssertEqual(sentenceRomanizationLine("کتاب من", authored: "ketāb-e man", scriptMode: .native, tags: [], look: look(display: .native)), "ketāb-e man")
        XCTAssertEqual(sentenceRomanizationLine("کتاب من", authored: nil, scriptMode: .native, tags: [], look: look(display: .native)), "ketāb man")
        XCTAssertNil(sentenceRomanizationLine("کتاب من", authored: nil, scriptMode: .native, tags: [], look: look(display: .romanized)))
    }

    // MARK: flow geometry

    private func item(_ w: CGFloat, _ h: CGFloat, gap: Bool = false) -> WordFlowGeometry.Item {
        return WordFlowGeometry.Item(size: CGSize(width: w, height: h), isGap: gap)
    }

    func testFlowWrapsAndBottomAligns() {
        let items = [item(40, 30), item(40, 20), item(40, 30)]
        let frames = WordFlowGeometry.frames(items: items, width: 90, rtl: false, centered: false, lineSpacing: 2)
        XCTAssertEqual(frames[0], CGRect(x: 0, y: 0, width: 40, height: 30))
        XCTAssertEqual(frames[1], CGRect(x: 40, y: 10, width: 40, height: 20))
        XCTAssertEqual(frames[2], CGRect(x: 0, y: 32, width: 40, height: 30))
        XCTAssertEqual(WordFlowGeometry.height(of: frames), 62)
    }

    func testFlowRtlStartsAtRightEdge() {
        let frames = WordFlowGeometry.frames(items: [item(40, 20), item(30, 20)], width: 100, rtl: true, centered: false, lineSpacing: 0)
        XCTAssertEqual(frames[0].maxX, 100)
        XCTAssertEqual(frames[1].maxX, 60)
    }

    func testFlowCentersRow() {
        let frames = WordFlowGeometry.frames(items: [item(40, 20)], width: 100, rtl: false, centered: true, lineSpacing: 0)
        XCTAssertEqual(frames[0].minX, 30)
    }

    func testFlowDropsLeadingGapAndKeepsGapAtRowEnd() {
        let items = [item(10, 20, gap: true), item(60, 20), item(10, 20, gap: true), item(60, 20)]
        let frames = WordFlowGeometry.frames(items: items, width: 100, rtl: false, centered: false, lineSpacing: 0)
        XCTAssertEqual(frames[0], .zero)
        XCTAssertEqual(frames[1].minX, 0)
        XCTAssertEqual(frames[2].minX, 60)
        XCTAssertEqual(frames[3].minX, 0)
        XCTAssertEqual(frames[3].minY, 20)
    }

    func testFlowLongItemGetsItsOwnRow() {
        let frames = WordFlowGeometry.frames(items: [item(10, 10), item(200, 10)], width: 100, rtl: false, centered: false, lineSpacing: 0)
        XCTAssertEqual(frames[1].minY, 10)
        XCTAssertEqual(frames[1].minX, 0)
    }
}
