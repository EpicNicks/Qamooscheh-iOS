import XCTest
import QModel
@testable import QNetwork

final class CdnClientTests: XCTestCase {
    private let manifestJSON = "{\"courseCode\":\"fa\",\"version\":3,\"units\":[{\"id\":\"u1\",\"path\":\"units/u1.json\"}],\"lexemeIndexPath\":\"lexemes.json\"}"

    private func makeClient() -> CdnClient {
        CdnClient(baseURL: URL(string: "https://cdn.test")!, session: StubURLProtocol.makeSession())
    }

    func testSha256KnownVector() {
        XCTAssertEqual(Sha256.hex(Data("abc".utf8)),
                       "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    func testVerifiedManifestDecodes() async throws {
        let json = manifestJSON
        StubURLProtocol.install { _ in StubResponse(200, json) }
        let hash = Sha256.hex(Data(json.utf8))
        let manifest = try await makeClient().courseManifest(courseCode: "fa", version: 3, manifestSha256: hash.uppercased())
        XCTAssertEqual(manifest.courseCode, "fa")
        XCTAssertEqual(manifest.units.count, 1)
        XCTAssertEqual(StubURLProtocol.requests[0].url?.absoluteString, "https://cdn.test/course/fa/v3/manifest.json")
    }

    func testTamperedManifestIsRejected() async throws {
        let json = manifestJSON
        StubURLProtocol.install { _ in StubResponse(200, json) }
        let wrong = Sha256.hex(Data("other".utf8))
        do {
            _ = try await makeClient().courseManifest(courseCode: "fa", version: 3, manifestSha256: wrong)
            XCTFail("expected mismatch")
        } catch let error as ManifestHashMismatchError {
            XCTAssertEqual(error.expected, wrong)
            XCTAssertEqual(error.actual, Sha256.hex(Data(json.utf8)))
        }
    }

    func testNon2xxThrowsFetchError() async throws {
        StubURLProtocol.install { _ in StubResponse(404) }
        do {
            _ = try await makeClient().courseManifest(courseCode: "fa", version: 3, manifestSha256: "00")
            XCTFail("expected CdnFetchError")
        } catch let error as CdnFetchError {
            XCTAssertEqual(error.status, 404)
        }
    }

    func testChildArtifactIsFetchedWithoutVerification() async throws {
        StubURLProtocol.install { _ in StubResponse(200, "{\"id\":\"u1\",\"path\":\"p\"}") }
        let ref: ManifestRef = try await makeClient().artifact(courseCode: "fa", version: 3, path: "units/u1.json")
        XCTAssertEqual(ref, ManifestRef(id: "u1", path: "p"))
        XCTAssertEqual(StubURLProtocol.requests[0].url?.absoluteString, "https://cdn.test/course/fa/v3/units/u1.json")
    }

    func testContentURLClimbsOutOfVersionRoot() {
        let url = makeClient().contentURL(courseCode: "fa", version: 3, relativePath: "../../../audio/abc.mp3")
        XCTAssertEqual(url?.absoluteString, "https://cdn.test/audio/abc.mp3")
    }
}
