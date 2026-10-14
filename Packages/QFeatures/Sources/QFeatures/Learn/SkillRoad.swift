import SwiftUI
import QDomain
import QDesign

/// The straight, branching road of a unit's standard skills (web SkillRoad, Android SkillRoad):
/// connectors drawn underneath, nodes placed on top, both from the same QDomain layout. x scales
/// from the theme's logical width to the real width; y is already in points. In a right-to-left
/// layout the whole road mirrors, as Compose's offset does.
public struct SkillRoadView: View {
    private let road: UnitRoad
    private let theme: PathTheme
    private let palette: AppPalette?
    private let onSkillTap: (PathSkill) -> Void
    private let onGroupTap: (PathPosition) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.layoutDirection) private var layoutDirection

    public init(
        road: UnitRoad,
        theme: PathTheme = .standard,
        palette: AppPalette? = nil,
        onSkillTap: @escaping (PathSkill) -> Void = { _ in },
        onGroupTap: @escaping (PathPosition) -> Void = { _ in }
    ) {
        self.road = road
        self.theme = theme
        self.palette = palette
        self.onSkillTap = onSkillTap
        self.onGroupTap = onGroupTap
    }

    public var body: some View {
        if road.positions.isEmpty {
            EmptyView()
        } else {
            GeometryReader { proxy in
                content(width: proxy.size.width)
            }
            .frame(height: CGFloat(road.layout.totalHeight))
        }
    }

    private func mirrored(_ x: CGFloat, width: CGFloat) -> CGFloat {
        return CGFloat(roadMirroredX(Double(x), width: Double(width), rtl: layoutDirection == .rightToLeft))
    }

    @ViewBuilder
    private func content(width: CGFloat) -> some View {
        let p = palette ?? (colorScheme == .dark ? AppPalette.dark : AppPalette.light)
        let scale = width / CGFloat(road.config.logicalWidth)
        let side = theme.nodeSize
        ZStack(alignment: .topLeading) {
            Canvas { context, _ in
                for edge in road.edgesInPaintOrder {
                    let startX = mirrored(CGFloat(edge.fromX) * scale, width: width)
                    let endX = mirrored(CGFloat(edge.toX) * scale, width: width)
                    let startY = CGFloat(edge.fromY)
                    let endY = CGFloat(edge.toY)
                    if let branches = road.collapsedBranches(edge) {
                        // Side by side in variant order; a finished variant's line runs green.
                        let pitch = theme.strokeWidth + 3
                        let colors = road.collapsedBranchColors(edge, branches: branches, palette: p)
                        for (index, color) in colors.enumerated() {
                            let dx = (CGFloat(index) - CGFloat(branches.count - 1) / 2) * pitch
                            var line = Path()
                            line.move(to: CGPoint(x: startX + dx, y: startY))
                            line.addLine(to: CGPoint(x: endX + dx, y: endY))
                            context.stroke(line, with: .color(Color(argb: color)), style: StrokeStyle(lineWidth: theme.strokeWidth, lineCap: .round))
                        }
                    } else {
                        var line = Path()
                        line.move(to: CGPoint(x: startX, y: startY))
                        line.addLine(to: CGPoint(x: endX, y: endY))
                        context.stroke(
                            line,
                            with: .color(Color(argb: road.edgeColor(edge, palette: p))),
                            style: StrokeStyle(lineWidth: theme.strokeWidth, lineCap: .round)
                        )
                    }
                }
            }
            .frame(width: width, height: CGFloat(road.layout.totalHeight))

            ForEach(Array(road.layout.nodes.enumerated()), id: \.offset) { entry in
                let node = entry.element
                let position = road.positions[node.positionIndex]
                // Clamped against the real width, so a narrow phone cannot hang a card off the edge.
                let centre = mirrored(CGFloat(node.x) * scale, width: width)
                let left = min(max(centre - side / 2, 0), max(width - side, 0))
                nodeView(position: position, skillIndex: node.skillIndex, palette: p)
                    .offset(x: left, y: CGFloat(node.y) - side / 2)
            }
        }
        .frame(width: width, height: CGFloat(road.layout.totalHeight), alignment: .topLeading)
    }

    @ViewBuilder
    private func nodeView(position: PathPosition, skillIndex: Int, palette p: AppPalette) -> some View {
        if road.collapseForks && position.skills.count > 1 {
            SkillGroupNodeView(
                position: position,
                icon: theme.icons[.standard],
                theme: theme,
                palette: p,
                onTap: { onGroupTap(position) }
            )
        } else {
            let skill = position.skills[skillIndex]
            SkillNodeView(
                title: skill.title,
                status: skill.status,
                icon: theme.icons[skill.category],
                completed: position.skills.count > 1 && skill.completed,
                theme: theme,
                palette: p,
                onTap: { onSkillTap(skill) }
            )
        }
    }
}
