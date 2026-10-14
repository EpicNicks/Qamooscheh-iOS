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
        let sync = PrefsSync(userId: "u", courseCode: "fa", api: makeAPI(), defaults: defaults)
        let before = await sync.prefs
        XCTAssertNil(before)
        let outcome = try await sync.sync()
        guard case .synced(let prefs) = outcome else { return XCTFail("expected synced") }
        XCTAssertEqual(prefs.dailyGoalXp, 50)
        let reopened = PrefsSync(userId: "u", courseCode: "fa", api: makeAPI(), defaults: defaults)
        let cached = await reopened.prefs
        XCTAssertEqual(cached?.dailyGoalXp, 50)
    }

    func testEditBeforeLoadThrows() async {
        StubURLProtocol.install { _ in StubResponse(500) }
        let sync = PrefsSync(userId: "u", courseCode: "fa", api: makeAPI(), defaults: makeDefaults())
        do {
            try await sync.update { $0.dailyGoalXp = 10 }
            XCTFail("expected notLoaded")
        } catch {
            XCTAssertEqual(error as? PrefsSyncError, .notLoaded)
        }
    }

    func testApplyPrefsHookFiresOnLoadEditAndMerge() async throws {
        let json = serverJson
        StubURLProtocol.install { _ in StubResponse(200, json) }
        let defaults = makeDefaults()
        let sync = PrefsSync(userId: "u", courseCode: "fa", api: makeAPI(), defaults: defaults)
        let seen = GoalLog()
        await sync.addApplyPrefs { seen.add($0.dailyGoalXp) }
        XCTAssertEqual(seen.values, [])
        _ = try await sync.sync()
        XCTAssertEqual(seen.values, [50])
        StubURLProtocol.install { _ in StubResponse(failing: .notConnectedToInternet) }
        _ = try await sync.update { $0.dailyGoalXp = 80 }
        XCTAssertEqual(seen.values, [50, 80])
        // Re-registering with cached prefs applies them at once (load).
        let again = GoalLog()
        let token = await sync.addApplyPrefs { again.add($0.dailyGoalXp) }
        XCTAssertEqual(again.values, [80])
        // Both hooks stay registered; removing one leaves the other.
        _ = try await sync.update { $0.dailyGoalXp = 90 }
        XCTAssertEqual(seen.values, [50, 80, 90])
        XCTAssertEqual(again.values, [80, 90])
        await sync.removeApplyPrefs(token)
        _ = try await sync.update { $0.dailyGoalXp = 95 }
        XCTAssertEqual(again.values, [80, 90])
        XCTAssertEqual(seen.values.last, 95)
    }

    func testProviderClearWipesStoredCoursesNotInstantiatedThisSession() async throws {
        let json = serverJson
        StubURLProtocol.install { _ in StubResponse(200, json) }
        let defaults = makeDefaults()
        // Previous session: pending edits stored for two courses and a corrupt copy.
        for course in ["fa", "ja"] {
            StubURLProtocol.install { _ in StubResponse(200, json) }
            let s = PrefsSync(userId: "u", courseCode: course, api: makeAPI(), defaults: defaults)
            _ = try await s.sync()
            StubURLProtocol.install { _ in StubResponse(failing: .notConnectedToInternet) }
            _ = try await s.update { $0.dailyGoalXp = 70 }
        }
        defaults.set(Data("x".utf8), forKey: "qamooscheh.serverPrefs.u.fa.corrupt.1")
        let other = PrefsSync(userId: "v", courseCode: "fa", api: makeAPI(), defaults: defaults)
        StubURLProtocol.install { _ in StubResponse(200, json) }
        _ = try await other.sync()
        // Relaunch: a new provider, no instance requested yet, then sign-out.
        let provider = PrefsSyncProvider(api: makeAPI(), defaults: defaults)
        await provider.clear(userId: "u")
        let keys = defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("qamooscheh.serverPrefs.u.") }
        XCTAssertTrue(keys.isEmpty)
        let fresh = PrefsSync(userId: "u", courseCode: "ja", api: makeAPI(), defaults: defaults)
        let freshPrefs = await fresh.prefs
        XCTAssertNil(freshPrefs)
        let otherPrefs = await other.prefs
        XCTAssertNotNil(otherPrefs)
    }

    func testProviderSharesOneSyncPerUserAndCourse() async {
        let provider = PrefsSyncProvider(api: makeAPI(), defaults: makeDefaults())
        let a1 = provider.sync(userId: "u", courseCode: "fa")
        let a2 = provider.sync(userId: "u", courseCode: "fa")
        let b = provider.sync(userId: "u", courseCode: "ja")
        let c = provider.sync(userId: "v", courseCode: "fa")
        XCTAssertTrue(a1 === a2)
        XCTAssertFalse(a1 === b)
        XCTAssertFalse(a1 === c)
        await provider.clear(userId: "u")
        XCTAssertFalse(a1 === provider.sync(userId: "u", courseCode: "fa"))
        XCTAssertTrue(c === provider.sync(userId: "v", courseCode: "fa"))
    }

    func testReminderPrefsPersistAndDecodeDefaults() {
        let store = LocalPrefsStore(defaults: makeDefaults())
        XCTAssertFalse(store.current(userId: "u").reminderEnabled)
        XCTAssertEqual(store.current(userId: "u").reminderHour, 19)
        store.update(userId: "u") { $0.reminderEnabled = true; $0.reminderHour = 7; $0.reminderMinute = 30 }
        let read = store.current(userId: "u")
        XCTAssertTrue(read.reminderEnabled)
        XCTAssertEqual(read.reminderHour, 7)
        XCTAssertEqual(read.reminderMinute, 30)
        let old = try? JSONDecoder().decode(LocalPrefs.self, from: Data("{\"reminderHour\":99}".utf8))
        XCTAssertEqual(old?.reminderHour, 23)
        XCTAssertEqual(old?.reminderMinute, 0)
    }

    func testOfflineEditThenSync() async throws {
        let json = serverJson
        StubURLProtocol.install { _ in StubResponse(200, json) }
        let defaults = makeDefaults()
        let sync = PrefsSync(userId: "u", courseCode: "fa", api: makeAPI(), defaults: defaults)
        _ = try await sync.sync()

        // Offline: the edit lands locally and stays pending.
        StubURLProtocol.install { _ in StubResponse(failing: .notConnectedToInternet) }
        let offline = try await sync.update { $0.dailyGoalXp = 80 }
        guard case .offline(let local) = offline else { return XCTFail("expected offline") }
        XCTAssertEqual(local?.dailyGoalXp, 80)
        let pending = await sync.hasPendingEdit
        XCTAssertTrue(pending)

        // A fresh instance (app relaunch) still has the edit, and a pull does not clobber it.
        let relaunched = PrefsSync(userId: "u", courseCode: "fa", api: makeAPI(), defaults: defaults)
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
        let sync = PrefsSync(userId: "u", courseCode: "fa", api: makeAPI(), defaults: makeDefaults())
        _ = try await sync.sync()
        StubURLProtocol.install { _ in StubResponse(503) }
        _ = try await sync.update { $0.autoplayAudio = false }
        let cached = await sync.prefs
        XCTAssertEqual(cached?.autoplayAudio, false)
        let pending = await sync.hasPendingEdit
        XCTAssertTrue(pending)
    }

    func testPermanentRejectionParksEditAndPulls() async throws {
        let json = serverJson
        StubURLProtocol.install { _ in StubResponse(200, json) }
        let sync = PrefsSync(userId: "u", courseCode: "fa", api: makeAPI(), defaults: makeDefaults())
        _ = try await sync.sync()
        StubURLProtocol.install { request in
            request.httpMethod == "PUT" ? StubResponse(400, "{\"error\":\"bad\"}") : StubResponse(200, json)
        }
        let outcome = try await sync.update { $0.dailyGoalXp = 5 }
        guard case .rejected(let status, let prefs) = outcome else { return XCTFail("expected rejected") }
        XCTAssertEqual(status, 400)
        XCTAssertEqual(prefs?.dailyGoalXp, 50)
        let pending = await sync.hasPendingEdit
        XCTAssertFalse(pending)
        let parked = await sync.rejectedEdit
        XCTAssertEqual(parked?.dailyGoalXp, 5)
        let cached = await sync.prefs
        XCTAssertEqual(cached?.dailyGoalXp, 50)
        let methods = StubURLProtocol.requests.map { $0.httpMethod ?? "" }
        XCTAssertEqual(methods, ["PUT", "GET"])
        // Not wedged: the next sync is a plain pull.
        let next = try await sync.sync()
        guard case .synced = next else { return XCTFail("expected synced") }
    }

    func testAuthRejectionStaysPendingAndThrows() async throws {
        let json = serverJson
        StubURLProtocol.install { _ in StubResponse(200, json) }
        let sync = PrefsSync(userId: "u", courseCode: "fa", api: makeAPI(), defaults: makeDefaults())
        _ = try await sync.sync()
        StubURLProtocol.install { _ in StubResponse(403, "{\"error\":\"no\"}") }
        do {
            try await sync.update { $0.dailyGoalXp = 5 }
            XCTFail("expected a thrown ApiError")
        } catch {
            XCTAssertEqual((error as? ApiError)?.status, 403)
        }
        let pending = await sync.hasPendingEdit
        XCTAssertTrue(pending)
    }

    func testEditsAreHeldPerCourse() async throws {
        let json = serverJson
        StubURLProtocol.install { _ in StubResponse(200, json) }
        let defaults = makeDefaults()
        let courseA = PrefsSync(userId: "u", courseCode: "fa", api: makeAPI(), defaults: defaults)
        _ = try await courseA.sync()
        StubURLProtocol.install { _ in StubResponse(failing: .notConnectedToInternet) }
        _ = try await courseA.update { $0.dailyGoalXp = 80 }

        // Course B has its own empty cache and never sees or sends A's edit.
        let other = serverJson.replacingOccurrences(of: "\"dailyGoalXp\":50", with: "\"dailyGoalXp\":20")
        StubURLProtocol.install { _ in StubResponse(200, other) }
        let courseB = PrefsSync(userId: "u", courseCode: "ja", api: makeAPI(), defaults: defaults)
        let beforeB = await courseB.prefs
        XCTAssertNil(beforeB)
        _ = try await courseB.sync()
        let bPrefs = await courseB.prefs
        XCTAssertEqual(bPrefs?.dailyGoalXp, 20)
        XCTAssertEqual(StubURLProtocol.requests.map { $0.httpMethod ?? "" }, ["GET"])
        let bPending = await courseB.hasPendingEdit
        XCTAssertFalse(bPending)

        // A's edit is still held.
        let aPending = await courseA.hasPendingEdit
        let aPrefs = await courseA.prefs
        XCTAssertTrue(aPending)
        XCTAssertEqual(aPrefs?.dailyGoalXp, 80)
    }

    func testEditDuringInFlightSyncIsResent() async throws {
        let json = serverJson
        // PUT echoes its body; GET returns the server copy.
        StubURLProtocol.install { request in
            request.httpMethod == "PUT"
                ? StubResponse(200, String(decoding: readBody(request), as: UTF8.self))
                : StubResponse(200, json)
        }
        let gate = Gate()
        let api = GatedAPI(gate: gate, inner: makeAPI())
        let sync = PrefsSync(userId: "u", courseCode: "fa", api: api, defaults: makeDefaults())
        _ = try await sync.sync()
        let first = Task { try await sync.update { $0.dailyGoalXp = 70 } }
        await gate.waitUntilEntered()
        let second = Task { try await sync.update { $0.autoplayAudio = false } }
        // Let the second edit land locally and join the flight before releasing.
        try await Task.sleep(nanoseconds: 200_000_000)
        await gate.open()
        _ = try await first.value
        let outcome = try await second.value
        guard case .synced(let final) = outcome else { return XCTFail("expected synced") }
        XCTAssertEqual(final.dailyGoalXp, 70)
        XCTAssertEqual(final.autoplayAudio, false)
        let pending = await sync.hasPendingEdit
        XCTAssertFalse(pending)
        let saves = await api.saveCount
        XCTAssertEqual(saves, 2)
    }

    func testSignOutDuringPullDoesNotRestore() async throws {
        let json = serverJson
        StubURLProtocol.install { _ in StubResponse(200, json) }
        let gate = Gate()
        let api = GatedAPI(gate: gate, inner: makeAPI(), gateFetch: true)
        let sync = PrefsSync(userId: "u", courseCode: "fa", api: api, defaults: makeDefaults())
        let pull = Task { try await sync.sync() }
        await gate.waitUntilEntered()
        await sync.clear()
        await gate.open()
        _ = try await pull.value
        let cached = await sync.prefs
        XCTAssertNil(cached)
    }

    func testCorruptRecordIsQuarantinedNotDropped() async throws {
        let json = serverJson
        StubURLProtocol.install { _ in StubResponse(200, json) }
        let defaults = makeDefaults()
        defaults.set(Data("garbage".utf8), forKey: "qamooscheh.serverPrefs.u.fa")
        let sync = PrefsSync(userId: "u", courseCode: "fa", api: makeAPI(), defaults: defaults)
        let before = await sync.prefs
        XCTAssertNil(before)
        let count = await sync.quarantinedRecordCount
        XCTAssertEqual(count, 1)
        let kept = defaults.dictionaryRepresentation().keys.contains { $0.hasPrefix("qamooscheh.serverPrefs.u.fa.corrupt.") }
        XCTAssertTrue(kept)
        // A pull then proceeds normally and leaves the quarantined copy alone.
        _ = try await sync.sync()
        let afterCount = await sync.quarantinedRecordCount
        XCTAssertEqual(afterCount, 1)
        await sync.clear()
        let cleared = await sync.quarantinedRecordCount
        XCTAssertEqual(cleared, 0)
    }

    func testPrefsArePerUser() async throws {
        let json = serverJson
        StubURLProtocol.install { _ in StubResponse(200, json) }
        let defaults = makeDefaults()
        _ = try await PrefsSync(userId: "a", courseCode: "fa", api: makeAPI(), defaults: defaults).sync()
        let other = await PrefsSync(userId: "b", courseCode: "fa", api: makeAPI(), defaults: defaults).prefs
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

func readBody(_ request: URLRequest) -> Data {
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

/// Suspends the first gated call until `open()`.
actor Gate {
    private var entered = false
    private var isOpen = false
    private var enteredWaiters: [CheckedContinuation<Void, Never>] = []
    private var openWaiters: [CheckedContinuation<Void, Never>] = []

    func enter() async {
        entered = true
        for w in enteredWaiters { w.resume() }
        enteredWaiters = []
        if isOpen { return }
        await withCheckedContinuation { openWaiters.append($0) }
    }

    func waitUntilEntered() async {
        if entered { return }
        await withCheckedContinuation { enteredWaiters.append($0) }
    }

    func open() {
        isOpen = true
        for w in openWaiters { w.resume() }
        openWaiters = []
    }
}

/// Wraps a PrefsAPI, holding the first save (or first fetch) at the gate after
/// the inner call returned.
actor GatedAPI: PrefsAPI {
    private let gate: Gate
    private let inner: PrefsAPI
    private let gateFetch: Bool
    private var gated = false
    private(set) var saveCount = 0

    init(gate: Gate, inner: PrefsAPI, gateFetch: Bool = false) {
        self.gate = gate
        self.inner = inner
        self.gateFetch = gateFetch
    }

    func fetch() async throws -> PrefsResponse {
        let result = try await inner.fetch()
        if gateFetch && !gated {
            gated = true
            await gate.enter()
        }
        return result
    }

    func save(_ request: UpdatePrefsRequest) async throws -> PrefsResponse {
        saveCount += 1
        let result = try await inner.save(request)
        if !gateFetch && !gated {
            gated = true
            await gate.enter()
        }
        return result
    }
}

private final class GoalLog: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [Int] = []
    func add(_ v: Int) { lock.lock(); items.append(v); lock.unlock() }
    var values: [Int] { lock.lock(); defer { lock.unlock() }; return items }
}
