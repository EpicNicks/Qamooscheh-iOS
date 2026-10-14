import Foundation
import QModel
import QData

// Pure helpers for the Settings screen (web GoalsSection/StudySection, Android SettingsScreen.kt).

/// Review-intensity presets. Any other value is "custom" and is never silently rewritten.
public struct RetentionPreset: Equatable, Sendable {
    public let value: Double
    public let label: String
    public let hint: String
}

public let retentionPresets: [RetentionPreset] = [
    RetentionPreset(value: 0.85, label: "Relaxed", hint: "Fewer reviews"),
    RetentionPreset(value: 0.9, label: "Balanced", hint: "FSRS's default"),
    RetentionPreset(value: 0.94, label: "Thorough", hint: "Forget less"),
]

public func matchRetentionPreset(_ value: Double) -> RetentionPreset? {
    return retentionPresets.first { abs($0.value - value) < 0.005 }
}

/// Slider output to a stored retention: whole percents.
public func snapRetention(_ value: Double) -> Double {
    return (value * 100).rounded() / 100
}

/// Text-size slider output: steps of 5 within 75...150.
public func snapFontPercent(_ value: Double) -> Int {
    let stepped = Int((value / 5).rounded()) * 5
    return min(150, max(75, stepped))
}

/// The custom daily-goal field keeps up to four ASCII digits.
public func sanitizedGoalInput(_ raw: String) -> String {
    let digits = raw.filter { "0123456789".contains($0) }
    return String(digits.prefix(4))
}

/// "For example: ..." under the text-mode toggle.
public func scriptModeSample(mode: ScriptMode, nativeName: String, romanizedName: String) -> String {
    switch mode {
    case .romanized: return romanizedName
    case .both: return "\(nativeName) (\(romanizedName))"
    default: return nativeName
    }
}

/// The Persian keyboard sample: joined, or broken apart by a ZWNJ after each letter.
public func keyboardSample(mode: KeyboardMode) -> String {
    let word = "\u{0633}\u{0644}\u{0627}\u{0645}"
    if mode == .isolated {
        return word.map { String($0) }.joined(separator: "\u{200C}")
    }
    return word
}

/// A labelled choice; `family` is the stored value (nil = default).
public struct FontChoice: Equatable, Sendable {
    public let label: String
    public let family: String?
}

/// Persian face choices. Vazirmatn is the only bundled face; a stored Noto Naskh pref falls back to it.
public let persianFontChoices: [FontChoice] = [
    FontChoice(label: "Default", family: nil),
    FontChoice(label: "Vazirmatn", family: "Vazirmatn"),
]

public let persianFlagChoices: [FontChoice] = [
    FontChoice(label: "Pahlavi", family: "pahlavi"),
    FontChoice(label: "Islamic Republic", family: "iri"),
]

/// What the screen says after Save.
public enum SettingsNotice: Equatable, Sendable {
    case saved
    case savedOffline
    case rejected(String)
    case failed(String)
}

public func settingsNotice(for outcome: PrefsSyncOutcome) -> SettingsNotice {
    switch outcome {
    case .synced:
        return .saved
    case .offline:
        return .savedOffline
    case .rejected(let status, _):
        return .rejected("The server didn't accept those settings (error \(status)). Your changes are still here; adjust them and save again.")
    }
}

/// Reminder controls (Android ReminderPrefs). Real scheduling is m7a; the screen only edits these.
public struct ReminderSettings: Equatable, Sendable {
    public var enabled = false
    public var hour = 19
    public var minute = 0
    /// ISO weekdays, 1 = Monday ... 7 = Sunday.
    public var days: Set<Int> = [1, 2, 3, 4, 5, 6, 7]
    public var smartSuppression = true
    public var streakNudge = true

    public init() {}
}

public let reminderDayLabels: [(day: Int, label: String)] = [
    (1, "Mon"), (2, "Tue"), (3, "Wed"), (4, "Thu"), (5, "Fri"), (6, "Sat"), (7, "Sun"),
]

/// Stub seam for m7a's real scheduler.
public protocol ReminderScheduling: AnyObject, Sendable {
    func current() -> ReminderSettings
    /// Asks for notification permission; true when granted.
    func requestPermission() async -> Bool
    func apply(_ settings: ReminderSettings)
}

/// Keeps reminder settings in memory only; nothing is scheduled.
public final class StubReminderScheduler: ReminderScheduling, @unchecked Sendable {
    private let lock = NSLock()
    private var settings = ReminderSettings()

    public init() {}

    public func current() -> ReminderSettings {
        lock.lock()
        defer { lock.unlock() }
        return settings
    }

    public func requestPermission() async -> Bool { true }

    public func apply(_ settings: ReminderSettings) {
        lock.lock()
        defer { lock.unlock() }
        self.settings = settings
    }
}

/// GET /v1/streak and the pause calls. The app wires this to QNetwork later.
public protocol StreakService: Sendable {
    func fetch() async throws -> StreakResponse
    func pause(_ request: StreakPauseRequest) async throws
    func cancelPause() async throws
}

/// A selectable course voice.
public struct SettingsVoice: Equatable, Sendable {
    public let id: String
    public let label: String
    /// A short phrase the Play button speaks; nil hides the button (Android hides it without a sample).
    public let sampleText: String?
    /// BCP-47 tag of the sample's language, e.g. "fa-IR".
    public let sampleLanguage: String?

    public init(id: String, label: String, sampleText: String? = nil, sampleLanguage: String? = nil) {
        self.id = id
        self.label = label
        self.sampleText = sampleText
        self.sampleLanguage = sampleLanguage
    }

    public var canPreview: Bool {
        guard let text = sampleText, let language = sampleLanguage else { return false }
        return !text.isEmpty && !language.isEmpty
    }
}

/// Plays a voice sample. Backed by SpeechService in the app; a stub in tests.
public protocol VoicePreviewing: AnyObject {
    /// Speaks `text` in `languageTag`; false when the device has no voice for it.
    func preview(text: String, languageTag: String) -> Bool
    func stop()
}

/// SpeechService behind VoicePreviewing.
public final class SpeechVoicePreviewer: VoicePreviewing {
    private let speech: SpeechService

    public init(speech: SpeechService) {
        self.speech = speech
    }

    public func preview(text: String, languageTag: String) -> Bool {
        return speech.speak(text, languageTag: languageTag)
    }

    public func stop() {
        speech.stop()
    }
}

private func utcDayFormatter() -> DateFormatter {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "UTC")
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter
}

/// A streak day ("yyyy-MM-dd") as midnight UTC, for the date picker.
public func streakDayDate(_ day: String) -> Date? {
    return utcDayFormatter().date(from: day)
}

public func streakDayString(_ date: Date) -> String {
    return utcDayFormatter().string(from: date)
}
