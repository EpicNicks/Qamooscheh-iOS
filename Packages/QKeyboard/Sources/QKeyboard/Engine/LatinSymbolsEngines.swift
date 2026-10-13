import Foundation

/// Plain QWERTY, for a Latin mode.
public struct LatinEngine: ScriptKeyboardEngine {
    public private(set) var shift = false

    public init() {}

    public var layout: KeyboardLayout {
        var rows: [[Key]] = []
        for (index, row) in LatinRows.qwerty.enumerated() {
            let keys = row.map { c -> Key in
                let s = shift ? c.uppercased() : c
                return Key(label: s, action: .letter(s))
            }
            if index == 2 {
                rows.append([Key(label: "\u{21E7}", action: .shift, weight: 1.5, highlighted: shift)] + keys + [Key(label: "\u{232B}", action: .backspace, weight: 1.5)])
            } else {
                rows.append(keys)
            }
        }
        rows.append([Key(label: ",", action: .letter(",")), Key(label: "space", action: .space, weight: 5), Key(label: ".", action: .letter("."))])
        return KeyboardLayout(rows: rows)
    }

    public mutating func press(_ action: KeyAction, textBefore: String) -> Edit {
        switch action {
        case .letter(let output):
            let text = shift ? output.uppercased() : output
            shift = false
            return Edit(delete: 0, insert: text)
        case .space: return Edit(delete: 0, insert: " ")
        case .backspace: return Edit(delete: 1, insert: "")
        case .shift:
            shift.toggle()
            return .none
        default: return .none
        }
    }
}

/// Digits and punctuation, Latin and Persian.
public struct SymbolsEngine: ScriptKeyboardEngine {
    public private(set) var persianDigits = false

    public init() {}

    public var layout: KeyboardLayout {
        let digits = persianDigits ? "۱۲۳۴۵۶۷۸۹۰" : "1234567890"
        func row(_ chars: String) -> [Key] {
            chars.map { Key(label: String($0), action: .letter(String($0))) }
        }
        return KeyboardLayout(rows: [
            row(digits),
            row("@#&-+()/:\""),
            [Key(label: persianDigits ? "123" : "۱۲۳", action: .scriptToggle, weight: 1.5)] + row("،؛؟!?'«»") + [Key(label: "\u{232B}", action: .backspace, weight: 1.5)],
            [Key(label: ",", action: .letter(",")), Key(label: "space", action: .space, weight: 5), Key(label: ".", action: .letter("."))],
        ])
    }

    public mutating func press(_ action: KeyAction, textBefore: String) -> Edit {
        switch action {
        case .letter(let output): return Edit(delete: 0, insert: output)
        case .space: return Edit(delete: 0, insert: " ")
        case .backspace: return Edit(delete: 1, insert: "")
        case .scriptToggle:
            persianDigits.toggle()
            return .none
        default: return .none
        }
    }
}
