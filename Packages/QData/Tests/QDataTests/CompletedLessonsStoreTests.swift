import XCTest
@testable import QData

final class CompletedLessonsStoreTests: XCTestCase {
    private struct Offline: Error {}

    func testServerKeysSurviveARelaunchOffline() async throws {
        let files = InMemoryContentStore()
        let first = CompletedLessonsStore(store: files)
        _ = try await first.resolve(userId: "u", courseCode: "fa", fetch: { ["a1", "b1"] })

        let relaunched = CompletedLessonsStore(store: files)
        let offline = try await relaunched.resolve(userId: "u", courseCode: "fa", fetch: { throw Offline() })
        XCTAssertEqual(offline, ["a1", "b1"])
    }

    func testOfflineWithNothingHeldRethrows() async {
        let store = CompletedLessonsStore(store: InMemoryContentStore())
        do {
            _ = try await store.resolve(userId: "u", courseCode: "fa", fetch: { throw Offline() })
            XCTFail("expected the fetch error")
        } catch {
            XCTAssertTrue(error is Offline)
        }
    }

    func testLocalCompletionJoinsServerKeysWithoutAddingAnything() async throws {
        let store = CompletedLessonsStore(store: InMemoryContentStore())
        try await store.recordLocalCompletion(userId: "u", courseCode: "fa", skillKey: "b1")
        let offline = try await store.resolve(userId: "u", courseCode: "fa", fetch: { throw Offline() })
        XCTAssertEqual(offline, ["b1"])
        // The server later confirms the same key: the set is unchanged, so no second completion appears.
        let online = try await store.resolve(userId: "u", courseCode: "fa", fetch: { ["a1", "b1"] })
        XCTAssertEqual(online, ["a1", "b1"])
    }

    func testPerUserAndPerCourse() async throws {
        let store = CompletedLessonsStore(store: InMemoryContentStore())
        try await store.recordLocalCompletion(userId: "u", courseCode: "fa", skillKey: "a1")
        try await store.recordLocalCompletion(userId: "u", courseCode: "es", skillKey: "z1")
        let mine = await store.keys(userId: "u", courseCode: "fa")
        let other = await store.keys(userId: "v", courseCode: "fa")
        XCTAssertEqual(mine, ["a1"])
        XCTAssertEqual(other, [])
        try await store.clear(userId: "u")
        let cleared = await store.keys(userId: "u", courseCode: "es")
        XCTAssertEqual(cleared, [])
    }
}
