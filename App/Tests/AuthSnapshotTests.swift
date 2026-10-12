import SwiftUI
import UIKit
import XCTest
@testable import Qamooscheh

/// Extends ShellSnapshotTests so CI runs these in the snapshots job and uploads the PNGs. Renders the login and register screens in a real window and writes PNGs to
/// App/Tests/__Snapshots__ (uploaded by CI). UNVERIFIED visually: a person reviews the PNGs.
extension ShellSnapshotTests {
    func testLoginLight() async throws {
        try renderAuth(await AuthScreenFixtures.login(), name: "auth-login-light", dark: false)
    }

    func testLoginDark() async throws {
        try renderAuth(await AuthScreenFixtures.login(), name: "auth-login-dark", dark: true)
    }

    func testLoginError() async throws {
        try renderAuth(await AuthScreenFixtures.login(errorAfterSubmit: true), name: "auth-login-error", dark: false)
    }

    func testLoginClosedAlpha() async throws {
        try renderAuth(await AuthScreenFixtures.login(registrationOpen: false), name: "auth-login-closed", dark: false)
    }

    func testRegisterLight() async throws {
        try renderAuth(await AuthScreenFixtures.register(), name: "auth-register-light", dark: false)
    }

    func testRegisterDark() async throws {
        try renderAuth(await AuthScreenFixtures.register(), name: "auth-register-dark", dark: true)
    }

    func testRegisterClosed() async throws {
        try renderAuth(await AuthScreenFixtures.register(registrationOpen: false), name: "auth-register-closed", dark: false)
    }

    private func renderAuth(_ view: AnyView, name: String, dark: Bool) throws {
        let size = CGSize(width: 390, height: 844)
        let controller = UIHostingController(rootView: view)
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
