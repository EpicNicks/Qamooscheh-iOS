import XCTest
import SwiftUI
@testable import QFeatures

final class PathChromeLogicTests: XCTestCase {
    func testLabels() {
        XCTAssertEqual(dailyGoalRingLabel(xp: 30, goal: 50), "30/50")
        XCTAssertEqual(dailyGoalAccessibilityLabel(xp: 30, goal: 50), "30 of 50 daily XP goal")
    }

    func testFraction() {
        XCTAssertEqual(dailyGoalRingFraction(xp: 0, goal: 50), 0, accuracy: 0.0001)
        XCTAssertEqual(dailyGoalRingFraction(xp: 25, goal: 50), 0.5, accuracy: 0.0001)
        XCTAssertEqual(dailyGoalRingFraction(xp: 80, goal: 50), 1, accuracy: 0.0001)
        XCTAssertEqual(dailyGoalRingFraction(xp: 5, goal: 0), 1, accuracy: 0.0001)
        XCTAssertEqual(dailyGoalRingFraction(xp: -5, goal: 50), 0, accuracy: 0.0001)
    }

    func testCelebrationOncePerDay() {
        XCTAssertTrue(shouldCelebrateGoal(reached: true, enabled: true, lastCelebratedDay: nil, today: "2026-10-12"))
        XCTAssertTrue(shouldCelebrateGoal(reached: true, enabled: true, lastCelebratedDay: "2026-10-11", today: "2026-10-12"))
        XCTAssertFalse(shouldCelebrateGoal(reached: true, enabled: true, lastCelebratedDay: "2026-10-12", today: "2026-10-12"))
        XCTAssertFalse(shouldCelebrateGoal(reached: false, enabled: true, lastCelebratedDay: nil, today: "2026-10-12"))
        XCTAssertFalse(shouldCelebrateGoal(reached: true, enabled: false, lastCelebratedDay: nil, today: "2026-10-12"))
    }

    func testJumpRotationAndStreak() {
        XCTAssertEqual(jumpArrowRotation(.up), 0)
        XCTAssertEqual(jumpArrowRotation(.down), 180)
        XCTAssertEqual(streakLabel(7), "7")
        XCTAssertEqual(streakLabel(-1), "0")
    }

    func testGoalRingSizeMatchesAndroid() {
        XCTAssertEqual(dailyGoalRingSize, 18.3, accuracy: 0.0001)
    }

    func testCelebrationSkippedUnderReduceMotion() {
        XCTAssertTrue(goalCelebrationAnimates(celebrating: true, reduceMotion: false))
        XCTAssertFalse(goalCelebrationAnimates(celebrating: true, reduceMotion: true))
        XCTAssertFalse(goalCelebrationAnimates(celebrating: false, reduceMotion: false))
    }

    func testTotalXpLabels() {
        XCTAssertEqual(totalXpLabel(4210), "4210 XP")
        XCTAssertEqual(totalXpLabel(-3), "0 XP")
        XCTAssertEqual(totalXpAccessibilityLabel(12), "12 total XP")
    }

    func testSheetOpensLarge() {
        XCTAssertEqual(pathSheetDetents, [.large])
    }
}
