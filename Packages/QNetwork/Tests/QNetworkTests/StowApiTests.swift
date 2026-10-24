import XCTest
import QModel
@testable import QNetwork

final class StowApiTests: XCTestCase {
    private let base = URL(string: "https://api.test")!

    private func make() -> StowApi {
        let store = InMemorySessionStore()
        let client = ApiClient(
            baseURL: base, clientHeader: "ios/1", session: StubURLProtocol.makeSession(), store: store)
        return StowApi(client: client)
    }

    private func bodyObject(_ request: URLRequest) -> [String: Any] {
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

    private let stowageJSON = """
    [{"unitKey":"02-daily-life","lessons":[{"lessonKey":"01-family","stowedAt":"2026-10-24T12:00:00+00:00","lessonsCompletedSince":3,"readyPromptDue":true,"muted":false}]},
     {"unitKey":"01-greetings","lessons":[]}]
    """

    func testStowSendsLessonKeyAndDecodes() async throws {
        let json = "{\"applied\":true,\"position\":{\"unitKey\":\"01-greetings\",\"skillKey\":\"02-numbers\"},\"stowage\":\(stowageJSON)}"
        StubURLProtocol.install { _ in StubResponse(200, json) }
        let response = try await make().stow(lessonKey: "01-hello")
        XCTAssertTrue(response.applied)
        XCTAssertEqual(response.position, PositionRef(unitKey: "01-greetings", skillKey: "02-numbers"))
        XCTAssertEqual(response.stowage.map { $0.unitKey }, ["02-daily-life", "01-greetings"])
        XCTAssertTrue(response.stowage[0].lessons[0].readyPromptDue)
        let request = StubURLProtocol.requests[0]
        XCTAssertEqual(request.url?.path, "/v1/journey/stow")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(bodyObject(request)["lessonKey"] as? String, "01-hello")
    }

    func testStowIdempotentRepeatIsNotApplied() async throws {
        StubURLProtocol.install { _ in
            StubResponse(200, "{\"applied\":false,\"position\":{\"unitKey\":\"u\",\"skillKey\":\"s\"},\"stowage\":[]}")
        }
        let response = try await make().stow(lessonKey: "a")
        XCTAssertFalse(response.applied)
        XCTAssertEqual(response.stowage, [])
    }

    func testSnoozeSendsNoBody() async throws {
        StubURLProtocol.install { _ in StubResponse(200, "{\"applied\":true,\"stowage\":\(self.stowageJSON)}") }
        let response = try await make().snoozeStowage()
        XCTAssertTrue(response.applied)
        XCTAssertEqual(response.stowage.count, 2)
        let request = StubURLProtocol.requests[0]
        XCTAssertEqual(request.url?.path, "/v1/journey/stowage/snooze")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertNil(request.httpBody)
        XCTAssertNil(request.httpBodyStream)
    }

    func testMuteSendsNoBodyAndNothingNewIsNotAnError() async throws {
        StubURLProtocol.install { _ in StubResponse(200, "{\"applied\":false,\"stowage\":[]}") }
        let response = try await make().muteStowage()
        XCTAssertFalse(response.applied)
        let request = StubURLProtocol.requests[0]
        XCTAssertEqual(request.url?.path, "/v1/journey/stowage/mute")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertNil(request.httpBody)
        XCTAssertNil(request.httpBodyStream)
    }

    func testStowErrorReasons() async {
        let cases: [(Int, String, StowError)] = [
            (400, "invalid_request", .invalidRequest),
            (404, "unknown_lesson", .unknownLesson),
            (409, "not_current_position", .notCurrentPosition),
            (409, "no_failed_attempt", .noFailedAttempt),
            (409, "already_cleared", .alreadyCleared),
            (409, "already_dropped", .alreadyDropped),
            (409, "not_provisioned", .notProvisioned),
        ]
        for (status, reason, expected) in cases {
            StubURLProtocol.install { _ in
                StubResponse(status, "{\"error\":\"nope\",\"reason\":\"\(reason)\"}")
            }
            do {
                _ = try await make().stow(lessonKey: "a")
                XCTFail("expected throw for \(reason)")
            } catch {
                XCTAssertEqual(error as? StowError, expected, reason)
            }
        }
    }

    func testSnoozeAndMuteMapErrorsToo() async {
        StubURLProtocol.install { _ in StubResponse(409, "{\"error\":\"x\",\"reason\":\"not_provisioned\"}") }
        do {
            _ = try await make().snoozeStowage()
            XCTFail("expected throw")
        } catch {
            XCTAssertEqual(error as? StowError, .notProvisioned)
        }
        do {
            _ = try await make().muteStowage()
            XCTFail("expected throw")
        } catch {
            XCTAssertEqual(error as? StowError, .notProvisioned)
        }
    }

    func testUnlistedFailuresStayApiErrors() async {
        // A 409 with an unknown reason, a 404 with another reason, a 401 and a 500 are not Stow errors.
        let cases: [(Int, String)] = [
            (409, "{\"error\":\"x\",\"reason\":\"something_else\"}"),
            (404, "{\"error\":\"x\",\"reason\":\"not_provisioned\"}"),
            (409, "{\"error\":\"x\"}"),
            (401, ""),
            (500, "oops"),
        ]
        for (status, body) in cases {
            StubURLProtocol.install { _ in StubResponse(status, body) }
            do {
                _ = try await make().stow(lessonKey: "a")
                XCTFail("expected throw for \(status)")
            } catch {
                XCTAssertEqual((error as? ApiError)?.status, status)
            }
        }
    }
}
