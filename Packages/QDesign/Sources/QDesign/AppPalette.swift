import SwiftUI

/// The app's color tokens, one field per `--color-*` variable (ported from Android `AppColors.kt`).
/// Values are 0xAARRGGBB so they can be tested without SwiftUI.
public struct AppPalette: Equatable, Sendable {
    public var bg: UInt32
    public var surface: UInt32
    public var border: UInt32
    public var text: UInt32
    public var textMuted: UInt32
    public var primary: UInt32
    public var primaryHover: UInt32
    public var primaryContrast: UInt32
    public var danger: UInt32
    public var dangerBg: UInt32
    public var success: UInt32
    public var successBg: UInt32
    public var warning: UInt32
    public var warningBg: UInt32
    public var info: UInt32
    public var infoBg: UInt32
    public var locked: UInt32
    public var current: UInt32
    public var placement: UInt32
    public var deepDive: UInt32
    public var deepDiveHover: UInt32
    public var streakFire: UInt32
    public var streakFireStart: UInt32
    public var streakFireEnd: UInt32
    public var streakEmber: UInt32
    public var streakAsh: UInt32
    public var isDark: Bool

    public static let light = AppPalette(
        bg: 0xFFFFFFFF,
        surface: 0xFFF7F7F9,
        border: 0xFFE5E5EA,
        text: 0xFF1A1A2E,
        textMuted: 0xFF6B6B7B,
        primary: 0xFF58CC02,
        primaryHover: 0xFF4CAF00,
        primaryContrast: 0xFFFFFFFF,
        danger: 0xFFFF4B4B,
        dangerBg: 0xFFFFEAEA,
        success: 0xFF58CC02,
        successBg: 0xFFEAFFDF,
        warning: 0xFFD9A100,
        warningBg: 0xFFFFF6D6,
        info: 0xFF0F6AA5,
        infoBg: 0xFFE2F2FC,
        locked: 0xFFCFCFD6,
        current: 0xFF1CB0F6,
        placement: 0xFFFF9600,
        deepDive: 0xFF8854D0,
        deepDiveHover: 0xFF7042B8,
        streakFire: 0xFFD9480F,
        streakFireStart: 0xFFE06800,
        streakFireEnd: 0xFFC62A12,
        streakEmber: 0xFF8C857F,
        streakAsh: 0xFFD3CFCB,
        isDark: false
    )

    /// Only the tokens the web's dark override changes differ from `light`.
    public static let dark: AppPalette = {
        var p = AppPalette.light
        p.bg = 0xFF131320
        p.surface = 0xFF1C1C2B
        p.border = 0xFF2C2C3D
        p.text = 0xFFF2F2F7
        p.textMuted = 0xFF9A9AAB
        p.dangerBg = 0xFF3A1414
        p.successBg = 0xFF123018
        p.warningBg = 0xFF3A2F08
        p.info = 0xFF6EC1F5
        p.infoBg = 0xFF0E2A3F
        p.locked = 0xFF3A3A4A
        p.streakFire = 0xFFFF7A3D
        p.streakFireStart = 0xFFFFA033
        p.streakFireEnd = 0xFFFF5A3C
        p.streakEmber = 0xFFEEE9E4
        p.streakAsh = 0xFF8F8B88
        p.isDark = true
        return p
    }()
}

public extension Color {
    /// Builds an sRGB color from 0xAARRGGBB.
    init(argb: UInt32) {
        let a = Double((argb >> 24) & 0xFF) / 255.0
        let r = Double((argb >> 16) & 0xFF) / 255.0
        let g = Double((argb >> 8) & 0xFF) / 255.0
        let b = Double(argb & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}
