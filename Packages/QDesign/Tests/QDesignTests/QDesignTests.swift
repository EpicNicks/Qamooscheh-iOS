import XCTest
@testable import QDesign

final class QDesignTests: XCTestCase {
    func testModuleIdentity() {
        XCTAssertEqual(QDesignInfo.name, "QDesign")
        XCTAssertEqual(QDesignInfo.dependencyNames, [])
    }
}
