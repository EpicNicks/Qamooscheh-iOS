import XCTest
import QModel
import QDomain
import QData
@testable import QFeatures

private let course = CourseRef(code: "ja", version: 3, manifestSha256: "x")

private func skill(_ key: String) -> PathSkillInput {
    PathSkillInput(skillKey: key, title: key, category: .standard)
}

private let units: [PathUnitInput] = [
    PathUnitInput(
        unitKey: "u1", title: "Unit 1",
        standardPositions: [
            PathPositionInput(skills: [skill("a")]),
            PathPositionInput(skills: [skill("b")]),
            PathPositionInput(skills: [skill("c")]),
        ],
        otherSkills: [])
]

private func bootstrap(stowable: [String] = [], update: CourseUpdateRef? = nil) -> BootstrapResponse {
    BootstrapResponse(
        course: course, position: PositionRef(unitKey: "u1", skillKey: "b"), graders: [], enrolledCourseCodes: ["ja"],
        onboardingComplete: true, update: update, stowage: [], stowableLessonKeys: stowable)
}

private struct StubRepo: PathRepository {
    func pathContent(course: CourseRef) async throws -> PathContent { PathContent(units: units) }
    func completedLessonKeys(courseCode: String) async throws -> Set<String> { ["a"] }
    func prefs() async throws -> PrefsResponse { throw URLError(.notConnectedToInternet) }
    func activity(courseCode: String) async throws -> ActivityResponse { throw URLError(.notConnectedToInternet) }
}

private struct StubStow: StowService {
    func stow(lessonKey: String) async throws -> StowResponse { throw URLError(.notConnectedToInternet) }
    func snoozeStowage() async throws -> StowageResponse { throw URLError(.notConnectedToInternet) }
    func muteStowage() async throws -> StowageResponse { throw URLError(.notConnectedToInternet) }
}

private final class Calls: @unchecked Sendable {
    var downloads = 0
    var previews: [String] = []
}

private func services(downloaded: Bool = true, downloadFails: Bool = false, calls: Calls = Calls()) -> PathServices {
    PathServices(
        repository: StubRepo(),
        themeIndex: { _ in nil },
        isDownloaded: { _ in downloaded },
        download: { _, _ in
            calls.downloads += 1
            if downloadFails { throw URLError(.notConnectedToInternet) }
        },
        stow: StubStow(),
        flushQueue: { _ in },
        rollForwardPreview: { code, version in
            calls.previews.append("\(code)/\(version)")
            return RollForwardPreviewResponse(
                courseCode: code, fromVersion: 3, toVersion: version, manifestSha256: "m", clamped: false, unitClamped: false, lessonClamped: false)
        },
        applyUpdate: { _, _, _ in bootstrap() })
}

@MainActor
final class PathHostTests: XCTestCase {
    private func makeHost(_ services: PathServices) -> PathHostModel {
        PathHostModel(shell: SignedInShell(app: nil), services: services, reminderPrefs: UserDefaultsStowReminderPrefs(defaults: UserDefaults(suiteName: "PathHostTests") ?? .standard))
    }

    private func stowOffered(_ host: PathHostModel) -> [String] {
        let state = host.path.state
        let keys = Set(state.stowableLessonKeys)
        var offered: [String] = []
        for unit in state.units {
            for position in unit.standardPositions {
                for skill in position.skills {
                    let actions = lessonPopoverActions(skill, nextSkipTarget: state.nextSkipTarget, themeIndex: nil, stowableLessonKeys: keys)
                    if actions.stowOffered { offered.append(skill.skillKey) }
                }
            }
        }
        return offered
    }

    func testStowActionAppearsOnTheStowableLessonOnly() async {
        let host = makeHost(services())
        await host.bootstrapChanged(bootstrap(stowable: ["b"]))
        XCTAssertEqual(stowOffered(host), ["b"])
    }

    func testNoStowActionWithoutStowableKeys() async {
        let host = makeHost(services())
        await host.bootstrapChanged(bootstrap())
        XCTAssertEqual(stowOffered(host), [])
    }

    func testBootstrapLoadsTheRoad() async {
        let host = makeHost(services())
        await host.bootstrapChanged(bootstrap())
        XCTAssertEqual(host.path.state.status, .ready)
        XCTAssertEqual(host.path.state.units.count, 1)
        XCTAssertNil(host.download)
    }

    func testAnUpdateOfferShowsOnTheBanner() async {
        let host = makeHost(services())
        await host.bootstrapChanged(bootstrap(update: CourseUpdateRef(version: 4, manifestSha256: "n", eligible: true)))
        XCTAssertEqual(host.banner.offer?.version, 4)
        XCTAssertTrue(host.banner.isVisible)
        await host.bootstrapChanged(bootstrap())
        XCTAssertNil(host.banner.offer)
    }

    func testMissingCourseStartsADownloadAndAFailureShowsTryAgain() async throws {
        let calls = Calls()
        let host = makeHost(services(downloaded: false, downloadFails: true, calls: calls))
        await host.bootstrapChanged(bootstrap())
        for _ in 0..<200 where host.download != .failed { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertEqual(host.download, .failed)
        XCTAssertEqual(calls.downloads, 1)
    }

    func testOpenRollForwardNeedsAnActiveCourse() async {
        let calls = Calls()
        let host = makeHost(services(calls: calls))
        await host.openRollForward()
        XCTAssertEqual(calls.previews, [])
        XCTAssertNil(host.banner.dialog)
    }

    func testStowClearedDropsTheLessonFromTheStowage() async {
        let host = makeHost(services())
        var next = bootstrap()
        next.stowage = [StowageUnit(unitKey: "u1", lessons: [StowedLesson(lessonKey: "a", stowedAt: Date(timeIntervalSince1970: 0), lessonsCompletedSince: 0, readyPromptDue: false, muted: false)])]
        await host.bootstrapChanged(next)
        XCTAssertEqual(host.path.state.stowedLessonKeys, ["a"])
        await host.stowCleared("a")
        XCTAssertEqual(host.path.state.stowedLessonKeys, [])
    }
}
