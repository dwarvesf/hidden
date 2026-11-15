import XCTest
@testable import Hidden_Bar

#if HIDDENBAR_NATIVE_VISIBILITY

/// Contract: switching from the App Store build imports only the preferences the
/// app defines, offers each step once, and finds App Store copies by receipt and
/// bundle id, never the running copy.
/// Mock boundary: a temp directory stands in for HOME and app bundles; a
/// throwaway UserDefaults suite stands in for the direct build's prefs.
final class AppStoreMigrationTests: XCTestCase {

    private let bundleID = "com.dwarvesv.minimalbar"
    private var root: URL!
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("AppStoreMigrationTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        suiteName = "AppStoreMigrationTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: root)
    }

    private var registered: [String: Any] { AppDelegate.defaultPreferenceValues }

    private func writeContainerPlist(_ values: [String: Any]) throws -> URL {
        let url = AppStoreSettingsImport.containerPreferencesURL(home: root, bundleIdentifier: bundleID)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(fromPropertyList: values, format: .binary, options: 0)
        try data.write(to: url)
        return url
    }

    private func makeBundle(_ relativePath: String, bundleID: String, appStore: Bool) throws -> URL {
        let app = root.appendingPathComponent(relativePath)
        let contents = app.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let info = try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": bundleID], format: .xml, options: 0)
        try info.write(to: contents.appendingPathComponent("Info.plist"))
        if appStore {
            let receipt = contents.appendingPathComponent("_MASReceipt")
            try FileManager.default.createDirectory(at: receipt, withIntermediateDirectories: true)
            try Data([0x30]).write(to: receipt.appendingPathComponent("receipt"))
        }
        return app
    }

    // MARK: whitelist import

    func testContainerPathMatchesTheSandboxLayout() {
        let url = AppStoreSettingsImport.containerPreferencesURL(home: URL(fileURLWithPath: "/Users/x"), bundleIdentifier: bundleID)
        XCTAssertEqual(url.path, "/Users/x/Library/Containers/com.dwarvesv.minimalbar/Data/Library/Preferences/com.dwarvesv.minimalbar.plist")
    }

    func testImportCopiesKnownKeysAndDropsTheRest() throws {
        let hotkey = Data([1, 2, 3])
        let url = try writeContainerPlist([
            "isAutoHide": false,
            "numberOfSecondForAutoHide": 30.0,
            "arrowStyle": "chevron",
            "globalKey": hotkey,
            "alwaysHiddenSectionEnabled": true,
            "SUEnableAutomaticChecks": true,
            "SULastCheckTime": Date(),
            "NSWindow Frame Preferences": "10 10 400 300",
            "NSStatusItem Preferred Position hiddenbar_separate": 120.0,
            "smAppServiceMigrated": true,
            "macOS27NoticeSuppressed": true,
            "somethingUnknown": "x",
        ])
        let container = try XCTUnwrap(AppStoreSettingsImport.readPlist(at: url))

        let written = AppStoreSettingsImport.apply(container, to: defaults)

        XCTAssertEqual(written, ["alwaysHiddenSectionEnabled", "arrowStyle", "globalKey", "isAutoHide", "numberOfSecondForAutoHide"])
        let stored = try XCTUnwrap(defaults.persistentDomain(forName: suiteName))
        XCTAssertEqual(Set(stored.keys), Set(written))
        XCTAssertEqual(defaults.object(forKey: "isAutoHide") as? Bool, false)
        XCTAssertEqual(defaults.double(forKey: "numberOfSecondForAutoHide"), 30.0)
        XCTAssertEqual(defaults.string(forKey: "arrowStyle"), "chevron")
        XCTAssertEqual(defaults.data(forKey: "globalKey"), hotkey)
    }

    func testWhitelistCoversEveryPreferenceKeyTheAppDefines() {
        let appKeys: Set<String> = [
            UserDefaults.Key.globalKey, UserDefaults.Key.numberOfSecondForAutoHide, UserDefaults.Key.isAutoStart,
            UserDefaults.Key.isAutoHide, UserDefaults.Key.isShowPreference, UserDefaults.Key.areSeparatorsHidden,
            UserDefaults.Key.alwaysHiddenSectionEnabled, UserDefaults.Key.useFullStatusBarOnExpandEnabled,
            UserDefaults.Key.stealthExpandIconEnabled, UserDefaults.Key.arrowStyle, UserDefaults.Key.hoverToExpand,
            UserDefaults.Key.notchOverflowEnabled, UserDefaults.Key.pauseHidingForUnkeepableItems,
        ]
        XCTAssertEqual(Set(AppStoreSettingsImport.importableKeys.keys), appKeys)
    }

    func testWrongTypedValueIsDropped() {
        let result = AppStoreSettingsImport.importable(from: ["arrowStyle": 3, "globalKey": "not data", "isAutoHide": "yes"])
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: when to offer the import

    func testOffersWhenContainerIsCustomizedAndDirectIsEmpty() {
        XCTAssertTrue(AppStoreSettingsImport.shouldOffer(containerValues: ["isAutoHide": false],
                                                         directValues: [:], registeredDefaults: registered,
                                                         alreadyAnswered: false))
    }

    func testOffersWhenDirectHoldsOnlyDefaultsAndUnknownKeys() {
        let direct: [String: Any] = ["isAutoHide": true, "numberOfSecondForAutoHide": 10.0,
                                     "smAppServiceMigrated": true, "NSStatusItem Visible hiddenbar_separate": true]
        XCTAssertTrue(AppStoreSettingsImport.shouldOffer(containerValues: ["arrowStyle": "chevron"],
                                                         directValues: direct, registeredDefaults: registered,
                                                         alreadyAnswered: false))
    }

    func testNoOfferWithoutContainerPlist() throws {
        let missing = AppStoreSettingsImport.readPlist(at: AppStoreSettingsImport.containerPreferencesURL(home: root, bundleIdentifier: bundleID))
        XCTAssertNil(missing)
        XCTAssertFalse(AppStoreSettingsImport.shouldOffer(containerValues: missing, directValues: [:],
                                                          registeredDefaults: registered, alreadyAnswered: false))
    }

    func testNoOfferWhenContainerHoldsOnlyDefaultsOrUnknownKeys() {
        let container: [String: Any] = ["isAutoHide": true, "SUEnableAutomaticChecks": false, "somethingUnknown": 1]
        XCTAssertFalse(AppStoreSettingsImport.shouldOffer(containerValues: container, directValues: [:],
                                                          registeredDefaults: registered, alreadyAnswered: false))
    }

    func testNoOfferWhenDirectIsAlreadyCustomized() {
        XCTAssertFalse(AppStoreSettingsImport.shouldOffer(containerValues: ["isAutoHide": false],
                                                          directValues: ["hoverToExpand": true],
                                                          registeredDefaults: registered, alreadyAnswered: false))
    }

    func testOfferIsShownOnlyOnceAfterAnyAnswer() {
        let ledger = MigrationOfferLedger(defaults: defaults)
        XCTAssertFalse(ledger.isAnswered(MigrationOfferLedger.importKey))
        ledger.recordAnswer(MigrationOfferLedger.importKey)

        let later = MigrationOfferLedger(defaults: UserDefaults(suiteName: suiteName)!)
        XCTAssertTrue(later.isAnswered(MigrationOfferLedger.importKey), "the answer must persist across launches")
        XCTAssertFalse(AppStoreSettingsImport.shouldOffer(containerValues: ["isAutoHide": false], directValues: [:],
                                                          registeredDefaults: registered,
                                                          alreadyAnswered: later.isAnswered(MigrationOfferLedger.importKey)))
        XCTAssertFalse(later.isAnswered(MigrationOfferLedger.trashKey), "each offer keeps its own answer")
        XCTAssertFalse(later.isAnswered(MigrationOfferLedger.moveKey))
    }

    // MARK: second copy detection

    func testFindsTheAppStoreCopyButNeverTheRunningOne() throws {
        let running = try makeBundle("Downloads/Hidden Bar.app", bundleID: bundleID, appStore: false)
        let masCopy = try makeBundle("Applications/Hidden Bar.app", bundleID: bundleID, appStore: true)
        let directCopy = try makeBundle("Other/Hidden Bar.app", bundleID: bundleID, appStore: false)
        let otherApp = try makeBundle("Applications/Other.app", bundleID: "com.example.other", appStore: true)
        let missing = root.appendingPathComponent("Nowhere/Hidden Bar.app")

        let found = AppStoreCopyFinder.appStoreCopies(candidates: [running, masCopy, directCopy, otherApp, missing, masCopy],
                                                      bundleIdentifier: bundleID, runningBundle: running)
        XCTAssertEqual(found.map(\.lastPathComponent), ["Hidden Bar.app"])
        XCTAssertEqual(found.first?.standardizedFileURL.path, masCopy.standardizedFileURL.path)
    }

    func testRunningAppStoreCopyIsNotReportedAsASecondCopy() throws {
        let running = try makeBundle("Applications/Hidden Bar.app", bundleID: bundleID, appStore: true)
        let viaSymlink = root.appendingPathComponent("link.app")
        try FileManager.default.createSymbolicLink(at: viaSymlink, withDestinationURL: running)
        XCTAssertTrue(AppStoreCopyFinder.appStoreCopies(candidates: [running, viaSymlink],
                                                        bundleIdentifier: bundleID, runningBundle: running).isEmpty)
    }

    func testWellKnownCandidatesCoverBothApplicationsFolders() {
        let home = URL(fileURLWithPath: "/Users/x")
        XCTAssertEqual(AppStoreCopyFinder.wellKnownCandidates(home: home, appName: "Hidden Bar").map(\.path),
                       ["/Applications/Hidden Bar.app", "/Users/x/Applications/Hidden Bar.app"])
    }

    // MARK: move into /Applications

    func testApplicationsFolderDetection() {
        let home = URL(fileURLWithPath: "/Users/x")
        XCTAssertTrue(MoveToApplications.isInApplicationsFolder(URL(fileURLWithPath: "/Applications/Hidden Bar.app"), home: home))
        XCTAssertTrue(MoveToApplications.isInApplicationsFolder(URL(fileURLWithPath: "/Applications/Utilities/Hidden Bar.app"), home: home))
        XCTAssertTrue(MoveToApplications.isInApplicationsFolder(URL(fileURLWithPath: "/Users/x/Applications/Hidden Bar.app"), home: home))
        XCTAssertFalse(MoveToApplications.isInApplicationsFolder(URL(fileURLWithPath: "/Users/x/Downloads/Hidden Bar.app"), home: home))
        XCTAssertFalse(MoveToApplications.isInApplicationsFolder(URL(fileURLWithPath: "/ApplicationsOld/Hidden Bar.app"), home: home))
        XCTAssertTrue(MoveToApplications.isTranslocated(URL(fileURLWithPath: "/private/var/folders/ab/T/AppTranslocation/1234/d/Hidden Bar.app")))
        XCTAssertEqual(MoveToApplications.destination(for: URL(fileURLWithPath: "/Users/x/Downloads/Hidden Bar.app")).path,
                       "/Applications/Hidden Bar.app")
    }

    func testMoveOfferRules() {
        let home = URL(fileURLWithPath: "/Users/x")
        let downloads = URL(fileURLWithPath: "/Users/x/Downloads/Hidden Bar.app")
        func offer(_ url: URL = downloads, answered: Bool = false, masAtDestination: Bool = false, writable: Bool = true) -> Bool {
            MoveToApplications.shouldOffer(runningBundle: url, home: home, alreadyAnswered: answered,
                                           destinationIsAppStoreCopy: masAtDestination, applicationsWritable: writable)
        }
        XCTAssertTrue(offer())
        XCTAssertFalse(offer(URL(fileURLWithPath: "/Applications/Hidden Bar.app")))
        XCTAssertFalse(offer(answered: true), "offered once")
        XCTAssertFalse(offer(masAtDestination: true), "the Trash offer handles the App Store copy first")
        XCTAssertFalse(offer(writable: false))
    }
}

#endif
