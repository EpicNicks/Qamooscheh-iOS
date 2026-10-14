import XCTest
import QModel
import QNetwork
@testable import QData

final class FriendsRepositoryTests: XCTestCase {
    private func makeRepo() -> FriendsRepository {
        let store = InMemorySessionStore(session: StoredSession(
            userId: "u", accessToken: "tok",
            accessTokenExpiresAt: Date().addingTimeInterval(3600), refreshToken: "r"))
        let client = ApiClient(
            baseURL: URL(string: "https://api.test")!, clientHeader: "ios/test",
            session: StubURLProtocol.makeSession(), store: store)
        return FriendsRepository(client: client)
    }

    private let id = "55555555-5555-5555-5555-555555555555"

    func testFriendsAndRequestsDecodeGoldenJson() async throws {
        let json = "[{\"userId\":\"\(id)\",\"displayName\":null,\"since\":\"2026-02-01T00:00:00.000Z\"}]"
        StubURLProtocol.install { _ in StubResponse(200, json) }
        let repo = makeRepo()
        let friends = try await repo.friends()
        XCTAssertEqual(friends.first?.userId, id)
        XCTAssertNil(friends.first?.displayName)
        _ = try await repo.incomingRequests()
        XCTAssertEqual(StubURLProtocol.requests.map { $0.url?.path }, ["/v1/friends", "/v1/friends/requests"])
        XCTAssertEqual(StubURLProtocol.requests.first?.httpMethod, "GET")
    }

    func testShortQuerySkipsTheNetwork() async throws {
        StubURLProtocol.install { _ in StubResponse(200, "[]") }
        let hits = try await makeRepo().search(" a ")
        XCTAssertTrue(hits.isEmpty)
        XCTAssertTrue(StubURLProtocol.requests.isEmpty)
    }

    func testSearchSendsTrimmedEncodedQuery() async throws {
        let json = "[{\"userId\":\"\(id)\",\"displayName\":\"Ali & Co\"}]"
        StubURLProtocol.install { _ in StubResponse(200, json) }
        let hits = try await makeRepo().search("  Ali & Co ")
        XCTAssertEqual(hits.first?.displayName, "Ali & Co")
        let url = try XCTUnwrap(StubURLProtocol.requests.first?.url)
        XCTAssertEqual(url.path, "/v1/friends/search")
        XCTAssertEqual(url.query, "query=Ali%20%26%20Co")
    }

    func testRequestReturnsStatusAndPostsToUser() async throws {
        StubURLProtocol.install { _ in StubResponse(200, "{\"status\":\"accepted\"}") }
        let status = try await makeRepo().request(id)
        XCTAssertEqual(status, .accepted)
        let request = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/v1/friends/\(id)")
    }

    func testAcceptAndDeclineAre204Posts() async throws {
        StubURLProtocol.install { _ in StubResponse(204) }
        let repo = makeRepo()
        try await repo.accept(id)
        try await repo.decline(id)
        XCTAssertEqual(StubURLProtocol.requests.map { $0.url?.path }, ["/v1/friends/\(id)/accept", "/v1/friends/\(id)/decline"])
        XCTAssertEqual(StubURLProtocol.requests.map { $0.httpMethod }, ["POST", "POST"])
    }

    func testServerErrorMessageSurfaces() async throws {
        StubURLProtocol.install { _ in StubResponse(400, "{\"error\":\"You can't add yourself.\"}") }
        do {
            _ = try await makeRepo().request(id)
            XCTFail("expected a throw")
        } catch let error as ApiError {
            XCTAssertEqual(error.status, 400)
            XCTAssertEqual(error.body?.error, "You can't add yourself.")
        }
    }
}
