import XCTest
import QModel
import QNetwork
@testable import QData

final class CheckpointRepositoryTests: XCTestCase {
    private func makeRepo() -> CheckpointRepository {
        let store = InMemorySessionStore(session: StoredSession(
            userId: "u", accessToken: "tok",
            accessTokenExpiresAt: Date().addingTimeInterval(3600), refreshToken: "r"))
        let client = ApiClient(
            baseURL: URL(string: "https://api.test")!, clientHeader: "ios/test",
            session: StubURLProtocol.makeSession(), store: store)
        return CheckpointRepository(client: client)
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

    func testPlanRequestAndDecode() async throws {
        StubURLProtocol.install { _ in
            StubResponse(200, "{\"courseVersion\":3,\"targetUnitKey\":\"02-family\",\"targetSkillKey\":\"01-family\",\"skills\":[{\"unitKey\":\"01-basics\",\"skillKey\":\"01-hello\",\"exerciseOrdinals\":[0,2]}],\"skippedLessons\":[],\"skippedCount\":3,\"alreadyCompletedCount\":1,\"requiresTest\":true}")
        }
        let plan = try await makeRepo().plan(unitKey: "02-family", skillKey: "01-family")
        let request = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.path, "/v1/checkpoint/02-family/01-family")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
        XCTAssertEqual(plan.skills.first?.exerciseOrdinals, [0, 2])
        XCTAssertEqual(plan.skippedCount, 3)
        XCTAssertTrue(plan.requiresTest)
    }

    func testPlanEscapesSlashesInKeys() async throws {
        StubURLProtocol.install { _ in
            StubResponse(200, "{\"courseVersion\":1,\"targetUnitKey\":\"a/b\",\"targetSkillKey\":\"c d\",\"skills\":[],\"skippedLessons\":[],\"skippedCount\":0,\"alreadyCompletedCount\":0,\"requiresTest\":false}")
        }
        _ = try await makeRepo().plan(unitKey: "a/b", skillKey: "c d")
        let request = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertTrue(request.url?.absoluteString.hasSuffix("/v1/checkpoint/a%2Fb/c%20d") ?? false)
    }

    func testSubmitPostsBodyAndDecodes() async throws {
        StubURLProtocol.install { _ in
            StubResponse(200, "{\"passed\":true,\"score\":0.9,\"cards\":[],\"skippedLessons\":[],\"skippedCount\":3,\"alreadyCompletedCount\":0,\"requiresTest\":true,\"applied\":false,\"xp\":null}")
        }
        let body = SubmitCheckpointRequest(
            submissionId: "id-1", targetUnitKey: "u2", targetSkillKey: "s1", courseVersion: 3,
            occurredAt: Date(timeIntervalSince1970: 0), skills: [])
        let response = try await makeRepo().submit(body)
        let request = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/v1/checkpoint/submit")
        let sent = try JSONSerialization.jsonObject(with: bodyData(request)) as? [String: Any]
        XCTAssertEqual(sent?["submissionId"] as? String, "id-1")
        XCTAssertEqual(sent?["targetSkillKey"] as? String, "s1")
        XCTAssertTrue(response.passed)
        XCTAssertFalse(response.applied)
        XCTAssertNil(response.xp)
    }

    func testServerErrorThrows() async {
        StubURLProtocol.install { _ in StubResponse(500, "{\"error\":\"boom\"}") }
        do {
            _ = try await makeRepo().plan(unitKey: "u", skillKey: "s")
            XCTFail("expected throw")
        } catch let error as ApiError {
            XCTAssertEqual(error.status, 500)
        } catch {
            XCTFail("wrong error \(error)")
        }
    }
}
