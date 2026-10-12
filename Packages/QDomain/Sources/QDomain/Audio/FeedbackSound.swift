// Port of Android core/platform FeedbackEffects' pure parts (sound identifiers,
// file names, volume, suppression rule). No audio is bundled or played here;
// playback is native (item m7b).

/// What just happened, in lesson terms.
public enum FeedbackEvent: String, CaseIterable, Sendable {
    case correct
    case incorrect
    case tilePlaced
    case lessonComplete
}

public enum FeedbackSound {
    /// Base file name (no extension) of the sound for an event; nil when the event has no sound.
    public static func fileName(for event: FeedbackEvent) -> String? {
        switch event {
        case .correct: return "sfx_correct"
        case .incorrect: return "sfx_incorrect"
        case .lessonComplete: return "sfx_complete"
        case .tilePlaced: return nil
        }
    }

    /// Playback volume (0...1), as Android's SoundPool call.
    public static let volume: Float = 0.6

    /// Sounds stay quiet when disabled and never play over a prompt being read aloud.
    public static func shouldPlay(event: FeedbackEvent, soundEnabled: Bool, isSpeaking: Bool) -> Bool {
        return soundEnabled && !isSpeaking && fileName(for: event) != nil
    }
}
