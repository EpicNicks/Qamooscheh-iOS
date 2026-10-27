import XCTest
import QModel
import QDomain
@testable import QFeatures

private func skill(_ key: String, unit: String = "u1", category: QDomain.SkillCategory = .standard, stowed: Bool = false) -> PathSkill {
    PathSkill(
        skillKey: key, title: key, category: category, arc: nil, unitKey: unit,
        status: .current, completed: false, positionIndex: 0, stowed: stowed)
}

/// What a destination opens, with the lesson route's random id left out.
private enum Opened: Equatable {
    case lesson(unitKey: String?, skillKey: String, practice: Bool, checkpoint: Bool, deepDive: String?)
    case push(AppRoute)

    init(_ destination: PathDestination) {
        switch destination {
        case .lesson(let route):
            self = .lesson(
                unitKey: route.unitKey, skillKey: route.skillKey, practice: route.practice,
                checkpoint: route.checkpoint, deepDive: route.deepDiveLessonKey)
        case .push(let route):
            self = .push(route)
        }
    }
}

final class AppPathNavigatorTests: XCTestCase {
    func testStartMapsEveryCategoryToTheLessonRouteByName() {
        let categories: [QDomain.SkillCategory] = [.standard, .story, .conversation, .song]
        for category in categories {
            XCTAssertEqual(
                Opened(AppPathNavigator.start(skill("s1", unit: "u2", category: category))),
                .lesson(unitKey: "u2", skillKey: "s1", practice: false, checkpoint: false, deepDive: nil),
                "\(category)")
        }
    }

    func testPracticeIsALocalPracticeRoute() {
        XCTAssertEqual(
            Opened(AppPathNavigator.practice(skill("s1"))),
            .lesson(unitKey: "u1", skillKey: "s1", practice: true, checkpoint: false, deepDive: nil))
    }

    func testRetryStowedIsTheOrdinaryRouteSoAPassClearsTheStow() {
        XCTAssertEqual(
            Opened(AppPathNavigator.retryStowed(skill("s1", stowed: true))),
            .lesson(unitKey: "u1", skillKey: "s1", practice: false, checkpoint: false, deepDive: nil))
    }

    func testCheckpointNamesTheTargetPosition() {
        XCTAssertEqual(
            Opened(AppPathNavigator.checkpoint(PositionKey(unitKey: "u3", skillKey: "t1"))),
            .lesson(unitKey: "u3", skillKey: "t1", practice: false, checkpoint: true, deepDive: nil))
    }

    func testVocabularyOpensTheSkillOrTheUnit() {
        XCTAssertEqual(Opened(AppPathNavigator.vocabulary(skill("s1"))), .push(.skillVocabulary(unitKey: "u1", skillKey: "s1")))
        XCTAssertEqual(Opened(AppPathNavigator.unitVocabulary(unitKey: "u9")), .push(.skillVocabulary(unitKey: "u9", skillKey: nil)))
    }

    func testDeepDiveRemixAndTheme() {
        XCTAssertEqual(
            Opened(AppPathNavigator.deepDive(lessonKey: "s1")),
            .lesson(unitKey: nil, skillKey: "remix-s1", practice: false, checkpoint: false, deepDive: "s1"))
        XCTAssertEqual(Opened(AppPathNavigator.theme(themeId: "food")), .push(.topic("food")))
    }

    func testNavigatorHandsEachCallToTheRightOpener() {
        var lessons: [LessonRoute] = []
        var pushes: [AppRoute] = []
        let navigator = AppPathNavigator(startLesson: { lessons.append($0) }, push: { pushes.append($0) })
        let s = skill("s1")
        navigator.startLesson(s)
        navigator.practice(s)
        navigator.retryStowed(s)
        navigator.checkpoint(PositionKey(unitKey: "u2", skillKey: "t"))
        navigator.deepDiveRemix(lessonKey: "s1")
        navigator.reviewVocabulary(s)
        navigator.reviewUnitVocabulary(unitKey: "u1")
        navigator.openTheme(themeId: "food", fromLessonKey: "s1")
        XCTAssertEqual(lessons.count, 5)
        XCTAssertEqual(pushes, [.skillVocabulary(unitKey: "u1", skillKey: "s1"), .skillVocabulary(unitKey: "u1", skillKey: nil), .topic("food")])
    }

    func testPrimaryButtonRoutesByState() {
        var opened: [PathDestination] = []
        let navigator = AppPathNavigator(open: { opened.append($0) })
        var stowed = skill("s1", stowed: true)
        stowed.status = .unlocked
        var passed = skill("s2")
        passed.status = .unlocked
        navigator.performPrimary(stowed)
        navigator.performPrimary(skill("s3"))
        navigator.performPrimary(passed)
        XCTAssertEqual(
            opened.map { Opened($0) },
            [
                .lesson(unitKey: "u1", skillKey: "s1", practice: false, checkpoint: false, deepDive: nil),
                .lesson(unitKey: "u1", skillKey: "s3", practice: false, checkpoint: false, deepDive: nil),
                .lesson(unitKey: "u1", skillKey: "s2", practice: true, checkpoint: false, deepDive: nil),
            ])
    }

    func testSkillVocabularyRouteTitle() {
        XCTAssertEqual(AppRoute.skillVocabulary(unitKey: "u1", skillKey: nil).title, "Vocabulary")
        XCTAssertNotEqual(AppRoute.skillVocabulary(unitKey: "u1", skillKey: nil), AppRoute.skillVocabulary(unitKey: "u1", skillKey: "a"))
    }

    func testLessonSubmitRefreshCarriesTheClearedStow() {
        let note = Notification(name: LessonSubmitRefresh.notification, object: nil, userInfo: ["stowCleared": "b1"])
        XCTAssertEqual(LessonSubmitRefresh.stowCleared(in: note), "b1")
        XCTAssertNil(LessonSubmitRefresh.stowCleared(in: Notification(name: LessonSubmitRefresh.notification)))
    }
}
