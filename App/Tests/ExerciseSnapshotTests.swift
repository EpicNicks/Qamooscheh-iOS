import SwiftUI
import UIKit
import XCTest
import QFeatures
@testable import Qamooscheh

/// Extends ShellSnapshotTests so CI runs these in the snapshots job and uploads the PNGs
/// (exercise-*.png in App/Tests/__Snapshots__). UNVERIFIED visually: a person reviews the PNGs.
extension ShellSnapshotTests {
    func testExercisePromptJapanese() throws { try renderExercise(.promptJapanese, name: "exercise-prompt-ja", height: 200, dark: false) }
    func testExercisePromptPersian() throws { try renderExercise(.promptPersian, name: "exercise-prompt-fa", height: 200, dark: false) }
    func testExerciseBankEmpty() throws { try renderExercise(.bankEmpty, name: "exercise-bank-empty", height: 260, dark: false) }
    func testExerciseBankPartial() throws { try renderExercise(.bankPartial, name: "exercise-bank-partial", height: 260, dark: false) }
    func testExerciseBankFull() throws { try renderExercise(.bankFull, name: "exercise-bank-full", height: 260, dark: false) }
    func testExerciseBankPersianRtl() throws { try renderExercise(.bankPersianRtl, name: "exercise-bank-rtl", height: 260, dark: false) }
    func testExerciseMatchSelected() throws { try renderExercise(.matchSelected, name: "exercise-match-selected", height: 260, dark: false) }
    func testExerciseMatchMatched() throws { try renderExercise(.matchMatched, name: "exercise-match-matched", height: 260, dark: false) }
    func testExerciseMatchWrong() throws { try renderExercise(.matchWrong, name: "exercise-match-wrong", height: 260, dark: false) }
    func testExerciseMatchWrongDark() throws { try renderExercise(.matchWrong, name: "exercise-match-wrong-dark", height: 260, dark: true) }

    private func renderExercise(_ scenario: ExerciseScenario, name: String, height: CGFloat, dark: Bool) throws {
        let size = CGSize(width: 390, height: height)
        let controller = UIHostingController(rootView: ExerciseShowcase(scenario))
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
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.6))

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
        XCTAssertGreaterThan(data.count, 1000, "render looks blank")
    }
}
