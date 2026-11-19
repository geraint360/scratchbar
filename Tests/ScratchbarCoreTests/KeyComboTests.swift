import XCTest
@testable import ScratchbarCore

final class KeyComboTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUp() {
        suite = "KeyComboTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
    }

    func testDefaultIsControlOptionCommandN() {
        let combo = KeyCombo.defaultCombo
        XCTAssertEqual(combo.displayString, "⌃⌥⌘N")
        XCTAssertEqual(combo.keyCode, 45)
        XCTAssertEqual(combo.modifiers, KeyCombo.controlKey | KeyCombo.optionKey | KeyCombo.cmdKey)
    }

    func testDisplayOrderFollowsMacConvention() {
        let combo = KeyCombo(keyCode: 1, modifiers: KeyCombo.cmdKey | KeyCombo.shiftKey | KeyCombo.controlKey, key: "S")
        XCTAssertEqual(combo.displayString, "⌃⇧⌘S")
    }

    func testFirstLaunchEnabledWithDefault() {
        let s = HotKeySettings.load(defaults)
        XCTAssertTrue(s.enabled)
        XCTAssertEqual(s.combo, .defaultCombo)
    }

    func testSaveAndLoadRoundTrip() {
        let combo = KeyCombo(keyCode: 49, modifiers: KeyCombo.optionKey, key: "Space")
        HotKeySettings.save(enabled: true, combo: combo, to: defaults)
        let s = HotKeySettings.load(defaults)
        XCTAssertEqual(s.combo, combo)
        XCTAssertEqual(s.combo?.displayString, "⌥Space")
    }

    func testClearedComboPersistsAsNil() {
        HotKeySettings.save(enabled: true, combo: nil, to: defaults)
        XCTAssertNil(HotKeySettings.load(defaults).combo)
    }

    func testDisabledPersists() {
        HotKeySettings.save(enabled: false, combo: .defaultCombo, to: defaults)
        XCTAssertFalse(HotKeySettings.load(defaults).enabled)
    }

    func testComboNeedsCommandOptionOrControl() {
        XCTAssertFalse(KeyCombo(keyCode: 45, modifiers: KeyCombo.shiftKey, key: "N").isAcceptable)
        XCTAssertFalse(KeyCombo(keyCode: 45, modifiers: 0, key: "N").isAcceptable)
        XCTAssertTrue(KeyCombo(keyCode: 45, modifiers: KeyCombo.controlKey, key: "N").isAcceptable)
    }
}
