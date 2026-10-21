import SwiftUI
import UIKit
import XCTest
import QFeatures
@testable import Qamooscheh

/// Extends ShellSnapshotTests so CI runs these in the snapshots job and uploads the PNGs
/// (clozerace-*.png in App/Tests/__Snapshots__). UNVERIFIED visually: a person reviews the PNGs.
extension ShellSnapshotTests {
    func testClozeRacePickerLight() throws {
        try renderClozeRace(.picker, name: "clozerace-picker-light", dark: false)
    }

    func testClozeRacePickerDark() throws {
        try renderClozeRace(.picker, name: "clozerace-picker-dark", dark: true)
    }

    func testClozeRaceCardLight() throws {
        try renderClozeRace(.card, name: "clozerace-card-light", dark: false)
    }

    func testClozeRaceCardDark() throws {
        try renderClozeRace(.card, name: "clozerace-card-dark", dark: true)
    }

    func testClozeRaceCardAnsweredLight() throws {
        try renderClozeRace(.cardAnswered, name: "clozerace-cardAnswered-light", dark: false)
    }

    func testClozeRaceCardAnsweredDark() throws {
        try renderClozeRace(.cardAnswered, name: "clozerace-cardAnswered-dark", dark: true)
    }

    func testClozeRaceLobbyLight() throws {
        try renderClozeRace(.lobby, name: "clozerace-lobby-light", dark: false)
    }

    func testClozeRaceLobbyDark() throws {
        try renderClozeRace(.lobby, name: "clozerace-lobby-dark", dark: true)
    }

    func testClozeRaceRunLight() throws {
        try renderClozeRace(.run, name: "clozerace-run-light", dark: false)
    }

    func testClozeRaceRunDark() throws {
        try renderClozeRace(.run, name: "clozerace-run-dark", dark: true)
    }

    func testClozeRaceResultsLight() throws {
        try renderClozeRace(.results, name: "clozerace-results-light", dark: false)
    }

    func testClozeRaceResultsDark() throws {
        try renderClozeRace(.results, name: "clozerace-results-dark", dark: true)
    }

    func testClozeRaceResultsHeldLight() throws {
        try renderClozeRace(.resultsHeld, name: "clozerace-resultsHeld-light", dark: false)
    }

    func testClozeRaceResultsHeldDark() throws {
        try renderClozeRace(.resultsHeld, name: "clozerace-resultsHeld-dark", dark: true)
    }

    func testClozeRaceBoardsLight() throws {
        try renderClozeRace(.boards, name: "clozerace-boards-light", dark: false)
    }

    func testClozeRaceBoardsDark() throws {
        try renderClozeRace(.boards, name: "clozerace-boards-dark", dark: true)
    }

    private func renderClozeRace(_ scenario: ClozeRaceScenario, name: String, dark: Bool) throws {
        let size = CGSize(width: 390, height: 844)
        let controller = UIHostingController(rootView: ClozeRaceShowcase(scenario))
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
