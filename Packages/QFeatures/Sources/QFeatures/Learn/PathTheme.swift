import CoreGraphics
import QDomain

/// The swap point for culture-specific path skins (web PathTheme, Android PathTheme.kt).
/// The road and nodes read geometry and icons from here and hardcode none of it.
public struct PathTheme: Equatable, Sendable {
    public var id: String
    public var layout: RoadLayoutConfig
    /// Road metrics below `compactBreakpoint`. Nil means `layout` everywhere.
    public var compactLayout: RoadLayoutConfig?
    /// What each category's node shows above its title; a missing entry shows none.
    public var icons: [SkillCategory: String]
    /// The square card's side; `nodeHalfWidth` is this halved, in logical units.
    public var nodeSize: CGFloat
    public var strokeWidth: CGFloat
    /// The lane a side lesson (story, listening) hangs in off the road, in the road's logical units (web's
    /// spurRowHeight, storyOffset, storyHalfWidth). Below `compactBreakpoint` it is `compactSideLane`.
    public var sideLane: SideRoadConfig
    public var compactSideLane: SideRoadConfig
    /// The round side node's diameter; `sideHalfWidth` is this halved, in logical units.
    public var sideNodeSize: CGFloat

    /// Phones and portrait tablets: compact road, collapsed forks.
    public static let compactBreakpoint: CGFloat = 768

    public init(
        id: String,
        layout: RoadLayoutConfig,
        compactLayout: RoadLayoutConfig?,
        icons: [SkillCategory: String],
        nodeSize: CGFloat,
        strokeWidth: CGFloat,
        sideLane: SideRoadConfig = SideRoadConfig(spurRowHeight: 130, sideOffset: 110, sideHalfWidth: 36),
        compactSideLane: SideRoadConfig = SideRoadConfig(spurRowHeight: 108, sideOffset: 110, sideHalfWidth: 36),
        sideNodeSize: CGFloat = 72
    ) {
        self.id = id
        self.layout = layout
        self.compactLayout = compactLayout
        self.icons = icons
        self.nodeSize = nodeSize
        self.strokeWidth = strokeWidth
        self.sideLane = sideLane
        self.compactSideLane = compactSideLane
        self.sideNodeSize = sideNodeSize
    }

    public func sideLaneFor(compact: Bool) -> SideRoadConfig {
        compact ? compactSideLane : sideLane
    }

    public func layoutFor(compact: Bool) -> RoadLayoutConfig {
        if compact, let compactLayout = compactLayout { return compactLayout }
        return layout
    }

    /// Web defaultPathTheme: a 100pt card in a 320-unit logical width. No icon for an ordinary lesson.
    public static let standard = PathTheme(
        id: "default",
        layout: RoadLayoutConfig(rowHeight: 190, branchSpread: 110, logicalWidth: 320, nodeHalfWidth: 50),
        compactLayout: RoadLayoutConfig(rowHeight: 150, branchSpread: 108, logicalWidth: 320, nodeHalfWidth: 50),
        icons: [
            .story: "\u{1F4D6}",
            .conversation: "\u{1F4AC}",
            .song: "\u{1F3B5}",
            .listening: "\u{1F3A7}",
        ],
        nodeSize: 100,
        strokeWidth: 6
    )
}
