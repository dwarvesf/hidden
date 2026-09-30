import XCTest
@testable import Hidden_Bar

final class GlobalShortcutTests: XCTestCase {
    private func shortcut(keyCode: UInt32 = 0, flags: UInt32 = 0,
                          function: Bool = false, capsLock: Bool = false) -> GlobalKeybindPreferences {
        GlobalKeybindPreferences(function: function, control: false, command: false,
                                shift: false, option: false, capsLock: capsLock,
                                carbonFlags: flags, characters: "a", keyCode: keyCode)
    }

    func testBareTypingAndCapsLockAreRejected() {
        XCTAssertFalse(shortcut().isValidGlobalShortcut)
        XCTAssertFalse(shortcut(flags: 1 << 10, capsLock: true).isValidGlobalShortcut)
        XCTAssertFalse(shortcut(function: true).isValidGlobalShortcut)
    }

    func testCarbonShortcutModifiersAreAccepted() {
        for flags: UInt32 in [1 << 8, 1 << 9, 1 << 11, 1 << 12] {
            XCTAssertTrue(shortcut(flags: flags).isValidGlobalShortcut)
        }
    }

    func testStandaloneFunctionKeyIsAccepted() {
        XCTAssertTrue(shortcut(keyCode: 79).isValidGlobalShortcut)
    }

    func testInvalidRecordingPreservesSavedShortcut() {
        let previous = Preferences.globalKey
        defer { Preferences.globalKey = previous }
        let saved = shortcut(flags: 1 << 8)
        Preferences.globalKey = saved
        let controller = PreferencesViewController()
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                                     timestamp: 0, windowNumber: 0, context: nil,
                                     characters: "a", charactersIgnoringModifiers: "a",
                                     isARepeat: false, keyCode: 0)!
        controller.updateGlobalShortcut(event)
        XCTAssertEqual(Preferences.globalKey?.carbonFlags, saved.carbonFlags)
        XCTAssertEqual(Preferences.globalKey?.keyCode, saved.keyCode)
    }
}
