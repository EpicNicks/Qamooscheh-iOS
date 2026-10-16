import XCTest
import QModel
import QNetwork
import QData
@testable import QFeatures

private final class CountingURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var recorded: [URLRequest] = []

    static func reset() {
        lock.lock()
        recorded = []
        lock.unlock()
    }

    static var requests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        CountingURLProtocol.lock.lock()
        CountingURLProtocol.recorded.append(request)
        CountingURLProtocol.lock.unlock()
        let body = Data(#"{"courseVersion":3,"words":[{"tag":"a","exercises":[{"unitKey":"u1","skillKey":"s1","ordinal":2}]}]}"#.utf8)
        let url = request.url ?? URL(string: "https://stub.invalid")!
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class LiveSavedPracticeSourceTests: XCTestCase {
    func testCountBecomesTheWordsQueryAndTheResponseComesBack() async throws {
        CountingURLProtocol.reset()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [CountingURLProtocol.self]
        let store = InMemorySessionStore(session: StoredSession(
            userId: "u", accessToken: "tok",
            accessTokenExpiresAt: Date().addingTimeInterval(3600), refreshToken: "r"))
        let client = ApiClient(
            baseURL: URL(string: "https://api.test")!, clientHeader: "ios/test",
            session: URLSession(configuration: config), store: store)
        let source = LiveSavedPracticeSource(repository: VocabRepository(client: client))
        let response = try await source.practice(count: 7)
        XCTAssertEqual(response.courseVersion, 3)
        XCTAssertEqual(response.words.map { $0.tag }, ["a"])
        let request = CountingURLProtocol.requests.first
        XCTAssertEqual(request?.url?.path, "/v1/vocab/starred/practice")
        XCTAssertEqual(request?.url?.query, "words=7")
    }
}
