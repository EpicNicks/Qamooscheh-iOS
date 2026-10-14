import Foundation
import QModel
import QNetwork

/// The two /v1/prefs calls. `PrefsRepository` is the production conformer.
public protocol PrefsAPI: Sendable {
    func fetch() async throws -> PrefsResponse
    func save(_ request: UpdatePrefsRequest) async throws -> PrefsResponse
}

/// GET/PUT /v1/prefs (PrefsContracts.cs). PUT is a full overwrite, so every
/// field is sent, including preferredVoice (absent resets the voice).
public struct PrefsRepository: PrefsAPI {
    private let client: ApiClient

    public init(client: ApiClient) {
        self.client = client
    }

    public func fetch() async throws -> PrefsResponse {
        try await client.send(.get, "/v1/prefs")
    }

    public func save(_ request: UpdatePrefsRequest) async throws -> PrefsResponse {
        try await client.send(.put, "/v1/prefs", body: request)
    }
}

extension PrefsResponse {
    public var updateRequest: UpdatePrefsRequest {
        UpdatePrefsRequest(
            scriptMode: scriptMode, register: register, autoplayAudio: autoplayAudio,
            keyboardMode: keyboardMode, desiredRetention: desiredRetention,
            dailyGoalXp: dailyGoalXp, preferredVoice: preferredVoice)
    }
}

public enum PrefsSyncOutcome: Equatable, Sendable {
    /// The local copy matches the server.
    case synced(PrefsResponse)
    /// Offline, or a newer local edit is still pending: the local copy stands.
    case offline(PrefsResponse?)
    /// The server permanently rejected the pending edit (4xx other than auth).
    /// The edit is parked (`rejectedEdit`), not retried; prefs carry the server
    /// copy when the follow-up pull succeeded, else the local copy.
    case rejected(status: Int, prefs: PrefsResponse?)
}

public enum PrefsSyncError: Error, Equatable, Sendable {
    /// An edit was attempted before prefs were ever loaded.
    case notLoaded
}

/// Server-synced prefs for one user and one course, cached on this device,
/// last-write-wins.
///
/// The server resolves prefs from the user's pinned course, so the cache and
/// any pending edit are keyed by user AND course: build one `PrefsSync` per
/// (user, course). An edit made on course A stays held under A and is never
/// sent while the caller syncs course B; it goes out when A is pinned again.
/// The caller must not run a sync across a course switch (the pin decides which
/// row the server writes).
///
/// An edit applies to the cache at once (optimistic) and is marked pending.
/// `sync()` pushes a pending edit as a full PUT; with nothing pending it pulls.
/// The server stores no edit time, so an unsent local edit always wins over a
/// pull. An edit made while a request is in flight is re-sent after that flight.
/// A permanently rejected edit is parked and the sync still pulls.
public actor PrefsSync {
    private struct Record: Codable {
        var prefs: PrefsResponse
        var pending: Bool
        var revision: Int
        var rejected: PrefsResponse?
    }

    private let userId: String
    private let courseCode: String
    private let api: PrefsAPI
    private let defaults: UserDefaults
    private var inFlight: Task<PrefsSyncOutcome, Error>?
    private var inFlightRevision = 0
    private var generation = 0
    private var applyHooks: [Int: @Sendable (PrefsResponse) -> Void] = [:]
    private var nextHookToken = 0

    public init(userId: String, courseCode: String, api: PrefsAPI, defaults: UserDefaults = .standard) {
        self.userId = userId
        self.courseCode = courseCode
        self.api = api
        self.defaults = defaults
    }

    /// The cached prefs, if ever loaded.
    public var prefs: PrefsResponse? { load()?.prefs }

    /// True while an edit has not reached the server.
    public var hasPendingEdit: Bool { load()?.pending ?? false }

    /// The last edit the server permanently rejected, until a later push lands
    /// or `dismissRejectedEdit()` is called.
    public var rejectedEdit: PrefsResponse? { load()?.rejected }

    /// Stored records that could not be decoded and were set aside (kept, not
    /// deleted, because they may hold an unsent edit).
    public var quarantinedRecordCount: Int {
        defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix(quarantinePrefix) }.count
    }

    /// Registers the applyPrefs hook, called with the merged prefs after load
    /// (at once, when prefs are cached), after each local edit and after each
    /// server merge (pull or accepted push). Several hooks may be registered
    /// (the instance is shared per user and course); keep the returned token
    /// to remove one with `removeApplyPrefs(_:)`.
    ///
    /// The edit hook fires optimistically, before the server accepts the edit,
    /// on purpose: the local copy is what the app shows and acts on. If the
    /// server rejects the edit the hooks fire again with the server copy when
    /// the follow-up pull succeeds.
    @discardableResult
    public func addApplyPrefs(_ hook: @escaping @Sendable (PrefsResponse) -> Void) -> Int {
        nextHookToken += 1
        let token = nextHookToken
        applyHooks[token] = hook
        if let current = load()?.prefs { hook(current) }
        return token
    }

    public func removeApplyPrefs(_ token: Int) {
        applyHooks.removeValue(forKey: token)
    }

    private func fireApply(_ prefs: PrefsResponse) {
        for hook in applyHooks.values { hook(prefs) }
    }

    public func dismissRejectedEdit() {
        guard var record = load() else { return }
        record.rejected = nil
        store(record)
    }

    /// Applies an edit locally, then tries to sync it. Throws `notLoaded` when
    /// there is nothing to edit yet.
    @discardableResult
    public func update(_ change: (inout PrefsResponse) -> Void) async throws -> PrefsSyncOutcome {
        guard var record = load() else { throw PrefsSyncError.notLoaded }
        change(&record.prefs)
        record.pending = true
        record.revision += 1
        store(record)
        fireApply(record.prefs)
        return try await sync()
    }

    /// Pushes a pending edit, otherwise pulls. Concurrent callers share one
    /// flight; a caller that joined a flight which pushed an older snapshot
    /// runs another sync so the newer edit is not lost.
    @discardableResult
    public func sync() async throws -> PrefsSyncOutcome {
        if let task = inFlight {
            let startRevision = inFlightRevision
            let result = try await task.value
            if let latest = load(), latest.pending, latest.revision > startRevision {
                return try await sync()
            }
            return result
        }
        let start = load()
        let gen = generation
        inFlightRevision = start?.revision ?? 0
        // The flight clears itself before it completes, so a waiter that
        // resumes never sees a finished flight still registered.
        let task = Task { () throws -> PrefsSyncOutcome in
            do {
                let result = try await self.runSync(start: start, generation: gen)
                await self.endFlight()
                return result
            } catch {
                await self.endFlight()
                throw error
            }
        }
        inFlight = task
        return try await task.value
    }

    private func endFlight() {
        inFlight = nil
    }

    /// Sign-out cleanup. Also invalidates any request still in flight so its
    /// response is not stored.
    public func clear() {
        generation += 1
        defaults.removeObject(forKey: key)
        for k in defaults.dictionaryRepresentation().keys where k.hasPrefix(quarantinePrefix) {
            defaults.removeObject(forKey: k)
        }
    }

    private static let keyRoot = "qamooscheh.serverPrefs."

    /// Removes every stored record (all courses, quarantined copies included)
    /// for one user, whether or not an instance exists this session. User ids
    /// are opaque ids without dots, so the "<root><userId>." prefix is exact.
    static func wipeStored(userId: String, defaults: UserDefaults) {
        let prefix = keyRoot + userId + "."
        for k in defaults.dictionaryRepresentation().keys where k.hasPrefix(prefix) {
            defaults.removeObject(forKey: k)
        }
    }

    private func runSync(start: Record?, generation gen: Int) async throws -> PrefsSyncOutcome {
        do {
            if let start = start, start.pending {
                do {
                    let saved = try await api.save(start.prefs.updateRequest)
                    guard gen == generation else { return .offline(nil) }
                    guard var latest = load() else { return .synced(saved) }
                    if latest.revision == start.revision {
                        latest.prefs = saved
                        latest.pending = false
                        latest.rejected = nil
                        store(latest)
                        fireApply(saved)
                        return .synced(saved)
                    }
                    // Edited during the PUT: keep the newer local copy pending.
                    return .offline(latest.prefs)
                } catch let error as ApiError where Self.isRejection(error) {
                    return await park(start: start, status: error.status, generation: gen)
                }
            }
            return try await pull(generation: gen)
        } catch {
            if Self.isTransient(error) { return .offline(load()?.prefs) }
            throw error
        }
    }

    private func pull(generation gen: Int) async throws -> PrefsSyncOutcome {
        let fetched = try await api.fetch()
        guard gen == generation else { return .offline(nil) }
        let current = load()
        if let current = current, current.pending { return .offline(current.prefs) }
        store(Record(prefs: fetched, pending: false, revision: (current?.revision ?? 0) + 1,
                     rejected: current?.rejected))
        fireApply(fetched)
        return .synced(fetched)
    }

    /// Parks the rejected edit (no longer pending) and still pulls.
    private func park(start: Record, status: Int, generation gen: Int) async -> PrefsSyncOutcome {
        guard gen == generation else { return .offline(nil) }
        guard var latest = load() else { return .rejected(status: status, prefs: nil) }
        // A newer edit made during the PUT stays pending (it will be retried
        // and parked on its own if still rejected).
        if latest.revision != start.revision { return .rejected(status: status, prefs: latest.prefs) }
        latest.pending = false
        latest.rejected = start.prefs
        store(latest)
        if let outcome = try? await pull(generation: gen), case .synced(let fetched) = outcome {
            return .rejected(status: status, prefs: fetched)
        }
        return .rejected(status: status, prefs: load()?.prefs)
    }

    /// 4xx other than auth, timeout and throttling: retrying cannot succeed.
    private static func isRejection(_ error: ApiError) -> Bool {
        error.status >= 400 && error.status < 500
            && error.status != 401 && error.status != 403
            && error.status != 408 && error.status != 429
    }

    private static func isTransient(_ error: Error) -> Bool {
        if error is URLError { return true }
        if let api = error as? ApiError {
            return api.status >= 500 || api.status == 408 || api.status == 429
        }
        return false
    }

    private var key: String { "\(Self.keyRoot)\(userId).\(courseCode)" }
    private var quarantinePrefix: String { key + ".corrupt." }

    private func load() -> Record? {
        guard let data = defaults.data(forKey: key) else { return nil }
        if let record = try? JSONDecoder().decode(Record.self, from: data) { return record }
        // Undecodable: it may hold an unsent edit, so set it aside instead of
        // letting the next pull overwrite it silently.
        defaults.set(data, forKey: quarantinePrefix + UUID().uuidString)
        defaults.removeObject(forKey: key)
        return nil
    }

    private func store(_ record: Record) {
        if let data = try? JSONEncoder().encode(record) {
            defaults.set(data, forKey: key)
        }
    }
}

/// One `PrefsSync` per (user, course), shared by every screen that asks for it.
public final class PrefsSyncProvider: @unchecked Sendable {
    private let api: PrefsAPI
    private let defaults: UserDefaults
    private let lock = NSLock()
    private var syncs: [String: PrefsSync] = [:]

    public init(api: PrefsAPI, defaults: UserDefaults = .standard) {
        self.api = api
        self.defaults = defaults
    }

    public func sync(userId: String, courseCode: String) -> PrefsSync {
        lock.lock()
        defer { lock.unlock() }
        let key = userId + "|" + courseCode
        if let existing = syncs[key] { return existing }
        let created = PrefsSync(userId: userId, courseCode: courseCode, api: api, defaults: defaults)
        syncs[key] = created
        return created
    }

    /// Sign-out: clears and forgets this user's instances.
    /// Also wipes stored records for courses never requested this session.
    public func clear(userId: String) async {
        let doomed = removeInstances(userId: userId)
        for entry in doomed { await entry.clear() }
        PrefsSync.wipeStored(userId: userId, defaults: defaults)
    }

    private func removeInstances(userId: String) -> [PrefsSync] {
        lock.lock()
        defer { lock.unlock() }
        let prefix = userId + "|"
        let doomed = syncs.filter { $0.key.hasPrefix(prefix) }
        for k in doomed.keys { syncs.removeValue(forKey: k) }
        return Array(doomed.values)
    }
}
