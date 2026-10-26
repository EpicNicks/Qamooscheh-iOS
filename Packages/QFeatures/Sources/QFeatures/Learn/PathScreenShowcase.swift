import SwiftUI
import QModel
import QDomain
import QDesign

public enum PathScreenPage: Sendable {
    /// The road: header, unit titles, placement node, forks, locked road ahead.
    case ready
    /// Downloading n of total.
    case downloading
    /// Download failed, with Try again.
    case failed
}

/// Fixture state and a gallery of the Path screen's bodies, for snapshot tests and previews.
public enum PathScreenFixtures {
    private static func skill(_ key: String) -> PathSkillInput {
        PathSkillInput(skillKey: key, title: key.capitalized, category: .standard)
    }

    /// Two units with the cursor mid-way through the first, so the second offers "Skip ahead".
    public static func readyState() -> PathState {
        let units = [
            PathUnitInput(
                unitKey: "u1",
                title: "Unit 1: Greetings",
                standardPositions: [
                    PathPositionInput(skills: [skill("hello")]),
                    PathPositionInput(skills: [skill("food"), skill("drinks")]),
                    PathPositionInput(skills: [skill("numbers")]),
                    PathPositionInput(skills: [skill("family")]),
                ],
                otherSkills: []
            ),
            PathUnitInput(
                unitKey: "u2",
                title: "Unit 2: Travel",
                standardPositions: [
                    PathPositionInput(skills: [skill("trains")]),
                    PathPositionInput(skills: [skill("hotels")]),
                ],
                otherSkills: []
            ),
        ]
        var state = PathState()
        state.setBootstrap(BootstrapResponse(
            course: CourseRef(code: "ja", version: 1, manifestSha256: "x"),
            position: PositionRef(unitKey: "u1", skillKey: "numbers"),
            graders: [],
            enrolledCourseCodes: ["ja"],
            onboardingComplete: true
        ))
        state.setContent(PathContent(units: units))
        state.setDailyGoal(goal: 50, days: [], today: "2026-01-01")
        return state
    }

    public static let header = PathHeaderInfo(courseName: "Japanese", streakDays: 12, totalXp: 340)
}

/// The three bodies the Path screen can show, rendered the way the app does. Used by the app's snapshot tests.
public struct PathScreenShowcase: View {
    private let page: PathScreenPage
    private let rtl: Bool

    public init(page: PathScreenPage, rtl: Bool = false) {
        self.page = page
        self.rtl = rtl
    }

    public var body: some View {
        screen
            .environment(\.layoutDirection, rtl ? .rightToLeft : .leftToRight)
    }

    @ViewBuilder
    private var screen: some View {
        switch page {
        case .ready:
            PathScreenView(state: PathScreenFixtures.readyState(), header: PathScreenFixtures.header)
        case .downloading:
            PathScreenView(
                state: PathScreenFixtures.readyState(),
                download: .downloading(done: 12, total: 40),
                header: PathScreenFixtures.header
            )
        case .failed:
            PathScreenView(
                state: PathScreenFixtures.readyState(),
                download: .failed,
                header: PathScreenFixtures.header
            )
        }
    }
}
