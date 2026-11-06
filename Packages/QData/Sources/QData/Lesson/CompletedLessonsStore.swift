import Foundation

/// The device's copy of "which lessons has this learner completed", one file per user holding every
/// course's keys. Completions are never revoked, so the held set only grows: it takes the union of
/// the server's list (GET /v1/lessons/completed) and local completions recorded when a lesson was
/// queued offline. Offline, the path still shows its checkmarks and green edges (Android #132).
/// Writes go through one actor, so two merges can't lose each other's keys.
public actor CompletedLessonsStore {
    private let store: ContentFileStore

    public init(store: ContentFileStore) {
        self.store = store
    }

    /// Hex keeps any user id a valid store key.
    static func key(userId: String) -> String {
        "completed-lessons/" + userId.utf8.map { String(format: "%02x", $0) }.joined() + ".json"
    }

    /// Keys held for this user and course. A missing or unreadable file reads as empty.
    public func keys(userId: String, courseCode: String) -> Set<String> {
        ((try? load(userId: userId)) ?? [:])[courseCode] ?? []
    }

    /// Adds `keys` to the held set and returns the whole set. If the file can't be read nothing is
    /// written (a transient read error must not wipe the other courses) and the error is thrown.
    @discardableResult
    public func add(userId: String, courseCode: String, keys: Set<String>) throws -> Set<String> {
        var all = try load(userId: userId)
        let merged = (all[courseCode] ?? []).union(keys)
        if merged == (all[courseCode] ?? []) && all[courseCode] != nil { return merged }
        all[courseCode] = merged
        let encoded = all.mapValues { $0.sorted() }
        try store.write(try JSONEncoder().encode(encoded), to: CompletedLessonsStore.key(userId: userId))
        return merged
    }

    /// The completed keys to show: the server's list folded into what is held, or just what is held
    /// when the fetch fails (offline). Rethrows only when the fetch failed and nothing is held, so
    /// the caller keeps its own last value. With no user the fetch passes straight through.
    public func resolve(
        userId: String?, courseCode: String, fetch: @Sendable () async throws -> [String]
    ) async throws -> Set<String> {
        guard let userId, !userId.isEmpty else { return Set(try await fetch()) }
        do {
            let fetched = Set(try await fetch())
            return (try? add(userId: userId, courseCode: courseCode, keys: fetched))
                ?? fetched.union(keys(userId: userId, courseCode: courseCode))
        } catch {
            let held = keys(userId: userId, courseCode: courseCode)
            if held.isEmpty { throw error }
            return held
        }
    }

    /// A lesson finished and queued offline counts as completed here at once.
    public func recordLocalCompletion(userId: String, courseCode: String, skillKey: String) throws {
        try add(userId: userId, courseCode: courseCode, keys: [skillKey])
    }

    /// Sign-out / account removal.
    public func clear(userId: String) throws {
        try store.remove(CompletedLessonsStore.key(userId: userId))
    }

    private func load(userId: String) throws -> [String: Set<String>] {
        guard let data = try store.read(CompletedLessonsStore.key(userId: userId)) else { return [:] }
        // Unreadable bytes are replaced by the next successful add, like a missing file.
        guard let decoded = try? JSONDecoder().decode([String: [String]].self, from: data) else { return [:] }
        return decoded.mapValues { Set($0) }
    }
}
