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

private final class StubPreviewer: VoicePreviewing {
    var hasVoice = true
    var played: [String] = []
    func preview(text: String, languageTag: String) -> Bool {
        played.append(text + "|" + languageTag)
        return hasVoice
    }
    func stop() {}
}

private struct SignOutFailure: Error {}

@MainActor
final class SettingsAccountVoiceTests: XCTestCase {
    private func makeModel(
        voices: [SettingsVoice] = [], accountName: String? = nil,
        signOut: (() async throws -> Void)? = nil, previewer: VoicePreviewing? = nil
    ) -> SettingsModel {
        let suite = UserDefaults(suiteName: "settings.tests." + UUID().uuidString)!
        return SettingsModel(
            userId: "u1", courseCode: "fa",
            sync: PrefsSync(userId: "u1", courseCode: "fa", api: OfflinePrefsAPI(), defaults: suite),
            localStore: LocalPrefsStore(defaults: suite), voices: voices,
            accountName: accountName, signOut: signOut, previewer: previewer)
    }

    func testSignOutCallsClosure() async {
        var calls = 0
        let model = makeModel(accountName: "a@b.c", signOut: { calls += 1 })
        XCTAssertTrue(model.canSignOut)
        XCTAssertEqual(model.accountName, "a@b.c")
        await model.signOut()
        XCTAssertEqual(calls, 1)
        XCTAssertFalse(model.signingOut)
        XCTAssertNil(model.signOutError)
    }

    func testSignOutFailureShowsError() async {
        let model = makeModel(signOut: { throw SignOutFailure() })
        await model.signOut()
        XCTAssertNotNil(model.signOutError)
        XCTAssertFalse(model.signingOut)
    }

    func testNoSignOutClosureHidesAccount() async {
        let model = makeModel()
        XCTAssertFalse(model.canSignOut)
        await model.signOut()
        XCTAssertNil(model.signOutError)
    }

    func testPreviewSpeaksSample() {
        let previewer = StubPreviewer()
        let voice = SettingsVoice(id: "v1", label: "One", sampleText: "Salam", sampleLanguage: "fa-IR")
        let model = makeModel(voices: [voice], previewer: previewer)
        model.previewVoice(voice)
        XCTAssertEqual(previewer.played, ["Salam|fa-IR"])
        XCTAssertNil(model.previewNotice)
    }

    func testPreviewWithoutDeviceVoiceSaysSo() {
        let previewer = StubPreviewer()
        previewer.hasVoice = false
        let voice = SettingsVoice(id: "v1", label: "One", sampleText: "Salam", sampleLanguage: "fa-IR")
        let model = makeModel(voices: [voice], previewer: previewer)
        model.previewVoice(voice)
        XCTAssertNotNil(model.previewNotice)
    }

    func testVoiceWithoutSampleCannotPreview() {
        let previewer = StubPreviewer()
        let voice = SettingsVoice(id: "v1", label: "One")
        XCTAssertFalse(voice.canPreview)
        let model = makeModel(voices: [voice], previewer: previewer)
        model.previewVoice(voice)
        XCTAssertTrue(previewer.played.isEmpty)
    }
}
