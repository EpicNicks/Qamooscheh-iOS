import SwiftUI
import UIKit
import XCTest
import QFeatures
@testable import Qamooscheh

/// Extends ShellSnapshotTests so CI runs these in the snapshots job and uploads the PNGs
/// (lessonscreen-*.png in App/Tests/__Snapshots__). UNVERIFIED visually: a person reviews the PNGs.
extension ShellSnapshotTests {
    func testLessonScreenWordBankActiveLight() throws {
        try renderLessonScreen(.wordBankActive, name: "lessonscreen-wordbank-active-light", dark: false)
    }

    func testLessonScreenWordBankActiveDark() throws {
        try renderLessonScreen(.wordBankActive, name: "lessonscreen-wordbank-active-dark", dark: true)
    }

    func testLessonScreenWordBankWrongLight() throws {
        try renderLessonScreen(.wordBankWrong, name: "lessonscreen-wordbank-wrong-light", dark: false)
    }

    func testLessonScreenWordBankWrongDark() throws {
        try renderLessonScreen(.wordBankWrong, name: "lessonscreen-wordbank-wrong-dark", dark: true)
    }

    func testLessonScreenTypeInKeyboardLight() throws {
        try renderLessonScreen(.typeInPersianKeyboard, name: "lessonscreen-typein-keyboard-light", dark: false)
    }

    func testLessonScreenTypeInKeyboardDark() throws {
        try renderLessonScreen(.typeInPersianKeyboard, name: "lessonscreen-typein-keyboard-dark", dark: true)
    }

    func testLessonScreenGradingPendingLight() throws {
        try renderLessonScreen(.gradingPending, name: "lessonscreen-grading-pending-light", dark: false)
    }

    func testLessonScreenGradingPendingDark() throws {
        try renderLessonScreen(.gradingPending, name: "lessonscreen-grading-pending-dark", dark: true)
    }

    func testLessonScreenLeaveLessonLight() throws {
        try renderLessonScreen(.leaveLessonModal, name: "lessonscreen-leave-lesson-light", dark: false)
    }

    func testLessonScreenLeaveLessonDark() throws {
        try renderLessonScreen(.leaveLessonModal, name: "lessonscreen-leave-lesson-dark", dark: true)
    }

    func testLessonScreenLeaveCheckpointLight() throws {
        try renderLessonScreen(.leaveCheckpointModal, name: "lessonscreen-leave-checkpoint-light", dark: false)
    }

    func testLessonScreenLeaveCheckpointDark() throws {
        try renderLessonScreen(.leaveCheckpointModal, name: "lessonscreen-leave-checkpoint-dark", dark: true)
    }

    func testLessonScreenSettingsPersianLight() throws {
        try renderLessonScreen(.settingsPersian, name: "lessonscreen-settings-fa-light", dark: false)
    }

    func testLessonScreenSettingsPersianDark() throws {
        try renderLessonScreen(.settingsPersian, name: "lessonscreen-settings-fa-dark", dark: true)
    }

    func testLessonScreenSettingsJapaneseLight() throws {
        try renderLessonScreen(.settingsJapanese, name: "lessonscreen-settings-ja-light", dark: false)
    }

    func testLessonScreenSettingsJapaneseDark() throws {
        try renderLessonScreen(.settingsJapanese, name: "lessonscreen-settings-ja-dark", dark: true)
    }

    private func renderLessonScreen(_ scenario: LessonScreenScenario, name: String, dark: Bool) throws {
        let size = CGSize(width: 390, height: 780)
        let controller = UIHostingController(rootView: LessonScreenShowcase(scenario))
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
