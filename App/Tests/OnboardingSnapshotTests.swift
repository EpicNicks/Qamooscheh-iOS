import SwiftUI
import UIKit
import XCTest
@testable import Qamooscheh

/// Extends ShellSnapshotTests so CI runs these in the snapshots job and uploads the PNGs
/// (onboarding-*.png in App/Tests/__Snapshots__). UNVERIFIED visually: a person reviews the PNGs.
extension ShellSnapshotTests {
    func testOnboardingNameLight() async throws {
        try renderOnboarding(await OnboardingScreenFixtures.name(), name: "onboarding-name-light", dark: false)
    }

    func testOnboardingNameDark() async throws {
        try renderOnboarding(await OnboardingScreenFixtures.name(typed: "Nicholas"), name: "onboarding-name-dark", dark: true)
    }

    func testOnboardingLanguagesLight() async throws {
        try renderOnboarding(await OnboardingScreenFixtures.languages(), name: "onboarding-languages-light", dark: false)
    }

    func testOnboardingLanguagesDark() async throws {
        try renderOnboarding(await OnboardingScreenFixtures.languages(), name: "onboarding-languages-dark", dark: true)
    }

    func testOnboardingTutorialWordBank() throws {
        try renderOnboarding(OnboardingScreenFixtures.tutorial(.wordBankCallout), name: "onboarding-tutorial-wordbank", dark: false)
    }

    func testOnboardingTutorialTypeIn() throws {
        try renderOnboarding(OnboardingScreenFixtures.tutorial(.typeIn), name: "onboarding-tutorial-typein", dark: false)
    }

    func testOnboardingTutorialDoneDark() throws {
        try renderOnboarding(OnboardingScreenFixtures.tutorial(.done), name: "onboarding-tutorial-done-dark", dark: true)
    }

    private func renderOnboarding(_ view: AnyView, name: String, dark: Bool) throws {
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
