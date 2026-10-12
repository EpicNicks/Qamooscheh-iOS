import XCTest
import QModel
@testable import QDomain

final class RecordingsTests: XCTestCase {
    private let noPreference = VoiceChoice(preferredVoice: nil, defaultVoice: "setareh")
    private let audio: AudioMap = ["setareh": ["s0.mp3", "s1.mp3"], "hooman": ["h0.mp3"]]

    // pickRecording

    func testPlaysPreferredVoicesFirstTake() {
        let choice = VoiceChoice(preferredVoice: "hooman", defaultVoice: "setareh")
        XCTAssertEqual(Recordings.pickRecording(audio, choice: choice), "h0.mp3")
    }

    func testFallsBackToDefaultVoiceWhenPreferredHasNoTake() {
        let choice = VoiceChoice(preferredVoice: "ali", defaultVoice: "setareh")
        XCTAssertEqual(Recordings.pickRecording(audio, choice: choice), "s0.mp3")
    }

    func testFallsBackToAnyVoiceWithATake() {
        XCTAssertEqual(Recordings.pickRecording(["hooman": ["h0.mp3"]], choice: noPreference), "h0.mp3")
    }

    func testSpeakerLineKeepsToSpeakerVoices() {
        let hooman = VoiceChoice(preferredVoice: nil, defaultVoice: "setareh", speakerVoices: ["hooman"])
        XCTAssertEqual(Recordings.pickRecording(audio, choice: hooman), "h0.mp3")
        let both = VoiceChoice(preferredVoice: "setareh", defaultVoice: "setareh", speakerVoices: ["hooman", "setareh"])
        XCTAssertEqual(Recordings.pickRecording(audio, choice: both), "s0.mp3")
    }

    func testPlaysAnotherVoiceWhenNoSpeakerVoiceRecordedTheLine() {
        let ali = VoiceChoice(preferredVoice: nil, defaultVoice: "setareh", speakerVoices: ["ali"])
        XCTAssertEqual(Recordings.pickRecording(audio, choice: ali), "s0.mp3")
    }

    func testNilWhenNothingIsRecorded() {
        XCTAssertNil(Recordings.pickRecording(nil, choice: noPreference))
        XCTAssertNil(Recordings.pickRecording(["setareh": []], choice: noPreference))
    }

    // exerciseVoice

    private let cast = ["ali", "hooman", "setareh"]

    private func question(_ i: Int, audio: AudioMap? = nil, speaker: [String] = [], seed: Int = 7) -> String? {
        let map: AudioMap = audio ?? ["setareh": ["s\(i).mp3"], "hooman": ["h\(i).mp3"]]
        return Recordings.exerciseVoice(prompt: "prompt \(i)", answer: "answer \(i)", promptAudio: map, answerAudio: map, cast: cast, speakerVoices: speaker, seed: seed)
    }

    func testExerciseVoiceStableForSameSeed() {
        for i in 0..<20 { XCTAssertEqual(question(i), question(i)) }
    }

    func testExerciseVoiceVariesAcrossQuestions() {
        let voices = Set((0..<40).compactMap { question($0) })
        XCTAssertEqual(voices, ["hooman", "setareh"])
    }

    func testExerciseVoicePrefersBothThenEither() {
        for seed in 0..<20 {
            let split = Recordings.exerciseVoice(prompt: "p", answer: "a", promptAudio: ["setareh": ["s.mp3"], "hooman": ["h.mp3"]], answerAudio: ["hooman": ["h2.mp3"]], cast: cast, speakerVoices: [], seed: seed)
            let promptOnly = Recordings.exerciseVoice(prompt: "p", answer: "a", promptAudio: ["setareh": ["s.mp3"], "hooman": []], answerAudio: nil, cast: cast, speakerVoices: [], seed: seed)
            XCTAssertEqual(split, "hooman")
            XCTAssertEqual(promptOnly, "setareh")
        }
    }

    func testExerciseVoiceDrawsFromWholeCastWhenNothingRecorded() {
        let voices = Set((0..<40).compactMap {
            Recordings.exerciseVoice(prompt: "p\($0)", answer: "a", promptAudio: nil, answerAudio: nil, cast: cast, speakerVoices: [], seed: 3)
        })
        XCTAssertEqual(voices, Set(cast))
    }

    func testExerciseVoiceKeepsSpeakerQuestionToSpeakerVoices() {
        let all: AudioMap = ["setareh": ["s.mp3"], "hooman": ["h.mp3"], "ali": ["a.mp3"]]
        for i in 0..<20 { XCTAssertEqual(question(i, audio: all, speaker: ["ali"], seed: i), "ali") }
    }

    // lineVoice

    func testLineVoiceDrawsAmongRecordedVoicesSpeakerFirst() {
        for seed in 0..<20 {
            XCTAssertEqual(Recordings.lineVoice(audio: ["setareh": [], "hooman": ["h0.mp3"]], speakerVoices: [], seed: seed), "hooman")
            XCTAssertEqual(Recordings.lineVoice(audio: ["setareh": ["s0.mp3"], "hooman": ["h0.mp3"]], speakerVoices: ["setareh"], seed: seed), "setareh")
        }
        XCTAssertNil(Recordings.lineVoice(audio: nil, speakerVoices: [], seed: 1))
    }

    // hash (values from web hash(), as in Android's RecordingsTest)

    func testVoiceHashMatchesWeb() {
        let expected: [String: UInt32] = [
            "": 2872998923,
            "7:s0.mp3|h0.mp3": 373146186,
            "12345:../../../audio/ab.mp3|../../../audio/cd.mp3": 3510813758,
            "سلام": 707356599,
        ]
        for (text, hash) in expected {
            XCTAssertEqual(Recordings.voiceHash(text), hash, text)
        }
    }

    // wordRecording

    private func entry(_ audio: AudioMap?, forms: [String]? = nil) -> LexemeIndexEntry {
        return LexemeIndexEntry(gloss: "x", romanizationIsAuthored: false, forms: forms, audio: audio)
    }

    private var index: [String: LexemeIndexEntry] {
        return [
            "کتاب<n>": entry(["setareh": ["book.mp3"]]),
            "شیر<n><milk>": entry(["setareh": ["milk.mp3"]]),
            "شیر<n><lion>": entry(["setareh": ["lion.mp3"]]),
            "ـم<poss>": entry(["setareh": ["am.mp3"]], forms: ["\u{200C}ام"]),
            "نان<n>": entry(nil),
        ]
    }

    func testWordRecordingFindsTileBySpelling() {
        XCTAssertEqual(Recordings.wordRecording(text: "کتاب", exerciseTags: [], lexemeIndex: index, choice: noPreference), "book.mp3")
    }

    func testWordRecordingIgnoresReadingAids() {
        XCTAssertEqual(Recordings.wordRecording(text: "کِتاب", exerciseTags: [], lexemeIndex: index, choice: noPreference), "book.mp3")
    }

    func testWordRecordingPrefersTaggedSenseForHomograph() {
        XCTAssertEqual(Recordings.wordRecording(text: "شیر", exerciseTags: ["شیر<n><lion>"], lexemeIndex: index, choice: noPreference), "lion.mp3")
    }

    func testWordRecordingMatchesOtherWrittenForm() {
        XCTAssertEqual(Recordings.wordRecording(text: "\u{200C}ام", exerciseTags: [], lexemeIndex: index, choice: noPreference), "am.mp3")
    }

    func testWordRecordingNilForUnrecordedOrWordWithEndings() {
        XCTAssertNil(Recordings.wordRecording(text: "نان", exerciseTags: [], lexemeIndex: index, choice: noPreference))
        XCTAssertNil(Recordings.wordRecording(text: "کتابم", exerciseTags: [], lexemeIndex: index, choice: noPreference))
    }
}
