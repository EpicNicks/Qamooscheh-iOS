import Foundation

/// A canned response for the stub protocol.
struct StubResponse {
    var status: Int
    var body: Data

    init(_ status: Int, _ json: String = "") {
        self.status = status
        self.body = Data(json.utf8)
    }
}

/// Intercepts URLSession traffic so tests never touch the network.
final class StubURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var handler: ((URLRequest) -> StubResponse)?
    private static var recorded: [URLRequest] = []

    static func install(_ handler: @escaping (URLRequest) -> StubResponse) {
        lock.lock()
        defer { lock.unlock() }
        self.handler = handler
        recorded = []
    }

    static var requests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        StubURLProtocol.lock.lock()
        StubURLProtocol.recorded.append(request)
        let handler = StubURLProtocol.handler
        StubURLProtocol.lock.unlock()

        let stub = handler?(request) ?? StubResponse(500)
        let url = request.url ?? URL(string: "https://stub.invalid")!
        let response = HTTPURLResponse(
            url: url, statusCode: stub.status, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
