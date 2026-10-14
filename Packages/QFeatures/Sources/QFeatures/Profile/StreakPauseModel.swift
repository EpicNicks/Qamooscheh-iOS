import Foundation
import QModel
import QNetwork
import QData
import QDomain

/// Why a pause window can't be booked, or nil when it can. The server re-checks all of this;
/// this only keeps an obviously bad request off the wire (Android SettingsScreen bounds the picker the same way).
public func streakPauseProblem(streak: StreakResponse, startDay: String, days: Int, now: Date) -> String? {
    guard streakDayDate(startDay) != nil, streakDayString(streakDayDate(startDay)!) == startDay else {
        return "Pick a valid start day."
    }
    if days < 1 { return "Pause for at least 1 day." }
    let maxLength = maxPauseLength(streak)
    if maxLength < 1 { return "You've used all your pause days for this year." }
    if days > maxLength { return "You can pause for at most \(formatStreakDays(maxLength))." }
    let today = streakToday(streak, now: now)
    if startDay < today { return "A pause can't start in the past." }
    if startDay > addDays(today, maxPauseLeadDays) { return "A pause can start at most \(maxPauseLeadDays) days from now." }
    return nil
}

/// Pause state for the Settings Streak section (Android SettingsViewModel pauseStreak/cancelStreakPause):
/// the streak, whether a booking or cancel is in flight, and the last error.
@MainActor
public final class StreakPauseModel: ObservableObject {
    @Published public private(set) var streak: StreakResponse?
    @Published public private(set) var busy = false
    @Published public private(set) var error: String?

    /// Pause days left this year; 0 until the streak loads.
    public var pauseDaysAvailable: Int { streak?.pauseDaysAvailable ?? 0 }
    /// The current (started) or upcoming pause, if any.
    public var pause: StreakPauseResponse? { streak?.pause }

    private let service: StreakService?
    private let now: @Sendable () -> Date

    public init(service: StreakService?, now: @escaping @Sendable () -> Date = { Date() }) {
        self.service = service
        self.now = now
    }

    /// Replaces the streak without any network (previews).
    public func seed(_ streak: StreakResponse?) {
        self.streak = streak
    }

    public func load() async {
        guard let service = service else { return }
        if let fresh = try? await service.fetch() { streak = fresh }
    }

    /// Books a pause of `days` days from `startDay` ("yyyy-MM-dd").
    public func book(startDay: String, days: Int) async {
        guard let service = service, !busy else { return }
        if let current = streak, let problem = streakPauseProblem(streak: current, startDay: startDay, days: days, now: now()) {
            error = problem
            return
        }
        guard days >= 1 else { return }
        await write(fallback: "Couldn't pause your streak.") {
            try await service.pause(StreakPauseRequest(startDay: startDay, endDay: addDays(startDay, days - 1)))
        }
    }

    /// Cancels the upcoming pause, or ends the running one (today stays covered).
    public func cancel() async {
        guard let service = service, !busy else { return }
        await write(fallback: "Couldn't cancel the pause.") {
            try await service.cancelPause()
        }
    }

    private func write(fallback: String, _ call: () async throws -> Void) async {
        busy = true
        error = nil
        do {
            try await call()
        } catch {
            self.error = AuthRules.message(for: error, fallback: fallback)
        }
        // A 404/409 means this copy was stale, so refetch on every outcome, like Android.
        await load()
        busy = false
    }
}

/// Wires the StreakService seam to the repository. A cancel that finds no pause (404) is a no-op.
extension StreakRepository: StreakService {
    public func fetch() async throws -> StreakResponse {
        try await streak()
    }

    public func pause(_ request: StreakPauseRequest) async throws {
        _ = try await bookPause(request)
    }

    public func cancelPause() async throws {
        _ = try await endPause()
    }
}
