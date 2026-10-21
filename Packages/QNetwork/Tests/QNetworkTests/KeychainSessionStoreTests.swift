import XCTest
@testable import QNetwork

private final class FakeKeychainClient: KeychainClient, @unchecked Sendable {
    private let lock = NSLock()
    private var data: Data?
    private(set) var deleteCount = 0

    init(data: Data? = nil) { self.data = data }

    func get() throws -> Data? { lock.lock(); defer { lock.unlock() }; return data }
    func set(_ data: Data) throws { lock.lock(); defer { lock.unlock() }; self.data = data }
    func delete() throws { lock.lock(); defer { lock.unlock() }; data = nil; deleteCount += 1 }
    var isEmpty: Bool { lock.lock(); defer { lock.unlock() }; return data == nil }
}

private struct FailingKeychainClient: KeychainClient {
    func get() throws -> Data? { throw KeychainError(status: -25308) }
    func set(_ data: Data) throws { throw KeychainError(status: -25308) }
    func delete() throws { throw KeychainError(status: -25308) }
}

private final class FailingSetKeychainClient: KeychainClient, @unchecked Sendable {
    private let lock = NSLock()
    private var data: Data?

    init(data: Data?) { self.data = data }

    func get() throws -> Data? { lock.lock(); defer { lock.unlock() }; return data }
    func set(_ data: Data) throws { throw KeychainError(status: -25308) }
    func delete() throws { lock.lock(); defer { lock.unlock() }; data = nil }
}

final class KeychainSessionStoreTests: XCTestCase {
    private func session(_ token: String = "access-1") -> StoredSession {
        StoredSession(
            userId: "u1",
            accessToken: token,
            accessTokenExpiresAt: Date(timeIntervalSince1970: 1_800_000_000),
            refreshToken: "refresh-1"
        )
    }

    func testNotFoundReturnsNil() async {
        let store = KeychainSessionStore(client: FakeKeychainClient())
        let loaded = await store.load()
        XCTAssertNil(loaded)
    }

    func testRoundTrip() async {
        let store = KeychainSessionStore(client: FakeKeychainClient())
        await store.save(session())
        let loaded = await store.load()
        XCTAssertEqual(loaded, session())
    }

    func testOverwrite() async {
        let store = KeychainSessionStore(client: FakeKeychainClient())
        await store.save(session("a"))
        await store.save(session("b"))
        let loaded = await store.load()
        XCTAssertEqual(loaded?.accessToken, "b")
    }

    func testClear() async {
        let fake = FakeKeychainClient()
        let store = KeychainSessionStore(client: fake)
        await store.save(session())
        await store.clear()
        let loaded = await store.load()
        XCTAssertNil(loaded)
        XCTAssertTrue(fake.isEmpty)
    }

    func testCorruptBlobReturnsNilAndDeletes() async {
        let fake = FakeKeychainClient(data: Data("not json".utf8))
        let store = KeychainSessionStore(client: fake)
        let loaded = await store.load()
        XCTAssertNil(loaded)
        XCTAssertTrue(fake.isEmpty)
        XCTAssertEqual(fake.deleteCount, 1)
    }

    func testClientFailuresDoNotCrash() async {
        let store = KeychainSessionStore(client: FailingKeychainClient())
        await store.save(session())
        let loaded = await store.load()
        XCTAssertNil(loaded)
        await store.clear()
    }

    func testErrorDescriptionHasNoTokens() {
        XCTAssertEqual(KeychainError(status: -25300).description, "Keychain error -25300")
    }

    func testFailedSaveDeletesStaleItem() async {
        let seed = KeychainSessionStore(client: FakeKeychainClient())
        await seed.save(session("old"))
        let old = Data("old-blob".utf8)
        let store = KeychainSessionStore(client: FailingSetKeychainClient(data: old))
        await store.save(session("new"))
        let loaded = await store.load()
        XCTAssertNil(loaded)
    }

    func testSaveCheckedRetriesThenSucceeds() async {
        let client = FlakySetKeychainClient(failures: 2, status: -25308)
        let store = KeychainSessionStore(client: client, freeBytes: { 10_000_000_000 }, notice: nil)
        let result = await store.saveChecked(session())
        XCTAssertEqual(result, .saved)
        XCTAssertEqual(client.setCalls, 3)
    }

    func testSaveCheckedFailureWithRoomIsNotLowStorage() async {
        let client = FlakySetKeychainClient(failures: 99, status: -25308)
        let notice = StorageNotice()
        let posted = PostCounter()
        notice.setHandler { posted.bump() }
        let store = KeychainSessionStore(client: client, freeBytes: { 10_000_000_000 }, notice: notice)
        let result = await store.saveChecked(session())
        XCTAssertEqual(result, .failed)
        XCTAssertEqual(posted.count, 0)
    }

    func testSaveCheckedDiskFullIsLowStorageAndNotifies() async {
        let client = FlakySetKeychainClient(failures: 99, status: -34)
        let notice = StorageNotice()
        let posted = PostCounter()
        notice.setHandler { posted.bump() }
        let store = KeychainSessionStore(client: client, freeBytes: { 10_000_000_000 }, notice: notice)
        let result = await store.saveChecked(session())
        XCTAssertEqual(result, .lowStorage)
        XCTAssertEqual(posted.count, 1)
        let loaded = await store.load()
        XCTAssertNil(loaded)
    }

    func testSaveCheckedFailureUnderThresholdIsLowStorage() async {
        let client = FlakySetKeychainClient(failures: 99, status: -25308)
        let store = KeychainSessionStore(client: client, freeBytes: { 10_000_000 }, notice: nil)
        let result = await store.saveChecked(session())
        XCTAssertEqual(result, .lowStorage)
    }
}

private final class PostCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func bump() { lock.lock(); value += 1; lock.unlock() }
    var count: Int { lock.lock(); defer { lock.unlock() }; return value }
}

private final class FlakySetKeychainClient: KeychainClient, @unchecked Sendable {
    private let lock = NSLock()
    private var remainingFailures: Int
    private let status: Int32
    private var data: Data?
    private(set) var setCalls = 0

    init(failures: Int, status: Int32) {
        remainingFailures = failures
        self.status = status
    }

    func get() throws -> Data? { lock.lock(); defer { lock.unlock() }; return data }
    func set(_ data: Data) throws {
        lock.lock(); defer { lock.unlock() }
        setCalls += 1
        if remainingFailures > 0 {
            remainingFailures -= 1
            throw KeychainError(status: status)
        }
        self.data = data
    }
    func delete() throws { lock.lock(); defer { lock.unlock() }; data = nil }
}
