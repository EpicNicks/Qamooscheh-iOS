import XCTest
import QModel
import QDomain
import QData
@testable import QFeatures

private final class Recorder: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [String] = []
    var values: [String] {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }

    func add(_ value: String) {
        lock.lock()
        stored.append(value)
        lock.unlock()
    }
}

private let course = CourseRef(code: "fa", version: 4, manifestSha256: "abc")

private func bank(_ word: String) -> ExerciseArtifact {
    ExerciseArtifact(type: .wordBank, scriptMode: .native, prompt: "p-\(word)", tiles: [word], answer: [word], tags: [word])
}

private func checkpointPlan(requiresTest: Bool = true) -> CheckpointPlanResponse {
    CheckpointPlanResponse(
        courseVersion: 4, targetUnitKey: "u2", targetSkillKey: "t",
        skills: [CheckpointSkillPlan(unitKey: "u1", skillKey: "a", exerciseOrdinals: [1])],
        skippedLessons: [], skippedCount: 2, alreadyCompletedCount: 0, requiresTest: requiresTest
    )
}

private func makeLoader(
    skills: [String: SkillArtifact] = [:],
    paths: [String: SkillArtifact] = [:],
    themes: ThemeLibraryData? = nil,
    planned: Recorder = Recorder(),
    signedIn: Bool = true
) -> LiveLessonSetupLoader {
    LiveLessonSetupLoader(
        course: { course },
        userId: { signedIn ? "user-1" : nil },
        cards: { _ in [:] },
        plan: { unitKey, skillKey in
            planned.add(unitKey + "/" + skillKey)
            return checkpointPlan()
        },
        content: LessonContentSource(
            skill: { _, unitKey, skillKey in skills[unitKey + "/" + skillKey] },
            skillAtPath: { _, path in paths[path] },
            themes: { _ in themes }
        )
    )
}

final class LiveLessonSetupLoaderTests: XCTestCase {
    func testCheckpointRoutePlansOnTheServerAndKeepsThePlannedExercises() async throws {
        let planned = Recorder()
        let skill = SkillArtifact(id: "a", title: "A", exercises: [bank("x"), bank("y"), bank("z")])
        let loader = makeLoader(skills: ["u1/a": skill], planned: planned)
        let setup = try await loader.setup(for: LessonRoute.forCheckpoint(unitKey: "u2", skillKey: "t"))
        XCTAssertEqual(planned.values, ["u2/t"])
        XCTAssertEqual(setup?.instances.map { $0.key }, ["u1/a/1"])
        XCTAssertEqual(setup?.checkpoint?.targetSkillKey, "t")
        XCTAssertEqual(setup?.courseCode, "fa")
        XCTAssertEqual(setup?.checkpointSummary, "Skipping 2 lessons.")
    }

    func testCheckpointWithAMissingSkillFileFailsRatherThanPlayingNothing() async {
        let loader = makeLoader()
        do {
            _ = try await loader.setup(for: LessonRoute.forCheckpoint(unitKey: "u2", skillKey: "t"))
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? LessonLoadError, .contentMissing)
        }
    }

    func testCheckpointPlanOnAnotherVersionRefreshesThenTellsTheLearner() async throws {
        var planned = checkpointPlan()
        planned.courseVersion = 5
        let plan = planned
        let skill = SkillArtifact(id: "a", title: "A", exercises: [bank("x"), bank("y")])
        let content = LessonContentSource(skill: { _, _, _ in skill }, skillAtPath: { _, _ in nil }, themes: { _ in nil })
        let stale = LiveLessonSetupLoader(
            course: { course }, userId: { "user-1" }, cards: { _ in [:] }, plan: { _, _ in plan }, content: content)
        do {
            _ = try await stale.setup(for: LessonRoute.forCheckpoint(unitKey: "u2", skillKey: "t"))
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? LessonLoadError, .courseUpdated)
            XCTAssertEqual((error as? LocalizedError)?.errorDescription, "This Parsle was updated. Reopen it to continue.")
        }
        // The first read is stale; the refresh finds the planned version.
        let reads = Recorder()
        let fresh = LiveLessonSetupLoader(
            course: {
                reads.add("read")
                return CourseRef(code: "fa", version: reads.values.count == 1 ? 4 : 5, manifestSha256: "abc")
            },
            userId: { "user-1" }, cards: { _ in [:] }, plan: { _, _ in plan }, content: content)
        let setup = try await fresh.setup(for: LessonRoute.forCheckpoint(unitKey: "u2", skillKey: "t"))
        XCTAssertEqual(setup?.courseVersion, 5)
    }

    func testStorySkillBecomesAChapter() async throws {
        let story = SkillArtifact(id: "s", title: "Chapter 1", category: .story, exercises: [bank("a"), bank("b")])
        let loader = makeLoader(skills: ["u1/s": story])
        let setup = try await loader.setup(for: LessonRoute(unitKey: "u1", skillKey: "s"))
        XCTAssertEqual(setup?.story?.title, "Chapter 1")
        XCTAssertEqual(setup?.story?.exercises.count, 2)
        XCTAssertEqual(setup?.instances.map { $0.key }, ["u1/s/0", "u1/s/1"])
        XCTAssertEqual(setup?.exerciseCountBySkill, ["s": 2])
        XCTAssertEqual(setup?.courseVersion, 4)
    }

    func testAStandardSkillStillReachesTheFallback() async {
        let standard = SkillArtifact(id: "s", title: "S", exercises: [bank("a")])
        let loader = makeLoader(skills: ["u1/s": standard])
        do {
            _ = try await loader.setup(for: LessonRoute(unitKey: "u1", skillKey: "s"))
            XCTFail("expected the placeholder to throw")
        } catch {
            XCTAssertTrue(error is UnwiredLessonSetupLoader.NotWired)
        }
    }

    func testRemixBuildsFromThePickedThemesStandardLessonsOnly() async throws {
        let index = ThemeIndexArtifact(themes: [
            ThemeEntry(id: "food", lessons: [
                ThemeLessonRef(id: "l1", path: "themes/l1.json"),
                ThemeLessonRef(id: "tale", path: "themes/tale.json"),
            ]),
            ThemeEntry(id: "other", lessons: [ThemeLessonRef(id: "l2", path: "themes/l2.json")]),
        ])
        let library = ThemeLibraryData(index: index, headers: [
            "l1": ThemeLessonHeader(title: "One", category: .standard),
            "tale": ThemeLessonHeader(title: "Tale", category: .story),
            "l2": ThemeLessonHeader(title: "Two", category: .standard),
        ])
        let paths = [
            "themes/l1.json": SkillArtifact(id: "l1", title: "One", exercises: [bank("a"), bank("b")]),
            "themes/tale.json": SkillArtifact(id: "tale", title: "Tale", category: .story, exercises: [bank("t")]),
            "themes/l2.json": SkillArtifact(id: "l2", title: "Two", exercises: [bank("c")]),
        ]
        let loader = makeLoader(paths: paths, themes: library)
        let setup = try await loader.setup(for: LessonRoute.forRemix(themeIds: ["food"]))
        XCTAssertEqual(setup?.instances.map { $0.key }, ["_/l1/0", "_/l1/1"])
        XCTAssertEqual(setup?.exerciseCountBySkill, ["l1": 2])
        XCTAssertNil(setup?.story)
        XCTAssertFalse(setup?.practice ?? true)
    }

    func testRemixWithNothingToPlayIsNil() async throws {
        let library = ThemeLibraryData(index: ThemeIndexArtifact(themes: [ThemeEntry(id: "empty", lessons: [])]), headers: [:])
        let loader = makeLoader(themes: library)
        let setup = try await loader.setup(for: LessonRoute.forRemix(themeIds: ["empty"]))
        XCTAssertNil(setup)
    }

    func testRemixRouteCarriesTheThemes() {
        let route = LessonRoute.forRemix(themeIds: ["a", "b"])
        XCTAssertEqual(route.remixThemeIds, ["a", "b"])
        XCTAssertFalse(route.checkpoint)
        XCTAssertTrue(route.needsContentsChoice)
        let chosen = route.choosing(.typeIn, hardcore: true)
        XCTAssertFalse(chosen.needsContentsChoice)
        XCTAssertEqual(chosen.remixContents, .typeIn)
        XCTAssertTrue(chosen.hardcore)
        XCTAssertFalse(LessonRoute(skillKey: "s").needsContentsChoice)
    }

    func testDeepDiveBlendsTheOtherLessonsUnderTheTopicsTheLessonTouches() async throws {
        let library = ThemeLibraryData(
            index: ThemeIndexArtifact(themes: [
                ThemeEntry(id: "food", lessons: [ThemeLessonRef(id: "src", path: "themes/src.json"), ThemeLessonRef(id: "l2", path: "themes/l2.json")]),
                ThemeEntry(id: "travel", lessons: [ThemeLessonRef(id: "l3", path: "themes/l3.json")]),
            ]),
            headers: [
                "src": ThemeLessonHeader(title: "Src", category: .standard),
                "l2": ThemeLessonHeader(title: "Two", category: .standard),
                "l3": ThemeLessonHeader(title: "Three", category: .standard),
            ])
        let paths = [
            "themes/src.json": SkillArtifact(id: "src", title: "Src", exercises: [bank("s")]),
            "themes/l2.json": SkillArtifact(id: "l2", title: "Two", exercises: [bank("b")]),
            "themes/l3.json": SkillArtifact(id: "l3", title: "Three", exercises: [bank("c")]),
        ]
        let loader = makeLoader(paths: paths, themes: library)
        let route = LessonRoute.forDeepDive(lessonKey: "src")
        XCTAssertTrue(route.isRemix)
        XCTAssertTrue(route.needsContentsChoice)
        XCTAssertFalse(route.choosing(.all, hardcore: false).needsContentsChoice)
        let setup = try await loader.setup(for: route.choosing(.all, hardcore: false))
        // Only the lessons under src's own topics, and not src itself.
        XCTAssertEqual(setup?.instances.map { $0.key }, ["_/l2/0"])
        let pool = try await loader.remixCloze(for: route.choosing(.cloze, hardcore: false))
        XCTAssertEqual(pool?.tags, ["b"])
    }

    func testDeepDiveWithNothingElseToBlendPlaysTheLessonItself() async throws {
        let library = ThemeLibraryData(
            index: ThemeIndexArtifact(themes: [ThemeEntry(id: "food", lessons: [ThemeLessonRef(id: "src", path: "themes/src.json")])]),
            headers: ["src": ThemeLessonHeader(title: "Src", category: .standard)])
        let loader = makeLoader(
            paths: ["themes/src.json": SkillArtifact(id: "src", title: "Src", exercises: [bank("s")])], themes: library)
        let setup = try await loader.setup(for: LessonRoute.forDeepDive(lessonKey: "src", contents: .all))
        XCTAssertEqual(setup?.instances.map { $0.key }, ["_/src/0"])
    }

    private func foodLoader() -> LiveLessonSetupLoader {
        let library = ThemeLibraryData(
            index: ThemeIndexArtifact(themes: [ThemeEntry(id: "food", lessons: [ThemeLessonRef(id: "l1", path: "themes/l1.json")])]),
            headers: ["l1": ThemeLessonHeader(title: "One", category: .standard)])
        let typed = ExerciseArtifact(type: .typeIn, scriptMode: .native, prompt: "p-typed", answer: ["a"], tags: ["a"])
        return makeLoader(paths: ["themes/l1.json": SkillArtifact(id: "l1", title: "One", exercises: [bank("b"), typed])], themes: library)
    }

    func testRemixKeepsOnlyTheChosenContents() async throws {
        let loader = foodLoader()
        let typing = try await loader.setup(for: LessonRoute.forRemix(themeIds: ["food"], contents: .typeIn))
        XCTAssertEqual(typing?.instances.map { $0.key }, ["_/l1/1"])
        let bankOnly = try await loader.setup(for: LessonRoute.forRemix(themeIds: ["food"], contents: .wordBank))
        XCTAssertEqual(bankOnly?.instances.map { $0.key }, ["_/l1/0"])
        let none = try await loader.setup(for: LessonRoute.forRemix(themeIds: ["food"], contents: .cloze))
        XCTAssertNil(none)
    }

    func testRemixClozePoolHoldsThePickedLessonsExercisesAndTheirWordsInOrder() async throws {
        let loader = foodLoader()
        let pool = try await loader.remixCloze(for: LessonRoute.forRemix(themeIds: ["food"], contents: .cloze))
        XCTAssertEqual(pool?.courseCode, "fa")
        XCTAssertEqual(pool?.exercises.count, 2)
        XCTAssertEqual(pool?.tags, ["b", "a"])
        let notARemix = try await loader.remixCloze(for: LessonRoute(skillKey: "s"))
        XCTAssertNil(notARemix)
    }

    func testPassedCheckpointAnnouncesARefreshAndAFailedOneDoesNot() {
        let center = NotificationCenter()
        let heard = Recorder()
        let token = center.addObserver(forName: CheckpointRefresh.notification, object: nil, queue: nil) { _ in heard.add("x") }
        defer { center.removeObserver(token) }
        func response(passed: Bool) -> CheckpointSubmitResponse {
            CheckpointSubmitResponse(
                passed: passed, score: 0.9, cards: [], skippedLessons: [], skippedCount: 1,
                alreadyCompletedCount: 0, requiresTest: true, applied: passed
            )
        }
        CheckpointRefresh.announce(response(passed: false), center: center)
        XCTAssertEqual(heard.values.count, 0)
        CheckpointRefresh.announce(response(passed: true), center: center)
        XCTAssertEqual(heard.values.count, 1)
    }
}

private final class RightOnlyGrader: Grader {
    func gradeEnvelope(_ request: GraderRequest) -> GraderResponse {
        let right = request.acceptedAnswers.contains(request.submitted)
        return GraderResponse(verdict: right ? "Correct" : "Incorrect", matchedAnswer: right ? request.submitted : nil, correct: right, xp: 0)
    }

    func xp(verdict: String, attempt: Int, usedHint: Bool, retype: Bool, retypeNumber: Int?) -> Int { 0 }
}

final class StoryResumeTests: XCTestCase {
    func testResumedStoryRebuildsEarlierMarks() {
        let exercises = [bank("a"), bank("b"), bank("c")]
        let instances = exercises.enumerated().map { index, ex in
            ExerciseInstance(key: "u/s/\(index)", unitKey: "u", skillKey: "s", ordinal: index, exercise: ex, renderType: .wordBank)
        }
        let setup = LessonSetup(
            courseCode: "fa", courseVersion: 1, instances: instances, exerciseCountBySkill: ["s": 3],
            story: StoryChapter(title: "Ch", exercises: exercises)
        )
        func item(_ ordinal: Int, _ text: String) -> RecordedItem {
            RecordedItem(unitKey: "u", skillKey: "s", item: SubmittedItem(
                exerciseOrdinal: ordinal, lexemeTag: "t", exerciseType: .wordBank, scriptMode: .native,
                submittedText: text, usedHint: false, latencyMs: nil, attempt: 1
            ))
        }
        let saved = LessonState(queue: [instances[2]], totalCount: 3, items: [item(0, "a"), item(1, "zzz")])
        let draft = MemoryLessonDraft(saved)
        let deps = LessonDependencies(
            grader: RightOnlyGrader(), gradingOnDevice: true, submit: { _ in LessonSubmitResult.queued }, draft: draft.store
        )
        let session = LessonSession(setup: setup, dependencies: deps)
        XCTAssertEqual(session.instance?.ordinal, 2)
        XCTAssertEqual(session.storyResults, [0: true, 1: false])
    }
}

final class SavedPracticeRouteTests: XCTestCase {
    func testExercisesStringParsesBackToRefsAndSkipsMalformedEntries() {
        let picked = SavedPracticeExercises(courseVersion: 4, exercises: "u1/a/2,bad,u2/b/0,u3//1,u4/c/x", count: 2)
        XCTAssertEqual(picked.refs, [
            StarredPracticeExercise(unitKey: "u1", skillKey: "a", ordinal: 2),
            StarredPracticeExercise(unitKey: "u2", skillKey: "b", ordinal: 0),
        ])
        XCTAssertEqual(LessonRoute.forSavedPractice(picked).exerciseRefs, picked.refs)
    }

    func testSavedPracticePlaysOnlyThePickedExercisesInOrderWithoutDuplicates() async throws {
        let a = SkillArtifact(id: "a", title: "A", exercises: [bank("a0"), bank("a1"), bank("a2")])
        let b = SkillArtifact(id: "b", title: "B", exercises: [bank("b0"), bank("b1")])
        let loader = makeLoader(skills: ["u1/a": a, "u2/b": b])
        let picked = SavedPracticeExercises(courseVersion: 4, exercises: "u2/b/1,u1/a/2,u2/b/1,u9/gone/0,u1/a/7", count: 2)
        let setup = try await loader.setup(for: LessonRoute.forSavedPractice(picked))
        XCTAssertEqual(setup?.instances.map { $0.key }, ["u2/b/1", "u1/a/2"])
        XCTAssertEqual(setup?.exerciseCountBySkill, ["u1/a": 3, "u2/b": 2])
        XCTAssertEqual(setup?.courseCode, "fa")
        XCTAssertNil(setup?.story)
    }

    func testSavedPracticeWithNothingFoundIsNil() async throws {
        let loader = makeLoader()
        let picked = SavedPracticeExercises(courseVersion: 4, exercises: "u1/a/0", count: 1)
        let setup = try await loader.setup(for: LessonRoute.forSavedPractice(picked))
        XCTAssertNil(setup)
    }

    func testSavedPracticePickedForAnotherCourseVersionFailsInsteadOfPlaying() async {
        let a = SkillArtifact(id: "a", title: "A", exercises: [bank("a0")])
        let loader = makeLoader(skills: ["u1/a": a])
        let picked = SavedPracticeExercises(courseVersion: 3, exercises: "u1/a/0", count: 1)
        do {
            _ = try await loader.setup(for: LessonRoute.forSavedPractice(picked))
            XCTFail("expected a version mismatch")
        } catch {
            XCTAssertEqual(error as? LessonLoadError, .courseVersionMismatch)
        }
    }

    func testSameSkillKeyInTwoUnitsKeepsSeparateCounts() async throws {
        let one = SkillArtifact(id: "a", title: "A", exercises: [bank("x"), bank("y")])
        let two = SkillArtifact(id: "a", title: "A", exercises: [bank("p"), bank("q"), bank("r")])
        let loader = makeLoader(skills: ["u1/a": one, "u2/a": two])
        let picked = SavedPracticeExercises(courseVersion: 4, exercises: "u1/a/0,u2/a/1", count: 2)
        let setup = try await loader.setup(for: LessonRoute.forSavedPractice(picked))
        XCTAssertEqual(setup?.exerciseCountBySkill, ["u1/a": 2, "u2/a": 3])
    }

    func testDraftKeyDiffersForADifferentPickedSetAndIsStableForTheSame() {
        let first = LessonRoute.forSavedPractice(SavedPracticeExercises(courseVersion: 4, exercises: "u1/a/0,u1/a/1", count: 2))
        let again = LessonRoute.forSavedPractice(SavedPracticeExercises(courseVersion: 4, exercises: "u1/a/0,u1/a/1", count: 2))
        let other = LessonRoute.forSavedPractice(SavedPracticeExercises(courseVersion: 4, exercises: "u1/a/2,u1/a/3", count: 2))
        XCTAssertEqual(first.skillKey, again.skillKey)
        XCTAssertNotEqual(first.skillKey, other.skillKey)
    }
}
