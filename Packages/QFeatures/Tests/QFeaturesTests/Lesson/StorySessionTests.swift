import XCTest
import QModel
import QDomain
import QData
@testable import QFeatures

private final class StoryGrader: Grader {
    func gradeEnvelope(_ request: GraderRequest) -> GraderResponse {
        let right = request.acceptedAnswers.contains(request.submitted)
        return GraderResponse(verdict: right ? "Correct" : "Incorrect", matchedAnswer: right ? request.submitted : nil, correct: right, xp: 0)
    }

    func xp(verdict: String, attempt: Int, usedHint: Bool, retype: Bool, retypeNumber: Int?) -> Int { 0 }
}

final class StorySessionTests: XCTestCase {
    private func exercise(_ ordinal: Int, answer: String) -> ExerciseArtifact {
        ExerciseArtifact(type: .wordBank, scriptMode: .native, prompt: "p\(ordinal)", tiles: [answer], answer: [answer], tags: [])
    }

    private func makeSession() -> LessonSession {
        let exercises = [exercise(0, answer: "a"), exercise(1, answer: "b"), exercise(2, answer: "c")]
        let instances = exercises.enumerated().map { index, ex in
            ExerciseInstance(key: "u/s/\(index)", unitKey: "u", skillKey: "s", ordinal: index, exercise: ex, renderType: .wordBank)
        }
        let setup = LessonSetup(
            courseCode: "fa", courseVersion: 1, instances: instances, exerciseCountBySkill: ["s": 3],
            story: StoryChapter(title: "Ch", exercises: exercises)
        )
        let deps = LessonDependencies(grader: StoryGrader(), gradingOnDevice: true, submit: { _ in LessonSubmitResult.queued })
        return LessonSession(setup: setup, dependencies: deps)
    }

    func testMissedLineIsNotAskedAgainAndIsMarked() {
        let session = makeSession()
        session.setTileAnswer("zzz")
        session.check()
        XCTAssertEqual(session.storyResults[0], false)
        session.continueOn()
        XCTAssertEqual(session.instance?.ordinal, 1)
        XCTAssertEqual(session.state.queue.count, 2)
    }

    func testReadingThroughCompletes() {
        let session = makeSession()
        for answer in ["a", "b", "c"] {
            session.setTileAnswer(answer)
            session.check()
            session.continueOn()
        }
        XCTAssertEqual(session.storyResults, [0: true, 1: true, 2: true])
        XCTAssertTrue(session.state.finished)
    }
}
