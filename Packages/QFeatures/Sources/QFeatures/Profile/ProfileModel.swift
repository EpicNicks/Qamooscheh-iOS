import Foundation
import Combine
import QModel
import QDomain

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
    @Published public private(set) var saveError: String?
    @Published public private(set) var signingOut = false
    @Published public private(set) var signOutError: String?
    @Published public private(set) var streak: StreakResponse?
    @Published public var context: ProfileContext

    private let service: ProfileService?
    private let streakService: StreakService?
    private let signOutAction: (@Sendable () async throws -> Void)?

    public init(
        service: ProfileService?,
        streakService: StreakService? = nil,
        context: ProfileContext = ProfileContext(),
        signOut: (@Sendable () async throws -> Void)? = nil
    ) {
        self.service = service
        self.streakService = streakService
        self.context = context
        self.signOutAction = signOut
    }

    public var totalXpValue: Int { totalXp(context.activity) }

    /// Today's streak-day: the server's, not the device date.
    public func today(now: Date) -> String {
        if let streak = streak { return streakToday(streak, now: now) }
        return todayLocalDay(now: now, calendar: .current)
    }

    public func load() async {
        loadError = nil
        if let streakService = streakService {
            streak = try? await streakService.fetch()
        }
        await loadProfile()
    }

    public func loadProfile() async {
        guard let service = service else { return }
        loadError = nil
        do {
            form = ProfileForm(try await service.fetch())
        } catch {
            loadError = "Couldn't load your profile. Check your connection and try again."
        }
    }

    /// "Saved." describes the values as saved, so the next edit clears it (as on the web).
    public func edit(_ change: (inout ProfileForm) -> Void) {
        guard var next = form else { return }
        change(&next)
        form = next.clamped()
        saved = false
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
        do {
            let response = try await service.save(profileRequest(current))
            // Keep edits typed while the PUT was in flight; they are not what was saved.
            if form == current {
                form = ProfileForm(response)
                saved = true
            }
        } catch {
            saveError = "Couldn't save your profile."
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
            signOutError = "Couldn't sign out."
        }
        signingOut = false
    }

    /// Seeds a loaded screen without any network (snapshot showcases).
    public static func preview(form: ProfileForm?, streak: StreakResponse?, context: ProfileContext) -> ProfileModel {
        let model = ProfileModel(service: nil, context: context)
        model.form = form
        model.streak = streak
        return model
    }
}
