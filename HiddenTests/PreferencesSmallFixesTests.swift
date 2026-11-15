import XCTest
import AppKit
@testable import Hidden_Bar

/// Contract: the hover-to-expand setting has a Preferences checkbox bound to
/// `Preferences.hoverToExpand`, and the always-hidden tutorial text matches the
/// hiding engine the build runs (separator "|" versus the arrow as the boundary
/// on the macOS 27 direct build).
/// Serves: PreferencesViewController (switch row, tutorial popover), Preferences
/// (storage + notification), MenuBarEngineFactory (which engine), every
/// Localizable.strings.
/// Behaviors covered: off by default, setter round-trip + notification, the loaded
/// Preferences view shows the checkbox in the stored state, clicking it writes the
/// preference both ways, the tutorial key per engine, the engine choice per OS and
/// build, and both new string keys in every locale.
/// Mock boundary: none; real `UserDefaults.standard` restored after each test, like
/// StealthExpandIconTests.
final class PreferencesSmallFixesTests: XCTestCase {

    private var priorHover: Any?

    override func setUp() {
        super.setUp()
        priorHover = UserDefaults.standard.object(forKey: UserDefaults.Key.hoverToExpand)
    }

    override func tearDown() {
        if let priorHover {
            UserDefaults.standard.set(priorHover, forKey: UserDefaults.Key.hoverToExpand)
        } else {
            UserDefaults.standard.removeObject(forKey: UserDefaults.Key.hoverToExpand)
        }
        super.tearDown()
    }

    private func loadedPreferencesView() -> (PreferencesViewController, NSSwitch?) {
        let controller = PreferencesViewController(context: .live)
        _ = controller.view // loads the view and builds the form
        let checkBox = Self.allSubviews(of: controller.view)
            .compactMap { $0 as? NSSwitch }
            .first { $0.identifier == PreferencesViewController.hoverToExpandCheckBoxIdentifier }
        return (controller, checkBox)
    }

    /// A click as the user makes it: the switch flips, then sends its action.
    private func click(_ toggle: NSSwitch) {
        toggle.state = toggle.state == .on ? .off : .on
        toggle.sendAction(toggle.action, to: toggle.target)
    }

    private static func allSubviews(of view: NSView) -> [NSView] {
        view.subviews + view.subviews.flatMap { allSubviews(of: $0) }
    }

    // MARK: hover-to-expand storage

    // Given a fresh install
    // When reading the preference with nothing stored
    // Then hover-to-expand is off, so nothing changes for existing users
    func test_hoverToExpand_isOffByDefault() {
        UserDefaults.standard.removeObject(forKey: UserDefaults.Key.hoverToExpand)

        XCTAssertFalse(Preferences.hoverToExpand)
    }

    // Given the preference
    // When setting it
    // Then it reads back and announces the change (the status bar installs or removes its monitor on it)
    func test_hoverToExpand_setterRoundTripsAndPostsPrefsChanged() {
        for value in [true, false] {
            let posted = expectation(forNotification: .prefsChanged, object: nil)

            Preferences.hoverToExpand = value

            wait(for: [posted], timeout: 1)
            XCTAssertEqual(Preferences.hoverToExpand, value)
        }
    }

    // MARK: checkbox binding

    // Given a stored value of true
    // When the Preferences view loads
    // Then the hover checkbox is on, and off for a stored false
    func test_checkbox_showsTheStoredValue() {
        for stored in [true, false] {
            Preferences.hoverToExpand = stored

            let (_, checkBox) = loadedPreferencesView()

            XCTAssertNotNil(checkBox, "the Preferences view has no hover-to-expand checkbox")
            XCTAssertEqual(checkBox?.state, stored ? .on : .off)
        }
    }

    // Given the loaded view with the preference off
    // When the user clicks the checkbox twice
    // Then the preference turns on, then off
    func test_clickingTheCheckbox_writesThePreference() {
        Preferences.hoverToExpand = false
        let (_, checkBox) = loadedPreferencesView()
        guard let checkBox else { return XCTFail("the Preferences view has no hover-to-expand checkbox") }

        click(checkBox)
        XCTAssertTrue(Preferences.hoverToExpand)
        XCTAssertEqual(checkBox.state, .on)

        click(checkBox)
        XCTAssertFalse(Preferences.hoverToExpand)
        XCTAssertEqual(checkBox.state, .off)
    }

    // MARK: tutorial text per engine

    // Given each engine
    // When choosing the tutorial string
    // Then the native engine gets the arrow-boundary text and the separator engine the original
    func test_tutorialKey_followsTheEngine() {
        XCTAssertEqual(TutorialText.key(usesNativeEngine: true), "Tutorial text (arrow boundary)")
        XCTAssertEqual(TutorialText.key(usesNativeEngine: false), "Tutorial text")
    }

    // Given the English strings
    // When reading both tutorial variants
    // Then the separator text names the normal bar and the arrow text names the arrow, never "normal bar"
    func test_englishTutorials_matchTheirBoundary() throws {
        let separatorText = try Self.englishString("Tutorial text")
        let arrowText = try Self.englishString("Tutorial text (arrow boundary)")

        XCTAssertTrue(separatorText.contains("normal bar"))
        XCTAssertTrue(arrowText.contains("left of the arrow"))
        XCTAssertFalse(arrowText.contains("normal bar"))
    }

    // Given a macOS version
    // When asking which engine runs
    // Then the direct build is native from macOS 27, and not before
    func test_engineChoice_dependsOnBuildAndOS() {
        XCTAssertFalse(MenuBarEngineFactory.usesNativeEngine(osMajorVersion: 26))
        // This bundle is hosted by the direct build, which defines the native engine.
        XCTAssertTrue(MenuBarEngineFactory.usesNativeEngine(osMajorVersion: 27))
    }

    // MARK: strings

    // Given the two new keys
    // When looking in every Localizable.strings the app ships
    // Then each locale carries each key (English text is fine), so none shows a raw key
    func test_everyLocale_carriesTheNewKeys() {
        let keys = ["Expand the bar when the pointer rests on the menu bar", TutorialText.arrowBoundaryKey]
        let localizations = Bundle.main.localizations.filter { $0 != "Base" }

        XCTAssertGreaterThan(localizations.count, 5)
        for locale in localizations {
            guard let path = Bundle.main.path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: locale),
                  let table = NSDictionary(contentsOfFile: path) as? [String: String] else {
                XCTFail("no Localizable.strings for \(locale)")
                continue
            }
            for key in keys {
                XCTAssertNotNil(table[key], "\(locale) is missing \"\(key)\"")
            }
        }
    }

    private static func englishString(_ key: String) throws -> String {
        let path = try XCTUnwrap(Bundle.main.path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: "en"))
        let table = try XCTUnwrap(NSDictionary(contentsOfFile: path) as? [String: String])
        return try XCTUnwrap(table[key])
    }
}
