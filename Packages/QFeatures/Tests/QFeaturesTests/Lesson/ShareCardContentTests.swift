import XCTest
import CoreGraphics
@testable import QFeatures

final class ShareCardContentTests: XCTestCase {
    func testLessonCardDefaults() {
        let c = ShareCardContent(xp: 40, streakDays: 12, word: "پنیر", reading: "panīr", gloss: "cheese")
        XCTAssertEqual(c.headline, "Lesson complete!")
        XCTAssertEqual(c.xpLine, "+40 XP")
        XCTAssertEqual(c.streakLine, "12-day streak")
        XCTAssertEqual(c.glossLine, "\u{201C}cheese\u{201D}")
        XCTAssertEqual(c.shareText, "Lesson complete!")
    }

    func testBlankAndNonPositiveFieldsAreDropped() {
        let c = ShareCardContent(xp: 0, streakDays: 0, word: "  ", reading: "\n", gloss: "")
        XCTAssertNil(c.xpLine)
        XCTAssertNil(c.streakLine)
        XCTAssertNil(c.word)
        XCTAssertNil(c.reading)
        XCTAssertNil(c.gloss)
        XCTAssertNil(ShareCardContent(streakDays: -3).streakDays)
    }

    func testNumbersAreClamped() {
        XCTAssertEqual(ShareCardContent(xp: -5).xp, 0)
        XCTAssertEqual(ShareCardContent(xp: 10_000_000).xp, ShareCardContent.maxXP)
        XCTAssertEqual(ShareCardContent(streakDays: 10_000_000).streakDays, ShareCardContent.maxStreakDays)
    }

    func testTextIsTrimmedCappedAndStrippedOfControlCharacters() {
        let long = String(repeating: "a", count: 500)
        let c = ShareCardContent(headline: "  Hi\u{0007}\n there ", word: long)
        XCTAssertEqual(c.headline, "Hi there")
        XCTAssertEqual(c.word?.count, ShareCardContent.maxWord)
    }

    func testStreakCardHidesXPAndNeedsAPositiveStreak() {
        XCTAssertNil(ShareCardContent.streak(days: 0))
        let c = ShareCardContent.streak(days: 7)
        XCTAssertEqual(c?.kind, .streak)
        XCTAssertEqual(c?.streakLine, "7-day streak")
        XCTAssertNil(c?.xpLine)
        XCTAssertEqual(c?.headline, "Keep it going!")
        XCTAssertEqual(ShareCardContent(kind: .streak, xp: 99, streakDays: 3).xp, 0)
    }

    func testSharedTextCarriesOnlyTheHeadline() {
        let c = ShareCardContent(headline: "Lesson complete!", xp: 40, streakDays: 12, word: "w", reading: "r", gloss: "g")
        XCTAssertEqual(c.shareText, "Lesson complete!")
        XCTAssertFalse(c.shareText.contains("://"))
    }

    func testPNGEncodeProducesPNGSignature() throws {
        let space = CGColorSpaceCreateDeviceRGB()
        let ctx = try XCTUnwrap(CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        let image = try XCTUnwrap(ctx.makeImage())
        let data = try ShareCardPNG.encode(image)
        XCTAssertEqual(Array(data.prefix(8)), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    }

    func testAccessibilityTextListsEveryShownField() {
        let c = ShareCardContent(xp: 40, streakDays: 2, word: "w", reading: "r", gloss: "g")
        XCTAssertEqual(c.accessibilityText, "Lesson complete!, +40 XP, 2-day streak, w, r, g")
    }
}
