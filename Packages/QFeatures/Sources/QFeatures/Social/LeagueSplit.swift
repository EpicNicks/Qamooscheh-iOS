import Foundation

public enum LeagueOutcome: Equatable, Sendable {
    case promoted
    case held
    case demoted
}

/// The backend's Leagues/LeagueSplit.cs (via Android LeagueSplit), so the standings can show
/// the zones the period will be decided by. The server sends no zones, so this must agree with it:
/// 7 up and 3 down of a 13-member cohort, scaled for other sizes, each at least 1, with demotions
/// shrunk first when the two overlap.
public enum LeagueSplit {
    static let targetCohortSize = 13
    static let promotePerCohort = 7
    static let demotePerCohort = 3

    /// Tier 0 has no tier below it, so a demotion there is a hold.
    public static let floorTier = 0

    /// How many of a cohort of `cohortSize` promote and demote.
    public static func counts(cohortSize: Int) -> (promote: Int, demote: Int) {
        if cohortSize <= 0 { return (0, 0) }
        let promote = scale(cohortSize, promotePerCohort)
        var demote = scale(cohortSize, demotePerCohort)
        if promote + demote > cohortSize { demote = max(0, cohortSize - promote) }
        return (min(promote, cohortSize - demote), demote)
    }

    /// What a 1-based `rank` in a cohort of `cohortSize` earns, ignoring the floor.
    public static func outcome(rank: Int, cohortSize: Int) -> LeagueOutcome {
        let c = counts(cohortSize: cohortSize)
        if rank <= c.promote { return .promoted }
        if rank > cohortSize - c.demote { return .demoted }
        return .held
    }

    /// Half away from zero, like the server's MidpointRounding.AwayFromZero.
    private static func scale(_ cohortSize: Int, _ band: Int) -> Int {
        let raw = (Double(cohortSize) * Double(band) / Double(targetCohortSize)).rounded(.toNearestOrAwayFromZero)
        return min(cohortSize, max(1, Int(raw)))
    }
}
