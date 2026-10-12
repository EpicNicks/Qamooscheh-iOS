import SwiftUI
import UIKit
import XCTest
import QFeatures
@testable import Qamooscheh

/// Extends ShellSnapshotTests so CI runs these in the snapshots job and uploads the PNGs
/// (pathpopovers-*.png in App/Tests/__Snapshots__). UNVERIFIED visually: a person reviews the PNGs.
extension ShellSnapshotTests {
    func testPathPopoversLight() throws {
        try renderPathPopovers(page: .popovers, rtl: false, name: "pathpopovers-light", dark: false)
    }

    func testPathPopoversDark() throws {
        try renderPathPopovers(page: .popovers, rtl: false, name: "pathpopovers-dark", dark: true)
    }

    func testPathPopoversRtlLight() throws {
        try renderPathPopovers(page: .popovers, rtl: true, name: "pathpopovers-rtl-light", dark: false)
    }

    func testPathSheetsLight() throws {
        try renderPathPopovers(page: .sheets, rtl: false, name: "pathsheets-light", dark: false)
    }

    func testPathSheetsDark() throws {
        try renderPathPopovers(page: .sheets, rtl: false, name: "pathsheets-dark", dark: true)
    }

    func testPathChooserLight() throws {
        try renderPathPopovers(page: .chooser, rtl: false, name: "pathchooser-light", dark: false)
    }

    private func renderPathPopovers(page: PathPopoversPage, rtl: Bool, name: String, dark: Bool) throws {
        let size = CGSize(width: 390, height: 800)
        let controller = UIHostingController(rootView: PathPopoversShowcase(page: page, rtl: rtl))
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
        let dir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("__Snapshots__")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try XCTUnwrap(image.pngData(), "PNG encoding failed")
        let file = dir.appendingPathComponent("\(name).png")
        try data.write(to: file)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        XCTAssertGreaterThan(data.count, 2000, "render looks blank")
    }
}
