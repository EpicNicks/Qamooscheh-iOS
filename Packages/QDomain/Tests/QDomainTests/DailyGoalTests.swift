import XCTest
import QModel
@testable import QDomain

final class DailyGoalTests: XCTestCase {
    func testFindsPresetAnExactXpValueMatches() {
        XCTAssertEqual(matchDailyGoalPreset(750), DailyGoalPreset(xp: 750, label: "Regular"))
    }

    func testReturnsNilForHandEnteredCustomValue() {
        XCTAssertNil(matchDailyGoalPreset(37))
    }

    func testPresetsAreSortedAscendingByXp() {
        let xps = dailyGoalPresets.map { $0.xp }
        XCTAssertEqual(xps, xps.sorted())
    }

    func testTotalXpAddsUpEveryDay() {
        let days = [
            ActivityDay(localDay: "2026-10-04", reviews: 12, xp: 40),
            ActivityDay(localDay: "2026-10-02", reviews: 3, xp: 10),
            ActivityDay(localDay: "2026-09-30", reviews: 0, xp: 0),
        ]
        XCTAssertEqual(totalXp(days), 50)
    }

    func testTotalXpIsZeroForNoActivity() {
        XCTAssertEqual(totalXp([]), 0)
    }

    func testXpTodayComesFromMatchingDayZeroWhenAbsent() {
        let days = [ActivityDay(localDay: "2026-09-30", reviews: 12, xp: 140), ActivityDay(localDay: "2026-09-29", reviews: 3, xp: 30)]
        XCTAssertEqual(xpToday(days, today: "2026-09-30"), 140)
        XCTAssertEqual(xpToday(days, today: "2026-10-01"), 0)
    }

    func testTodayLocalDayUsesInjectedCalendarZone() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        // 2026-10-01T02:00Z is still 30 Sep in New York.
        let now = Date(timeIntervalSince1970: 1_790_820_000)
        XCTAssertEqual(todayLocalDay(now: now, calendar: calendar), "2026-09-30")
    }

    func testTodayLocalDayIsGregorianForNonGregorianCalendars() {
        // 2026-10-12T12:00Z; Tehran, Bangkok and Tokyo are all still 12 Oct.
        let now = Date(timeIntervalSince1970: 1_791_806_400)
        let cases: [(Calendar.Identifier, String)] = [
            (.persian, "Asia/Tehran"),
            (.buddhist, "Asia/Bangkok"),
            (.japanese, "Asia/Tokyo"),
        ]
        for (identifier, zone) in cases {
            var calendar = Calendar(identifier: identifier)
            calendar.timeZone = TimeZone(identifier: zone)!
            XCTAssertEqual(todayLocalDay(now: now, calendar: calendar), "2026-10-12", "\(identifier)")
        }
    }

    func testTodayLocalDayNonGregorianCalendarKeepsInjectedZone() {
        // 2026-10-11T22:00Z is already 12 Oct in Tokyo.
        let now = Date(timeIntervalSince1970: 1_791_756_000)
        var calendar = Calendar(identifier: .japanese)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        XCTAssertEqual(todayLocalDay(now: now, calendar: calendar), "2026-10-12")
    }
}
