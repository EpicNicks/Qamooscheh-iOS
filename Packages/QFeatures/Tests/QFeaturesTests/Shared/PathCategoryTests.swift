import XCTest
import QModel
import QDomain
@testable import QFeatures

final class PathCategoryTests: XCTestCase {
    func testEachKnownCategoryMapsToItsOwn() {
        let table: [(QModel.SkillCategory, QDomain.SkillCategory)] = [
            (.standard, .standard), (.story, .story), (.conversation, .conversation), (.song, .song), (.listening, .listening),
        ]
        for (model, path) in table {
            XCTAssertEqual(pathCategory(of: SkillArtifact(id: "s", title: "S", category: model)), path)
        }
    }

    func testAnUnknownCategoryStaysUnknownSoThePathDropsIt() {
        XCTAssertEqual(pathCategory(of: SkillArtifact(id: "s", title: "S", category: .unknown)), .unknown)
    }

    func testAMissingSkillFileCountsAsStandard() {
        XCTAssertEqual(pathCategory(of: nil), .standard)
    }
}
