import SwiftUI
import UIKit
import XCTest
import QFeatures
@testable import Qamooscheh

/// Extends ShellSnapshotTests so CI runs these in the snapshots job and uploads the PNGs
/// (sharecard-*.png in App/Tests/__Snapshots__). UNVERIFIED visually: a person reviews the PNGs.
extension ShellSnapshotTests {
    private static let lesson = ShareCardContent(xp: 40, streakDays: 12, word: "\u{067E}\u{0646}\u{06CC}\u{0631}", reading: "pan\u{012B}r", gloss: "cheese")
    private static let streak = ShareCardContent.streak(days: 30, word: "\u{0633}\u{0644}\u{0627}\u{0645}", reading: "sal\u{0101}m", gloss: "hello")!
    private static let tight = ShareCardContent(headline: "A very long headline that needs to shrink to fit the panel", xp: 99_999, streakDays: 99_999,
                                                word: "\u{062E}\u{0627}\u{0646}\u{0647}\u{200C}\u{0647}\u{0627}\u{06CC}\u{200C}\u{0645}\u{0627}\u{0646}", reading: "a long romanization that also needs to shrink", gloss: "our houses and everything in them")

    func testShareCardLessonLight() throws {
        try renderShare(AnyView(ShareCardView(content: Self.lesson)), name: "sharecard-lesson-light", dark: false, large: false, size: CGSize(width: 360, height: 360))
    }

    func testShareCardLessonDark() throws {
        try renderShare(AnyView(ShareCardView(content: Self.lesson)), name: "sharecard-lesson-dark", dark: true, large: false, size: CGSize(width: 360, height: 360))
    }

    func testShareCardStreakLight() throws {
        try renderShare(AnyView(ShareCardView(content: Self.streak)), name: "sharecard-streak-light", dark: false, large: false, size: CGSize(width: 360, height: 360))
    }

    func testShareCardLongTextLight() throws {
        try renderShare(AnyView(ShareCardView(content: Self.tight)), name: "sharecard-long-light", dark: false, large: false, size: CGSize(width: 360, height: 360))
    }

    func testShareCardPreviewLight() throws {
        try renderShare(AnyView(ShareCardPreview(content: Self.lesson)), name: "sharecard-preview-light", dark: false, large: false, size: CGSize(width: 390, height: 640))
    }

    func testShareCardPreviewDark() throws {
        try renderShare(AnyView(ShareCardPreview(content: Self.lesson)), name: "sharecard-preview-dark", dark: true, large: false, size: CGSize(width: 390, height: 640))
    }

    func testShareCardPreviewLargeTypeLight() throws {
        try renderShare(AnyView(ShareCardPreview(content: Self.lesson)), name: "sharecard-preview-large-light", dark: false, large: true, size: CGSize(width: 390, height: 760))
    }

    func testShareCardPreviewLargeTypeDark() throws {
        try renderShare(AnyView(ShareCardPreview(content: Self.lesson)), name: "sharecard-preview-large-dark", dark: true, large: true, size: CGSize(width: 390, height: 760))
    }

    /// The renderer path itself: the PNG that would be shared must decode to a 1080 x 1080 image.
    func testShareCardRendersTo1080Png() throws {
        let image = try ShareCardRenderer.cgImage(for: Self.lesson)
        XCTAssertEqual(image.width, 1080)
        XCTAssertEqual(image.height, 1080)
        let data = try ShareCardPNG.encode(image)
        XCTAssertGreaterThan(data.count, 5000)
        let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("__Snapshots__")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try data.write(to: dir.appendingPathComponent("sharecard-exported.png"))
    }

    private func renderShare(_ view: AnyView, name: String, dark: Bool, large: Bool, size: CGSize) throws {
        var root = view
        if large { root = AnyView(root.environment(\.sizeCategory, .accessibilityLarge)) }
        let controller = UIHostingController(rootView: root)
        controller.overrideUserInterfaceStyle = dark ? .dark : .light
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let window: UIWindow
        if let scene = scene {
            window = UIWindow(windowScene: scene)
            window.frame = CGRect(origin: .zero, size: size)
        } else {
            window = UIWindow(frame: CGRect(origin: .zero, size: size))
        }
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.frame = window.bounds
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 1.5))

        let image = UIGraphicsImageRenderer(size: size).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let dir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("__Snapshots__")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try XCTUnwrap(image.pngData(), "PNG encoding failed")
        let file = dir.appendingPathComponent("\(name).png")
        try data.write(to: file)
        XCTAssertGreaterThan(data.count, 2000, "render looks blank")
    }
}
