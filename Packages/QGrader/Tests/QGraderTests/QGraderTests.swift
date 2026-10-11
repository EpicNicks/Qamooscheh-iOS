import XCTest
@testable import QGrader

final class QGraderTests: XCTestCase {
    func testModuleIdentity() {
        XCTAssertEqual(QGraderInfo.name, "QGrader")
        XCTAssertEqual(QGraderInfo.dependencyNames, ["QModel"])
    }
}
