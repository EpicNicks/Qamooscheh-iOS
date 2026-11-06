import XCTest
import QModel
import QDomain
@testable import QFeatures

private let course = CourseRef(code: "ja", version: 3, manifestSha256: "x")

private func skill(_ key: String) -> PathSkillInput {
    PathSkillInput(skillKey: key, title: key, category: .standard)
}

private let units = [
    PathUnitInput(unitKey: "u1", title: "U1", standardPositions: [
        PathPositionInput(skills: [skill("a")]),
        PathPositionInput(skills: [skill("b")]),
        PathPositionInput(skills: [skill("c")]),
    ], otherSkills: [])
]

private func bootstrap(at key: String) -> BootstrapResponse {
    BootstrapResponse(
        course: course, position: PositionRef(unitKey: "u1", skillKey: key), graders: [], enrolledCourseCodes: ["ja"],
        onboardingComplete: true)
}

private final class Repo: PathRepository, @unchecked Sendable {
    var completed: Set<String> = []
    func pathContent(course: CourseRef) async throws -> PathContent { PathContent(units: units) }
    func completedLessonKeys(courseCode: String) async throws -> Set<String> { completed }
    func prefs() async throws -> PrefsResponse { throw URLError(.notConnectedToInternet) }
    func activity(courseCode: String) async throws -> ActivityResponse { throw URLError(.notConnectedToInternet) }
}

@MainActor
final class PathModelTransitionTests: XCTestCase {
    private let expected = JourneyTransition(
        completedSkillKey: "a", edges: [JourneyEdge(from: "a", to: "b")], unlockedSkillKeys: ["b"])

    private func loaded() async -> (PathModel, Repo) {
        let repo = Repo()
        let model = PathModel(repository: repo)
        await model.refresh(bootstrap: bootstrap(at: "a"))
        return (model, repo)
    }

    func testFinishThenReloadPlaysOnce() async {
        let (model, repo) = await loaded()
        model.noteFinished(skillKey: "a")
        XCTAssertNil(model.transition)
        repo.completed = ["a"]
        await model.refresh(bootstrap: bootstrap(at: "b"))
        XCTAssertEqual(model.consumeTransition(), expected)
        XCTAssertNil(model.consumeTransition())
    }

    func testReloadThenFinishPlaysOnce() async {
        let (model, repo) = await loaded()
        repo.completed = ["a"]
        await model.refresh(bootstrap: bootstrap(at: "b"))
        XCTAssertNil(model.transition)
        model.noteFinished(skillKey: "a")
        XCTAssertEqual(model.consumeTransition(), expected)
    }

    func testRevisitDoesNotReplay() async {
        let (model, repo) = await loaded()
        model.noteFinished(skillKey: "a")
        repo.completed = ["a"]
        await model.refresh(bootstrap: bootstrap(at: "b"))
        _ = model.consumeTransition()
        await model.refresh(bootstrap: bootstrap(at: "b"))
        XCTAssertNil(model.transition)
    }

    func testStaleFinishIsDropped() async {
        var clock = Date(timeIntervalSince1970: 0)
        let repo = Repo()
        let model = PathModel(repository: repo, now: { clock })
        await model.refresh(bootstrap: bootstrap(at: "a"))
        model.noteFinished(skillKey: "a")
        clock = Date(timeIntervalSince1970: 120)
        repo.completed = ["a"]
        await model.refresh(bootstrap: bootstrap(at: "b"))
        XCTAssertNil(model.transition)
    }

    func testReplayOfEarlierLessonGivesNothing() async {
        let repo = Repo()
        repo.completed = ["a"]
        let model = PathModel(repository: repo)
        await model.refresh(bootstrap: bootstrap(at: "b"))
        model.noteFinished(skillKey: "a")
        await model.refresh(bootstrap: bootstrap(at: "b"))
        XCTAssertNil(model.transition)
    }
}
