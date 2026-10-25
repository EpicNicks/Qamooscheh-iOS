import Foundation
import QNetwork

/// Placeholder wording for the Stow dialogs and errors, in one place until the owner approves it.
public enum StowCopy {
    public static let actionLabel = "Stow"

    public static let confirmTitle = "Stow this lesson?"
    public static let confirmBody = "Stowing sets this lesson aside and moves you on to the next one. You can come back to it later, and we will remind you."
    public static let confirmAction = "Stow"
    public static let confirmCancel = "Not now"

    public static let encouragedTitle = "Stowed"
    public static let encouragedBody = "Good call. Keep going, and you will be ready for it later."
    public static let encouragedContinue = "Continue"

    public static let declinedTitle = "You got this!"
    public static let declinedBody = "Give it another go whenever you are ready."
    public static let declinedClose = "Close"
    public static let declinedRetry = "Retry Lesson"

    public static let reminderTitle = "Ready to retry?"
    public static let reminderNotYet = "Not yet"

    public static let genericStowError = "Couldn't stow this lesson."
    public static let reminderError = "Couldn't save that. Try again."

    /// What went wrong with a stow, in words. Each contract refusal means the path on screen was stale.
    public static func message(for error: Error) -> String {
        if let stow = error as? StowError {
            switch stow {
            case .noFailedAttempt:
                return "This lesson can't be stowed any more. Your path has been refreshed."
            case .alreadyCleared:
                return "You've already passed this lesson."
            case .alreadyDropped, .unknownLesson:
                return "This lesson is no longer on your path."
            case .notCurrentPosition, .notProvisioned:
                return "Your path has moved on. It has been refreshed."
            case .invalidRequest:
                return genericStowError
            }
        }
        let text = (error as? LocalizedError)?.errorDescription ?? ""
        return text.isEmpty ? genericStowError : text
    }

    /// Whether the held path was stale, so it should be refreshed after this refusal.
    static func staleState(_ error: Error) -> Bool {
        guard let stow = error as? StowError else { return false }
        return stow != .invalidRequest
    }
}
