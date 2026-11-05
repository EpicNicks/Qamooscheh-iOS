import XCTest
import QModel
import QDomain
import QData
@testable import QFeatures

private final class RecordingSpy: RecordingPlaying {
    var end: PlayEnd = .completed
    private(set) var keys: [[String]] = []
    func play(keys: [String], rate: Double, onEnd: @escaping (PlayEnd) -> Void) {
        self.keys.append(keys)
        onEnd(end)
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
}
