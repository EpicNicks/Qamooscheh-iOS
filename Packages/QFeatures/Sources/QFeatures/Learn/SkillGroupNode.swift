import SwiftUI
import QDomain
import QDesign

/// A fork collapsed into one node (web SkillGroupNode, Android SkillGroupNode): a stacked deck so it
/// reads as "more behind this", with a count pill. A 100pt card cannot show several lesson titles
/// side by side on a phone. Takes plain values; the caller supplies the tap.
public struct SkillGroupNodeView: View {
    private let position: PathPosition
    private let icon: String?
    private let theme: PathTheme
    private let palette: AppPalette?
    private let onTap: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    public init(
        position: PathPosition,
        icon: String? = nil,
        theme: PathTheme = .standard,
        palette: AppPalette? = nil,
        onTap: @escaping () -> Void = {}
    ) {
        self.position = position
        self.icon = icon
        self.theme = theme
        self.palette = palette
        self.onTap = onTap
    }

    public var body: some View {
        let p = palette ?? (colorScheme == .dark ? AppPalette.dark : AppPalette.light)
        let count = position.skills.count
        let side = theme.nodeSize
        let radius = Radii.standard.md
        ZStack {
            ForEach([8, 4], id: \.self) { step in
                RoundedRectangle(cornerRadius: radius)
                    .fill(Color(argb: p.surface))
                    .frame(width: side, height: side)
                    .offset(x: CGFloat(step), y: CGFloat(step))
                RoundedRectangle(cornerRadius: radius - 1)
                    .strokeBorder(Color(argb: p.border), lineWidth: 2)
                    .frame(width: side, height: side)
                    .offset(x: CGFloat(step), y: CGFloat(step))
            }
            SkillNodeView(
                title: "\(count) lessons",
                status: position.status,
                icon: icon,
                completed: allBranchesFinished(position),
                branch: false,
                accessibilityLabel: "\(count) lesson choices\(groupDoneNote(position)): \(position.skills.map { $0.title }.joined(separator: ", "))",
                theme: theme,
                palette: p,
                onTap: onTap,
                badge: {
                    Text("\(count)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Color(argb: p.primaryContrast))
                        .padding(.horizontal, 4)
                        .frame(minWidth: 18, minHeight: 18)
                        .background(Capsule().fill(Color(argb: p.primary)))
                        .offset(x: side / 2 - 3, y: -(side / 2 - 3))
                }
            )
        }
        .frame(width: side, height: side)
    }
}
