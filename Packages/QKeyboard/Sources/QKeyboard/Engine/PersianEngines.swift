import Foundation
import QDomain

/// The standard Persian ISIRI layout. In isolated mode each letter is followed by a ZWNJ so it
/// shows in its isolated form.
public struct PersianLayoutEngine: ScriptKeyboardEngine {
    public var isolated: Bool
    public private(set) var shift = false

    public init(isolated: Bool) {
        self.isolated = isolated
    }

    public var layout: KeyboardLayout {
        var rows: [[Key]] = []
        for (index, row) in IsiriLayout.rows.enumerated() {
            let keys: [Key] = row.map { key in
                var letter = key.letter
                if shift, let cp = IsiriLayout.shift[key.physicalCode], let scalar = Unicode.Scalar(cp) {
                    letter = String(Character(scalar))
                }
                return Key(label: letter, action: .letter(letter))
            }
            if index < 2 {
                rows.append(keys)
            } else {
                rows.append([Key(label: "\u{21E7}", action: .shift, weight: 1.3, highlighted: shift)] + keys + [Key(label: "\u{232B}", action: .backspace, weight: 1.3)])
            }
        }
        rows.append([Key(label: "\u{2322}", action: .zwnj, weight: 1.5), Key(label: "space", action: .space, weight: 5)])
        return KeyboardLayout(rows: rows)
    }

    public mutating func press(_ action: KeyAction, textBefore: String) -> Edit {
        switch action {
        case .letter(let output):
            shift = false
            return Edit(delete: 0, insert: output + (isolated ? "\u{200C}" : ""))
        case .space: return Edit(delete: 0, insert: " ")
        case .backspace: return Edit(delete: 1, insert: "")
        case .zwnj: return zwnjToggle(textBefore: textBefore)
        case .shift:
            shift.toggle()
            return .none
        default: return .none
        }
    }
}

/// Type Persian by sound on a QWERTY layout. The most likely letter goes in at once; when a sound
/// has several spellings the others are offered above the key, and the next key press commits.
public struct PersianPhoneticKeyboardEngine: ScriptKeyboardEngine {
    public private(set) var state = PersianPhoneticState.initial
    private var offered: [String]?

    public init() {}

    public var candidates: [String]? { offered }

    public var layout: KeyboardLayout {
        var rows: [[Key]] = []
        for (index, row) in LatinRows.qwerty.enumerated() {
            let keys = row.map { Key(label: $0, action: .letter($0), enabled: PersianPhoneticMap.hasPhoneticValue($0)) }
            if index == 2 {
                rows.append([Key(label: "'", action: .letter("'"))] + keys + [Key(label: "\u{232B}", action: .backspace, weight: 1.5)])
            } else {
                rows.append(keys)
            }
        }
        rows.append([Key(label: "\u{2322}", action: .zwnj, weight: 1.5), Key(label: "space", action: .space, weight: 5)])
        return KeyboardLayout(rows: rows, rtlCandidates: true)
    }

    public mutating func press(_ action: KeyAction, textBefore: String) -> Edit {
        switch action {
        case .letter(let output):
            guard output.count == 1, let char = output.first, PersianPhoneticMap.hasPhoneticValue(output) else { return .none }
            let step = PersianPhoneticEngine.feedLatinChar(state, char)
            state = step.state
            offered = step.candidates
            return Edit(delete: step.deleteCount, insert: step.insertText)
        case .space:
            let e = finalize()
            return Edit(delete: e.delete, insert: e.insert + " ")
        case .zwnj:
            _ = finalize()
            return zwnjToggle(textBefore: textBefore)
        case .backspace:
            // A digraph starter that has not produced a letter yet has nothing on screen to delete.
            var invisible = false
            if let prefix = state.bufferedPrefix.first {
                invisible = PersianPhoneticEngine.feedLatinChar(.initial, prefix).insertText.isEmpty
            }
            reset()
            return invisible ? .none : Edit(delete: 1, insert: "")
        default: return .none
        }
    }

    public mutating func pick(_ index: Int) -> Edit {
        guard let list = offered, list.indices.contains(index) else { return .none }
        let choice = list[index]
        reset()
        return Edit(delete: 1, insert: choice)
    }

    public mutating func finalize() -> Edit {
        let step = PersianPhoneticEngine.finalizeWord()
        state = step.state
        offered = nil
        return Edit(delete: step.deleteCount, insert: step.insertText)
    }

    private mutating func reset() {
        state = .initial
        offered = nil
    }
}
