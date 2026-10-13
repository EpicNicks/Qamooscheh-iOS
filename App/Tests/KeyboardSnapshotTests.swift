import SwiftUI
import UIKit
import XCTest
import QFeatures
@testable import Qamooscheh

/// Extends ShellSnapshotTests so CI runs these in the snapshots job and uploads the PNGs
/// (keyboard-*.png in App/Tests/__Snapshots__). UNVERIFIED visually: a person reviews the PNGs.
extension ShellSnapshotTests {
    func testKeyboardPersianNativeLight() throws {
        try renderKeyboard(.persianNative, name: "keyboard-persian-native-light", width: 390, dark: false)
    }

    func testKeyboardPersianPhoneticCandidatesLight() throws {
        try renderKeyboard(.persianPhonetic, name: "keyboard-persian-phonetic-light", width: 390, dark: false)
    }

    func testKeyboardKanaLight() throws {
        try renderKeyboard(.kana, name: "keyboard-kana-light", width: 390, dark: false)
    }

    func testKeyboardKanaDakutenLight() throws {
        try renderKeyboard(.kanaDakuten, name: "keyboard-kana-dakuten-light", width: 390, dark: false)
    }

    func testKeyboardPersianPhoneticDark() throws {
        try renderKeyboard(.persianPhonetic, name: "keyboard-persian-phonetic-dark", width: 390, dark: true)
    }

    func testKeyboardKanaSmallWidth() throws {
        try renderKeyboard(.kana, name: "keyboard-kana-se", width: 320, dark: false)
    }

    private func renderKeyboard(_ scenario: KeyboardShowcaseScenario, name: String, width: CGFloat, dark: Bool) throws {
        let size = CGSize(width: width, height: 480)
        let controller = UIHostingController(rootView: KeyboardShowcase(scenario))
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
