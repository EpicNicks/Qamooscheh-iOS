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

    func testContentURLResolvesRelativePath() throws {
        let url = try makeClient().contentURL(courseCode: "fa", version: 3, relativePath: "audio/abc.mp3")
        XCTAssertEqual(url.absoluteString, "https://cdn.test/course/fa/v3/audio/abc.mp3")
    }

    func testContentURLResolvesPublisherAudioPath() throws {
        let hash = String(repeating: "ab", count: 32)
        let url = try makeClient().contentURL(courseCode: "fa", version: 3, relativePath: "../../../audio/\(hash).mp3")
        XCTAssertEqual(url.absoluteString, "https://cdn.test/audio/\(hash).mp3")
    }

    func testContentURLWithBasePathStaysUnderBase() throws {
        let client = CdnClient(baseURL: URL(string: "https://cdn.test/base/")!, session: StubURLProtocol.makeSession())
        let url = try client.contentURL(courseCode: "fa", version: 3, relativePath: "../../../audio/x.mp3")
        XCTAssertEqual(url.absoluteString, "https://cdn.test/base/audio/x.mp3")
        XCTAssertThrowsError(try client.contentURL(courseCode: "fa", version: 3, relativePath: "../../../../audio/x.mp3"))
    }

    func testContentURLRejectsHostReplacementAndEscapes() {
        let bad = [
            "https://evil.example/a.mp3", "//evil.example/a.mp3", "/abs/a.mp3", "javascript:alert(1)",
            "mailto:x@y.z", "../../../audio/abc.mp3", "a/../b.mp3", "", "a\\b",
        ]
        for path in bad {
            XCTAssertThrowsError(try makeClient().contentURL(courseCode: "fa", version: 3, relativePath: path), path) { error in
                XCTAssertEqual(error as? InvalidContentPathError, InvalidContentPathError(path: path))
            }
        }
    }

    func testCourseCodeIsPercentEncodedPerSegment() {
        XCTAssertEqual(makeClient().courseRoot(courseCode: "a/b?c#d", version: 3),
                       "https://cdn.test/course/a%2Fb%3Fc%23d/v3")
    }

    func testBaseURLTrailingSlashIsNormalised() {
        let client = CdnClient(baseURL: URL(string: "https://cdn.test/")!, session: StubURLProtocol.makeSession())
        XCTAssertEqual(client.courseRoot(courseCode: "fa", version: 3), "https://cdn.test/course/fa/v3")
    }

    func testArtifactPathSegmentsAreEncoded() async throws {
        StubURLProtocol.install { _ in StubResponse(200, "{\"id\":\"u1\",\"path\":\"p\"}") }
        let _: ManifestRef = try await makeClient().artifact(courseCode: "fa", version: 3, path: "units/a b.json")
        XCTAssertEqual(StubURLProtocol.requests[0].url?.absoluteString, "https://cdn.test/course/fa/v3/units/a%20b.json")
    }
}
