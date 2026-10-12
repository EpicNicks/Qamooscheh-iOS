import SwiftUI
import QDomain
import QDesign

/// Fixture data and a gallery of every road and node state, for snapshot tests and previews.
public enum PathRoadFixtures {
    private static func skill(_ key: String, _ title: String, status: SkillStatus, completed: Bool, position: Int) -> PathSkill {
        PathSkill(
            skillKey: key, title: title, category: .standard, arc: nil, unitKey: "u1",
            status: status, completed: completed, positionIndex: position
        )
    }

    /// done, a half-finished fork, the current lesson, then locked road ahead.
    public static func positions() -> [PathPosition] {
        return [
            PathPosition(positionIndex: 0, status: .unlocked, skills: [skill("a", "Greetings", status: .unlocked, completed: true, position: 0)]),
            PathPosition(positionIndex: 1, status: .unlocked, skills: [
                skill("b1", "Food", status: .unlocked, completed: true, position: 1),
                skill("b2", "Drinks", status: .unlocked, completed: false, position: 1),
            ]),
            PathPosition(positionIndex: 2, status: .current, skills: [skill("c", "Numbers and counting things", status: .current, completed: false, position: 2)]),
            PathPosition(positionIndex: 3, status: .locked, skills: [
                skill("d1", "Family", status: .locked, completed: false, position: 3),
                skill("d2", "Friends", status: .locked, completed: false, position: 3),
            ]),
            PathPosition(positionIndex: 4, status: .locked, skills: [skill("e", "Travel", status: .locked, completed: false, position: 4)]),
        ]
    }

    public static func road(compact: Bool) -> UnitRoad {
        return UnitRoad(positions: positions(), config: PathTheme.standard.layoutFor(compact: compact), collapseForks: compact)
    }
}

/// Every node state, then the road (compact and full). Used by the app's snapshot tests.
public struct PathRoadShowcase: View {
    private let rtl: Bool

    @Environment(\.colorScheme) private var colorScheme

    public init(rtl: Bool = false) {
        self.rtl = rtl
    }

    public var body: some View {
        let p = colorScheme == .dark ? AppPalette.dark : AppPalette.light
        ScrollView {
            VStack(spacing: 24) {
                HStack(spacing: 16) {
                    SkillNodeView(title: "Locked", status: .locked, icon: nil)
                    SkillNodeView(title: "Current", status: .current, icon: nil)
                    SkillNodeView(title: "Done", status: .unlocked, icon: nil)
                }
                HStack(spacing: 16) {
                    SkillNodeView(title: "Branch done", status: .unlocked, icon: nil, completed: true)
                    SkillNodeView(title: "Story", status: .current, icon: "\u{1F4D6}")
                }
                HStack(spacing: 24) {
                    SkillGroupNodeView(position: PathRoadFixtures.positions()[3])
                    SkillGroupNodeView(position: PathRoadFixtures.positions()[1])
                }
                PlacementTestNodeView()
                SkillRoadView(road: PathRoadFixtures.road(compact: true))
            }
            .padding(16)
        }
        .background(Color(argb: p.bg))
        .environment(\.layoutDirection, rtl ? .rightToLeft : .leftToRight)
    }
}
