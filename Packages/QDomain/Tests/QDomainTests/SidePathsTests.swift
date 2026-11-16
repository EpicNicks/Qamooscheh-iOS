import XCTest
@testable import QDomain

final class SidePathsTests: XCTestCase {
    private func std(_ key: String) -> PathSkillInput { PathSkillInput(skillKey: key, title: key, category: .standard) }
    private func listening(_ key: String, after: Int?) -> PathSkillInput {
        PathSkillInput(skillKey: key, title: key, category: .listening, afterPosition: after)
    }

    private func path(position: PositionKey?) -> [PathUnit] {
        computePathProgress([
            PathUnitInput(
                unitKey: "u1", title: "One",
                standardPositions: [PathPositionInput(skills: [std("a")]), PathPositionInput(skills: [std("b")]), PathPositionInput(skills: [std("review")])],
                otherSkills: [listening("l1", after: 2), listening("l0", after: nil),
                              PathSkillInput(skillKey: "st", title: "st", category: .story, afterPosition: 2)]),
            PathUnitInput(
                unitKey: "u2", title: "Two",
                standardPositions: [PathPositionInput(skills: [std("c")])],
                otherSkills: [listening("l2", after: 0)]),
        ], position: position)
    }

    func testOnlyStoriesAndListeningBranchOffAndOnlyListeningUsesThePlayer() {
        XCTAssertTrue(SkillCategory.story.branchesOffRoad)
        XCTAssertTrue(SkillCategory.listening.branchesOffRoad)
        for c in [SkillCategory.standard, .conversation, .song, .unknown] { XCTAssertFalse(c.branchesOffRoad, "\(c)") }
        XCTAssertTrue(SkillCategory.listening.opensInLessonPlayer)
        XCTAssertFalse(SkillCategory.story.opensInLessonPlayer)
        XCTAssertFalse(SkillCategory.unknown.isKnown)
        XCTAssertTrue(SkillCategory.listening.isKnown)
    }

    func testSideIsStableAndBothSidesOccur() {
        XCTAssertEqual(sidePathSide(unitKey: "u1", skillKey: "l1"), sidePathSide(unitKey: "u1", skillKey: "l1"))
        let sides = Set((0..<40).map { sidePathSide(unitKey: "u1", skillKey: "lesson-\($0)") })
        XCTAssertEqual(sides, [.left, .right])
    }

    /// Values computed with web's `storySide` (src/domain/roadRows.ts) so the sides agree across surfaces.
    func testSideMatchesWebsHash() {
        let expected: [(String, String, SidePathSide)] = [
            ("u1", "l1", .right), ("u1", "l0", .left), ("u1", "st", .left), ("u2", "l2", .right),
            ("unit-1", "story-1", .right), ("unit-1", "listening-1", .left),
            ("cafe", "cafe-1", .right), ("cafe", "cafe-2", .left), ("cafe", "cafe-3", .right),
        ]
        for (unit, skill, side) in expected {
            XCTAssertEqual(sidePathSide(unitKey: unit, skillKey: skill), side, "\(unit)/\(skill)")
        }
    }

    func testASideLessonOpensOnceItIsDoneOrItsParsleIsDone() {
        // The cursor clamps on the course's last lesson: the review stays current even once it is passed.
        var p = path(position: PositionKey(unitKey: "u1", skillKey: "review"))
        var l1 = p[0].otherSkills.first { $0.skillKey == "l1" }!
        XCTAssertTrue(sidePathLocked(l1, in: p[0]))
        l1.completed = true
        XCTAssertFalse(sidePathLocked(l1, in: p[0]))
        l1.completed = false
        p[0].standardPositions[2].skills[0].completed = true
        XCTAssertFalse(sidePathLocked(l1, in: p[0]))
    }

    func testStoryLibraryListsOnlyStories() {
        let p = path(position: PositionKey(unitKey: "u1", skillKey: "a"))
        let library = storyLibrary(p)
        XCTAssertEqual(library.map { $0.unitKey }, ["u1"])
        XCTAssertEqual(library[0].lessons.map { $0.skillKey }, ["st"])
        XCTAssertTrue(library[0].unlocked)
    }

    func testLockedUntilTheParsleItFollowsIsPassed() {
        // Cursor on position 2 (the review): l1 follows it, so it is still locked.
        let atReview = path(position: PositionKey(unitKey: "u1", skillKey: "review"))
        let l1 = atReview[0].otherSkills.first { $0.skillKey == "l1" }!
        XCTAssertTrue(sidePathLocked(l1, in: atReview[0]))
        // Cursor on the next unit: the review is behind it, so l1 opens.
        let past = path(position: PositionKey(unitKey: "u2", skillKey: "c"))
        XCTAssertFalse(sidePathLocked(past[0].otherSkills.first { $0.skillKey == "l1" }!, in: past[0]))
    }

    func testAnAnchorlessOneOpensWithItsUnitAndALaterUnitStaysLocked() {
        let atReview = path(position: PositionKey(unitKey: "u1", skillKey: "review"))
        XCTAssertFalse(sidePathLocked(atReview[0].otherSkills.first { $0.skillKey == "l0" }!, in: atReview[0]))
        XCTAssertTrue(sidePathLocked(atReview[1].otherSkills[0], in: atReview[1]))
    }

    func testListeningNeverMovesTheCursorOrJoinsTheStandardPositions() {
        let p = path(position: PositionKey(unitKey: "u1", skillKey: "a"))
        XCTAssertEqual(p[0].standardPositions.count, 3)
        XCTAssertEqual(p[0].standardPositions.map { $0.status }, [.current, .locked, .locked])
        XCTAssertTrue(p[0].otherSkills.allSatisfy { $0.positionIndex == nil })
    }

    func testLibraryListsListeningByUnitInCourseOrderUnlockedByUnit() {
        let p = path(position: PositionKey(unitKey: "u1", skillKey: "a"))
        let library = listeningLibrary(p)
        XCTAssertEqual(library.map { $0.unitKey }, ["u1", "u2"])
        XCTAssertEqual(library[0].lessons.map { $0.skillKey }, ["l1", "l0"])
        XCTAssertEqual(library[0].heading, "Unit 1: One")
        // The story is not a listening lesson.
        XCTAssertFalse(library[0].lessons.contains { $0.skillKey == "st" })
        // Unlocked by the unit being reached, regardless of the Parsle it follows on the road.
        XCTAssertEqual(library.map { $0.unlocked }, [true, false])
    }

    func testAUnitWithoutAListeningLessonIsLeftOut() {
        let p = computePathProgress([PathUnitInput(unitKey: "u", title: "U", standardPositions: [], otherSkills: [])], position: nil)
        XCTAssertTrue(listeningLibrary(p).isEmpty)
    }
}
