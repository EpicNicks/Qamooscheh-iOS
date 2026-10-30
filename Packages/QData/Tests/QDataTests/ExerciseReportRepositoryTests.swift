import XCTest
import QModel
import QNetwork
@testable import QData

final class ExerciseReportRepositoryTests: XCTestCase {
    private func makeRepo() -> ExerciseReportRepository {
        let store = InMemorySessionStore(session: StoredSession(
            userId: "u", accessToken: "tok",
            accessTokenExpiresAt: Date().addingTimeInterval(3600), refreshToken: "r"))
        let client = ApiClient(
            baseURL: URL(string: "https://api.test")!, clientHeader: "ios/test",
            session: StubURLProtocol.makeSession(), store: store)
        return ExerciseReportRepository(client: client)
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

    func testSubmitPostsTheReportAndDecodes() async throws {
        StubURLProtocol.install { _ in StubResponse(200, "{\"id\":42,\"createdAt\":\"2026-10-29T12:00:00Z\"}") }
        let body = SubmitExerciseReportRequest(
            exercisePrompt: "Hello", exerciseTags: ["salam<interj>"], reasons: [.audioWrong, .other],
            details: "cuts off", submittedAnswer: "salam ", renderType: .typeIn,
            courseVersion: 6, unitKey: "u1", skillKey: "a", exerciseOrdinal: 3,
            audioFiles: ["../../../audio/a.mp3"])
        let response = try await makeRepo().submit(body)
        let request = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/v1/exercise-reports")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
        let sent = try XCTUnwrap(try JSONSerialization.jsonObject(with: bodyData(request)) as? [String: Any])
        XCTAssertEqual(sent["exercisePrompt"] as? String, "Hello")
        XCTAssertEqual(sent["exerciseTags"] as? [String], ["salam<interj>"])
        XCTAssertEqual(sent["reasons"] as? [String], ["audio_wrong", "other"])
        XCTAssertEqual(sent["details"] as? String, "cuts off")
        XCTAssertEqual(sent["submittedAnswer"] as? String, "salam ")
        XCTAssertEqual(sent["renderType"] as? String, "type_in")
        XCTAssertEqual(sent["courseVersion"] as? Int, 6)
        XCTAssertEqual(sent["unitKey"] as? String, "u1")
        XCTAssertEqual(sent["skillKey"] as? String, "a")
        XCTAssertEqual(sent["exerciseOrdinal"] as? Int, 3)
        XCTAssertEqual(sent["audioFiles"] as? [String], ["../../../audio/a.mp3"])
        XCTAssertEqual(response.id, 42)
    }

    func testUnansweredReportLeavesOutTheAnswerAndLocation() async throws {
        StubURLProtocol.install { _ in StubResponse(200, "{\"id\":1,\"createdAt\":\"2026-10-29T12:00:00Z\"}") }
        let body = SubmitExerciseReportRequest(exercisePrompt: "Hello", exerciseTags: ["t"], reasons: [.audioWrong])
        try await makeRepo().submit(body)
        let request = try XCTUnwrap(StubURLProtocol.requests.first)
        let sent = try XCTUnwrap(try JSONSerialization.jsonObject(with: bodyData(request)) as? [String: Any])
        XCTAssertNil(sent["submittedAnswer"])
        XCTAssertNil(sent["courseVersion"])
        XCTAssertNil(sent["audioFiles"])
        XCTAssertNil(sent["details"])
    }

    func testServerErrorThrows() async {
        StubURLProtocol.install { _ in StubResponse(400, "{\"error\":\"bad\"}") }
        do {
            try await makeRepo().submit(SubmitExerciseReportRequest(exercisePrompt: "p", exerciseTags: ["t"], reasons: [.other]))
            XCTFail("expected throw")
        } catch let error as ApiError {
            XCTAssertEqual(error.status, 400)
        } catch {
            XCTFail("unexpected \(error)")
        }
    }
}
