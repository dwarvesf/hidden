import XCTest
@testable import Hidden_Bar

/// Contract: Preferences.notchOverflowEnabled and AppDelegate's default
/// values must give the user an explicit, persistent, discoverable way to
/// turn the notch-overflow feature off — the exact gap the reviewer on #350
/// flagged ("should we have a way to enable/disable this feature
/// manually?") that the original PR never actually wired into any UI.
/// Serves: the Preferences checkbox (PreferencesViewController) and
/// StatusBarController's context menu, which reads this preference fresh
/// every time getContextMenu() builds a new menu for the next presentation
/// (see showContextMenu(from:)) rather than needing a push notification to
/// stay in sync.
/// Behaviors covered (2): fresh-install default is `true`, and setting the
/// preference persists the new value.
/// Mock boundary: none — exercises the real `UserDefaults.standard`, saving/
/// restoring prior state around each test since this preference is
/// process-wide shared state, matching how the rest of this codebase's
/// Preferences enum already works (no DI seam exists there to mock against).
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
}
