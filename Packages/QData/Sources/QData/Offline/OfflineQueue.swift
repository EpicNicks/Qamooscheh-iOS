import Foundation
import QModel

/// One queued lesson submission plus its retry metadata. `session` is exactly
/// what will be sent (API_SPEC.md section 7/8); it carries its own
/// submissionId/occurredAt/courseVersion/courseCode, so a delayed batched
/// flush is safe to retry.
public struct QueuedSession: Codable, Equatable, Sendable {
    public var submissionId: String
    public var session: SubmittedSession
    public var queuedAtMillis: Int64
    public var attempts: Int
    /// Earliest time (epoch ms) a flush should retry this item; nil = now.
    public var nextEligibleAtMillis: Int64?
    public var lastError: String?
    /// Set when the server rejected the session. Kept, never dropped, so it can be surfaced.
    public var rejectionReason: String?

    public init(session: SubmittedSession, queuedAtMillis: Int64, attempts: Int = 0, nextEligibleAtMillis: Int64? = nil, lastError: String? = nil, rejectionReason: String? = nil) {
        self.submissionId = session.submissionId
        self.session = session
        self.queuedAtMillis = queuedAtMillis
        self.attempts = attempts
        self.nextEligibleAtMillis = nextEligibleAtMillis
        self.lastError = lastError
        self.rejectionReason = rejectionReason
    }

    private enum CodingKeys: String, CodingKey {
        case submissionId, session, queuedAtMillis, attempts, nextEligibleAtMillis, lastError, rejectionReason
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        submissionId = try c.decode(String.self, forKey: .submissionId)
        session = try c.decode(SubmittedSession.self, forKey: .session)
        queuedAtMillis = try c.decodeIfPresent(Int64.self, forKey: .queuedAtMillis) ?? 0
        attempts = try c.decodeIfPresent(Int.self, forKey: .attempts) ?? 0
        nextEligibleAtMillis = try c.decodeIfPresent(Int64.self, forKey: .nextEligibleAtMillis)
        lastError = try c.decodeIfPresent(String.self, forKey: .lastError)
        rejectionReason = try c.decodeIfPresent(String.self, forKey: .rejectionReason)
    }
}

/// Durable per-user FIFO queue of session submissions that could not reach the
/// server yet. Ports web offlineQueue.ts; where web and Android differ it
/// follows Android's pending_session table (idempotent insert by submissionId,
/// rejected items kept, unsent = not rejected). No networking: a flusher reads
/// `eligible`, sends, then calls `removeFromQueue` / `markRejected` /
/// `recordFailure`.
///
/// Safety: every mutation is read-modify-write inside the actor with no
/// suspension point, and persisted atomically before the call returns. A failed
/// write throws and leaves the previously persisted queue intact. Entries that
/// cannot be decoded are preserved on disk (not returned, not dropped), and a
/// file that is not even a JSON array is copied to a `.corrupt` blob before
/// being replaced.
public actor OfflineQueue {
    private let storage: OfflineQueueStorage
    private let nowMillis: @Sendable () -> Int64
    private var listeners: [UUID: AsyncStream<Void>.Continuation] = [:]

    public init(storage: OfflineQueueStorage, nowMillis: @escaping @Sendable () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) }) {
        self.storage = storage
        self.nowMillis = nowMillis
    }

    // MARK: Reading

    /// Unsent (not rejected) sessions, oldest first. Mirrors web `loadQueue` / Android `unsent`.
    public func loadQueue(userId: String) throws -> [SubmittedSession] {
        try locked { try readState(userId) }.records.filter { $0.rejectionReason == nil }.map { $0.session }
    }

    /// Every record including rejected ones and retry metadata, oldest first.
    public func records(userId: String) throws -> [QueuedSession] {
        try locked { try readState(userId) }.records
    }

    /// Unsent records whose retry time has arrived, oldest first. Throws
    /// `OfflineQueueError.undecodableEntries` when the user's file holds unsent
    /// entries this build cannot decode, so a flush fails loudly instead of
    /// silently skipping them (they stay on disk and in `unsentCount`).
    public func eligible(userId: String) throws -> [QueuedSession] {
        let now = nowMillis()
        let state = try locked { try readState(userId) }
        let stuck = state.foreign.filter { !OfflineQueue.isRejected($0) }
        if !stuck.isEmpty {
            throw OfflineQueueError.undecodableEntries(count: stuck.count, submissionIds: stuck.compactMap { OfflineQueue.entryId($0) })
        }
        return state.records.filter {
            $0.rejectionReason == nil && ($0.nextEligibleAtMillis ?? 0) <= now
        }
    }

    /// Unsent items, counting undecodable ones (Android `unsentCount` counts every non-rejected row).
    public func unsentCount(userId: String) throws -> Int {
        let state = try locked { try readState(userId) }
        return state.records.filter { $0.rejectionReason == nil }.count
            + state.foreign.filter { !OfflineQueue.isRejected($0) }.count
    }

    /// Number of stored entries this build cannot decode (kept on disk, never deleted).
    public func undecodableCount(userId: String) throws -> Int {
        try locked { try readState(userId) }.foreign.count
    }

    /// True when `queue` holds a submission id that isn't in `knownIds`.
    public nonisolated static func hasUnknownSubmissions(_ queue: [SubmittedSession], knownIds: Set<String>) -> Bool {
        queue.contains { !knownIds.contains($0.submissionId) }
    }

    // MARK: Writing

    /// Appends the session unless its submissionId is already queued (idempotent,
    /// Android `OnConflictStrategy.IGNORE`). Returns true when it was added.
    @discardableResult
    public func enqueue(userId: String, session: SubmittedSession) throws -> Bool {
        try enqueue(userId: userId, sessions: [session]) == 1
    }

    /// Appends several sessions in one atomic write; returns how many were new.
    @discardableResult
    public func enqueue(userId: String, sessions: [SubmittedSession]) throws -> Int {
        let now = nowMillis()
        let added: Int = try locked {
            var state = try readState(userId)
            var known = Set(state.records.map { $0.submissionId })
            for entry in state.foreign {
                if let id = OfflineQueue.entryId(entry) { known.insert(id) }
            }
            var added = 0
            for session in sessions where !known.contains(session.submissionId) {
                known.insert(session.submissionId)
                state.records.append(QueuedSession(session: session, queuedAtMillis: now))
                added += 1
            }
            if added > 0 { try persist(userId, state) }
            return added
        }
        if added > 0 { notifyChanged() }
        return added
    }

    /// Removes every queued session whose submissionId is in `submissionIds` (settled by the server).
    public func removeFromQueue(userId: String, submissionIds: [String]) throws {
        let drop = Set(submissionIds)
        try locked {
            var state = try readState(userId)
            state.records.removeAll { drop.contains($0.submissionId) }
            try persist(userId, state)
        }
        notifyChanged()
    }

    /// Keeps the item but flags it as rejected so it is surfaced, not retried or lost.
    public func markRejected(userId: String, submissionId: String, reason: String) throws {
        let changed: Bool = try locked {
            var state = try readState(userId)
            guard let index = state.records.firstIndex(where: { $0.submissionId == submissionId }) else { return false }
            state.records[index].rejectionReason = reason
            try persist(userId, state)
            return true
        }
        if changed { notifyChanged() }
    }

    /// Records a failed send: bumps attempts and sets the next eligible time with
    /// exponential backoff (30 s, doubling, capped at one hour; Android WorkManager
    /// uses 30 s exponential). The item stays queued.
    public func recordFailure(userId: String, submissionIds: [String], error: String?) throws {
        let targets = Set(submissionIds)
        let now = nowMillis()
        let changed: Bool = try locked {
            var state = try readState(userId)
            var changed = false
            for index in state.records.indices where targets.contains(state.records[index].submissionId) {
                state.records[index].attempts += 1
                state.records[index].lastError = error
                state.records[index].nextEligibleAtMillis = now + OfflineQueue.backoffMillis(attempts: state.records[index].attempts)
                changed = true
            }
            if changed { try persist(userId, state) }
            return changed
        }
        if changed { notifyChanged() }
    }

    /// Deletes the user's queue and any quarantined `.corrupt` leftovers
    /// (Android `deleteForUser`, run on sign-out cleanup).
    public func clear(userId: String) throws {
        let name = OfflineQueue.fileName(userId)
        try locked {
            for leftover in try storage.list() where leftover.hasPrefix(name + ".corrupt") {
                try storage.remove(leftover)
            }
            try storage.remove(name)
        }
        notifyChanged()
    }

    public nonisolated static func backoffMillis(attempts: Int) -> Int64 {
        let exponent = min(max(attempts - 1, 0), 7)
        return min(30_000 * Int64(1 << exponent), 3_600_000)
    }

    // MARK: Change notification (web OFFLINE_QUEUE_CHANGED_EVENT)

    /// Yields once per enqueue/removal/update. Subscribe before mutating.
    public func changes() -> AsyncStream<Void> {
        let id = UUID()
        var continuation: AsyncStream<Void>.Continuation!
        let stream = AsyncStream<Void> { continuation = $0 }
        listeners[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeListener(id) }
        }
        return stream
    }

    private func removeListener(_ id: UUID) {
        listeners[id] = nil
    }

    private func notifyChanged() {
        for continuation in listeners.values { continuation.yield() }
    }

    // MARK: Persistence

    private struct State {
        var records: [QueuedSession] = []
        /// Array elements that did not decode; written back untouched.
        var foreign: [Any] = []
        /// Raw bytes of a file that was not a JSON array; saved aside before overwrite.
        var unreadableRoot: Data?
    }

    /// Per-user file name; hex of the UTF-8 id so any id is filesystem-safe and distinct.
    nonisolated static func fileName(_ userId: String) -> String {
        "offlineQueue." + userId.utf8.map { String(format: "%02x", $0) }.joined() + ".json"
    }

    /// Runs `body` under the process-wide lock for this storage location, so
    /// separate OfflineQueue instances on the same directory serialize their
    /// read-modify-write cycles. `body` must not call `locked` again.
    private func locked<T>(_ body: () throws -> T) rethrows -> T {
        try OfflineQueueLocks.shared.withLock(key: storage.lockKey, body)
    }

    private static func entryId(_ element: Any) -> String? {
        (element as? [String: Any])?["submissionId"] as? String
    }

    private static func isRejected(_ element: Any) -> Bool {
        guard let dict = element as? [String: Any], let reason = dict["rejectionReason"] else { return false }
        return !(reason is NSNull)
    }

    private func readState(_ userId: String) throws -> State {
        var state = State()
        guard let data = try storage.read(OfflineQueue.fileName(userId)) else { return state }
        guard let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
              let array = object as? [Any] else {
            state.unreadableRoot = data
            return state
        }
        let decoder = OfflineQueue.makeDecoder()
        for element in array {
            if JSONSerialization.isValidJSONObject(element),
               let bytes = try? JSONSerialization.data(withJSONObject: element),
               let record = try? decoder.decode(QueuedSession.self, from: bytes) {
                state.records.append(record)
            } else {
                state.foreign.append(element)
            }
        }
        return state
    }

    private func persist(_ userId: String, _ state: State) throws {
        let name = OfflineQueue.fileName(userId)
        if let raw = state.unreadableRoot {
            // Never overwrite an earlier quarantine: pick the first free name.
            var corrupt = name + ".corrupt"
            var n = 1
            while try storage.read(corrupt) != nil {
                corrupt = name + ".corrupt." + String(n)
                n += 1
            }
            try storage.write(corrupt, raw)
        }
        let encoder = OfflineQueue.makeEncoder()
        var elements: [Any] = []
        for record in state.records {
            let bytes = try encoder.encode(record)
            elements.append(try JSONSerialization.jsonObject(with: bytes))
        }
        elements.append(contentsOf: state.foreign)
        let data = try JSONSerialization.data(withJSONObject: elements)
        try storage.write(name, data)
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, enc in
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            var container = enc.singleValueContainer()
            try container.encode(formatter.string(from: date))
        }
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { dec in
            let container = try dec.singleValueContainer()
            let text = try container.decode(String.self)
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: text) { return date }
            let plain = ISO8601DateFormatter()
            plain.formatOptions = [.withInternetDateTime]
            if let date = plain.date(from: text) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "bad date \(text)")
        }
        return decoder
    }
}

/// Thrown at flush time when stored entries cannot be decoded by this build.
public enum OfflineQueueError: Error, Equatable, Sendable {
    case undecodableEntries(count: Int, submissionIds: [String])
}

/// Process-wide per-location locks shared by every OfflineQueue instance.
final class OfflineQueueLocks: @unchecked Sendable {
    static let shared = OfflineQueueLocks()
    private let registry = NSLock()
    private var locks: [String: NSLock] = [:]

    func withLock<T>(key: String, _ body: () throws -> T) rethrows -> T {
        registry.lock()
        let lock: NSLock
        if let existing = locks[key] {
            lock = existing
        } else {
            lock = NSLock()
            locks[key] = lock
        }
        registry.unlock()
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }
}
