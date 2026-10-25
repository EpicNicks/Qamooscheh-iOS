import SwiftUI
import QDomain
import QDesign

/// How a unit's completion mark reads (stow-deferred-unit). A deferred unit keeps its normal header; its
/// completion check is replaced by a gray stow icon with a dimmed border. Owner-proposed default, defined
/// here only so the look can change in one place.
public struct StowedUnitStyle: Equatable, Sendable {
    /// SF Symbol shown in place of the completion check.
    public var iconName: String
    /// Border opacity of the badge (dimmed).
    public var borderOpacity: Double
    /// Never the completed look.
    public var showsCheck: Bool

    public init(iconName: String, borderOpacity: Double, showsCheck: Bool) {
        self.iconName = iconName
        self.borderOpacity = borderOpacity
        self.showsCheck = showsCheck
    }

    public static let placeholder = StowedUnitStyle(iconName: "tray.full.fill", borderOpacity: 0.45, showsCheck: false)

    /// The style for a unit, or nil when it is not deferred (the ordinary complete or in-progress look applies).
    public static func style(for unit: PathUnit) -> StowedUnitStyle? {
        unit.deferred ? placeholder : nil
    }
}

/// The unit's completion mark: a green-ish check when complete, a gray stow icon with a dimmed border when
/// deferred, nothing otherwise. `complete` is whether every lesson is passed; a deferred unit is never complete.
public struct UnitCompletionBadgeView: View {
    private let complete: Bool
    private let style: StowedUnitStyle?
    private let palette: AppPalette?

    @Environment(\.colorScheme) private var colorScheme

    public init(complete: Bool, style: StowedUnitStyle?, palette: AppPalette? = nil) {
        self.complete = complete
        self.style = style
        self.palette = palette
    }

    public var body: some View {
        let p = palette ?? (colorScheme == .dark ? AppPalette.dark : AppPalette.light)
        if let style = style {
            Image(systemName: style.iconName)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(Color(argb: p.locked))
                .frame(width: 28, height: 28)
                .overlay(Circle().strokeBorder(Color(argb: p.locked).opacity(style.borderOpacity), lineWidth: 2))
                .accessibilityLabel(StowCopy.actionLabel)
        } else if complete {
            Image(systemName: "checkmark")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(Color(argb: p.success))
                .frame(width: 28, height: 28)
                .overlay(Circle().strokeBorder(Color(argb: p.success), lineWidth: 2))
                .accessibilityLabel("Complete")
        }
    }
}

/// Everything the future journey screen attaches for Stow, ready to mount. The screen holds one of these,
/// reads `onStow` for each popover, `unitBadge` for each unit header, and applies `view(_:)` once on its
/// root so the dialogs and the reminder can present.
@MainActor
public struct StowJourneyHooks {
    public let flow: StowFlowModel
    public let reminder: StowReminderModel
    /// Starts the tapped lesson (Retry Lesson).
    public let onRetryLesson: (String) -> Void

    public init(flow: StowFlowModel, reminder: StowReminderModel, onRetryLesson: @escaping (String) -> Void) {
        self.flow = flow
        self.reminder = reminder
        self.onRetryLesson = onRetryLesson
    }

    /// The popover's Stow closure: nil unless the server lists the lesson as stowable.
    public func onStow(for skill: PathSkill, actions: SkillActions) -> (() -> Void)? {
        guard actions.stowOffered else { return nil }
        let key = skill.skillKey
        let flow = self.flow
        return { flow.request(lessonKey: key) }
    }

    /// The unit header's completion mark.
    public func unitBadge(for unit: PathUnit, complete: Bool) -> UnitCompletionBadgeView {
        let style = StowedUnitStyle.style(for: unit)
        return UnitCompletionBadgeView(complete: complete && style == nil, style: style)
    }

    /// Mounts the Stow dialogs and the reminder on the journey screen's root.
    public func view<Content: View>(_ content: Content, path: [PathUnit]) -> some View {
        content
            .stowDialogs(model: flow, onRetry: onRetryLesson)
            .stowReminder(model: reminder, path: path)
    }
}
