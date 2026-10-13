import Foundation
import QDomain

private let smallKanaMap: [String: String] = [
    "つ": "っ", "や": "ゃ", "ゆ": "ゅ", "よ": "ょ",
    "あ": "ぁ", "い": "ぃ", "う": "ぅ", "え": "ぇ", "お": "ぉ",
]

/// The JIS kana layout: voicing marks change the last kana, "small" types ゃ っ and so on, and a
/// toggle switches between hiragana and katakana.
public struct JapaneseKanaEngine: ScriptKeyboardEngine {
    public private(set) var script: KanaScript = .hiragana
    public private(set) var small = false

    public init() {}

    private func display(_ kana: String) -> String {
        convertKanaScript(kana, script: script)
    }

    public var layout: KeyboardLayout {
        func keyFor(_ kana: String) -> Key {
            let base = small ? (smallKanaMap[kana] ?? kana) : kana
            return Key(label: display(base), action: .letter(base))
        }
        var rows: [[Key]] = [jisKanaNumberRow.map { keyFor($0.kana) }]
        rows.append(contentsOf: jisKanaRows.map { row in row.map { keyFor($0.kana) } })
        rows.append([
            keyFor(jisKanaWo),
            Key(label: "\u{309B}", action: .dakuten),
            Key(label: "\u{309C}", action: .handakuten),
            Key(label: small ? "small \u{2713}" : "small", action: .smallKana, weight: 1.6, highlighted: small),
            Key(label: script == .hiragana ? "カタカナ" : "ひらがな", action: .scriptToggle, weight: 1.8),
            Key(label: "\u{232B}", action: .backspace, weight: 1.3),
        ])
        rows.append([Key(label: "space", action: .space, weight: 5)])
        return KeyboardLayout(rows: rows)
    }

    public mutating func press(_ action: KeyAction, textBefore: String) -> Edit {
        switch action {
        case .letter(let output):
            small = false
            return Edit(delete: 0, insert: display(output))
        case .space: return Edit(delete: 0, insert: " ")
        case .backspace: return Edit(delete: 1, insert: "")
        case .dakuten: return replaceLast(textBefore, applyDakuten)
        case .handakuten: return replaceLast(textBefore, applyHandakuten)
        case .smallKana:
            small.toggle()
            return .none
        case .scriptToggle:
            script = (script == .hiragana) ? .katakana : .hiragana
            return .none
        default: return .none
        }
    }

    private func replaceLast(_ textBefore: String, _ mark: (String) -> String) -> Edit {
        guard let last = lastScalarString(textBefore) else { return .none }
        let marked = mark(last)
        return marked == last ? .none : Edit(delete: 1, insert: marked)
    }
}

/// Romaji typed and turned into kana as you go.
public struct JapaneseRomajiEngine: ScriptKeyboardEngine {
    public private(set) var state = JapanesePhoneticState.initial

    public init() {}

    public var pending: String? {
        let b = state.buffer
        return (b.isEmpty || b == "n") ? nil : b
    }

    public var layout: KeyboardLayout {
        var rows: [[Key]] = []
        for (index, row) in LatinRows.qwerty.enumerated() {
            let keys = row.map { Key(label: $0, action: .letter($0)) }
            rows.append(index == 2 ? keys + [Key(label: "\u{232B}", action: .backspace, weight: 1.5)] : keys)
        }
        rows.append([Key(label: "-", action: .letter("-")), Key(label: "space", action: .space, weight: 5)])
        return KeyboardLayout(rows: rows)
    }

    public mutating func press(_ action: KeyAction, textBefore: String) -> Edit {
        switch action {
        case .letter(let output):
            guard output.count == 1, let char = output.first else { return .none }
            let step = feedRomajiChar(state, char)
            state = step.state
            return Edit(delete: step.deleteCount, insert: step.insertText)
        case .space:
            let e = finalize()
            return Edit(delete: e.delete, insert: e.insert + " ")
        case .backspace:
            // A consonant buffer is not in the text yet, so clearing it is the whole backspace;
            // a lone "n" already has its placeholder in the text, which goes like any character.
            let invisible = !state.buffer.isEmpty && state.buffer != "n"
            state = .initial
            return invisible ? .none : Edit(delete: 1, insert: "")
        default: return .none
        }
    }

    public mutating func finalize() -> Edit {
        let step = finalizeRomaji(state)
        state = step.state
        return Edit(delete: step.deleteCount, insert: step.insertText)
    }
}
