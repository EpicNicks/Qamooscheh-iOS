import SwiftUI
import UIKit
import XCTest
import QDesign
@testable import Qamooscheh

/// Extends ShellSnapshotTests so CI uploads script-fonts-specimen.png. UNVERIFIED visually: a person reviews the PNG.
/// Renders with whatever fonts are installed (system fallback when the Vazirmatn file is absent).
extension ShellSnapshotTests {
    func testScriptFontsSpecimen() throws {
        ScriptFonts.registerBundledFonts()
        let size = CGSize(width: 390, height: 700)
        let controller = UIHostingController(rootView: ScriptSpecimenSheet())
        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
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
        let file = dir.appendingPathComponent("script-fonts-specimen.png")
        try data.write(to: file)
        XCTAssertGreaterThan(data.count, 2000, "render looks blank")
    }
}
