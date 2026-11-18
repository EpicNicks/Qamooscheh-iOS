import SwiftUI
import UIKit
import XCTest
import QFeatures
@testable import Qamooscheh

/// Extends ShellSnapshotTests so CI runs these in the snapshots job and uploads the PNGs
/// (vocabulary-*.png and verb-forms-*.png in App/Tests/__Snapshots__). UNVERIFIED visually: a person reviews the PNGs.
/// The showcase is split into sections, each at most 2600 pt tall: renders much over ~8000 px tall come out blank.
extension ShellSnapshotTests {
    func testVocabularyListSnapshots() throws {
        try renderVocabularyVariants(base: "vocabulary-list", section: .list, height: 900)
    }

    func testVocabularyVerbsSnapshots() throws {
        try renderVocabularyVariants(base: "vocabulary-verbs", section: .verbs, height: 900)
    }

    func testVerbFormsPresentSnapshots() throws {
        try renderVocabularyVariants(base: "verb-forms-present", section: .verbFormsPresent, height: 1200)
    }

    func testVerbFormsPastNegativeSnapshots() throws {
        try renderVocabularyVariants(base: "verb-forms-past-negative", section: .verbFormsPastNegative, height: 1200)
    }

    func testVocabularyFlashcardsSnapshots() throws {
        try renderVocabularyVariants(base: "vocabulary-flashcards", section: .flashcards, height: 1300)
    }

    func testSnapshotBlankCheckFlagsSingleColour() throws {
        let size = CGSize(width: 60, height: 200)
        let solid = UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
        let marked = UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            UIColor.black.setFill()
            ctx.fill(CGRect(x: 10, y: 150, width: 20, height: 20))
        }
        XCTAssertTrue(snapshotIsSingleColour(try XCTUnwrap(solid.cgImage)))
        XCTAssertFalse(snapshotIsSingleColour(try XCTUnwrap(marked.cgImage)))
    }

    /// Light, dark and large-text (light and dark) renders of one section. Large text gets the 2600 pt cap.
    private func renderVocabularyVariants(base: String, section: VocabularyShowcaseSection, height: CGFloat) throws {
        try renderVocabulary(name: "\(base)-light", section: section, dark: false, large: false, height: height)
        try renderVocabulary(name: "\(base)-dark", section: section, dark: true, large: false, height: height)
        try renderVocabulary(name: "\(base)-large-light", section: section, dark: false, large: true, height: vocabularyMaxHeight)
        try renderVocabulary(name: "\(base)-large-dark", section: section, dark: true, large: true, height: vocabularyMaxHeight)
    }

    private var vocabularyMaxHeight: CGFloat { 2600 }

    private func renderVocabulary(
        name: String, section: VocabularyShowcaseSection, dark: Bool, large: Bool, height: CGFloat
    ) throws {
        XCTAssertLessThanOrEqual(height, vocabularyMaxHeight, "\(name) is too tall to render")
        let size = CGSize(width: 390, height: min(height, vocabularyMaxHeight))
        let controller = UIHostingController(rootView: VocabularyShowcase(large: large, section: section))
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
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.5))

        let image = UIGraphicsImageRenderer(size: size).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        window.isHidden = true
        let dir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("__Snapshots__")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try XCTUnwrap(image.pngData(), "PNG encoding failed")
        let file = dir.appendingPathComponent("\(name).png")
        try data.write(to: file)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        XCTAssertGreaterThan(data.count, 2000, "render looks blank")
        let cgImage = try XCTUnwrap(image.cgImage, "no CGImage for \(name)")
        XCTAssertFalse(snapshotIsSingleColour(cgImage), "\(name) rendered as a single colour (blank)")
    }
}

/// Samples the image on a coarse nearest-neighbour grid (one sample per point at most) and reports whether every
/// sample is within a small tolerance of the first, i.e. nothing rendered.
func snapshotIsSingleColour(_ image: CGImage) -> Bool {
    let width = max(1, min(image.width, 390))
    let height = max(1, Int((Double(image.height) * Double(width) / Double(max(image.width, 1))).rounded()))
    let bytesPerRow = width * 4
    var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
    let drawn: Bool = pixels.withUnsafeMutableBytes { buffer -> Bool in
        guard let context = CGContext(
            data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return false }
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return true
    }
    guard drawn, pixels.count >= 4 else { return true }
    let first = Array(pixels[0..<4])
    var index = 0
    while index + 3 < pixels.count {
        for channel in 0..<4 where abs(Int(pixels[index + channel]) - Int(first[channel])) > 8 {
            return false
        }
        index += 4
    }
    return true
}
