import XCTest
@testable import QDomain

final class PersianFaceTests: XCTestCase {
    func testNilFamilyIsVazirmatn() {
        XCTAssertEqual(PersianFace.of(nil), .vazirmatn)
    }

    func testRemovedNaskhFamilyFallsBackToDefault() {
        XCTAssertEqual(PersianFace.of("Noto Naskh Arabic"), .vazirmatn)
        XCTAssertEqual(PersianFace.allCases, [.vazirmatn])
    }

    func testUnknownFamilyFallsBackToDefault() {
        XCTAssertEqual(PersianFace.of("Tahoma"), .vazirmatn)
    }

    func testLabelsAndBundling() {
        XCTAssertEqual(PersianFace.vazirmatn.label, "Vazirmatn")
        XCTAssertTrue(PersianFace.vazirmatn.isBundled)
    }
}
