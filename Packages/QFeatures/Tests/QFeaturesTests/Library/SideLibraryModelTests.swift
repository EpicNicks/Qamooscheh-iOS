import XCTest
import QModel
import QDomain
@testable import QFeatures

private struct LibraryError: Error {}

private final class LibraryRepo: PathRepository, @unchecked Sendable {
    var content: Result<PathContent, Error>
    var completed: Result<Set<String>, Error> = .success([])

    init(_ units: [PathUnitInput]) { content = .success(PathContent(units: units)) }

    func pathContent(course: CourseRef) async throws -> PathContent { try content.get() }
    func completedLessonKeys(courseCode: String) async throws -> Set<String> { try completed.get() }
    func prefs() async throws -> PrefsResponse { throw URLError(.notConnectedToInternet) }
    func activity(courseCode: String) async throws -> ActivityResponse { throw URLError(.notConnectedToInternet) }
}

private func std(_ key: String) -> PathSkillInput { PathSkillInput(skillKey: key, title: key, category: .standard) }
private func other(_ key: String, _ category: QDomain.SkillCategory, after: Int?) -> PathSkillInput {
    PathSkillInput(skillKey: key, title: key, category: category, afterPosition: after)
}

private let units: [PathUnitInput] = [
    PathUnitInput(
        unitKey: "u1", title: "One",
        standardPositions: [PathPositionInput(skills: [std("a")]), PathPositionInput(skills: [std("review")])],
        otherSkills: [other("l1", .listening, after: 1), other("s1", .story, after: 1), other("conv", .conversation, after: 1)]),
    PathUnitInput(
        unitKey: "u2", title: "Two",
        standardPositions: [PathPositionInput(skills: [std("c")])],
        otherSkills: [other("l2", .listening, after: 0), other("s2", .story, after: 0)]),
    PathUnitInput(unitKey: "u3", title: "Three", standardPositions: [PathPositionInput(skills: [std("d")])], otherSkills: []),
]

private let course = CourseRef(code: "fa", version: 1, manifestSha256: "x")

private func bootstrap(course: CourseRef? = course, at skill: String = "a") -> BootstrapResponse {
    BootstrapResponse(
        course: course, position: PositionRef(unitKey: "u1", skillKey: skill), graders: [],
        enrolledCourseCodes: ["fa"], onboardingComplete: true)
}

@MainActor
final class SideLibraryModelTests: XCTestCase {
    private func model(_ kind: SideLibraryKind, repo: LibraryRepo = LibraryRepo(units), boot: BootstrapResponse? = bootstrap()) -> SideLibraryModel {
        SideLibraryModel(kind: kind, repository: repo, bootstrap: { boot })
    }

    func testListeningPageListsListeningByUnitLeavingOutOtherCategoriesAndEmptyUnits() async {
        let m = model(.listening)
        await m.refresh()
        guard case .ready(let page) = m.state else { return XCTFail("\(m.state)") }
        XCTAssertEqual(page.map { $0.unitKey }, ["u1", "u2"])
        XCTAssertEqual(page.map { $0.heading }, ["Unit 1: One", "Unit 2: Two"])
        XCTAssertEqual(page[0].lessons.map { $0.skillKey }, ["l1"])
        XCTAssertEqual(page[1].lessons.map { $0.skillKey }, ["l2"])
    }

    func testStoryPageListsStoriesOnly() async {
        let m = model(.story)
        await m.refresh()
        guard case .ready(let page) = m.state else { return XCTFail("\(m.state)") }
        XCTAssertEqual(page.flatMap { $0.lessons.map { $0.skillKey } }, ["s1", "s2"])
    }

    func testUnlockedByUnitNotByTheParsleItFollows() async {
        // The cursor is on the first Parsle: l1 follows the review (still ahead), yet its unit is reached, so the page opens it.
        let m = model(.listening)
        await m.refresh()
        guard case .ready(let page) = m.state else { return XCTFail("\(m.state)") }
        XCTAssertEqual(page.map { $0.unlocked }, [true, false])
        XCTAssertEqual(page[0].lessons.map { $0.status }, [.unlocked])
        XCTAssertEqual(page[1].lessons.map { $0.status }, [.locked])
    }

    func testCompletedLessonsAreMarkedAndAFailedCompletionReadShowsNone() async {
        let repo = LibraryRepo(units)
        repo.completed = .success(["l1"])
        let m = model(.listening, repo: repo)
        await m.refresh()
        guard case .ready(let page) = m.state else { return XCTFail("\(m.state)") }
        XCTAssertEqual(page[0].lessons.map { $0.completed }, [true])

        repo.completed = .failure(LibraryError())
        let again = model(.listening, repo: repo)
        await again.refresh()
        guard case .ready(let none) = again.state else { return XCTFail("\(again.state)") }
        XCTAssertEqual(none[0].lessons.map { $0.completed }, [false])
    }

    func testNoCourseIsUnavailable() async {
        let m = model(.story, boot: bootstrap(course: nil))
        await m.refresh()
        XCTAssertEqual(m.state, .unavailable("Pick a course to see its lessons."))
        let noBootstrap = model(.story, boot: nil)
        await noBootstrap.refresh()
        XCTAssertEqual(noBootstrap.state, .unavailable("Pick a course to see its lessons."))
    }

    func testAReadFailureIsUnavailableButAShownPageStays() async {
        let repo = LibraryRepo(units)
        let m = model(.story, repo: repo)
        await m.refresh()
        repo.content = .failure(PathContentError.notDownloaded)
        await m.refresh()
        if case .ready = m.state {} else { XCTFail("a loaded page stays up: \(m.state)") }

        let fresh = model(.story, repo: repo)
        await fresh.refresh()
        XCTAssertEqual(fresh.state, .unavailable("This course isn't downloaded yet."))
    }

    func testKindsAndRowNotes() {
        XCTAssertEqual(SideLibraryKind.story.title, "Stories")
        XCTAssertEqual(SideLibraryKind.listening.title, "Listening")
        XCTAssertEqual(AppRoute.sideLibrary(.listening).title, "Listening")
        XCTAssertNotEqual(AppRoute.sideLibrary(.story), AppRoute.sideLibrary(.listening))
        let open = PathSkill(skillKey: "l", title: "l", category: .listening, arc: nil, unitKey: "u", status: .unlocked, completed: false, positionIndex: nil)
        var done = open
        done.completed = true
        XCTAssertNil(sideLibraryRowNote(open, unitUnlocked: true))
        XCTAssertEqual(sideLibraryRowNote(open, unitUnlocked: false), "Locked")
        XCTAssertEqual(sideLibraryRowNote(done, unitUnlocked: true), "Done")
    }
}
