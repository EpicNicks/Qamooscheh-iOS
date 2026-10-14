import Foundation
import QModel
import QDomain

/// The profile form's three fields, as typed (web ProfilePage, Android ProfileForm).
public struct ProfileForm: Equatable, Sendable {
    public var displayName: String
    public var fullName: String
    public var country: String

    public init(displayName: String = "", fullName: String = "", country: String = "") {
        self.displayName = displayName
        self.fullName = fullName
        self.country = country
    }

    public init(_ response: ProfileResponse) {
        self.init(displayName: response.displayName ?? "", fullName: response.fullName ?? "", country: response.country ?? "")
    }

    /// Backend ProfileService limits.
    public static let maxDisplayName = 40
    public static let maxFullName = 100
    public static let maxCountry = 2

    /// Fields capped at the backend limits; the country upper-cased.
    public func clamped() -> ProfileForm {
        ProfileForm(
            displayName: String(displayName.prefix(ProfileForm.maxDisplayName)),
            fullName: String(fullName.prefix(ProfileForm.maxFullName)),
            country: String(country.uppercased().prefix(ProfileForm.maxCountry)))
    }
}

/// The message for a form that cannot be saved, or nil when it can.
public func profileFormError(_ form: ProfileForm) -> String? {
    if form.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return "A display name is required."
    }
    let country = form.country.trimmingCharacters(in: .whitespacesAndNewlines)
    if !country.isEmpty && !isCountryCode(country) {
        return "Country must be a 2-letter code, e.g. US."
    }
    return nil
}

private func isCountryCode(_ text: String) -> Bool {
    let scalars = Array(text.unicodeScalars)
    return scalars.count == 2 && scalars.allSatisfy { $0.value >= 65 && $0.value <= 90 }
}

/// The PUT body for a valid form; blank optional fields are sent as null, which clears them.
public func profileRequest(_ form: ProfileForm) -> UpdateProfileRequest {
    func blankToNil(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
    return UpdateProfileRequest(
        displayName: form.displayName.trimmingCharacters(in: .whitespacesAndNewlines),
        fullName: blankToNil(form.fullName),
        country: blankToNil(form.country))
}

/// One bar of the activity chart.
public struct DayXp: Equatable, Sendable {
    public let day: String
    public let xp: Int

    public init(day: String, xp: Int) {
        self.day = day
        self.xp = xp
    }
}

/// The last `count` streak-days ending `today` ("yyyy-MM-dd"), oldest first, with 0 for days
/// without activity. Pass the server's streak-day, as for `xpToday`.
public func recentActivity(_ days: [ActivityDay], today: String, count: Int = 7) -> [DayXp] {
    var byDay: [String: Int] = [:]
    for d in days { byDay[d.localDay] = d.xp }
    var result: [DayXp] = []
    var back = count - 1
    while back >= 0 {
        let day = addDays(today, -back)
        result.append(DayXp(day: day, xp: byDay[day] ?? 0))
        back -= 1
    }
    return result
}

/// Bar height as a fraction of the chart: a sliver for zero days so every day has a mark.
public func barFraction(xp: Int, peak: Int) -> Double {
    let floorValue = xp > 0 ? 0.04 : 0.02
    let raw = Double(xp) / Double(max(peak, 1))
    return min(max(raw, floorValue), 1.0)
}

/// "Studying Persian and 2 more", or nil with no active course.
public func studyingLine(courseCode: String?, enrolledCount: Int) -> String? {
    guard let code = courseCode else { return nil }
    let name = Languages.languageInfo(code)?.displayName ?? code.uppercased()
    let others = enrolledCount - 1
    return "Studying \(name)" + (others > 0 ? " and \(others) more" : "")
}

/// Short weekday name for a "yyyy-MM-dd" day, e.g. "Mon".
public func weekdayShort(_ day: String, locale: Locale) -> String {
    guard let date = streakDayDate(day) else { return day }
    let formatter = DateFormatter()
    formatter.locale = locale
    formatter.timeZone = TimeZone(identifier: "UTC")
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.dateFormat = "EEE"
    return formatter.string(from: date)
}

/// GET/PUT /v1/profile. The app wires this to QNetwork later.
public protocol ProfileService: Sendable {
    func fetch() async throws -> ProfileResponse
    func save(_ request: UpdateProfileRequest) async throws -> ProfileResponse
}
