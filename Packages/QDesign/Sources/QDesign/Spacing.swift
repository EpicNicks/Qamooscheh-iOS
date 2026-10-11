import CoreGraphics

/// `--space-1..5` from the web's `index.css` (ported from Android `Dimens.kt`), in points.
public struct Spacing: Equatable, Sendable {
    public let s1: CGFloat
    public let s2: CGFloat
    public let s3: CGFloat
    public let s4: CGFloat
    public let s5: CGFloat

    public init(s1: CGFloat = 4, s2: CGFloat = 8, s3: CGFloat = 16, s4: CGFloat = 24, s5: CGFloat = 32) {
        self.s1 = s1
        self.s2 = s2
        self.s3 = s3
        self.s4 = s4
        self.s5 = s5
    }

    public static let standard = Spacing()
}

/// `--radius-sm/md/lg` from the web's `index.css`, in points.
public struct Radii: Equatable, Sendable {
    public let sm: CGFloat
    public let md: CGFloat
    public let lg: CGFloat

    public init(sm: CGFloat = 8, md: CGFloat = 14, lg: CGFloat = 20) {
        self.sm = sm
        self.md = md
        self.lg = lg
    }

    public static let standard = Radii()
}
