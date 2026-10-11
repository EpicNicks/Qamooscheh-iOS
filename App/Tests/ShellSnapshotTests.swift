import SnapshotTesting
import SwiftUI
import UIKit
import XCTest
@testable import Qamooscheh

/// Renders the empty shell in a real window, fails if the render is blank,
/// and writes the PNG next to this file (uploaded by CI as an artifact).
@MainActor
final class ShellSnapshotTests: XCTestCase {
    func testEmptyShell() throws {
        let size = CGSize(width: 390, height: 844)
        let controller = UIHostingController(rootView: RootTabView())
        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.frame = window.bounds
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.5))

        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        XCTAssertGreaterThan(distinctColors(of: image), 3, "render is blank or uniform")

        let dir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("__Snapshots__")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try XCTUnwrap(image.pngData(), "PNG encoding failed")
        let file = dir.appendingPathComponent("shell.png")
        try data.write(to: file)

        // Record mode: no committed references yet, so a record message is expected;
        // any other verification failure fails the test.
        let result = verifySnapshot(
            of: controller,
            as: .image(on: .iPhone13),
            named: "shell-recorded",
            record: true,
            snapshotDirectory: dir.path
        )
        if let result = result {
            XCTAssertTrue(result.lowercased().contains("record"), "snapshot verification failed: \(result)")
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path), "no PNG at \(file.path)")
    }

    private func distinctColors(of image: UIImage) -> Int {
        guard let cg = image.cgImage else { return 0 }
        let w = 64, h = 128
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(
            data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return 0 }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        var seen = Set<UInt32>()
        for i in stride(from: 0, to: pixels.count, by: 4) {
            seen.insert(UInt32(pixels[i]) << 16 | UInt32(pixels[i + 1]) << 8 | UInt32(pixels[i + 2]))
        }
        return seen.count
    }
}
