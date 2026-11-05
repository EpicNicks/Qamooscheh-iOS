import XCTest
@testable import QFeatures
import QDomain

#if canImport(AVFoundation)
/// Offline listening: the player only ever reads the on-disk store, so a take that is not there ends at once as `.failed`.
final class StoreRecordingPlayerTests: XCTestCase {
    func testMissingTakeFailsImmediatelyWithoutHanging() {
        var asked: [String] = []
        let player = StoreRecordingPlayer(read: { key in asked.append(key); return nil })
        var ends: [PlayEnd] = []
        player.play(keys: ["a", "b"], rate: 1) { ends.append($0) }
        XCTAssertEqual(ends, [.failed])
        XCTAssertEqual(asked, ["a", "b"], "every candidate is tried from the store, in order")
    }

    func testUndecodableTakeFails() {
        let player = StoreRecordingPlayer(read: { _ in Data([1, 2, 3]) })
        var ends: [PlayEnd] = []
        player.play(keys: ["a"], rate: 1) { ends.append($0) }
        XCTAssertEqual(ends, [.failed])
    }

    func testNoKeysFails() {
        let player = StoreRecordingPlayer(read: { _ in nil })
        var ends: [PlayEnd] = []
        player.play(keys: [], rate: 1) { ends.append($0) }
        XCTAssertEqual(ends, [.failed])
    }
}
#endif
