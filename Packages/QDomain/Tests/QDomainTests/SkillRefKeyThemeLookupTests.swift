import XCTest
import QModel
@testable import QDomain

final class SkillRefKeyThemeLookupTests: XCTestCase {
    func testRefKeyJoinsUnitAndSkill() {
        XCTAssertEqual(refKey(SkillRef(unitKey: "01-greetings", skillKey: "02-how")), "01-greetings/02-how")
    }

    func testRefKeyUsesUnderscoreForThemeLessonNilUnit() {
        XCTAssertEqual(refKey(SkillRef(unitKey: nil, skillKey: "food")), "_/food")
    }

    private let index = ThemeIndexArtifact(themes: [
        ThemeEntry(id: "food", lessons: [ThemeLessonRef(id: "l1", path: "a"), ThemeLessonRef(id: "l2", path: "b")]),
        ThemeEntry(id: "travel", parentId: nil, lessons: [ThemeLessonRef(id: "l2", path: "b")]),
        ThemeEntry(id: "home", lessons: [ThemeLessonRef(id: "l3", path: "c")]),
    ])

    func testThemesForLessonReturnsEveryBucketListingIt() {
        XCTAssertEqual(themesForLesson(index, lessonKey: "l2").map { $0.id }, ["food", "travel"])
        XCTAssertEqual(themesForLesson(index, lessonKey: "l3").map { $0.id }, ["home"])
    }

    func testThemesForLessonEmptyForUnknownLessonOrMissingIndex() {
        XCTAssertEqual(themesForLesson(index, lessonKey: "zzz"), [])
        XCTAssertEqual(themesForLesson(nil, lessonKey: "l1"), [])
    }
}
