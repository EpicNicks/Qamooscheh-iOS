import XCTest
@testable import QModel

final class QModelTests: XCTestCase {
    func testModuleIdentity() {
        XCTAssertEqual(QModelInfo.name, "QModel")
        XCTAssertEqual(QModelInfo.dependencyNames, [])
    }
}
