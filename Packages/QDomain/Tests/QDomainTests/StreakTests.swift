import XCTest
import QModel
@testable import QDomain

final class StreakTests: XCTestCase {
    // 2026-09-30T22:00:00Z
    private let now = Date(timeIntervalSince1970: 1_790_805_600)
    private let en = Locale(identifier: "en_US")

    private func streak(current: Int = 0, longest: Int = 0, practiced: Bool = false, paused: Bool = false, deadlineOffset: TimeInterval = 9 * 3600, dayStartHour: Int = 3, today: String = "2026-09-30", pauseDays: Int = 30, zone: String = "America/New_York") -> StreakResponse {
        return StreakResponse(currentStreakDays: current, longestStreakDays: longest, practicedToday: practiced, pausedToday: paused, pause: nil, pauseDaysAvailable: pauseDays, timeZone: zone, dayStartHour: dayStartHour, today: today, nextDayStartsAt: now.addingTimeInterval(deadlineOffset))
    }

    func testStreakDaysSingularForExactlyOne() {
        XCTAssertEqual(formatStreakDays(1), "1 day")
    }

    func testStreakDaysPluralForZeroAndMany() {
        XCTAssertEqual(formatStreakDays(0), "0 days")
        XCTAssertEqual(formatStreakDays(12), "12 days")
    }

    func testDescribeInvitesLearnerWithNoStreak() {
        XCTAssertEqual(describeStreak(streak(current: 0, longest: 4), now: now), "No streak yet. Finish a lesson today to start one.")
    }

    func testDescribeSaysSafeOncePracticed() {
        XCTAssertEqual(describeStreak(streak(current: 5, longest: 5, practiced: true), now: now), "5-day streak. You've practiced today.")
    }

    func testDescribeWarnsWithTimeLeftOnGraceDay() {
        XCTAssertEqual(describeStreak(streak(current: 5, longest: 9), now: now), "5-day streak. Practice in the next 9h 0m to keep it going.")
    }

    func testDescribeSaysPausedDayIsSafe() {
        XCTAssertEqual(describeStreak(streak(current: 5, longest: 9, paused: true), now: now), "5-day streak. Paused today, so it's safe.")
    }

    func testFormatTimeLeftShowsHoursMinutesThenFloor() {
        XCTAssertEqual(formatTimeLeft(now.addingTimeInterval(3 * 3600 + 12 * 60 + 30), now: now), "3h 12m")
        XCTAssertEqual(formatTimeLeft(now.addingTimeInterval(3600), now: now), "1h 0m")
        XCTAssertEqual(formatTimeLeft(now.addingTimeInterval(45 * 60), now: now), "45m")
        XCTAssertEqual(formatTimeLeft(now.addingTimeInterval(30), now: now), "under a minute")
        XCTAssertEqual(formatTimeLeft(now.addingTimeInterval(-3600), now: now), "under a minute")
    }

    func testAddDaysMovesAcrossMonthEnds() {
        XCTAssertEqual(addDays("2026-09-30", 1), "2026-10-01")
        XCTAssertEqual(addDays("2026-03-01", -1), "2026-02-28")
    }

    func testFormatStreakDayNeverShiftsTheDay() {
        XCTAssertEqual(formatStreakDay("2026-10-05", locale: en), "Mon, Oct 5")
    }

    func testFormatStreakDayRange() {
        XCTAssertEqual(formatStreakDayRange("2026-10-05", "2026-10-05", locale: en), "Mon, Oct 5")
        XCTAssertEqual(formatStreakDayRange("2026-10-05", "2026-10-09", locale: en), "Mon, Oct 5 \u{2013} Fri, Oct 9")
    }

    func testFormatDayStartShowsHourAsTime() {
        let shown = formatDayStart(streak(), locale: en).replacingOccurrences(of: "\u{202F}", with: " ")
        XCTAssertEqual(shown, "3:00 AM")
        XCTAssertEqual(formatDayStart(streak(dayStartHour: 0), locale: Locale(identifier: "de_DE")), "00:00")
    }

    func testMaxPauseLengthIsCapOrAllowanceNeverNegative() {
        XCTAssertEqual(maxPauseLength(streak(pauseDays: 30)), 14)
        XCTAssertEqual(maxPauseLength(streak(pauseDays: 3)), 3)
        XCTAssertEqual(maxPauseLength(streak(pauseDays: -1)), 0)
    }

    func testFormatZoneShowsUnderscoresAsSpaces() {
        XCTAssertEqual(formatZone("America/New_York"), "America/New York")
    }

    func testStreakTodayTakesServerValueElseWorksItOut() {
        XCTAssertEqual(streakToday(streak(today: "2026-10-04"), now: now), "2026-10-04")
        // 2026-10-04T05:00Z is 01:00 in New York; with a 3am day start it is still 3 Oct.
        let early = Date(timeIntervalSince1970: 1_791_090_000)
        XCTAssertEqual(streakToday(streak(today: "garbled"), now: early), "2026-10-03")
    }

    func testStreakZoneFallsBackToUtc() {
        XCTAssertEqual(streakZone(streak(zone: "not/a-zone")).identifier, "UTC")
        XCTAssertEqual(streakZone(streak(zone: "Asia/Tokyo")).identifier, "Asia/Tokyo")
    }
}
