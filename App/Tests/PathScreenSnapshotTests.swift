import SwiftUI
import UIKit
import XCTest
import QFeatures
@testable import Qamooscheh

/// Extends ShellSnapshotTests so CI runs these in the snapshots job and uploads the PNGs
/// (pathscreen-*.png in App/Tests/__Snapshots__). UNVERIFIED visually: a person reviews the PNGs.
extension ShellSnapshotTests {
    func testPathScreenReadyLight() throws {
        try renderPathScreen(page: .ready, rtl: false, name: "pathscreen-ready-light")
    }

    func testPathScreenDownloadingLight() throws {
        try renderPathScreen(page: .downloading, rtl: false, name: "pathscreen-downloading-light")
    }

    func testPathScreenFailedLight() throws {
        try renderPathScreen(page: .failed, rtl: false, name: "pathscreen-failed-light")
    }

    func testPathScreenReadyRtl() throws {
        try renderPathScreen(page: .ready, rtl: true, name: "pathscreen-ready-rtl")
    }

    func testPathScreenDownloadingRtl() throws {
        try renderPathScreen(page: .downloading, rtl: true, name: "pathscreen-downloading-rtl")
    }

    func testPathScreenFailedRtl() throws {
        try renderPathScreen(page: .failed, rtl: true, name: "pathscreen-failed-rtl")
    }

    private func renderPathScreen(page: PathScreenPage, rtl: Bool, name: String) throws {
        let size = CGSize(width: 390, height: 700)
        let controller = UIHostingController(rootView: PathScreenShowcase(page: page, rtl: rtl))
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
