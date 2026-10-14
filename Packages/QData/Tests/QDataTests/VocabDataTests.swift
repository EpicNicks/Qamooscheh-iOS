import XCTest
import QModel
import QNetwork
@testable import QData

final class VocabDataTests: XCTestCase {
    private func makeRepo() -> VocabRepository {
        let store = InMemorySessionStore(session: StoredSession(
            userId: "u", accessToken: "tok",
            accessTokenExpiresAt: Date().addingTimeInterval(3600), refreshToken: "r"))
        let client = ApiClient(
            baseURL: URL(string: "https://api.test")!, clientHeader: "ios/test",
            session: StubURLProtocol.makeSession(), store: store)
        return VocabRepository(client: client)
    }

    func testSetStarredSendsAbsoluteState() async throws {
        StubURLProtocol.install { _ in StubResponse(200, #"{"tags":["a"],"limit":100,"refused":[]}"#) }
        let response = try await makeRepo().setStarred(tag: "a", starred: true)
        XCTAssertEqual(response.tags, ["a"])
        let request = StubURLProtocol.requests.first
        XCTAssertEqual(request?.httpMethod, "PUT")
        XCTAssertEqual(request?.url?.path, "/v1/vocab/starred")
    }

    func testStarredOverLimitSurfacesServerMessage() async {
        StubURLProtocol.install { _ in StubResponse(409, #"{"error":"You can save up to 1 words."}"#) }
        do {
            _ = try await makeRepo().setStarred(tag: "a", starred: true)
            XCTFail("expected throw")
        } catch {
            XCTAssertEqual((error as? ApiError)?.status, 409)
            XCTAssertEqual((error as? ApiError)?.body?.error, "You can save up to 1 words.")
        }
    }

    func testSubmitFlashcardsPosts() async throws {
        StubURLProtocol.install { _ in StubResponse(200, #"{"alreadyProcessed":false,"xp":10}"#) }
        let request = SubmitFlashcardsRequest(
            submissionId: "s", courseCode: "fa", occurredAt: Date(timeIntervalSince1970: 0), inRemix: false,
            cards: [SubmittedFlashcard(tag: "a", kind: .translation, correct: true)])
        let response = try await makeRepo().submitFlashcards(request)
        XCTAssertEqual(response.xp, 10)
        XCTAssertEqual(StubURLProtocol.requests.first?.url?.path, "/v1/flashcards/submit")
    }

    private func card(_ tag: String, stability: Double, reviewed: TimeInterval?) -> CardState {
        CardState(
            lexemeTag: tag, stability: stability, difficulty: 5,
            lastReviewedAt: reviewed.map { Date(timeIntervalSince1970: $0) }, dueAt: nil, reviewCount: 1, lapseCount: 0)
    }

    func testCardStatesPersistAcrossRelaunch() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cards-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let first = CardStateStore(store: FileContentStore(root: dir))
        try await first.merge(userId: "user/1", cards: [card("a", stability: 3, reviewed: 100)])

        let relaunched = CardStateStore(store: FileContentStore(root: dir))
        let held = await relaunched.all(userId: "user/1")
        XCTAssertEqual(held["a"]?.stability, 3)
        XCTAssertEqual(held["a"]?.lastReviewedAt, Date(timeIntervalSince1970: 100))
        let other = await relaunched.all(userId: "user/2")
        XCTAssertTrue(other.isEmpty)
    }

    func testMergeKeepsLaterReviewAndOtherCards() async throws {
        let store = CardStateStore(store: InMemoryContentStore())
        try await store.merge(userId: "u", cards: [card("a", stability: 9, reviewed: 200), card("b", stability: 1, reviewed: 50)])
        try await store.merge(userId: "u", cards: [card("a", stability: 2, reviewed: 100), card("c", stability: 4, reviewed: nil)])
        let held = await store.all(userId: "u")
        XCTAssertEqual(held["a"]?.stability, 9)
        XCTAssertEqual(held["b"]?.stability, 1)
        XCTAssertEqual(held["c"]?.stability, 4)
    }

    func testNilIncomingNeverOverwritesAReviewedCard() async throws {
        let store = CardStateStore(store: InMemoryContentStore())
        try await store.merge(userId: "u", cards: [card("a", stability: 9, reviewed: 200)])
        try await store.merge(userId: "u", cards: [card("a", stability: 1, reviewed: nil)])
        let held = await store.all(userId: "u")
        XCTAssertEqual(held["a"]?.stability, 9)
    }

    func testReviewedIncomingBeatsANilHeldCard() async throws {
        let store = CardStateStore(store: InMemoryContentStore())
        try await store.merge(userId: "u", cards: [card("a", stability: 1, reviewed: nil)])
        try await store.merge(userId: "u", cards: [card("a", stability: 5, reviewed: 10)])
        let held = await store.all(userId: "u")
        XCTAssertEqual(held["a"]?.stability, 5)
    }

    func testCorruptFileIsQuarantinedNotSilentlyDropped() async throws {
        let backing = InMemoryContentStore()
        let key = CardStateStore.key(userId: "u")
        try backing.write(Data("not json".utf8), to: key)
        let store = CardStateStore(store: backing)
        let before = await store.all(userId: "u")
        XCTAssertTrue(before.isEmpty)
        XCTAssertEqual(backing.keys, [key])
        try await store.merge(userId: "u", cards: [card("a", stability: 1, reviewed: 1)])
        let after = await store.all(userId: "u")
        XCTAssertEqual(after.count, 1)
        XCTAssertEqual(try backing.read(key + ".corrupt"), Data("not json".utf8))
        // A second corrupt file gets its own name.
        try backing.write(Data("again".utf8), to: key)
        try await store.merge(userId: "u", cards: [card("b", stability: 1, reviewed: 1)])
        XCTAssertEqual(try backing.read(key + ".corrupt"), Data("not json".utf8))
        XCTAssertEqual(try backing.read(key + ".corrupt.2"), Data("again".utf8))
    }

    func testClearAlsoRemovesQuarantinedCopies() async throws {
        let backing = InMemoryContentStore()
        let key = CardStateStore.key(userId: "u")
        try backing.write(Data("not json".utf8), to: key)
        let store = CardStateStore(store: backing)
        try await store.merge(userId: "u", cards: [card("a", stability: 1, reviewed: 1)])
        try backing.write(Data("again".utf8), to: key)
        try await store.merge(userId: "u", cards: [card("b", stability: 1, reviewed: 1)])
        XCTAssertNotNil(try backing.read(key + ".corrupt.2"))
        try await store.clear(userId: "u")
        XCTAssertTrue(backing.keys.isEmpty)
    }

    func testOneBadCardKeepsTheOthersAndQuarantinesTheFile() async throws {
        let backing = InMemoryContentStore()
        let key = CardStateStore.key(userId: "u")
        let good = try QJSON.makeEncoder().encode([card("a", stability: 4, reviewed: 1)])
        var text = String(data: good, encoding: .utf8) ?? "[]"
        text.removeLast()
        text += ",{\"lexemeTag\":\"bad\"}]"
        try backing.write(Data(text.utf8), to: key)
        let store = CardStateStore(store: backing)
        let before = await store.all(userId: "u")
        XCTAssertEqual(before["a"]?.stability, 4)
        XCTAssertNil(before["bad"])
        try await store.merge(userId: "u", cards: [card("c", stability: 2, reviewed: 2)])
        let after = await store.all(userId: "u")
        XCTAssertEqual(Set(after.keys), ["a", "c"])
        XCTAssertNotNil(try backing.read(key + ".corrupt"))
    }

    func testFailedReadDoesNotOverwriteTheMirror() async throws {
        let backing = FlakyReadStore()
        let store = CardStateStore(store: backing)
        try await store.merge(userId: "u", cards: [card("a", stability: 7, reviewed: 1)])
        backing.failReads = true
        let during = await store.all(userId: "u")
        XCTAssertTrue(during.isEmpty)
        do {
            try await store.merge(userId: "u", cards: [card("b", stability: 1, reviewed: 1)])
            XCTFail("expected throw")
        } catch {}
        backing.failReads = false
        let after = await store.all(userId: "u")
        XCTAssertEqual(Set(after.keys), ["a"])
        XCTAssertEqual(after["a"]?.stability, 7)
    }
}

private struct ReadFailure: Error {}

private final class FlakyReadStore: ContentFileStore, @unchecked Sendable {
    private let inner = InMemoryContentStore()
    var failReads = false

    func read(_ key: String) throws -> Data? {
        if failReads { throw ReadFailure() }
        return try inner.read(key)
    }

    func write(_ data: Data, to key: String) throws { try inner.write(data, to: key) }
    func remove(_ key: String) throws { try inner.remove(key) }
}
