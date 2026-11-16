import XCTest
import QDomain
@testable import QFeatures

private func skill(_ key: String, category: QDomain.SkillCategory = .standard) -> PathSkill {
    PathSkill(
        skillKey: key, title: key, category: category, arc: nil, unitKey: "u1",
        status: .current, completed: false, positionIndex: 0, stowed: false)
}

final class LessonOriginTests: XCTestCase {
    func testARouteWithNoOriginReturnsToThePath() {
        XCTAssertEqual(LessonRoute(skillKey: "s1").origin, .path)
        XCTAssertEqual(LessonRoute(skillKey: "s1").origin.backLabel, "Back to path")
        XCTAssertEqual(LessonRoute.forCheckpoint(unitKey: "u1", skillKey: "t").origin, .path)
        XCTAssertEqual(LessonRoute.forDeepDive(lessonKey: "s1").origin, .path)
    }

    func testBackLabelsNameTheOrigin() {
        XCTAssertEqual(LessonOrigin.path.backLabel, "Back to path")
        XCTAssertEqual(LessonOrigin.sideLibrary(.story).backLabel, "Back to Stories")
        XCTAssertEqual(LessonOrigin.sideLibrary(.listening).backLabel, "Back to Listening")
        XCTAssertEqual(LessonOrigin.themes.backLabel, "Back to themes")
        XCTAssertEqual(LessonOrigin.topic.backLabel, "Back to topic")
    }

    func testFromTagsARouteAndKeepsItsOtherFields() {
        let tagged = LessonRoute(unitKey: "u1", skillKey: "s1", practice: true).from(.sideLibrary(.listening))
        XCTAssertEqual(tagged.origin, .sideLibrary(.listening))
        XCTAssertEqual(tagged.skillKey, "s1")
        XCTAssertTrue(tagged.practice)
    }

    func testChoosingRemixContentsKeepsTheOrigin() {
        let route = LessonRoute.forRemix(themeIds: ["food"]).from(.themes)
        XCTAssertEqual(route.choosing(.cloze, hardcore: true).origin, .themes)
    }

    func testALibraryNavigatorTagsEveryLessonItOpens() {
        var lessons: [LessonRoute] = []
        var pushes: [AppRoute] = []
        let navigator = AppPathNavigator(
            origin: .sideLibrary(.listening), startLesson: { lessons.append($0) }, push: { pushes.append($0) })
        let s = skill("l1")
        navigator.startLesson(s)
        navigator.practice(s)
        navigator.retryStowed(s)
        navigator.checkpoint(PositionKey(unitKey: "u1", skillKey: "t"))
        navigator.deepDiveRemix(lessonKey: "l1")
        XCTAssertEqual(lessons.count, 5)
        XCTAssertTrue(lessons.allSatisfy { $0.origin == .sideLibrary(.listening) })
        XCTAssertTrue(pushes.isEmpty)
    }

    func testTheDefaultNavigatorTagsThePath() {
        var lessons: [LessonRoute] = []
        let navigator = AppPathNavigator(startLesson: { lessons.append($0) }, push: { _ in })
        navigator.startLesson(skill("s1"))
        XCTAssertEqual(lessons.map(\.origin), [.path])
    }

    func testAStoryOpenedFromTheStoriesPageCarriesTheOriginToItsReader() {
        var pushes: [AppRoute] = []
        let navigator = AppPathNavigator(origin: .sideLibrary(.story), startLesson: { _ in }, push: { pushes.append($0) })
        navigator.startLesson(skill("st1", category: .story))
        navigator.practice(skill("st1", category: .story))
        XCTAssertEqual(pushes, [
            .storyReader(unitKey: "u1", skillKey: "st1", practice: false, origin: .sideLibrary(.story)),
            .storyReader(unitKey: "u1", skillKey: "st1", practice: true, origin: .sideLibrary(.story)),
        ])
    }

    func testAStoryReaderFromTheRoadStillDefaultsToThePath() {
        XCTAssertEqual(
            AppPathNavigator.start(skill("st1", category: .story)),
            .push(.storyReader(unitKey: "u1", skillKey: "st1", practice: false)))
        XCTAssertNotEqual(
            AppRoute.storyReader(unitKey: "u1", skillKey: "st1", origin: .sideLibrary(.story)),
            AppRoute.storyReader(unitKey: "u1", skillKey: "st1"))
    }

    func testALessonPopsTheReaderBackToItsLibraryPage() {
        let origin = LessonOrigin.sideLibrary(.story)
        let reader = AppRoute.storyReader(unitKey: "u1", skillKey: "st1", origin: origin)
        XCTAssertEqual(origin.stackForLesson([.sideLibrary(.story), reader]), [.sideLibrary(.story)])
    }

    func testALessonFromTheLibraryPageItselfLeavesTheStackAlone() {
        let stack: [AppRoute] = [.themes, .sideLibrary(.listening)]
        XCTAssertEqual(LessonOrigin.sideLibrary(.listening).stackForLesson(stack), stack)
    }

    func testTheLibraryPageIsReusedNotDuplicated() {
        let stack: [AppRoute] = [.sideLibrary(.story), .sideLibrary(.listening), .glossary]
        XCTAssertEqual(
            LessonOrigin.sideLibrary(.story).stackForLesson(stack).filter { $0 == .sideLibrary(.story) }.count, 1)
        XCTAssertEqual(LessonOrigin.sideLibrary(.story).stackForLesson(stack), [.sideLibrary(.story)])
    }

    func testAMissingLibraryPageIsPushed() {
        XCTAssertEqual(LessonOrigin.sideLibrary(.story).stackForLesson([]), [.sideLibrary(.story)])
    }

    func testOtherOriginsLeaveTheStackAlone() {
        let stack: [AppRoute] = [.themes, .topic("food")]
        for origin in [LessonOrigin.path, .themes, .topic] {
            XCTAssertEqual(origin.stackForLesson(stack), stack)
        }
    }
}
