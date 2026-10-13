import SwiftUI
import QKeyboard
import QDesign

/// One key cap (Android `KeyCap`). Drawing only; the keyboard owns the gestures.
public struct VirtualKey: View {
    private let key: Key
    private let palette: AppPalette

    public init(key: Key, palette: AppPalette) {
        self.key = key
        self.palette = palette
    }

    public static func accessibilityName(for key: Key) -> String {
        switch key.action {
        case .backspace: return "Backspace"
        case .zwnj: return "Half-space"
        case .space: return "Space"
        case .shift: return "Shift"
        default: return key.label
        }
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8)
        let long = key.label.count > 2
        Text(key.label)
            .font(.system(size: long ? 14 : 20, weight: long ? .semibold : .regular))
            .foregroundColor(Color(argb: palette.text))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity)
            .frame(height: KeyboardMetrics.keyHeight)
            .background(shape.fill(Color(argb: key.highlighted ? palette.successBg : palette.bg)))
            .shadow(color: Color.black.opacity(0.18), radius: 0.5, x: 0, y: 1)
            .opacity(key.enabled ? 1 : 0.35)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(VirtualKey.accessibilityName(for: key))
            .accessibilityAddTraits(.isButton)
    }
}
