import Foundation
import QDomain

/// Haptic patterns, mirroring Android's CONFIRM / REJECT / CLOCK_TICK / composed flourish.
public enum HapticKind: Equatable, Sendable {
    case success
    case error
    case tick
    case celebrate
}

public protocol HapticsPlaying: AnyObject {
    func play(_ kind: HapticKind)
}

public protocol SfxPlaying: AnyObject {
    /// Plays the bundled sound with this base name. Silently does nothing when the asset is missing.
    func play(fileName: String, volume: Float)
}

/// Pure event-to-feedback mapping.
public enum FeedbackPlan {
    public static func haptic(for event: FeedbackEvent, reduceMotion: Bool) -> HapticKind? {
        switch event {
        case .correct: return .success
        case .incorrect: return .error
        case .tilePlaced: return reduceMotion ? nil : .tick
        case .lessonComplete: return reduceMotion ? .success : .celebrate
        }
    }
}

/// Lessons emit semantic events; this decides how they feel and sound (Android FeedbackEffects).
public final class FeedbackEffects {
    private let haptics: HapticsPlaying
    private let sfx: SfxPlaying

    public init(haptics: HapticsPlaying, sfx: SfxPlaying) {
        self.haptics = haptics
        self.sfx = sfx
    }

    public func perform(
        _ event: FeedbackEvent,
        hapticsEnabled: Bool,
        soundEnabled: Bool,
        isSpeaking: Bool,
        reduceMotion: Bool
    ) {
        if hapticsEnabled, let kind = FeedbackPlan.haptic(for: event, reduceMotion: reduceMotion) {
            haptics.play(kind)
        }
        if FeedbackSound.shouldPlay(event: event, soundEnabled: soundEnabled, isSpeaking: isSpeaking),
           let name = FeedbackSound.fileName(for: event) {
            sfx.play(fileName: name, volume: FeedbackSound.volume)
        }
    }
}
