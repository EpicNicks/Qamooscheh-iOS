import Foundation

// When reminders fire and when they back off (Android ReminderSchedule.kt). Pure, so the rules are tested without
// UserNotifications.

/// The streak-at-risk nudge's time: late evening, before most people's day ends.
public let streakNudgeHour = 21
public let streakNudgeMinute = 30

/// Reminders ignored in a row before they drop to every other day.
public let reminderBackoffThreshold = 7

/// Reminders ignored in a row before they stop, with one last notice.
public let reminderStopThreshold = 14

private let reenableDelayMillis: Int64 = 24 * 60 * 60 * 1000

/// ISO weekday of `date` in `calendar`: 1 = Monday ... 7 = Sunday.
public func isoWeekday(_ date: Date, calendar: Calendar) -> Int {
    (calendar.component(.weekday, from: date) + 5) % 7 + 1
}

/// The next time after `now` on one of `days` (ISO weekdays) at `hour`:`minute` in `calendar`'s zone. A wall-clock time
/// that doesn't exist that day (a spring-forward gap) moves to the next real instant. Nil when no day is picked.
public func nextReminderOccurrence(after now: Date, hour: Int, minute: Int, days: Set<Int>, calendar: Calendar) -> Date? {
    if days.isEmpty { return nil }
    let startOfToday = calendar.startOfDay(for: now)
    for offset in 0...8 {
        guard let day = calendar.date(byAdding: .day, value: offset, to: startOfToday),
              let candidate = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day, matchingPolicy: .nextTime)
        else { continue }
        if candidate > now && days.contains(isoWeekday(day, calendar: calendar)) { return candidate }
    }
    return nil
}

/// The streak nudge only makes sense after the daily reminder, so it's skipped when that's already late.
public func streakNudgeApplies(reminderHour: Int, reminderMinute: Int) -> Bool {
    reminderHour * 60 + reminderMinute < streakNudgeHour * 60 + streakNudgeMinute - 60
}

/// Which daily reminder to send, from what the learner has done today.
public enum DailyReminder: Equatable, Sendable {
    /// Nothing practiced yet today. `streakDays` is a streak today would keep, or 0.
    case start(streakDays: Int)
    /// Practiced today, goal not met yet. `xpLeft` is nil when today's XP or the goal couldn't be read.
    case goal(xpLeft: Int?)
    /// Today's goal is met: encouragement to keep going.
    case keepGoing

    /// The notification's title and body.
    public var text: (title: String, body: String) {
        switch self {
        case .start(let streakDays):
            return ("Time for today's practice", streakDays > 0 ? "Keep your \(streakDays)-day streak going." : "A few minutes is all it takes.")
        case .goal(let xpLeft):
            return (xpLeft.map { "You're \($0) XP from today's goal" } ?? "You're partway to today's goal", "Another Parsle gets you there.")
        case .keepGoing:
            return ("Today's goal is done", "On a roll? Another Parsle keeps it going.")
        }
    }
}

/// The daily reminder for today, or nil when it is skipped: `smartSuppression` skips it only once today's XP goal is
/// met. `practicedToday` comes from the streak's own "today" (a streak that failed to refresh is "not practiced");
/// `xpToday` and `goalXp` are nil when they couldn't be read, and then the goal never counts as met. `streakDays` is the
/// streak today would keep, or 0.
public func dailyReminder(smartSuppression: Bool, practicedToday: Bool, xpToday: Int?, goalXp: Int?, streakDays: Int) -> DailyReminder? {
    var xpLeft: Int?
    if let xp = xpToday, let goal = goalXp, goal > 0 { xpLeft = max(0, goal - xp) }
    if xpLeft == 0 { return smartSuppression ? nil : .keepGoing }
    if practicedToday || (xpToday ?? 0) > 0 { return .goal(xpLeft: xpLeft) }
    return .start(streakDays: streakDays)
}

public enum BackoffStep: Equatable, Sendable {
    case send, skip, stop
}

/// After `reminderBackoffThreshold` ignored reminders, only every other day sends; at `reminderStopThreshold` they stop.
public func backoffStep(ignoredInARow: Int, epochDay: Int) -> BackoffStep {
    if ignoredInARow >= reminderStopThreshold { return .stop }
    if ignoredInARow >= reminderBackoffThreshold && epochDay % 2 == 1 { return .skip }
    return .send
}

/// Days since 1970-01-01 of `date`'s calendar day in `calendar`'s zone.
public func epochDay(of date: Date, calendar: Calendar) -> Int {
    let parts = calendar.dateComponents([.year, .month, .day], from: date)
    var utc = Calendar(identifier: .gregorian)
    utc.timeZone = TimeZone(identifier: "UTC")!
    let midnight = utc.date(from: parts) ?? date
    return Int((midnight.timeIntervalSince1970 / 86_400).rounded(.down))
}

/// Whether to ask "Want daily reminders back on?" now: reminders are off, it's been a day since they were turned off,
/// the learner hasn't said "don't ask again", and any "remind me tomorrow" has passed.
public func reenablePromptDue(enabled: Bool, disabledAt: Int64?, nextAskAt: Int64?, neverAsk: Bool, nowMillis: Int64) -> Bool {
    guard !enabled, !neverAsk, let disabledAt = disabledAt else { return false }
    if nowMillis - disabledAt < reenableDelayMillis { return false }
    guard let nextAskAt = nextAskAt else { return true }
    return nowMillis >= nextAskAt
}

/// "Remind me tomorrow": the next time to ask.
public func nextReenableAsk(nowMillis: Int64) -> Int64 { nowMillis + reenableDelayMillis }
