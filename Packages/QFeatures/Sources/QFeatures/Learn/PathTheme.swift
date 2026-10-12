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

    /// Phones and portrait tablets: compact road, collapsed forks.
    public static let compactBreakpoint: CGFloat = 768

    public init(
        id: String,
        layout: RoadLayoutConfig,
        compactLayout: RoadLayoutConfig?,
        icons: [SkillCategory: String],
        nodeSize: CGFloat,
        strokeWidth: CGFloat
    ) {
        self.id = id
        self.layout = layout
        self.compactLayout = compactLayout
        self.icons = icons
        self.nodeSize = nodeSize
        self.strokeWidth = strokeWidth
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
        ],
        nodeSize: 100,
        strokeWidth: 6
    )
}
