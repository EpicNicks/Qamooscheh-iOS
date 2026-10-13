import SwiftUI
import UIKit
import XCTest
import QFeatures
@testable import Qamooscheh

/// Extends ShellSnapshotTests so CI runs these in the snapshots job and uploads the PNGs
/// (annotated-*.png in App/Tests/__Snapshots__). UNVERIFIED visually: a person reviews the PNGs.
extension ShellSnapshotTests {
    func testAnnotatedFuriganaWrapping() throws {
        try renderAnnotated(.furiganaWrapping, name: "annotated-furigana-wrapping", width: 280, dark: false)
    }

    func testAnnotatedMixedJapaneseLatin() throws {
        try renderAnnotated(.mixedJapaneseLatin, name: "annotated-mixed-ja-latin", width: 390, dark: false)
    }

    func testAnnotatedPersianEzafe() throws {
        try renderAnnotated(.persianEzafe, name: "annotated-persian-ezafe-rtl", width: 390, dark: false)
    }

    func testAnnotatedPersianVowelMarksOff() throws {
        try renderAnnotated(.persianVowelMarksOff, name: "annotated-persian-vowels-off", width: 390, dark: false)
    }

    func testAnnotatedPersianVowelMarksOn() throws {
        try renderAnnotated(.persianVowelMarksOn, name: "annotated-persian-vowels-on", width: 390, dark: false)
    }

    func testAnnotatedFuriganaDark() throws {
        try renderAnnotated(.furiganaWrapping, name: "annotated-furigana-dark", width: 280, dark: true)
    }

    private func renderAnnotated(_ scenario: AnnotatedTextScenario, name: String, width: CGFloat, dark: Bool) throws {
        let size = CGSize(width: width, height: 220)
        let controller = UIHostingController(rootView: AnnotatedTextShowcase(scenario))
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
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.6))

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
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        XCTAssertGreaterThan(data.count, 1000, "render looks blank")
    }
}
