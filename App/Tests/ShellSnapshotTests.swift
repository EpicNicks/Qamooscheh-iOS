import SnapshotTesting
import SwiftUI
import UIKit
import XCTest
@testable import Qamooscheh

/// Renders the empty shell and writes the PNG next to this file (uploaded by CI as an artifact).
/// Always records: there are no committed references yet, the PNG is for human review.
@MainActor
final class ShellSnapshotTests: XCTestCase {
    func testEmptyShell() throws {
        let controller = UIHostingController(rootView: RootTabView())
        let dir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("__Snapshots__")
            .path
        _ = verifySnapshot(
            of: controller,
            as: .image(on: .iPhone13),
            named: "shell",
            record: true,
            snapshotDirectory: dir
        )
        let files = try FileManager.default.contentsOfDirectory(atPath: dir)
        XCTAssertTrue(files.contains { $0.hasSuffix(".png") }, "no PNG written to \(dir)")
    }
}
