import XCTest
import QModel
import QData
@testable import QFeatures

final class SettingsLogicTests: XCTestCase {
    func testRetentionPresetMatch() {
        XCTAssertEqual(matchRetentionPreset(0.9)?.label, "Balanced")
        XCTAssertEqual(matchRetentionPreset(0.903)?.label, "Balanced")
        XCTAssertNil(matchRetentionPreset(0.92))
    }

    func testSnaps() {
        XCTAssertEqual(snapRetention(0.9149), 0.91, accuracy: 0.0001)
        XCTAssertEqual(snapFontPercent(62), 75)
        XCTAssertEqual(snapFontPercent(112), 110)
        XCTAssertEqual(snapFontPercent(400), 150)
    }

    func testGoalInput() {
        XCTAssertEqual(sanitizedGoalInput("12a34567"), "1234")
        XCTAssertEqual(sanitizedGoalInput("abc"), "")
    }

    func testSamples() {
        XCTAssertEqual(scriptModeSample(mode: .native, nativeName: "N", romanizedName: "R"), "N")
        XCTAssertEqual(scriptModeSample(mode: .romanized, nativeName: "N", romanizedName: "R"), "R")
        XCTAssertEqual(scriptModeSample(mode: .both, nativeName: "N", romanizedName: "R"), "N (R)")
        XCTAssertFalse(keyboardSample(mode: .contextual).contains("\u{200C}"))
        XCTAssertEqual(keyboardSample(mode: .isolated).unicodeScalars.filter { $0.value == 0x200C }.count, 3)
    }

    func testNoticeMapping() {
        let prefs = PrefsResponse(scriptMode: .native, register: .both, autoplayAudio: true, keyboardMode: .contextual, desiredRetention: 0.9, dailyGoalXp: 500)
        XCTAssertEqual(settingsNotice(for: .synced(prefs)), .saved)
        XCTAssertEqual(settingsNotice(for: .offline(prefs)), .savedOffline)
        if case .rejected(let message) = settingsNotice(for: .rejected(status: 422, prefs: prefs)) {
            XCTAssertTrue(message.contains("422"))
        } else {
            XCTFail("expected rejected")
        }
    }

    func testStreakDayRoundTrip() {
        let date = streakDayDate("2026-10-12")
        XCTAssertNotNil(date)
        XCTAssertEqual(streakDayString(date ?? Date()), "2026-10-12")
        XCTAssertNil(streakDayDate("nope"))
    }
}
