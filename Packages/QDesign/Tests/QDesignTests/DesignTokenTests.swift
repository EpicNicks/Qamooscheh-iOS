import XCTest
import SwiftUI
@testable import QDesign

final class DesignTokenTests: XCTestCase {
    func testSpacingMatchesWeb() {
        let s = Spacing.standard
        XCTAssertEqual([s.s1, s.s2, s.s3, s.s4, s.s5], [4, 8, 16, 24, 32])
        let r = Radii.standard
        XCTAssertEqual([r.sm, r.md, r.lg], [8, 14, 20])
    }

    func testDarkOverridesOnlyChangedTokens() {
        XCTAssertEqual(AppPalette.light.primary, 0xFF58CC02)
        XCTAssertEqual(AppPalette.dark.primary, AppPalette.light.primary)
        XCTAssertEqual(AppPalette.dark.bg, 0xFF131320)
        XCTAssertTrue(AppPalette.dark.isDark)
        XCTAssertFalse(AppPalette.light.isDark)
    }
}

final class DirectionalTextTests: XCTestCase {
    func testLayoutDirection() {
        XCTAssertEqual(DirectionalText.layoutDirection(rtl: true), .rightToLeft)
        XCTAssertEqual(DirectionalText.layoutDirection(rtl: false), .leftToRight)
    }
}
