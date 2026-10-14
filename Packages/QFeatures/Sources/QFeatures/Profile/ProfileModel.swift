import Foundation
import Combine
import QModel
import QDomain
import QNetwork

/// What the Profile tab shows about the active course; the app pushes it in from bootstrap, prefs and activity.
public struct ProfileContext: Equatable, Sendable {
    public var courseCode: String?
    public var enrolledCount: Int
    /// The active course's activity.
    public var activity: [ActivityDay]
    public var dailyGoalXp: Int?

    public init(courseCode: String? = nil, enrolledCount: Int = 0, activity: [ActivityDay] = [], dailyGoalXp: Int? = nil) {
        self.courseCode = courseCode
        self.enrolledCount = enrolledCount
        self.activity = activity
        self.dailyGoalXp = dailyGoalXp
    }
}

/// State for the Profile tab (web ProfilePage, Android ProfileViewModel).
@MainActor
public final class ProfileModel: ObservableObject {
    @Published public private(set) var form: ProfileForm?
    @Published public private(set) var loadError: String?
    @Published public private(set) var saving = false
    @Published public private(set) var saved = false
    /// True after a save that finished while newer edits were pending: the earlier values are stored, the newer ones are not.
    @Published public private(set) var savedWithNewerEdits = false
    @Published public private(set) var saveError: String?
    @Published public private(set) var signingOut = false
    @Published public private(set) var signOutError: String?
    @Published public private(set) var streak: StreakResponse?
    @Published public var context: ProfileContext

    private let service: ProfileService?
    private let streakService: StreakService?
    private let signOutAction: (@Sendable () async throws -> Void)?
    private let onUnauthorized: (@Sendable () -> Void)?
    private var loadingProfile = false
    private var lastDayStartHour = 0

    public init(
        service: ProfileService?,
        streakService: StreakService? = nil,
        context: ProfileContext = ProfileContext(),
        signOut: (@Sendable () async throws -> Void)? = nil,
        onUnauthorized: (@Sendable () -> Void)? = nil
    ) {
        self.onUnauthorized = onUnauthorized
        self.service = service
        self.streakService = streakService
        self.context = context
        self.signOutAction = signOut
    }

    public var totalXpValue: Int { totalXp(context.activity) }

    /// Today's streak-day: the server's, advanced past `nextDayStartsAt` (Android currentStreakDay).
    /// Without a streak, the device date shifted by the last known day-start hour.
    public func today(now: Date) -> String {
        if let streak = streak { return currentStreakDay(streak, now: now) }
        return todayLocalDay(now: now.addingTimeInterval(-TimeInterval(lastDayStartHour * 3600)), calendar: .current)
    }

    /// Safe to call on every appearance: the streak is refreshed (a failure keeps the last good one) but the
    /// profile form is fetched only while there is none, so a typed draft is never replaced.
    public func load() async {
        if let streakService = streakService {
            if let fresh = try? await streakService.fetch() {
                streak = fresh
                lastDayStartHour = min(max(fresh.dayStartHour, 0), 23)
            }
        }
        if form == nil { await loadProfile() }
    }

    public func loadProfile() async {
        guard let service = service, form == nil, !loadingProfile else { return }
        loadingProfile = true
        loadError = nil
        do {
            let response = try await service.fetch()
            if form == nil { form = ProfileForm(response) }
        } catch {
            loadError = failureMessage(error, fallback: "Couldn't load your profile.")
        }
        loadingProfile = false
    }

    /// The server's message when there is one (Android userMessage); a 401 also reaches `onUnauthorized`.
    private func failureMessage(_ error: Error, fallback: String) -> String {
        if (error as? ApiError)?.status == 401 || error is SessionExpiredError { onUnauthorized?() }
        return AuthRules.message(for: error, fallback: fallback)
    }

    /// "Saved." describes the values as saved, so the next edit clears it (as on the web).
    public func edit(_ change: (inout ProfileForm) -> Void) {
        guard var next = form else { return }
        change(&next)
        form = next.clamped()
        saved = false
        savedWithNewerEdits = false
        saveError = nil
    }

    public func save() async {
        guard let current = form, !saving, let service = service else { return }
        if let message = profileFormError(current) {
            saveError = message
            return
        }
        saving = true
        saveError = nil
        saved = false
        savedWithNewerEdits = false
        do {
            let response = try await service.save(profileRequest(current))
            let stored = ProfileForm(response)
            if form == current {
                form = stored
                saved = true
            } else if let latest = form {
                // Adopt the server's values only for fields not edited during the PUT.
                form = ProfileForm(
                    displayName: latest.displayName == current.displayName ? stored.displayName : latest.displayName,
                    fullName: latest.fullName == current.fullName ? stored.fullName : latest.fullName,
                    country: latest.country == current.country ? stored.country : latest.country)
                savedWithNewerEdits = true
            }
        } catch {
            saveError = failureMessage(error, fallback: "Couldn't save your profile.")
        }
        saving = false
    }

    public func signOut() async {
        guard !signingOut, let action = signOutAction else { return }
        signingOut = true
        signOutError = nil
        do {
            try await action()
        } catch {
            signOutError = AuthRules.message(for: error, fallback: "Couldn't sign out.")
            signingOut = false
        }
        // On success stay "signing out" until the root swaps views, so a second tap cannot fire.
    }

    /// Seeds a loaded screen without any network (snapshot showcases).
    public static func preview(form: ProfileForm?, streak: StreakResponse?, context: ProfileContext) -> ProfileModel {
        let model = ProfileModel(service: nil, context: context)
        model.form = form
        model.streak = streak
        return model
    }
}
