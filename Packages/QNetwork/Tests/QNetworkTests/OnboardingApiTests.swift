import XCTest
import QModel
@testable import QNetwork

final class OnboardingApiTests: XCTestCase {
    private let base = URL(string: "https://api.test")!

    private func make() -> OnboardingApi {
        let store = InMemorySessionStore()
        let client = ApiClient(
            baseURL: base, clientHeader: "ios/1", session: StubURLProtocol.makeSession(), store: store)
        return OnboardingApi(client: client)
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

    private func bootstrapJSON(active: String, enrolled: [String], complete: Bool = false) -> String {
        let codes = enrolled.map { "\"\($0)\"" }.joined(separator: ",")
        return "{\"course\":{\"code\":\"\(active)\",\"version\":1,\"manifestSha256\":\"h\"},"
            + "\"graders\":[],\"enrolledCourseCodes\":[\(codes)],\"onboardingComplete\":\(complete)}"
    }

    func testCatalog() async throws {
        StubURLProtocol.install { _ in
            StubResponse(200, "{\"courses\":[{\"code\":\"fa\",\"nativeName\":\"x\",\"latinName\":\"Persian\",\"cultureFacts\":[]}]}")
        }
        let courses = try await make().catalog()
        XCTAssertEqual(courses.map { $0.code }, ["fa"])
        let request = StubURLProtocol.requests[0]
        XCTAssertEqual(request.url?.path, "/v1/courses")
        XCTAssertEqual(request.httpMethod, "GET")
    }

    func testSetDisplayNameTrimsAndSendsNoOtherFields() async throws {
        StubURLProtocol.install { _ in StubResponse(200, "{\"displayName\":\"Sara\"}") }
        let profile = try await make().setDisplayName("  Sara ")
        XCTAssertEqual(profile.displayName, "Sara")
        let request = StubURLProtocol.requests[0]
        XCTAssertEqual(request.url?.path, "/v1/profile")
        XCTAssertEqual(request.httpMethod, "PUT")
        XCTAssertEqual(bodyObject(request)["displayName"] as? String, "Sara")
        XCTAssertNil(bodyObject(request)["fullName"] as? String)
        XCTAssertNil(bodyObject(request)["country"] as? String)
    }

    func testEnrollAllEnrollsInOrderThenSwitchesAndReturnsFinalBootstrap() async throws {
        let enrolled = bootstrapJSON(active: "ja", enrolled: ["ja"])
        let final = bootstrapJSON(active: "ja", enrolled: ["ja", "fa"])
        StubURLProtocol.install { request in
            request.httpMethod == "PUT" ? StubResponse(200, final) : StubResponse(200, enrolled)
        }
        let result = try await make().enrollAll(courseCodes: ["ja", "fa"], active: "ja")
        XCTAssertEqual(result.enrolledCourseCodes, ["ja", "fa"])
        let requests = StubURLProtocol.requests
        XCTAssertEqual(requests.map { $0.httpMethod ?? "" }, ["POST", "POST", "PUT"])
        XCTAssertEqual(requests.map { $0.url?.path ?? "" },
                       ["/v1/courses/ja/enroll", "/v1/courses/fa/enroll", "/v1/courses/active"])
        XCTAssertEqual(bodyObject(requests[2])["courseCode"] as? String, "ja")
    }

    func testEnrollAllStopsAtFirstFailure() async {
        let ok = bootstrapJSON(active: "ja", enrolled: ["ja"])
        StubURLProtocol.install { request in
            request.url?.path == "/v1/courses/fa/enroll"
                ? StubResponse(404, "{\"error\":\"No such course.\"}")
                : StubResponse(200, ok)
        }
        do {
            _ = try await make().enrollAll(courseCodes: ["ja", "fa", "xx"], active: "ja")
            XCTFail("expected throw")
        } catch {
            XCTAssertEqual((error as? ApiError)?.status, 404)
        }
        XCTAssertEqual(StubURLProtocol.requests.count, 2)
    }

    func testCompleteOnboarding() async throws {
        StubURLProtocol.install { _ in StubResponse(200, "{\"onboardingComplete\":true}") }
        let done = try await make().completeOnboarding()
        XCTAssertTrue(done)
        let request = StubURLProtocol.requests[0]
        XCTAssertEqual(request.url?.path, "/v1/onboarding/complete")
        XCTAssertEqual(request.httpMethod, "POST")
    }

    func testPathSegmentEncodesSlashes() {
        XCTAssertEqual(OnboardingApi.pathSegment("a/b c"), "a%2Fb%20c")
    }
}
