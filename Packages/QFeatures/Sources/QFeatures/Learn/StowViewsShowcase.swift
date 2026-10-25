import SwiftUI
import QDomain
import QDesign

public enum StowViewsPage: Sendable {
    /// The three dialog cards.
    case dialogs
    /// The reminder, a stowed node beside a normal one, and the popover with Stow.
    case reminder
}

/// Gallery for snapshot tests, one page per screenful.
public struct StowViewsShowcase: View {
    private let page: StowViewsPage
    private let rtl: Bool

    @Environment(\.colorScheme) private var colorScheme

    public init(page: StowViewsPage, rtl: Bool = false) {
        self.page = page
        self.rtl = rtl
    }

    private static func lesson(_ key: String, _ title: String, unit: String, stowed: Bool = true) -> PathSkill {
        PathSkill(
            skillKey: key, title: title, category: .standard, arc: nil, unitKey: unit,
            status: .unlocked, completed: true, positionIndex: 0, stowed: stowed
        )
    }

    static let groups: [StowageGroup] = [
        StowageGroup(unitKey: "u3", unitTitle: "Unit 3: Travel", lessons: [lesson("t1", "Trains", unit: "u3")]),
        StowageGroup(unitKey: "u1", unitTitle: "Unit 1: Basics", lessons: [lesson("a", "Greetings", unit: "u1"), lesson("b", "Food", unit: "u1")]),
    ]

    public var body: some View {
        let p = colorScheme == .dark ? AppPalette.dark : AppPalette.light
        VStack(spacing: 16) {
            switch page {
            case .dialogs:
                card(StowDialogCardView(state: StowFlowState(lessonKey: "c")))
                card(StowDialogCardView(state: stateAt(.encouraged)))
                card(StowDialogCardView(state: stateAt(.declined)))
            case .reminder:
                StowReminderView(groups: StowViewsShowcase.groups)
                    .frame(height: 360)
                    .clipShape(RoundedRectangle(cornerRadius: Radii.standard.lg))
                    .overlay(RoundedRectangle(cornerRadius: Radii.standard.lg).strokeBorder(Color(argb: p.border), lineWidth: 2))
                HStack(spacing: 24) {
                    SkillNodeView(title: "Greetings", status: .unlocked, icon: nil, completed: true)
                    SkillNodeView(title: "Food", status: .unlocked, icon: nil, completed: true, stowed: true)
                }
                LessonStartPopoverView(primaryLabel: "Start lesson", description: "Numbers", onDeepDive: {}, onSkip: {}, onStow: {})
                    .clipShape(RoundedRectangle(cornerRadius: Radii.standard.md))
                    .overlay(RoundedRectangle(cornerRadius: Radii.standard.md).strokeBorder(Color.gray.opacity(0.5), lineWidth: 2))
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(argb: p.bg))
        .environment(\.layoutDirection, rtl ? .rightToLeft : .leftToRight)
    }

    private func stateAt(_ step: StowStep) -> StowFlowState {
        var state = StowFlowState(lessonKey: "c")
        state.step = step
        return state
    }

    private func card<Content: View>(_ content: Content) -> some View {
        content
            .clipShape(RoundedRectangle(cornerRadius: Radii.standard.md))
            .overlay(RoundedRectangle(cornerRadius: Radii.standard.md).strokeBorder(Color.gray.opacity(0.5), lineWidth: 2))
    }
}
