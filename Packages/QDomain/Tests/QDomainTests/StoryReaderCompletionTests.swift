import XCTest
@testable import QDomain

private final class CompletionFakePlayer: StoryClipPlayer {
    private var pending: ((PlayEnd) -> Void)?
    func play(clip: String, onEnd: @escaping (PlayEnd) -> Void) { pending = onEnd }
    func stop() { pending = nil }
    func finishClip() {
        let done = pending
        pending = nil
        done?(.completed)
    }
}

final class StoryReaderCompletionTests: XCTestCase {
    private let stamp = Date(timeIntervalSince1970: 1_700_000_000)

    private func make(_ clips: [String?]) -> (StoryReaderPlayback, CompletionFakePlayer, RecordingStoryReaderCompletionSubmitter) {
        let fake = CompletionFakePlayer()
        let lines = clips.enumerated().map {
            StoryReaderLine(exerciseIndex: $0.offset, text: "t", romanization: nil, audio: nil, tags: [], speaker: nil, clip: $0.element)
        }
        let playback = StoryReaderPlayback(lines: lines, player: fake)
        let recorder = RecordingStoryReaderCompletionSubmitter()
        let trigger = StoryReaderCompletionTrigger(
            unitKey: "u1", skillKey: "s1", courseCode: "fa", submitter: recorder, now: { Date(timeIntervalSince1970: 1_700_000_000) })
        playback.onReachedEnd = { trigger.fire() }
        return (playback, fake, recorder)
    }

    func testFiresOnceWhenChainEnds() {
        let (playback, fake, recorder) = make(["a", "b"])
        playback.playMain()
        fake.finishClip()
        fake.finishClip()
        XCTAssertEqual(recorder.requests.count, 1)
        let request = recorder.requests[0]
        XCTAssertEqual(request.unitKey, "u1")
        XCTAssertEqual(request.skillKey, "s1")
        XCTAssertEqual(request.courseCode, "fa")
        XCTAssertEqual(request.occurredAt, stamp)
        // Replaying the chain in the same open does not fire again.
        playback.playMain()
        fake.finishClip()
        fake.finishClip()
        XCTAssertEqual(recorder.requests.count, 1)
    }

    func testFiresOnceWhenLastLineReached() {
        let (playback, _, recorder) = make(["a", "b", "c"])
        playback.seek(to: 2)
        XCTAssertEqual(recorder.requests.count, 1)
        playback.seek(to: 2)
        playback.seek(to: 0)
        XCTAssertEqual(recorder.requests.count, 1)
    }

    func testPartialPlayDoesNotFire() {
        let (playback, fake, recorder) = make(["a", "b", "c"])
        playback.playMain()
        fake.finishClip()
        playback.seek(to: 1)
        playback.pauseMain()
        playback.playLine(0)
        XCTAssertTrue(recorder.requests.isEmpty)
    }
}
