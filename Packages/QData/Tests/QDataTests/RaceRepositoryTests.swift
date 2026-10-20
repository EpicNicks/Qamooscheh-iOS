import XCTest
import QModel
import QNetwork
@testable import QData

final class RaceRepositoryTests: XCTestCase {
    private let runId = "77777777-7777-7777-7777-777777777777"

    private func makeRepo() -> RaceRepository {
        let store = InMemorySessionStore(session: StoredSession(
            userId: "u", accessToken: "tok",
            accessTokenExpiresAt: Date().addingTimeInterval(3600), refreshToken: "r"))
        let client = ApiClient(
            baseURL: URL(string: "https://api.test")!, clientHeader: "ios/test",
            session: StubURLProtocol.makeSession(), store: store)
        return RaceRepository(client: client)
    }

    private func bodyData(_ request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let n = stream.read(&buffer, maxLength: buffer.count)
            if n <= 0 { break }
            data.append(buffer, count: n)
        }
        return data
    }

    func testStartPostsTheDeckAsATouchDevice() async throws {
        StubURLProtocol.install { _ in
            StubResponse(200, #"{"runId":"77777777-7777-7777-7777-777777777777","serverStartedAt":"2026-03-01T12:30:45.123+00:00","weights":{"a":1.5}}"#)
        }
        let started = try await makeRepo().start(courseCode: "fa", mode: .perfectDelivery, hardcore: true, tags: ["a", "b"])
        XCTAssertEqual(started.runId, runId)
        XCTAssertEqual(started.weights, ["a": 1.5])
        let request = StubURLProtocol.requests.first
        XCTAssertEqual(request?.httpMethod, "POST")
        XCTAssertEqual(request?.url?.path, "/v1/race/runs")
        let sent = try QJSON.makeDecoder().decode(StartRaceRequest.self, from: bodyData(try XCTUnwrap(request)))
        XCTAssertEqual(sent, StartRaceRequest(courseCode: "fa", mode: .perfectDelivery, hardcore: true, deviceClass: .touch, tags: ["a", "b"]))
    }

    func testFinishPostsEveryAnswerToTheRun() async throws {
        StubURLProtocol.install { _ in
            StubResponse(200, #"{"score":1.5,"timeMs":9000,"solved":1,"strikes":0,"endReason":"deck_done","xp":5,"held":false,"alreadyFinished":false}"#)
        }
        let response = try await makeRepo().finish(
            runId: runId, answers: [RaceAnswer(tag: "a", attempt: 1, correct: true, elapsedMs: 2000)], deckDone: true)
        XCTAssertEqual(response.xp, 5)
        XCTAssertNil(response.rank)
        let request = StubURLProtocol.requests.first
        XCTAssertEqual(request?.httpMethod, "POST")
        XCTAssertEqual(request?.url?.path, "/v1/race/runs/\(runId)/finish")
    }

    func testARunIdThatIsNotAGuidNeverReachesTheNetwork() async {
        StubURLProtocol.install { _ in StubResponse(200, "{}") }
        do {
            _ = try await makeRepo().finish(runId: "../x", answers: [], deckDone: false)
            XCTFail("expected throw")
        } catch {
            XCTAssertTrue(error is URLError)
        }
        XCTAssertTrue(StubURLProtocol.requests.isEmpty)
    }

    func testBoardAsksForPerfectDeliveryOnTouchByScopeAndHardcore() async throws {
        StubURLProtocol.install { _ in
            StubResponse(200, #"{"entries":[{"rank":1,"userId":"88888888-8888-8888-8888-888888888888","score":9.5,"timeMs":60000,"isYou":false}]}"#)
        }
        let board = try await makeRepo().board(courseCode: "fa", scope: .weekly, hardcore: true, weekOf: "2026-03-01")
        XCTAssertEqual(board.entries.first?.rank, 1)
        let request = StubURLProtocol.requests.first
        XCTAssertEqual(request?.httpMethod, "GET")
        XCTAssertEqual(request?.url?.path, "/v1/race/boards")
        let items = URLComponents(url: try XCTUnwrap(request?.url), resolvingAgainstBaseURL: false)?.queryItems ?? []
        let query = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(query, [
            "courseCode": "fa", "mode": "perfect_delivery", "scope": "weekly", "deviceClass": "touch", "hardcore": "true", "week": "2026-03-01",
        ])
    }
}
