import Foundation

public enum KanaScript: Sendable {
    case hiragana
    case katakana
}

private func shiftScalars(_ text: String, from range: ClosedRange<UInt32>, by delta: Int) -> String {
    var out = String.UnicodeScalarView()
    for scalar in text.unicodeScalars {
        if range.contains(scalar.value), let shifted = Unicode.Scalar(UInt32(Int(scalar.value) + delta)) {
            out.append(shifted)
        } else {
            out.append(scalar)
        }
    }
    return String(out)
}

/// Hiragana (U+3041...U+3096) to katakana, 0x60 code points apart. Everything else passes through.
public func toKatakana(_ text: String) -> String {
    shiftScalars(text, from: 0x3041...0x3096, by: 0x60)
}

/// Katakana (U+30A1...U+30F6) to hiragana. Everything else passes through.
public func toHiragana(_ text: String) -> String {
    shiftScalars(text, from: 0x30A1...0x30F6, by: -0x60)
}

public func convertKanaScript(_ text: String, script: KanaScript) -> String {
    switch script {
    case .katakana: return toKatakana(text)
    case .hiragana: return toHiragana(text)
    }
}
