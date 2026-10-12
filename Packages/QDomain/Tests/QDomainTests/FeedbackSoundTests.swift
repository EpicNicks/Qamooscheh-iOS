import XCTest
@testable import QDomain

final class FeedbackSoundTests: XCTestCase {
    func testFileNames() {
        XCTAssertEqual(FeedbackSound.fileName(for: .correct), "sfx_correct")
        XCTAssertEqual(FeedbackSound.fileName(for: .incorrect), "sfx_incorrect")
        XCTAssertEqual(FeedbackSound.fileName(for: .lessonComplete), "sfx_complete")
        XCTAssertNil(FeedbackSound.fileName(for: .tilePlaced))
    }

    func testVolume() {
        XCTAssertEqual(FeedbackSound.volume, 0.6)
    }

    func testPlaysWhenEnabledAndQuiet() {
        XCTAssertTrue(FeedbackSound.shouldPlay(event: .correct, soundEnabled: true, isSpeaking: false))
    }

    func testSilentWhenDisabledSpeakingOrSoundless() {
        XCTAssertFalse(FeedbackSound.shouldPlay(event: .correct, soundEnabled: false, isSpeaking: false))
        XCTAssertFalse(FeedbackSound.shouldPlay(event: .correct, soundEnabled: true, isSpeaking: true))
        XCTAssertFalse(FeedbackSound.shouldPlay(event: .tilePlaced, soundEnabled: true, isSpeaking: false))
    }
}
