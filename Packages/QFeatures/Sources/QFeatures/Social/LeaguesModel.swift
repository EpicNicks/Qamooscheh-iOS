import Foundation
import Combine
import QModel
import QNetwork
import QData

/// The league call the screen needs. `LeagueRepository` conforms; tests use a fake.
public protocol LeagueService: Sendable {
    func current() async throws -> CurrentLeagueResponse?
}

extension LeagueRepository: LeagueService {}

public struct StandingRow: Equatable, Sendable {
    public var rank: Int
    public var userId: String
    public var displayName: String?
    public var points: Int
    public var isMe: Bool
    /// Where this rank would land if the period ended now. Never `.demoted` on the floor tier.
    public var outcome: LeagueOutcome
}

public struct LeagueUi: Equatable, Sendable {
    public var tier: Int
    public var endsAt: Date
    public var rows: [StandingRow]
}

public enum LeaguesState: Equatable, Sendable {
    case loading
    /// A 404: new account, not yet active enough, or between a period's end and its rollover.
    case noLeague
    case failed(String)
    case ready(LeagueUi)
}

/// What the web shows for a competitor with no display name.
public let leagueUnnamed = "Unnamed learner"

/// Builds the rows; the viewer is matched case-insensitively (Android toUi).
public func makeLeagueUi(_ response: CurrentLeagueResponse, viewerId: String?) -> LeagueUi {
    let size = response.standings.count
    var rows: [StandingRow] = []
    for (index, standing) in response.standings.enumerated() {
        var outcome = LeagueSplit.outcome(rank: index + 1, cohortSize: size)
        if outcome == .demoted && response.tier <= LeagueSplit.floorTier { outcome = .held }
        let isMe = viewerId.map { $0.lowercased() == standing.userId.lowercased() } ?? false
        rows.append(StandingRow(
            rank: index + 1, userId: standing.userId, displayName: standing.displayName,
            points: standing.points, isMe: isMe, outcome: outcome))
    }
    return LeagueUi(tier: response.tier, endsAt: response.periodEndsAt, rows: rows)
}

/// Coarser the further off it is, so the text doesn't churn a day out (Android formatRemaining).
public func formatRemaining(seconds: Int) -> String {
    let minute = 60
    let hour = 60 * minute
    let day = 24 * hour
    if seconds <= 0 { return "This period has ended. Results are on the way." }
    if seconds >= day { return "\(seconds / day)d \(seconds % day / hour)h left" }
    if seconds >= hour { return "\(seconds / hour)h \(seconds % hour / minute)m left" }
    return "\(seconds / minute)m \(seconds % minute)s left"
}

/// State for the Leagues screen (web LeaguesPage + useCurrentLeague, Android LeaguesViewModel).
@MainActor
public final class LeaguesModel: ObservableObject {
    @Published public private(set) var state: LeaguesState = .loading

    private let service: LeagueService?
    private let viewerId: String?
    private let onUnauthorized: (@Sendable () -> Void)?
    private var generation = 0

    public init(service: LeagueService?, viewerId: String?, onUnauthorized: (@Sendable () -> Void)? = nil) {
        self.service = service
        self.viewerId = viewerId
        self.onUnauthorized = onUnauthorized
    }

    /// Safe on every appearance: a reload keeps the old standings up meanwhile, and only the newest call's result lands.
    public func refresh() async {
        guard let service = service else { return }
        generation += 1
        let mine = generation
        if case .ready = state {} else { state = .loading }
        do {
            let league = try await service.current()
            if mine != generation { return }
            if let league = league {
                state = .ready(makeLeagueUi(league, viewerId: viewerId))
            } else {
                state = .noLeague
            }
        } catch {
            if mine != generation { return }
            if (error as? ApiError)?.status == 401 || error is SessionExpiredError { onUnauthorized?() }
            state = .failed(AuthRules.message(for: error, fallback: "Couldn't load your league."))
        }
    }

    /// Seeds a screen without any network (snapshot showcases).
    public static func preview(_ state: LeaguesState) -> LeaguesModel {
        let model = LeaguesModel(service: nil, viewerId: nil)
        model.state = state
        return model
    }
}
