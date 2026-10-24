import Foundation
import Combine
import QModel
import QDomain

/// The device-local Stow reminders setting (stow-reminder-pref): defaults on, never synced.
public protocol StowReminderPrefs: Sendable {
    func isEnabled() -> Bool
    func setEnabled(_ enabled: Bool)
}

public final class UserDefaultsStowReminderPrefs: StowReminderPrefs, @unchecked Sendable {
    public static let key = "stowRemindersEnabled"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func isEnabled() -> Bool {
        defaults.object(forKey: Self.key) == nil ? true : defaults.bool(forKey: Self.key)
    }

    public func setEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Self.key)
    }
}

/// A unit's stowed lessons as the reminder lists them.
public struct StowageGroup: Equatable, Sendable {
    public var unitKey: String
    public var unitTitle: String
    public var lessons: [PathSkill]

    public init(unitKey: String, unitTitle: String, lessons: [PathSkill]) {
        self.unitKey = unitKey
        self.unitTitle = unitTitle
        self.lessons = lessons
    }
}

/// The Stowage laid out for the reminder (stow-stowage-list): grouped by unit, in the order the server
/// returned (units descending, lessons in path order). A lesson the loaded course lacks is left out, and
/// so is a unit left empty.
public func stowageGroups(_ stowage: [StowageUnit], path: [PathUnit]) -> [StowageGroup] {
    var groups: [StowageGroup] = []
    for stowed in stowage {
        guard let unit = path.first(where: { $0.unitKey == stowed.unitKey }) else { continue }
        let skills = unit.standardPositions.flatMap { $0.skills }
        let lessons = stowed.lessons.compactMap { entry in skills.first(where: { $0.skillKey == entry.lessonKey }) }
        if !lessons.isEmpty {
            groups.append(StowageGroup(unitKey: unit.unitKey, unitTitle: unit.title, lessons: lessons))
        }
    }
    return groups
}

/// The "ready to retry?" reminder. SwiftUI-free.
@MainActor
public final class StowReminderModel: ObservableObject {
    @Published public private(set) var busy = false
    @Published public private(set) var error: String?
    /// Put away for now (back or outside tap): quiet until the model is rebuilt; nothing is sent.
    @Published public private(set) var dismissed = false

    private let service: StowService
    private let prefs: StowReminderPrefs
    private let host: StowStateHost

    public init(service: StowService, prefs: StowReminderPrefs, host: StowStateHost) {
        self.service = service
        self.prefs = prefs
        self.host = host
    }

    /// Any stowed lesson is due its reminder.
    public var readyPromptDue: Bool {
        host.stowage.contains(where: { unit in unit.lessons.contains(where: { $0.readyPromptDue }) })
    }

    /// Shown when something is due and the device setting is on.
    public var isShown: Bool {
        readyPromptDue && prefs.isEnabled() && !dismissed
    }

    /// The reminder's list, grouped by unit as the server returned it.
    public func groups(path: [PathUnit]) -> [StowageGroup] {
        stowageGroups(host.stowage, path: path)
    }

    /// "Not yet": the server asks again after three more journey lessons. The setting is untouched.
    public func notYet() async {
        await answer { try await self.service.snoozeStowage() }
    }

    /// The X: reminders stop for the lessons in the Stowage now. The setting is untouched.
    public func mute() async {
        await answer { try await self.service.muteStowage() }
    }

    public func putAway() {
        dismissed = true
    }

    private func answer(_ call: () async throws -> StowageResponse) async {
        if busy { return }
        busy = true
        error = nil
        do {
            let response = try await call()
            host.applyStowage(response.stowage, position: nil)
        } catch {
            self.error = StowCopy.reminderError
        }
        busy = false
    }
}
