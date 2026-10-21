import XCTest
@testable import QFeatures

final class LessonDraftCleanupTests: XCTestCase {
    func testRemoveAllDeletesOnlyThatUsersDrafts() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("drafts-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let mine = LessonDraftStore.key(userId: "u1", courseCode: "ja", unitKey: nil, skillKey: "s", practice: false, checkpoint: false)
        let mineToo = LessonDraftStore.key(userId: "u1", courseCode: "ja", unitKey: "x", skillKey: "s", practice: true, checkpoint: false)
        let other = LessonDraftStore.key(userId: "u10", courseCode: "ja", unitKey: nil, skillKey: "s", practice: false, checkpoint: false)
        for key in [mine, mineToo, other] {
            let url = dir.appendingPathComponent(LessonDraftStore.fileName(for: key))
            try Data("{}".utf8).write(to: url)
        }
        LessonDraftStore.removeAll(directory: dir, userId: "u1")
        let left = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertEqual(left, [LessonDraftStore.fileName(for: other)])
    }
}
