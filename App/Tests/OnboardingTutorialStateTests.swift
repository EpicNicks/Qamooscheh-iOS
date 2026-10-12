import XCTest
import QFeatures
@testable import Qamooscheh

@MainActor
final class OnboardingTutorialStateTests: XCTestCase {
    func testWordBankWrongThenRightAdvancesToTypeIn() {
        let state = OnboardingTutorialState()
        XCTAssertEqual(state.phase, .wordBank)
        state.toggleTile(1)
        state.submit()
        XCTAssertEqual(state.feedback, .wrong)
        state.advance()
        XCTAssertEqual(state.phase, .wordBank, "a wrong answer never advances")
        state.toggleTile(1)
        XCTAssertNil(state.feedback)
        state.toggleTile(0)
        state.submit()
        XCTAssertEqual(state.feedback, .correct)
        state.advance()
        XCTAssertEqual(state.phase, .typeIn)
        XCTAssertTrue(state.chosen.isEmpty)
        XCTAssertEqual(state.calloutIndex, 0)
    }

    func testTypeInIsTrimmedAndCaseInsensitive() {
        let state = OnboardingTutorialState()
        state.toggleTile(0)
        state.submit()
        state.advance()
        state.type("  onWARD ")
        state.submit()
        XCTAssertEqual(state.feedback, .correct)
        state.advance()
        XCTAssertEqual(state.phase, .done)
        state.submit()
        XCTAssertEqual(state.phase, .done)
    }

    func testCalloutsStepThenHide() {
        let state = OnboardingTutorialState()
        XCTAssertEqual(state.callout?.target, .prompt)
        state.nextCallout()
        XCTAssertEqual(state.callout?.target, .answer)
        state.nextCallout()
        XCTAssertEqual(state.callout?.target, .submit)
        XCTAssertTrue(state.isLastCallout)
        state.nextCallout()
        XCTAssertNil(state.callout)
    }

    func testHideCalloutsLeavesPhaseAlone() {
        let state = OnboardingTutorialState()
        state.hideCallouts()
        XCTAssertNil(state.callout)
        XCTAssertEqual(state.phase, .wordBank)
    }
}
