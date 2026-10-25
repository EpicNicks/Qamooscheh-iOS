import SwiftUI
import UIKit
import XCTest
import QFeatures
@testable import Qamooscheh

/// Extends ShellSnapshotTests so CI runs these in the snapshots job and uploads the PNGs
/// (stow-*.png in App/Tests/__Snapshots__). UNVERIFIED visually: a person reviews the PNGs.
extension ShellSnapshotTests {
    func testStowDialogsLight() throws {
        try renderStow(page: .dialogs, rtl: false, name: "stow-dialogs-light")
    }

    func testStowDialogsRtlLight() throws {
        try renderStow(page: .dialogs, rtl: true, name: "stow-dialogs-rtl-light")
    }

    func testStowReminderLight() throws {
        try renderStow(page: .reminder, rtl: false, name: "stow-reminder-light")
    }

    func testStowReminderRtlLight() throws {
        try renderStow(page: .reminder, rtl: true, name: "stow-reminder-rtl-light")
    }

    private func renderStow(page: StowViewsPage, rtl: Bool, name: String) throws {
        let size = CGSize(width: 390, height: 800)
        let controller = UIHostingController(rootView: StowViewsShowcase(page: page, rtl: rtl))
        controller.overrideUserInterfaceStyle = .light
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
