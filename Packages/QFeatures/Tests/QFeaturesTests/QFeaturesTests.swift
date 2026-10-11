import XCTest
@testable import QFeatures

final class QFeaturesTests: XCTestCase {
    func testModuleIdentity() {
        XCTAssertEqual(QFeaturesInfo.name, "QFeatures")
        XCTAssertEqual(QFeaturesInfo.dependencyNames, ["QModel", "QDomain", "QNetwork", "QData", "QGrader", "QDesign", "QKeyboard"])
    }
}
