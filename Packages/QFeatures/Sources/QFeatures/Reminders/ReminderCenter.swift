import Foundation
#if canImport(UserNotifications)
import UserNotifications
#endif

public enum ReminderAuthorization: Equatable, Sendable {
    case notDetermined, denied, granted
}

/// The slice of UNUserNotificationCenter the reminders use, so tests need no notification center.
public protocol ReminderCenter: Sendable {
    func authorization() async -> ReminderAuthorization
    /// Asks for permission; true when granted.
    func requestAuthorization() async -> Bool
    func schedule(_ reminders: [PlannedReminder], calendar: Calendar) async
    /// Removes every reminder this app scheduled, pending or already showing, whoever's it was.
    func removeAllReminders() async
}

/// Where a denied permission is re-enabled (the app's page in Settings).
public enum ReminderSettingsLink {
    public static let url = URL(string: "app-settings:")
}

/// Category of a reminder notification: its Start and Snooze actions.
public enum ReminderActions {
    public static let category = "reminder"
    public static let snooze = "snooze"
    public static let start = "start"
    public static let snoozeInterval: TimeInterval = 3600
}

/// Whether a notification may show for the signed-in account. A reminder belongs to the account that scheduled it.
public enum ReminderPolicy {
    public static func shouldPresent(reminderUserId: String?, currentUserId: String?) -> Bool {
        guard let owner = reminderUserId, !owner.isEmpty, let current = currentUserId else { return false }
        return owner == current
    }
}

#if canImport(UserNotifications)
public struct SystemReminderCenter: ReminderCenter, @unchecked Sendable {
    public static let userIdKey = "userId"
    public static let kindKey = "kind"

    private let center: UNUserNotificationCenter

    public init(center: UNUserNotificationCenter = .current()) {
        self.center = center
        let snooze = UNNotificationAction(identifier: ReminderActions.snooze, title: "Snooze 1h", options: [])
        let start = UNNotificationAction(identifier: ReminderActions.start, title: "Start Parsle", options: [.foreground])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: ReminderActions.category, actions: [start, snooze], intentIdentifiers: [], options: []),
        ])
    }

    public func authorization() async -> ReminderAuthorization {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        default: return .granted
        }
    }

    public func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    public func schedule(_ reminders: [PlannedReminder], calendar: Calendar) async {
        for reminder in reminders {
            await add(reminder, trigger: UNCalendarNotificationTrigger(
                dateMatching: calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: reminder.fireAt),
                repeats: false), calendar: calendar)
        }
    }

    /// A one-off reminder after `interval` (Snooze).
    public func scheduleAfter(_ reminder: PlannedReminder, interval: TimeInterval) async {
        await add(reminder, trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false), calendar: .current)
    }

    private func add(_ reminder: PlannedReminder, trigger: UNNotificationTrigger, calendar: Calendar) async {
        let content = UNMutableNotificationContent()
        content.title = reminder.title
        content.body = reminder.body
        content.sound = .default
        content.userInfo = [SystemReminderCenter.userIdKey: reminder.userId, SystemReminderCenter.kindKey: reminder.kind.rawValue]
        if reminder.kind != .stop { content.categoryIdentifier = ReminderActions.category }
        try? await center.add(UNNotificationRequest(identifier: reminder.id, content: content, trigger: trigger))
    }

    public func removeAllReminders() async {
        let pending = await center.pendingNotificationRequests().map { $0.identifier }.filter { $0.hasPrefix(ReminderPlanner.idPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending)
        let delivered = await center.deliveredNotifications().map { $0.request.identifier }.filter { $0.hasPrefix(ReminderPlanner.idPrefix) }
        center.removeDeliveredNotifications(withIdentifiers: delivered)
    }
}

/// Shows a reminder only for the account that scheduled it, and handles Snooze.
public final class ReminderNotificationDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    private let currentUserId: @Sendable () async -> String?
    private let center: SystemReminderCenter

    public init(center: SystemReminderCenter, currentUserId: @escaping @Sendable () async -> String?) {
        self.center = center
        self.currentUserId = currentUserId
    }

    public func userNotificationCenter(
        _ notificationCenter: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        let owner = notification.request.content.userInfo[SystemReminderCenter.userIdKey] as? String
        guard ReminderPolicy.shouldPresent(reminderUserId: owner, currentUserId: await currentUserId()) else { return [] }
        return [.banner, .sound]
    }

    public func userNotificationCenter(
        _ notificationCenter: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard response.actionIdentifier == ReminderActions.snooze else { return }
        let content = response.notification.request.content
        let owner = content.userInfo[SystemReminderCenter.userIdKey] as? String
        guard ReminderPolicy.shouldPresent(reminderUserId: owner, currentUserId: await currentUserId()), let owner = owner else { return }
        notificationCenter.removeDeliveredNotifications(withIdentifiers: [response.notification.request.identifier])
        let kind = ReminderKind(rawValue: content.userInfo[SystemReminderCenter.kindKey] as? String ?? "") ?? .daily
        let again = PlannedReminder(
            id: "\(ReminderPlanner.idPrefix)\(owner).snooze.\(Int(Date().timeIntervalSince1970))",
            userId: owner, kind: kind, fireAt: Date().addingTimeInterval(ReminderActions.snoozeInterval),
            title: content.title, body: content.body)
        await center.scheduleAfter(again, interval: ReminderActions.snoozeInterval)
    }
}
#endif
