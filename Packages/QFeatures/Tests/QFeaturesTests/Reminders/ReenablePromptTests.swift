import XCTest
import QData
@testable import QFeatures

private final class PromptCenter: ReminderCenter, @unchecked Sendable {
    var status: ReminderAuthorization
    var grants = true
    private(set) var requests = 0

    init(status: ReminderAuthorization) { self.status = status }

    func authorization() async -> ReminderAuthorization { status }
    func requestAuthorization() async -> Bool {
        requests += 1
        if grants { status = .granted } else { status = .denied }
        return grants
    }
    func schedule(_ reminders: [PlannedReminder], calendar: Calendar) async {}
    func removeAllReminders() async {}
}

private final class Clock: @unchecked Sendable {
    var millis: Int64 = 1_000_000_000_000
    var date: Date { Date(timeIntervalSince1970: Double(millis) / 1000) }
}

private let day: Int64 = 24 * 60 * 60 * 1000

@MainActor
final class ReenablePromptTests: XCTestCase {
    private func suite() -> UserDefaults {
        let name = "reenable-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func make(_ center: PromptCenter, clock: Clock, defaults: UserDefaults) -> (ReenablePromptModel, ReenablePromptStore, LocalPrefsStore, ReminderService) {
        let service = ReminderService(center: center, defaults: defaults)
        let store = ReenablePromptStore(defaults: defaults)
        let local = LocalPrefsStore(defaults: defaults)
        let model = ReenablePromptModel(userId: "u", service: service, localStore: local, store: store, now: { clock.date })
        return (model, store, local, service)
    }

    func testNothingToAskWhenRemindersWereNeverTurnedOff() {
        let clock = Clock()
        let (model, _, _, _) = make(PromptCenter(status: .granted), clock: clock, defaults: suite())
        model.check()
        XCTAssertFalse(model.isPresented)
    }

    func testAsksADayAfterTheyWereTurnedOff() {
        let clock = Clock()
        let (model, store, _, _) = make(PromptCenter(status: .granted), clock: clock, defaults: suite())
        store.recordDisabled(userId: "u", nowMillis: clock.millis)
        clock.millis += day - 1
        model.check()
        XCTAssertFalse(model.isPresented)
        clock.millis += 1
        model.check()
        XCTAssertTrue(model.isPresented)
    }

    func testTomorrowAsksAgainAfterADay() {
        let clock = Clock()
        let (model, store, _, _) = make(PromptCenter(status: .granted), clock: clock, defaults: suite())
        store.recordDisabled(userId: "u", nowMillis: clock.millis - 2 * day)
        model.check()
        XCTAssertTrue(model.isPresented)
        model.askTomorrow()
        XCTAssertFalse(model.isPresented)
        model.check()
        XCTAssertFalse(model.isPresented)
        clock.millis += day
        model.check()
        XCTAssertTrue(model.isPresented)
    }

    func testDontAskAgainStaysQuietEvenAfterTurningThemOffAgain() {
        let clock = Clock()
        let (model, store, _, _) = make(PromptCenter(status: .granted), clock: clock, defaults: suite())
        store.recordDisabled(userId: "u", nowMillis: clock.millis - 2 * day)
        model.check()
        model.dontAskAgain()
        store.recordEnabled(userId: "u")
        store.recordDisabled(userId: "u", nowMillis: clock.millis - 2 * day)
        model.check()
        XCTAssertFalse(model.isPresented)
    }

    func testTurnOnEnablesAndSchedulesWithTheChosenTime() async {
        let clock = Clock()
        let center = PromptCenter(status: .notDetermined)
        let (model, store, local, service) = make(center, clock: clock, defaults: suite())
        local.update(userId: "u") { $0.reminderHour = 7; $0.reminderMinute = 30 }
        store.recordDisabled(userId: "u", nowMillis: clock.millis - 2 * day)
        model.check()
        let outcome = await model.turnOn()
        XCTAssertEqual(outcome, .turnedOn)
        XCTAssertEqual(center.requests, 1)
        XCTAssertTrue(local.current(userId: "u").reminderEnabled)
        XCTAssertTrue(service.settings(userId: "u").enabled)
        XCTAssertEqual(service.settings(userId: "u").hour, 7)
        XCTAssertEqual(service.settings(userId: "u").minute, 30)
        XCTAssertNil(store.state(userId: "u").disabledAt)
        XCTAssertFalse(model.isPresented)
    }

    func testBlockedNotificationsSendTheLearnerToSettingsAndAskLater() async {
        let clock = Clock()
        let center = PromptCenter(status: .denied)
        let (model, store, local, _) = make(center, clock: clock, defaults: suite())
        store.recordDisabled(userId: "u", nowMillis: clock.millis - 2 * day)
        model.check()
        let outcome = await model.turnOn()
        XCTAssertEqual(outcome, .needsSettings)
        XCTAssertEqual(center.requests, 0)
        XCTAssertFalse(local.current(userId: "u").reminderEnabled)
        model.check()
        XCTAssertFalse(model.isPresented)
        clock.millis += day
        model.check()
        XCTAssertTrue(model.isPresented)
    }

    func testDecliningThePermissionPromptKeepsRemindersOff() async {
        let clock = Clock()
        let center = PromptCenter(status: .notDetermined)
        center.grants = false
        let (model, store, local, _) = make(center, clock: clock, defaults: suite())
        store.recordDisabled(userId: "u", nowMillis: clock.millis - 2 * day)
        model.check()
        let outcome = await model.turnOn()
        XCTAssertEqual(outcome, .declined)
        XCTAssertFalse(local.current(userId: "u").reminderEnabled)
    }

    func testStateIsPerUser() {
        let store = ReenablePromptStore(defaults: suite())
        store.recordDisabled(userId: "a", nowMillis: 5)
        store.neverAskAgain(userId: "a")
        XCTAssertEqual(store.state(userId: "b"), ReenablePromptStore.State())
        store.clear(userId: "a")
        XCTAssertEqual(store.state(userId: "a"), ReenablePromptStore.State())
    }

    func testSettingsRecordsWhenRemindersAreTurnedOffAndOn() {
        let defaults = suite()
        let store = ReenablePromptStore(defaults: defaults)
        let model = SettingsModel(
            userId: "u", courseCode: "fa",
            sync: PrefsSync(userId: "u", courseCode: "fa", api: OfflinePrefsAPI(), defaults: defaults),
            localStore: LocalPrefsStore(defaults: defaults), reenable: store)
        model.updateReminders { $0.enabled = true }
        XCTAssertNil(store.state(userId: "u").disabledAt)
        model.updateReminders { $0.enabled = false }
        XCTAssertNotNil(store.state(userId: "u").disabledAt)
        model.updateReminders { $0.enabled = true }
        XCTAssertNil(store.state(userId: "u").disabledAt)
    }
}
