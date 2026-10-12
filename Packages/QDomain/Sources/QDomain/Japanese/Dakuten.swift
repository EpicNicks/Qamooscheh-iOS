import Foundation

private let dakutenTable: [String: String] = [
    "か": "が", "き": "ぎ", "く": "ぐ", "け": "げ", "こ": "ご",
    "さ": "ざ", "し": "じ", "す": "ず", "せ": "ぜ", "そ": "ぞ",
    "た": "だ", "ち": "ぢ", "つ": "づ", "て": "で", "と": "ど",
    "は": "ば", "ひ": "び", "ふ": "ぶ", "へ": "べ", "ほ": "ぼ",
]

private let handakutenTable: [String: String] = [
    "は": "ぱ", "ひ": "ぴ", "ふ": "ぷ", "へ": "ぺ", "ほ": "ぽ",
]

private func applyMark(_ table: [String: String], _ kana: String) -> String {
    let hira = toHiragana(kana)
    guard let marked = table[hira] else { return kana }
    return hira == kana ? marked : toKatakana(marked)
}

/// Voices the previously typed kana (script preserved); unchanged if it has no voiced form.
public func applyDakuten(_ kana: String) -> String {
    applyMark(dakutenTable, kana)
}

/// Adds the semi-voiced mark to a ha-row kana (script preserved); unchanged otherwise.
public func applyHandakuten(_ kana: String) -> String {
    applyMark(handakutenTable, kana)
}
