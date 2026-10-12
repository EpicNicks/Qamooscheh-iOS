import Foundation

/// One letter key: the Persian letter's code point and the physical key it sits on
/// (DOM `KeyboardEvent.code` style: "KeyQ", "BracketLeft", ...).
public struct IsiriKey: Equatable, Sendable {
    public let codePoint: UInt32
    public let physicalCode: String

    public init(_ codePoint: UInt32, _ physicalCode: String) {
        self.codePoint = codePoint
        self.physicalCode = physicalCode
    }

    public var letter: String {
        guard let scalar = Unicode.Scalar(codePoint) else { return "" }
        return String(Character(scalar))
    }
}

/// ISIRI standard-layout letter placement. Port of web isiriLayout.ts.
public enum IsiriLayout {
    public static let rows: [[IsiriKey]] = [
        [
            IsiriKey(0x0636, "KeyQ"),
            IsiriKey(0x0635, "KeyW"),
            IsiriKey(0x062b, "KeyE"),
            IsiriKey(0x0642, "KeyR"),
            IsiriKey(0x0641, "KeyT"),
            IsiriKey(0x063a, "KeyY"),
            IsiriKey(0x0639, "KeyU"),
            IsiriKey(0x0647, "KeyI"),
            IsiriKey(0x062e, "KeyO"),
            IsiriKey(0x062d, "KeyP"),
            IsiriKey(0x062c, "BracketLeft"),
            IsiriKey(0x0686, "BracketRight"),
        ],
        [
            IsiriKey(0x0634, "KeyA"),
            IsiriKey(0x0633, "KeyS"),
            IsiriKey(0x06cc, "KeyD"),
            IsiriKey(0x0628, "KeyF"),
            IsiriKey(0x0644, "KeyG"),
            IsiriKey(0x0627, "KeyH"),
            IsiriKey(0x062a, "KeyJ"),
            IsiriKey(0x0646, "KeyK"),
            IsiriKey(0x0645, "KeyL"),
            IsiriKey(0x06a9, "Semicolon"),
            IsiriKey(0x06af, "Quote"),
        ],
        [
            IsiriKey(0x0638, "KeyZ"),
            IsiriKey(0x0637, "KeyX"),
            IsiriKey(0x0632, "KeyC"),
            IsiriKey(0x0631, "KeyV"),
            IsiriKey(0x0630, "KeyB"),
            IsiriKey(0x062f, "KeyN"),
            IsiriKey(0x067e, "KeyM"),
            IsiriKey(0x0648, "Comma"),
            IsiriKey(0x0698, "Period"),
        ],
    ]

    private static let punctuationCodeChar: [String: Character] = [
        "BracketLeft": "[",
        "BracketRight": "]",
        "Semicolon": ";",
        "Quote": "'",
        "Comma": ",",
        "Period": ".",
    ]

    /// The on-screen keyboard's virtual-only Shift layer (physical code -> code point).
    public static let shift: [String: UInt32] = [
        "KeyH": 0x0622,
        "KeyA": 0x0624,
        "KeyS": 0x0626,
        "KeyM": 0x0621,
    ]

    /// "KeyQ" / "BracketLeft" -> the character a US keyboard sends for it.
    static func defaultChar(forPhysicalCode code: String) -> Character? {
        if code.hasPrefix("Key"), code.count == 4, let last = code.last,
           last.isASCII, last.isUppercase {
            return Character(last.lowercased())
        }
        return punctuationCodeChar[code]
    }

    /// US key character -> the Persian letter at the same physical position.
    public static let physicalKeyToIsiri: [Character: String] = {
        var map: [Character: String] = [:]
        for row in rows {
            for key in row {
                if let char = defaultChar(forPhysicalCode: key.physicalCode) {
                    map[char] = key.letter
                }
            }
        }
        return map
    }()
}
