import SwiftUI
import QDomain

// The Journey's completion playback: the transition's edges draw in order along the road, then the
// newly unlocked skills pulse. The look is not yet checked on a device (CI and unit tests only);
// the sequencing and the geometry rules below are what the tests pin.

/// How far each in-flight edge is drawn, and how strongly each unlocked skill is pulsing.
public struct JourneyReveal: Equatable, Sendable {
    /// 0 = hidden, 1 = fully drawn. An edge that is absent is fully drawn.
    public var edgeProgress: [JourneyEdge: Double] = [:]
    /// 0...1 per skill key; absent = at rest.
    public var pulse: [String: Double] = [:]

    public init(edgeProgress: [JourneyEdge: Double] = [:], pulse: [String: Double] = [:]) {
        self.edgeProgress = edgeProgress
        self.pulse = pulse
    }

    public static let none = JourneyReveal()
}

private struct JourneyRevealKey: EnvironmentKey {
    static let defaultValue = JourneyReveal.none
}

extension EnvironmentValues {
    var journeyReveal: JourneyReveal {
        get { self[JourneyRevealKey.self] }
        set { self[JourneyRevealKey.self] = newValue }
    }
}

/// Holds the playback's moving values; the road reads them through the environment.
@MainActor
public final class JourneyRevealModel: ObservableObject {
    @Published public private(set) var reveal = JourneyReveal.none

    public init() {}

    func setProgress(_ edge: JourneyEdge, _ value: Double) { reveal.edgeProgress[edge] = value }
    func setPulse(_ skillKey: String, _ value: Double) { reveal.pulse[skillKey] = value }
    func reset() { reveal = .none }

    /// What to render while `transition` is pending: its edges not yet started stay hidden, so the end state
    /// never flashes before the draw begins.
    func visible(for transition: JourneyTransition?) -> JourneyReveal {
        guard let transition else { return .none }
        var shown = reveal
        for edge in transition.edges where shown.edgeProgress[edge] == nil { shown.edgeProgress[edge] = 0 }
        return shown
    }
}

/// Ease-in-out fraction of a draw at `step` of `total` frames.
func journeyFraction(step: Int, total: Int) -> Double {
    guard total > 0 else { return 1 }
    let t = min(max(Double(step) / Double(total), 0), 1)
    return t * t * (3 - 2 * t)
}

/// A pulse that rises and settles back to rest: 0 at both ends, 1 in the middle.
func journeyPulse(step: Int, total: Int) -> Double {
    guard total > 0 else { return 0 }
    let t = min(max(Double(step) / Double(total), 0), 1)
    return sin(Double.pi * t)
}

/// Draws the edges one after another, then pulses the unlocked skills, in frames spaced by `sleep`.
@MainActor
public final class RoadJourneyAnimator: JourneyAnimator {
    private let model: JourneyRevealModel
    private let edgeFrames: Int
    private let pulseFrames: Int
    private let frameNanos: UInt64
    private let sleep: @MainActor (UInt64) async -> Void

    public init(
        model: JourneyRevealModel, edgeFrames: Int = 20, pulseFrames: Int = 30, frameNanos: UInt64 = 16_000_000,
        sleep: @escaping @MainActor (UInt64) async -> Void = { try? await Task.sleep(nanoseconds: $0) }
    ) {
        self.model = model
        self.edgeFrames = edgeFrames
        self.pulseFrames = pulseFrames
        self.frameNanos = frameNanos
        self.sleep = sleep
    }

    public func drawEdges(_ edges: [JourneyEdge]) async {
        for edge in edges {
            model.setProgress(edge, 0)
            for step in 1...max(edgeFrames, 1) {
                if Task.isCancelled { return }
                await sleep(frameNanos)
                model.setProgress(edge, journeyFraction(step: step, total: edgeFrames))
            }
        }
    }

    public func playUnlock(_ skillKeys: [String]) async {
        for step in 1...max(pulseFrames, 1) {
            if Task.isCancelled { break }
            await sleep(frameNanos)
            for key in skillKeys { model.setPulse(key, journeyPulse(step: step, total: pulseFrames)) }
        }
        for key in skillKeys { model.setPulse(key, 0) }
    }
}

extension UnitRoad {
    /// How much of `edge` to draw: the least progress among the transition edges it stands for (all of
    /// them while forks are collapsed into one group node), or 1 when none is playing.
    func journeyProgress(_ edge: RoadEdgeGeometry, reveal: JourneyReveal) -> Double {
        if reveal.edgeProgress.isEmpty { return 1 }
        let from = positions[edge.fromPositionIndex].skills
        let to = positions[edge.toPositionIndex].skills
        func keys(_ skills: [PathSkill], _ index: Int) -> Set<String> {
            if collapseForks { return Set(skills.map { $0.skillKey }) }
            return index < skills.count ? [skills[index].skillKey] : []
        }
        let fromKeys = keys(from, edge.fromSkillIndex)
        let toKeys = keys(to, edge.toSkillIndex)
        let matching = reveal.edgeProgress.filter { fromKeys.contains($0.key.from) && toKeys.contains($0.key.to) }
        return matching.values.min() ?? 1
    }
}

/// Plays the path's pending completion transition once on return to the Journey, then clears it.
/// Under reduce-motion nothing plays and the end state simply shows.
struct JourneyPlayback: ViewModifier {
    @ObservedObject var model: PathModel
    let reveal: JourneyRevealModel
    let animator: JourneyAnimator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .task(id: model.transition) {
                // Clear only after it has played: clearing first would change the task id and cancel playback.
                guard let transition = model.transition else { return }
                await playJourneyTransition(transition, animator: animator, reduceMotion: reduceMotion)
                _ = model.consumeTransition()
                reveal.reset()
            }
    }
}
