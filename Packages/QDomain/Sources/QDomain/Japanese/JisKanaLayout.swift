import Foundation

/// One kana key and the physical key it sits on, as a DOM `KeyboardEvent.code`, or nil when it has no US counterpart.
public struct JisKanaKey: Equatable, Sendable {
    public let kana: String
    public let physicalCode: String?

    public init(_ kana: String, _ physicalCode: String?) {
        self.kana = kana
        self.physicalCode = physicalCode
    }
}

public let jisKanaNumberRow: [JisKanaKey] = [
    JisKanaKey("ぬ", "Digit1"), JisKanaKey("ふ", "Digit2"), JisKanaKey("あ", "Digit3"), JisKanaKey("う", "Digit4"),
    JisKanaKey("え", "Digit5"), JisKanaKey("お", "Digit6"), JisKanaKey("や", "Digit7"), JisKanaKey("ゆ", "Digit8"),
    JisKanaKey("よ", "Digit9"), JisKanaKey("わ", "Digit0"), JisKanaKey("ほ", "Minus"), JisKanaKey("へ", "Equal"),
]

public let jisKanaRows: [[JisKanaKey]] = [
    [
        JisKanaKey("た", "KeyQ"), JisKanaKey("て", "KeyW"), JisKanaKey("い", "KeyE"), JisKanaKey("す", "KeyR"),
        JisKanaKey("か", "KeyT"), JisKanaKey("ん", "KeyY"), JisKanaKey("な", "KeyU"), JisKanaKey("に", "KeyI"),
        JisKanaKey("ら", "KeyO"), JisKanaKey("せ", "KeyP"), JisKanaKey("ー", "Backslash"),
    ],
    [
        JisKanaKey("ち", "KeyA"), JisKanaKey("と", "KeyS"), JisKanaKey("し", "KeyD"), JisKanaKey("は", "KeyF"),
        JisKanaKey("き", "KeyG"), JisKanaKey("く", "KeyH"), JisKanaKey("ま", "KeyJ"), JisKanaKey("の", "KeyK"),
        JisKanaKey("り", "KeyL"), JisKanaKey("れ", "Semicolon"), JisKanaKey("け", "Quote"), JisKanaKey("む", "BracketLeft"),
    ],
    [
        JisKanaKey("つ", "KeyZ"), JisKanaKey("さ", "KeyX"), JisKanaKey("そ", "KeyC"), JisKanaKey("ひ", "KeyV"),
        JisKanaKey("こ", "KeyB"), JisKanaKey("み", "KeyN"), JisKanaKey("も", "KeyM"), JisKanaKey("ね", "Comma"),
        JisKanaKey("る", "Period"), JisKanaKey("め", "Slash"), JisKanaKey("ろ", nil),
    ],
]

/// The wo kana has no US-layout key of its own (real JIS position is Shift+0): tap-only.
public let jisKanaWo: String = "を"

private func charForPhysicalCode(_ code: String) -> Character? {
    if code.hasPrefix("Key"), code.count == 4, let c = code.last, c >= "A", c <= "Z" {
        return Character(String(c).lowercased())
    }
    if code.hasPrefix("Digit"), code.count == 6, let c = code.last, c >= "0", c <= "9" {
        return c
    }
    switch code {
    case "Minus": return "-"
    case "Equal": return "="
    case "Backslash": return "\\"
    default: return nil
    }
}

/// US key character -> kana at the same physical JIS position. Only letter, digit, Minus, Equal and Backslash codes resolve (as on web and Android).
public let physicalCharToKana: [Character: String] = {
    var map: [Character: String] = [:]
    for row in [jisKanaNumberRow] + jisKanaRows {
        for key in row {
            guard let code = key.physicalCode, let ch = charForPhysicalCode(code) else { continue }
            map[ch] = key.kana
        }
    }
    return map
}()
