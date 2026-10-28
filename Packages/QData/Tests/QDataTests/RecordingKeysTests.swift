import XCTest
@testable import QData

final class RecordingKeysTests: XCTestCase {
    func testAudioPathClimbsToTheSharedAudioFolder() {
        XCTAssertEqual(RecordingKeys.storeKey(courseCode: "fa", version: 3, path: "../../../audio/abc.mp3"), "audio/abc.mp3")
    }

    func testPathInsideTheVersionStaysUnderIt() {
        XCTAssertEqual(RecordingKeys.storeKey(courseCode: "fa", version: 3, path: "./audio/abc.mp3"), "course/fa/v3/audio/abc.mp3")
    }

    func testPathThatClimbsOutOrIsEmptyHasNoKey() {
        XCTAssertNil(RecordingKeys.storeKey(courseCode: "fa", version: 3, path: "../../../../x.mp3"))
        XCTAssertNil(RecordingKeys.storeKey(courseCode: "fa", version: 3, path: ""))
        XCTAssertNil(RecordingKeys.storeKey(courseCode: "fa", version: 3, path: "/abs.mp3"))
    }
}
