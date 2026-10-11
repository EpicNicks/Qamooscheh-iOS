import XCTest
@testable import QKeyboard

final class QKeyboardTests: XCTestCase {
    func testModuleIdentity() {
        XCTAssertEqual(QKeyboardInfo.name, "QKeyboard")
        XCTAssertEqual(QKeyboardInfo.dependencyNames, [])
    }
}
