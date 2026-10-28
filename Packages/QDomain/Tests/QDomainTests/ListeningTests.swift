import XCTest
import QModel
@testable import QDomain

final class ListeningTests: XCTestCase {
    private func exercise(_ type: ExerciseType, audio: AudioMap?) -> ExerciseArtifact {
        return ExerciseArtifact(type: type, scriptMode: .native, prompt: "p", answer: ["a"], promptAudio: audio)
    }

    func testUnknownTypeIsNotPlayable() {
        XCTAssertFalse(isPlayable(exercise(.unknown, audio: ["v": ["a.mp3"]])))
    }

    func testListeningNeedsARecording() {
        XCTAssertTrue(isPlayable(exercise(.listenType, audio: ["v": ["a.mp3"]])))
        XCTAssertFalse(isPlayable(exercise(.listenType, audio: nil)))
        XCTAssertFalse(isPlayable(exercise(.listenType, audio: [:])))
        XCTAssertFalse(isPlayable(exercise(.listenType, audio: ["v": []])))
        XCTAssertFalse(isPlayable(exercise(.listenType, audio: ["v": [""]])))
    }

    func testOtherTypesNeedNoRecording() {
        for type in [ExerciseType.wordBank, .typeIn, .match, .speak] {
            XCTAssertTrue(isPlayable(exercise(type, audio: nil)))
        }
    }

    func testSubmittedSessionWithUnplayableIsDeclinedNotSkipped() {
        let items = [exercise(.typeIn, audio: nil), exercise(.listenType, audio: nil)]
        XCTAssertEqual(screenUnplayable(items, submitted: true, exercise: { $0 }), .decline)
        let unknown = [exercise(.unknown, audio: nil), exercise(.typeIn, audio: nil)]
        XCTAssertEqual(screenUnplayable(unknown, submitted: true, exercise: { $0 }), .decline)
    }

    func testRepackAndPracticeLeaveUnplayableOut() {
        let kept = exercise(.typeIn, audio: nil)
        let items = [kept, exercise(.listenType, audio: nil), exercise(.unknown, audio: nil)]
        XCTAssertEqual(screenUnplayable(items, submitted: false, exercise: { $0 }), .play([kept]))
    }

    func testAllPlayableIsKeptWhenSubmitted() {
        let items = [exercise(.typeIn, audio: nil), exercise(.listenType, audio: ["v": ["a.mp3"]])]
        XCTAssertEqual(screenUnplayable(items, submitted: true, exercise: { $0 }), .play(items))
    }

    func testPlayChargedOnlyWhenTheTakeCompletes() {
        var plays = ListeningPlays()
        XCTAssertTrue(plays.begin())
        XCTAssertEqual(plays.finished, 0)
        plays.end(.completed)
        XCTAssertEqual(plays.finished, 1)
        XCTAssertEqual(plays.left, 2)
        XCTAssertTrue(plays.begin())
        plays.end(.cutOff)
        XCTAssertTrue(plays.begin())
        plays.end(.failed)
        XCTAssertEqual(plays.finished, 1)
    }

    func testButtonsLockedWhileATakePlays() {
        var plays = ListeningPlays()
        XCTAssertFalse(plays.buttonsLocked)
        XCTAssertTrue(plays.begin())
        XCTAssertTrue(plays.buttonsLocked)
        XCTAssertFalse(plays.begin(), "neither the normal nor the slow button starts a second take")
        plays.end(.completed)
        XCTAssertFalse(plays.buttonsLocked)
    }

    func testNoPlayStartsOnceThreeAreUsed() {
        var plays = ListeningPlays(finished: 2)
        XCTAssertTrue(plays.begin())
        plays.end(.completed)
        XCTAssertEqual(plays.left, 0)
        XCTAssertFalse(plays.canStart)
        XCTAssertFalse(plays.begin())
        XCTAssertEqual(plays.finished, 3)
    }

    func testEndWithoutATakeChangesNothing() {
        var plays = ListeningPlays()
        plays.end(.completed)
        XCTAssertEqual(plays.finished, 0)
    }

    func testPlaysUsedIsClampedAndOneWhenUnheard() {
        XCTAssertEqual(Listening.playsUsed(0), 1)
        XCTAssertEqual(Listening.playsUsed(2), 2)
        XCTAssertEqual(Listening.playsUsed(9), 3)
    }

    func testPricedAttemptIsTheLargerOfAttemptAndPlays() {
        XCTAssertEqual(Listening.pricedAttempt(attempt: 1, plays: 3), 3)
        XCTAssertEqual(Listening.pricedAttempt(attempt: 2, plays: 1), 2)
        XCTAssertTrue(Listening.playedMoreThanOnce(attempt: 1, plays: 2))
        XCTAssertFalse(Listening.playedMoreThanOnce(attempt: 1, plays: 1))
        XCTAssertFalse(Listening.playedMoreThanOnce(attempt: 2, plays: 2))
        XCTAssertEqual(Listening.extraPlaysNote, "You played it more than once")
    }
}

final class ListeningCandidatesTests: XCTestCase {
    func testNothingRecordedHasNoCandidates() {
        XCTAssertEqual(Listening.candidates(nil), [])
        XCTAssertEqual(Listening.candidates([:]), [])
        XCTAssertEqual(Listening.candidates(["v": []]), [])
    }

    func testEveryVoiceIsOfferedOnceInVoiceOrder() {
        let audio: AudioMap = ["b": ["b.mp3", "b2.mp3"], "a": ["a.mp3"]]
        XCTAssertEqual(Listening.candidates(audio), ["a.mp3", "b.mp3"])
    }
}
