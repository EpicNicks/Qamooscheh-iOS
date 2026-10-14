import XCTest
import QModel
import QNetwork
@testable import QData

final class LeagueRepositoryTests: XCTestCase {
    private func makeRepo() -> LeagueRepository {
        let store = InMemorySessionStore(session: StoredSession(
            userId: "u", accessToken: "tok",
            accessTokenExpiresAt: Date().addingTimeInterval(3600), refreshToken: "r"))
        let client = ApiClient(
            baseURL: URL(string: "https://api.test")!, clientHeader: "ios/test",
            session: StubURLProtocol.makeSession(), store: store)
        return LeagueRepository(client: client)
    }

    func testDecodesGoldenJson() async throws {
        let json = """
        {"tier":2,"periodEndsAt":"2026-03-08T00:00:00.000Z",
         "standings":[{"userId":"55555555-5555-5555-5555-555555555555","displayName":null,"points":120}]}
        """
        StubURLProtocol.install { _ in StubResponse(200, json) }
        let league = try await makeRepo().current()
        XCTAssertEqual(league?.tier, 2)
        XCTAssertNil(league?.standings.first?.displayName)
        XCTAssertEqual(StubURLProtocol.requests.first?.url?.path, "/v1/leagues/current")
        XCTAssertEqual(StubURLProtocol.requests.first?.httpMethod, "GET")
    }

    func testNotFoundIsNoLeague() async throws {
        StubURLProtocol.install { _ in StubResponse(404, "{\"error\":\"none\"}") }
        let league = try await makeRepo().current()
        XCTAssertNil(league)
    }

    func testServerErrorsStillThrow() async {
        StubURLProtocol.install { _ in StubResponse(500, "{\"error\":\"Boom\"}") }
        do {
            _ = try await makeRepo().current()
            XCTFail("expected throw")
        } catch {
            XCTAssertEqual((error as? ApiError)?.status, 500)
        }
    }
}
