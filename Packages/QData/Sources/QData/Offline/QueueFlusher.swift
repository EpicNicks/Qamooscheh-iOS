import Foundation
import QModel
import QNetwork

/// What the flusher sends through. `LessonRepository` is the production conformer.
public protocol SessionSubmitting: Sendable {
    func submit(_ sessions: [SubmittedSession]) async throws -> SubmitSessionsResponse
}

extension LessonRepository: SessionSubmitting {}

/// Called with the server's per-session results (cards to merge, caches to
/// refresh) after a successful submit and BEFORE the settled sessions leave the
/// queue (Android order: cards upserted, then pending rows deleted).
public typealias SettledHandler = @Sendable (_ userId: String, _ results: [SubmittedSessionResponse]) async -> Void

public enum FlushOutcome: Equatable, Sendable {
    /// Nothing was eligible to send.
    case idle
    /// A request was answered; see `FlushReport` for per-session results.
    case completed
    /// Network, 5xx, 408, 429 or an unusable response: everything stays queued, retry later.
    case transientFailure(String)
    /// Any other 4xx on the whole request (Android worker `Result.failure`). Nothing is dropped.
    case permanentFailure(status: Int, message: String)
}

public struct FlushReport: Equatable, Sendable {
    /// Submissions the server settled (Processed or AlreadyProcessed); removed from the queue.
    public var settled: [String] = []
    /// Submissions the server rejected; kept and flagged, never retried.
    public var rejected: [String] = []
    /// Sent but missing from the response; kept for the next flush.
    public var unanswered: [String] = []
    /// The server's per-session answers (settled and rejected) for sessions in this flush.
    public var results: [SubmittedSessionResponse] = []
    public var outcome: FlushOutcome = .idle
    /// Earliest `nextEligibleAtMillis` among the still-queued items, if any.
    public var nextRetryAtMillis: Int64?

    public init() {}
}

/// Single-flight flush of an `OfflineQueue` through a `SessionSubmitting`.
///
/// Guarantees:
/// - At most one flush per user is in flight; concurrent callers join it and
///   ask for one more pass (so a session enqueued mid-flush is still drained).
///   Items are read, sent and removed by one flight only, so a queued
///   submission is never sent twice by this process.
/// - The flight is an unstructured task: cancelling a caller never abandons a
///   request mid-bookkeeping (a delivered batch is always removed).
/// - Nothing is dropped on failure. Transport errors, 5xx, 408, 429, undecodable
///   responses and any other 4xx keep every item queued (with backoff). If the
///   app dies after the server accepted a batch, the next flush resends the same
///   submissionIds and the server answers AlreadyProcessed.
/// - Undecodable queue entries make `flush` throw `OfflineQueueError.undecodableEntries`
///   (nothing is sent) instead of silently skipping them.
public actor QueueFlusher {
    private struct Flight {
        var task: Task<FlushReport, Error>
        var rerun = false
        var ignoreBackoff = false
    }

    private let queue: OfflineQueue
    private let submitter: SessionSubmitting
    private let onSettled: SettledHandler?
    private var flights: [String: Flight] = [:]

    public init(queue: OfflineQueue, submitter: SessionSubmitting, onSettled: SettledHandler? = nil) {
        self.queue = queue
        self.submitter = submitter
        self.onSettled = onSettled
    }

    public func flush(userId: String, ignoreBackoff: Bool = false) async throws -> FlushReport {
        if var flight = flights[userId] {
            flight.rerun = true
            flight.ignoreBackoff = flight.ignoreBackoff || ignoreBackoff
            flights[userId] = flight
            return try await flight.task.value
        }
        let task = Task<FlushReport, Error> { [self] in
            try await self.runFlight(userId: userId, ignoreBackoff: ignoreBackoff)
        }
        flights[userId] = Flight(task: task)
        return try await task.value
    }

    public func flush(userId: String, reason: FlushReason) async throws -> FlushReport {
        try await flush(userId: userId, ignoreBackoff: reason.ignoresBackoff)
    }

    private func runFlight(userId: String, ignoreBackoff: Bool) async throws -> FlushReport {
        var report = FlushReport()
        var ignore = ignoreBackoff
        while true {
            let pass: FlushReport
            do {
                pass = try await runPass(userId: userId, ignoreBackoff: ignore)
            } catch {
                flights[userId] = nil
                throw error
            }
            report.settled += pass.settled
            report.rejected += pass.rejected
            report.unanswered += pass.unanswered
            report.results += pass.results
            report.nextRetryAtMillis = pass.nextRetryAtMillis
            if pass.outcome != .idle { report.outcome = pass.outcome }
            // No suspension between the checks below and clearing the flight,
            // so a caller either sets `rerun` before this point or starts a fresh flight.
            switch pass.outcome {
            case .transientFailure, .permanentFailure:
                flights[userId] = nil
                return report
            case .idle, .completed:
                break
            }
            guard var flight = flights[userId], flight.rerun else {
                flights[userId] = nil
                return report
            }
            ignore = flight.ignoreBackoff
            flight.rerun = false
            flight.ignoreBackoff = false
            flights[userId] = flight
        }
    }

    private func runPass(userId: String, ignoreBackoff: Bool) async throws -> FlushReport {
        var report = FlushReport()
        // Throws OfflineQueueError.undecodableEntries: loud, nothing sent.
        let items = try await queue.eligible(userId: userId, ignoringBackoff: ignoreBackoff)
        if items.isEmpty {
            report.nextRetryAtMillis = try await nextRetry(userId)
            return report
        }
        let sent = items.map { $0.session }
        let sentIds = items.map { $0.submissionId }

        let response: SubmitSessionsResponse
        do {
            response = try await submitter.submit(sent)
        } catch {
            let message = QueueFlusher.describe(error)
            // The account changed mid-request: these items are not at fault, so leave their retry state alone.
            if !(error is AccountChangedError) {
                try await queue.recordFailure(userId: userId, submissionIds: sentIds, error: message)
            }
            report.outcome = QueueFlusher.classify(error)
            report.nextRetryAtMillis = try await nextRetry(userId)
            return report
        }

        let sentSet = Set(sentIds)
        var seen = Set<String>()
        var results: [SubmittedSessionResponse] = []
        for result in response.sessions where sentSet.contains(result.submissionId) {
            if seen.insert(result.submissionId).inserted { results.append(result) }
        }

        if let handler = onSettled, !results.isEmpty {
            await handler(userId, results)
        }

        var settled: [String] = []
        for result in results {
            if result.outcome == .rejected {
                try await queue.markRejected(userId: userId, submissionId: result.submissionId, reason: result.rejectionReason ?? "rejected")
                report.rejected.append(result.submissionId)
            } else {
                settled.append(result.submissionId)
            }
        }
        if !settled.isEmpty {
            try await queue.removeFromQueue(userId: userId, submissionIds: settled)
        }
        report.settled = settled
        report.results = results
        report.unanswered = sentIds.filter { !seen.contains($0) }
        if !report.unanswered.isEmpty {
            try await queue.recordFailure(userId: userId, submissionIds: report.unanswered, error: "no result in response")
            report.outcome = .transientFailure("\(report.unanswered.count) session(s) missing from the response")
        } else {
            report.outcome = .completed
        }
        report.nextRetryAtMillis = try await nextRetry(userId)
        return report
    }

    private func nextRetry(_ userId: String) async throws -> Int64? {
        let records = try await queue.records(userId: userId)
        return records
            .filter { $0.rejectionReason == nil }
            .compactMap { $0.nextEligibleAtMillis }
            .min()
    }

    /// Android `FlushSessionsWorker`: a 4xx other than 408/429 is a permanent
    /// failure of the request (no automatic retry); everything else retries.
    nonisolated static func classify(_ error: Error) -> FlushOutcome {
        let message = describe(error)
        if let api = error as? ApiError, (400...499).contains(api.status), api.status != 408, api.status != 429 {
            return .permanentFailure(status: api.status, message: message)
        }
        return .transientFailure(message)
    }

    nonisolated static func describe(_ error: Error) -> String {
        if let api = error as? ApiError { return "HTTP \(api.status)" }
        return (error as NSError).localizedDescription
    }
}

// MARK: Trigger hooks

/// Why a flush was requested.
public enum FlushReason: Equatable, Sendable {
    case enqueued
    case appForeground
    case reachabilityRegained
    /// BGTaskScheduler wake-up (registered in the App target).
    case backgroundTask
    case manual

    /// Foreground and reachability changes mean the network just changed, so
    /// pending backoff delays are skipped for them.
    public var ignoresBackoff: Bool {
        switch self {
        case .appForeground, .reachabilityRegained: return true
        case .enqueued, .backgroundTask, .manual: return false
        }
    }
}

/// Something that can ask for flushes (app lifecycle, reachability monitor, ...).
public protocol FlushTriggerSource: Sendable {
    func triggers() -> AsyncStream<FlushReason>
}

/// A trigger source driven by code: the App target calls `fire` from its
/// scenePhase / NWPathMonitor / BGTask handlers.
public final class ManualFlushTrigger: FlushTriggerSource, @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [UUID: AsyncStream<FlushReason>.Continuation] = [:]

    public init() {}

    public func triggers() -> AsyncStream<FlushReason> {
        let id = UUID()
        var continuation: AsyncStream<FlushReason>.Continuation!
        let stream = AsyncStream<FlushReason> { continuation = $0 }
        lock.lock()
        continuations[id] = continuation
        lock.unlock()
        continuation.onTermination = { [weak self] _ in
            self?.lock.lock()
            self?.continuations[id] = nil
            self?.lock.unlock()
        }
        return stream
    }

    public func fire(_ reason: FlushReason) {
        lock.lock()
        let all = Array(continuations.values)
        lock.unlock()
        for continuation in all { continuation.yield(reason) }
    }
}

/// Flushes `userId`'s queue once on start and again for every trigger.
/// Every flush result is handed to `onReport` (with the reason that caused it);
/// failures (including undecodable queue entries) go to `onError`, never swallowed.
///
/// When a flush leaves entries queued behind a backoff, the driver sleeps until
/// the earliest `nextRetryAtMillis` and flushes again (honouring backoff). A new
/// trigger cancels the pending retry. A permanent 4xx is not retried (Android
/// worker `Result.failure`).
public final class QueueFlushDriver: @unchecked Sendable {
    public typealias Sleeper = @Sendable (_ nanoseconds: UInt64) async throws -> Void

    private let flusher: QueueFlusher
    private let nowMillis: @Sendable () -> Int64
    private let sleeper: Sleeper
    private let lock = NSLock()
    private var tasks: [Task<Void, Never>] = []
    private var retryTask: Task<Void, Never>?
    private var stopped = false

    public init(
        flusher: QueueFlusher,
        nowMillis: @escaping @Sendable () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) },
        sleeper: @escaping Sleeper = { try await Task.sleep(nanoseconds: $0) }
    ) {
        self.flusher = flusher
        self.nowMillis = nowMillis
        self.sleeper = sleeper
    }

    public func start(
        userId: String,
        sources: [FlushTriggerSource],
        onReport: @escaping @Sendable (_ reason: FlushReason, _ report: FlushReport) -> Void,
        onError: @escaping @Sendable (Error) -> Void
    ) {
        lock.lock()
        stopped = false
        lock.unlock()
        let run: @Sendable (FlushReason) async -> Void = { [self] reason in
            cancelRetry()
            await perform(userId: userId, reason: reason, onReport: onReport, onError: onError)
        }
        var started: [Task<Void, Never>] = [Task { await run(.manual) }]
        for source in sources {
            let stream = source.triggers()
            started.append(Task {
                for await reason in stream {
                    if Task.isCancelled { break }
                    await run(reason)
                }
            })
        }
        lock.lock()
        tasks += started
        lock.unlock()
    }

    public func stop() {
        lock.lock()
        stopped = true
        let all = tasks
        tasks = []
        let retry = retryTask
        retryTask = nil
        lock.unlock()
        for task in all { task.cancel() }
        retry?.cancel()
    }

    private func cancelRetry() {
        lock.lock()
        let retry = retryTask
        retryTask = nil
        lock.unlock()
        retry?.cancel()
    }

    private func perform(
        userId: String,
        reason: FlushReason,
        onReport: @escaping @Sendable (FlushReason, FlushReport) -> Void,
        onError: @escaping @Sendable (Error) -> Void
    ) async {
        do {
            let report = try await flusher.flush(userId: userId, reason: reason)
            onReport(reason, report)
            scheduleRetry(userId: userId, report: report, onReport: onReport, onError: onError)
        } catch {
            onError(error)
        }
    }

    private func scheduleRetry(
        userId: String,
        report: FlushReport,
        onReport: @escaping @Sendable (FlushReason, FlushReport) -> Void,
        onError: @escaping @Sendable (Error) -> Void
    ) {
        if case .permanentFailure = report.outcome { return }
        guard let next = report.nextRetryAtMillis else { return }
        let delayMillis = max(0, next - nowMillis())
        let sleeper = self.sleeper
        let task = Task { [self] in
            do {
                try await sleeper(UInt64(delayMillis) * 1_000_000)
            } catch {
                return
            }
            if Task.isCancelled { return }
            await perform(userId: userId, reason: .manual, onReport: onReport, onError: onError)
        }
        lock.lock()
        if stopped {
            lock.unlock()
            task.cancel()
            return
        }
        let previous = retryTask
        retryTask = task
        lock.unlock()
        previous?.cancel()
    }
}

/// One `QueueFlusher` per user, shared by every view and driver, so the
/// single-flight guarantee holds app-wide rather than per call site.
public actor QueueFlusherProvider {
    private let make: @Sendable (_ userId: String) -> QueueFlusher
    private var flushers: [String: QueueFlusher] = [:]

    public init(make: @escaping @Sendable (_ userId: String) -> QueueFlusher) {
        self.make = make
    }

    public func flusher(for userId: String) -> QueueFlusher {
        if let existing = flushers[userId] { return existing }
        let created = make(userId)
        flushers[userId] = created
        return created
    }

    /// Drops the cached flusher (sign-out); a later call builds a fresh one.
    public func discard(userId: String) {
        flushers[userId] = nil
    }
}
