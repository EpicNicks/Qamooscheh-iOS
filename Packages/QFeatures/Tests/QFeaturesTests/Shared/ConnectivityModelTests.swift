import XCTest
@testable import QFeatures

private struct ScriptedSource: ConnectivitySource {
    let values: [Bool]
    func updates() -> AsyncStream<Bool> {
        AsyncStream { continuation in
            for value in values { continuation.yield(value) }
            continuation.finish()
        }
    }
}

@MainActor
final class ConnectivityModelTests: XCTestCase {
    func testStartsOnlineSoLaunchNeverFlashesTheStrip() {
        let model = ConnectivityModel(source: nil)
        XCTAssertTrue(model.isOnline)
        XCTAssertFalse(model.showsStrip)
    }

    func testFollowsTheSourceToOfflineAndBack() async {
        let offline = ConnectivityModel(source: ScriptedSource(values: [true, false]))
        await offline.watch()
        XCTAssertTrue(offline.showsStrip)

        let back = ConnectivityModel(source: ScriptedSource(values: [false, true]))
        await back.watch()
        XCTAssertFalse(back.showsStrip)
    }

    func testFixedModelsForPreviews() {
        XCTAssertTrue(ConnectivityModel.fixed(online: false).showsStrip)
        XCTAssertFalse(ConnectivityModel.fixed(online: true).showsStrip)
    }

    func testCopyMatchesTheLedger() {
        XCTAssertEqual(ConnectivityModel.message, "You're offline. Finished Parsles sync when you're back.")
    }
}
