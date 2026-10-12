import XCTest
import QModel
import QDomain
@testable import QFeatures

final class PopoverLogicTests: XCTestCase {
    private func skill(_ key: String, status: SkillStatus, category: QDomain.SkillCategory = .standard) -> PathSkill {
        PathSkill(skillKey: key, title: key, category: category, arc: nil, unitKey: "u1", status: status, completed: false, positionIndex: 0)
    }

    private let index = ThemeIndexArtifact(themes: [
        ThemeEntry(id: "Food", parentId: nil, lessons: [ThemeLessonRef(id: "a", path: "a"), ThemeLessonRef(id: "c", path: "c")]),
        ThemeEntry(id: "Fruit", parentId: "Food", lessons: [ThemeLessonRef(id: "a", path: "a")]),
        ThemeEntry(id: "Travel", parentId: nil, lessons: [ThemeLessonRef(id: "c", path: "c")]),
    ])

    func testCurrentLessonStartsAndCanTestOut() {
        let target = PositionKey(unitKey: "u1", skillKey: "z")
        let actions = lessonPopoverActions(skill("a", status: .current), nextSkipTarget: target, themeIndex: index)
        XCTAssertEqual(actions.primaryLabel, "Start lesson")
        XCTAssertTrue(actions.startsLesson)
        XCTAssertEqual(actions.skipTarget, target)
        XCTAssertTrue(actions.hasDeepDive)
    }

    func testCompletedLessonPracticesWithoutTestOut() {
        let target = PositionKey(unitKey: "u1", skillKey: "z")
        let actions = lessonPopoverActions(skill("a", status: .unlocked), nextSkipTarget: target, themeIndex: index)
        XCTAssertEqual(actions.primaryLabel, "Practice")
        XCTAssertFalse(actions.startsLesson)
        XCTAssertNil(actions.skipTarget)
    }

    func testNoDeepDiveWhenUntaggedOrNoIndex() {
        XCTAssertFalse(lessonPopoverActions(skill("q", status: .current), nextSkipTarget: nil, themeIndex: index).hasDeepDive)
        XCTAssertFalse(lessonPopoverActions(skill("a", status: .current), nextSkipTarget: nil, themeIndex: nil).hasDeepDive)
    }

    func testSelectionClamps() {
        XCTAssertEqual(clampedSelection(5, count: 2), 1)
        XCTAssertEqual(clampedSelection(-1, count: 2), 0)
        XCTAssertEqual(clampedSelection(1, count: 0), 0)
    }

    func testRemixOnlyWithSeveralRootTopics() {
        let multi = deepDiveContent(themeIndex: index, lessonKey: "c")
        XCTAssertTrue(multi.showRemix)
        XCTAssertTrue(multi.showsPickPrompt)
        let single = deepDiveContent(themeIndex: index, lessonKey: "a")
        XCTAssertFalse(single.showRemix)
        XCTAssertFalse(single.showsPickPrompt)
    }

    func testRowsIndentAndTintByDepth() {
        let content = deepDiveContent(themeIndex: index, lessonKey: "a")
        XCTAssertEqual(content.rows.map { $0.themeId }, ["Food", "Fruit"])
        XCTAssertEqual(content.rows.map { $0.step }, [0, 1])
        XCTAssertEqual(content.rows[0].title, "Dive Level 1")
        XCTAssertEqual(content.rows[0].borderAlpha, 0.35, accuracy: 0.0001)
        XCTAssertEqual(content.rows[1].tint, 0.08, accuracy: 0.0001)
        XCTAssertEqual(content.rows[1].borderAlpha, 0.48, accuracy: 0.0001)
    }

    func testEmptyIndexHasNothing() {
        let content = deepDiveContent(themeIndex: nil, lessonKey: "a")
        XCTAssertFalse(content.showRemix)
        XCTAssertTrue(content.rows.isEmpty)
    }
}
