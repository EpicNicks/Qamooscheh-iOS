import XCTest
import QModel
import QData
@testable import QFeatures

private struct PreviewFailed: Error {}

private final class Calls: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [Int] = []

    func record(_ version: Int) {
        lock.lock()
        items.append(version)
        lock.unlock()
    }

    var all: [Int] {
        lock.lock()
        defer { lock.unlock() }
        return items
    }
}

private func makePreview() -> RollForwardPreviewResponse {
    RollForwardPreviewResponse(
        courseCode: "fa", fromVersion: 3, toVersion: 4, manifestSha256: "b",
        from: RollForwardPositionRef(unitKey: "u1", skillKey: "s1", unitIndex: 0, lessonIndex: 0),
        to: RollForwardPositionRef(unitKey: "u1", skillKey: "s1", unitIndex: 0, lessonIndex: 0),
        clamped: false, unitClamped: false, lessonClamped: false)
}

@MainActor
final class UpdateBannerModelTests: XCTestCase {
    private let eligible = ContentUpdateOffer(version: 4, manifestSha256: "b", eligible: true)
    private let ineligible = ContentUpdateOffer(version: 4, manifestSha256: "b", eligible: false)

    func testRequestUpdateOpensConfirmationFromPreview() async {
        let model = UpdateBannerModel(offer: eligible)
        let calls = Calls()
        await model.requestUpdate(courseCode: "fa") { _, version in
            calls.record(version)
            return makePreview()
        }
        XCTAssertEqual(calls.all, [4])
        guard case .ready(let confirmation)? = model.dialog else { return XCTFail("expected ready") }
        XCTAssertEqual(confirmation.title, "Update to version 4?")
        XCTAssertTrue(confirmation.unchanged)
        XCTAssertEqual(model.state, .idle, "nothing applied before confirm")
    }

    func testIneligibleOfferNeverRequestsPreview() async {
        let model = UpdateBannerModel(offer: ineligible)
        let calls = Calls()
        await model.requestUpdate(courseCode: "fa") { _, version in
            calls.record(version)
            return makePreview()
        }
        XCTAssertEqual(calls.all, [])
        XCTAssertNil(model.dialog)
    }

    func testPreviewFailureShowsMessageAndCannotConfirm() async {
        let model = UpdateBannerModel(offer: eligible)
        await model.requestUpdate(courseCode: "fa") { _, _ in throw PreviewFailed() }
        XCTAssertEqual(model.dialog, .failed("Couldn't check this update."))
    }

    func testCancelClosesDialogWithoutApplying() async {
        let model = UpdateBannerModel(offer: eligible)
        await model.requestUpdate(courseCode: "fa") { _, _ in makePreview() }
        model.cancelConfirmation()
        XCTAssertNil(model.dialog)
        XCTAssertEqual(model.state, .idle)
        XCTAssertNotNil(model.offer)
    }

    func testConfirmAppliesOnlyFromReadyDialog() async {
        let model = UpdateBannerModel(offer: eligible)
        await model.requestUpdate(courseCode: "fa") { _, _ in makePreview() }
        let calls = Calls()
        let task = model.confirm { offer, _ in calls.record(offer.version) }
        XCTAssertNil(model.dialog)
        XCTAssertEqual(model.state, .downloading(DownloadProgress(done: 0, discovered: 0)))
        await task?.value
        XCTAssertEqual(calls.all, [4])
        XCTAssertEqual(model.state, .idle)
        XCTAssertNil(model.offer)
    }

    func testCancelAfterConfirmDoesNotUndoApply() async {
        let model = UpdateBannerModel(offer: eligible)
        await model.requestUpdate(courseCode: "fa") { _, _ in makePreview() }
        let calls = Calls()
        let task = model.confirm { offer, _ in calls.record(offer.version) }
        model.cancelConfirmation()
        await task?.value
        XCTAssertEqual(calls.all, [4])
    }

    func testConfirmIsNoOpAfterCancel() async {
        let model = UpdateBannerModel(offer: eligible)
        await model.requestUpdate(courseCode: "fa") { _, _ in makePreview() }
        model.cancelConfirmation()
        let calls = Calls()
        XCTAssertNil(model.confirm { offer, _ in calls.record(offer.version) })
        XCTAssertEqual(calls.all, [])
        XCTAssertEqual(model.state, .idle)
    }

    func testConfirmIsNoOpWithoutDialogOrWhileFailed() async {
        let calls = Calls()
        let none = UpdateBannerModel(offer: eligible)
        XCTAssertNil(none.confirm { offer, _ in calls.record(offer.version) })

        let failed = UpdateBannerModel(offer: eligible)
        await failed.requestUpdate(courseCode: "fa") { _, _ in throw PreviewFailed() }
        XCTAssertNil(failed.confirm { offer, _ in calls.record(offer.version) })
        XCTAssertEqual(calls.all, [])
    }

    func testConfirmFailureShowsMessageAndKeepsOffer() async {
        let model = UpdateBannerModel(offer: eligible)
        await model.requestUpdate(courseCode: "fa") { _, _ in makePreview() }
        let task = model.confirm { _, _ in throw PreviewFailed() }
        await task?.value
        guard case .failed = model.state else { return XCTFail("expected failed") }
        XCTAssertNotNil(model.offer)
    }
}
