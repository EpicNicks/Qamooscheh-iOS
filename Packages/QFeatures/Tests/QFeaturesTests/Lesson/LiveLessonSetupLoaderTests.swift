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
