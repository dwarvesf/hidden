import XCTest
import AppKit
@testable import Hidden_Bar

/// Contract: a test run never reads or writes the shipping app's preferences
/// domain (`com.dwarvesv.minimalbar`) and never acts on the real install. The
/// test host launches with the shipping bundle id, so `UserDefaults.standard`
/// there IS the user's real domain; the app goes through `AppDefaults.store`,
/// a dedicated suite under XCTest.
/// Serves: AppDefaults (store and side-effect policy), Preferences, AutoStart,
/// StatusBarController (autosaved item names).
/// Behaviors covered: the store is a suite and not the standard domain, Preferences
/// writes land in the suite and leave the real domain byte-for-byte unchanged, the
/// suite is wiped when it is first built, the side-effect policy per input, a test
/// host skips login items and the second-copy quit, and its status items are not
/// autosaved into the real domain.
/// Mock boundary: none; the real domain is only ever read, through CFPreferences.
final class PrefsIsolationTests: XCTestCase {

    private static let realDomain = "com.dwarvesv.minimalbar"

    /// Every key in the shipping app's domain, read without writing anything.
    private func realDomainSnapshot() -> NSDictionary {
        CFPreferencesAppSynchronize(Self.realDomain as CFString)
        let keys = CFPreferencesCopyKeyList(Self.realDomain as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as? [String] ?? []
        let values = CFPreferencesCopyMultiple(keys as CFArray, Self.realDomain as CFString,
                                               kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as? [String: Any] ?? [:]
        return values as NSDictionary
    }

    // Given a test run
    // When the app asks for its preferences store
    // Then it is the dedicated test suite, not the real domain's standard store
    func test_store_isTheTestSuiteUnderXCTest() {
        XCTAssertTrue(AppDefaults.isRunningUnderXCTest)
        XCTAssertFalse(AppDefaults.store === UserDefaults.standard)
        XCTAssertEqual(AppDefaults.testSuiteName, "com.dwarvesv.minimalbar.tests")
    }

    // Given the real domain as it is before any preference is written
    // When Preferences setters run (a bool, a double, an enum, a notification-posting one)
    // Then the values are in the suite and the real domain is exactly as it was
    func test_preferenceWrites_leaveTheRealDomainUntouched() {
        let before = realDomainSnapshot()
        let priorHover = Preferences.hoverToExpand
        let priorSeconds = Preferences.numberOfSecondForAutoHide
        let priorStyle = Preferences.arrowStyle
        defer {
            Preferences.hoverToExpand = priorHover
            Preferences.numberOfSecondForAutoHide = priorSeconds
            Preferences.arrowStyle = priorStyle
            AppDefaults.store.removeObject(forKey: "prefsIsolationProbe")
        }

        Preferences.hoverToExpand = !priorHover
        Preferences.numberOfSecondForAutoHide = priorSeconds + 7
        Preferences.arrowStyle = ArrowStyle.allCases.first { $0 != priorStyle } ?? priorStyle
        AppDefaults.store.set("written by a test", forKey: "prefsIsolationProbe")

        XCTAssertEqual(Preferences.hoverToExpand, !priorHover, "the write reached the suite")
        XCTAssertEqual(AppDefaults.store.string(forKey: "prefsIsolationProbe"), "written by a test")
        XCTAssertEqual(realDomainSnapshot(), before, "a test wrote the real com.dwarvesv.minimalbar domain")
        XCTAssertNil(realDomainSnapshot()["prefsIsolationProbe"])
    }

    // Given stale keys left in the test suite by an earlier run
    // When the store is built for a test run
    // Then the suite is empty again, so no test depends on a previous run
    func test_makeStore_wipesTheSuite() throws {
        let suite = try XCTUnwrap(UserDefaults(suiteName: AppDefaults.testSuiteName))
        suite.set("stale", forKey: "prefsIsolationStale")
        XCTAssertEqual(suite.string(forKey: "prefsIsolationStale"), "stale")

        let rebuilt = AppDefaults.makeStore(underXCTest: true)

        XCTAssertNil(rebuilt.object(forKey: "prefsIsolationStale"))
        XCTAssertNil(suite.object(forKey: "prefsIsolationStale"))
    }

    // Given a shipping launch (not under XCTest)
    // When the store is built
    // Then it is the standard store, so the shipping app keeps its real preferences
    func test_makeStore_isStandardOutsideXCTest() {
        XCTAssertTrue(AppDefaults.makeStore(underXCTest: false) === UserDefaults.standard)
    }

    // Given each combination of test host, opt-in and environment
    // When asking whether host side effects may run
    // Then only a test host with no opt-in is blocked
    func test_sideEffectPolicy() {
        let none: [String: String] = [:]
        XCTAssertTrue(AppDefaults.allowsHostSideEffects(underXCTest: false, optedIn: false, environment: none))
        XCTAssertFalse(AppDefaults.allowsHostSideEffects(underXCTest: true, optedIn: false, environment: none))
        XCTAssertTrue(AppDefaults.allowsHostSideEffects(underXCTest: true, optedIn: true, environment: none))
        XCTAssertTrue(AppDefaults.allowsHostSideEffects(underXCTest: true, optedIn: false,
                                                        environment: [AppDefaults.sideEffectsOptInVariable: "1"]))
        XCTAssertFalse(AppDefaults.allowsHostSideEffects(underXCTest: true, optedIn: false,
                                                         environment: [AppDefaults.sideEffectsOptInVariable: "0"]))
    }

    // Given this test host
    // When asking what the app may do to the machine
    // Then side effects, login items and the second-copy quit are all off
    func test_testHost_skipsSideEffects() throws {
        try XCTSkipIf(AppDefaults.sideEffectsOptIn || ProcessInfo.processInfo.environment[AppDefaults.sideEffectsOptInVariable] == "1",
                      "this run opted in to host side effects")
        XCTAssertFalse(AppDefaults.allowsHostSideEffects)
        XCTAssertFalse(AutoStart.shouldTouchLoginItems())
        XCTAssertFalse(AutoStart.shouldEnforceSingleInstance())
    }

    // Given the app host this test runs in
    // When its status items were created
    // Then none carries an autosave name, which macOS would persist in the real domain
    func test_hostStatusItems_areNotAutosaved() throws {
        let delegate = try XCTUnwrap(NSApp.delegate as? AppDelegate)
        let names = ["hiddenbar_expandcollapse", "hiddenbar_separate", "hiddenbar_terminate"]
        for item in [delegate.statusBarController.toggleItem, delegate.statusBarController.separatorItem] {
            XCTAssertFalse(names.contains(item.autosaveName ?? ""), "autosaved as \(item.autosaveName ?? "")")
        }
    }
}
