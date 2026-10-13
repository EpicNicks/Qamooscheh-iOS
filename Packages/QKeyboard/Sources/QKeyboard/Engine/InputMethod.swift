import Foundation

/// Which engine a field uses: phonetic (Latin keys, sound-based) or native layout, per script.
public enum InputMethod: Equatable, Sendable {
    case persianPhonetic
    case persianLayout(isolated: Bool)
    case japaneseRomaji
    case japaneseKana
    case latin
    case symbols

    public func makeEngine() -> any ScriptKeyboardEngine {
        switch self {
        case .persianPhonetic: return PersianPhoneticKeyboardEngine()
        case .persianLayout(let isolated): return PersianLayoutEngine(isolated: isolated)
        case .japaneseRomaji: return JapaneseRomajiEngine()
        case .japaneseKana: return JapaneseKanaEngine()
        case .latin: return LatinEngine()
        case .symbols: return SymbolsEngine()
        }
    }

    /// The phonetic/native toggle within a script; other methods are unchanged.
    public var toggledLayout: InputMethod {
        switch self {
        case .persianPhonetic: return .persianLayout(isolated: false)
        case .persianLayout: return .persianPhonetic
        case .japaneseRomaji: return .japaneseKana
        case .japaneseKana: return .japaneseRomaji
        default: return self
        }
    }
}

/// An engine plus the text it is editing: the input-state machine (key, composing buffer,
/// candidates, commit/backspace). Hosts with their own text storage use the engine directly.
public struct KeyboardInputSession {
    public private(set) var engine: any ScriptKeyboardEngine
    public private(set) var text: String

    public init(method: InputMethod, text: String = "") {
        self.engine = method.makeEngine()
        self.text = text
    }

    public var layout: KeyboardLayout { engine.layout }
    public var candidates: [String]? { engine.candidates }
    public var pending: String? { engine.pending }

    public mutating func press(_ action: KeyAction) {
        let edit = engine.press(action, textBefore: text)
        text = edit.applyTo(text)
    }

    public mutating func type(_ letter: String) {
        press(.letter(letter))
    }

    public mutating func pick(_ index: Int) {
        let edit = engine.pick(index)
        text = edit.applyTo(text)
    }

    public mutating func finalize() {
        let edit = engine.finalize()
        text = edit.applyTo(text)
    }

    /// Switches method, committing anything pending first; the text is kept.
    public mutating func switchMethod(_ method: InputMethod) {
        finalize()
        engine = method.makeEngine()
    }
}
