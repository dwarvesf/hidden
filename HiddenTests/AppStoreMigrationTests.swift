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
            UserDefaults.Key.revealOnScrollEnabled, UserDefaults.Key.revealOnEmptyClickEnabled,
            UserDefaults.Key.revealOnShakeEnabled, UserDefaults.Key.newAppDefaultSection,
            UserDefaults.Key.findHiddenIconShortcut,
            UserDefaults.Key.presentationAutoMirrorEnabled, UserDefaults.Key.presentationSensitiveApps,
            UserDefaults.Key.presentationShortcut, UserDefaults.Key.rightClickAction,
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

    // Given the App Store copy running at launch, so the direct build collapses before the offer
    // When the first collapse wrote the separator state and the pinned-sections table
    // Then those writes do not count as the direct build's own settings, and the import is still offered
    func test_keysTheDirectBuildWritesAtLaunchDoNotBlockTheImport() {
        let launchWrites: [String: Any] = [UserDefaults.Key.areSeparatorsHidden: true,
                                           UserDefaultsPinnedSections.key: ["com.example.app": 1]]
        XCTAssertTrue(AppStoreSettingsImport.shouldOffer(containerValues: ["isAutoHide": false], directValues: launchWrites,
                                                         registeredDefaults: registered, alreadyAnswered: false))
        var chosen = launchWrites
        chosen["hoverToExpand"] = true
        XCTAssertFalse(AppStoreSettingsImport.shouldOffer(containerValues: ["isAutoHide": false], directValues: chosen,
                                                          registeredDefaults: registered, alreadyAnswered: false),
                       "a setting the user changed in this build still wins")
    }

    // Given the direct build's settings captured at launch
    // When something is written to its domain afterwards (an alert held the launch while the bar collapsed)
    // Then the import decision reads the launch values
    func test_importDecisionReadsTheSettingsAsLaunchFoundThem() throws {
        _ = try writeContainerPlist(["isAutoHide": false, "isAutoStart": true])
        let migration = AppStoreMigration(environment: .init(home: root, bundleURL: downloadsApp, bundleIdentifier: bundleID,
                                                             defaults: defaults, registeredDefaults: registered))
        migration.captureLaunchState()
        defaults.set(true, forKey: UserDefaults.Key.alwaysHiddenSectionEnabled)
        XCTAssertTrue(migration.wouldOfferImport)
        MigrationOfferLedger(defaults: defaults).recordAnswer(MigrationOfferLedger.importKey)
        XCTAssertFalse(migration.wouldOfferImport, "answered once, never again")
    }

    // MARK: open at login across the switch

    // Given the App Store build opened at login and the import offer is still to come
    // When the direct build sets up its login item at launch
    // Then it leaves the item alone instead of applying its own unset "off"
    func test_loginItemIsLeftAloneWhileTheImportIsPending() {
        XCTAssertFalse(LaunchLoginItem.shouldApply(importOfferPending: true, containerOpensAtLogin: true, directAutoStart: false))
        XCTAssertTrue(LaunchLoginItem.shouldApply(importOfferPending: false, containerOpensAtLogin: true, directAutoStart: false),
                      "once answered, this build's setting applies")
        XCTAssertTrue(LaunchLoginItem.shouldApply(importOfferPending: true, containerOpensAtLogin: false, directAutoStart: false))
        XCTAssertTrue(LaunchLoginItem.shouldApply(importOfferPending: true, containerOpensAtLogin: true, directAutoStart: true))
        XCTAssertTrue(AppStoreSettingsImport.opensAtLogin(["isAutoStart": true]))
        XCTAssertFalse(AppStoreSettingsImport.opensAtLogin(["isAutoStart": false]))
        XCTAssertFalse(AppStoreSettingsImport.opensAtLogin(nil))
    }

    // Given the App Store build opened at login
    // When the user answers "Not now" to the import, and Hidden Bar launches again
    // Then "Open at login" stays on in this build, and nothing else is copied
    func test_notNowKeepsOpenAtLogin() {
        let written = AppStoreSettingsImport.applyDecline(["isAutoStart": true, "isAutoHide": false, "arrowStyle": "chevron"], to: defaults)
        XCTAssertEqual(written, [UserDefaults.Key.isAutoStart])
        XCTAssertTrue(defaults.bool(forKey: UserDefaults.Key.isAutoStart))
        XCTAssertEqual(defaults.persistentDomain(forName: suiteName).map { Set($0.keys) }, [UserDefaults.Key.isAutoStart])
        // The next launch: the offer is answered, so this build's value applies, and it is on.
        XCTAssertTrue(LaunchLoginItem.shouldApply(importOfferPending: false, containerOpensAtLogin: true,
                                                  directAutoStart: defaults.bool(forKey: UserDefaults.Key.isAutoStart)))
        XCTAssertTrue(defaults.bool(forKey: UserDefaults.Key.isAutoStart))

        let off = UserDefaults(suiteName: suiteName + ".off")!
        defer { off.removePersistentDomain(forName: suiteName + ".off") }
        XCTAssertEqual(AppStoreSettingsImport.applyDecline(["isAutoStart": false, "isAutoHide": false], to: off), [])
        XCTAssertNil(off.persistentDomain(forName: suiteName + ".off")?[UserDefaults.Key.isAutoStart])
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

    // Given an older direct copy (1.8 to 1.12) running from another folder
    // When this newer copy opens
    // Then it offers "Quit and Switch" instead of quitting silently
    func test_olderDirectCopyIsOfferedAQuit() {
        let older = OtherRunningCopy.Instance(pid: 42, bundleURL: URL(fileURLWithPath: "/Applications/Hidden Bar.app"),
                                              isAppStoreBuild: false, version: "1.12")
        XCTAssertEqual(OtherRunningCopy.decide(others: [older], runningBundle: downloadsApp, runningVersion: "1.13.0"),
                       .offerToReplaceOlderCopy(42))
        let v18 = OtherRunningCopy.Instance(pid: 43, bundleURL: URL(fileURLWithPath: "/Applications/Hidden Bar.app"),
                                            isAppStoreBuild: false, version: "1.8")
        XCTAssertEqual(OtherRunningCopy.decide(others: [v18], runningBundle: downloadsApp, runningVersion: "1.13.0"),
                       .offerToReplaceOlderCopy(43))
    }

    // Given another direct copy that is not older, or whose version is unknown, or a relaunch of this same copy
    // When this copy opens
    // Then it brings that copy forward and quits, as before
    func test_directCopyNotOlderStillWinsSilently() {
        func copy(_ version: String?, _ path: String = "/Applications/Hidden Bar.app") -> OtherRunningCopy.Instance {
            .init(pid: 42, bundleURL: URL(fileURLWithPath: path), isAppStoreBuild: false, version: version)
        }
        XCTAssertEqual(OtherRunningCopy.decide(others: [copy("1.13.0")], runningBundle: downloadsApp, runningVersion: "1.13.0"), .quitInFavorOf(42))
        XCTAssertEqual(OtherRunningCopy.decide(others: [copy("1.14")], runningBundle: downloadsApp, runningVersion: "1.13.0"), .quitInFavorOf(42))
        XCTAssertEqual(OtherRunningCopy.decide(others: [copy(nil)], runningBundle: downloadsApp, runningVersion: "1.13.0"), .quitInFavorOf(42))
        XCTAssertEqual(OtherRunningCopy.decide(others: [copy("1.12", downloadsApp.path)], runningBundle: downloadsApp, runningVersion: "1.13.0"),
                       .quitInFavorOf(42), "a relaunch of the same bundle path")
        XCTAssertTrue(OtherRunningCopy.isOlder("1.9", than: "1.13.0"))
        XCTAssertTrue(OtherRunningCopy.isOlder("1.12.3", than: "1.13"))
        XCTAssertFalse(OtherRunningCopy.isOlder("1.13.0", than: "1.13.0"))
        XCTAssertFalse(OtherRunningCopy.isOlder(nil, than: "1.13.0"))
        XCTAssertFalse(OtherRunningCopy.isOlder("1.12", than: nil))
    }

    // Given an import from the App Store build
    // When its settings are applied
    // Then the pinned-sections notice goes out too, as the engine and the catalog listen to it, not to prefsChanged
    func test_importTellsTheAppAboutPinnedSections() {
        XCTAssertTrue(AppDelegate.importedPreferenceNotifications.contains(.pinnedSectionsChanged))
        XCTAssertTrue(AppDelegate.importedPreferenceNotifications.contains(.prefsChanged))
    }

    // Given the migration alerts and the status card's button
    // When looking in every Localizable.strings the app ships
    // Then each locale carries them with the same placeholders, so none shows a raw key or drops a path
    func test_everyLocale_carriesTheMigrationStrings() {
        let keys = [
            "Hidden Bar from the App Store is running. Quit it and switch to this version?",
            "Only one Hidden Bar can run at a time. The App Store version stays installed until you choose otherwise.",
            "Hidden Bar %@ is running. Quit it and switch to this version?",
            "Only one Hidden Bar can run at a time. The older version stays where it is until you choose otherwise.",
            "Quit and Switch",
            "Cancel",
            "Import your settings from the App Store version?",
            "Hidden Bar from the App Store keeps its settings in a separate place. Import them so this version starts the way you set it up.",
            "Import",
            "Not now",
            "Move the App Store copy to the Trash?",
            "The App Store version of Hidden Bar is still installed:\n%@\nYou can restore it from the Trash later.",
            "Move to Trash",
            "Hidden Bar could not move the App Store copy to the Trash",
            "Drag it to the Trash in Finder instead:\n%@",
            "The App Store copy is in /Applications. Quit Hidden Bar, move /Applications/Hidden Bar.app to the Trash, drag this copy into Applications, then open it from there.",
            "This account can't add apps to /Applications. Ask an administrator to drag Hidden Bar into /Applications, then open it from there.",
            "Hidden Bar is running from outside Applications. The copy already in Applications goes to the Trash, then Hidden Bar relaunches from there.",
            "Hidden Bar is running from outside Applications. Move it there so it keeps working after you empty Downloads, then relaunch.",
            "Move Hidden Bar to the Applications folder?",
            "Move to Applications",
            "Hidden Bar can hide icons only from /Applications",
            "OK",
            "a temporary folder",
            "Hidden Bar cannot hide icons on macOS 27",
            "macOS 27 no longer lets App Store apps hide menu-bar icons. Hidden Bar from github.com/consolelabs/hidden (free, open source) works on macOS 27.",
            "Open github.com/consolelabs/hidden",
            "Close",
            "Don't show again",
            "Hidden Bar on macOS 27",
            "macOS 27: get the working version...",
            "Or install it with Homebrew:",
            "Quit this App Store version and move it to the Trash first. Homebrew does not install over it.",
        ]
        let localizations = Bundle.main.localizations.filter { $0 != "Base" }
        XCTAssertGreaterThan(localizations.count, 5)
        for locale in localizations {
            guard let path = Bundle.main.path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: locale),
                  let table = NSDictionary(contentsOfFile: path) as? [String: String] else {
                XCTFail("no Localizable.strings for \(locale)")
                continue
            }
            for key in keys {
                guard let value = table[key] else { XCTFail("\(locale) is missing \"\(key)\""); continue }
                for token in ["%@", "\n"] {
                    XCTAssertEqual(value.components(separatedBy: token).count, key.components(separatedBy: token).count,
                                   "\(locale) \"\(key)\" changes the \(token) count")
                }
            }
        }
    }

    // Given a build that does not use the native engine
    // When the app registers its shortcuts
    // Then the palette and presentation shortcuts are not registered; with the native engine they are
    func test_paletteAndPresentationShortcutsExistOnlyWithTheNativeEngine() {
        let registry = HotKeyRegistry(defaults: defaults, center: NotificationCenter()) { _, _ in nil }
        AppDelegate.registerNativeEngineHotKeys(in: registry, usesNativeEngine: false, togglePalette: {}, togglePresentation: {})
        XCTAssertEqual(registry.registeredKeys, [])

        AppDelegate.registerNativeEngineHotKeys(in: registry, usesNativeEngine: true, togglePalette: {}, togglePresentation: {})
        XCTAssertEqual(registry.registeredKeys, [UserDefaults.Key.findHiddenIconShortcut, UserDefaults.Key.presentationShortcut].sorted())
    }
}

#endif
