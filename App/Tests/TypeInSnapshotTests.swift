import SwiftUI
import UIKit
import XCTest
import QFeatures
@testable import Qamooscheh

/// Extends ShellSnapshotTests so CI runs these in the snapshots job and uploads the PNGs
/// (typein-*.png in App/Tests/__Snapshots__). UNVERIFIED visually: a person reviews the PNGs.
extension ShellSnapshotTests {
    func testTypeInPersianEmptyLight() throws {
        try renderTypeIn(.persianEmpty, name: "typein-persian-empty-light", dark: false)
    }

    func testTypeInPersianTypedLight() throws {
        try renderTypeIn(.persianTyped, name: "typein-persian-typed-light", dark: false)
    }

    func testTypeInJapaneseTypedLight() throws {
        try renderTypeIn(.japaneseTyped, name: "typein-japanese-typed-light", dark: false)
    }

    func testTypeInPersianMarkedWrongLight() throws {
        try renderTypeIn(.persianMarkedWrong, name: "typein-persian-wrong-light", dark: false)
    }

    func testTypeInJapaneseMarkedWrongLight() throws {
        try renderTypeIn(.japaneseMarkedWrong, name: "typein-japanese-wrong-light", dark: false)
    }

    func testTypeInPersianMarkedWrongDark() throws {
        try renderTypeIn(.persianMarkedWrong, name: "typein-persian-wrong-dark", dark: true)
    }

    func testTypeInPersianCorrectLight() throws {
        try renderTypeIn(.persianMarkedCorrect, name: "typein-persian-correct-light", dark: false)
    }

    func testTypeInNoVoiceLight() throws {
        try renderTypeIn(.noVoice, name: "typein-no-voice-light", dark: false)
    }

    func testTypeInSpeakLight() throws {
        try renderTypeIn(.speak, name: "typein-speak-light", dark: false)
    }

    private func renderTypeIn(_ scenario: TypeInShowcaseScenario, name: String, dark: Bool) throws {
        let size = CGSize(width: 390, height: 640)
        let controller = UIHostingController(rootView: TypeInShowcase(scenario))
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
        XCTAssertGreaterThan(data.count, 2000, "render looks blank")
    }
}
