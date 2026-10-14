import SwiftUI
import QDomain
import QDesign

/// Today's XP against the daily goal: a small ring and "30/50" (Android DailyGoalCounter, the compact
/// header version; the web's caption is dropped, as on Android). `celebrating` shows the one-off pulse:
/// the ring scaled up with a success-coloured halo.
public struct DailyGoalRingView: View {
    private let xp: Int
    private let goal: Int
    private let celebrating: Bool
    private let palette: AppPalette?

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(xp: Int, goal: Int, celebrating: Bool = false, palette: AppPalette? = nil) {
        self.xp = xp
        self.goal = goal
        self.celebrating = celebrating
        self.palette = palette
    }

    public var body: some View {
        let p = palette ?? (colorScheme == .dark ? AppPalette.dark : AppPalette.light)
        let reached = xp >= goal
        let fraction = dailyGoalRingFraction(xp: xp, goal: goal)
        let size = CGFloat(dailyGoalRingSize)
        let stroke: CGFloat = size * 5.0 / 48.0
        let animates = goalCelebrationAnimates(celebrating: celebrating, reduceMotion: reduceMotion)
        HStack(spacing: Spacing.standard.s1) {
            ZStack {
                Circle()
                    .stroke(Color(argb: p.border), lineWidth: stroke)
                Circle()
                    .trim(from: 0, to: CGFloat(fraction))
                    .stroke(
                        Color(argb: reached ? p.success : p.primary),
                        style: StrokeStyle(lineWidth: stroke, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
            }
            .padding(size * 4.0 / 48.0)
            .frame(width: size, height: size)
            Text(dailyGoalRingLabel(xp: xp, goal: goal))
                .font(.subheadline.weight(.bold))
                .foregroundColor(Color(argb: p.text))
                .lineLimit(1)
        }
        .padding(.horizontal, Spacing.standard.s1)
        .padding(.vertical, Spacing.standard.s1)
        .background(
            Capsule().fill(celebrating ? Color(argb: p.successBg) : Color.clear)
        )
        .overlay(
            Capsule().stroke(Color(argb: p.success).opacity(celebrating ? 0.45 : 0), lineWidth: 3)
        )
        .scaleEffect(animates ? 1.08 : 1)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: fraction)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(dailyGoalAccessibilityLabel(xp: xp, goal: goal))
    }
}
