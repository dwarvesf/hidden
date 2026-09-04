import XCTest
@testable import Hidden_Bar

/// Contract: Preferences.notchOverflowEnabled and AppDelegate's default
/// values must give the user an explicit, persistent, discoverable way to
/// turn the notch-overflow feature off — the exact gap the reviewer on #350
/// flagged ("should we have a way to enable/disable this feature
/// manually?") that the original PR never actually wired into any UI.
/// Serves: the Preferences checkbox (PreferencesViewController) and
/// StatusBarController's context-menu rebuild, both of which depend on this
/// preference's get/set/notify contract.
/// Behaviors covered (3): fresh-install default is `true`, setting the
/// preference persists the new value, and setting it posts the
/// `.notchOverflowToggle` notification StatusBarController listens for.
/// Mock boundary: none — exercises the real `UserDefaults.standard` and
/// `NotificationCenter.default`, saving/restoring prior state around each
/// test since this preference is process-wide shared state, matching how
/// the rest of this codebase's Preferences enum already works (no DI seam
/// exists there to mock against).
final class NotchOverflowPreferencesTests: XCTestCase {

    private var priorValue: Bool!

    override func setUp() {
        super.setUp()
        priorValue = UserDefaults.standard.bool(forKey: UserDefaults.Key.notchOverflowEnabled)
    }

    override func tearDown() {
        UserDefaults.standard.set(priorValue, forKey: UserDefaults.Key.notchOverflowEnabled)
        super.tearDown()
    }

    // Given a fresh install (defaults never registered by the user)
    // When reading the app's declared default preference values
    // Then notchOverflowEnabled defaults to true
    func test_defaultPreferenceValues_notchOverflowEnabledDefaultsToTrue() {
        let defaults = AppDelegate.defaultPreferenceValues

        XCTAssertEqual(defaults[UserDefaults.Key.notchOverflowEnabled] as? Bool, true,
                       "a first-time user should see notch overflow available without opting in")
    }

    // Given the preference is set to false
    // When reading it back
    // Then it reports false (the setter/getter round-trip persists correctly)
    func test_settingPreferenceFalse_persistsAndReadsBackFalse() {
        Preferences.notchOverflowEnabled = false

        XCTAssertFalse(Preferences.notchOverflowEnabled, "the preference must persist the value it was set to")
    }

    // Given an observer registered for the toggle notification
    // When the preference is set
    // Then the .notchOverflowToggle notification fires
    func test_settingPreference_postsNotchOverflowToggleNotification() {
        let expectation = expectation(forNotification: .notchOverflowToggle, object: nil)

        Preferences.notchOverflowEnabled = !priorValue

        wait(for: [expectation], timeout: 1.0)
    }
}
