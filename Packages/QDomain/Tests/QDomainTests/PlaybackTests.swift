import XCTest
@testable import QDomain

private final class FakeBackend: PlaybackBackend {
    final class Recording {
        let url: String
        let rate: Double
        let onEnd: () -> Void
        let onError: () -> Void
        var paused = false
        init(url: String, rate: Double, onEnd: @escaping () -> Void, onError: @escaping () -> Void) {
            self.url = url
            self.rate = rate
            self.onEnd = onEnd
            self.onError = onError
        }
    }

    var recordings: [Recording] = []
    var spoken: [String] = []
    var spokenRates: [Double] = []
    var cancels = 0

    func startRecording(url: String, rate: Double, onEnd: @escaping () -> Void, onError: @escaping () -> Void) -> () -> Void {
        let recording = Recording(url: url, rate: rate, onEnd: onEnd, onError: onError)
        recordings.append(recording)
        return { recording.paused = true }
    }

    func startSpeech(text: String, lang: String, rate: Double, onEnd: @escaping () -> Void) -> () -> Void {
        spoken.append(text)
        spokenRates.append(rate)
        return { [unowned self] in self.cancels += 1 }
    }
}

final class PlaybackTests: XCTestCase {
    private var backend: FakeBackend!
    private var playback: Playback!

    override func setUp() {
        backend = FakeBackend()
        playback = Playback(backend: backend)
    }

    func testPlaysSlowedAtRequestedRate() {
        playback.play(PlaybackRequest(url: "https://cdn/a.mp3", text: "سلام", speechLang: "fa-IR", rate: Playback.slowRate))
        XCTAssertEqual(backend.recordings[0].rate, Playback.slowRate)
        playback.play(PlaybackRequest(url: nil, text: "سلام", speechLang: "fa-IR", rate: Playback.slowRate))
        XCTAssertEqual(backend.spokenRates, [Playback.slowRate])
        playback.play(PlaybackRequest(url: nil, text: "سلام", speechLang: "fa-IR"))
        XCTAssertEqual(backend.spokenRates, [Playback.slowRate, 1])
    }

    func testPlaysRecordingWhenThereIsOne() {
        playback.play(PlaybackRequest(url: "https://cdn/a.mp3", text: "سلام", speechLang: "fa-IR"))
        XCTAssertEqual(backend.recordings.map { $0.url }, ["https://cdn/a.mp3"])
        XCTAssertEqual(backend.spoken, [])
    }

    func testReadsTextAloudWithoutRecording() {
        playback.play(PlaybackRequest(url: nil, text: "سلام", speechLang: "fa-IR"))
        XCTAssertEqual(backend.spoken, ["سلام"])
    }

    func testFallsBackToSpeechWhenRecordingFails() {
        playback.play(PlaybackRequest(url: "https://cdn/missing.mp3", text: "سلام", speechLang: "fa-IR"))
        backend.recordings[0].onError()
        XCTAssertEqual(backend.spoken, ["سلام"])
    }

    func testEndsAtOnceWithNoRecordingAndNoSpeechLanguage() {
        var ends = 0
        playback.play(PlaybackRequest(url: nil, text: "سلام", speechLang: nil), onEnd: { ends += 1 })
        XCTAssertEqual(ends, 1)
        XCTAssertEqual(backend.spoken, [])
    }

    func testStopsWhatWasPlayingWhenSomethingElseStarts() {
        var first = 0
        playback.play(PlaybackRequest(url: "https://cdn/prompt.mp3", text: "x", speechLang: "fa-IR"), onEnd: { first += 1 })
        playback.play(PlaybackRequest(url: "https://cdn/tile.mp3", text: "y", speechLang: "fa-IR"))
        XCTAssertTrue(backend.recordings[0].paused)
        XCTAssertEqual(first, 1)
    }

    func testStaleHandleStoppedLaterDoesNotCancelNewerSpeech() {
        let old = playback.play(PlaybackRequest(url: nil, text: "prompt", speechLang: "fa-IR"))
        playback.play(PlaybackRequest(url: nil, text: "tile", speechLang: "fa-IR"))
        let cancelsAfterHandOver = backend.cancels
        old.stop()
        XCTAssertEqual(backend.cancels, cancelsAfterHandOver)
    }

    func testOnEndFiresExactlyOnce() {
        var ends = 0
        let handle = playback.play(PlaybackRequest(url: "https://cdn/a.mp3", text: "x", speechLang: "fa-IR"), onEnd: { ends += 1 })
        backend.recordings[0].onEnd()
        handle.stop()
        XCTAssertEqual(ends, 1)
    }
}
