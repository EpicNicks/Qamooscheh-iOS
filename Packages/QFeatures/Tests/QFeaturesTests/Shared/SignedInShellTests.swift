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

    func testApplyBootstrapSetsCourseAndName() {
        let shell = SignedInShell(app: nil)
        let course = CourseRef(code: "fa", version: 1, manifestSha256: "x")
        shell.apply(BootstrapResponse(course: course, graders: [], enrolledCourseCodes: ["fa"], onboardingComplete: true))
        XCTAssertEqual(shell.course, course)
        XCTAssertEqual(shell.courseName, "FA")
    }
}
