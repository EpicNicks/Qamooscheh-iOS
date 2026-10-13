import Foundation

public enum PersianInputMethod: String, Codable, Equatable, Sendable, CaseIterable {
    case layout
    case phonetic
}

public enum JapaneseInputMethod: String, Codable, Equatable, Sendable, CaseIterable {
    case kana
    case romaji
}

public enum NativeTextAlign: String, Codable, Equatable, Sendable, CaseIterable {
    case start
    case center
}

/// One script's font choice: a family name (nil = default) and a size percentage.
public struct ScriptFontPref: Codable, Equatable, Sendable {
    public var family: String?
    public var sizePct: Int

    public init(family: String? = nil, sizePct: Int = 100) {
        self.family = family
        self.sizePct = sizePct
    }
}

/// Prefs that describe this device, not the account (web localAppPrefs.ts,
/// Android LocalPrefs), stored per user. Defaults follow Android where it
/// differs from the web. Decoding tolerates missing or malformed keys (a blob
/// written by an older build keeps working): each falls back to its default.
public struct LocalPrefs: Codable, Equatable, Sendable {
    public var suppressSkipWarning = false
    public var persianInputMethod: PersianInputMethod = .phonetic
    public var japaneseInputMethod: JapaneseInputMethod = .romaji
    public var deviceInputEnabled = false
    public var showFurigana = true
    public var showRomanizationHints = true
    public var showTranslationHints = true
    public var showNativeHints = true
    public var showVowelMarks = true
    public var showSentenceRomanization = true
    public var nativeTextAlign: NativeTextAlign = .start
    /// Exercise types whose first-time overlay has been seen.
    public var seenLessonOverlay: Set<String> = []
    public var lastGoalCelebrationDay: String?
    public var goalCelebrationEnabled = true
    public var smoulderingStreak = true
    public var fontFa = ScriptFontPref()
    public var fontJa = ScriptFontPref()
    public var fontLatin = ScriptFontPref()
    /// "pahlavi" or "iri".
    public var persianFlag = "pahlavi"
    public var speakWordBankTiles = true
    public var speakAnswers = true
    public var shuffleVoices = true
    public var hapticsEnabled = true
    public var soundEffectsEnabled = true
    public var lessonsCompleted = 0
    public var reviewPromptShown = false
    public var notificationPermissionAsked = false

    public init() {}

    enum CodingKeys: String, CodingKey {
        case suppressSkipWarning, persianInputMethod, japaneseInputMethod, deviceInputEnabled
        case showFurigana, showRomanizationHints, showTranslationHints, showNativeHints
        case showVowelMarks, showSentenceRomanization, nativeTextAlign, seenLessonOverlay
        case lastGoalCelebrationDay, goalCelebrationEnabled, smoulderingStreak
        case fontFa, fontJa, fontLatin, persianFlag, speakWordBankTiles, speakAnswers
        case shuffleVoices, hapticsEnabled, soundEffectsEnabled, lessonsCompleted
        case reviewPromptShown, notificationPermissionAsked
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            ((try? c.decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback
        }
        let d = LocalPrefs()
        suppressSkipWarning = value(.suppressSkipWarning, d.suppressSkipWarning)
        persianInputMethod = value(.persianInputMethod, d.persianInputMethod)
        japaneseInputMethod = value(.japaneseInputMethod, d.japaneseInputMethod)
        deviceInputEnabled = value(.deviceInputEnabled, d.deviceInputEnabled)
        showFurigana = value(.showFurigana, d.showFurigana)
        showRomanizationHints = value(.showRomanizationHints, d.showRomanizationHints)
        showTranslationHints = value(.showTranslationHints, d.showTranslationHints)
        showNativeHints = value(.showNativeHints, d.showNativeHints)
        showVowelMarks = value(.showVowelMarks, d.showVowelMarks)
        showSentenceRomanization = value(.showSentenceRomanization, d.showSentenceRomanization)
        nativeTextAlign = value(.nativeTextAlign, d.nativeTextAlign)
        seenLessonOverlay = value(.seenLessonOverlay, d.seenLessonOverlay)
        lastGoalCelebrationDay = value(.lastGoalCelebrationDay, d.lastGoalCelebrationDay)
        goalCelebrationEnabled = value(.goalCelebrationEnabled, d.goalCelebrationEnabled)
        smoulderingStreak = value(.smoulderingStreak, d.smoulderingStreak)
        fontFa = value(.fontFa, d.fontFa)
        fontJa = value(.fontJa, d.fontJa)
        fontLatin = value(.fontLatin, d.fontLatin)
        persianFlag = value(.persianFlag, d.persianFlag)
        speakWordBankTiles = value(.speakWordBankTiles, d.speakWordBankTiles)
        speakAnswers = value(.speakAnswers, d.speakAnswers)
        shuffleVoices = value(.shuffleVoices, d.shuffleVoices)
        hapticsEnabled = value(.hapticsEnabled, d.hapticsEnabled)
        soundEffectsEnabled = value(.soundEffectsEnabled, d.soundEffectsEnabled)
        lessonsCompleted = value(.lessonsCompleted, d.lessonsCompleted)
        reviewPromptShown = value(.reviewPromptShown, d.reviewPromptShown)
        notificationPermissionAsked = value(.notificationPermissionAsked, d.notificationPermissionAsked)
    }
}

/// Per-user, device-only prefs in UserDefaults (inject a suite for tests).
/// Never sent to the server.
public final class LocalPrefsStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let lock = NSLock()

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The user's prefs; defaults when never set or the stored blob is unreadable.
    public func current(userId: String) -> LocalPrefs {
        lock.lock()
        defer { lock.unlock() }
        return read(userId)
    }

    /// Applies `change` to the stored prefs atomically and returns the result.
    @discardableResult
    public func update(userId: String, _ change: (inout LocalPrefs) -> Void) -> LocalPrefs {
        lock.lock()
        defer { lock.unlock() }
        var prefs = read(userId)
        change(&prefs)
        if let data = try? JSONEncoder().encode(prefs) {
            defaults.set(data, forKey: key(userId))
        }
        return prefs
    }

    /// Sign-out cleanup.
    public func clear(userId: String) {
        lock.lock()
        defer { lock.unlock() }
        defaults.removeObject(forKey: key(userId))
    }

    private func read(_ userId: String) -> LocalPrefs {
        guard let data = defaults.data(forKey: key(userId)),
              let prefs = try? JSONDecoder().decode(LocalPrefs.self, from: data) else { return LocalPrefs() }
        return prefs
    }

    private func key(_ userId: String) -> String { "qamooscheh.localPrefs.\(userId)" }
}
