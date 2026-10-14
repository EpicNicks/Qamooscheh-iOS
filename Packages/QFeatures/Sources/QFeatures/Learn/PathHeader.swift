import SwiftUI
import QDesign

/// The Path screen's top row (Android top bar): course picker button, streak, and the daily goal ring
/// (hidden without a goal, as on Android).
public struct PathHeaderView: View {
    private let courseName: String
    private let streakDays: Int
    private let goal: DailyGoalProgress?
    private let totalXp: Int?
    private let celebrating: Bool
    private let palette: AppPalette?
    private let onPickCourse: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    public init(
        courseName: String,
        streakDays: Int,
        goal: DailyGoalProgress?,
        totalXp: Int? = nil,
        celebrating: Bool = false,
        palette: AppPalette? = nil,
        onPickCourse: @escaping () -> Void = {}
    ) {
        self.courseName = courseName
        self.streakDays = streakDays
        self.goal = goal
        self.totalXp = totalXp
        self.celebrating = celebrating
        self.palette = palette
        self.onPickCourse = onPickCourse
    }

    public var body: some View {
        let p = palette ?? (colorScheme == .dark ? AppPalette.dark : AppPalette.light)
        HStack(spacing: Spacing.standard.s3) {
            Button(action: onPickCourse) {
                HStack(spacing: Spacing.standard.s1) {
                    Text(courseName)
                        .font(.callout.weight(.bold))
                        .foregroundColor(Color(argb: p.text))
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundColor(Color(argb: p.textMuted))
                }
                .padding(.horizontal, Spacing.standard.s3)
                .padding(.vertical, Spacing.standard.s2)
                .background(
                    RoundedRectangle(cornerRadius: Radii.standard.md).fill(Color(argb: p.surface))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radii.standard.md).stroke(Color(argb: p.border), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Course: \(courseName)")
            .accessibilityAddTraits(.isButton)
            Spacer(minLength: 0)
            HStack(spacing: Spacing.standard.s1) {
                Text("\u{1F525}")
                    .font(.callout)
                Text(streakLabel(streakDays))
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(Color(argb: p.streakFire))
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(streakLabel(streakDays)) day streak")
            if let totalXp = totalXp {
                Text(totalXpLabel(totalXp))
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(Color(argb: p.text))
                    .lineLimit(1)
                    .accessibilityLabel(totalXpAccessibilityLabel(totalXp))
            }
            if let goal = goal {
                DailyGoalRingView(xp: goal.xp, goal: goal.goal, celebrating: celebrating, palette: p)
            }
        }
        .padding(.horizontal, Spacing.standard.s3)
        .padding(.vertical, Spacing.standard.s2)
        .background(Color(argb: p.bg))
    }
}

/// Gallery for snapshot tests: the header, the ring at 0%, 50%, 100% and the celebration state,
/// and both jump directions.
public struct PathChromeShowcase: View {
    private let rtl: Bool

    @Environment(\.colorScheme) private var colorScheme

    public init(rtl: Bool = false) {
        self.rtl = rtl
    }

    public var body: some View {
        let p = colorScheme == .dark ? AppPalette.dark : AppPalette.light
        VStack(alignment: .leading, spacing: 20) {
            PathHeaderView(courseName: "Persian", streakDays: 12, goal: DailyGoalProgress(xp: 300, goal: 750), totalXp: 4210)
            DailyGoalRingView(xp: 0, goal: 750)
            DailyGoalRingView(xp: 375, goal: 750)
            DailyGoalRingView(xp: 750, goal: 750)
            DailyGoalRingView(xp: 750, goal: 750, celebrating: true)
            HStack(spacing: 24) {
                JumpToCurrentButton(direction: .up)
                JumpToCurrentButton(direction: .down)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(argb: p.bg))
        .environment(\.layoutDirection, rtl ? .rightToLeft : .leftToRight)
    }
}
