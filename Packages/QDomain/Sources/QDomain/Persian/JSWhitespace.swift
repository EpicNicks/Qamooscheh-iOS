import Foundation

/// JavaScript's `\s` class, exactly (it differs from Unicode White_Space: it
/// includes U+FEFF and excludes U+0085). Keeps ports of the web string logic
/// splitting text where the web does.
func isJSWhitespace(_ s: Unicode.Scalar) -> Bool {
    switch s.value {
    case 0x09...0x0D, 0x20, 0xA0, 0x1680, 0x2000...0x200A, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF:
        return true
    default:
        return false
    }
}
