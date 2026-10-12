import Foundation
import Combine

/// The intro tutorial's mock exercises, in order (Android TutorialPhase).
public enum TutorialPhase: Equatable, Sendable {
    case wordBank
    case typeIn
    case done
}

/// What a callout points at.
public enum TutorialTarget: Equatable, Sendable {
    case prompt
    case answer
    case submit
}

/// Which way the skip confirmation was opened; only its title differs.
public enum SkipSource: Equatable, Sendable {
    case link

    public var title: String { "Are you sure?" }
}

public struct TutorialCallout: Equatable, Sendable {
    public let target: TutorialTarget
    public let title: String
    public let description: String
}

public enum TutorialFeedback: Equatable, Sendable {
    case correct
    case wrong

    public var text: String {
        switch self {
        case .correct: return "Correct!"
        case .wrong: return "Not quite \u{2014} try again."
        }
    }
}

/// The intro tutorial's state (Android IntroTutorialState, web OnboardingTutorialStep):
/// a word bank, then a type-in, in plain English, retried until right, with callouts.
@MainActor
public final class OnboardingTutorialState: ObservableObject {
    @Published public private(set) var phase: TutorialPhase = .wordBank
    /// Indices into `wordBankTiles`, in the order they were placed.
    @Published public private(set) var chosen: [Int] = []
    @Published public private(set) var typed: String = ""
    @Published public private(set) var feedback: TutorialFeedback?
    /// Whether the callouts are still showing; their own skip only hides them.
    @Published public private(set) var guided = true
    @Published public private(set) var calloutIndex = 0
    /// Non-nil while the skip confirmation is open.
    @Published public var confirmingSkip: SkipSource?

    public init() {}

    public static let wordBankTiles = ["Hello", "Goodbye", "Thanks"]
    public static let wordBankAnswer = "Hello"
    public static let typeInAnswer = "Onward"

    private static let wordBankCallouts = [
        TutorialCallout(target: .prompt, title: "The prompt", description: "This tells you what to do for the exercise on screen."),
        TutorialCallout(target: .answer, title: "Word bank", description: "Tap the tiles, in order, to build your answer."),
        TutorialCallout(target: .submit, title: "Submit", description: "Once your answer looks right, tap here to check it."),
    ]
    private static let typeInCallouts = [
        TutorialCallout(target: .prompt, title: "The prompt", description: "Some exercises ask you to type instead of tapping tiles."),
        TutorialCallout(target: .answer, title: "Your answer", description: "Type your answer here."),
        TutorialCallout(target: .submit, title: "Submit", description: "Tap here (or press Return) when you are done."),
    ]

    public var callouts: [TutorialCallout] {
        switch phase {
        case .wordBank: return Self.wordBankCallouts
        case .typeIn: return Self.typeInCallouts
        case .done: return []
        }
    }

    public var callout: TutorialCallout? {
        guard guided, calloutIndex < callouts.count else { return nil }
        return callouts[calloutIndex]
    }

    public var isLastCallout: Bool { calloutIndex >= callouts.count - 1 }

    public func toggleTile(_ index: Int) {
        if let position = chosen.firstIndex(of: index) {
            chosen.remove(at: position)
        } else {
            chosen.append(index)
        }
        feedback = nil
    }

    public func type(_ text: String) {
        typed = text
        feedback = nil
    }

    /// Checks the current answer; `advance()` moves on once a right one has been shown for a moment.
    public func submit() {
        let right: Bool
        switch phase {
        case .wordBank:
            right = chosen.map { Self.wordBankTiles[$0] }.joined(separator: " ") == Self.wordBankAnswer
        case .typeIn:
            right = typed.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == Self.typeInAnswer.lowercased()
        case .done:
            return
        }
        feedback = right ? .correct : .wrong
    }

    public func advance() {
        guard feedback == .correct else { return }
        feedback = nil
        chosen = []
        phase = phase == .wordBank ? .typeIn : .done
        calloutIndex = 0
    }

    public func nextCallout() {
        if calloutIndex < callouts.count - 1 {
            calloutIndex += 1
        } else {
            guided = false
        }
    }

    public func hideCallouts() {
        guided = false
    }
}
