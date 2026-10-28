import XCTest
import QModel
import QDomain
import QData
import QKeyboard
@testable import QFeatures

final class LessonScreenLogicTests: XCTestCase {
    private func response(_ outcome: SessionOutcome, completed: Bool?) -> SubmittedSessionResponse {
        SubmittedSessionResponse(submissionId: "s", outcome: outcome, cards: [], lessonCompleted: completed)
    }

    func testCanCheckTypeIn() {
        XCTAssertFalse(LessonScreenLogic.canCheck(typeIn: true, typed: "  ", keyboardPending: nil, tileAnswer: nil))
        XCTAssertTrue(LessonScreenLogic.canCheck(typeIn: true, typed: "a", keyboardPending: nil, tileAnswer: nil))
        XCTAssertTrue(LessonScreenLogic.canCheck(typeIn: true, typed: "", keyboardPending: "s", tileAnswer: nil))
        XCTAssertFalse(LessonScreenLogic.canCheck(typeIn: true, typed: "", keyboardPending: "", tileAnswer: nil))
    }

    func testCanCheckTiles() {
        XCTAssertFalse(LessonScreenLogic.canCheck(typeIn: false, typed: "x", keyboardPending: nil, tileAnswer: nil))
        XCTAssertTrue(LessonScreenLogic.canCheck(typeIn: false, typed: "", keyboardPending: nil, tileAnswer: "a b"))
    }

    func testSubmittableText() {
        XCTAssertNil(LessonScreenLogic.submittableText(typeIn: true, typed: " ", tileAnswer: "t"))
        XCTAssertEqual(LessonScreenLogic.submittableText(typeIn: true, typed: "hi", tileAnswer: nil), "hi")
        XCTAssertEqual(LessonScreenLogic.submittableText(typeIn: false, typed: "", tileAnswer: "t"), "t")
        XCTAssertNil(LessonScreenLogic.submittableText(typeIn: false, typed: "x", tileAnswer: nil))
    }

    func testCheckButtonLabel() {
        XCTAssertEqual(LessonScreenLogic.checkButtonLabel(isCheckpoint: false), "Check")
        XCTAssertEqual(LessonScreenLogic.checkButtonLabel(isCheckpoint: true), "Next")
    }

    func testIsTypeIn() {
        XCTAssertTrue(LessonScreenLogic.isTypeIn(.typeIn))
        XCTAssertTrue(LessonScreenLogic.isTypeIn(.speak))
        XCTAssertFalse(LessonScreenLogic.isTypeIn(.wordBank))
        XCTAssertFalse(LessonScreenLogic.isTypeIn(.match))
    }

    func testCaretAfterTap() {
        // A spot before the caret stays; a spot after it moves with the committed text.
        XCTAssertEqual(LessonScreenLogic.caretAfterTap(to: 1, oldCaret: 3, oldLength: 5, newLength: 6), 1)
        XCTAssertEqual(LessonScreenLogic.caretAfterTap(to: 4, oldCaret: 3, oldLength: 5, newLength: 6), 5)
        XCTAssertEqual(LessonScreenLogic.caretAfterTap(to: 40, oldCaret: 3, oldLength: 5, newLength: 6), 6)
        XCTAssertEqual(LessonScreenLogic.caretAfterTap(to: -2, oldCaret: 3, oldLength: 5, newLength: 5), 0)
    }

    func testCaretAfterArrow() {
        XCTAssertEqual(LessonScreenLogic.caretAfterArrow(caret: 2, length: 5, rightKey: true, rtl: false), 3)
        XCTAssertEqual(LessonScreenLogic.caretAfterArrow(caret: 2, length: 5, rightKey: true, rtl: true), 1)
        XCTAssertEqual(LessonScreenLogic.caretAfterArrow(caret: 0, length: 5, rightKey: false, rtl: false), 0)
        XCTAssertEqual(LessonScreenLogic.caretAfterArrow(caret: 5, length: 5, rightKey: true, rtl: false), 5)
    }

    func testEndKindPracticeAndEmpty() {
        XCTAssertEqual(LessonScreenLogic.endKind(results: [], locallyCompleted: nil, practice: false), .practice)
        XCTAssertEqual(LessonScreenLogic.endKind(results: [.queued], locallyCompleted: true, practice: true), .practice)
    }

    func testEndKindSavedUsesServerCompletion() {
        let end = LessonScreenLogic.endKind(results: [.submitted(response(.processed, completed: false))], locallyCompleted: true, practice: false)
        XCTAssertEqual(end, .saved(completed: false, alreadyRecorded: false))
    }

    func testEndKindSavedFallsBackToDeviceGuess() {
        let end = LessonScreenLogic.endKind(results: [.submitted(response(.processed, completed: nil))], locallyCompleted: true, practice: false)
        XCTAssertEqual(end, .saved(completed: true, alreadyRecorded: false))
    }

    func testEndKindAlreadyRecorded() {
        let end = LessonScreenLogic.endKind(results: [.submitted(response(.alreadyProcessed, completed: true))], locallyCompleted: nil, practice: false)
        XCTAssertEqual(end, .saved(completed: true, alreadyRecorded: true))
    }

    func testEndKindQueuedWhenAnySessionIsStillOffline() {
        let results: [LessonSubmitResult] = [.submitted(response(.processed, completed: true)), .queued]
        XCTAssertEqual(LessonScreenLogic.endKind(results: results, locallyCompleted: true, practice: false), .queued(completed: true))
        XCTAssertEqual(LessonScreenLogic.endKind(results: [.queuedPermanentFailure(status: 403, message: "no")], locallyCompleted: nil, practice: false), .queued(completed: nil))
    }

    func testEndKindRejected() {
        XCTAssertEqual(LessonScreenLogic.endKind(results: [.rejected(reason: "stale")], locallyCompleted: true, practice: false), .rejected(partial: false, reason: "stale"))
        let results: [LessonSubmitResult] = [.submitted(response(.processed, completed: true)), .rejected(reason: nil)]
        XCTAssertEqual(LessonScreenLogic.endKind(results: results, locallyCompleted: nil, practice: false), .rejected(partial: true, reason: nil))
    }

    func testSettingsRowsPersian() {
        var prefs = LocalPrefs()
        prefs.persianInputMethod = .phonetic
        XCTAssertEqual(
            LessonSettingsRows.rows(courseCode: "fa", prefs: prefs, hasServerPrefs: true),
            [.textMode, .textAlignment, .romanizationTips, .translationTips, .nativeTips, .vowelMarks, .sentenceRomanization, .font]
        )
        prefs.persianInputMethod = .layout
        XCTAssertTrue(LessonSettingsRows.rows(courseCode: "fa", prefs: prefs, hasServerPrefs: true).contains(.keyboardMode))
        XCTAssertFalse(LessonSettingsRows.rows(courseCode: "fa", prefs: prefs, hasServerPrefs: false).contains(.keyboardMode))
        XCTAssertFalse(LessonSettingsRows.rows(courseCode: "fa", prefs: prefs, hasServerPrefs: false).contains(.textMode))
    }

    func testSettingsRowsJapanese() {
        XCTAssertEqual(
            LessonSettingsRows.rows(courseCode: "ja", prefs: LocalPrefs(), hasServerPrefs: true),
            [.textMode, .furigana, .romanizationTips, .translationTips, .nativeTips, .font]
        )
    }

    func testFontGroupPersianOffersFamiliesAndGreysOutMissing() {
        var prefs = LocalPrefs()
        prefs.fontFa = ScriptFontPref(family: "Vazirmatn", sizePct: 120)
        let group = LessonSettingsRows.fontGroup(courseCode: "fa", prefs: prefs, isAvailable: { _ in false })
        XCTAssertEqual(group?.options.map { $0.label }, ["Default", "Vazirmatn"])
        XCTAssertEqual(group?.options.map { $0.available }, [true, false])
        XCTAssertEqual(group?.selectedFamily, "Vazirmatn")
        XCTAssertEqual(group?.sizePct, 120)
    }

    func testFontGroupUnknownStoredFamilyFallsBackToDefault() {
        var prefs = LocalPrefs()
        prefs.fontFa = ScriptFontPref(family: "Noto Naskh Arabic", sizePct: 100)
        XCTAssertNil(LessonSettingsRows.fontGroup(courseCode: "fa", prefs: prefs, isAvailable: { _ in true })?.selectedFamily)
    }

    func testFontGroupJapaneseIsSizeOnly() {
        let group = LessonSettingsRows.fontGroup(courseCode: "ja", prefs: LocalPrefs(), isAvailable: { _ in true })
        XCTAssertEqual(group?.options, [])
        XCTAssertEqual(group?.sizePct, 100)
    }

    func testSettingFontWritesTheSameStoredPrefAsSettings() {
        var next = LessonSettingsRows.settingFontFamily("Vazirmatn", courseCode: "fa", in: LocalPrefs())
        XCTAssertEqual(next.fontFa.family, "Vazirmatn")
        XCTAssertEqual(next.fontJa, ScriptFontPref())
        next = LessonSettingsRows.settingFontSize(122, courseCode: "fa", in: next)
        XCTAssertEqual(next.fontFa.sizePct, 120)
        XCTAssertEqual(LessonSettingsRows.settingFontSize(500, courseCode: "ja", in: LocalPrefs()).fontJa.sizePct, 150)
        XCTAssertEqual(LessonSettingsRows.settingFontSize(10, courseCode: "ja", in: LocalPrefs()).fontJa.sizePct, 75)
    }

    func testFontSizeReachesTheLessonTextLook() {
        var prefs = LocalPrefs()
        prefs.fontFa.sizePct = 130
        let look = LessonScreenLogic.textLook(prefs: prefs, serverPrefs: LessonServerPrefs(), courseCode: "fa", hints: [:])
        XCTAssertEqual(look.nativeScale, 1.3, accuracy: 0.001)
    }

    func testSettingsToggleRoundTrip() {
        let rows: [LessonSettingsRow] = [.furigana, .romanizationTips, .translationTips, .nativeTips, .vowelMarks, .sentenceRomanization]
        for row in rows {
            let off = LessonSettingsRows.setting(row, to: false, in: LocalPrefs())
            XCTAssertEqual(LessonSettingsRows.isOn(row, prefs: off), false, "\(row)")
            let on = LessonSettingsRows.setting(row, to: true, in: off)
            XCTAssertEqual(LessonSettingsRows.isOn(row, prefs: on), true, "\(row)")
        }
        XCTAssertNil(LessonSettingsRows.isOn(.textMode, prefs: LocalPrefs()))
        XCTAssertEqual(LessonSettingsRows.setting(.textAlignment, to: false, in: LocalPrefs()), LocalPrefs())
    }

    func testTextLookFollowsPrefs() {
        var prefs = LocalPrefs()
        prefs.showVowelMarks = false
        prefs.nativeTextAlign = .center
        prefs.fontFa = ScriptFontPref(family: nil, sizePct: 120)
        let look = LessonScreenLogic.textLook(prefs: prefs, serverPrefs: LessonServerPrefs(scriptMode: .both), courseCode: "fa", hints: [:])
        XCTAssertEqual(look.settings.display, .both)
        XCTAssertFalse(look.settings.vowelMarks)
        XCTAssertTrue(look.centerNative)
        XCTAssertEqual(Double(look.nativeScale), 1.2, accuracy: 0.001)
    }

    func testTextLookJapaneseFuriganaShowsBothInNativeMode() {
        var prefs = LocalPrefs()
        prefs.showFurigana = true
        XCTAssertEqual(LessonScreenLogic.textLook(prefs: prefs, serverPrefs: LessonServerPrefs(), courseCode: "ja", hints: [:]).settings.display, .both)
        prefs.showFurigana = false
        XCTAssertEqual(LessonScreenLogic.textLook(prefs: prefs, serverPrefs: LessonServerPrefs(), courseCode: "ja", hints: [:]).settings.display, .native)
    }

    func testInAppKeyboardChoice() {
        var prefs = LocalPrefs()
        XCTAssertTrue(LessonScreenLogic.usesInAppKeyboard(method: .persianPhonetic, prefs: prefs))
        XCTAssertFalse(LessonScreenLogic.usesInAppKeyboard(method: nil, prefs: prefs))
        prefs.deviceInputEnabled = true
        XCTAssertFalse(LessonScreenLogic.usesInAppKeyboard(method: .persianPhonetic, prefs: prefs))
    }
}
