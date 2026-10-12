import XCTest
@testable import QDomain

final class PersianFaceTests: XCTestCase {
    func testNilFamilyIsVazirmatn() {
        XCTAssertEqual(PersianFace.of(nil), .vazirmatn)
    }

    func testKnownFamilyResolves() {
        XCTAssertEqual(PersianFace.of("Noto Naskh Arabic"), .notoNaskh)
    }

    func testUnknownFamilyFallsBackToDefault() {
        XCTAssertEqual(PersianFace.of("Tahoma"), .vazirmatn)
    }

    func testLabelsAndBundling() {
        XCTAssertEqual(PersianFace.vazirmatn.label, "Vazirmatn")
        XCTAssertEqual(PersianFace.notoNaskh.label, "Noto Naskh")
        XCTAssertTrue(PersianFace.vazirmatn.isBundled)
        XCTAssertFalse(PersianFace.notoNaskh.isBundled)
    }
}
