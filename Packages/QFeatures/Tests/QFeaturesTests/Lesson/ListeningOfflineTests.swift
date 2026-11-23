import XCTest
import QModel
import QDomain
import QData
@testable import QFeatures

private final class RecordingSpy: RecordingPlaying {
    var end: PlayEnd = .completed
    /// Ends, in order, for successive plays; `end` once they run out.
    var ends: [PlayEnd] = []
    private(set) var keys: [[String]] = []
    private(set) var rates: [Double] = []
    func play(keys: [String], rate: Double, onEnd: @escaping (PlayEnd) -> Void) {
        self.keys.append(keys)
        rates.append(rate)
        onEnd(ends.isEmpty ? end : ends.removeFirst())
    }
    func stop() {}
}

private final class SynthSpy: SpeechSynthesizing {
    private(set) var spoken: [String] = []
    func installedVoiceLanguages() -> [String] { ["fa-IR"] }
    var isSpeaking: Bool { false }
    func speak(text: String, voiceLanguage: String, rate: Double, onEnd: @escaping () -> Void) {
        spoken.append(text)
        onEnd()
    }
    func stop() {}
}

/// Offline listening: a listening exercise plays only recordings from the on-disk store (Backend#44), never speech and never a stream.
final class ListeningOfflineTests: XCTestCase {
    private let take = "../../../audio/" + String(repeating: "a", count: 64) + ".mp3"

    private func session(player: RecordingSpy, synth: SynthSpy) -> LessonSession {
        let exercise = ExerciseArtifact(type: .listenType, scriptMode: .native, prompt: "p", answer: ["a"], tags: ["a"], promptAudio: ["v": [take]])
        let instance = ExerciseInstance(key: "u/s/0", unitKey: "u", skillKey: "s", ordinal: 0, exercise: exercise, renderType: .listenType)
        let setup = LessonSetup(courseCode: "fa", courseVersion: 4, instances: [instance])
        let deps = LessonDependencies(submit: { _ in LessonSubmitResult.queued }, speech: SpeechService(synthesizer: synth), recordings: player)
        return LessonSession(setup: setup, dependencies: deps)
    }

    func testAnOnDiskTakePlaysFromTheStoreAndSpeechStaysQuiet() {
        let player = RecordingSpy()
        let synth = SynthSpy()
        let lesson = session(player: player, synth: synth)
        lesson.playListening(slow: false)
        XCTAssertEqual(player.keys.count, 1)
        let key = player.keys.first?.first ?? ""
        XCTAssertTrue(key.hasPrefix("audio/"), "a store key, not a URL: \(key)")
        XCTAssertFalse(key.contains("://"))
        XCTAssertFalse(lesson.listenFailed)
        XCTAssertTrue(synth.spoken.isEmpty)
    }

    func testATakeThatCannotBeLoadedFailsFreeAndDoesNotSpeakOrHang() {
        let player = RecordingSpy()
        player.end = .failed
        let synth = SynthSpy()
        let lesson = session(player: player, synth: synth)
        lesson.playListening(slow: false)
        XCTAssertTrue(lesson.listenFailed, "the learner sees it failed")
        XCTAssertFalse(lesson.listenPlaying, "nothing is left waiting")
        XCTAssertTrue(synth.spoken.isEmpty, "a listening exercise never falls back to speech")
        lesson.playListening(slow: false)
        XCTAssertEqual(player.keys.count, 2, "a failed play costs nothing, so it can be retried")
    }

    // Dedicated slow takes (slow-take-optional-fallback)

    private let slowTake = "../../../audio/" + String(repeating: "b", count: 64) + ".mp3"

    private func slowSession(player: RecordingSpy, slowAudio: SlowAudioMap?) -> LessonSession {
        let exercise = ExerciseArtifact(type: .listenType, scriptMode: .native, prompt: "p", answer: ["a"], tags: ["a"], promptAudio: ["v": [take]], promptSlowAudio: slowAudio)
        let instance = ExerciseInstance(key: "u/s/0", unitKey: "u", skillKey: "s", ordinal: 0, exercise: exercise, renderType: .listenType)
        let setup = LessonSetup(courseCode: "fa", courseVersion: 4, instances: [instance])
        let deps = LessonDependencies(submit: { _ in LessonSubmitResult.queued }, speech: SpeechService(synthesizer: SynthSpy()), recordings: player)
        return LessonSession(setup: setup, dependencies: deps)
    }

    func testSlowButtonPlaysTheDedicatedTakeAtNormalSpeedAndIsCharged() {
        let player = RecordingSpy()
        let lesson = slowSession(player: player, slowAudio: ["v": slowTake])
        lesson.playListening(slow: true)
        XCTAssertEqual(player.keys.count, 1)
        XCTAssertTrue(player.keys[0].first?.contains(String(repeating: "b", count: 64)) ?? false)
        XCTAssertEqual(player.rates, [1])
        XCTAssertEqual(lesson.engine.state.current?.plays, 1)
    }

    func testSlowButtonSlowsTheNormalTakeWhenOnlyAnotherVoiceHasASlowTake() {
        let player = RecordingSpy()
        let lesson = slowSession(player: player, slowAudio: ["other": slowTake])
        lesson.playListening(slow: true)
        XCTAssertEqual(player.rates, [SpeechService.slowRate])
        XCTAssertTrue(player.keys[0].first?.contains(String(repeating: "a", count: 64)) ?? false)
    }

    func testSlowButtonFallsBackToTheSlowedNormalTakeWhenTheSlowFileFailsToLoad() {
        let player = RecordingSpy()
        player.ends = [.failed, .completed]
        let lesson = slowSession(player: player, slowAudio: ["v": slowTake])
        lesson.playListening(slow: true)
        XCTAssertEqual(player.rates, [1, SpeechService.slowRate])
        XCTAssertFalse(lesson.listenFailed)
        XCTAssertEqual(lesson.engine.state.current?.plays, 1, "charged once, for the take that finished")
    }

    func testTheNormalButtonIgnoresTheSlowTake() {
        let player = RecordingSpy()
        let lesson = slowSession(player: player, slowAudio: ["v": slowTake])
        lesson.playListening(slow: false)
        XCTAssertEqual(player.rates, [1])
        XCTAssertTrue(player.keys[0].first?.contains(String(repeating: "a", count: 64)) ?? false)
    }
}
