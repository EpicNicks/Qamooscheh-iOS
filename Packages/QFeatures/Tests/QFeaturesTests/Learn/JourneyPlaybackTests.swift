import XCTest
import QDomain
@testable import QFeatures

@MainActor
final class JourneyPlaybackTests: XCTestCase {
    private let ab1 = JourneyEdge(from: "a", to: "b1")
    private let ab2 = JourneyEdge(from: "a", to: "b2")

    private func animator(_ model: JourneyRevealModel, ticks: Ticks) -> RoadJourneyAnimator {
        RoadJourneyAnimator(model: model, edgeFrames: 4, pulseFrames: 4, frameNanos: 1, sleep: { _ in ticks.count += 1 })
    }

    final class Ticks { var count = 0 }

    func testEasingAndPulseEndpoints() {
        XCTAssertEqual(journeyFraction(step: 0, total: 4), 0)
        XCTAssertEqual(journeyFraction(step: 4, total: 4), 1)
        XCTAssertEqual(journeyFraction(step: 2, total: 4), 0.5, accuracy: 1e-9)
        XCTAssertEqual(journeyPulse(step: 0, total: 4), 0, accuracy: 1e-9)
        XCTAssertEqual(journeyPulse(step: 2, total: 4), 1, accuracy: 1e-9)
        XCTAssertEqual(journeyPulse(step: 4, total: 4), 0, accuracy: 1e-9)
    }

    func testEdgesDrawInOrderAndEndFullyDrawn() async {
        let model = JourneyRevealModel()
        let ticks = Ticks()
        let anim = RoadJourneyAnimator(model: model, edgeFrames: 4, pulseFrames: 4, frameNanos: 1, sleep: { _ in
            // While the first edge is still drawing, the second has not started.
            if let first = model.reveal.edgeProgress[self.ab1], first < 1 {
                XCTAssertNil(model.reveal.edgeProgress[self.ab2])
            }
            ticks.count += 1
        })
        await anim.drawEdges([ab1, ab2])
        XCTAssertEqual(model.reveal.edgeProgress[ab1], 1)
        XCTAssertEqual(model.reveal.edgeProgress[ab2], 1)
        XCTAssertEqual(ticks.count, 8)
    }

    func testUnlockPulsesThenRests() async {
        let model = JourneyRevealModel()
        let anim = animator(model, ticks: Ticks())
        await anim.playUnlock(["b1", "b2"])
        XCTAssertEqual(model.reveal.pulse["b1"], 0)
        XCTAssertEqual(model.reveal.pulse["b2"], 0)
    }

    func testPendingTransitionHidesItsEdgesUntilTheyStart() {
        let model = JourneyRevealModel()
        let transition = JourneyTransition(completedSkillKey: "a", edges: [ab1, ab2], unlockedSkillKeys: ["b1", "b2"])
        XCTAssertEqual(model.visible(for: nil), .none)
        let hidden = model.visible(for: transition)
        XCTAssertEqual(hidden.edgeProgress[ab1], 0)
        XCTAssertEqual(hidden.edgeProgress[ab2], 0)
        model.setProgress(ab1, 0.5)
        let mid = model.visible(for: transition)
        XCTAssertEqual(mid.edgeProgress[ab1], 0.5)
        XCTAssertEqual(mid.edgeProgress[ab2], 0)
        model.reset()
        XCTAssertEqual(model.reveal, .none)
    }

    func testRoadDrawsOnlyThePlayingEdgePartway() {
        let road = PathRoadFixtures.road(compact: false)
        let reveal = JourneyReveal(edgeProgress: [ab1: 0.5])
        let edges = road.edges
        let toB1 = edges.first { $0.fromPositionIndex == 0 && $0.toPositionIndex == 1 && $0.toSkillIndex == 0 }!
        let toB2 = edges.first { $0.fromPositionIndex == 0 && $0.toPositionIndex == 1 && $0.toSkillIndex == 1 }!
        let later = edges.first { $0.fromPositionIndex == 2 }!
        XCTAssertEqual(road.journeyProgress(toB1, reveal: reveal), 0.5)
        XCTAssertEqual(road.journeyProgress(toB2, reveal: reveal), 1)
        XCTAssertEqual(road.journeyProgress(later, reveal: reveal), 1)
        XCTAssertEqual(road.journeyProgress(toB1, reveal: .none), 1)
    }

    func testCollapsedForkEdgeFollowsItsBranches() {
        let road = PathRoadFixtures.road(compact: true)
        let reveal = JourneyReveal(edgeProgress: [ab1: 0.25, ab2: 0.75])
        let edge = road.edges.first { $0.fromPositionIndex == 0 && $0.toPositionIndex == 1 }!
        XCTAssertEqual(road.journeyProgress(edge, reveal: reveal), 0.25)
    }
}
