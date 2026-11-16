import XCTest
import AppKit
@testable import Hidden_Bar

/// Contract: the stealth-mode preference (issue #173) fades the arrow only
/// while the bar is collapsed, is off on a fresh install, and persists.
/// Serves: StatusBarController (arrow image) and the Preferences checkbox.
/// Behaviors covered (6): default off, setter round-trip, setter posts the
/// toggle notification, alpha rule for all four states, faded image keeps
/// template-ness, an opaque request returns the original image.
/// Mock boundary: none; the preference tests use the real `AppDefaults.store`
/// and restore the prior value, like NotchOverflowPreferencesTests.
final class StealthExpandIconTests: XCTestCase {

    private var priorValue: Any?

    override func setUp() {
        super.setUp()
        priorValue = AppDefaults.store.object(forKey: UserDefaults.Key.stealthExpandIconEnabled)
    }

    override func tearDown() {
        if let priorValue {
            AppDefaults.store.set(priorValue, forKey: UserDefaults.Key.stealthExpandIconEnabled)
        } else {
            AppDefaults.store.removeObject(forKey: UserDefaults.Key.stealthExpandIconEnabled)
        }
        super.tearDown()
    }

    // Given a fresh install
    // When reading the declared default values
    // Then stealth mode is off, so the arrow looks the same as before
    func test_defaultPreferenceValues_stealthIsOff() {
        let defaults = AppDelegate.defaultPreferenceValues

        XCTAssertEqual(defaults[UserDefaults.Key.stealthExpandIconEnabled] as? Bool, false)
    }

    // Given stealth mode is switched on, then off
    // When reading it back each time
    // Then it reports what was set
    func test_settingPreference_persistsBothWays() {
        Preferences.stealthExpandIconEnabled = true
        XCTAssertTrue(Preferences.stealthExpandIconEnabled)

        Preferences.stealthExpandIconEnabled = false
        XCTAssertFalse(Preferences.stealthExpandIconEnabled)
    }

    // Given an observer of the toggle notification
    // When the preference changes
    // Then the observer is told, so a collapsed arrow redraws at once
    func test_settingPreference_postsToggleNotification() {
        let posted = expectation(forNotification: .stealthExpandIconToggle, object: nil)

        Preferences.stealthExpandIconEnabled = true

        wait(for: [posted], timeout: 1)
    }

    // Given each combination of stealth and collapsed state
    // When asking for the arrow opacity
    // Then only stealth + collapsed fades it; every other state is opaque
    func test_expandIconAlpha_fadesOnlyWhenStealthAndCollapsed() {
        XCTAssertEqual(Assets.expandIconAlpha(stealthEnabled: true, isCollapsed: true), Assets.stealthExpandIconAlpha)
        XCTAssertEqual(Assets.expandIconAlpha(stealthEnabled: true, isCollapsed: false), 1)
        XCTAssertEqual(Assets.expandIconAlpha(stealthEnabled: false, isCollapsed: true), 1)
        XCTAssertEqual(Assets.expandIconAlpha(stealthEnabled: false, isCollapsed: false), 1)
        XCTAssertLessThan(Assets.stealthExpandIconAlpha, 0.2, "stealth must be nearly transparent")
        XCTAssertGreaterThan(Assets.stealthExpandIconAlpha, 0, "stealth must not be fully invisible")
    }

    // Given a template image
    // When it is drawn faded
    // Then the result keeps its size and stays a template, so the menu bar still tints it
    func test_fadedImage_keepsSizeAndTemplateFlag() {
        let source = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            NSColor.black.setFill()
            rect.fill()
            return true
        }
        source.isTemplate = true

        let faded = Assets.image(source, alpha: Assets.stealthExpandIconAlpha)

        XCTAssertNotNil(faded)
        XCTAssertFalse(faded === source)
        XCTAssertEqual(faded?.size, source.size)
        XCTAssertEqual(faded?.isTemplate, true)
    }

    // Given an opaque request
    // When asking for the image
    // Then the original image comes back untouched
    func test_image_atFullAlphaReturnsOriginal() {
        let source = NSImage(size: NSSize(width: 18, height: 18))

        XCTAssertTrue(Assets.image(source, alpha: 1) === source)
        XCTAssertNil(Assets.image(nil, alpha: 0.05))
    }
}
