import Foundation

/// Which Persian letter(s) a Latin sound maps to, ordered by frequency
/// (index 0 is the default, auto-picked candidate). Port of web phoneticMap.ts.
public enum PersianPhoneticMap {
    /// Digraphs are matched before their single-letter prefix would resolve.
    public static let digraphs: [String: [String]] = [
        "kh": ["خ"],
        "gh": ["غ", "ق"],
        "ch": ["چ"],
        "sh": ["ش"],
        "zh": ["ژ"],
    ]

    /// First letters of every digraph above.
    public static let digraphStarters: Set<String> = ["k", "g", "c", "s", "z"]

    public static let singles: [String: [String]] = [
        "a": ["ا", "آ"],
        "e": ["ا", "آ"],
        "i": ["ی"],
        "o": ["و"],
        "u": ["و"],
        "b": ["ب"],
        "p": ["پ"],
        "t": ["ت", "ط"],
        "s": ["س", "ص", "ث"],
        "j": ["ج"],
        "h": ["ه", "ح"],
        "d": ["د"],
        "z": ["ز", "ذ", "ض", "ظ"],
        "r": ["ر"],
        "f": ["ف"],
        "k": ["ک"],
        "g": ["گ"],
        "l": ["ل"],
        "m": ["م"],
        "n": ["ن"],
        "v": ["و"],
        "w": ["و"],
        "x": ["خ"],
        "y": ["ی"],
        "q": ["ق", "غ"],
        "'": ["ع", "ء"],
    ]

    /// Looks up an already-resolved trigger (a full digraph or a single letter).
    public static func resolveTrigger(_ sound: String) -> [String]? {
        return digraphs[sound] ?? singles[sound]
    }

    /// Every Latin character the phonetic keyboard does something with ("c" included).
    public static let validPhoneticLetters: Set<String> =
        Set(singles.keys).union(digraphStarters)

    public static func hasPhoneticValue(_ letter: String) -> Bool {
        return validPhoneticLetters.contains(letter.lowercased())
    }
}
