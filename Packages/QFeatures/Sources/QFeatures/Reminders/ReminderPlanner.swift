import Foundation
import QDomain

/// What the planner knows about today. Unknown (nil context) is treated as "not practiced yet".
public struct ReminderContext: Equatable, Sendable {
    public var practicedToday: Bool
    public var pausedToday: Bool
    public var streakDays: Int
    public var goalMetToday: Bool
    /// Today's XP and the daily goal; nil when they couldn't be read (then the goal never counts as met).
    public var xpToday: Int?
    public var goalXp: Int?

    public init(
        practicedToday: Bool = false, pausedToday: Bool = false, streakDays: Int = 0, goalMetToday: Bool = false,
        xpToday: Int? = nil, goalXp: Int? = nil
    ) {
        self.xpToday = xpToday
        self.goalXp = goalXp
        self.practicedToday = practicedToday
        self.pausedToday = pausedToday
        self.streakDays = streakDays
        self.goalMetToday = goalMetToday
    }

    /// XP and goal for the decision. A caller that only knows the goal is met (`goalMetToday`) is honored.
    var effectiveGoal: Int? { goalMetToday ? (goalXp ?? 1) : goalXp }
    var effectiveXp: Int? { goalMetToday ? max(xpToday ?? 0, effectiveGoal ?? 1) : xpToday }

    /// Practiced or paused: today's streak is safe.
    public var safeToday: Bool { practicedToday || pausedToday }
}

public enum ReminderKind: String, Sendable {
    case daily, streak, stop
}

/// One local notification to schedule.
public struct PlannedReminder: Equatable, Sendable {
    public var id: String
    public var userId: String
    public var kind: ReminderKind
    public var fireAt: Date
    public var title: String
    public var body: String
}

/// Turns a user's reminder settings into the notifications to schedule. iOS runs no code when a local notification fires,
/// so what Android decides at fire time (suppression, back-off) is decided here, when the plan is made. The app reopening
/// replans, which is also what resets the back-off (Android `onAppOpened`).
public enum ReminderPlanner {
    /// Daily reminders looked ahead; the plan also stops at `maxPlanned` notifications (iOS keeps 64 pending).
    static let lookahead = 30
    static let maxPlanned = 40
    public static let idPrefix = "reminder."

    public static func plan(
        userId: String,
        settings: ReminderSettings,
        context: ReminderContext?,
        now: Date,
        calendar: Calendar
    ) -> [PlannedReminder] {
        guard settings.enabled, !settings.days.isEmpty else { return [] }
        let known = context ?? ReminderContext()

        var slots: [(date: Date, kind: ReminderKind)] = []
        var cursor = now
        for _ in 0..<lookahead {
            guard let next = nextReminderOccurrence(after: cursor, hour: settings.hour, minute: settings.minute, days: settings.days, calendar: calendar) else { break }
            slots.append((next, .daily))
            cursor = next
        }
        if settings.streakNudge && streakNudgeApplies(reminderHour: settings.hour, reminderMinute: settings.minute) {
            cursor = now
            for _ in 0..<lookahead {
                guard let next = nextReminderOccurrence(after: cursor, hour: streakNudgeHour, minute: streakNudgeMinute, days: settings.days, calendar: calendar) else { break }
                slots.append((next, .streak))
                cursor = next
            }
        }
        slots.sort { $0.date < $1.date }

        var planned: [PlannedReminder] = []
        var ignored = 0
        for slot in slots {
            if planned.count >= maxPlanned { break }
            let today = calendar.isDate(slot.date, inSameDayAs: now)
            var daily: DailyReminder?
            if slot.kind == .daily {
                if today {
                    daily = dailyReminder(
                        smartSuppression: settings.smartSuppression, practicedToday: known.practicedToday,
                        xpToday: known.effectiveXp, goalXp: known.effectiveGoal,
                        streakDays: known.streakDays > 0 && !known.safeToday ? known.streakDays : 0)
                    if daily == nil { continue }
                } else {
                    // Later days: nothing is practiced yet; the streak carries on if it is alive.
                    daily = .start(streakDays: known.streakDays)
                }
            } else {
                // A zero streak has nothing to keep; a practiced or paused day is already safe.
                if known.streakDays == 0 || (today && known.safeToday) { continue }
            }
            switch backoffStep(ignoredInARow: ignored, epochDay: epochDay(of: slot.date, calendar: calendar)) {
            case .skip:
                continue
            case .stop:
                planned.append(make(userId, .stop, slot.date, "We'll stop reminding you", "Turn reminders back on in Settings whenever you like."))
                return planned
            case .send:
                planned.append(content(userId, slot.kind, slot.date, known, daily))
                ignored += 1
            }
        }
        return planned
    }

    private static func content(_ userId: String, _ kind: ReminderKind, _ at: Date, _ ctx: ReminderContext, _ daily: DailyReminder?) -> PlannedReminder {
        if kind == .streak {
            return make(userId, .streak, at, "Keep your \(ctx.streakDays)-day streak going", "One short Parsle today keeps it alive.")
        }
        let text = (daily ?? .start(streakDays: 0)).text
        return make(userId, .daily, at, text.title, text.body)
    }

    private static func make(_ userId: String, _ kind: ReminderKind, _ at: Date, _ title: String, _ body: String) -> PlannedReminder {
        PlannedReminder(
            id: "\(idPrefix)\(userId).\(kind.rawValue).\(Int(at.timeIntervalSince1970))",
            userId: userId, kind: kind, fireAt: at, title: title, body: body)
    }
}
