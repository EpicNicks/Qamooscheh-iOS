import XCTest
import QModel
@testable import QDomain

private let salam = "\u{0633}\u{0644}\u{0627}\u{0645}"
private let khoob = "\u{062E}\u{0648}\u{0628}"

private final class FakePlayer: StoryClipPlayer {
    var played: [String] = []
    var stops = 0
    private var pending: ((PlayEnd) -> Void)?

    func play(clip: String, onEnd: @escaping (PlayEnd) -> Void) {
        played.append(clip)
        pending = onEnd
    }

    func stop() {
        stops += 1
        pending = nil
    }

    /// The running clip reaches its end.
    func finishClip() {
        let done = pending
        pending = nil
        done?(.completed)
    }
}

private func line(_ i: Int, clip: String?) -> StoryReaderLine {
    StoryReaderLine(exerciseIndex: i, text: "t\(i)", romanization: nil, audio: nil, tags: [], speaker: nil, clip: clip)
}

private func make(_ clips: [String?]) -> (StoryReaderPlayback, FakePlayer) {
    let fake = FakePlayer()
    let lines = clips.enumerated().map { line($0.offset, clip: $0.element) }
    return (StoryReaderPlayback(lines: lines, player: fake), fake)
}

final class StoryReaderTests: XCTestCase {
    func testChainSkipsLinesWithoutAudioAndFinishes() {
        let (playback, fake) = make(["a", nil, "c"])
        var finished = 0
        playback.onFinished = { finished += 1 }
        XCTAssertFalse(playback.hasPlayButton(1))
        playback.playMain()
        XCTAssertEqual(fake.played, ["a"])
        fake.finishClip()
        XCTAssertEqual(fake.played, ["a", "c"])
        XCTAssertEqual(playback.position, 2)
        fake.finishClip()
        XCTAssertEqual(finished, 1)
        XCTAssertFalse(playback.isMainPlaying)
        XCTAssertTrue(playback.isFinished)
    }

    func testPerLinePlayPausesMainAndDoesNotResume() {
        let (playback, fake) = make(["a", "b"])
        playback.playMain()
        playback.playLine(1)
        XCTAssertFalse(playback.isMainPlaying)
        XCTAssertEqual(playback.playingLine, 1)
        XCTAssertEqual(fake.played, ["a", "b"])
        fake.finishClip()
        XCTAssertNil(playback.playingLine)
        XCTAssertFalse(playback.isMainPlaying)
        XCTAssertEqual(fake.played, ["a", "b"])
    }

    func testSegmentsAndSeekDeriveFromCurrentLine() {
        let (playback, fake) = make(["a", "b", "c"])
        XCTAssertEqual(playback.segments, [.current, .upcoming, .upcoming])
        playback.seek(to: 2)
        XCTAssertEqual(playback.segments, [.filled, .filled, .current])
        XCTAssertTrue(fake.played.isEmpty)
        playback.playMain()
        XCTAssertEqual(fake.played, ["c"])
        playback.seek(to: 1)
        XCTAssertEqual(fake.played, ["c", "b"])
        XCTAssertEqual(playback.segments, [.filled, .current, .upcoming])
    }

    func testPauseKeepsPositionAndStaleEndIsIgnored() {
        let (playback, fake) = make(["a", "b"])
        playback.playMain()
        fake.finishClip()
        playback.pauseMain()
        XCTAssertEqual(playback.position, 1)
        playback.playMain()
        XCTAssertEqual(fake.played, ["a", "b", "b"])
    }

    func testHoverSpeechNeedsSettingAndSilentMainPlayer() {
        XCTAssertTrue(StoryWords.canSpeakWord(speakHoveredWords: true, mainPlaying: false))
        XCTAssertFalse(StoryWords.canSpeakWord(speakHoveredWords: true, mainPlaying: true))
        XCTAssertFalse(StoryWords.canSpeakWord(speakHoveredWords: false, mainPlaying: false))
    }

    func testHighlightSavedSavedVerbNone() {
        let verbInf = "\u{0631}\u{0641}\u{062A}\u{0646}<v>"
        let verbForm = "\u{0645}\u{06CC}\u{0631}\u{0648}\u{0645}<v>"
        let word = "\u{0686}\u{0627}\u{06CC}<n>"
        let lexemes: [String: LexemeIndexEntry] = [
            verbInf: LexemeIndexEntry(gloss: "to go", pos: "verb", verbForm: "infinitive", lemma: "go", romanizationIsAuthored: false),
            verbForm: LexemeIndexEntry(gloss: "I go", pos: "verb", verbForm: "present", lemma: "go", romanizationIsAuthored: false),
            word: LexemeIndexEntry(gloss: "tea", romanizationIsAuthored: false),
        ]
        let saved: Set<String> = [verbInf, word]
        XCTAssertEqual(StoryWords.highlight(tag: word, saved: saved, lexemes: lexemes), .saved)
        XCTAssertEqual(StoryWords.highlight(tag: verbInf, saved: saved, lexemes: lexemes), .savedVerb)
        XCTAssertEqual(StoryWords.highlight(tag: verbForm, saved: saved, lexemes: lexemes), .savedVerb)
        XCTAssertEqual(StoryWords.highlight(tag: word, saved: [], lexemes: lexemes), .none)
    }

    func testLineSelectionPromptThenAnswerThenSkipped() {
        let promptAudio: AudioMap = ["v1": ["p.mp3"]]
        let answerAudio: AudioMap = ["v1": ["a.mp3"]]
        let variantAudio: [AudioMap?] = [["v1": ["a0.mp3"]], ["v1": ["a1.mp3"]]]
        let promptLine = ExerciseArtifact(
            type: .wordBank, scriptMode: .native, prompt: salam, answer: ["hello"],
            promptRomanization: "salam", answerRomanization: "x", promptAudio: promptAudio, answerAudio: answerAudio)
        let answerLine = ExerciseArtifact(
            type: .typeIn, scriptMode: .native, prompt: "good", answer: [khoob, salam],
            promptRomanization: "x", answerRomanization: "khub", promptAudio: promptAudio,
            answerAudio: answerAudio, answerVariantAudio: variantAudio)
        let englishOnly = ExerciseArtifact(type: .typeIn, scriptMode: .native, prompt: "yes", answer: ["no"])
        let lines = StoryReaderLines.lines(
            [promptLine, englishOnly, answerLine], courseCode: "fa", preferredVoice: nil, defaultVoice: "v1")
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(lines[0].text, salam)
        XCTAssertEqual(lines[0].romanization, "salam")
        XCTAssertEqual(lines[0].clip, "p.mp3")
        XCTAssertEqual(lines[1].text, khoob)
        XCTAssertEqual(lines[1].romanization, "khub")
        XCTAssertEqual(lines[1].clip, "a0.mp3")
        XCTAssertEqual(lines[1].exerciseIndex, 2)
    }

    func testLineWithoutPromptAudioHasNoClip() {
        let silent = ExerciseArtifact(type: .wordBank, scriptMode: .native, prompt: salam, answer: ["hello"])
        let lines = StoryReaderLines.lines([silent], courseCode: "fa", preferredVoice: nil, defaultVoice: nil)
        XCTAssertEqual(lines.count, 1)
        XCTAssertNil(lines[0].clip)
    }
}
