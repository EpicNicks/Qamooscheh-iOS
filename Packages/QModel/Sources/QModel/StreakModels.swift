import Foundation


/// Streak pause window; days are yyyy-MM-dd.
public struct StreakPauseResponse: Codable, Equatable, Sendable {
    public var startDay: String
    public var endDay: String
    public var started: Bool

    public init(startDay: String, endDay: String, started: Bool) {
        self.startDay = startDay
        self.endDay = endDay
        self.started = started
    }
}

/// POST /v1/streak/pause; days are yyyy-MM-dd.
public struct StreakPauseRequest: Codable, Equatable, Sendable {
    public var startDay: String
    public var endDay: String

    public init(startDay: String, endDay: String) {
        self.startDay = startDay
        self.endDay = endDay
    }
}

/// GET /v1/streak; today is yyyy-MM-dd.
public struct StreakResponse: Codable, Equatable, Sendable {
    public var currentStreakDays: Int
    public var longestStreakDays: Int
    public var practicedToday: Bool
    public var pausedToday: Bool
    public var pause: StreakPauseResponse?
    public var pauseDaysAvailable: Int
    public var timeZone: String
    public var dayStartHour: Int
    public var today: String
    public var nextDayStartsAt: Date

    public init(currentStreakDays: Int, longestStreakDays: Int, practicedToday: Bool, pausedToday: Bool, pause: StreakPauseResponse? = nil, pauseDaysAvailable: Int, timeZone: String, dayStartHour: Int, today: String, nextDayStartsAt: Date) {
        self.currentStreakDays = currentStreakDays
        self.longestStreakDays = longestStreakDays
        self.practicedToday = practicedToday
        self.pausedToday = pausedToday
        self.pause = pause
        self.pauseDaysAvailable = pauseDaysAvailable
        self.timeZone = timeZone
        self.dayStartHour = dayStartHour
        self.today = today
        self.nextDayStartsAt = nextDayStartsAt
    }
}

/// One daily_activity row; localDay is yyyy-MM-dd.
public struct ActivityDay: Codable, Equatable, Sendable {
    public var localDay: String
    public var reviews: Int
    public var xp: Int

    public init(localDay: String, reviews: Int, xp: Int) {
        self.localDay = localDay
        self.reviews = reviews
        self.xp = xp
    }
}

/// GET /v1/activity/{courseCode}.
public struct ActivityResponse: Codable, Equatable, Sendable {
    public var courseCode: String
    public var days: [ActivityDay]

    public init(courseCode: String, days: [ActivityDay]) {
        self.courseCode = courseCode
        self.days = days
    }
}
