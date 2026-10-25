import SwiftUI
import QDomain
import QDesign

/// The square road card (web SkillNode "node" layout, Android SkillNode): every card is the same
/// square whatever its title, with a dog-eared top-left corner that deepens while pressed.
/// Takes plain values; the caller supplies the tap.
public struct SkillNodeView<Badge: View>: View {
    private let title: String
    private let status: SkillStatus
    private let icon: String?
    private let completed: Bool
    private let branch: Bool
    private let springFold: Bool
    private let stowed: Bool
    private let accessibilityText: String
    private let theme: PathTheme
    private let palette: AppPalette?
    private let onTap: () -> Void
    private let badge: Badge

    @Environment(\.colorScheme) private var colorScheme

    public init(
        title: String,
        status: SkillStatus,
        icon: String?,
        completed: Bool = false,
        branch: Bool = true,
        springFold: Bool = false,
        stowed: Bool = false,
        accessibilityLabel: String? = nil,
        theme: PathTheme = .standard,
        palette: AppPalette? = nil,
        onTap: @escaping () -> Void = {},
        @ViewBuilder badge: () -> Badge
    ) {
        self.title = title
        self.status = status
        self.icon = icon
        self.completed = completed
        self.branch = branch
        self.springFold = springFold
        self.stowed = stowed
        self.accessibilityText = accessibilityLabel ?? title
        self.theme = theme
        self.palette = palette
        self.onTap = onTap
        self.badge = badge()
    }

    public var body: some View {
        let p = palette ?? (colorScheme == .dark ? AppPalette.dark : AppPalette.light)
        // A stowed lesson reads from StowedNodeStyle only: a gray not-done node that stays tappable.
        let look = stowed ? StowedNodeStyle.placeholder : nil
        let drawStatus: SkillStatus = (look?.gray ?? false) ? .locked : status
        let drawCompleted = (look?.showsDone ?? true) ? completed : false
        let tappable = look?.tappable ?? (status != .locked)
        Button(action: onTap) {
            SkillNodeFace(
                title: title, status: drawStatus, icon: icon, completed: drawCompleted, branch: branch,
                theme: theme, palette: p, badge: badge
            )
        }
        .buttonStyle(NodePressStyle(locked: !tappable, theme: theme, palette: p, status: drawStatus, completed: drawCompleted, branch: branch, springFold: springFold))
        .disabled(!tappable)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(accessibilityText), \(stowed ? "stowed" : nodeStatusWord(status: status, completed: completed))")
        .accessibilityAddTraits(.isButton)
    }
}

extension SkillNodeView where Badge == EmptyView {
    public init(
        title: String,
        status: SkillStatus,
        icon: String?,
        completed: Bool = false,
        branch: Bool = true,
        springFold: Bool = false,
        stowed: Bool = false,
        accessibilityLabel: String? = nil,
        theme: PathTheme = .standard,
        palette: AppPalette? = nil,
        onTap: @escaping () -> Void = {}
    ) {
        self.init(
            title: title, status: status, icon: icon, completed: completed, branch: branch, springFold: springFold, stowed: stowed,
            accessibilityLabel: accessibilityLabel, theme: theme, palette: palette, onTap: onTap,
            badge: { EmptyView() }
        )
    }
}

/// Draws the card for the pressed or resting fold. Not a Button style's label: the style
/// only decides the fold depth, so it overlays the same card content.
private struct NodePressStyle: ButtonStyle {
    let locked: Bool
    let theme: PathTheme
    let palette: AppPalette
    let status: SkillStatus
    let completed: Bool
    let branch: Bool
    let springFold: Bool

    func makeBody(configuration: Configuration) -> some View {
        let depth = CGFloat(nodeFoldDepth(pressed: configuration.isPressed, locked: locked))
        return configuration.label.overlay(
            FoldCorner(
                colors: nodeColors(status: status, palette: palette, completed: completed, branch: branch),
                fold: depth,
                backdrop: palette.bg,
                size: theme.nodeSize
            )
            .animation(springFold ? .spring(response: 0.3, dampingFraction: 0.55) : nil, value: depth)
        )
    }
}

/// The card body: halo, fill, border, then icon and title, plus the check mark and badge.
struct SkillNodeFace<Badge: View>: View {
    let title: String
    let status: SkillStatus
    let icon: String?
    let completed: Bool
    let branch: Bool
    let theme: PathTheme
    let palette: AppPalette
    let badge: Badge

    var body: some View {
        let colors = nodeColors(status: status, palette: palette, completed: completed, branch: branch)
        let radius = Radii.standard.md
        let side = theme.nodeSize
        ZStack {
            if let halo = colors.halo {
                RoundedRectangle(cornerRadius: radius + 3)
                    .fill(Color(argb: halo))
                    .frame(width: side + 6, height: side + 6)
            }
            RoundedRectangle(cornerRadius: radius)
                .fill(Color(argb: colors.background))
                .frame(width: side, height: side)
            RoundedRectangle(cornerRadius: radius - 1)
                .strokeBorder(Color(argb: colors.accent), lineWidth: 2)
                .frame(width: side, height: side)
            VStack(spacing: 4) {
                if let icon = icon {
                    Text(icon).font(.title3)
                }
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(Color(argb: colors.title))
                    .multilineTextAlignment(.center)
                    // A story/conversation/song card's icon costs a line.
                    .lineLimit(icon != nil ? 3 : 4)
            }
            .padding(EdgeInsets(top: 16, leading: 8, bottom: 8, trailing: 8))
            .frame(width: side, height: side)
            badge
            if completed {
                Text("\u{2713}")
                    .font(.caption.weight(.bold))
                    .foregroundColor(Color(argb: palette.primaryContrast))
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(Color(argb: branch ? palette.current : palette.primary)))
                    .offset(x: side / 2 - 10 + 6, y: side / 2 - 10 + 6)
            }
        }
        .frame(width: side, height: side)
    }
}

/// The folded corner. The fold line runs from (f, 0) to (0, f) on the card's outer corner.
/// Everything off that line is painted away in the page color (bleeding past the edges so it
/// also cuts the halo); the flap is the cut triangle mirrored across the fold.
struct FoldCorner: View {
    let colors: NodeColors
    let fold: CGFloat
    let backdrop: UInt32
    let size: CGFloat

    private let bleed: CGFloat = 5

    var body: some View {
        let f = fold
        let pad = bleed
        Canvas { context, _ in
            // Canvas origin is the card's top-left minus the bleed.
            let o = pad
            var cut = Path()
            cut.move(to: CGPoint(x: o - pad, y: o - pad))
            cut.addLine(to: CGPoint(x: o + f + pad, y: o - pad))
            cut.addLine(to: CGPoint(x: o - pad, y: o + f + pad))
            cut.closeSubpath()
            context.fill(cut, with: .color(Color(argb: backdrop)))

            func flap(shift: CGFloat) -> Path {
                var p = Path()
                p.move(to: CGPoint(x: o + f + shift, y: o + shift))
                p.addLine(to: CGPoint(x: o + f + shift, y: o + f - 4 + shift))
                p.addQuadCurve(
                    to: CGPoint(x: o + f - 4 + shift, y: o + f + shift),
                    control: CGPoint(x: o + f + shift, y: o + f + shift)
                )
                p.addLine(to: CGPoint(x: o + shift, y: o + f + shift))
                p.closeSubpath()
                return p
            }
            context.fill(flap(shift: 1), with: .color(Color.black.opacity(0.18)))
            context.fill(
                flap(shift: 0),
                with: .linearGradient(
                    Gradient(colors: [Color(argb: colors.flapLight), Color(argb: colors.flapDark)]),
                    startPoint: CGPoint(x: o + f / 2, y: o + f / 2),
                    endPoint: CGPoint(x: o + f, y: o + f)
                )
            )
        }
        .frame(width: size + 2 * pad, height: size + 2 * pad)
        .allowsHitTesting(false)
    }
}
