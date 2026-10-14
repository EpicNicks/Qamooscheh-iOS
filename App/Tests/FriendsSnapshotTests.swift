import SwiftUI
import UIKit
import XCTest
import QFeatures
@testable import Qamooscheh

/// Extends ShellSnapshotTests so CI runs these in the snapshots job and uploads the PNGs
/// (friends-*.png in App/Tests/__Snapshots__). UNVERIFIED visually: a person reviews the PNGs.
extension ShellSnapshotTests {
    func testFriendsLight() throws {
        try renderFriends(name: "friends-light", dark: false, large: false)
    }

    func testFriendsDark() throws {
        try renderFriends(name: "friends-dark", dark: true, large: false)
    }

    func testFriendsLargeType() throws {
        try renderFriends(name: "friends-large-light", dark: false, large: true)
    }

    func testFriendsLargeTypeDark() throws {
        try renderFriends(name: "friends-large-dark", dark: true, large: true)
    }

    private func renderFriends(name: String, dark: Bool, large: Bool) throws {
        let size = CGSize(width: 390, height: large ? 3600 : 1500)
        let controller = UIHostingController(rootView: FriendsShowcase(large: large))
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
