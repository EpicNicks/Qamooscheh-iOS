import XCTest
@testable import QData

private final class FakeSynthesizer: SpeechSynthesizing {
    var voices: [String]
    var spoken: [(text: String, voice: String, rate: Double)] = []
    var stopCalls = 0
    var pending: (() -> Void)?
    var isSpeaking = false

    init(voices: [String]) { self.voices = voices }

    func installedVoiceLanguages() -> [String] { return voices }

    func speak(text: String, voiceLanguage: String, rate: Double, onEnd: @escaping () -> Void) {
        spoken.append((text, voiceLanguage, rate))
        pending = onEnd
        isSpeaking = true
    }

    func stop() {
        stopCalls += 1
        isSpeaking = false
        // A real engine reports the cancel afterwards.
        let callback = pending
        pending = nil
        callback?()
    }

    func finishSpeaking() {
        isSpeaking = false
        let callback = pending
        pending = nil
        callback?()
    }
}

final class SpeechServiceTests: XCTestCase {
    func testExactVoicePreferredThenSameLanguage() {
        let fake = FakeSynthesizer(voices: ["fa-AF", "ja-JP", "fa-IR"])
        let service = SpeechService(synthesizer: fake)
        XCTAssertEqual(service.voice(for: "fa-IR"), "fa-IR")
        fake.voices = ["fa-AF", "ja-JP"]
        XCTAssertEqual(service.voice(for: "fa-IR"), "fa-AF")
        XCTAssertEqual(service.voice(for: "ja_JP"), "ja-JP")
    }

    func testNoVoiceReturnsFalseAndSpeaksNothing() {
        let fake = FakeSynthesizer(voices: ["ja-JP"])
        let service = SpeechService(synthesizer: fake)
        var ended = 0
        XCTAssertFalse(service.hasVoice("fa-IR"))
        XCTAssertFalse(service.speak("salam", languageTag: "fa-IR", onEnd: { ended += 1 }))
        XCTAssertTrue(fake.spoken.isEmpty)
        XCTAssertEqual(ended, 0)
    }

    func testStartSpeechWithNoVoiceEndsAtOnce() {
        let fake = FakeSynthesizer(voices: [])
        let service = SpeechService(synthesizer: fake)
        var ended = 0
        let stop = service.startSpeech(text: "x", lang: "fa-IR", rate: 1, onEnd: { ended += 1 })
        XCTAssertEqual(ended, 1)
        stop()
        XCTAssertEqual(ended, 1)
        XCTAssertEqual(fake.stopCalls, 0)
    }

    func testSpeakPassesVoiceAndRate() {
        let fake = FakeSynthesizer(voices: ["ja-JP"])
        let service = SpeechService(synthesizer: fake)
        XCTAssertTrue(service.speak("konnichiwa", languageTag: "ja-JP", rate: SpeechService.slowRate))
        XCTAssertEqual(fake.spoken.count, 1)
        XCTAssertEqual(fake.spoken[0].voice, "ja-JP")
        XCTAssertEqual(fake.spoken[0].rate, 0.7, accuracy: 0.0001)
        XCTAssertTrue(service.isSpeaking)
    }

    func testNewSpeechInterruptsOldAndEndsItOnce() {
        let fake = FakeSynthesizer(voices: ["ja-JP"])
        let service = SpeechService(synthesizer: fake)
        var firstEnded = 0
        var secondEnded = 0
        service.speak("one", languageTag: "ja-JP", onEnd: { firstEnded += 1 })
        service.speak("two", languageTag: "ja-JP", onEnd: { secondEnded += 1 })
        XCTAssertEqual(firstEnded, 1)
        XCTAssertEqual(secondEnded, 0)
        XCTAssertEqual(fake.spoken.map { $0.text }, ["one", "two"])
        fake.finishSpeaking()
        XCTAssertEqual(firstEnded, 1)
        XCTAssertEqual(secondEnded, 1)
    }

    func testFailedRequestStillInterruptsCurrentSpeech() {
        let fake = FakeSynthesizer(voices: ["ja-JP"])
        let service = SpeechService(synthesizer: fake)
        var ended = 0
        service.speak("one", languageTag: "ja-JP", onEnd: { ended += 1 })
        XCTAssertFalse(service.speak("two", languageTag: "fa-IR"))
        XCTAssertEqual(ended, 1)
        XCTAssertEqual(fake.stopCalls, 1)
    }

    func testStaleStopHandleDoesNotCutOffNewerSpeech() {
        let fake = FakeSynthesizer(voices: ["ja-JP"])
        let service = SpeechService(synthesizer: fake)
        let stopOld = service.startSpeech(text: "old", lang: "ja-JP", rate: 1, onEnd: {})
        var newEnded = 0
        _ = service.startSpeech(text: "new", lang: "ja-JP", rate: 1, onEnd: { newEnded += 1 })
        stopOld()
        XCTAssertEqual(newEnded, 0)
        XCTAssertTrue(service.isSpeaking)
    }

    func testStopHandleStopsItsOwnSpeech() {
        let fake = FakeSynthesizer(voices: ["ja-JP"])
        let service = SpeechService(synthesizer: fake)
        var ended = 0
        let stop = service.startSpeech(text: "a", lang: "ja-JP", rate: 1, onEnd: { ended += 1 })
        stop()
        XCTAssertEqual(ended, 1)
        XCTAssertFalse(service.isSpeaking)
    }

    func testFinishEndsOnce() {
        let fake = FakeSynthesizer(voices: ["ja-JP"])
        let service = SpeechService(synthesizer: fake)
        var ended = 0
        service.speak("a", languageTag: "ja-JP", onEnd: { ended += 1 })
        fake.finishSpeaking()
        service.stop()
        XCTAssertEqual(ended, 1)
    }
}
