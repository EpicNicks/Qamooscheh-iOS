import XCTest
@testable import QFeatures

private let utc: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}()

// 2026-03-02 is a Monday.
private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    utc.date(from: DateComponents(year: 2026, month: 3, day: day, hour: hour, minute: minute))!
}

private func settings(enabled: Bool = true, hour: Int = 19, nudge: Bool = true, smart: Bool = true, days: Set<Int> = Set(1...7)) -> ReminderSettings {
    var s = ReminderSettings()
    s.enabled = enabled
    s.hour = hour
    s.streakNudge = nudge
    s.smartSuppression = smart
    s.days = days
    return s
}

private final class FakeCenter: ReminderCenter, @unchecked Sendable {
    private let lock = NSLock()
    private var log: [String] = []
    private var scheduledAll: [PlannedReminder] = []
    var status: ReminderAuthorization = .granted

    var events: [String] { lock.lock(); defer { lock.unlock() }; return log }
    var scheduled: [PlannedReminder] { lock.lock(); defer { lock.unlock() }; return scheduledAll }

    func authorization() async -> ReminderAuthorization { status }
    func requestAuthorization() async -> Bool { status != .denied }
    func schedule(_ reminders: [PlannedReminder], calendar: Calendar) async {
        lock.lock(); defer { lock.unlock() }
        log.append("schedule \(reminders.count)")
        scheduledAll += reminders
    }
    func removeAllReminders() async {
        lock.lock(); defer { lock.unlock() }
        log.append("removeAll")
        scheduledAll = []
    }
}

final class ReminderPlannerTests: XCTestCase {
    func testDisabledOrNoDaysPlansNothing() {
        let now = at(2, 8)
        XCTAssertTrue(ReminderPlanner.plan(userId: "u", settings: settings(enabled: false), context: nil, now: now, calendar: utc).isEmpty)
        XCTAssertTrue(ReminderPlanner.plan(userId: "u", settings: settings(days: []), context: nil, now: now, calendar: utc).isEmpty)
    }

    func testPlansDailyAndStreakNudgeInTimeOrder() {
        let plan = ReminderPlanner.plan(
            userId: "u", settings: settings(), context: ReminderContext(streakDays: 5), now: at(2, 8), calendar: utc)
        XCTAssertEqual(plan.prefix(3).map { $0.kind }, [.daily, .streak, .daily])
        XCTAssertEqual(plan.first?.fireAt, at(2, 19))
        XCTAssertEqual(plan[1].fireAt, at(2, 21, 30))
        XCTAssertEqual(plan.first?.body, "Keep your 5-day streak going.")
        XCTAssertTrue(plan.allSatisfy { $0.userId == "u" && $0.id.hasPrefix("reminder.u.") })
        XCTAssertEqual(Set(plan.map { $0.id }).count, plan.count)
    }

    func testLateReminderTimeDropsTheNudge() {
        let plan = ReminderPlanner.plan(userId: "u", settings: settings(hour: 21), context: ReminderContext(streakDays: 5), now: at(2, 8), calendar: utc)
        XCTAssertTrue(plan.allSatisfy { $0.kind == .daily })
    }

    func testPracticedTodaySkipsTodaysDailyAndNudgeOnly() {
        let ctx = ReminderContext(practicedToday: true, streakDays: 5)
        let plan = ReminderPlanner.plan(userId: "u", settings: settings(), context: ctx, now: at(2, 8), calendar: utc)
        XCTAssertEqual(plan.first?.fireAt, at(3, 19))
        XCTAssertFalse(plan.contains { $0.fireAt == at(2, 21, 30) })
        XCTAssertTrue(plan.contains { $0.fireAt == at(3, 21, 30) })
    }

    func testSmartSuppressionOffStillSendsToday() {
        let ctx = ReminderContext(practicedToday: true, goalMetToday: true, streakDays: 5)
        let plan = ReminderPlanner.plan(userId: "u", settings: settings(smart: false), context: ctx, now: at(2, 8), calendar: utc)
        XCTAssertEqual(plan.first?.fireAt, at(2, 19))
    }

    func testGoalMetSuppressesTodaysDaily() {
        let plan = ReminderPlanner.plan(userId: "u", settings: settings(nudge: false), context: ReminderContext(goalMetToday: true), now: at(2, 8), calendar: utc)
        XCTAssertEqual(plan.first?.fireAt, at(3, 19))
    }

    func testNoStreakMeansNoNudge() {
        let plan = ReminderPlanner.plan(userId: "u", settings: settings(), context: ReminderContext(streakDays: 0), now: at(2, 8), calendar: utc)
        XCTAssertTrue(plan.allSatisfy { $0.kind == .daily })
    }

    func testBackoffThinsThenStopsWithOneLastNotice() {
        let plan = ReminderPlanner.plan(userId: "u", settings: settings(nudge: false), context: nil, now: at(2, 8), calendar: utc)
        // 7 sends, then every other day, then the stop notice after 14 sends.
        XCTAssertEqual(plan.last?.kind, .stop)
        XCTAssertEqual(plan.filter { $0.kind == .daily }.count, 14)
        XCTAssertEqual(plan.filter { $0.kind == .stop }.count, 1)
        let thinned = plan.filter { $0.kind == .daily }.dropFirst(7)
        let gaps = zip(thinned, thinned.dropFirst()).map { $1.fireAt.timeIntervalSince($0.fireAt) }
        XCTAssertTrue(gaps.allSatisfy { $0 >= 2 * 86_400 - 1 })
    }

    func testOnlyPickedDays() {
        let plan = ReminderPlanner.plan(userId: "u", settings: settings(nudge: false, days: [3]), context: nil, now: at(2, 8), calendar: utc)
        XCTAssertTrue(plan.allSatisfy { isoDay($0.fireAt) == 3 })
        XCTAssertEqual(plan.first?.fireAt, at(4, 19))
    }

    private func isoDay(_ d: Date) -> Int { (utc.component(.weekday, from: d) + 5) % 7 + 1 }
}

final class ReminderServiceTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        let name = "reminders-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func makeService(_ center: FakeCenter, defaults: UserDefaults) -> ReminderService {
        ReminderService(center: center, defaults: defaults, calendar: { utc }, now: { at(2, 8) })
    }

    func testSettingsAreStoredPerUser() async {
        let service = makeService(FakeCenter(), defaults: makeDefaults())
        var mine = settings()
        mine.days = [1, 3]
        await service.apply(mine, userId: "a")
        XCTAssertEqual(service.settings(userId: "a").days, [1, 3])
        XCTAssertTrue(service.settings(userId: "a").enabled)
        // Another learner never sees them.
        XCTAssertFalse(service.settings(userId: "b").enabled)
        XCTAssertEqual(service.settings(userId: "b"), ReminderSettings())
    }

    func testApplyReplacesThePlanAndPlansForThatUserOnly() async {
        let center = FakeCenter()
        let service = makeService(center, defaults: makeDefaults())
        await service.apply(settings(nudge: false), userId: "a")
        XCTAssertFalse(center.scheduled.isEmpty)
        XCTAssertTrue(center.scheduled.allSatisfy { $0.userId == "a" })
        XCTAssertEqual(center.events.first, "removeAll")
        // Another account refreshing wipes the first's notifications and has none of its own.
        await service.refresh(userId: "b", context: ReminderContext())
        XCTAssertTrue(center.scheduled.isEmpty)
    }

    func testCancelAllRemovesEverything() async {
        let center = FakeCenter()
        let service = makeService(center, defaults: makeDefaults())
        await service.apply(settings(), userId: "a")
        await service.cancelAll()
        XCTAssertTrue(center.scheduled.isEmpty)
        XCTAssertEqual(center.events.last, "removeAll")
    }

    func testDeniedPermissionSchedulesNothing() async {
        let center = FakeCenter()
        center.status = .denied
        let service = makeService(center, defaults: makeDefaults())
        await service.apply(settings(), userId: "a")
        XCTAssertTrue(center.scheduled.isEmpty)
        XCTAssertTrue(service.settings(userId: "a").enabled)
    }

    func testRefreshUsesTheContext() async {
        let center = FakeCenter()
        let service = makeService(center, defaults: makeDefaults())
        await service.apply(settings(nudge: false), userId: "a")
        XCTAssertEqual(center.scheduled.first?.fireAt, at(2, 19))
        await service.refresh(userId: "a", context: ReminderContext(practicedToday: true))
        XCTAssertEqual(center.scheduled.first?.fireAt, at(3, 19))
    }
}

final class ReminderPolicyTests: XCTestCase {
    func testOnlyTheSchedulingAccountSeesAReminder() {
        XCTAssertTrue(ReminderPolicy.shouldPresent(reminderUserId: "a", currentUserId: "a"))
        XCTAssertFalse(ReminderPolicy.shouldPresent(reminderUserId: "a", currentUserId: "b"))
        XCTAssertFalse(ReminderPolicy.shouldPresent(reminderUserId: "a", currentUserId: nil))
        XCTAssertFalse(ReminderPolicy.shouldPresent(reminderUserId: nil, currentUserId: "a"))
        XCTAssertFalse(ReminderPolicy.shouldPresent(reminderUserId: "", currentUserId: ""))
    }
}
