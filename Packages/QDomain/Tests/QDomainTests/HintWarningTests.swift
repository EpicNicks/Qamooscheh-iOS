import XCTest
@testable import QDomain

final class HintWarningTests: XCTestCase {
    private func freshDefaults() -> UserDefaults {
        let name = "HintWarningTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    func testDefaultShowsTheWarning() {
        XCTAssertTrue(UserDefaultsHintWarningPrefs(defaults: freshDefaults()).showsHintWarning)
    }

    func testPreferencePersists() {
        let defaults = freshDefaults()
        let prefs = UserDefaultsHintWarningPrefs(defaults: defaults)
        prefs.showsHintWarning = false
        XCTAssertFalse(UserDefaultsHintWarningPrefs(defaults: defaults).showsHintWarning)
        prefs.showsHintWarning = true
        XCTAssertTrue(UserDefaultsHintWarningPrefs(defaults: defaults).showsHintWarning)
    }

    func testGate() {
        XCTAssertTrue(HintWarningGate.shouldWarn(prefEnabled: true, hintAlreadyUsed: false))
        XCTAssertFalse(HintWarningGate.shouldWarn(prefEnabled: true, hintAlreadyUsed: true))
        XCTAssertFalse(HintWarningGate.shouldWarn(prefEnabled: false, hintAlreadyUsed: false))
        XCTAssertFalse(HintWarningGate.shouldWarn(prefEnabled: false, hintAlreadyUsed: true))
    }

    func testGateReadsThePrefs() {
        let prefs = UserDefaultsHintWarningPrefs(defaults: freshDefaults())
        XCTAssertTrue(HintWarningGate.shouldWarn(prefs: prefs, hintAlreadyUsed: false))
        prefs.showsHintWarning = false
        XCTAssertFalse(HintWarningGate.shouldWarn(prefs: prefs, hintAlreadyUsed: false))
    }
}
