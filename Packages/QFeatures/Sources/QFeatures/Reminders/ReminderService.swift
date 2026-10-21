import Foundation
import QDomain

/// Keeps each signed-in learner's reminder settings and schedules their notifications. Settings are stored per user and a
/// plan is always built for an explicit user, so one learner's reminders never read another's settings.
public actor ReminderService {
    private let center: ReminderCenter
    private let defaults: UserDefaults
    private let calendar: @Sendable () -> Calendar
    private let now: @Sendable () -> Date
    private var contexts: [String: ReminderContext] = [:]
    /// Kept alive for as long as the service: the notification center holds its delegate weakly.
    private var retained: [AnyObject] = []

    public init(
        center: ReminderCenter,
        defaults: UserDefaults = .standard,
        calendar: @escaping @Sendable () -> Calendar = { .current },
        now: @escaping @Sendable () -> Date = { Date() },
        retaining: [AnyObject] = []
    ) {
        self.center = center
        self.defaults = defaults
        self.calendar = calendar
        self.now = now
        self.retained = retaining
    }

    /// The learner's stored settings; defaults for a user who never set any.
    public nonisolated func settings(userId: String) -> ReminderSettings {
        guard let data = defaults.data(forKey: ReminderService.key(userId)),
              let stored = try? JSONDecoder().decode(StoredSettings.self, from: data) else { return ReminderSettings() }
        return stored.settings
    }

    /// Saves the learner's settings and replans their notifications.
    public func apply(_ settings: ReminderSettings, userId: String) async {
        guard !userId.isEmpty, let data = try? JSONEncoder().encode(StoredSettings(settings)) else { return }
        defaults.set(data, forKey: ReminderService.key(userId))
        await reschedule(userId: userId)
    }

    /// The app opened (or came back) with fresh facts about today: drop whatever was scheduled, whoever's it was, and
    /// plan this learner's reminders. Opening the app is also what restarts the back-off.
    public func refresh(userId: String, context: ReminderContext) async {
        guard !userId.isEmpty else { return }
        contexts[userId] = context
        await reschedule(userId: userId)
    }

    /// Sign-out: nothing scheduled or showing outlives the account that asked for it.
    public func cancelAll() async {
        contexts = [:]
        await center.removeAllReminders()
    }

    public nonisolated func requestPermission() async -> Bool { await center.requestAuthorization() }

    public nonisolated func authorization() async -> ReminderAuthorization { await center.authorization() }

    private func reschedule(userId: String) async {
        await center.removeAllReminders()
        let stored = settings(userId: userId)
        guard stored.enabled, await center.authorization() != .denied else { return }
        let zone = calendar()
        let plan = ReminderPlanner.plan(userId: userId, settings: stored, context: contexts[userId], now: now(), calendar: zone)
        await center.schedule(plan, calendar: zone)
    }

    private static func key(_ userId: String) -> String { "reminders.\(userId)" }

    private struct StoredSettings: Codable {
        var enabled: Bool
        var hour: Int
        var minute: Int
        var days: [Int]
        var smartSuppression: Bool
        var streakNudge: Bool

        init(_ s: ReminderSettings) {
            enabled = s.enabled
            hour = s.hour
            minute = s.minute
            days = s.days.sorted()
            smartSuppression = s.smartSuppression
            streakNudge = s.streakNudge
        }

        var settings: ReminderSettings {
            var s = ReminderSettings()
            s.enabled = enabled
            s.hour = min(23, max(0, hour))
            s.minute = min(59, max(0, minute))
            s.days = Set(days.filter { (1...7).contains($0) })
            s.smartSuppression = smartSuppression
            s.streakNudge = streakNudge
            return s
        }
    }
}

/// The Settings screen's view of the service: one learner's reminders.
public final class LiveReminderScheduler: ReminderScheduling, @unchecked Sendable {
    private let userId: String
    private let service: ReminderService

    public init(userId: String, service: ReminderService) {
        self.userId = userId
        self.service = service
    }

    public func current() -> ReminderSettings { service.settings(userId: userId) }

    public func requestPermission() async -> Bool { await service.requestPermission() }

    public func apply(_ settings: ReminderSettings) {
        let user = userId
        let service = self.service
        Task { await service.apply(settings, userId: user) }
    }
}
