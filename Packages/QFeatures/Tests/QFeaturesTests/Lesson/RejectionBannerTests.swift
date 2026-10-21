import XCTest
@testable import QFeatures

private actor FakeRejections: RejectionSource {
    var items: [RejectedLesson]
    private(set) var dismissed: [String] = []
    init(_ items: [RejectedLesson]) { self.items = items }
    func rejected() async -> [RejectedLesson] { items }
    func dismiss(_ ids: [String]) async {
        dismissed += ids
        items.removeAll { ids.contains($0.id) }
    }
}

@MainActor
final class RejectionBannerTests: XCTestCase {
    func testShowsRejectionsWithReasonAndDismisses() async {
        let source = FakeRejections([RejectedLesson(id: "a", reason: "stale course version")])
        let model = RejectionBannerModel(source: source)
        XCTAssertFalse(model.isVisible)
        await model.refresh()
        XCTAssertTrue(model.isVisible)
        XCTAssertEqual(model.reason, "stale course version")
        await model.dismiss()
        XCTAssertFalse(model.isVisible)
        let dismissed = await source.dismissed
        XCTAssertEqual(dismissed, ["a"])
        await model.refresh()
        XCTAssertFalse(model.isVisible)
    }

    func testMessageMatchesLedgerCopy() {
        XCTAssertEqual(
            RejectionBannerModel.message,
            "A Parsle you finished offline wasn't saved, so it won't count toward your review schedule.")
    }
}
