import XCTest
import QDomain
@testable import QFeatures

private final class SpyHaptics: HapticsPlaying {
    var played: [HapticKind] = []
    func play(_ kind: HapticKind) { played.append(kind) }
}

private final class SpySfx: SfxPlaying {
    var played: [(String, Float)] = []
    func play(fileName: String, volume: Float) { played.append((fileName, volume)) }
}

final class FeedbackEffectsTests: XCTestCase {
    private func make() -> (FeedbackEffects, SpyHaptics, SpySfx) {
        let h = SpyHaptics()
        let s = SpySfx()
        return (FeedbackEffects(haptics: h, sfx: s), h, s)
    }

    func testPlanMapping() {
        XCTAssertEqual(FeedbackPlan.haptic(for: .correct, reduceMotion: false), .success)
        XCTAssertEqual(FeedbackPlan.haptic(for: .incorrect, reduceMotion: false), .error)
        XCTAssertEqual(FeedbackPlan.haptic(for: .tilePlaced, reduceMotion: false), .tick)
        XCTAssertEqual(FeedbackPlan.haptic(for: .lessonComplete, reduceMotion: false), .celebrate)
    }

    func testReduceMotionSoftensHaptics() {
        XCTAssertNil(FeedbackPlan.haptic(for: .tilePlaced, reduceMotion: true))
        XCTAssertEqual(FeedbackPlan.haptic(for: .lessonComplete, reduceMotion: true), .success)
        XCTAssertEqual(FeedbackPlan.haptic(for: .correct, reduceMotion: true), .success)
    }

    func testCorrectPlaysHapticAndSound() {
        let (fx, h, s) = make()
        fx.perform(.correct, hapticsEnabled: true, soundEnabled: true, isSpeaking: false, reduceMotion: false)
        XCTAssertEqual(h.played, [.success])
        XCTAssertEqual(s.played.count, 1)
        XCTAssertEqual(s.played.first?.0, "sfx_correct")
        XCTAssertEqual(s.played.first?.1, 0.6)
    }

    func testCompleteUsesCompleteSound() {
        let (fx, h, s) = make()
        fx.perform(.lessonComplete, hapticsEnabled: true, soundEnabled: true, isSpeaking: false, reduceMotion: false)
        XCTAssertEqual(h.played, [.celebrate])
        XCTAssertEqual(s.played.first?.0, "sfx_complete")
    }

    func testTilePlacedHasNoSound() {
        let (fx, h, s) = make()
        fx.perform(.tilePlaced, hapticsEnabled: true, soundEnabled: true, isSpeaking: false, reduceMotion: false)
        XCTAssertEqual(h.played, [.tick])
        XCTAssertTrue(s.played.isEmpty)
    }

    func testTogglesAndSpeakingGate() {
        let (fx, h, s) = make()
        fx.perform(.incorrect, hapticsEnabled: false, soundEnabled: false, isSpeaking: false, reduceMotion: false)
        XCTAssertTrue(h.played.isEmpty)
        XCTAssertTrue(s.played.isEmpty)
        fx.perform(.incorrect, hapticsEnabled: true, soundEnabled: true, isSpeaking: true, reduceMotion: false)
        XCTAssertEqual(h.played, [.error])
        XCTAssertTrue(s.played.isEmpty)
    }
}
