import SwiftUI
import UIKit
import XCTest
import QFeatures
@testable import Qamooscheh

/// One smoke render per tab with no services (every tab shows its empty state). PNGs land in App/Tests/__Snapshots__
/// (tab-*.png) and are UNVERIFIED visually: a person reviews them.
extension ShellSnapshotTests {
    func testTabLearn() throws { try renderTab(.learn) }
    func testTabLibrary() throws { try renderTab(.library) }
    func testTabReview() throws { try renderTab(.review) }
    func testTabLeagues() throws { try renderTab(.leagues) }
    func testTabProfile() throws { try renderTab(.profile) }

    private func renderTab(_ tab: AppTab) throws {
        let size = CGSize(width: 390, height: 844)
        let controller = UIHostingController(rootView: RootTabView(initialTab: tab))
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
        let file = dir.appendingPathComponent("tab-\(tab.rawValue).png")
        try data.write(to: file)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        XCTAssertGreaterThan(data.count, 2000, "render looks blank")
    }
}
