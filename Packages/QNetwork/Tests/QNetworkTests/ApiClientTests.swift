import XCTest
import QModel
@testable import QNetwork

private struct Ping: Codable, Equatable {
    var value: Int
}

final class ApiClientTests: XCTestCase {
    private let base = URL(string: "https://api.test")!
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    private func session(token: String = "old", expiresIn: TimeInterval = 3600, refresh: String = "r1") -> StoredSession {
        StoredSession(userId: "u1", accessToken: token,
                      accessTokenExpiresAt: t0.addingTimeInterval(expiresIn), refreshToken: refresh)
    }

    private func makeClient(store: SessionStore, onExpired: (@Sendable () -> Void)? = nil) -> ApiClient {
        let start = t0
        return ApiClient(
            baseURL: base, clientHeader: "ios/1", session: StubURLProtocol.makeSession(), store: store,
            now: { start }, timeZoneProvider: { "America/New_York" }, onSessionExpired: onExpired)
    }

    private func refreshJSON(access: String, refresh: String = "r2") -> String {
        "{\"userId\":\"u1\",\"accessToken\":\"\(access)\",\"refreshToken\":\"\(refresh)\",\"accessTokenExpiresAt\":\"2030-01-01T00:00:00Z\"}"
    }

    private func auth(_ request: URLRequest) -> String? {
        request.value(forHTTPHeaderField: "Authorization")
    }

    func testAttachesHeadersAndDecodes() async throws {
        StubURLProtocol.install { _ in StubResponse(200, "{\"value\":7}") }
        let client = makeClient(store: InMemorySessionStore(session: session()))
        let result: Ping = try await client.send(.get, "/v1/ping")
        XCTAssertEqual(result, Ping(value: 7))
        let request = StubURLProtocol.requests[0]
        XCTAssertEqual(request.url?.absoluteString, "https://api.test/v1/ping")
        XCTAssertEqual(auth(request), "Bearer old")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Client"), "ios/1")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Time-Zone"), "America/New_York")
        XCTAssertNil(request.value(forHTTPHeaderField: "Content-Type"))
    }

    func testAnonymousSkipsAuthorization() async throws {
        StubURLProtocol.install { _ in StubResponse(200, "{\"value\":1}") }
        let client = makeClient(store: InMemorySessionStore(session: session()))
        let _: Ping = try await client.send(.post, "/v1/auth/login", body: Ping(value: 1), anonymous: true)
        let request = StubURLProtocol.requests[0]
        XCTAssertNil(auth(request))
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
    }

    func testRefreshesOnceOn401ThenRetries() async throws {
        StubURLProtocol.install { request in
            let path = request.url?.path ?? ""
            if path == "/v1/auth/refresh" { return StubResponse(200, self.refreshJSON(access: "new")) }
            if self.auth(request) == "Bearer new" { return StubResponse(200, "{\"value\":2}") }
            return StubResponse(401)
        }
        let store = InMemorySessionStore(session: session())
        let client = makeClient(store: store)
        let result: Ping = try await client.send(.get, "/v1/ping")
        XCTAssertEqual(result, Ping(value: 2))
        let paths = StubURLProtocol.requests.map { $0.url?.path ?? "" }
        XCTAssertEqual(paths, ["/v1/ping", "/v1/auth/refresh", "/v1/ping"])
        let saved = await store.load()
        XCTAssertEqual(saved?.accessToken, "new")
        XCTAssertEqual(saved?.refreshToken, "r2")
    }

    func testSecondConsecutive401IsSurfacedWithoutLooping() async throws {
        StubURLProtocol.install { request in
            if request.url?.path == "/v1/auth/refresh" { return StubResponse(200, self.refreshJSON(access: "new")) }
            return StubResponse(401, "{\"error\":\"nope\"}")
        }
        let client = makeClient(store: InMemorySessionStore(session: session()))
        do {
            let _: Ping = try await client.send(.get, "/v1/ping")
            XCTFail("expected ApiError")
        } catch let error as ApiError {
            XCTAssertEqual(error.status, 401)
            XCTAssertEqual(error.body?.error, "nope")
        }
        XCTAssertEqual(StubURLProtocol.requests.count, 3)
    }

    func testRefreshRejectionClearsSessionAndSignalsLogout() async throws {
        StubURLProtocol.install { request in
            if request.url?.path == "/v1/auth/refresh" { return StubResponse(401) }
            return StubResponse(401)
        }
        let store = InMemorySessionStore(session: session())
        let expired = ExpiredFlag()
        let client = makeClient(store: store, onExpired: { expired.set() })
        do {
            let _: Ping = try await client.send(.get, "/v1/ping")
            XCTFail("expected SessionExpiredError")
        } catch is SessionExpiredError {
        }
        let remaining = await store.load()
        XCTAssertNil(remaining)
        XCTAssertTrue(expired.value)
    }

    func testRefresh5xxKeepsSession() async throws {
        StubURLProtocol.install { request in
            if request.url?.path == "/v1/auth/refresh" { return StubResponse(503, "{\"error\":\"down\"}") }
            return StubResponse(401)
        }
        let store = InMemorySessionStore(session: session())
        let client = makeClient(store: store)
        do {
            let _: Ping = try await client.send(.get, "/v1/ping")
            XCTFail("expected ApiError")
        } catch let error as ApiError {
            XCTAssertEqual(error.status, 503)
        }
        let remaining = await store.load()
        XCTAssertNotNil(remaining)
    }

    func testRefreshesUpFrontWhenTokenNearExpiry() async throws {
        StubURLProtocol.install { request in
            if request.url?.path == "/v1/auth/refresh" { return StubResponse(200, self.refreshJSON(access: "new")) }
            return StubResponse(200, "{\"value\":3}")
        }
        let client = makeClient(store: InMemorySessionStore(session: session(expiresIn: 10)))
        let _: Ping = try await client.send(.get, "/v1/ping")
        let paths = StubURLProtocol.requests.map { $0.url?.path ?? "" }
        XCTAssertEqual(paths, ["/v1/auth/refresh", "/v1/ping"])
        XCTAssertEqual(auth(StubURLProtocol.requests[1]), "Bearer new")
    }

    func testNonSuccessThrowsApiErrorWithBody() async throws {
        StubURLProtocol.install { _ in StubResponse(400, "{\"error\":\"bad\",\"reason\":\"why\"}") }
        let client = makeClient(store: InMemorySessionStore(session: session()))
        do {
            let _: Ping = try await client.send(.get, "/v1/ping")
            XCTFail("expected ApiError")
        } catch let error as ApiError {
            XCTAssertEqual(error.status, 400)
            XCTAssertEqual(error.body, ApiErrorBody(error: "bad", reason: "why"))
            XCTAssertEqual(error.localizedDescription, "bad")
        }
    }

    func testConcurrent401sShareExactlyOneRefresh() async throws {
        StubURLProtocol.install { request in
            if request.url?.path == "/v1/auth/refresh" { return StubResponse(200, self.refreshJSON(access: "new")) }
            if self.auth(request) == "Bearer new" { return StubResponse(200, "{\"value\":2}") }
            return StubResponse(401)
        }
        let client = makeClient(store: InMemorySessionStore(session: session()))
        let total = try await withThrowingTaskGroup(of: Int.self) { group -> Int in
            for _ in 0..<5 {
                group.addTask {
                    let ping: Ping = try await client.send(.get, "/v1/ping")
                    return ping.value
                }
            }
            var sum = 0
            for try await value in group { sum += value }
            return sum
        }
        XCTAssertEqual(total, 10)
        let refreshes = StubURLProtocol.requests.filter { $0.url?.path == "/v1/auth/refresh" }
        XCTAssertEqual(refreshes.count, 1)
    }

    func testStaleRefreshRetriesWithCurrentSession() async throws {
        let store = LockedSessionStore(session: session())
        StubURLProtocol.install { request in
            if request.url?.path == "/v1/auth/refresh" {
                store.replace(self.session(token: "other", refresh: "r9"))
                return StubResponse(200, self.refreshJSON(access: "new"))
            }
            if self.auth(request) == "Bearer other" { return StubResponse(200, "{\"value\":5}") }
            return StubResponse(401)
        }
        let expired = ExpiredFlag()
        let client = makeClient(store: store, onExpired: { expired.set() })
        let result: Ping = try await client.send(.get, "/v1/ping")
        XCTAssertEqual(result, Ping(value: 5))
        let paths = StubURLProtocol.requests.map { $0.url?.path ?? "" }
        XCTAssertEqual(paths, ["/v1/ping", "/v1/auth/refresh", "/v1/ping"])
        XCTAssertEqual(store.snapshot?.accessToken, "other")
        XCTAssertFalse(expired.value)
    }

    func testStaleRefreshWithNoSessionSurfacesUnauthenticated() async throws {
        let store = LockedSessionStore(session: session())
        StubURLProtocol.install { request in
            if request.url?.path == "/v1/auth/refresh" {
                store.replace(nil)
                return StubResponse(200, self.refreshJSON(access: "new"))
            }
            return StubResponse(401)
        }
        let expired = ExpiredFlag()
        let client = makeClient(store: store, onExpired: { expired.set() })
        do {
            let _: Ping = try await client.send(.get, "/v1/ping")
            XCTFail("expected SessionExpiredError")
        } catch is SessionExpiredError {
        }
        XCTAssertNil(store.snapshot)
        XCTAssertFalse(expired.value)
    }

    func testAlreadyRotatedTokenRetriesWithoutRefreshing() async throws {
        let store = LockedSessionStore(session: session())
        StubURLProtocol.install { request in
            if self.auth(request) == "Bearer rotated" { return StubResponse(200, "{\"value\":6}") }
            store.replace(self.session(token: "rotated", refresh: "r2"))
            return StubResponse(401)
        }
        let client = makeClient(store: store)
        let result: Ping = try await client.send(.get, "/v1/ping")
        XCTAssertEqual(result, Ping(value: 6))
        let paths = StubURLProtocol.requests.map { $0.url?.path ?? "" }
        XCTAssertEqual(paths, ["/v1/ping", "/v1/ping"])
    }

    func testUpFrontRefreshFailureFallsThroughWithCurrentToken() async throws {
        StubURLProtocol.install { request in
            if request.url?.path == "/v1/auth/refresh" { return StubResponse(503) }
            return StubResponse(200, "{\"value\":4}")
        }
        let store = InMemorySessionStore(session: session(expiresIn: 10))
        let client = makeClient(store: store)
        let result: Ping = try await client.send(.get, "/v1/ping")
        XCTAssertEqual(result, Ping(value: 4))
        let paths = StubURLProtocol.requests.map { $0.url?.path ?? "" }
        XCTAssertEqual(paths, ["/v1/auth/refresh", "/v1/ping"])
        XCTAssertEqual(auth(StubURLProtocol.requests[1]), "Bearer old")
        let remaining = await store.load()
        XCTAssertNotNil(remaining)
    }

    func testUpFrontRefreshRejectionStillLogsOut() async throws {
        StubURLProtocol.install { _ in StubResponse(401) }
        let store = InMemorySessionStore(session: session(expiresIn: 10))
        let expired = ExpiredFlag()
        let client = makeClient(store: store, onExpired: { expired.set() })
        do {
            let _: Ping = try await client.send(.get, "/v1/ping")
            XCTFail("expected SessionExpiredError")
        } catch is SessionExpiredError {
        }
        let remaining = await store.load()
        XCTAssertNil(remaining)
        XCTAssertTrue(expired.value)
        XCTAssertEqual(StubURLProtocol.requests.count, 1)
    }

    func testUpFrontStaleRefreshSendsWithCurrentSession() async throws {
        let store = LockedSessionStore(session: session(expiresIn: 10))
        StubURLProtocol.install { request in
            if request.url?.path == "/v1/auth/refresh" {
                store.replace(self.session(token: "other", refresh: "r9"))
                return StubResponse(200, self.refreshJSON(access: "new"))
            }
            return StubResponse(200, "{\"value\":8}")
        }
        let client = makeClient(store: store)
        let result: Ping = try await client.send(.get, "/v1/ping")
        XCTAssertEqual(result, Ping(value: 8))
        XCTAssertEqual(auth(StubURLProtocol.requests[1]), "Bearer other")
    }

    func testBodilessErrorFallbackMessage() {
        XCTAssertEqual(ApiError(status: 429, body: nil).localizedDescription,
                       "Too many attempts. Wait a moment and try again.")
        XCTAssertEqual(ApiError(status: 500, body: nil).localizedDescription, "Request failed with status 500")
    }
}

final class ExpiredFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false

    func set() {
        lock.lock()
        flag = true
        lock.unlock()
    }

    var value: Bool {
        lock.lock()
        defer { lock.unlock() }
        return flag
    }
}

/// Store whose state can be changed synchronously from a stub handler.
final class LockedSessionStore: SessionStore, @unchecked Sendable {
    private let lock = NSLock()
    private var current: StoredSession?

    init(session: StoredSession?) {
        current = session
    }

    func replace(_ session: StoredSession?) {
        lock.lock()
        current = session
        lock.unlock()
    }

    var snapshot: StoredSession? {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    func load() async -> StoredSession? { snapshot }
    func save(_ session: StoredSession) async { replace(session) }
    func clear() async { replace(nil) }
}
