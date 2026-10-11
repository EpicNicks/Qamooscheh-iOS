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
}
