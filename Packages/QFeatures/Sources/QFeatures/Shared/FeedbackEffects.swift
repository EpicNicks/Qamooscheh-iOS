import Foundation
import QData
import QDomain
#if canImport(UIKit) && !os(watchOS)
import UIKit
#endif

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

public extension FeedbackEffects {
    /// The one player for the app: sound and haptics are device-wide.
    static let shared = FeedbackEffects(haptics: SystemHaptics(), sfx: SystemSfx())

    /// Plays `event` as the learner's device prefs allow; the sound is skipped while a voice is speaking.
    func play(_ event: FeedbackEvent, prefs: LocalPrefs, isSpeaking: Bool = false) {
        perform(event, hapticsEnabled: prefs.hapticsEnabled, soundEnabled: prefs.soundEffectsEnabled, isSpeaking: isSpeaking, reduceMotion: FeedbackEffects.reduceMotion)
    }

    private static var reduceMotion: Bool {
        #if canImport(UIKit) && !os(watchOS)
        return UIAccessibility.isReduceMotionEnabled
        #else
        return false
        #endif
    }
}
