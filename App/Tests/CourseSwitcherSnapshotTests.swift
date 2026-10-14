import SwiftUI
import UIKit
import XCTest
import QModel
import QFeatures
@testable import Qamooscheh

/// Extends ShellSnapshotTests so CI runs these in the snapshots job and uploads the PNGs
/// (course-switcher-*.png in App/Tests/__Snapshots__). UNVERIFIED visually: a person reviews the PNGs.
extension ShellSnapshotTests {
    func testCourseSwitcherLight() async throws {
        try renderCourses(await courseSwitcherView(rtl: false), name: "course-switcher-light")
    }

    func testCourseSwitcherRtl() async throws {
        try renderCourses(await courseSwitcherView(rtl: true), name: "course-switcher-rtl")
    }

    private func courseSwitcherView(rtl: Bool) async -> AnyView {
        let boot = BootstrapResponse(
            course: CourseRef(code: "fa", version: 1, manifestSha256: "h"),
            graders: [], enrolledCourseCodes: ["fa", "ja"], onboardingComplete: true)
        let model = CourseSwitcherModel(service: PreviewOnboardingService(), bootstrap: boot)
        await model.loadCatalog()
        return AnyView(
            CourseSwitcherView(model: model)
                .environment(\.layoutDirection, rtl ? .rightToLeft : .leftToRight))
    }

    private func renderCourses(_ view: AnyView, name: String) throws {
        let size = CGSize(width: 390, height: 844)
        let controller = UIHostingController(rootView: view)
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
