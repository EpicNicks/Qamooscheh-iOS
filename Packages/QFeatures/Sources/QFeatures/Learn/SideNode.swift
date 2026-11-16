import SwiftUI
import QDomain
import QDesign

/// A side lesson's round node on the road (web SkillNode "story" layout): a small circle instead of the dog-eared
/// square, so it reads as a side trip. A story and a listening lesson look alike apart from the icon. Takes plain
/// values; the caller supplies the tap. A locked node is not tappable.
public struct SideNodeView: View {
    private let skill: PathSkill
    private let locked: Bool
    private let icon: String?
    private let theme: PathTheme
    private let palette: AppPalette?
    private let onTap: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    public init(
        skill: PathSkill,
        locked: Bool,
        icon: String?,
        theme: PathTheme = .standard,
        palette: AppPalette? = nil,
        onTap: @escaping () -> Void = {}
    ) {
        self.skill = skill
        self.locked = locked
        self.icon = icon
        self.theme = theme
        self.palette = palette
        self.onTap = onTap
    }

    public var body: some View {
        let p = palette ?? (colorScheme == .dark ? AppPalette.dark : AppPalette.light)
        let colors = sideNodeColors(locked: locked, completed: skill.completed, palette: p)
        let side = theme.sideNodeSize
        Button(action: onTap) {
            ZStack {
                Circle().fill(Color(argb: colors.background)).frame(width: side, height: side)
                Circle().strokeBorder(Color(argb: colors.accent), lineWidth: 2).frame(width: side, height: side)
                VStack(spacing: 0) {
                    if let icon = icon {
                        Text(icon).font(.footnote)
                    }
                    Text(skill.title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color(argb: colors.title))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                }
                .padding(6)
                .frame(width: side, height: side)
                if skill.completed {
                    Text("\u{2713}")
                        .font(.caption2.weight(.bold))
                        .foregroundColor(Color(argb: p.primaryContrast))
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(Color(argb: p.primary)))
                        .offset(x: side / 2 - 9 + 4, y: -(side / 2 - 9 + 4))
                }
            }
            .frame(width: side, height: side)
        }
        .buttonStyle(.plain)
        .disabled(locked)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(sideNodeLabel(skill, locked: locked))
        .accessibilityAddTraits(.isButton)
    }
}
