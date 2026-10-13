import XCTest
import QModel
import QNetwork
@testable import QData

final class LessonRepositoryTests: XCTestCase {
    private let course = CourseRef(code: "fa", version: 7, manifestSha256: "x")

    private func makeRepo() -> LessonRepository {
        let store = InMemorySessionStore(session: StoredSession(
            userId: "u", accessToken: "tok",
            accessTokenExpiresAt: Date().addingTimeInterval(3600), refreshToken: "r"))
        let client = ApiClient(
            baseURL: URL(string: "https://api.test")!, clientHeader: "ios/test",
            session: StubURLProtocol.makeSession(), store: store)
        return LessonRepository(client: client)
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

    private let planJson = "{\"courseVersion\":7,\"skills\":[{\"unitKey\":\"u1\",\"skillKey\":\"s1\"},{\"unitKey\":null,\"skillKey\":\"t1\"}],\"reviewTags\":[\"a\"],\"newTags\":[\"b\"],\"prefetchTags\":[]}"

    func testPlanRequestAndDecode() async throws {
        let json = planJson
        StubURLProtocol.install { _ in StubResponse(200, json) }
        let plan = try await makeRepo().plan(course: course, position: nil)
        let request = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.path, "/v1/sessions/next")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
        XCTAssertEqual(plan.skills.count, 2)
        XCTAssertNil(plan.skills[1].unitKey)
        XCTAssertEqual(plan.reviewTags, ["a"])
    }

    func testPlanEmptyFallsBackToPositionKeepingServerVersion() async throws {
        StubURLProtocol.install { _ in
            StubResponse(200, "{\"courseVersion\":9,\"skills\":[],\"reviewTags\":[],\"newTags\":[],\"prefetchTags\":[]}")
        }
        let plan = try await makeRepo().plan(course: course, position: PositionRef(unitKey: "u2", skillKey: "s2"))
        XCTAssertEqual(plan.courseVersion, 9)
        XCTAssertEqual(plan.skills, [SkillRef(unitKey: "u2", skillKey: "s2")])
    }

    func testPlanOfflineFallsBackToPosition() async throws {
        StubURLProtocol.install { _ in StubResponse(failing: .notConnectedToInternet) }
        let plan = try await makeRepo().plan(course: course, position: PositionRef(unitKey: "u2", skillKey: "s2"))
        XCTAssertEqual(plan.courseVersion, 7)
        XCTAssertEqual(plan.skills, [SkillRef(unitKey: "u2", skillKey: "s2")])
    }

    func testPlanServerErrorThrows() async {
        StubURLProtocol.install { _ in StubResponse(500, "{\"error\":\"boom\"}") }
        do {
            _ = try await makeRepo().plan(course: course, position: nil)
            XCTFail("expected throw")
        } catch let error as ApiError {
            XCTAssertEqual(error.status, 500)
            XCTAssertEqual(error.body?.error, "boom")
        } catch {
            XCTFail("wrong error \(error)")
        }
    }

    func testDeepDivePathEncodedAndDecoded() async throws {
        let json = planJson
        StubURLProtocol.install { _ in StubResponse(200, json) }
        let plan = try await makeRepo().deepDivePlan(course: course, lessonKey: "a b/c")
        let request = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://api.test/v1/sessions/for-lesson/a%20b%2Fc")
        XCTAssertEqual(plan?.skills.count, 2)
    }

    func testDeepDive404IsNil() async throws {
        StubURLProtocol.install { _ in StubResponse(404, "{\"error\":\"no\"}") }
        let plan = try await makeRepo().deepDivePlan(course: course, lessonKey: "x")
        XCTAssertNil(plan)
    }

    func testDeepDiveOfflinePlaysLessonWhole() async throws {
        StubURLProtocol.install { _ in StubResponse(failing: .timedOut) }
        let plan = try await makeRepo().deepDivePlan(course: course, lessonKey: "x")
        XCTAssertEqual(plan?.courseVersion, 7)
        XCTAssertEqual(plan?.skills, [SkillRef(unitKey: nil, skillKey: "x")])
    }

    func testDeepDiveOtherErrorThrows() async {
        StubURLProtocol.install { _ in StubResponse(403, "") }
        do {
            _ = try await makeRepo().deepDivePlan(course: course, lessonKey: "x")
            XCTFail("expected throw")
        } catch let error as ApiError {
            XCTAssertEqual(error.status, 403)
        } catch {
            XCTFail("wrong error \(error)")
        }
    }

    func testSubmitBodyAndResponse() async throws {
        StubURLProtocol.install { _ in
            StubResponse(200, "{\"sessions\":[{\"submissionId\":\"s-1\",\"outcome\":\"Processed\",\"rejectionReason\":null,\"cards\":[{\"lexemeTag\":\"w\",\"stability\":1.5,\"difficulty\":2.5,\"lastReviewedAt\":\"2026-01-02T03:04:05.1234567+00:00\",\"dueAt\":null,\"reviewCount\":1,\"lapseCount\":0}],\"score\":0.9,\"lessonCompleted\":true,\"xp\":12}]}")
        }
        let item = SubmittedItem(
            exerciseOrdinal: 1, lexemeTag: "w", exerciseType: .typeIn, scriptMode: .native,
            submittedText: "x", usedHint: false, attempt: 1)
        let session = SubmittedSession(
            submissionId: "s-1", courseCode: "fa", unitKey: nil, skillKey: "t1", courseVersion: 7,
            occurredAt: Date(timeIntervalSince1970: 0), completed: true, items: [item])
        let response = try await makeRepo().submit([session])
        let request = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/v1/sessions/submit")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: bodyData(request)) as? [String: Any])
        let sessions = try XCTUnwrap(json["sessions"] as? [[String: Any]])
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0]["submissionId"] as? String, "s-1")
        XCTAssertEqual(sessions[0]["courseCode"] as? String, "fa")
        XCTAssertEqual(sessions[0]["occurredAt"] as? String, "1970-01-01T00:00:00.000Z")
        XCTAssertEqual(sessions[0]["completed"] as? Bool, true)
        let items = try XCTUnwrap(sessions[0]["items"] as? [[String: Any]])
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0]["exerciseType"] as? String, "type_in")
        XCTAssertEqual(response.sessions.count, 1)
        XCTAssertEqual(response.sessions[0].submissionId, "s-1")
        XCTAssertEqual(response.sessions[0].outcome, .processed)
        XCTAssertEqual(response.sessions[0].cards[0].reviewCount, 1)
        XCTAssertEqual(response.sessions[0].xp, 12)
        XCTAssertEqual(response.sessions[0].lessonCompleted, true)
    }

    func testSubmitErrorMapsToApiError() async {
        StubURLProtocol.install { _ in StubResponse(400, "{\"error\":\"bad\",\"reason\":\"r\"}") }
        do {
            _ = try await makeRepo().submit([])
            XCTFail("expected throw")
        } catch let error as ApiError {
            XCTAssertEqual(error.status, 400)
            XCTAssertEqual(error.body?.reason, "r")
        } catch {
            XCTFail("wrong error \(error)")
        }
    }

    func testCompletedLessons() async throws {
        StubURLProtocol.install { _ in StubResponse(200, "{\"courseCode\":\"fa\",\"completedLessonKeys\":[\"a\",\"b\"]}") }
        let result = try await makeRepo().completedLessons(courseCode: "fa")
        let request = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.absoluteString, "https://api.test/v1/lessons/completed?courseCode=fa")
        XCTAssertEqual(result.completedLessonKeys, ["a", "b"])
    }
}
