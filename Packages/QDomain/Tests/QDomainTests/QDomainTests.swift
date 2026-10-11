import XCTest
@testable import QDomain

final class QDomainTests: XCTestCase {
    func testModuleIdentity() {
        XCTAssertEqual(QDomainInfo.name, "QDomain")
        XCTAssertEqual(QDomainInfo.dependencyNames, ["QModel"])
    }
}
