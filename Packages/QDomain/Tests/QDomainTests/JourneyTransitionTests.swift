import XCTest
@testable import QDomain

final class JourneyTransitionTests: XCTestCase {
    private func std(_ key: String) -> PathSkillInput {
        PathSkillInput(skillKey: key, title: key, category: .standard)
    }

    /// u1: a1, fork b1/b2, c1. u2: d1.
    private let course = [
        PathUnitInput(unitKey: "u1", title: "U1", standardPositions: [
            PathPositionInput(skills: [PathSkillInput(skillKey: "a1", title: "a1", category: .standard)]),
            PathPositionInput(skills: [PathSkillInput(skillKey: "b1", title: "b1", category: .standard), PathSkillInput(skillKey: "b2", title: "b2", category: .standard)]),
            PathPositionInput(skills: [PathSkillInput(skillKey: "c1", title: "c1", category: .standard)]),
        ], otherSkills: []),
        PathUnitInput(unitKey: "u2", title: "U2", standardPositions: [
            PathPositionInput(skills: [PathSkillInput(skillKey: "d1", title: "d1", category: .standard)]),
        ], otherSkills: []),
    ]

    private func path(at skill: String, unit: String, done: Set<String>) -> [PathUnit] {
        computePathProgress(course, position: PositionKey(unitKey: unit, skillKey: skill), completedSkillKeys: done)
    }

    func testPlainCompletionDrawsEdgeThenUnlocksFork() {
        let before = path(at: "a1", unit: "u1", done: [])
        let after = path(at: "b1", unit: "u1", done: ["a1"])
        XCTAssertEqual(
            diffPathProgress(before: before, after: after, completedSkillKey: "a1"),
            JourneyTransition(
                completedSkillKey: "a1",
                edges: [JourneyEdge(from: "a1", to: "b1"), JourneyEdge(from: "a1", to: "b2")],
                unlockedSkillKeys: ["b1", "b2"]))
    }

    func testForkBranchDrawsToNextPosition() {
        let before = path(at: "b1", unit: "u1", done: ["a1"])
        let after = path(at: "c1", unit: "u1", done: ["a1", "b1"])
        XCTAssertEqual(
            diffPathProgress(before: before, after: after, completedSkillKey: "b1"),
            JourneyTransition(completedSkillKey: "b1", edges: [JourneyEdge(from: "b1", to: "c1")], unlockedSkillKeys: ["c1"]))
    }

    func testUnitBoundaryHasNoEdgesButUnlocksNextUnit() {
        let before = path(at: "c1", unit: "u1", done: ["a1", "b1"])
        let after = path(at: "d1", unit: "u2", done: ["a1", "b1", "c1"])
        XCTAssertEqual(
            diffPathProgress(before: before, after: after, completedSkillKey: "c1"),
            JourneyTransition(completedSkillKey: "c1", edges: [], unlockedSkillKeys: ["d1"]))
    }

    func testReplayOfCompletedSkillIsNil() {
        let state = path(at: "c1", unit: "u1", done: ["a1", "b1"])
        XCTAssertNil(diffPathProgress(before: state, after: state, completedSkillKey: "a1"))
    }

    func testCursorDidNotMoveIsNil() {
        let before = path(at: "a1", unit: "u1", done: [])
        let after = path(at: "a1", unit: "u1", done: ["a1"])
        XCTAssertNil(diffPathProgress(before: before, after: after, completedSkillKey: "a1"))
    }

    func testPassedOverForkAlternateIsNil() {
        // The cursor is already past the fork; finishing b2 now is not the cursor lesson.
        let before = path(at: "c1", unit: "u1", done: ["a1", "b1"])
        let after = path(at: "c1", unit: "u1", done: ["a1", "b1", "b2"])
        XCTAssertNil(diffPathProgress(before: before, after: after, completedSkillKey: "b2"))
    }

    func testLastLessonOfCourseIsNil() {
        let before = path(at: "d1", unit: "u2", done: ["a1", "b1", "c1"])
        let after = path(at: "d1", unit: "u2", done: ["a1", "b1", "c1", "d1"])
        XCTAssertNil(diffPathProgress(before: before, after: after, completedSkillKey: "d1"))
    }

    @MainActor
    func testReduceMotionPlaysNothing() async {
        final class Spy: JourneyAnimator {
            var calls: [String] = []
            func drawEdges(_ edges: [JourneyEdge]) async { calls.append("edges") }
            func playUnlock(_ skillKeys: [String]) async { calls.append("unlock") }
        }
        let transition = JourneyTransition(completedSkillKey: "a1", edges: [JourneyEdge(from: "a1", to: "b1")], unlockedSkillKeys: ["b1"])
        let quiet = Spy()
        await playJourneyTransition(transition, animator: quiet, reduceMotion: true)
        XCTAssertEqual(quiet.calls, [])
        let loud = Spy()
        await playJourneyTransition(transition, animator: loud, reduceMotion: false)
        XCTAssertEqual(loud.calls, ["edges", "unlock"])
    }
}
