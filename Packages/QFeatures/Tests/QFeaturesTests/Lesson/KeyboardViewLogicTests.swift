import XCTest
import CoreGraphics
import QKeyboard
@testable import QFeatures

final class KeyboardViewLogicTests: XCTestCase {
    func testStripIsCenteredAboveAnchor() {
        let anchor = CGRect(x: 100, y: 120, width: 30, height: 46)
        let rects = CandidateStripGeometry.cellRects(anchor: anchor, count: 3, rtl: false, containerWidth: 390)
        XCTAssertEqual(rects.count, 3)
        XCTAssertEqual(rects[0].minX, 115 - 72, accuracy: 0.001)
        XCTAssertEqual(rects[0].minY, 120 - 48 - 6, accuracy: 0.001)
        XCTAssertEqual(rects[1].minX - rects[0].minX, 48, accuracy: 0.001)
    }

    func testStripClampsToContainer() {
        let left = CandidateStripGeometry.cellRects(anchor: CGRect(x: 0, y: 100, width: 30, height: 46), count: 3, rtl: false, containerWidth: 390)
        XCTAssertEqual(left[0].minX, 0, accuracy: 0.001)
        let right = CandidateStripGeometry.cellRects(anchor: CGRect(x: 370, y: 100, width: 30, height: 46), count: 3, rtl: false, containerWidth: 390)
        XCTAssertEqual(right[2].maxX, 390, accuracy: 0.001)
    }

    func testRtlPutsFirstCandidateRightmost() {
        let rects = CandidateStripGeometry.cellRects(anchor: CGRect(x: 100, y: 100, width: 30, height: 46), count: 3, rtl: true, containerWidth: 390)
        XCTAssertGreaterThan(rects[0].minX, rects[1].minX)
        XCTAssertGreaterThan(rects[1].minX, rects[2].minX)
    }

    func testHitIndex() {
        let rects = CandidateStripGeometry.cellRects(anchor: CGRect(x: 100, y: 100, width: 30, height: 46), count: 2, rtl: false, containerWidth: 390)
        XCTAssertEqual(CandidateStripGeometry.hitIndex(at: CGPoint(x: rects[1].midX, y: rects[1].midY), in: rects), 1)
        XCTAssertNil(CandidateStripGeometry.hitIndex(at: CGPoint(x: 0, y: 0), in: rects))
    }

    func testKeyWidthsSplitByWeight() {
        let widths = CandidateStripGeometry.keyWidths(weights: [1, 1, 2], total: 104, spacing: 4)
        XCTAssertEqual(widths, [24, 24, 48])
        XCTAssertEqual(CandidateStripGeometry.keyWidths(weights: [], total: 100, spacing: 4), [])
    }

    func testPressOpensAndPickClosesStrip() {
        let state = KeyboardState(method: .persianPhonetic)
        var text = ""
        text = state.press(.letter("s"), keyId: "1:1", textBefore: text).applyTo(text)
        XCTAssertEqual(text, "س")
        XCTAssertEqual(state.anchorKeyId, "1:1")
        XCTAssertEqual(state.candidates ?? [], ["س", "ص", "ث"])
        text = state.pick(1).applyTo(text)
        XCTAssertEqual(text, "ص")
        XCTAssertNil(state.anchorKeyId)
    }

    func testSwitchResetsAnchor() {
        let state = KeyboardState(method: .persianPhonetic)
        _ = state.press(.letter("s"), keyId: "1:1", textBefore: "")
        state.switchTo(.persianLayout(isolated: false))
        XCTAssertNil(state.anchorKeyId)
        XCTAssertNil(state.candidates)
    }

    func testKeyAccessibilityNames() {
        XCTAssertEqual(VirtualKey.accessibilityName(for: Key(label: "\u{232B}", action: .backspace)), "Backspace")
        XCTAssertEqual(VirtualKey.accessibilityName(for: Key(label: "x", action: .letter("x"))), "x")
    }
}
