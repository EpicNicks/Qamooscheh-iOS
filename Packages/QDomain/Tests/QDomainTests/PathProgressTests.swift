import XCTest
@testable import QDomain

final class PathProgressTests: XCTestCase {
    // MARK: fixtures

    private func standard(_ key: String) -> PathSkillInput {
        PathSkillInput(skillKey: key, title: key.uppercased(), category: .standard)
    }

    private func story(_ key: String, arc: String? = nil) -> PathSkillInput {
        PathSkillInput(skillKey: key, title: key.uppercased(), category: .story, arc: arc)
    }

    /// Unit 1: three standard positions (middle is a fork b1/b2) plus a story;
    /// unit 2: two standard positions plus a story.
    private func courseFixture() -> [PathUnitInput] {
        [
            PathUnitInput(
                unitKey: "u1",
                title: "Unit 1",
                standardPositions: [
                    PathPositionInput(skills: [standard("a1")]),
                    PathPositionInput(skills: [standard("b1"), standard("b2")]),
                    PathPositionInput(skills: [standard("c1")]),
                ],
                otherSkills: [story("s1")]
            ),
            PathUnitInput(
                unitKey: "u2",
                title: "Unit 2",
                standardPositions: [
                    PathPositionInput(skills: [standard("d1")]),
                    PathPositionInput(skills: [standard("e1")]),
                ],
                otherSkills: [story("s2")]
            ),
        ]
    }

    private func interludeUnit() -> PathUnitInput {
        PathUnitInput(unitKey: "u-interlude", title: "Interlude", standardPositions: [], otherSkills: [story("s3")])
    }

    private func key(_ unit: String, _ skill: String) -> PositionKey {
        PositionKey(unitKey: unit, skillKey: skill)
    }

    private func statusGrid(_ units: [PathUnit]) -> [[SkillStatus]] {
        units.map { $0.standardPositions.map { $0.status } }
    }

    private func finished(_ unit: String, _ skill: String) -> [(unitKey: String?, skillKey: String)] {
        [(unitKey: unit, skillKey: skill)]
    }

    // MARK: computePathProgress

    func testMarksCursorPositionCurrentEarlierUnlockedLaterLocked() {
        let path = computePathProgress(courseFixture(), position: key("u1", "a1"))
        XCTAssertEqual(statusGrid(path), [[.current, .locked, .locked], [.locked, .locked]])
    }

    func testTreatsForkAlternatesAsOnePositionSharingStatus() {
        let path = computePathProgress(courseFixture(), position: key("u1", "b2"))
        XCTAssertEqual(statusGrid(path), [[.unlocked, .current, .locked], [.locked, .locked]])

        let fork = path[0].standardPositions[1]
        XCTAssertEqual(fork.skills.map { $0.skillKey }, ["b1", "b2"])
        XCTAssertEqual(fork.skills.map { $0.status }, [.current, .current])
        XCTAssertEqual(fork.skills.map { $0.positionIndex }, [1, 1])
        XCTAssertTrue(fork.skills.allSatisfy { $0.unitKey == "u1" })
    }

    func testNamesSiblingAlternateCurrentWhenCursorSitsOnFirstOne() {
        let path = computePathProgress(courseFixture(), position: key("u1", "b1"))
        XCTAssertEqual(statusGrid(path)[0], [.unlocked, .current, .locked])
        XCTAssertEqual(path[0].standardPositions[1].skills.map { $0.status }, [.current, .current])
    }

    func testUnlocksEveryPositionOfPrecedingUnitWhenCursorMovedOn() {
        let path = computePathProgress(courseFixture(), position: key("u2", "e1"))
        XCTAssertEqual(statusGrid(path), [[.unlocked, .unlocked, .unlocked], [.unlocked, .current]])
    }

    func testGatesStorySkillsByUnitOnly() {
        let path = computePathProgress(courseFixture(), position: key("u1", "a1"))
        XCTAssertEqual(path[0].otherSkills.map { $0.status }, [.unlocked])
        XCTAssertEqual(path[1].otherSkills.map { $0.status }, [.locked])
        XCTAssertNil(path[0].otherSkills[0].positionIndex)
        XCTAssertEqual(path[0].otherSkills[0].unitKey, "u1")
    }

    func testUnlocksLaterUnitsStoryOnceCursorReachesThatUnit() {
        let path = computePathProgress(courseFixture(), position: key("u2", "d1"))
        XCTAssertEqual(path[1].otherSkills.map { $0.status }, [.unlocked])
    }

    func testLocksEverythingWhenThereIsNoCursor() {
        let path = computePathProgress(courseFixture(), position: nil)
        XCTAssertEqual(statusGrid(path), [[.locked, .locked, .locked], [.locked, .locked]])
        XCTAssertEqual(path.flatMap { $0.otherSkills.map { $0.status } }, [.locked, .locked])
    }

    func testLocksCursorUnitWhenSkillKeyIsUnknown() {
        let path = computePathProgress(courseFixture(), position: key("u1", "nope"))
        XCTAssertEqual(statusGrid(path)[0], [.locked, .locked, .locked])
    }

    func testLocksEverythingWhenCursorUnitIsNotInManifest() {
        let path = computePathProgress(courseFixture(), position: key("missing", "a1"))
        XCTAssertEqual(statusGrid(path), [[.locked, .locked, .locked], [.locked, .locked]])
    }

    func testPreservesUnitIdentityAndTitles() {
        let path = computePathProgress(courseFixture(), position: key("u1", "a1"))
        XCTAssertEqual(path.map { $0.unitKey }, ["u1", "u2"])
        XCTAssertEqual(path.map { $0.title }, ["Unit 1", "Unit 2"])
        XCTAssertEqual(path[0].standardPositions.map { $0.positionIndex }, [0, 1, 2])
    }

    // MARK: findNextStandardTarget

    func testNextStandardTargetReturnsNextPositionInSameUnit() {
        let path = computePathProgress(courseFixture(), position: key("u1", "a1"))
        XCTAssertEqual(findNextStandardTarget(path), key("u1", "b1"))
    }

    func testNextStandardTargetUsesFirstAlternateWhenNextIsFork() {
        let path = computePathProgress(courseFixture(), position: key("u1", "a1"))
        XCTAssertEqual(findNextStandardTarget(path)?.skillKey, "b1")
    }

    func testNextStandardTargetCrossesIntoNextUnit() {
        let path = computePathProgress(courseFixture(), position: key("u1", "c1"))
        XCTAssertEqual(findNextStandardTarget(path), key("u2", "d1"))
    }

    func testNextStandardTargetSkipsUnitWithNoStandardPositions() {
        var units = courseFixture()
        units.insert(interludeUnit(), at: 1)
        let path = computePathProgress(units, position: key("u1", "c1"))
        XCTAssertEqual(findNextStandardTarget(path), key("u2", "d1"))
    }

    func testNextStandardTargetNilAtLastPositionOfCourse() {
        let path = computePathProgress(courseFixture(), position: key("u2", "e1"))
        XCTAssertNil(findNextStandardTarget(path))
    }

    func testNextStandardTargetNilWhenNothingCurrent() {
        XCTAssertNil(findNextStandardTarget(computePathProgress(courseFixture(), position: nil)))
    }

    // MARK: findNextUnitEntryTarget

    func testNextUnitEntryTargetsNextUnitFirstPositionEvenMidUnit() {
        let path = computePathProgress(courseFixture(), position: key("u1", "a1"))
        XCTAssertEqual(findNextUnitEntryTarget(path), key("u2", "d1"))
    }

    func testNextUnitEntryNilWhenCursorUnitIsLast() {
        let path = computePathProgress(courseFixture(), position: key("u2", "e1"))
        XCTAssertNil(findNextUnitEntryTarget(path))
    }

    func testNextUnitEntrySkipsUnitWithNoStandardPositions() {
        var units = courseFixture()
        units.insert(interludeUnit(), at: 1)
        let path = computePathProgress(units, position: key("u1", "a1"))
        XCTAssertEqual(findNextUnitEntryTarget(path), key("u2", "d1"))
    }

    func testNextUnitEntryNilWhenNothingCurrent() {
        XCTAssertNil(findNextUnitEntryTarget(computePathProgress(courseFixture(), position: nil)))
    }

    // MARK: groupByArc

    func testGroupByArcCollectsSharedArcAtFirstMemberSpot() {
        let path = computePathProgress(
            [
                PathUnitInput(
                    unitKey: "u1",
                    title: "Unit 1",
                    standardPositions: [PathPositionInput(skills: [standard("a1")])],
                    otherSkills: [story("ch1", arc: "moon"), story("solo"), story("ch2", arc: "moon")]
                ),
            ],
            position: key("u1", "a1")
        )

        let groups = groupByArc(path[0].otherSkills)
        XCTAssertEqual(groups.map { $0.arc }, ["moon", nil])
        XCTAssertEqual(groups[0].skills.map { $0.skillKey }, ["ch1", "ch2"])
        XCTAssertEqual(groups[0].key, "arc:moon")
        XCTAssertEqual(groups[1].skills.map { $0.skillKey }, ["solo"])
        XCTAssertEqual(groups[1].key, "u1/solo")
    }

    func testGroupByArcReturnsNoGroupsForNoSkills() {
        XCTAssertEqual(groupByArc([]), [])
    }

    // MARK: isFirstStandardPosition

    func testIsFirstStandardPositionTrueForFirstUnitFirstPosition() {
        let path = computePathProgress(courseFixture(), position: key("u1", "a1"))
        XCTAssertTrue(isFirstStandardPosition(path, target: key("u1", "a1")))
    }

    func testIsFirstStandardPositionFalseForLaterPositionInFirstUnit() {
        let path = computePathProgress(courseFixture(), position: key("u1", "b1"))
        XCTAssertFalse(isFirstStandardPosition(path, target: key("u1", "b1")))
        XCTAssertFalse(isFirstStandardPosition(path, target: key("u1", "b2")))
    }

    func testIsFirstStandardPositionFalseForFirstPositionOfLaterUnit() {
        let path = computePathProgress(courseFixture(), position: key("u2", "d1"))
        XCTAssertFalse(isFirstStandardPosition(path, target: key("u2", "d1")))
    }

    func testIsFirstStandardPositionFalseForUnknownSkillOrEmptyPath() {
        let path = computePathProgress(courseFixture(), position: key("u1", "a1"))
        XCTAssertFalse(isFirstStandardPosition(path, target: key("u1", "nope")))
        XCTAssertFalse(isFirstStandardPosition([], target: key("u1", "a1")))
    }

    // MARK: findLessonAfter

    func testLessonAfterReturnsCursorPositionOncePastFinishedLesson() {
        let path = computePathProgress(courseFixture(), position: key("u1", "c1"))
        XCTAssertEqual(findLessonAfter(path, finished: finished("u1", "b2")), key("u1", "c1"))
    }

    func testLessonAfterCrossesIntoNextUnit() {
        let path = computePathProgress(courseFixture(), position: key("u2", "d1"))
        XCTAssertEqual(findLessonAfter(path, finished: finished("u1", "c1")), key("u2", "d1"))
    }

    func testLessonAfterUsesFirstAlternateWhenNextIsFork() {
        let path = computePathProgress(courseFixture(), position: key("u1", "b2"))
        XCTAssertEqual(findLessonAfter(path, finished: finished("u1", "a1")), key("u1", "b1"))
    }

    func testLessonAfterNilWhileCursorStillOnFinishedLesson() {
        let path = computePathProgress(courseFixture(), position: key("u2", "e1"))
        XCTAssertNil(findLessonAfter(path, finished: finished("u2", "e1")))
    }

    func testLessonAfterTreatsFinishedForkAlternateAsSamePosition() {
        let path = computePathProgress(courseFixture(), position: key("u1", "b1"))
        XCTAssertNil(findLessonAfter(path, finished: finished("u1", "b2")))
    }

    func testLessonAfterNilWithNoCursor() {
        let path = computePathProgress(courseFixture(), position: nil)
        XCTAssertNil(findLessonAfter(path, finished: finished("u1", "a1")))
    }

    // MARK: per-branch completion

    func testJoinsCompletedSkillKeysOntoEachAlternate() {
        let path = computePathProgress(courseFixture(), position: key("u1", "b1"), completedSkillKeys: ["a1", "b2"])
        let fork = path[0].standardPositions[1]
        XCTAssertEqual(fork.skills.map { $0.completed }, [false, true])
        XCTAssertFalse(path[1].otherSkills[0].completed)
    }

    func testMarksNothingWithoutCompletedSet() {
        let path = computePathProgress(courseFixture(), position: key("u1", "b1"))
        XCTAssertFalse(path[0].standardPositions.flatMap { $0.skills }.contains(where: { $0.completed }))
    }

    func testDescribesAForkBranchesAndProgress() {
        let path = computePathProgress(courseFixture(), position: key("u1", "b1"), completedSkillKeys: ["b2"])
        let branches = positionBranches(path[0].standardPositions[1])
        XCTAssertEqual(branches?.kind, .fork)
        XCTAssertEqual(branches?.done, 1)
        XCTAssertEqual(branches?.total, 2)
    }

    func testHasNoBranchesAtSingleLessonPosition() {
        let path = computePathProgress(courseFixture(), position: key("u1", "a1"))
        XCTAssertNil(positionBranches(path[0].standardPositions[0]))
    }

    func testOffersFirstUnfinishedAlternateAsNextLesson() {
        let path = computePathProgress(courseFixture(), position: key("u1", "b1"), completedSkillKeys: ["b1"])
        XCTAssertEqual(findLessonAfter(path, finished: finished("u1", "a1")), key("u1", "b2"))
    }

    func testFallsBackToFirstAlternateWhenEveryBranchFinished() {
        let path = computePathProgress(courseFixture(), position: key("u1", "b1"), completedSkillKeys: ["b1", "b2"])
        XCTAssertEqual(findLessonAfter(path, finished: finished("u1", "a1")), key("u1", "b1"))
    }
}
