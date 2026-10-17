import XCTest
import QModel
import QNetwork
@testable import QData

final class ContactsRepositoryTests: XCTestCase {
    private func makeRepo() -> ContactsRepository {
        let store = InMemorySessionStore(session: StoredSession(
            userId: "u", accessToken: "tok",
            accessTokenExpiresAt: Date().addingTimeInterval(3600), refreshToken: "r"))
        let client = ApiClient(
            baseURL: URL(string: "https://api.test")!, clientHeader: "ios/test",
            session: StubURLProtocol.makeSession(), store: store)
        return ContactsRepository(client: client)
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

    func testSha256KnownAnswers() {
        XCTAssertEqual(ContactHashing.sha256Hex(""), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        XCTAssertEqual(ContactHashing.sha256Hex("abc"), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        XCTAssertEqual(ContactHashing.sha256Hex("hello"), "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")
    }

    func testEmailIsTrimmedAndLowerCasedBeforeHashing() {
        let expected = ContactHashing.sha256Hex("foo@example.com")
        XCTAssertEqual(ContactHashing.hash(email: "  Foo@Example.COM \n"), expected)
        XCTAssertEqual(expected.count, 64)
        XCTAssertNil(ContactHashing.hash(email: "   "))
    }

    func testHashesDedupeAndCap() {
        let result = ContactHashing.hashes(emails: ["A@x.com", "a@x.com ", "", "b@x.com", "c@x.com"], limit: 2)
        XCTAssertEqual(result.hashes, [ContactHashing.sha256Hex("a@x.com"), ContactHashing.sha256Hex("b@x.com")])
        XCTAssertTrue(result.truncated)
        let all = ContactHashing.hashes(emails: ["a@x.com", "A@x.com"], limit: 2)
        XCTAssertEqual(all.hashes.count, 1)
        XCTAssertFalse(all.truncated)
    }

    func testFindableGetAndPut() async throws {
        StubURLProtocol.install { _ in StubResponse(200, "{\"findable\":true,\"canBeFound\":false}") }
        let repo = makeRepo()
        let got = try await repo.findable()
        XCTAssertEqual(got, ContactsFindableResponse(findable: true, canBeFound: false))
        let put = try await repo.setFindable(true)
        XCTAssertTrue(put.findable)
        let requests = StubURLProtocol.requests
        XCTAssertEqual(requests.map { $0.httpMethod }, ["GET", "PUT"])
        XCTAssertEqual(requests.map { $0.url?.path }, ["/v1/contacts/findable", "/v1/contacts/findable"])
        let body = try JSONSerialization.jsonObject(with: bodyData(requests[1])) as? [String: Any]
        XCTAssertEqual(body?["findable"] as? Bool, true)
    }

    func testMatchPostsOnlyHashesAndDecodesRelationship() async throws {
        let id = "55555555-5555-5555-5555-555555555555"
        let json = "{\"matches\":[{\"userId\":\"\(id)\",\"displayName\":null,\"relationship\":\"request_received\"}]}"
        StubURLProtocol.install { _ in StubResponse(200, json) }
        let hash = ContactHashing.sha256Hex("a@x.com")
        let matches = try await makeRepo().match([hash])
        XCTAssertEqual(matches, [ContactMatchResponse(userId: id, displayName: nil, relationship: .requestReceived)])
        let request = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/v1/contacts/match")
        let text = String(decoding: bodyData(request), as: UTF8.self)
        XCTAssertTrue(text.contains(hash))
        XCTAssertFalse(text.contains("a@x.com"))
    }
}
