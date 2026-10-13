import SwiftUI

/// Layout direction and face for native-script course content (prompts, tiles, typed answers),
/// the SwiftUI side of Android DirectionalText.kt: right-to-left text is Persian, set in the
/// learner's Persian face. App chrome is never wrapped and stays left-to-right.
public enum DirectionalText {
    public static func layoutDirection(rtl: Bool) -> LayoutDirection {
        return rtl ? .rightToLeft : .leftToRight
    }

    /// The font for course text of `size`: the learner's Persian family when `rtl` and one is set, else the system face.
    public static func font(size: CGFloat, rtl: Bool, family: String?) -> Font {
        if rtl, let family = family, !family.isEmpty {
            return Font.custom(family, size: size)
        }
        return Font.system(size: size)
    }
}

public extension View {
    /// Wraps this content in the course language's layout direction (right-to-left for Persian).
    func directionalText(rtl: Bool) -> some View {
        environment(\.layoutDirection, DirectionalText.layoutDirection(rtl: rtl))
    }
}
