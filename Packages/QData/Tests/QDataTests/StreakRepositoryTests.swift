import XCTest
import QModel
import QNetwork
@testable import QData

final class StreakRepositoryTests: XCTestCase {
    private func makeRepo() -> StreakRepository {
        let store = InMemorySessionStore(session: StoredSession(
            userId: "u", accessToken: "tok",
            accessTokenExpiresAt: Date().addingTimeInterval(3600), refreshToken: "r"))
        let client = ApiClient(
            baseURL: URL(string: "https://api.test")!, clientHeader: "ios/test",
            session: StubURLProtocol.makeSession(), store: store)
        return StreakRepository(client: client)
    }

    private let streakJson = """
    {"currentStreakDays":4,"longestStreakDays":9,"practicedToday":false,"pausedToday":false,\
    "pause":{"startDay":"2026-10-14","endDay":"2026-10-16","started":false},"pauseDaysAvailable":11,\
    "timeZone":"UTC","dayStartHour":3,"today":"2026-10-13","nextDayStartsAt":"2026-10-14T03:00:00.000Z"}
    """

    func testStreakGetsAndDecodes() async throws {
        StubURLProtocol.install { _ in StubResponse(200, self.streakJson) }
        let streak = try await makeRepo().streak()
        XCTAssertEqual(streak.currentStreakDays, 4)
        XCTAssertEqual(streak.pause?.endDay, "2026-10-16")
        XCTAssertEqual(streak.pauseDaysAvailable, 11)
        let request = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.path, "/v1/streak")
    }

    func testPausePostsDaysBody() async throws {
        StubURLProtocol.install { _ in StubResponse(200, self.streakJson) }
        let streak = try await makeRepo().bookPause(StreakPauseRequest(startDay: "2026-10-14", endDay: "2026-10-16"))
        XCTAssertEqual(streak.pause?.startDay, "2026-10-14")
        let request = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/v1/streak/pause")
        let body = readBody(request)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: String])
        XCTAssertEqual(object, ["startDay": "2026-10-14", "endDay": "2026-10-16"])
    }

    func testPauseConflictSurfacesServerMessage() async throws {
        StubURLProtocol.install { _ in StubResponse(409, "{\"error\":\"A pause is already booked.\",\"code\":\"pause_exists\"}") }
        do {
            _ = try await makeRepo().bookPause(StreakPauseRequest(startDay: "2026-10-14", endDay: "2026-10-16"))
            XCTFail("expected a throw")
        } catch let error as ApiError {
            XCTAssertEqual(error.status, 409)
            XCTAssertEqual(error.body?.error, "A pause is already booked.")
        }
    }

    func testCancelDeletesAndReturnsStreak() async throws {
        StubURLProtocol.install { _ in StubResponse(200, self.streakJson) }
        let streak = try await makeRepo().endPause()
        XCTAssertNotNil(streak)
        let request = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertEqual(request.httpMethod, "DELETE")
        XCTAssertEqual(request.url?.path, "/v1/streak/pause")
    }

    func testCancelOn404IsANoOp() async throws {
        StubURLProtocol.install { _ in StubResponse(404, "{\"error\":\"No pause.\"}") }
        let streak = try await makeRepo().endPause()
        XCTAssertNil(streak)
    }

    func testCancelOtherErrorsStillThrow() async throws {
        StubURLProtocol.install { _ in StubResponse(500) }
        do {
            _ = try await makeRepo().endPause()
            XCTFail("expected a throw")
        } catch let error as ApiError {
            XCTAssertEqual(error.status, 500)
        }
    }
}
