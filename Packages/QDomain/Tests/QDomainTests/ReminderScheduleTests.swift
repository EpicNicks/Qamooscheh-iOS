import XCTest
@testable import QDomain

final class ReminderScheduleTests: XCTestCase {
    private func calendar(_ zone: String) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: zone)!
        return c
    }

    private func date(_ s: String, _ zone: String) -> Date {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: zone)!
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.date(from: s)!
    }

    private func hm(_ d: Date, _ c: Calendar) -> String {
        let p = c.dateComponents([.month, .day, .hour, .minute], from: d)
        return String(format: "%02d-%02d %02d:%02d", p.month!, p.day!, p.hour!, p.minute!)
    }

    func testTodayIfStillAhead() {
        let c = calendar("America/New_York")
        let now = date("2026-03-02 08:00:00", "America/New_York")
        let next = nextReminderOccurrence(after: now, hour: 19, minute: 0, days: Set(1...7), calendar: c)
        XCTAssertEqual(next.map { hm($0, c) }, "03-02 19:00")
    }

    func testTomorrowIfPassedAndNilWithNoDays() {
        let c = calendar("America/New_York")
        let now = date("2026-03-02 20:00:00", "America/New_York")
        XCTAssertEqual(nextReminderOccurrence(after: now, hour: 19, minute: 0, days: Set(1...7), calendar: c).map { hm($0, c) }, "03-03 19:00")
        XCTAssertNil(nextReminderOccurrence(after: now, hour: 19, minute: 0, days: [], calendar: c))
    }

    func testOnlyPickedWeekdays() {
        let c = calendar("UTC")
        // 2026-03-02 is a Monday.
        let now = date("2026-03-02 12:00:00", "UTC")
        XCTAssertEqual(isoWeekday(now, calendar: c), 1)
        let next = nextReminderOccurrence(after: now, hour: 9, minute: 0, days: [3, 6], calendar: c)
        XCTAssertEqual(next.map { hm($0, c) }, "03-04 09:00")
        let weekly = nextReminderOccurrence(after: now, hour: 9, minute: 0, days: [1], calendar: c)
        XCTAssertEqual(weekly.map { hm($0, c) }, "03-09 09:00")
    }

    func testSpringForwardGapStillLandsOnTheDay() {
        let c = calendar("America/New_York")
        // 2026-03-08 02:30 does not exist in New York.
        let now = date("2026-03-08 00:10:00", "America/New_York")
        let next = nextReminderOccurrence(after: now, hour: 2, minute: 30, days: [7], calendar: c)
        XCTAssertNotNil(next)
        XCTAssertEqual(next.map { c.component(.day, from: $0) }, 8)
        XCTAssertGreaterThan(next!, now)
    }

    func testFallBackKeepsTheWallClockTime() {
        let c = calendar("America/New_York")
        let now = date("2026-11-01 00:10:00", "America/New_York")
        let next = nextReminderOccurrence(after: now, hour: 19, minute: 0, days: [7], calendar: c)
        XCTAssertEqual(next.map { hm($0, c) }, "11-01 19:00")
    }

    func testTravelUsesTheCurrentZone() {
        // The same instant is a different wall-clock day in Tokyo, so the next 08:00 differs.
        let now = date("2026-03-02 23:00:00", "America/New_York")
        let ny = calendar("America/New_York")
        let tokyo = calendar("Asia/Tokyo")
        XCTAssertEqual(nextReminderOccurrence(after: now, hour: 8, minute: 0, days: Set(1...7), calendar: ny).map { hm($0, ny) }, "03-03 08:00")
        XCTAssertEqual(nextReminderOccurrence(after: now, hour: 8, minute: 0, days: Set(1...7), calendar: tokyo).map { hm($0, tokyo) }, "03-04 08:00")
    }

    func testStreakNudgeAppliesOnlyWellBeforeTheNudge() {
        XCTAssertTrue(streakNudgeApplies(reminderHour: 19, reminderMinute: 0))
        XCTAssertFalse(streakNudgeApplies(reminderHour: 20, reminderMinute: 30))
        XCTAssertFalse(streakNudgeApplies(reminderHour: 21, reminderMinute: 0))
        XCTAssertTrue(streakNudgeApplies(reminderHour: 20, reminderMinute: 29))
    }

    func testNoParsleYetStartsWithStreakOrNot() {
        let r = dailyReminder(smartSuppression: true, practicedToday: false, xpToday: 0, goalXp: 50, streakDays: 12)
        XCTAssertEqual(r, .start(streakDays: 12))
        XCTAssertEqual(r?.text.title, "Time for today's practice")
        XCTAssertEqual(r?.text.body, "Keep your 12-day streak going.")
        XCTAssertEqual(DailyReminder.start(streakDays: 0).text.body, "A few minutes is all it takes.")
    }

    func testPracticedShortOfGoal() {
        let r = dailyReminder(smartSuppression: true, practicedToday: true, xpToday: 20, goalXp: 50, streakDays: 0)
        XCTAssertEqual(r, .goal(xpLeft: 30))
        XCTAssertEqual(r?.text.title, "You're 30 XP from today's goal")
        XCTAssertEqual(r?.text.body, "Another Parsle gets you there.")
        // XP alone counts as practiced.
        XCTAssertEqual(dailyReminder(smartSuppression: true, practicedToday: false, xpToday: 20, goalXp: 50, streakDays: 3), .goal(xpLeft: 30))
    }

    func testUnreadableXpOrGoalIsPartway() {
        let practiced = dailyReminder(smartSuppression: true, practicedToday: true, xpToday: nil, goalXp: 50, streakDays: 0)
        XCTAssertEqual(practiced, .goal(xpLeft: nil))
        XCTAssertEqual(practiced?.text.title, "You're partway to today's goal")
        XCTAssertEqual(dailyReminder(smartSuppression: true, practicedToday: true, xpToday: 20, goalXp: nil, streakDays: 0), .goal(xpLeft: nil))
    }

    func testGoalMetSuppressesOnlyWithSmartSuppression() {
        XCTAssertNil(dailyReminder(smartSuppression: true, practicedToday: true, xpToday: 50, goalXp: 50, streakDays: 4))
        let on = dailyReminder(smartSuppression: false, practicedToday: true, xpToday: 60, goalXp: 50, streakDays: 4)
        XCTAssertEqual(on, .keepGoing)
        XCTAssertEqual(on?.text.title, "Today's goal is done")
        XCTAssertEqual(on?.text.body, "On a roll? Another Parsle keeps it going.")
    }

    func testPracticedButGoalUnmetStillNudges() {
        XCTAssertNotNil(dailyReminder(smartSuppression: true, practicedToday: true, xpToday: 10, goalXp: 50, streakDays: 4))
    }

    func testUnreadableGoalIsNeverMet() {
        XCTAssertEqual(dailyReminder(smartSuppression: true, practicedToday: false, xpToday: 500, goalXp: nil, streakDays: 0), .goal(xpLeft: nil))
        XCTAssertEqual(dailyReminder(smartSuppression: true, practicedToday: false, xpToday: nil, goalXp: 50, streakDays: 0), .start(streakDays: 0))
        XCTAssertEqual(dailyReminder(smartSuppression: true, practicedToday: false, xpToday: 0, goalXp: 0, streakDays: 0), .start(streakDays: 0))
    }

    func testBackoff() {
        XCTAssertEqual(backoffStep(ignoredInARow: 6, epochDay: 1), .send)
        XCTAssertEqual(backoffStep(ignoredInARow: 7, epochDay: 1), .skip)
        XCTAssertEqual(backoffStep(ignoredInARow: 7, epochDay: 2), .send)
        XCTAssertEqual(backoffStep(ignoredInARow: 13, epochDay: 3), .skip)
        XCTAssertEqual(backoffStep(ignoredInARow: 14, epochDay: 2), .stop)
    }

    func testEpochDay() {
        XCTAssertEqual(epochDay(of: date("1970-01-02 12:00:00", "UTC"), calendar: calendar("UTC")), 1)
        // Late evening in New York is already the next UTC day, but its own calendar day counts.
        XCTAssertEqual(epochDay(of: date("1970-01-02 22:00:00", "America/New_York"), calendar: calendar("America/New_York")), 1)
    }

    func testReenablePrompt() {
        let day: Int64 = 24 * 60 * 60 * 1000
        XCTAssertFalse(reenablePromptDue(enabled: true, disabledAt: 0, nextAskAt: nil, neverAsk: false, nowMillis: 2 * day))
        XCTAssertFalse(reenablePromptDue(enabled: false, disabledAt: nil, nextAskAt: nil, neverAsk: false, nowMillis: 2 * day))
        XCTAssertFalse(reenablePromptDue(enabled: false, disabledAt: 0, nextAskAt: nil, neverAsk: true, nowMillis: 2 * day))
        XCTAssertFalse(reenablePromptDue(enabled: false, disabledAt: 0, nextAskAt: nil, neverAsk: false, nowMillis: day - 1))
        XCTAssertTrue(reenablePromptDue(enabled: false, disabledAt: 0, nextAskAt: nil, neverAsk: false, nowMillis: day))
        XCTAssertFalse(reenablePromptDue(enabled: false, disabledAt: 0, nextAskAt: 3 * day, neverAsk: false, nowMillis: 2 * day))
        XCTAssertTrue(reenablePromptDue(enabled: false, disabledAt: 0, nextAskAt: 3 * day, neverAsk: false, nowMillis: 3 * day))
        XCTAssertEqual(nextReenableAsk(nowMillis: 5), 5 + day)
    }
}
