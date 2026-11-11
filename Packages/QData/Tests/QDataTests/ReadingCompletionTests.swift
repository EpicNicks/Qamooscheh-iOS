import XCTest
import QModel
import QNetwork
@testable import QData

private final class Clock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Int64 = 1_000_000
    var now: Int64 { lock.lock(); defer { lock.unlock() }; return value }
    func advance(_ ms: Int64) { lock.lock(); value += ms; lock.unlock() }
}

private final class MockCompleter: ReadingCompleting, @unchecked Sendable {
    typealias Behavior = @Sendable (Int, ReadingCompletionRequest) throws -> ReadingCompletionResponse

    private let lock = NSLock()
    private var sent: [ReadingCompletionRequest] = []
    private let behavior: Behavior

    init(_ behavior: @escaping Behavior = { _, _ in ReadingCompletionResponse(outcome: .recorded) }) {
        self.behavior = behavior
    }

    var requests: [ReadingCompletionRequest] { lock.lock(); defer { lock.unlock() }; return sent }

    func complete(_ request: ReadingCompletionRequest) async throws -> ReadingCompletionResponse {
        lock.lock()
        sent.append(request)
        let index = sent.count - 1
        lock.unlock()
        return try behavior(index, request)
    }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String] = []
    func add(_ value: String) { lock.lock(); items.append(value); lock.unlock() }
    var values: [String] { lock.lock(); defer { lock.unlock() }; return items }
}

final class ReadingCompletionTests: XCTestCase {
    private let user = "u1"
    private let date = Date(timeIntervalSince1970: 1_700_000_000)

    private func request(_ skill: String = "s1", unit: String? = "u-1") -> ReadingCompletionRequest {
        ReadingCompletionRequest(courseCode: "fa", unitKey: unit, skillKey: skill, occurredAt: date)
    }

    private func makeQueue(
        _ completer: ReadingCompleting, storage: InMemoryOfflineQueueStorage = InMemoryOfflineQueueStorage(),
        clock: Clock = Clock(), onRecorded: ReadingCompletionQueue.RecordedHandler? = nil
    ) -> ReadingCompletionQueue {
        ReadingCompletionQueue(storage: storage, completer: completer, nowMillis: { clock.now }, onRecorded: onRecorded)
    }

    // MARK: Wire

    func testBodyCarriesCourseUnitSkillAndOccurredAtOnly() throws {
        let data = try QJSON.makeEncoder().encode(request())
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["courseCode", "unitKey", "skillKey", "occurredAt"])
        XCTAssertEqual(object["courseCode"] as? String, "fa")
        XCTAssertEqual(object["unitKey"] as? String, "u-1")
        XCTAssertEqual(object["skillKey"] as? String, "s1")
        XCTAssertEqual(object["occurredAt"] as? String, "2023-11-14T22:13:20.000Z")
    }

    func testUnitKeyIsOptionalOnTheWire() throws {
        let data = try QJSON.makeEncoder().encode(request(unit: nil))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(object["unitKey"])
        XCTAssertEqual(object["skillKey"] as? String, "s1")
    }

    func testOutcomesDecode() throws {
        let recorded = try QJSON.makeDecoder().decode(ReadingCompletionResponse.self, from: Data(#"{"outcome":"Recorded"}"#.utf8))
        let already = try QJSON.makeDecoder().decode(ReadingCompletionResponse.self, from: Data(#"{"outcome":"AlreadyCompleted"}"#.utf8))
        XCTAssertEqual(recorded.outcome, .recorded)
        XCTAssertEqual(already.outcome, .alreadyCompleted)
    }

    // MARK: Classification

    func testClassification() {
        func status(_ code: Int) -> ReadingCompletionDisposition {
            ReadingCompletionQueue.disposition(for: ApiError(status: code, body: nil))
        }
        XCTAssertEqual(status(400), .drop)
        XCTAssertEqual(status(401), .drop)
        XCTAssertEqual(status(404), .drop)
        XCTAssertEqual(status(403), .drop)
        XCTAssertEqual(status(500), .retry)
        XCTAssertEqual(status(503), .retry)
        XCTAssertEqual(status(408), .retry)
        XCTAssertEqual(status(429), .retry)
        XCTAssertEqual(ReadingCompletionQueue.disposition(for: URLError(.notConnectedToInternet)), .retry)
        XCTAssertEqual(ReadingCompletionQueue.disposition(for: SessionExpiredError()), .retry)
        XCTAssertEqual(ReadingCompletionQueue.disposition(for: AccountChangedError()), .leave)
    }

    // MARK: Queue

    func testEnqueueIsIdempotentBySubmissionId() async throws {
        let queue = makeQueue(MockCompleter())
        let first = try await queue.enqueue(userId: user, submissionId: "a", request: request())
        let second = try await queue.enqueue(userId: user, submissionId: "a", request: request())
        let records = try await queue.records(userId: user)
        XCTAssertTrue(first)
        XCTAssertFalse(second)
        XCTAssertEqual(records.count, 1)
    }

    func testRecordedIsRemovedAndAnnounced() async throws {
        let announced = Counter()
        let completer = MockCompleter()
        let queue = makeQueue(completer, onRecorded: { uid, req in announced.add(uid + ":" + req.skillKey) })
        try await queue.enqueue(userId: user, submissionId: "a", request: request("s1"))
        let report = try await queue.flush(userId: user)
        let left = try await queue.records(userId: user)
        XCTAssertEqual(report.recorded, ["a"])
        XCTAssertTrue(left.isEmpty)
        XCTAssertEqual(announced.values, ["u1:s1"])
        XCTAssertEqual(completer.requests, [request("s1")])
    }

    func testAlreadyCompletedIsASuccessWithoutAnnouncement() async throws {
        let announced = Counter()
        let completer = MockCompleter { _, _ in ReadingCompletionResponse(outcome: .alreadyCompleted) }
        let queue = makeQueue(completer, onRecorded: { _, req in announced.add(req.skillKey) })
        try await queue.enqueue(userId: user, submissionId: "a", request: request())
        let report = try await queue.flush(userId: user)
        let left = try await queue.records(userId: user)
        XCTAssertEqual(report.alreadyCompleted, ["a"])
        XCTAssertTrue(report.recorded.isEmpty)
        XCTAssertTrue(left.isEmpty)
        XCTAssertTrue(announced.values.isEmpty)
    }

    func testEachDefinitiveErrorDropsTheCall() async throws {
        for (code, reason) in [(400, "not_a_reading_skill"), (400, "invalid_request"), (404, "unknown_course"), (404, "unknown_skill"), (401, nil)] as [(Int, String?)] {
            let completer = MockCompleter { _, _ in throw ApiError(status: code, body: ApiErrorBody(error: "x", reason: reason)) }
            let announced = Counter()
            let queue = makeQueue(completer, onRecorded: { _, req in announced.add(req.skillKey) })
            try await queue.enqueue(userId: user, submissionId: "a", request: request())
            let report = try await queue.flush(userId: user)
            let left = try await queue.records(userId: user)
            XCTAssertEqual(report.dropped, ["a"], "\(code) \(reason ?? "")")
            XCTAssertTrue(left.isEmpty, "\(code) \(reason ?? "")")
            XCTAssertTrue(announced.values.isEmpty)
            XCTAssertEqual(completer.requests.count, 1)
        }
    }

    func testNetworkFailureKeepsTheCallWithBackoff() async throws {
        let clock = Clock()
        let completer = MockCompleter { _, _ in throw URLError(.notConnectedToInternet) }
        let queue = makeQueue(completer, clock: clock)
        try await queue.enqueue(userId: user, submissionId: "a", request: request())
        let report = try await queue.flush(userId: user)
        let left = try await queue.records(userId: user)
        XCTAssertEqual(report.retained, ["a"])
        XCTAssertEqual(left.count, 1)
        XCTAssertEqual(left[0].attempts, 1)
        XCTAssertEqual(left[0].nextEligibleAtMillis, clock.now + 30_000)
    }

    func testServerErrorKeepsTheCallAndBackoffGatesTheNextFlush() async throws {
        let clock = Clock()
        let completer = MockCompleter { index, _ in
            if index == 0 { throw ApiError(status: 503, body: nil) }
            return ReadingCompletionResponse(outcome: .recorded)
        }
        let queue = makeQueue(completer, clock: clock)
        try await queue.enqueue(userId: user, submissionId: "a", request: request())
        let first = try await queue.flush(userId: user)
        XCTAssertEqual(first.retained, ["a"])

        let gated = try await queue.flush(userId: user)
        XCTAssertEqual(completer.requests.count, 1, "still backing off")
        XCTAssertTrue(gated.recorded.isEmpty)

        clock.advance(30_001)
        let later = try await queue.flush(userId: user)
        let left = try await queue.records(userId: user)
        XCTAssertEqual(later.recorded, ["a"])
        XCTAssertTrue(left.isEmpty)
    }

    func testIgnoringBackoffRetriesAtOnce() async throws {
        let completer = MockCompleter { index, _ in
            if index == 0 { throw URLError(.timedOut) }
            return ReadingCompletionResponse(outcome: .recorded)
        }
        let queue = makeQueue(completer)
        try await queue.enqueue(userId: user, submissionId: "a", request: request())
        _ = try await queue.flush(userId: user)
        let again = try await queue.flush(userId: user, ignoreBackoff: true)
        XCTAssertEqual(again.recorded, ["a"])
    }

    func testRetryableFailureStopsThePassAndKeepsLaterCalls() async throws {
        let completer = MockCompleter { _, _ in throw ApiError(status: 500, body: nil) }
        let queue = makeQueue(completer)
        try await queue.enqueue(userId: user, submissionId: "a", request: request("s1"))
        try await queue.enqueue(userId: user, submissionId: "b", request: request("s2"))
        let report = try await queue.flush(userId: user)
        let left = try await queue.records(userId: user)
        XCTAssertEqual(completer.requests.count, 1)
        XCTAssertEqual(report.retained, ["a"])
        XCTAssertEqual(left.map { $0.submissionId }, ["a", "b"])
    }

    func testDefinitiveDropDoesNotBlockTheNextCall() async throws {
        let completer = MockCompleter { _, req in
            if req.skillKey == "s1" { throw ApiError(status: 404, body: ApiErrorBody(error: "x", reason: "unknown_skill")) }
            return ReadingCompletionResponse(outcome: .recorded)
        }
        let queue = makeQueue(completer)
        try await queue.enqueue(userId: user, submissionId: "a", request: request("s1"))
        try await queue.enqueue(userId: user, submissionId: "b", request: request("s2"))
        let report = try await queue.flush(userId: user)
        XCTAssertEqual(report.dropped, ["a"])
        XCTAssertEqual(report.recorded, ["b"])
    }

    func testAccountChangeLeavesTheCallUntouched() async throws {
        let completer = MockCompleter { _, _ in throw AccountChangedError() }
        let queue = makeQueue(completer)
        try await queue.enqueue(userId: user, submissionId: "a", request: request())
        let report = try await queue.flush(userId: user)
        let left = try await queue.records(userId: user)
        XCTAssertEqual(report, ReadingCompletionFlushReport())
        XCTAssertEqual(left.count, 1)
        XCTAssertEqual(left[0].attempts, 0)
    }

    func testQueuedCallsSurviveARestartAndReplay() async throws {
        let storage = InMemoryOfflineQueueStorage()
        let down = MockCompleter { _, _ in throw URLError(.notConnectedToInternet) }
        let first = makeQueue(down, storage: storage)
        try await first.enqueue(userId: user, submissionId: "a", request: request(unit: nil))
        _ = try await first.flush(userId: user)

        let up = MockCompleter()
        let second = makeQueue(up, storage: storage)
        let report = try await second.flush(userId: user, ignoreBackoff: true)
        XCTAssertEqual(report.recorded, ["a"])
        XCTAssertEqual(up.requests, [request(unit: nil)])
    }

    func testUsersAreSeparateAndClearRemovesOnlyOne() async throws {
        let queue = makeQueue(MockCompleter())
        try await queue.enqueue(userId: "u1", submissionId: "a", request: request())
        try await queue.enqueue(userId: "u2", submissionId: "b", request: request())
        try await queue.clear(userId: "u1")
        let one = try await queue.records(userId: "u1")
        let two = try await queue.records(userId: "u2")
        XCTAssertTrue(one.isEmpty)
        XCTAssertEqual(two.count, 1)
    }

    func testUnreadableFileIsKeptAsideNotOverwritten() async throws {
        let storage = InMemoryOfflineQueueStorage()
        let name = ReadingCompletionQueue.fileName(user)
        try storage.write(name, Data("not json".utf8))
        let queue = makeQueue(MockCompleter(), storage: storage)
        try await queue.enqueue(userId: user, submissionId: "a", request: request())
        XCTAssertEqual(try storage.read(name + ".corrupt"), Data("not json".utf8))
        let records = try await queue.records(userId: user)
        XCTAssertEqual(records.count, 1)
    }
}
