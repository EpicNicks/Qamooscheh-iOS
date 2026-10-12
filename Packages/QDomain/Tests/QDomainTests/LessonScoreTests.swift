import XCTest
@testable import QDomain

final class LessonScoreTests: XCTestCase {
    func testPassThresholdIsSeventyFivePercent() {
        XCTAssertEqual(lessonPassThreshold, 0.75)
    }

    func testVerdictWeights() {
        XCTAssertEqual(verdictWeight(.correct), 1)
        XCTAssertEqual(verdictWeight(.acceptedWithCorrection), 0.5)
        XCTAssertEqual(verdictWeight(.incorrect), 0)
    }

    func testPendingVerdictWeighsNothing() {
        XCTAssertEqual(verdictWeight(.pending), 0)
    }
}
