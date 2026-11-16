import XCTest
@testable import QModel

final class SkillCategoryDecodeTests: XCTestCase {
    private func skill(category: String) -> Data {
        Data("{\"id\":\"s\",\"title\":\"t\",\"category\":\"\(category)\",\"exercises\":[]}".utf8)
    }

    func testListeningIsAKnownCategory() throws {
        XCTAssertEqual(SkillCategory.listening.rawValue, "listening")
        let decoded = try JSONDecoder().decode(SkillArtifact.self, from: skill(category: "listening"))
        XCTAssertEqual(decoded.category, .listening)
    }

    func testAnUnrecognisedCategoryDecodesToUnknownRatherThanFailingOrBecomingStandard() throws {
        let decoded = try JSONDecoder().decode(SkillArtifact.self, from: skill(category: "podcast"))
        XCTAssertEqual(decoded.category, .unknown)
    }

    func testAMissingCategoryIsStillStandard() throws {
        let data = Data("{\"id\":\"s\",\"title\":\"t\"}".utf8)
        XCTAssertEqual(try JSONDecoder().decode(SkillArtifact.self, from: data).category, .standard)
    }
}
