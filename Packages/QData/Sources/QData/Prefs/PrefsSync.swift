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
}

public enum PrefsSyncError: Error, Equatable, Sendable {
    /// An edit was attempted before prefs were ever loaded.
    case notLoaded
}

/// Server-synced prefs for one user, cached on this device, last-write-wins.
///
/// An edit applies to the cache at once (optimistic, like the web and Android)
/// and is marked pending. `sync()` pushes a pending edit as a full PUT; with
/// nothing pending it pulls. The server stores no edit time, so an unsent local
/// edit always wins over a pull. An edit made while a request is in flight
/// stays pending and goes out on the next sync.
public actor PrefsSync {
    private struct Record: Codable {
        var prefs: PrefsResponse
        var pending: Bool
        var revision: Int
    }

    private let userId: String
    private let api: PrefsAPI
    private let defaults: UserDefaults
    private var inFlight: Task<PrefsSyncOutcome, Error>?

    public init(userId: String, api: PrefsAPI, defaults: UserDefaults = .standard) {
        self.userId = userId
        self.api = api
        self.defaults = defaults
    }

    /// The cached prefs, if ever loaded.
    public var prefs: PrefsResponse? { load()?.prefs }

    /// True while an edit has not reached the server.
    public var hasPendingEdit: Bool { load()?.pending ?? false }

    /// Applies an edit locally, then tries to sync it. Throws `notLoaded` when
    /// there is nothing to edit yet; a permanent server rejection is rethrown
    /// (the edit stays pending locally).
    @discardableResult
    public func update(_ change: (inout PrefsResponse) -> Void) async throws -> PrefsSyncOutcome {
        guard var record = load() else { throw PrefsSyncError.notLoaded }
        change(&record.prefs)
        record.pending = true
        record.revision += 1
        store(record)
        return try await sync()
    }

    /// Pushes a pending edit, otherwise pulls. Concurrent callers share one flight.
    @discardableResult
    public func sync() async throws -> PrefsSyncOutcome {
        if let task = inFlight { return try await task.value }
        let task = Task { try await self.runSync() }
        inFlight = task
        defer { inFlight = nil }
        return try await task.value
    }

    /// Sign-out cleanup.
    public func clear() {
        defaults.removeObject(forKey: key)
    }

    private func runSync() async throws -> PrefsSyncOutcome {
        let start = load()
        do {
            if let start = start, start.pending {
                let saved = try await api.save(start.prefs.updateRequest)
                guard var latest = load() else { return .synced(saved) }
                if latest.revision == start.revision {
                    latest.prefs = saved
                    latest.pending = false
                    store(latest)
                    return .synced(saved)
                }
                // Edited during the PUT: keep the newer local copy pending.
                return .offline(latest.prefs)
            }
            let fetched = try await api.fetch()
            if let latest = load(), latest.pending { return .offline(latest.prefs) }
            store(Record(prefs: fetched, pending: false, revision: (load()?.revision ?? 0) + 1))
            return .synced(fetched)
        } catch {
            if Self.isTransient(error) { return .offline(load()?.prefs) }
            throw error
        }
    }

    private static func isTransient(_ error: Error) -> Bool {
        if error is URLError { return true }
        if let api = error as? ApiError {
            return api.status >= 500 || api.status == 408 || api.status == 429
        }
        return false
    }

    private var key: String { "qamooscheh.serverPrefs.\(userId)" }

    private func load() -> Record? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(Record.self, from: data)
    }

    private func store(_ record: Record) {
        if let data = try? JSONEncoder().encode(record) {
            defaults.set(data, forKey: key)
        }
    }
}
