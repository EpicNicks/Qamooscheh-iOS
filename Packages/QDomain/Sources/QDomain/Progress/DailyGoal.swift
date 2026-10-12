import Foundation
import QModel

public struct DailyGoalPreset: Equatable, Sendable {
    public let xp: Int
    public let label: String

    public init(xp: Int, label: String) {
        self.xp = xp
        self.label = label
    }
}

/// The goal choices Settings offers, ascending. Any other value is a hand-entered custom goal.
public let dailyGoalPresets: [DailyGoalPreset] = [
    DailyGoalPreset(xp: 500, label: "Casual"),
    DailyGoalPreset(xp: 750, label: "Regular"),
    DailyGoalPreset(xp: 1000, label: "Serious"),
    DailyGoalPreset(xp: 1500, label: "Intense"),
]

/// The preset this value exactly matches, or nil for a hand-entered custom goal.
public func matchDailyGoalPreset(_ xp: Int) -> DailyGoalPreset? {
    return dailyGoalPresets.first { $0.xp == xp }
}

/// "yyyy-MM-dd" for `now` in the given calendar's time zone (the device's, when the caller passes `.current`).
public func todayLocalDay(now: Date, calendar: Calendar) -> String {
    let parts = calendar.dateComponents([.year, .month, .day], from: now)
    return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
}

/// Today's XP from the activity history, matched on `today` ("yyyy-MM-dd"); 0 when today has no activity yet.
public func xpToday(_ days: [ActivityDay], today: String) -> Int {
    return days.first { $0.localDay == today }?.xp ?? 0
}

/// Every XP earned in a course: the whole activity history summed.
public func totalXp(_ days: [ActivityDay]) -> Int {
    return days.reduce(0) { $0 + $1.xp }
}
