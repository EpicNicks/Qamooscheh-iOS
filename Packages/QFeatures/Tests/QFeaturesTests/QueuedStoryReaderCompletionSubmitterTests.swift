import XCTest
import QDomain
import QData
@testable import QFeatures

private final class FakeCompleter: ReadingCompleting, @unchecked Sendable {
    private let lock = NSLock()
    private var sent: [ReadingCompletionRequest] = []
    private let result: Result<ReadingCompletionResponse, Error>

    init(_ result: Result<ReadingCompletionResponse, Error>) { self.result = result }

    var requests: [ReadingCompletionRequest] { lock.lock(); defer { lock.unlock() }; return sent }

    func complete(_ request: ReadingCompletionRequest) async throws -> ReadingCompletionResponse {
        lock.lock(); sent.append(request); lock.unlock()
        return try result.get()
    }
}

private final class RecordedCount: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func bump() { lock.lock(); count += 1; lock.unlock() }
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
}

final class QueuedStoryReaderCompletionSubmitterTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_700_000_000)

    private func completion(unit: String = "u-1") -> StoryReaderCompletionRequest {
        StoryReaderCompletionRequest(submissionId: "id-1", unitKey: unit, skillKey: "s1", courseCode: "fa", occurredAt: date)
    }

    private func make(
        _ completer: FakeCompleter, user: String? = "me", recorded: RecordedCount = RecordedCount()
    ) -> (QueuedStoryReaderCompletionSubmitter, ReadingCompletionQueue) {
        let queue = ReadingCompletionQueue(
            storage: InMemoryOfflineQueueStorage(), completer: completer, onRecorded: { _, _ in recorded.bump() })
        return (QueuedStoryReaderCompletionSubmitter(queue: queue, userId: { user }), queue)
    }

    func testWireMapsFieldsAndSendsEmptyUnitAsAbsent() {
        let wire = QueuedStoryReaderCompletionSubmitter.wire(completion())
        XCTAssertEqual(wire, ReadingCompletionRequest(courseCode: "fa", unitKey: "u-1", skillKey: "s1", occurredAt: date))
        XCTAssertNil(QueuedStoryReaderCompletionSubmitter.wire(completion(unit: "")).unitKey)
    }

    func testSubmitSendsOnceAndAnnouncesRecorded() async throws {
        let completer = FakeCompleter(.success(ReadingCompletionResponse(outcome: .recorded)))
        let recorded = RecordedCount()
        let (submitter, queue) = make(completer, recorded: recorded)
        await submitter.submit(completion())
        let left = try await queue.records(userId: "me")
        XCTAssertEqual(completer.requests.count, 1)
        XCTAssertEqual(recorded.value, 1)
        XCTAssertTrue(left.isEmpty)
    }

    func testOfflineSubmitStaysQueued() async throws {
        let down = FakeCompleter(.failure(URLError(.notConnectedToInternet)))
        let (submitter, queue) = make(down)
        await submitter.submit(completion())
        let queued = try await queue.records(userId: "me")
        XCTAssertEqual(queued.count, 1)
        XCTAssertEqual(queued[0].request.skillKey, "s1")
    }

    func testForegroundFlushSendsQueuedCompletionPastBackoff() async throws {
        let completer = FakeCompleter(.success(ReadingCompletionResponse(outcome: .recorded)))
        let recorded = RecordedCount()
        let (submitter, queue) = make(completer, recorded: recorded)
        let request = QueuedStoryReaderCompletionSubmitter.wire(completion())
        try await queue.enqueue(userId: "me", submissionId: "id-1", request: request)
        await submitter.flushPending(ignoreBackoff: true)
        let left = try await queue.records(userId: "me")
        XCTAssertEqual(completer.requests.count, 1)
        XCTAssertEqual(recorded.value, 1)
        XCTAssertTrue(left.isEmpty)
    }

    func testFailedForegroundFlushKeepsTheEntry() async throws {
        let down = FakeCompleter(.failure(URLError(.notConnectedToInternet)))
        let (submitter, queue) = make(down)
        try await queue.enqueue(userId: "me", submissionId: "id-1", request: QueuedStoryReaderCompletionSubmitter.wire(completion()))
        await submitter.flushPending(ignoreBackoff: true)
        let left = try await queue.records(userId: "me")
        XCTAssertEqual(left.count, 1)
        XCTAssertEqual(left[0].attempts, 1)
    }

    func testNoUserSendsNothing() async throws {
        let completer = FakeCompleter(.success(ReadingCompletionResponse(outcome: .recorded)))
        let (submitter, _) = make(completer, user: nil)
        await submitter.submit(completion())
        await submitter.flushPending()
        XCTAssertTrue(completer.requests.isEmpty)
    }

    func testAnnounceHandsOffToTheMainThread() {
        let center = NotificationCenter()
        let seen = expectation(description: "posted")
        let token = center.addObserver(forName: ReaderCompletionRefresh.notification, object: nil, queue: nil) { _ in
            XCTAssertTrue(Thread.isMainThread)
            seen.fulfill()
        }
        ReaderCompletionRefresh.announce(center: center)
        wait(for: [seen], timeout: 2)
        center.removeObserver(token)
    }
}
