import XCTest
import QModel
import QNetwork
@testable import QData

final class RoughSpotsRepositoryTests: XCTestCase {
    private func makeRepo() -> RoughSpotsRepository {
        let store = InMemorySessionStore(session: StoredSession(
            userId: "u", accessToken: "tok",
            accessTokenExpiresAt: Date().addingTimeInterval(3600), refreshToken: "r"))
        let client = ApiClient(
            baseURL: URL(string: "https://api.test")!, clientHeader: "ios/test",
            session: StubURLProtocol.makeSession(), store: store)
        return RoughSpotsRepository(client: client)
    }

    func testRequestAndDecode() async throws {
        StubURLProtocol.install { _ in
            StubResponse(200, "{\"courseVersion\":4,\"words\":[{\"tag\":\"khordan<v>\",\"lapses\":3,\"reviews\":9,\"retrievability\":0.4,\"exercises\":[{\"unitKey\":\"u1\",\"skillKey\":\"s1\",\"ordinal\":2,\"form\":\"khordam<v>\"}]}]}")
        }
        let response = try await makeRepo().roughSpots(words: 10)
        let request = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.path, "/v1/sessions/rough-spots")
        XCTAssertEqual(request.url?.query, "words=10&listening=exclude")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
        XCTAssertEqual(response.courseVersion, 4)
        XCTAssertEqual(response.words.map { $0.tag }, ["khordan<v>"])
        XCTAssertEqual(response.words.first?.exercises, [StarredPracticeExercise(unitKey: "u1", skillKey: "s1", ordinal: 2, form: "khordam<v>")])
    }

    func testNothingRoughDecodesToNoWords() async throws {
        StubURLProtocol.install { _ in StubResponse(200, "{\"courseVersion\":4,\"words\":[]}") }
        let response = try await makeRepo().roughSpots(words: 5)
        XCTAssertTrue(response.words.isEmpty)
    }

    func testBadQueryAndNotBootstrappedSurfaceTheirStatus() async {
        for status in [400, 409] {
            StubURLProtocol.install { _ in StubResponse(status, "{\"error\":\"nope\"}") }
            do {
                _ = try await makeRepo().roughSpots(words: 10)
                XCTFail("expected throw")
            } catch let error as ApiError {
                XCTAssertEqual(error.status, status)
            } catch {
                XCTFail("wrong error \(error)")
            }
        }
    }
}
