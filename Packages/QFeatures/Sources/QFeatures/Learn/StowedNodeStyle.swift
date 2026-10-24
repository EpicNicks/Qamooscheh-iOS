import Foundation
import QDomain

/// How a stowed lesson reads on the path, drawn from this one place so Rive art can replace it later.
/// Until then it is a plain not-done gray node (stow-node-gray-placeholder). It holds through failed and
/// abandoned retries (stow-retry-keeps-stowed); only a pass leaves the Stowage and so ends it.
public struct StowedNodeStyle: Equatable, Sendable {
    /// Drawn as a gray node, not the done, current or unlocked look.
    public var gray: Bool
    /// Never shown with the done look.
    public var showsDone: Bool
    /// Tappable, so the learner can retry it.
    public var tappable: Bool

    public init(gray: Bool, showsDone: Bool, tappable: Bool) {
        self.gray = gray
        self.showsDone = showsDone
        self.tappable = tappable
    }

    /// The placeholder look.
    public static let placeholder = StowedNodeStyle(gray: true, showsDone: false, tappable: true)

    /// The look for a stowed skill, or nil when it is not stowed (the ordinary status look applies).
    /// Reads `skill.stowed`, which comes from the Stowage, never from the skill's position.
    public static func style(for skill: PathSkill) -> StowedNodeStyle? {
        skill.stowed ? placeholder : nil
    }
}
