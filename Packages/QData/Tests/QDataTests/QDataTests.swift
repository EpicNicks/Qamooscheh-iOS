import XCTest
@testable import QData

final class QDataTests: XCTestCase {
    func testModuleIdentity() {
        XCTAssertEqual(QDataInfo.name, "QData")
        XCTAssertEqual(QDataInfo.dependencyNames, ["QModel", "QNetwork"])
    }
}
