import XCTest
@testable import QModel

final class SlowAudioDecodeTests: XCTestCase {
    private func exercise(_ extra: String) throws -> ExerciseArtifact {
        let json = "{\"type\":\"type_in\",\"scriptMode\":\"native\",\"prompt\":\"p\",\"answer\":[\"a\"],\"promptAudio\":{\"sara\":[\"a.mp3\"]}\(extra)}"
        return try JSONDecoder().decode(ExerciseArtifact.self, from: Data(json.utf8))
    }

    func testExerciseSlowAudioDecodes() throws {
        let decoded = try exercise(",\"promptSlowAudio\":{\"sara\":\"a-slow.mp3\"},\"answerSlowAudio\":null")
        XCTAssertEqual(decoded.promptSlowAudio, ["sara": "a-slow.mp3"])
        XCTAssertNil(decoded.answerSlowAudio)
    }

    func testOlderExerciseWithoutTheFieldsStillDecodes() throws {
        let decoded = try exercise("")
        XCTAssertNil(decoded.promptSlowAudio)
        XCTAssertNil(decoded.answerSlowAudio)
    }

    func testLexemeSlowAudioIsOptional() throws {
        let with = try JSONDecoder().decode(LexemeIndexEntry.self, from: Data(
            "{\"gloss\":\"g\",\"romanizationIsAuthored\":false,\"audio\":{\"sara\":[\"a.mp3\"]},\"slowAudio\":{\"sara\":\"a-slow.mp3\"}}".utf8))
        XCTAssertEqual(with.slowAudio, ["sara": "a-slow.mp3"])
        let without = try JSONDecoder().decode(LexemeIndexEntry.self, from: Data("{\"gloss\":\"g\",\"romanizationIsAuthored\":false}".utf8))
        XCTAssertNil(without.slowAudio)
    }

    func testAudioIndexPhraseSlowFlagIsOptional() throws {
        let data = Data("{\"phrases\":[{\"text\":\"t\",\"voice\":\"sara\",\"path\":\"a.mp3\",\"take\":1},{\"text\":\"t\",\"voice\":\"sara\",\"path\":\"s.mp3\",\"slow\":true}]}".utf8)
        let index = try JSONDecoder().decode(AudioIndexArtifact.self, from: data)
        XCTAssertNil(index.phrases[0].slow)
        XCTAssertEqual(index.phrases[1].slow, true)
    }
}
