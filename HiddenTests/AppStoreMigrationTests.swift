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
            UserDefaults.Key.pinnedSectionsEnabled, UserDefaultsPinnedSections.key,
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
        XCTAssertTrue(MoveToApplications.isInApplicationsFolder(URL(fileURLWithPath: "/Applications/Hidden Bar.app")))
        XCTAssertTrue(MoveToApplications.isInApplicationsFolder(URL(fileURLWithPath: "/Applications/Utilities/Hidden Bar.app")))
        XCTAssertFalse(MoveToApplications.isInApplicationsFolder(URL(fileURLWithPath: "/Users/x/Applications/Hidden Bar.app")),
                       "macOS 27 hides the arrow of a copy in ~/Applications")
        XCTAssertFalse(MoveToApplications.isInApplicationsFolder(URL(fileURLWithPath: "/Users/x/Downloads/Hidden Bar.app")))
        XCTAssertFalse(MoveToApplications.isInApplicationsFolder(URL(fileURLWithPath: "/ApplicationsOld/Hidden Bar.app")))
        XCTAssertTrue(MoveToApplications.isTranslocated(URL(fileURLWithPath: "/private/var/folders/ab/T/AppTranslocation/1234/d/Hidden Bar.app")))
        XCTAssertEqual(MoveToApplications.destination(for: URL(fileURLWithPath: "/Users/x/Downloads/Hidden Bar.app")).path,
                       "/Applications/Hidden Bar.app")
    }

    // Fake answers: the plan reads no disk, so writability and the App Store copy are parameters.
    private func plan(_ running: String = "/Users/x/Downloads/Hidden Bar.app", answered: Bool = false,
                      writable: Bool = true, masInApplications: Bool = false) -> MoveToApplications.Plan {
        MoveToApplications.plan(runningBundle: URL(fileURLWithPath: running), alreadyAnswered: answered,
                                applicationsWritable: writable, applicationsHoldsAppStoreCopy: masInApplications)
    }

    func testMoveGoesToApplicationsWhenItCan() {
        XCTAssertEqual(plan(), .moveToApplications(URL(fileURLWithPath: "/Applications/Hidden Bar.app")))
        XCTAssertEqual(plan("/Users/x/Applications/Hidden Bar.app"), .moveToApplications(URL(fileURLWithPath: "/Applications/Hidden Bar.app")))
        XCTAssertEqual(plan("/Applications/Hidden Bar.app"), MoveToApplications.Plan.none)
        XCTAssertEqual(plan(answered: true), MoveToApplications.Plan.none, "offered once")
    }

    /// Dead end: "Not now" to the Trash left the App Store copy in /Applications
    /// and the move offer never showed, nor anything else.
    func testKeptAppStoreCopyInApplicationsExplainsWhatToDo() {
        XCTAssertEqual(plan(masInApplications: true), .explainAppStoreCopyKept)
        XCTAssertEqual(plan(answered: true, masInApplications: true), MoveToApplications.Plan.none)
    }

    /// Dead end: a standard account cannot write /Applications.
    func testUnwritableApplicationsExplainsWhatToDo() {
        XCTAssertEqual(plan(writable: false), .explainNotWritable)
        XCTAssertEqual(plan(writable: false, masInApplications: true), .explainNotWritable)
    }

    /// The move check reads the real folder: a fake /Applications on disk.
    func testMovePlanReadsTheFolderAndTheKeptAppStoreCopy() throws {
        let downloads = try makeBundle("Downloads/Hidden Bar.app", bundleID: bundleID, appStore: false)
        let system = root.appendingPathComponent("SystemApplications")
        try FileManager.default.createDirectory(at: system, withIntermediateDirectories: true)
        func migration() -> AppStoreMigration {
            AppStoreMigration(environment: .init(home: root, bundleURL: downloads, bundleIdentifier: bundleID,
                                                 defaults: defaults, registeredDefaults: registered,
                                                 systemApplications: system))
        }
        XCTAssertEqual(migration().movePlan, .moveToApplications(system.appendingPathComponent("Hidden Bar.app")))

        _ = try makeBundle("SystemApplications/Hidden Bar.app", bundleID: bundleID, appStore: true)
        XCTAssertEqual(migration().movePlan, .explainAppStoreCopyKept)

        // The Trash answer does not matter.
        MigrationOfferLedger(defaults: defaults).recordAnswer(MigrationOfferLedger.trashKey)
        XCTAssertEqual(migration().movePlan, .explainAppStoreCopyKept)
    }

    // MARK: another copy already running

    private let downloadsApp = URL(fileURLWithPath: "/Users/x/Downloads/Hidden Bar.app")

    private func instance(_ pid: pid_t, _ path: String, appStore: Bool) -> OtherRunningCopy.Instance {
        .init(pid: pid, bundleURL: URL(fileURLWithPath: path), isAppStoreBuild: appStore)
    }

    /// Dead end: the App Store copy runs at login and the direct build quit silently.
    func testRunningAppStoreCopyIsOfferedAQuit() {
        let others = [instance(41, "/Applications/Hidden Bar.app", appStore: true)]
        XCTAssertEqual(OtherRunningCopy.decide(others: others, runningBundle: downloadsApp), .offerToReplaceAppStoreCopy(41))
    }

    func testRunningDirectCopyStillWinsSilently() {
        XCTAssertEqual(OtherRunningCopy.decide(others: [instance(42, "/Applications/Hidden Bar.app", appStore: false)],
                                               runningBundle: downloadsApp), .quitInFavorOf(42))
        XCTAssertEqual(OtherRunningCopy.decide(others: [instance(41, "/Applications/Hidden Bar.app", appStore: true),
                                                        instance(42, "/Users/x/Applications/Hidden Bar.app", appStore: false)],
                                               runningBundle: downloadsApp), .quitInFavorOf(42),
                       "a direct copy is already running; nothing to switch")
        XCTAssertEqual(OtherRunningCopy.decide(others: [], runningBundle: downloadsApp), .launch)
    }

    func testDebugRulesOnlyCountTheSamePathUnlessForced() {
        let installed = instance(42, "/Applications/Hidden Bar.app", appStore: false)
        let appStore = instance(41, "/Applications/Hidden Bar.app", appStore: true)
        let relaunch = instance(43, downloadsApp.path, appStore: false)
        XCTAssertEqual(OtherRunningCopy.decide(others: [installed, appStore], runningBundle: downloadsApp,
                                               countsOtherPaths: false, countsAppStoreCopies: false), .launch)
        XCTAssertEqual(OtherRunningCopy.decide(others: [installed, appStore], runningBundle: downloadsApp,
                                               countsOtherPaths: false, countsAppStoreCopies: true), .offerToReplaceAppStoreCopy(41))
        XCTAssertEqual(OtherRunningCopy.decide(others: [appStore, relaunch], runningBundle: downloadsApp,
                                               countsOtherPaths: false, countsAppStoreCopies: true), .quitInFavorOf(43))
    }
}

#endif
