import XCTest
@testable import QDomain

final class IsiriLayoutTests: XCTestCase {
    func testRowsHoldAll32LettersOnceEach() {
        XCTAssertEqual(IsiriLayout.rows.map { $0.count }, [12, 11, 9])
        let letters = IsiriLayout.rows.flatMap { $0 }.map { $0.letter }
        XCTAssertEqual(Set(letters).count, 32)
    }

    func testRowContentsReadInIsiriOrder() {
        XCTAssertEqual(IsiriLayout.rows[0].map { $0.letter }.joined(), "ضصثقفغعهخحجچ")
        XCTAssertEqual(IsiriLayout.rows[1].map { $0.letter }.joined(), "شسیبلاتنمکگ")
        XCTAssertEqual(IsiriLayout.rows[2].map { $0.letter }.joined(), "ظطزرذدپوژ")
    }

    func testUsKeyMapsToLetterAtSamePosition() {
        let m = IsiriLayout.physicalKeyToIsiri
        XCTAssertEqual(m["q"], "ض")
        XCTAssertEqual(m["h"], "ا")
        XCTAssertEqual(m["["], "ج")
        XCTAssertEqual(m["]"], "چ")
        XCTAssertEqual(m[";"], "ک")
        XCTAssertEqual(m["'"], "گ")
        XCTAssertEqual(m[","], "و")
        XCTAssertEqual(m["."], "ژ")
        XCTAssertEqual(m.count, 32)
        XCTAssertNil(m["Q"])
    }

    func testShiftLayerAddsFourDistinctLetters() {
        var out: [String: String] = [:]
        for (k, v) in IsiriLayout.shift {
            out[k] = String(Character(Unicode.Scalar(v)!))
        }
        XCTAssertEqual(out, ["KeyH": "آ", "KeyA": "ؤ", "KeyS": "ئ", "KeyM": "ء"])
    }
}
