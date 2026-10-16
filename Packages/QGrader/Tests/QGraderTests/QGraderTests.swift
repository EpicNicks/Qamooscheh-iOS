import XCTest
@testable import QGrader

final class QGraderTests: XCTestCase {
    func testModuleIdentity() {
        XCTAssertEqual(QGraderInfo.name, "QGrader")
        XCTAssertEqual(QGraderInfo.dependencyNames, ["QModel"])
    }

    func testRequestOmitsNilFields() throws {
        let request = GraderRequest(exerciseType: "TypeIn", scriptMode: "Native", submitted: "a", acceptedAnswers: ["a"])
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any]
        XCTAssertEqual(Set(json?.keys.map { $0 } ?? []), ["exerciseType", "scriptMode", "submitted", "acceptedAnswers"])
    }

    func testResponseDecodesWireJSON() throws {
        let wire = """
        {"verdict":"AcceptedWithCorrection","matchedAnswer":"x","correct":false,"acceptedWithCorrection":true,
         "reasons":["ZwnjOrSpacing"],"xp":7,"separatorEdits":[{"kind":"missingZwnj","index":2,"length":1}]}
        """
        let r = try JSONDecoder().decode(GraderResponse.self, from: Data(wire.utf8))
        XCTAssertEqual(r.verdict, "AcceptedWithCorrection")
        XCTAssertEqual(r.reasons, ["ZwnjOrSpacing"])
        XCTAssertEqual(r.xp, 7)
        XCTAssertEqual(r.separatorEdits, [SeparatorEditResponse(kind: "missingZwnj", index: 2, length: 1)])
        XCTAssertNil(r.error)
    }

    func testErrorResponseDecodesWithoutReasons() throws {
        let r = try JSONDecoder().decode(GraderResponse.self, from: Data(#"{"error":"unknown exerciseType"}"#.utf8))
        XCTAssertNil(r.verdict)
        XCTAssertEqual(r.error, "unknown exerciseType")
        XCTAssertEqual(r.reasons, [])
    }

    func testBundledGraderMatchesItsManifest() throws {
        let bundle = try GraderBundle.bundled(language: "fa")
        let manifestSha = try bundle.verify()
        print("QGRADER-SPIKE bundle language=\(bundle.language) version=\(bundle.version) manifestSha256=\(manifestSha)")
        XCTAssertEqual(manifestSha.count, 64)
    }

    func testFixturesLoad() throws {
        let vectors = try Fixtures.vectors()
        XCTAssertEqual(vectors.count, 29)
        XCTAssertEqual(vectors.filter { $0.expect != nil }.count, 15)
        XCTAssertFalse(try Fixtures.xpVectors().isEmpty)
    }
}
