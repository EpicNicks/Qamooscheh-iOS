import SwiftUI
import QDomain

/// Stands in for the real renderer until its look is decided (held for a visual judgement): the end
/// state is already on screen, so it draws and unlocks nothing. Rive or a hand-drawn one replaces it
/// behind `JourneyAnimator`.
@MainActor
public struct NoopJourneyAnimator: JourneyAnimator {
    public init() {}
    public func drawEdges(_ edges: [JourneyEdge]) async {}
    public func playUnlock(_ skillKeys: [String]) async {}
}

/// Plays the path's pending completion transition once on return to the Journey, then clears it.
/// Under reduce-motion nothing plays and the end state simply shows.
struct JourneyPlayback: ViewModifier {
    @ObservedObject var model: PathModel
    let animator: JourneyAnimator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .task(id: model.transition) {
                // Clear only after it has played: clearing first would change the task id and cancel playback.
                guard let transition = model.transition else { return }
                await playJourneyTransition(transition, animator: animator, reduceMotion: reduceMotion)
                _ = model.consumeTransition()
            }
    }
}
