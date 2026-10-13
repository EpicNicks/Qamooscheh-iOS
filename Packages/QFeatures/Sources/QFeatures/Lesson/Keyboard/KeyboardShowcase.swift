import SwiftUI
import QKeyboard
import QDesign

public enum KeyboardShowcaseScenario: Sendable {
    case persianNative
    case persianPhonetic
    case kana
    case kanaDakuten
}

/// Gallery for snapshot tests: an answer line with the virtual caret above the keyboard,
/// pre-driven to a scenario by pressing real keys through the engine.
public struct KeyboardShowcase: View {
    private let state: KeyboardState
    private let text: String

    @Environment(\.colorScheme) private var colorScheme

    public init(_ scenario: KeyboardShowcaseScenario) {
        let method: InputMethod
        switch scenario {
        case .persianNative: method = .persianLayout(isolated: false)
        case .persianPhonetic: method = .persianPhonetic
        case .kana, .kanaDakuten: method = .japaneseKana
        }
        let state = KeyboardState(method: method)
        var text = ""
        func press(_ label: String) {
            guard let id = KeyboardShowcase.keyId(state, label: label) else { return }
            let layout = state.layout
            let parts = id.split(separator: ":").compactMap { Int($0) }
            guard parts.count == 2 else { return }
            let key = layout.rows[parts[0]][parts[1]]
            text = state.press(key.action, keyId: id, textBefore: text).applyTo(text)
        }
        switch scenario {
        case .persianNative: press("س"); press("ل"); press("ا"); press("م")
        case .persianPhonetic: press("s")
        case .kana: press("か"); press("な")
        case .kanaDakuten: press("か"); press("\u{309B}")
        }
        self.state = state
        self.text = text
    }

    static func keyId(_ state: KeyboardState, label: String) -> String? {
        let rows = state.layout.rows
        for r in 0..<rows.count {
            for i in 0..<rows[r].count where rows[r][i].label == label {
                return KeyboardState.keyId(row: r, index: i)
            }
        }
        return nil
    }

    public var body: some View {
        let p = colorScheme == .dark ? AppPalette.dark : AppPalette.light
        VStack(spacing: 0) {
            HStack(spacing: 2) {
                Text(text)
                    .font(.system(size: 28))
                    .foregroundColor(Color(argb: p.text))
                VirtualCaret(palette: p, blinks: false)
            }
            .padding(Spacing.standard.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Radii.standard.md).stroke(Color(argb: p.border), lineWidth: 1))
            .padding(Spacing.standard.s3)
            Spacer(minLength: 0)
            ScriptKeyboardView(state: state, palette: p, hapticsEnabled: false, textBefore: { text }, onEdit: { _ in })
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(argb: p.bg))
    }
}
