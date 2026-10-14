import Foundation
import Combine
import QDomain

/// Letters practice on screen: the session, plus the answer just given while its feedback shows.
/// `review`'s session is already the next state; it takes over when the learner continues.
public struct LettersPracticeState: Equatable, Sendable {
    public var session: LettersSession
    public var review: LetterAnswer?

    public init(session: LettersSession, review: LetterAnswer? = nil) {
        self.session = session
        self.review = review
    }

    /// The question to draw: the one being reviewed, else the next one up.
    public var question: LetterQuestion? { review?.question ?? session.current }
    public var finished: Bool { review == nil && session.finished }
}

/// Lets any generator be passed where a concrete one is needed.
public struct BoxedGenerator: RandomNumberGenerator {
    var base: any RandomNumberGenerator

    public init(_ base: any RandomNumberGenerator) { self.base = base }

    public mutating func next() -> UInt64 { base.next() }
}

/// A local quiz over the Persian letters (spec 9.8, Android LettersPracticeViewModel). Nothing is
/// submitted, so nothing here touches the network or the learner's review cards.
@MainActor
public final class LettersPracticeModel: ObservableObject {
    @Published public private(set) var state: LettersPracticeState
    private var random: BoxedGenerator

    public init(random: any RandomNumberGenerator = SystemRandomNumberGenerator()) {
        var generator = BoxedGenerator(random)
        state = LettersPracticeState(session: lettersSession(using: &generator))
        self.random = generator
    }

    /// Answers the current question with option `choice`; ignored while the last answer's feedback is up.
    public func choose(_ choice: Int) {
        if state.review != nil || state.session.finished { return }
        state.review = state.session.answer(choice)
    }

    public func continueOn() {
        if let review = state.review { state = LettersPracticeState(session: review.session) }
    }

    public func again() {
        state = LettersPracticeState(session: lettersSession(using: &random))
    }

    public static func preview(_ state: LettersPracticeState) -> LettersPracticeModel {
        let model = LettersPracticeModel()
        model.state = state
        return model
    }
}
