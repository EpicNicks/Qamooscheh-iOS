import XCTest
import QModel
@testable import QNetwork

final class AuthApiTests: XCTestCase {
    private let base = URL(string: "https://api.test")!

    private func authJSON(access: String = "a1", refresh: String = "r1") -> String {
        "{\"userId\":\"u1\",\"accessToken\":\"\(access)\",\"refreshToken\":\"\(refresh)\",\"accessTokenExpiresAt\":\"2030-01-01T00:00:00Z\"}"
    }

    private func make(store: SessionStore) -> AuthApi {
        let client = ApiClient(
            baseURL: base, clientHeader: "ios/1", session: StubURLProtocol.makeSession(), store: store)
        return AuthApi(client: client, store: store)
    }

    private func old() -> StoredSession {
        StoredSession(userId: "u0", accessToken: "oldA",
                      accessTokenExpiresAt: Date(timeIntervalSince1970: 1_900_000_000), refreshToken: "oldR")
    }

    /// URLSession may move httpBody into a stream before the protocol sees it.
    private func body(_ request: URLRequest) -> [String: Any] {
        var data = request.httpBody
        if data == nil, let stream = request.httpBodyStream {
            stream.open()
            var collected = Data()
            var buffer = [UInt8](repeating: 0, count: 1024)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                collected.append(buffer, count: count)
            }
            stream.close()
            data = collected
        }
        guard let data = data,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return object
    }

    // MARK: login

    func testLoginSavesSessionAndTrimsEmail() async throws {
        let json = authJSON()
        StubURLProtocol.install { _ in StubResponse(200, json) }
        let store = InMemorySessionStore()
        let session = try await make(store: store).login(email: "  a@b.co ", password: "pw")
        XCTAssertEqual(session.accessToken, "a1")
        let saved = await store.load()
        XCTAssertEqual(saved, session)
        XCTAssertEqual(saved?.userId, "u1")
        XCTAssertEqual(saved?.refreshToken, "r1")
        let request = StubURLProtocol.requests[0]
        XCTAssertEqual(request.url?.absoluteString, "https://api.test/v1/auth/login")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(body(request)["email"] as? String, "a@b.co")
        XCTAssertEqual(body(request)["password"] as? String, "pw")
    }

    func testLoginInvalidCredentialsDoesNotSave() async {
        StubURLProtocol.install { _ in StubResponse(401, "{\"error\":\"Invalid email or password.\"}") }
        let store = InMemorySessionStore()
        do {
            _ = try await make(store: store).login(email: "a@b.co", password: "bad")
            XCTFail("expected throw")
        } catch {
            XCTAssertEqual(error as? AuthError, .invalidCredentials(message: "Invalid email or password."))
        }
        let saved = await store.load()
        XCTAssertNil(saved)
    }

    func testLoginTooManyAttempts() async {
        StubURLProtocol.install { _ in
            StubResponse(429, "{\"error\":\"Try again in 60 seconds.\",\"retryAfterSeconds\":60}")
        }
        do {
            _ = try await make(store: InMemorySessionStore()).login(email: "a@b.co", password: "x")
            XCTFail("expected throw")
        } catch {
            XCTAssertEqual(error as? AuthError, .tooManyAttempts(message: "Try again in 60 seconds."))
        }
    }

    // MARK: register

    func testRegisterSavesSession() async throws {
        let json = authJSON(access: "a2", refresh: "r2")
        StubURLProtocol.install { _ in StubResponse(200, json) }
        let store = InMemorySessionStore()
        let session = try await make(store: store)
            .register(email: "n@b.co", password: "password1", confirmPassword: "password1")
        XCTAssertEqual(session.refreshToken, "r2")
        let saved = await store.load()
        XCTAssertEqual(saved?.accessToken, "a2")
        let request = StubURLProtocol.requests[0]
        XCTAssertEqual(request.url?.path, "/v1/auth/register")
        XCTAssertEqual(body(request)["confirmPassword"] as? String, "password1")
    }

    func testRegisterEmailTaken() async {
        StubURLProtocol.install { _ in StubResponse(409, "{\"error\":\"Email already registered.\"}") }
        let store = InMemorySessionStore()
        do {
            _ = try await make(store: store)
                .register(email: "n@b.co", password: "password1", confirmPassword: "password1")
            XCTFail("expected throw")
        } catch {
            XCTAssertEqual(error as? AuthError, .emailTaken(message: "Email already registered."))
        }
        let saved = await store.load()
        XCTAssertNil(saved)
    }

    func testRegisterValidationFailure() async {
        StubURLProtocol.install { _ in
            StubResponse(400, "{\"title\":\"One or more validation errors occurred.\",\"status\":400}")
        }
        do {
            _ = try await make(store: InMemorySessionStore())
                .register(email: "bad", password: "x", confirmPassword: "y")
            XCTFail("expected throw")
        } catch {
            XCTAssertEqual(error as? AuthError, .validation(message: nil))
            XCTAssertEqual((error as? AuthError)?.errorDescription, "Check your details and try again.")
        }
    }

    func testRegisterClosed() async {
        StubURLProtocol.install { _ in StubResponse(403, "{\"error\":\"Registration is closed.\"}") }
        do {
            _ = try await make(store: InMemorySessionStore())
                .register(email: "n@b.co", password: "password1", confirmPassword: "password1")
            XCTFail("expected throw")
        } catch {
            XCTAssertEqual(error as? AuthError, .registrationClosed(message: "Registration is closed."))
        }
    }

    // MARK: google

    func testGoogleSavesSession() async throws {
        let json = authJSON()
        StubURLProtocol.install { _ in StubResponse(200, json) }
        let store = InMemorySessionStore()
        _ = try await make(store: store).signInWithGoogle(idToken: "tok")
        let saved = await store.load()
        XCTAssertEqual(saved?.userId, "u1")
        let request = StubURLProtocol.requests[0]
        XCTAssertEqual(request.url?.path, "/v1/auth/google")
        XCTAssertEqual(body(request)["idToken"] as? String, "tok")
    }

    func testGoogleRejectedToken() async {
        StubURLProtocol.install { _ in StubResponse(401, "{\"error\":\"Google token invalid.\"}") }
        let store = InMemorySessionStore()
        do {
            _ = try await make(store: store).signInWithGoogle(idToken: "bad")
            XCTFail("expected throw")
        } catch {
            XCTAssertEqual(error as? AuthError, .invalidCredentials(message: "Google token invalid."))
        }
        let saved = await store.load()
        XCTAssertNil(saved)
    }

    func testUnmappedStatusIsOther() async {
        StubURLProtocol.install { _ in StubResponse(500) }
        do {
            _ = try await make(store: InMemorySessionStore()).signInWithGoogle(idToken: "t")
            XCTFail("expected throw")
        } catch {
            XCTAssertEqual(error as? AuthError, .other(ApiError(status: 500, body: nil)))
        }
    }

    // MARK: logout

    func testLogoutCallsServerThenClears() async {
        StubURLProtocol.install { _ in StubResponse(204) }
        let store = InMemorySessionStore(session: old())
        await make(store: store).logout()
        let saved = await store.load()
        XCTAssertNil(saved)
        let request = StubURLProtocol.requests[0]
        XCTAssertEqual(request.url?.path, "/v1/auth/logout")
        XCTAssertEqual(body(request)["refreshToken"] as? String, "oldR")
    }

    func testLogoutClearsEvenWhenServerFails() async {
        StubURLProtocol.install { _ in StubResponse(500) }
        let store = InMemorySessionStore(session: old())
        await make(store: store).logout()
        let saved = await store.load()
        XCTAssertNil(saved)
        XCTAssertEqual(StubURLProtocol.requests.count, 1)
    }

    func testLogoutWithoutSessionMakesNoCall() async {
        StubURLProtocol.install { _ in StubResponse(204) }
        let store = InMemorySessionStore()
        await make(store: store).logout()
        XCTAssertEqual(StubURLProtocol.requests.count, 0)
    }

    // MARK: registration status

    func testRegistrationEnabled() async throws {
        StubURLProtocol.install { _ in StubResponse(200, "{\"enabled\":false}") }
        let enabled = try await make(store: InMemorySessionStore()).registrationEnabled()
        XCTAssertFalse(enabled)
        XCTAssertEqual(StubURLProtocol.requests[0].httpMethod, "GET")
    }
}
