import XCTest
import QFeatures
@testable import Qamooscheh

final class ShellTests: XCTestCase {
    func testFiveTabsInOrder() {
        XCTAssertEqual(AppTab.allCases.map { $0.title }, ["Learn", "Library", "Review", "Leagues", "Profile"])
    }

    func testEachTabOffersItsRoutes() {
        XCTAssertEqual(AppRoute.libraryEntries.map { $0.title }, ["Themes", "Glossary"])
        XCTAssertEqual(AppRoute.reviewEntries.map { $0.title }, ["Flashcards", "Vocabulary", "Practice saved words"])
        XCTAssertEqual(
            AppRoute.profileLinks.map { $0.title },
            ["Settings", "Friends", "Help & FAQ", "About", "Share your streak"])
    }
}
