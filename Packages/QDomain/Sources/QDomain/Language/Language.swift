import Foundation
import QModel

public enum WritingDirection: String, Equatable, Sendable {
    case rtl
    case ltr
}

public struct LanguageInfo: Equatable, Sendable {
    /// The grader/content language, "fa" or "ja".
    public let language: String
    public let displayName: String
    public let direction: WritingDirection
    /// BCP-47 tag for speech.
    public let speechTag: String
    public let nativeName: String
    public let romanizedName: String
}

public enum KeyboardKind: String, Equatable, Sendable {
    case persianLayout = "persian-layout"
    case persianPhonetic = "persian-phonetic"
    case japanesePhonetic = "japanese-phonetic"
    case japaneseKana = "japanese-kana"
}

public enum FaInputMethod: Equatable, Sendable { case layout, phonetic }
public enum JaInputMethod: Equatable, Sendable { case phonetic, kana }

/// Course code -> language metadata. Port of web language.ts (Android shape).
public enum Languages {
    private static let courseLanguages: [String: LanguageInfo] = [
        "fa": LanguageInfo(language: "fa", displayName: "Persian", direction: .rtl,
                           speechTag: "fa-IR", nativeName: "فارسی", romanizedName: "Farsi"),
        "ja": LanguageInfo(language: "ja", displayName: "Japanese", direction: .ltr,
                           speechTag: "ja-JP", nativeName: "日本語", romanizedName: "Nihongo"),
    ]

    public static func languageInfo(_ courseCode: String?) -> LanguageInfo? {
        guard let code = courseCode else { return nil }
        return courseLanguages[code]
    }

    public static func isPersian(_ courseCode: String?) -> Bool {
        return languageInfo(courseCode)?.language == "fa"
    }

    public static func writingDirection(_ courseCode: String?) -> WritingDirection {
        return languageInfo(courseCode)?.direction ?? .ltr
    }

    private static func isArabicScript(_ v: UInt32) -> Bool {
        return (0x0600...0x06FF).contains(v) || (0x0750...0x077F).contains(v)
            || (0xFB50...0xFDFF).contains(v) || (0xFE70...0xFEFF).contains(v)
    }

    private static func isJapaneseScript(_ v: UInt32) -> Bool {
        return (0x3040...0x30FF).contains(v) || (0x3400...0x4DBF).contains(v)
            || (0x4E00...0x9FFF).contains(v)
    }

    /// Whether `text` is written in the course language's own script.
    public static func isNativeText(_ courseCode: String?, _ text: String) -> Bool {
        switch languageInfo(courseCode)?.language {
        case "fa": return text.unicodeScalars.contains { isArabicScript($0.value) }
        case "ja": return text.unicodeScalars.contains { isJapaneseScript($0.value) }
        default: return false
        }
    }

    /// BCP-47 tag to speak `text` in: the course tag if native script, else en-US; nil if language unknown.
    public static func speechLang(_ courseCode: String?, _ text: String) -> String? {
        guard let info = languageInfo(courseCode) else { return nil }
        return isNativeText(courseCode, text) ? info.speechTag : "en-US"
    }

    /// Direction of `text` from its own content (basic Arabic block only).
    public static func detectScriptDirection(_ text: String) -> WritingDirection {
        let hasArabic = text.unicodeScalars.contains { (0x0600...0x06FF).contains($0.value) }
        return hasArabic ? .rtl : .ltr
    }

    /// Which on-screen keyboard to show; nil when not native script or language unknown.
    public static func keyboardKind(_ courseCode: String?, scriptMode: ExerciseScriptMode,
                                    fa: FaInputMethod, ja: JaInputMethod) -> KeyboardKind? {
        if scriptMode != .native { return nil }
        switch languageInfo(courseCode)?.language {
        case "fa": return fa == .phonetic ? .persianPhonetic : .persianLayout
        case "ja": return ja == .kana ? .japaneseKana : .japanesePhonetic
        default: return nil
        }
    }
}
