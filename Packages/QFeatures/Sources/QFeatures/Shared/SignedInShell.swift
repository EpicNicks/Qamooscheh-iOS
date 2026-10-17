import Foundation
import SwiftUI
import QModel
import QDomain
import QNetwork

/// The signed-in app's shared state: the models behind each tab, the active course, and the numbers the Path header shows.
/// With no `app` (previews, snapshot tests) every model is built without a service and shows its empty state.
@MainActor
public final class SignedInShell: ObservableObject {
    public let app: AppEnvironment?
    public let onboarding: OnboardingService?

    @Published public private(set) var userId: String?
    @Published public private(set) var bootstrap: BootstrapResponse?
    @Published public private(set) var course: CourseRef?
    @Published public private(set) var catalog: [CourseCatalogEntry] = []
    @Published public private(set) var streak: StreakResponse?
    /// Every XP earned in the active course; nil until the activity has loaded once.
    @Published public private(set) var totalXp: Int?
    @Published public private(set) var goal: DailyGoalProgress?

    public let profile: ProfileModel
    public let library: LibraryModel
    public let leagues: LeaguesModel
    public let friends: FriendsModel
    public let contactsMatching: ContactsMatchingModel
    public let vocabulary: VocabularyStore
    public let flashcards: FlashcardsModel

    /// Called when a request answers 401; models built later (saved practice) report it here.
    public let unauthorizedHandler: @Sendable () -> Void
    private let onSignedOut: @MainActor @Sendable () -> Void

    /// Holds the signed-in user's id for the leagues model, which reads it on every refresh.
    @MainActor
    private final class ViewerBox {
        var id: String?
    }

    private let viewer: ViewerBox
    /// The course whose activity `totalXp` and `goal` describe.
    private var activityCourse: String?
    /// The course the course-bound models last loaded for.
    private var modelsCourse: String??

    public init(
        app: AppEnvironment?,
        onboarding: OnboardingService? = nil,
        onSignedOut: @escaping @MainActor @Sendable () -> Void = {}
    ) {
        let box = ViewerBox()
        self.viewer = box
        self.app = app
        self.onboarding = onboarding
        self.onSignedOut = onSignedOut
        // An expired session forgets the user's local prefs and card mirror, like an explicit sign-out.
        let unauthorized: @Sendable () -> Void = {
            Task { @MainActor in
                if let env = app, let id = box.id { await env.forgetUser(id) }
                onSignedOut()
            }
        }
        var signOut: (@Sendable () async throws -> Void)?
        if let env = app {
            signOut = { @Sendable () async throws -> Void in
                await env.signOut()
                await MainActor.run { onSignedOut() }
            }
        }
        self.unauthorizedHandler = unauthorized
        self.profile = ProfileModel(
            service: app?.profile, streakService: app?.streak, signOut: signOut, onUnauthorized: unauthorized)
        self.library = LibraryModel(source: app?.themes, onUnauthorized: unauthorized)
        self.friends = FriendsModel(service: app?.friends, onUnauthorized: unauthorized)
        self.contactsMatching = ContactsMatchingModel(
            service: app?.contacts, reader: app?.contactEmails, onUnauthorized: unauthorized)
        let store = VocabularyStore(source: app?.vocabulary, onUnauthorized: unauthorized)
        self.vocabulary = store
        self.flashcards = FlashcardsModel(store: store, submitter: app?.flashcards, onUnauthorized: unauthorized)
        self.leagues = LeaguesModel(service: app?.leagues, viewerId: { box.id }, onUnauthorized: unauthorized)
    }

    public var streakDays: Int { streak?.currentStreakDays ?? 0 }

    /// The active course's name for the header: the catalog's Latin name, else the upper-cased code.
    public var courseName: String {
        guard let code = course?.code else { return "Pick a course" }
        return catalog.first { $0.code == code }?.latinName ?? code.uppercased()
    }

    /// Loads the user, bootstrap, streak, activity and daily goal. Safe to call again; a failed call keeps the last good values.
    public func refresh() async {
        guard let app = app else { return }
        let uid = await app.currentUserId()
        userId = uid
        viewer.id = uid
        do {
            apply(try await app.bootstrap())
        } catch {
            await noteFailure(error)
            // Offline: the last pin this user saw, so the header and screens still know the course.
            if course == nil, let cached = try? await app.pinnedCourse() { course = cached }
        }
        if let onboarding = onboarding, catalog.isEmpty, let entries = try? await onboarding.catalog() {
            catalog = entries
        }
        do {
            streak = try await app.streak.fetch()
        } catch {
            await noteFailure(error)
        }
        var days: [ActivityDay]?
        var goalXp: Int?
        if let active = course {
            do {
                days = try await app.activity(active.code)
            } catch {
                await noteFailure(error)
            }
            if let user = uid {
                let sync = app.makePrefsSync(user, active.code)
                _ = try? await sync.sync()
                goalXp = await sync.prefs?.dailyGoalXp
            }
        }
        // A failed fetch keeps the last values only for the same course; after a switch they show as unknown.
        let sameCourse = course?.code == activityCourse
        if let loaded = days {
            totalXp = QDomain.totalXp(loaded)
            activityCourse = course?.code
        } else if !sameCourse {
            totalXp = nil
            goal = nil
        }
        if days != nil || sameCourse { goal = makeGoal(days: days, goalXp: goalXp, fallback: sameCourse ? goal : nil) }
        let keepContext = sameCourse
        profile.context = ProfileContext(
            courseCode: course?.code,
            enrolledCount: bootstrap?.enrolledCourseCodes.count ?? 0,
            activity: days ?? (keepContext ? profile.context.activity : []),
            dailyGoalXp: goalXp ?? (keepContext ? profile.context.dailyGoalXp : nil))
        if modelsCourse == nil || modelsCourse! != course?.code {
            let switched = modelsCourse != nil
            modelsCourse = .some(course?.code)
            if switched { await reloadCourseModels() }
        }
    }

    /// `fallback` is what stands when the goal can't be computed: the last goal on the same course, nil after a switch.
    func makeGoal(days: [ActivityDay]?, goalXp: Int?, fallback: DailyGoalProgress?) -> DailyGoalProgress? {
        guard let days = days, let goalXp = goalXp, goalXp > 0 else { return fallback }
        let today: String
        if let streak = streak {
            today = currentStreakDay(streak, now: Date())
        } else {
            today = todayLocalDay(now: Date(), calendar: .current)
        }
        return DailyGoalProgress(xp: xpToday(days, today: today), goal: goalXp)
    }

    private func noteFailure(_ error: Error) async {
        guard isUnauthorizedError(error) else { return }
        if let id = viewer.id { await app?.forgetUser(id) }
        onSignedOut()
    }

    /// Reloads the screens that read the active course from disk, so none keeps the previous course's content.
    private func reloadCourseModels() async {
        library.resetForCourseSwitch()
        vocabulary.resetForCourseSwitch()
        await library.refresh()
        await vocabulary.refresh()
    }

    /// Takes a bootstrap from the server or the course switcher.
    public func apply(_ response: BootstrapResponse) {
        bootstrap = response
        course = response.course
    }

    /// A course switcher on the current bootstrap; `onSwitched` runs after each change the server accepts.
    public func makeSwitcherModel(onSwitched: @escaping @MainActor () -> Void = {}) -> CourseSwitcherModel? {
        guard let onboarding = onboarding, let current = bootstrap else { return nil }
        return CourseSwitcherModel(service: onboarding, bootstrap: current, onBootstrap: { [weak self] next in
            self?.apply(next)
            onSwitched()
            Task { await self?.refresh() }
        })
    }

    /// A Settings model for the signed-in user and active course; nil with no user or no course.
    public func makeSettingsModel() async -> SettingsModel? {
        guard let app = app else { return nil }
        var uid = userId
        if uid == nil { uid = await app.currentUserId() }
        var active = course
        if active == nil { active = try? await app.pinnedCourse() }
        guard let user = uid, let pinned = active else { return nil }
        let after = onSignedOut
        return app.makeSettingsModel(
            userId: user, course: pinned, accountName: profile.form?.displayName,
            afterSignOut: { await MainActor.run { after() } })
    }

    /// Stops a playing voice sample; call when Settings is left.
    public func stopVoicePreview() {
        app?.stopVoicePreview()
    }
}
