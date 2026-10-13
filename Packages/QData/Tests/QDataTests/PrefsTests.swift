import XCTest
import QModel
import QNetwork
@testable import QData

final class PrefsTests: XCTestCase {
    private let serverJson = "{\"scriptMode\":\"both\",\"register\":\"spoken\",\"autoplayAudio\":true,\"keyboardMode\":\"contextual\",\"desiredRetention\":0.9,\"dailyGoalXp\":50,\"preferredVoice\":\"v1\"}"

    private func makeDefaults() -> UserDefaults {
        let name = "prefs-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func makeAPI() -> PrefsRepository {
        let store = InMemorySessionStore(session: StoredSession(
            userId: "u", accessToken: "tok",
            accessTokenExpiresAt: Date().addingTimeInterval(3600), refreshToken: "r"))
        let client = ApiClient(
            baseURL: URL(string: "https://api.test")!, clientHeader: "ios/test",
            session: StubURLProtocol.makeSession(), store: store)
        return PrefsRepository(client: client)
    }

    private func bodyData(_ request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let n = stream.read(&buffer, maxLength: buffer.count)
            if n <= 0 { break }
            data.append(buffer, count: n)
        }
        return data
    }

    // MARK: Server prefs

    func testFetchAndSaveRoundTrip() async throws {
        let json = serverJson
        StubURLProtocol.install { _ in StubResponse(200, json) }
        let api = makeAPI()
        let fetched = try await api.fetch()
        XCTAssertEqual(fetched.scriptMode, .both)
        XCTAssertEqual(fetched.preferredVoice, "v1")
        let saved = try await api.save(fetched.updateRequest)
        XCTAssertEqual(saved, fetched)
        let requests = StubURLProtocol.requests
        XCTAssertEqual(requests[0].httpMethod, "GET")
        XCTAssertEqual(requests[1].httpMethod, "PUT")
        XCTAssertEqual(requests[1].url?.path, "/v1/prefs")
        let body = try JSONSerialization.jsonObject(with: bodyData(requests[1])) as? [String: Any]
        XCTAssertEqual(body?["dailyGoalXp"] as? Int, 50)
        XCTAssertEqual(body?["preferredVoice"] as? String, "v1")
        XCTAssertEqual(body?["scriptMode"] as? String, "both")
    }

    func testFirstSyncPullsAndPersists() async throws {
        let json = serverJson
        StubURLProtocol.install { _ in StubResponse(200, json) }
        let defaults = makeDefaults()
        let sync = PrefsSync(userId: "u", api: makeAPI(), defaults: defaults)
        let before = await sync.prefs
        XCTAssertNil(before)
        let outcome = try await sync.sync()
        guard case .synced(let prefs) = outcome else { return XCTFail("expected synced") }
        XCTAssertEqual(prefs.dailyGoalXp, 50)
        let reopened = PrefsSync(userId: "u", api: makeAPI(), defaults: defaults)
        let cached = await reopened.prefs
        XCTAssertEqual(cached?.dailyGoalXp, 50)
    }

    func testEditBeforeLoadThrows() async {
        StubURLProtocol.install { _ in StubResponse(500) }
        let sync = PrefsSync(userId: "u", api: makeAPI(), defaults: makeDefaults())
        do {
            try await sync.update { $0.dailyGoalXp = 10 }
            XCTFail("expected notLoaded")
        } catch {
            XCTAssertEqual(error as? PrefsSyncError, .notLoaded)
        }
    }

    func testOfflineEditThenSync() async throws {
        let json = serverJson
        StubURLProtocol.install { _ in StubResponse(200, json) }
        let defaults = makeDefaults()
        let sync = PrefsSync(userId: "u", api: makeAPI(), defaults: defaults)
        _ = try await sync.sync()

        // Offline: the edit lands locally and stays pending.
        StubURLProtocol.install { _ in StubResponse(failing: .notConnectedToInternet) }
        let offline = try await sync.update { $0.dailyGoalXp = 80 }
        guard case .offline(let local) = offline else { return XCTFail("expected offline") }
        XCTAssertEqual(local?.dailyGoalXp, 80)
        let pending = await sync.hasPendingEdit
        XCTAssertTrue(pending)

        // A fresh instance (app relaunch) still has the edit, and a pull does not clobber it.
        let relaunched = PrefsSync(userId: "u", api: makeAPI(), defaults: defaults)
        let relaunchedPending = await relaunched.hasPendingEdit
        XCTAssertTrue(relaunchedPending)

        // Back online: the pending edit goes out as a full PUT and the echo is kept.
        let echo = serverJson.replacingOccurrences(of: "\"dailyGoalXp\":50", with: "\"dailyGoalXp\":80")
        StubURLProtocol.install { _ in StubResponse(200, echo) }
        let outcome = try await relaunched.sync()
        guard case .synced(let synced) = outcome else { return XCTFail("expected synced") }
        XCTAssertEqual(synced.dailyGoalXp, 80)
        let requests = StubURLProtocol.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests[0].httpMethod, "PUT")
        let body = try JSONSerialization.jsonObject(with: bodyData(requests[0])) as? [String: Any]
        XCTAssertEqual(body?["dailyGoalXp"] as? Int, 80)
        XCTAssertEqual(body?["preferredVoice"] as? String, "v1")
        let stillPending = await relaunched.hasPendingEdit
        XCTAssertFalse(stillPending)
    }

    func testPullNeverOverwritesPendingEdit() async throws {
        let json = serverJson
        StubURLProtocol.install { _ in StubResponse(200, json) }
        let sync = PrefsSync(userId: "u", api: makeAPI(), defaults: makeDefaults())
        _ = try await sync.sync()
        StubURLProtocol.install { _ in StubResponse(503) }
        _ = try await sync.update { $0.autoplayAudio = false }
        let cached = await sync.prefs
        XCTAssertEqual(cached?.autoplayAudio, false)
        let pending = await sync.hasPendingEdit
        XCTAssertTrue(pending)
    }

    func testPermanentRejectionThrowsAndKeepsEdit() async throws {
        let json = serverJson
        StubURLProtocol.install { _ in StubResponse(200, json) }
        let sync = PrefsSync(userId: "u", api: makeAPI(), defaults: makeDefaults())
        _ = try await sync.sync()
        StubURLProtocol.install { _ in StubResponse(400, "{\"error\":\"bad\"}") }
        do {
            try await sync.update { $0.dailyGoalXp = 5 }
            XCTFail("expected a thrown ApiError")
        } catch {
            XCTAssertEqual((error as? ApiError)?.status, 400)
        }
        let pending = await sync.hasPendingEdit
        XCTAssertTrue(pending)
    }

    func testPrefsArePerUser() async throws {
        let json = serverJson
        StubURLProtocol.install { _ in StubResponse(200, json) }
        let defaults = makeDefaults()
        _ = try await PrefsSync(userId: "a", api: makeAPI(), defaults: defaults).sync()
        let other = await PrefsSync(userId: "b", api: makeAPI(), defaults: defaults).prefs
        XCTAssertNil(other)
    }

    // MARK: Local prefs

    func testLocalPrefsDefaultsFollowAndroid() {
        let prefs = LocalPrefsStore(defaults: makeDefaults()).current(userId: "u")
        XCTAssertEqual(prefs, LocalPrefs())
        XCTAssertEqual(prefs.persianInputMethod, .phonetic)
        XCTAssertEqual(prefs.japaneseInputMethod, .romaji)
        XCTAssertTrue(prefs.showTranslationHints)
        XCTAssertTrue(prefs.shuffleVoices)
        XCTAssertEqual(prefs.nativeTextAlign, .start)
        XCTAssertEqual(prefs.persianFlag, "pahlavi")
    }

    func testLocalPrefsRoundTripPerUserAndClear() {
        let store = LocalPrefsStore(defaults: makeDefaults())
        store.update(userId: "a") {
            $0.showFurigana = false
            $0.seenLessonOverlay.insert("word_bank")
            $0.fontFa = ScriptFontPref(family: "Vazirmatn", sizePct: 120)
            $0.lastGoalCelebrationDay = "2026-10-11"
        }
        let a = store.current(userId: "a")
        XCTAssertFalse(a.showFurigana)
        XCTAssertEqual(a.seenLessonOverlay, ["word_bank"])
        XCTAssertEqual(a.fontFa.family, "Vazirmatn")
        XCTAssertEqual(a.fontFa.sizePct, 120)
        XCTAssertEqual(a.lastGoalCelebrationDay, "2026-10-11")
        XCTAssertTrue(store.current(userId: "b").showFurigana)
        store.clear(userId: "a")
        XCTAssertEqual(store.current(userId: "a"), LocalPrefs())
    }

    func testLocalPrefsToleratesOldAndCorruptBlobs() throws {
        let defaults = makeDefaults()
        let store = LocalPrefsStore(defaults: defaults)
        defaults.set(Data("{\"showFurigana\":false,\"nativeTextAlign\":\"bogus\"}".utf8), forKey: "qamooscheh.localPrefs.u")
        let partial = store.current(userId: "u")
        XCTAssertFalse(partial.showFurigana)
        XCTAssertEqual(partial.nativeTextAlign, .start)
        XCTAssertTrue(partial.speakAnswers)
        defaults.set(Data("not json".utf8), forKey: "qamooscheh.localPrefs.u")
        XCTAssertEqual(store.current(userId: "u"), LocalPrefs())
    }
}
