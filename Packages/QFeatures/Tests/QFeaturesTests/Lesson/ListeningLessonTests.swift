import XCTest
import QModel
import QDomain
@testable import QFeatures

private final class ListenGrader: Grader {
    var verdicts: [String]
    init(_ verdicts: [String]) { self.verdicts = verdicts }

    func gradeEnvelope(_ request: GraderRequest) -> GraderResponse {
        let v = verdicts.isEmpty ? "Correct" : verdicts.removeFirst()
        return GraderResponse(verdict: v, matchedAnswer: request.acceptedAnswers.first, correct: v == "Correct", acceptedWithCorrection: false, xp: 0)
    }

    func xp(verdict: String, attempt: Int, usedHint: Bool, retype: Bool, retypeNumber: Int?) -> Int { 0 }
}

final class ListeningLessonTests: XCTestCase {
    private func listening(_ answer: String, audio: AudioMap? = ["v": ["a.mp3"]]) -> ExerciseArtifact {
        ExerciseArtifact(type: .listenType, scriptMode: .native, prompt: "p", answer: [answer], tags: [answer], promptAudio: audio)
    }

    private func engine(_ exercises: [ExerciseArtifact], grader: Grader? = ListenGrader([])) -> LessonEngine {
        let skill = SkillArtifact(id: "s", title: "S", exercises: exercises)
        let instances = buildInstances(skills: [(ref: SkillRef(unitKey: "u", skillKey: "s"), skill: skill)], cards: [:])
        return LessonEngine(state: LessonState(queue: instances), courseCode: "fa", grader: grader)
    }

    func testListenTypeRendersAsItself() {
        let e = engine([listening("a")])
        XCTAssertEqual(e.state.current?.renderType, .listenType)
        XCTAssertTrue(e.state.current?.listening ?? false)
        XCTAssertEqual(e.state.current?.playsLeft, 3)
    }

    func testListeningSharesTheTypingField() {
        XCTAssertTrue(LessonScreenLogic.isTypeIn(.listenType))
    }

    func testAFinishedPlayIsCountedOnTheInstanceUpToThree() {
        var e = engine([listening("a")])
        let key = e.state.current?.key ?? ""
        for _ in 0..<5 { e.recordPlay(key: key) }
        XCTAssertEqual(e.state.current?.plays, 3)
        XCTAssertEqual(e.state.current?.playsLeft, 0)
    }

    func testAPlayForAnotherExerciseIsIgnored() {
        var e = engine([listening("a")])
        e.recordPlay(key: "somewhere/else")
        XCTAssertEqual(e.state.current?.plays, 0)
    }

    func testPlayIsNotCountedForOtherTypes() {
        let plain = ExerciseArtifact(type: .typeIn, scriptMode: .native, prompt: "p", answer: ["a"], tags: ["a"])
        var e = engine([plain])
        let key = e.state.current?.key ?? ""
        e.recordPlay(key: key)
        XCTAssertEqual(e.state.current?.plays, 0)
    }

    func testAnswerCarriesPlaysUsedAndOneWhenUnheard() {
        var unheard = engine([listening("a")])
        XCTAssertEqual(unheard.submit("a")?.state.items.first?.item.playsUsed, 1)

        var heard = engine([listening("a")])
        let key = heard.state.current?.key ?? ""
        heard.recordPlay(key: key)
        heard.recordPlay(key: key)
        let item = heard.submit("a")?.state.items.first?.item
        XCTAssertEqual(item?.playsUsed, 2)
        XCTAssertEqual(item?.exerciseType, .listenType)
    }

    func testOtherTypesSendNoPlaysUsed() {
        let plain = ExerciseArtifact(type: .typeIn, scriptMode: .native, prompt: "p", answer: ["a"], tags: ["a"])
        var e = engine([plain])
        XCTAssertNil(e.submit("a")?.state.items.first?.item.playsUsed)
    }

    func testExtraPlaysCostXpAndAreSaid() {
        var once = engine([listening("a")])
        let onceKey = once.state.current?.key ?? ""
        once.recordPlay(key: onceKey)
        let single = once.submit("a")
        XCTAssertEqual(single?.xpGained, 10)
        XCTAssertEqual(single?.extraPlays, false)

        var thrice = engine([listening("a")])
        let key = thrice.state.current?.key ?? ""
        thrice.recordPlay(key: key)
        thrice.recordPlay(key: key)
        thrice.recordPlay(key: key)
        let many = thrice.submit("a")
        XCTAssertEqual(many?.xpGained, 5)
        XCTAssertEqual(many?.extraPlays, true)
    }

    func testAWrongAnswerIsRetriedWithFreshPlays() {
        var e = engine([listening("a"), listening("b"), listening("c"), listening("d")], grader: ListenGrader(["Incorrect"]))
        let key = e.state.current?.key ?? ""
        e.recordPlay(key: key)
        e.recordPlay(key: key)
        let outcome = e.submit("zzz")
        XCTAssertEqual(outcome?.requeued, true)
        XCTAssertEqual(outcome?.extraPlays, false)
        let again = e.state.queue.first { $0.key == key }
        XCTAssertEqual(again?.attempt, 1)
        XCTAssertEqual(again?.plays, 0)
    }

    func testPlaysSurviveTheDraftRoundTrip() throws {
        var e = engine([listening("a")])
        let key = e.state.current?.key ?? ""
        e.recordPlay(key: key)
        let data = try JSONEncoder().encode(e.state)
        let restored = try JSONDecoder().decode(LessonState.self, from: data)
        XCTAssertEqual(restored.current?.plays, 1)
    }

    func testADraftSavedBeforePlaysExistedStillLoads() throws {
        let e = engine([listening("a")])
        let data = try JSONEncoder().encode(e.state)
        var text = String(data: data, encoding: .utf8) ?? ""
        text = text.replacingOccurrences(of: ",\"plays\":0", with: "").replacingOccurrences(of: "\"plays\":0,", with: "")
        XCTAssertFalse(text.contains("\"plays\""))
        let restored = try JSONDecoder().decode(LessonState.self, from: Data(text.utf8))
        XCTAssertEqual(restored.current?.plays, 0)
    }

    func testCheckpointItemsCarryPlaysUsedForListeningOnly() {
        let info = CheckpointPlanInfo(courseVersion: 3, targetUnitKey: "u2", targetSkillKey: "t", skippedCount: 1, alreadyCompletedCount: 0, requiresTest: true)
        let heard = ExerciseInstance(key: "u/s/0", unitKey: "u", skillKey: "s", ordinal: 0, exercise: listening("a"), renderType: .listenType)
        let typed = ExerciseInstance(key: "u/s/1", unitKey: "u", skillKey: "s", ordinal: 1, exercise: ExerciseArtifact(type: .typeIn, scriptMode: .native, prompt: "p", answer: ["b"], tags: ["b"]), renderType: .typeIn)
        let request = CheckpointLogic.request(
            info: info, instances: [heard, typed], answers: ["u/s/0": "x", "u/s/1": "y"], plays: ["u/s/0": 2],
            submissionId: "id", occurredAt: Date(timeIntervalSince1970: 1)
        )
        let items = request.skills[0].items
        XCTAssertEqual(items[0].playsUsed, 2)
        XCTAssertNil(items[1].playsUsed)
    }

    // MARK: Unplayable exercises

    private func route(remix: Bool = false, refs: Bool = false) -> LessonRoute {
        var r = LessonRoute(skillKey: "s")
        if remix { r.remixThemeIds = ["t"] }
        if refs { r.exerciseRefs = [] }
        return r
    }

    private func setup(_ exercises: [ExerciseArtifact]) -> LessonSetup {
        let skill = SkillArtifact(id: "s", title: "S", exercises: exercises)
        let instances = buildInstances(skills: [(ref: SkillRef(unitKey: "u", skillKey: "s"), skill: skill)], cards: [:])
        return LessonSetup(courseCode: "fa", courseVersion: 1, instances: instances)
    }

    func testALessonWithAnUnrecordedListeningExerciseIsDeclined() {
        let s = setup([listening("a"), listening("b", audio: nil)])
        XCTAssertThrowsError(try LessonEnvironment.screened(s, route: route())) { error in
            XCTAssertEqual(error as? LessonLoadError, .unplayable)
        }
    }

    func testALessonWithAnUnknownTypeIsDeclined() {
        let unknown = ExerciseArtifact(type: .unknown, scriptMode: .native, prompt: "p", answer: ["a"])
        XCTAssertThrowsError(try LessonEnvironment.screened(setup([unknown]), route: route()))
    }

    func testARemixAndSavedPracticeLeaveThemOut() throws {
        let s = setup([listening("a"), listening("b", audio: nil)])
        XCTAssertEqual(try LessonEnvironment.screened(s, route: route(remix: true)).instances.count, 1)
        XCTAssertEqual(try LessonEnvironment.screened(s, route: route(refs: true)).instances.count, 1)
    }

    func testAFullyPlayableLessonIsUntouched() throws {
        let s = setup([listening("a")])
        XCTAssertEqual(try LessonEnvironment.screened(s, route: route()), s)
    }

    func testTheDeclineMessageReachesTheLearner() {
        XCTAssertEqual(LessonLoadError.unplayable.errorDescription, unplayableLessonMessage)
    }

    func testListenPromptCopy() {
        XCTAssertEqual(ListenPromptCopy.playsLeftText(3), "3 plays left")
        XCTAssertEqual(ListenPromptCopy.playsLeftText(1), "1 play left")
        XCTAssertEqual(ListenPromptCopy.playsLeftText(0), "No plays left")
        XCTAssertEqual(ListenPromptCopy.playLabel(playsLeft: 2), "Play audio, 2 plays left")
    }
}
