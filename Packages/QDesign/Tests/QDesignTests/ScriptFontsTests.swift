import XCTest
@testable import QDesign

final class ScriptFontsTests: XCTestCase {
    private let none: (String) -> Bool = { _ in false }
    private let all: (String) -> Bool = { _ in true }

    func testFallbackWhenNoFontsInstalled() {
        let fonts = ScriptFonts(persianFamily: nil, isAvailable: none)
        for script in ScriptKind.allCases {
            XCTAssertNil(fonts.resolvedFamily(for: script))
        }
        let naskh = ScriptFonts(persianFamily: "Noto Naskh Arabic", isAvailable: none)
        XCTAssertNil(naskh.resolvedFamily(for: .persian))
    }

    func testMappingWhenInstalled() {
        XCTAssertEqual(ScriptFonts(persianFamily: nil, isAvailable: all).resolvedFamily(for: .persian), "Vazirmatn")
        XCTAssertEqual(ScriptFonts(persianFamily: "Noto Naskh Arabic", isAvailable: all).resolvedFamily(for: .persian), "Vazirmatn")
        XCTAssertEqual(ScriptFonts(persianFamily: "Unknown", isAvailable: all).resolvedFamily(for: .persian), "Vazirmatn")
        XCTAssertNil(ScriptFonts(isAvailable: all).resolvedFamily(for: .japanese))
        XCTAssertNil(ScriptFonts(isAvailable: all).resolvedFamily(for: .latin))
    }

    func testRequestedFamilyIgnoresAvailability() {
        XCTAssertEqual(ScriptFonts(isAvailable: none).requestedFamily(for: .persian), "Vazirmatn")
        XCTAssertNil(ScriptFonts(isAvailable: none).requestedFamily(for: .japanese))
    }

    func testStyleSizesAscend() {
        let sizes = ScriptTextStyle.allCases.map { $0.size }
        XCTAssertEqual(sizes, sizes.sorted())
        XCTAssertEqual(Set(sizes).count, sizes.count)
    }

    func testRegisterWithoutFilesRegistersNothing() {
        XCTAssertEqual(ScriptFonts.registerBundledFonts(in: [Bundle(for: ScriptFontsTests.self)]), 0)
    }

    func testFontAccessorsBuildWithoutFiles() {
        let fonts = ScriptFonts(isAvailable: none)
        _ = fonts.font(.persian, style: .body)
        _ = fonts.font(.japanese, size: 20, weight: .bold)
    }

    func testWeightAndSizePctAccessorsBuild() {
        let fonts = ScriptFonts(isAvailable: all)
        _ = fonts.font(.persian, size: 20, weight: .bold, sizePct: 130, relativeTo: .title)
        _ = fonts.font(.persian, style: .prompt, weight: .semibold, sizePct: 80)
    }

    func testScaledSizeHonoursPercent() {
        XCTAssertEqual(ScriptFonts.scaledSize(20, sizePct: 100), 20)
        XCTAssertEqual(ScriptFonts.scaledSize(20, sizePct: 150), 30)
        XCTAssertEqual(ScriptFonts.scaledSize(20, sizePct: 0), 0.2, accuracy: 0.0001)
    }

    func testTextStylesMapToDynamicTypeStyles() {
        XCTAssertEqual(ScriptTextStyle.body.textStyle, .body)
        XCTAssertEqual(ScriptTextStyle.display.textStyle, .largeTitle)
    }
}
