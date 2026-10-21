import Foundation
import QDomain

/// What the planner knows about today. Unknown (nil context) is treated as "not practiced yet".
public struct ReminderContext: Equatable, Sendable {
    public var practicedToday: Bool
    public var pausedToday: Bool
    public var streakDays: Int
    public var goalMetToday: Bool

    public init(practicedToday: Bool = false, pausedToday: Bool = false, streakDays: Int = 0, goalMetToday: Bool = false) {
        self.practicedToday = practicedToday
        self.pausedToday = pausedToday
        self.streakDays = streakDays
        self.goalMetToday = goalMetToday
    }

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
            if slot.kind == .daily {
                if today && dailyReminderSuppressed(smartSuppression: settings.smartSuppression, practicedToday: known.practicedToday, goalMet: known.goalMetToday) { continue }
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
                planned.append(content(userId, slot.kind, slot.date, known))
                ignored += 1
            }
        }
        return planned
    }

    private static func content(_ userId: String, _ kind: ReminderKind, _ at: Date, _ ctx: ReminderContext) -> PlannedReminder {
        if kind == .streak {
            return make(userId, .streak, at, "Keep your \(ctx.streakDays)-day streak going", "One short Parsle today keeps it alive.")
        }
        let body = ctx.streakDays > 0 && !ctx.safeToday
            ? "Keep your \(ctx.streakDays)-day streak going."
            : "A few minutes is all it takes."
        return make(userId, .daily, at, "Time for today's practice", body)
    }

    private static func make(_ userId: String, _ kind: ReminderKind, _ at: Date, _ title: String, _ body: String) -> PlannedReminder {
        PlannedReminder(
            id: "\(idPrefix)\(userId).\(kind.rawValue).\(Int(at.timeIntervalSince1970))",
            userId: userId, kind: kind, fireAt: at, title: title, body: body)
    }
}
