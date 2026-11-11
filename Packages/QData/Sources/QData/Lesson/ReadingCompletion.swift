import Foundation
import QModel
import QNetwork

/// POST /v1/skills/complete-reading body (ReaderCompletion.CompleteReadingRequest). `unitKey` is null or absent to
/// resolve the skill course-wide; `occurredAt` is accepted by the server but not stored in v1. No courseVersion.
public struct ReadingCompletionRequest: Codable, Equatable, Sendable {
    public var courseCode: String
    public var unitKey: String?
    public var skillKey: String
    public var occurredAt: Date

    public init(courseCode: String, unitKey: String?, skillKey: String, occurredAt: Date) {
        self.courseCode = courseCode
        self.unitKey = unitKey
        self.skillKey = skillKey
        self.occurredAt = occurredAt
    }
}

/// ReaderCompletionOutcome: both are a success.
public enum ReadingCompletionOutcome: String, Codable, Equatable, Sendable {
    case recorded = "Recorded"
    case alreadyCompleted = "AlreadyCompleted"
}

/// 200 body of POST /v1/skills/complete-reading.
public struct ReadingCompletionResponse: Codable, Equatable, Sendable {
    public var outcome: ReadingCompletionOutcome

    public init(outcome: ReadingCompletionOutcome) {
        self.outcome = outcome
    }
}

/// What the queue sends through. `ReadingCompletionRepository` is the production conformer.
public protocol ReadingCompleting: Sendable {
    func complete(_ request: ReadingCompletionRequest) async throws -> ReadingCompletionResponse
}

public struct ReadingCompletionRepository: ReadingCompleting {
    private let client: ApiClient

    public init(client: ApiClient) {
        self.client = client
    }

    /// POST /v1/skills/complete-reading. Idempotent on the server, so a replay is safe.
    public func complete(_ request: ReadingCompletionRequest) async throws -> ReadingCompletionResponse {
        try await client.send(.post, "/v1/skills/complete-reading", body: request)
    }
}

/// One queued completion plus its retry metadata. `submissionId` is only the queue identity (the wire has none).
public struct QueuedReadingCompletion: Codable, Equatable, Sendable {
    public var submissionId: String
    public var request: ReadingCompletionRequest
    public var queuedAtMillis: Int64
    public var attempts: Int
    public var nextEligibleAtMillis: Int64?
    public var lastError: String?

    public init(submissionId: String, request: ReadingCompletionRequest, queuedAtMillis: Int64, attempts: Int = 0, nextEligibleAtMillis: Int64? = nil, lastError: String? = nil) {
        self.submissionId = submissionId
        self.request = request
        self.queuedAtMillis = queuedAtMillis
        self.attempts = attempts
        self.nextEligibleAtMillis = nextEligibleAtMillis
        self.lastError = lastError
    }
}

/// What one flush did, by queue identity.
public struct ReadingCompletionFlushReport: Equatable, Sendable {
    /// Sent and answered Recorded; removed.
    public var recorded: [String] = []
    /// Sent and answered AlreadyCompleted; removed (a success).
    public var alreadyCompleted: [String] = []
    /// Refused definitively (400, 401, 404 and any other non-retryable 4xx); removed without retry.
    public var dropped: [String] = []
    /// Network failure or 5xx; kept with backoff.
    public var retained: [String] = []

    public init() {}
}

/// What to do with a queued call after a failed send.
public enum ReadingCompletionDisposition: Equatable, Sendable {
    /// Definitive refusal: remove the call.
    case drop
    /// Network failure, 5xx or an unusable answer: keep it and retry later.
    case retry
    /// The signed-in account changed mid-request: leave the item untouched.
    case leave
}

/// Durable per-user FIFO of reader completions that have not reached the server. The server call is idempotent, so a
/// replay after a crash (sent but not yet removed) answers AlreadyCompleted. Network failure and 5xx retry with the
/// offline queue's backoff; a definitive 4xx drops the call. Entries live in their own file, apart from session submits.
public actor ReadingCompletionQueue {
    public typealias RecordedHandler = @Sendable (_ userId: String, _ request: ReadingCompletionRequest) async -> Void

    private let storage: OfflineQueueStorage
    private let completer: ReadingCompleting
    private let nowMillis: @Sendable () -> Int64
    private let onRecorded: RecordedHandler?
    private var sending: Set<String> = []

    public init(
        storage: OfflineQueueStorage,
        completer: ReadingCompleting,
        nowMillis: @escaping @Sendable () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) },
        onRecorded: RecordedHandler? = nil
    ) {
        self.storage = storage
        self.completer = completer
        self.nowMillis = nowMillis
        self.onRecorded = onRecorded
    }

    /// Every stored completion, oldest first.
    public func records(userId: String) throws -> [QueuedReadingCompletion] {
        try read(userId)
    }

    /// Appends the completion unless its id is already queued; true when it was added.
    @discardableResult
    public func enqueue(userId: String, submissionId: String, request: ReadingCompletionRequest) throws -> Bool {
        var all = try read(userId)
        if all.contains(where: { $0.submissionId == submissionId }) { return false }
        all.append(QueuedReadingCompletion(submissionId: submissionId, request: request, queuedAtMillis: nowMillis()))
        try write(userId, all)
        return true
    }

    /// Sends every eligible completion oldest first, one call each. Stops at the first retryable failure (the rest
    /// would fail the same way). `ignoreBackoff` skips the retry-time gate (foreground, or the learner just finished).
    @discardableResult
    public func flush(userId: String, ignoreBackoff: Bool = false) async throws -> ReadingCompletionFlushReport {
        var report = ReadingCompletionFlushReport()
        let now = nowMillis()
        let items = try read(userId).filter {
            !sending.contains($0.submissionId) && (ignoreBackoff || ($0.nextEligibleAtMillis ?? 0) <= now)
        }
        for item in items {
            if sending.contains(item.submissionId) { continue }
            sending.insert(item.submissionId)
            defer { sending.remove(item.submissionId) }
            do {
                let response = try await completer.complete(item.request)
                try remove(userId, ids: [item.submissionId])
                switch response.outcome {
                case .recorded:
                    report.recorded.append(item.submissionId)
                    if let handler = onRecorded { await handler(userId, item.request) }
                case .alreadyCompleted:
                    report.alreadyCompleted.append(item.submissionId)
                }
            } catch {
                switch ReadingCompletionQueue.disposition(for: error) {
                case .drop:
                    try remove(userId, ids: [item.submissionId])
                    report.dropped.append(item.submissionId)
                case .leave:
                    return report
                case .retry:
                    try recordFailure(userId, id: item.submissionId, error: ReadingCompletionQueue.describe(error))
                    report.retained.append(item.submissionId)
                    return report
                }
            }
        }
        return report
    }

    /// Deletes the user's queue (sign-out cleanup).
    public func clear(userId: String) throws {
        try storage.remove(ReadingCompletionQueue.fileName(userId))
    }

    /// Contract: errors are definitive (drop) except a network failure or 5xx. 408 and 429 say "try later", so they retry too.
    nonisolated public static func disposition(for error: Error) -> ReadingCompletionDisposition {
        if error is AccountChangedError { return .leave }
        if let api = error as? ApiError {
            if api.status == 408 || api.status == 429 || api.status >= 500 { return .retry }
            if (400...499).contains(api.status) { return .drop }
        }
        return .retry
    }

    nonisolated static func describe(_ error: Error) -> String {
        if let api = error as? ApiError { return "HTTP \(api.status)" }
        return (error as NSError).localizedDescription
    }

    nonisolated static func fileName(_ userId: String) -> String {
        "readingCompletions." + userId.utf8.map { String(format: "%02x", $0) }.joined() + ".json"
    }

    // MARK: Persistence

    private func read(_ userId: String) throws -> [QueuedReadingCompletion] {
        let name = ReadingCompletionQueue.fileName(userId)
        guard let data = try storage.read(name) else { return [] }
        if let decoded = try? QJSON.makeDecoder().decode([QueuedReadingCompletion].self, from: data) { return decoded }
        // Not readable by this build: keep the bytes aside rather than overwrite them.
        var corrupt = name + ".corrupt"
        var n = 1
        while try storage.read(corrupt) != nil {
            corrupt = name + ".corrupt." + String(n)
            n += 1
        }
        try storage.write(corrupt, data)
        try storage.remove(name)
        return []
    }

    private func write(_ userId: String, _ all: [QueuedReadingCompletion]) throws {
        let name = ReadingCompletionQueue.fileName(userId)
        if all.isEmpty {
            try storage.remove(name)
        } else {
            try storage.write(name, try QJSON.makeEncoder().encode(all))
        }
    }

    private func remove(_ userId: String, ids: [String]) throws {
        let drop = Set(ids)
        var all = try read(userId)
        all.removeAll { drop.contains($0.submissionId) }
        try write(userId, all)
    }

    private func recordFailure(_ userId: String, id: String, error: String) throws {
        var all = try read(userId)
        guard let index = all.firstIndex(where: { $0.submissionId == id }) else { return }
        all[index].attempts += 1
        all[index].lastError = error
        all[index].nextEligibleAtMillis = nowMillis() + OfflineQueue.backoffMillis(attempts: all[index].attempts)
        try write(userId, all)
    }
}
