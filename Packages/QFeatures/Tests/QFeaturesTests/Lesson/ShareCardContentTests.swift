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
        XCTAssertEqual(c.xpLine, "+0 XP")
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

    func testZWNJZWJAndDirectionMarksSurviveCleaning() {
        let khane = "\u{062E}\u{0627}\u{0646}\u{0647}\u{200C}\u{0647}\u{0627}\u{06CC}\u{200C}\u{0645}\u{0646}"
        let c = ShareCardContent(headline: khane, word: khane, reading: "\u{200F}khane\u{200E}", gloss: "a\u{200D}b")
        XCTAssertEqual(c.headline, khane)
        XCTAssertEqual(c.word, khane)
        XCTAssertEqual(c.word?.unicodeScalars.filter { $0.value == 0x200C }.count, 2)
        XCTAssertEqual(c.reading, "\u{200F}khane\u{200E}")
        XCTAssertEqual(c.gloss, "a\u{200D}b")
    }

    func testUnsafeFormatAndControlCharactersAreStripped() {
        let c = ShareCardContent(headline: "A\u{FEFF}B\u{202E}C\u{00AD}D\u{0000}E\u{200C}F")
        XCTAssertEqual(c.headline, "ABCDE\u{200C}F")
    }

    func testXPLineShownForZeroOnLessonCardOnly() {
        XCTAssertEqual(ShareCardContent(xp: 0).xpLine, "+0 XP")
        XCTAssertNil(ShareCardContent.streak(days: 3)?.xpLine)
    }

    func testShrinkSizesStepFourPixelsToTwentyFourPixelFloor() {
        let sizes = ShrinkingText<Text>.sizes(from: 44)
        XCTAssertEqual(sizes.first, 44)
        XCTAssertEqual(sizes.last, 8)
        XCTAssertEqual(sizes[0] - sizes[1], 4.0 / 3.0, accuracy: 0.0001)
        XCTAssertTrue(sizes.allSatisfy { $0 >= 8 })
    }

    func testAccessibilityTextListsEveryShownField() {
        let c = ShareCardContent(xp: 40, streakDays: 2, word: "w", reading: "r", gloss: "g")
        XCTAssertEqual(c.accessibilityText, "Lesson complete!, +40 XP, 2-day streak, w, r, g")
    }
}
