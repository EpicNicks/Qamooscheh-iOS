import XCTest
@testable import QNetwork

final class QNetworkTests: XCTestCase {
    func testModuleIdentity() {
        XCTAssertEqual(QNetworkInfo.name, "QNetwork")
        XCTAssertEqual(QNetworkInfo.dependencyNames, ["QModel"])
    }
}
