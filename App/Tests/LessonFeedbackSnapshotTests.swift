import SwiftUI
import UIKit
import XCTest
import QFeatures
@testable import Qamooscheh

/// Extends ShellSnapshotTests so CI runs these in the snapshots job and uploads the PNGs
/// (lessonfeedback-*.png in App/Tests/__Snapshots__). UNVERIFIED visually: a person reviews the PNGs.
extension ShellSnapshotTests {
    func testLessonFeedbackCorrectLight() throws {
        try renderLessonFeedback(.correct, name: "lessonfeedback-correct-light", dark: false)
    }

    func testLessonFeedbackCorrectDark() throws {
        try renderLessonFeedback(.correct, name: "lessonfeedback-correct-dark", dark: true)
    }

    func testLessonFeedbackWrongLight() throws {
        try renderLessonFeedback(.wrongWithMistakeHint, name: "lessonfeedback-wrong-light", dark: false)
    }

    func testLessonFeedbackWrongDark() throws {
        try renderLessonFeedback(.wrongWithMistakeHint, name: "lessonfeedback-wrong-dark", dark: true)
    }

    func testLessonFeedbackResultsLight() throws {
        try renderLessonFeedback(.resultsWithStreakAndGoal, name: "lessonfeedback-results-light", dark: false)
    }

    func testLessonFeedbackResultsDark() throws {
        try renderLessonFeedback(.resultsWithStreakAndGoal, name: "lessonfeedback-results-dark", dark: true)
    }

    private func renderLessonFeedback(_ scenario: LessonFeedbackScenario, name: String, dark: Bool) throws {
        let size = CGSize(width: 390, height: 700)
        let controller = UIHostingController(rootView: LessonFeedbackShowcase(scenario))
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
