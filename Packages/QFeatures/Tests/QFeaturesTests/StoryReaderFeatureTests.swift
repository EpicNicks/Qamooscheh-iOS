import XCTest
import QModel
import QDomain
@testable import QFeatures

@MainActor
private final class FakeStars: StoryStarring {
    var starredTags: [String] = ["tea"]
    var toggled: [String] = []
    func toggleStar(_ tag: String) async { toggled.append(tag) }
}

final class StoryReaderFeatureTests: XCTestCase {
    func testAutoscrollDefaultsOnAndPersists() throws {
        let suite = "storyprefs-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let prefs = StoryReaderPrefs(defaults: defaults)
        XCTAssertTrue(prefs.autoscroll(userId: "u1"))
        prefs.setAutoscroll(false, userId: "u1")
        XCTAssertFalse(prefs.autoscroll(userId: "u1"))
        XCTAssertTrue(prefs.autoscroll(userId: "u2"))
    }

    @MainActor
    func testWordTapGivesHintAndTogglesStarOnly() async {
        let stars = FakeStars()
        let lexemes = ["tea": LexemeIndexEntry(gloss: "a drink", romanizationIsAuthored: false)]
        let tap = StoryWordTap.make(tag: "tea", lexemes: lexemes, starred: stars)
        XCTAssertEqual(tap.hint, "a drink")
        XCTAssertTrue(tap.isSaved)
        XCTAssertEqual(tap.highlight, .saved)
        await tap.toggleSaved(on: stars)
        XCTAssertEqual(stars.toggled, ["tea"])
    }
}
