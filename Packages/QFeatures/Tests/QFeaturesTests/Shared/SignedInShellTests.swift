import XCTest
import QModel
@testable import QFeatures

@MainActor
final class SignedInShellTests: XCTestCase {
    func testEmptyShellHasNoCourseOrXp() async {
        let shell = SignedInShell(app: nil)
        await shell.refresh()
        XCTAssertEqual(shell.courseName, "Pick a course")
        XCTAssertNil(shell.totalXp)
        XCTAssertNil(shell.goal)
        XCTAssertEqual(shell.streakDays, 0)
        XCTAssertNil(shell.makeSwitcherModel())
        let settings = await shell.makeSettingsModel()
        XCTAssertNil(settings)
        shell.stopVoicePreview()
    }

    func testMakeGoalFallsBackOnlyToTheGivenFallback() {
        let shell = SignedInShell(app: nil)
        let days = [ActivityDay(localDay: "2026-01-01", reviews: 1, xp: 10)]
        let old = DailyGoalProgress(xp: 5, goal: 50)
        XCTAssertEqual(shell.makeGoal(days: days, goalXp: nil, fallback: old), old)
        XCTAssertNil(shell.makeGoal(days: days, goalXp: nil, fallback: nil))
        XCTAssertNil(shell.makeGoal(days: days, goalXp: 0, fallback: nil))
    }

    func testApplyBootstrapSetsCourseAndName() {
        let shell = SignedInShell(app: nil)
        let course = CourseRef(code: "fa", version: 1, manifestSha256: "x")
        shell.apply(BootstrapResponse(course: course, graders: [], enrolledCourseCodes: ["fa"], onboardingComplete: true))
        XCTAssertEqual(shell.course, course)
        XCTAssertEqual(shell.courseName, "FA")
    }
}
