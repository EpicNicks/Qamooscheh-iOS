import XCTest
import QModel
import QData
import QNetwork
@testable import QFeatures

private final class FakeAPI: PrefsAPI, @unchecked Sendable {
    var server = PrefsResponse(scriptMode: .native, register: .both, autoplayAudio: true, keyboardMode: .contextual, desiredRetention: 0.9, dailyGoalXp: 500)
    var failure: Error?
    var saved: [UpdatePrefsRequest] = []
    var duringSave: (@Sendable () async -> Void)?

    func fetch() async throws -> PrefsResponse {
        if let failure = failure { throw failure }
        return server
    }

    func save(_ request: UpdatePrefsRequest) async throws -> PrefsResponse {
        if let failure = failure { throw failure }
        if let hook = duringSave { await hook() }
        saved.append(request)
        server = PrefsResponse(
            scriptMode: request.scriptMode, register: request.register, autoplayAudio: request.autoplayAudio,
            keyboardMode: request.keyboardMode, desiredRetention: request.desiredRetention,
            dailyGoalXp: request.dailyGoalXp, preferredVoice: request.preferredVoice)
        return server
    }
}

private final class FakeScheduler: ReminderScheduling, @unchecked Sendable {
    var granted = true
    var settings = ReminderSettings()
    func current() -> ReminderSettings { settings }
    func requestPermission() async -> Bool { granted }
    func apply(_ settings: ReminderSettings) { self.settings = settings }
}

@MainActor
final class SettingsModelTests: XCTestCase {
    private func makeModel(api: FakeAPI, scheduler: FakeScheduler = FakeScheduler()) -> SettingsModel {
        let suite = UserDefaults(suiteName: "settings.tests." + UUID().uuidString)!
        return SettingsModel(
            userId: "u1", courseCode: "fa",
            sync: PrefsSync(userId: "u1", courseCode: "fa", api: api, defaults: suite),
            localStore: LocalPrefsStore(defaults: suite), scheduler: scheduler)
    }

    func testLoadThenSaveSends() async {
        let api = FakeAPI()
        let model = makeModel(api: api)
        await model.load()
        XCTAssertEqual(model.form?.dailyGoalXp, 500)
        model.edit { $0.dailyGoalXp = 1000 }
        await model.save()
        XCTAssertEqual(model.notice, .saved)
        XCTAssertEqual(api.saved.last?.dailyGoalXp, 1000)
    }

    func testOfflineLoadWithoutCacheShowsError() async {
        let api = FakeAPI()
        api.failure = URLError(.notConnectedToInternet)
        let model = makeModel(api: api)
        await model.load()
        XCTAssertNil(model.form)
        XCTAssertNotNil(model.loadError)
    }

    func testOfflineSaveKeepsEditAndSaysSo() async {
        let api = FakeAPI()
        let model = makeModel(api: api)
        await model.load()
        api.failure = URLError(.notConnectedToInternet)
        model.edit { $0.autoplayAudio = false }
        await model.save()
        XCTAssertEqual(model.notice, .savedOffline)
        XCTAssertEqual(model.form?.autoplayAudio, false)
    }

    func testEditClearsNoticeAndLocalPrefsPersist() async {
        let api = FakeAPI()
        let model = makeModel(api: api)
        await model.load()
        await model.save()
        XCTAssertEqual(model.notice, .saved)
        model.edit { $0.register = .written }
        XCTAssertNil(model.notice)
        model.updateLocal { $0.hapticsEnabled = false }
        XCTAssertFalse(model.local.hapticsEnabled)
    }

    func testRemindersNeedPermission() async {
        let scheduler = FakeScheduler()
        scheduler.granted = false
        let model = makeModel(api: FakeAPI(), scheduler: scheduler)
        await model.setRemindersEnabled(true)
        XCTAssertFalse(model.reminders.enabled)
        scheduler.granted = true
        await model.setRemindersEnabled(true)
        XCTAssertTrue(model.reminders.enabled)
        XCTAssertTrue(scheduler.settings.enabled)
    }

    func testRejectedSaveKeepsDraftAndShowsError() async {
        let api = FakeAPI()
        let model = makeModel(api: api)
        await model.load()
        api.failure = ApiError(status: 422, body: nil)
        model.edit { $0.dailyGoalXp = 9999 }
        await model.save()
        XCTAssertEqual(model.form?.dailyGoalXp, 9999)
        if case .rejected(let message)? = model.notice {
            XCTAssertTrue(message.contains("422"))
        } else {
            XCTFail("expected rejected notice")
        }
        // A reload must not replace the kept draft with the server copy.
        api.failure = nil
        await model.load()
        XCTAssertEqual(model.form?.dailyGoalXp, 9999)
    }

    func testDirtyLoadIsNotOverwritten() async {
        let api = FakeAPI()
        let model = makeModel(api: api)
        await model.load()
        model.edit { $0.dailyGoalXp = 2000 }
        await model.load()
        XCTAssertEqual(model.form?.dailyGoalXp, 2000)
    }

    func testEditDuringSaveStaysDirty() async {
        let api = FakeAPI()
        let model = makeModel(api: api)
        await model.load()
        model.edit { $0.dailyGoalXp = 1000 }
        api.duringSave = { await MainActor.run { model.edit { $0.autoplayAudio = false } } }
        await model.save()
        XCTAssertEqual(model.form?.autoplayAudio, false)
        XCTAssertNil(model.notice)
        api.duringSave = nil
        await model.load()
        XCTAssertEqual(model.form?.autoplayAudio, false)
        XCTAssertEqual(model.form?.dailyGoalXp, 1000)
    }

    func testThrownSaveSaysItWillSyncLater() async {
        let api = FakeAPI()
        let model = makeModel(api: api)
        await model.load()
        api.failure = ApiError(status: 401, body: nil)
        model.edit { $0.dailyGoalXp = 1500 }
        await model.save()
        if case .failed(let message)? = model.notice {
            XCTAssertTrue(message.contains("sync later"))
        } else {
            XCTFail("expected failed notice")
        }
        XCTAssertEqual(model.form?.dailyGoalXp, 1500)
    }
}
