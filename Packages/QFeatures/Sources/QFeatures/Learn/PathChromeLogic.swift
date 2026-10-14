import Foundation

// Pure logic behind the Path header chrome (Android TopBarStats.DailyGoalCounter, PathHeader.JumpToCurrentButton).

/// "30/50" (Android compact counter: numbers only, no caption).
public func dailyGoalRingLabel(xp: Int, goal: Int) -> String {
    return "\(xp)/\(goal)"
}

/// Spoken form, as Android and web: "30 of 50 daily XP goal".
public func dailyGoalAccessibilityLabel(xp: Int, goal: Int) -> String {
    return "\(xp) of \(goal) daily XP goal"
}

/// Android DailyGoalCounter fills the ring when the goal is not positive (target 1f).
public func dailyGoalRingFraction(xp: Int, goal: Int) -> Double {
    if goal <= 0 { return 1 }
    return min(max(Double(xp) / Double(goal), 0), 1)
}

/// The celebration plays once per calendar day: when the goal is first reached, it is enabled,
/// and today's pulse has not already played (web lastGoalCelebrationDay).
public func shouldCelebrateGoal(reached: Bool, enabled: Bool, lastCelebratedDay: String?, today: String) -> Bool {
    return reached && enabled && lastCelebratedDay != today
}

/// Arrow rotation in degrees for the jump button: points up by default, down when the road is below.
public func jumpArrowRotation(_ direction: JumpDirection) -> Double {
    switch direction {
    case .up: return 0
    case .down: return 180
    }
}

/// "1,234" style grouping is locale-driven; the streak is shown as a plain integer.
public func streakLabel(_ days: Int) -> String {
    return "\(max(days, 0))"
}

/// The header's goal ring is 18.3pt (Android DailyGoalCounter), not 16pt.
public let dailyGoalRingSize: Double = 18.3

/// The celebration pulse scales the ring only when motion is allowed.
public func goalCelebrationAnimates(celebrating: Bool, reduceMotion: Bool) -> Bool {
    return celebrating && !reduceMotion
}

/// The header's lifetime XP counter.
public func totalXpLabel(_ xp: Int) -> String {
    return "\(max(xp, 0)) XP"
}

public func totalXpAccessibilityLabel(_ xp: Int) -> String {
    return "\(max(xp, 0)) total XP"
}
