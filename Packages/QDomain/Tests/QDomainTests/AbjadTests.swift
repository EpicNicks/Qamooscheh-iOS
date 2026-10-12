import XCTest
@testable import QDomain

final class AbjadTests: XCTestCase {
    func testHasAll32LettersEachOnce() {
        XCTAssertEqual(abjadLetters.count, 32)
        XCTAssertEqual(Set(abjadLetters.map { $0.letter }).count, 32)
    }

    func testMarksExactlyTheSevenNonJoiningLetters() {
        XCTAssertEqual(abjadLetters.filter { !$0.joinsNext }.map { $0.letter }.joined(), "ادذرزژو")
    }

    private func lettersFor(_ groups: [AbjadSoundGroup], _ sound: SoundId) -> String? {
        groups.first { $0.sound == sound }?.letters.map { $0.letter }.joined()
    }

    func testGroupsTheLettersThatShareASound() {
        let groups = abjadSoundGroups()
        XCTAssertEqual(lettersFor(groups, .s), "ثسص")
        XCTAssertEqual(lettersFor(groups, .z), "ذزضظ")
        XCTAssertEqual(lettersFor(groups, .h), "حه")
        XCTAssertEqual(lettersFor(groups, .t), "تط")
        XCTAssertEqual(lettersFor(groups, .gh), "غق")
    }

    func testOrdersGroupsByTheirFirstLettersPlaceInTheAlphabet() {
        let groups = abjadSoundGroups()
        XCTAssertEqual(groups.map { $0.letters[0].letter }.joined(), "ابپتثجچحخدذرژشعغفکگلمنوی")
    }

    private func letter(_ l: String) -> AbjadLetter {
        abjadLetters.first { $0.letter == l }!
    }

    func testLetterInFormExtendsAJoiningLetterTowardEachNeighborItJoins() {
        let be = letter("ب")
        XCTAssertEqual(LetterForm.allCases.map { letterInForm(be, $0) }, ["ب", "بـ", "ـبـ", "ـب"])
    }

    func testLetterInFormNeverExtendsANonJoinerToItsLeft() {
        let re = letter("ر")
        XCTAssertEqual(LetterForm.allCases.map { letterInForm(re, $0) }, ["ر", "ر", "ـر", "ـر"])
    }

    func testLetterFormsAreInIsolatedInitialMedialFinalOrder() {
        XCTAssertEqual(LetterForm.allCases, [.isolated, .initial, .medial, .final])
    }

    func testFlashcardsAreOneCardPerLetterCarryingSoundAndBothNameSpellings() {
        let cards = abjadFlashcards()
        XCTAssertEqual(cards.count, 32)
        let se = cards.first { $0.id == "ث" }
        XCTAssertNotNil(se)
        XCTAssertEqual(se?.nameRomanized, "se")
        XCTAssertEqual(se?.nameNative, "ثِ")
        XCTAssertEqual(se?.sound.label, "s")
    }

    func testEverySoundHasALabel() {
        XCTAssertEqual(Set(abjadSounds.keys), Set(SoundId.allCases))
        XCTAssertEqual(soundOf(.a).label, "ā / a / e / o")
        XCTAssertEqual(soundOf(.glottal).label, "'")
    }

    func testLetterNamesKeepTheirDiacriticsExactly() {
        let heh = letter("ه")
        XCTAssertEqual(heh.nameRomanized, "he (do-cheshm)")
        XCTAssertEqual(heh.nameNative, "هِ")
    }
}
