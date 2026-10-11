import XCTest
@testable import Qamooscheh

final class ShellTests: XCTestCase {
    func testFiveTabsInOrder() {
        XCTAssertEqual(AppTab.allCases.map { $0.title }, ["Learn", "Library", "Review", "Leagues", "Profile"])
    }
}
