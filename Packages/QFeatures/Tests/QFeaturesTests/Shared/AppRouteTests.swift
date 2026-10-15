import XCTest
@testable import QFeatures

final class AppRouteTests: XCTestCase {
    func testTitles() {
        XCTAssertEqual(AppRoute.themes.title, "Themes")
        XCTAssertEqual(AppRoute.topic("t1").title, "Topic")
        XCTAssertEqual(AppRoute.glossary.title, "Glossary")
        XCTAssertEqual(AppRoute.flashcards.title, "Flashcards")
        XCTAssertEqual(AppRoute.vocabulary.title, "Vocabulary")
        XCTAssertEqual(AppRoute.settings.title, "Settings")
        XCTAssertEqual(AppRoute.friends.title, "Friends")
        XCTAssertEqual(AppRoute.help.title, "Help & FAQ")
        XCTAssertEqual(AppRoute.about.title, "About")
        XCTAssertEqual(AppRoute.shareStreak.title, "Share your streak")
    }

    func testTabEntries() {
        XCTAssertEqual(AppRoute.libraryEntries, [.themes, .glossary])
        XCTAssertEqual(AppRoute.reviewEntries, [.flashcards, .vocabulary])
        XCTAssertEqual(AppRoute.profileLinks, [.settings, .friends, .help, .about, .shareStreak])
    }

    func testTopicRoutesDifferById() {
        XCTAssertNotEqual(AppRoute.topic("a"), AppRoute.topic("b"))
        XCTAssertEqual(AppRoute.topic("a"), AppRoute.topic("a"))
    }
}
