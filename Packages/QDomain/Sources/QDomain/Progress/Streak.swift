import Foundation
import QModel

/// Mirrors the server's StreakPolicy. The server re-checks both; these only bound the picker.
public let maxPauseDays = 14
public let maxPauseLeadDays = 30

/// "1 day" / "12 days", for a count shown on its own without the word "streak".
public func formatStreakDays(_ days: Int) -> String {
    return days == 1 ? "1 day" : "\(days) days"
}

/// "3h 12m" / "45m" / "under a minute": time left until `deadline`, for a countdown.
public func formatTimeLeft(_ deadline: Date, now: Date) -> String {
    let minutes = Int((deadline.timeIntervalSince(now) / 60).rounded(.down))
    if minutes < 1 { return "under a minute" }
    let hours = minutes / 60
    return hours > 0 ? "\(hours)h \(minutes % 60)m" : "\(minutes)m"
}

/// "Practice in the next 3h 12m".
public func practiceToKeep(_ streak: StreakResponse, now: Date) -> String {
    return "Practice in the next \(formatTimeLeft(streak.nextDayStartsAt, now: now))"
}

/// The full sentence a compact display (the bare number) needs as its accessibility label.
public func describeStreak(_ streak: StreakResponse, now: Date) -> String {
    if streak.currentStreakDays == 0 { return "No streak yet. Finish a lesson today to start one." }
    let run = "\(streak.currentStreakDays)-day streak"
    if streak.practicedToday { return "\(run). You've practiced today." }
    if streak.pausedToday { return "\(run). Paused today, so it's safe." }
    return "\(run). \(practiceToKeep(streak, now: now)) to keep it going."
}

/// The zone the streak is counted in, or UTC for one this device can't resolve.
public func streakZone(_ streak: StreakResponse) -> TimeZone {
    return TimeZone(identifier: streak.timeZone) ?? TimeZone(identifier: "UTC")!
}

/// "3:00 AM": the wall-clock time a new streak-day starts (Android's dayStartHour rendering).
public func formatDayStart(_ streak: StreakResponse, locale: Locale) -> String {
    let hour = min(max(streak.dayStartHour, 0), 23)
    let formatter = DateFormatter()
    formatter.locale = locale
    formatter.timeZone = TimeZone(identifier: "UTC")
    formatter.dateStyle = .none
    formatter.timeStyle = .short
    return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(hour * 3600)))
}

/// "America/New_York" becomes "America/New York", for display.
public func formatZone(_ timeZone: String) -> String {
    return timeZone.replacingOccurrences(of: "_", with: " ")
}

private func dayFormatter(_ pattern: String, locale: Locale) -> DateFormatter {
    let formatter = DateFormatter()
    formatter.locale = locale
    formatter.timeZone = TimeZone(identifier: "UTC")
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.dateFormat = pattern
    return formatter
}

private func parseDay(_ day: String) -> Date? {
    guard day.count == 10 else { return nil }
    let formatter = dayFormatter("yyyy-MM-dd", locale: Locale(identifier: "en_US_POSIX"))
    formatter.isLenient = false
    return formatter.date(from: day)
}

/// Today's streak-day: the server's own `today`; when that does not parse, the calendar date in the
/// streak's zone `dayStartHour` hours ago (at 1am with a 3am day start, "today" is still yesterday).
public func streakToday(_ streak: StreakResponse, now: Date) -> String {
    if parseDay(streak.today) != nil { return streak.today }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = streakZone(streak)
    return todayLocalDay(now: now.addingTimeInterval(-TimeInterval(streak.dayStartHour * 3600)), calendar: calendar)
}

/// `day` ("yyyy-MM-dd") moved by `days`, as a plain calendar date; no time zone involved.
/// Returns `day` unchanged if it does not parse.
public func addDays(_ day: String, _ days: Int) -> String {
    guard let date = parseDay(day) else { return day }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    guard let moved = calendar.date(byAdding: .day, value: days, to: date) else { return day }
    return dayFormatter("yyyy-MM-dd", locale: Locale(identifier: "en_US_POSIX")).string(from: moved)
}

/// "Mon, Oct 5": a streak-day for display. A plain date, so no zone can shift it.
public func formatStreakDay(_ day: String, locale: Locale) -> String {
    guard let date = parseDay(day) else { return day }
    return dayFormatter("EEE, MMM d", locale: locale).string(from: date)
}

/// "Mon, Oct 5" or "Mon, Oct 5 – Fri, Oct 9".
public func formatStreakDayRange(_ start: String, _ end: String, locale: Locale) -> String {
    if start == end { return formatStreakDay(start, locale: locale) }
    return "\(formatStreakDay(start, locale: locale)) \u{2013} \(formatStreakDay(end, locale: locale))"
}

/// The longest pause the learner can book right now: the policy's cap, or what's left of their allowance.
public func maxPauseLength(_ streak: StreakResponse) -> Int {
    return max(min(maxPauseDays, streak.pauseDaysAvailable), 0)
}
