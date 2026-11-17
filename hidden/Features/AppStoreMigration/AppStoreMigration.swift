//
//  AppStoreMigration.swift
//  Hidden Bar
//
//  Copyright © 2026 Dwarves Foundation. All rights reserved.
//

import AppKit

// Direct build only. Switching from the App Store build loses settings, because
// the sandboxed build keeps its prefs inside its container and the direct build
// reads ~/Library/Preferences. On launch the direct build offers, once each:
//   1. import the App Store build's settings (known keys only),
//   2. move a leftover App Store copy to the Trash,
//   3. move itself into /Applications, or say what to do when /Applications is
//      not writable or holds the App Store copy the user kept.
// Before those, an App Store copy that is already running is offered a quit
// instead of this build quitting silently.
// Nothing happens without the user's click. The App Store build compiles none of
// this: App Review 2.4.5(iv) forbids it from fetching or installing other apps.
#if HIDDENBAR_NATIVE_VISIBILITY

/// Records that the user answered an offer, so each one is shown at most once.
struct MigrationOfferLedger {
    static let importKey = "appStoreImportOfferAnswered"
    static let trashKey = "appStoreCopyTrashOfferAnswered"
    static let moveKey = "moveToApplicationsOfferAnswered"

    let defaults: UserDefaults

    func isAnswered(_ key: String) -> Bool { defaults.bool(forKey: key) }
    func recordAnswer(_ key: String) { defaults.set(true, forKey: key) }
}

/// The settings import, free of AppKit so it is testable with plain dictionaries.
enum AppStoreSettingsImport {
    enum Kind { case number, string, data, dictionary }

    /// Every preference the app defines, with the plist type it is stored as.
    /// Anything else in the container (Sparkle SU* keys, window frames, status
    /// item positions, internal flags) is never copied.
    static let importableKeys: [String: Kind] = [
        UserDefaults.Key.globalKey: .data,
        UserDefaults.Key.findHiddenIconShortcut: .data,
        UserDefaults.Key.numberOfSecondForAutoHide: .number,
        UserDefaults.Key.isAutoStart: .number,
        UserDefaults.Key.isAutoHide: .number,
        UserDefaults.Key.isShowPreference: .number,
        UserDefaults.Key.areSeparatorsHidden: .number,
        UserDefaults.Key.alwaysHiddenSectionEnabled: .number,
        UserDefaults.Key.useFullStatusBarOnExpandEnabled: .number,
        UserDefaults.Key.stealthExpandIconEnabled: .number,
        UserDefaults.Key.arrowStyle: .string,
        UserDefaults.Key.hoverToExpand: .number,
        UserDefaults.Key.revealOnScrollEnabled: .number,
        UserDefaults.Key.revealOnEmptyClickEnabled: .number,
        UserDefaults.Key.revealOnShakeEnabled: .number,
        UserDefaults.Key.notchOverflowEnabled: .number,
        UserDefaults.Key.pauseHidingForUnkeepableItems: .number,
        UserDefaults.Key.pinnedSectionsEnabled: .number,
        UserDefaults.Key.newAppDefaultSection: .number,
        UserDefaultsPinnedSections.key: .dictionary,
        UserDefaults.Key.presentationAutoMirrorEnabled: .number,
        UserDefaults.Key.presentationSensitiveApps: .dictionary,
        UserDefaults.Key.presentationShortcut: .data,
        UserDefaults.Key.rightClickAction: .string,
    ]

    static func containerPreferencesURL(home: URL, bundleIdentifier: String) -> URL {
        home.appendingPathComponent("Library/Containers/\(bundleIdentifier)/Data/Library/Preferences/\(bundleIdentifier).plist")
    }

    static func readPlist(at url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any]
    }

    /// Whitelisted keys whose value has the expected type; everything else dropped.
    static func importable(from values: [String: Any]) -> [String: Any] {
        values.filter { key, value in
            switch importableKeys[key] {
            case .number?: return value is NSNumber
            case .string?: return value is String
            case .data?: return value is Data
            case .dictionary?: return value is [String: Any]
            case nil: return false
            }
        }
    }

    /// A key is at its default when it is absent, or equals the registered
    /// default (false for keys with none registered).
    static func isDefault(_ key: String, in values: [String: Any], registeredDefaults: [String: Any]) -> Bool {
        guard let value = values[key] as? NSObject else { return true }
        let fallback = registeredDefaults[key] ?? false
        return value.isEqual(fallback)
    }

    static func customizedKeys(in values: [String: Any], registeredDefaults: [String: Any]) -> [String] {
        importable(from: values).keys
            .filter { !isDefault($0, in: values, registeredDefaults: registeredDefaults) }
            .sorted()
    }

    /// Offer only when the App Store build has customized settings, this build
    /// still has none of its own, and the user has not answered before.
    static func shouldOffer(containerValues: [String: Any]?,
                            directValues: [String: Any],
                            registeredDefaults: [String: Any],
                            alreadyAnswered: Bool) -> Bool {
        guard !alreadyAnswered, let containerValues else { return false }
        guard !customizedKeys(in: containerValues, registeredDefaults: registeredDefaults).isEmpty else { return false }
        return customizedKeys(in: directValues, registeredDefaults: registeredDefaults).isEmpty
    }

    /// Copies the importable values; returns the keys written.
    @discardableResult
    static func apply(_ containerValues: [String: Any], to defaults: UserDefaults) -> [String] {
        let values = importable(from: containerValues)
        for (key, value) in values { defaults.set(value, forKey: key) }
        return values.keys.sorted()
    }
}

/// Finds App Store copies of this app other than the one running.
enum AppStoreCopyFinder {
    static func isAppStoreBuild(_ bundleURL: URL, fileManager: FileManager = .default) -> Bool {
        fileManager.fileExists(atPath: bundleURL.appendingPathComponent("Contents/_MASReceipt/receipt").path)
    }

    static func bundleIdentifier(of bundleURL: URL) -> String? {
        let info = AppStoreSettingsImport.readPlist(at: bundleURL.appendingPathComponent("Contents/Info.plist"))
        return info?["CFBundleIdentifier"] as? String
    }

    /// The usual install spots, checked in addition to what Launch Services knows.
    static func wellKnownCandidates(home: URL, appName: String) -> [URL] {
        [URL(fileURLWithPath: "/Applications/\(appName).app"),
         home.appendingPathComponent("Applications/\(appName).app")]
    }

    static func appStoreCopies(candidates: [URL],
                               bundleIdentifier: String,
                               runningBundle: URL,
                               fileManager: FileManager = .default) -> [URL] {
        let running = runningBundle.resolvingSymlinksInPath().standardizedFileURL.path
        var seen = Set<String>()
        return candidates.filter { url in
            let path = url.resolvingSymlinksInPath().standardizedFileURL.path
            guard path != running, seen.insert(path).inserted else { return false }
            return self.bundleIdentifier(of: url) == bundleIdentifier
                && isAppStoreBuild(url, fileManager: fileManager)
        }
    }

    /// Signed by the Mac App Store (leaf certificate carries Apple's MAS
    /// marker). Catches an App Store copy whose receipt is missing.
    static func hasAppStoreSignature(_ bundleURL: URL) -> Bool {
        var code: SecStaticCode?
        var requirement: SecRequirement?
        guard SecStaticCodeCreateWithPath(bundleURL as CFURL, [], &code) == errSecSuccess, let code,
              SecRequirementCreateWithString("anchor apple generic and certificate leaf[field.1.2.840.113635.100.6.1.9] exists" as CFString,
                                             [], &requirement) == errSecSuccess, let requirement else { return false }
        return SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSBasicValidateOnly), requirement) == errSecSuccess
    }
}

/// What to do at launch when another copy with this bundle id is running.
/// The App Store copy often starts at login; quitting silently in front of it
/// made the downloaded build look broken.
enum OtherRunningCopy {
    struct Instance {
        let pid: pid_t
        let bundleURL: URL?
        let isAppStoreBuild: Bool
    }

    enum Decision: Equatable {
        case launch
        /// Another direct copy: bring it forward and quit, as before.
        case quitInFavorOf(pid_t)
        /// The App Store copy: ask before quitting it and taking over.
        case offerToReplaceAppStoreCopy(pid_t)
    }

    /// `others` are running apps with this bundle id, this process excluded.
    /// Debug builds pass `countsOtherPaths: false` so a dev build runs next to
    /// the installed copy, and `countsAppStoreCopies` to test the offer.
    static func decide(others: [Instance], runningBundle: URL,
                       countsOtherPaths: Bool = true, countsAppStoreCopies: Bool = true) -> Decision {
        let running = runningBundle.resolvingSymlinksInPath().standardizedFileURL.path
        func isSamePath(_ instance: Instance) -> Bool {
            instance.bundleURL?.resolvingSymlinksInPath().standardizedFileURL.path == running
        }
        let counted = others.filter { instance in
            if isSamePath(instance) { return true }
            return instance.isAppStoreBuild ? countsAppStoreCopies : countsOtherPaths
        }
        if let direct = counted.first(where: { !$0.isAppStoreBuild || isSamePath($0) }) {
            return .quitInFavorOf(direct.pid)
        }
        if let appStore = counted.first {
            return .offerToReplaceAppStoreCopy(appStore.pid)
        }
        return .launch
    }
}

/// Where to move the running copy so macOS 27 knows it by bundle id. Only
/// /Applications counts: run from ~/Applications, macOS 27 still hides the
/// arrow on collapse, like any folder outside /Applications.
enum MoveToApplications {
    enum Plan: Equatable {
        case none
        case moveToApplications(URL)
        /// The App Store copy the user kept holds /Applications/Hidden Bar.app.
        case explainAppStoreCopyKept
        /// This account cannot write to /Applications.
        case explainNotWritable
    }

    static func isInApplicationsFolder(_ bundleURL: URL) -> Bool {
        bundleURL.resolvingSymlinksInPath().standardizedFileURL.path.hasPrefix("/Applications/")
    }

    /// Gatekeeper runs a quarantined app from a read-only random path.
    static func isTranslocated(_ bundleURL: URL) -> Bool {
        bundleURL.path.contains("/AppTranslocation/")
    }

    static func destination(for bundleURL: URL, in folder: URL = URL(fileURLWithPath: "/Applications")) -> URL {
        folder.appendingPathComponent(bundleURL.lastPathComponent)
    }

    /// Independent of the Trash answer: when /Applications cannot take this
    /// copy, say what to do instead of skipping the offer in silence.
    static func plan(runningBundle: URL, alreadyAnswered: Bool,
                     applicationsWritable: Bool, applicationsHoldsAppStoreCopy: Bool,
                     systemApplications: URL = URL(fileURLWithPath: "/Applications")) -> Plan {
        guard !alreadyAnswered, !isInApplicationsFolder(runningBundle) else { return .none }
        guard applicationsWritable else { return .explainNotWritable }
        guard !applicationsHoldsAppStoreCopy else { return .explainAppStoreCopyKept }
        return .moveToApplications(destination(for: runningBundle, in: systemApplications))
    }
}

/// Runs the three offers at launch. Paths and defaults are injected so a
/// harness can point it at a fake home.
final class AppStoreMigration {
    struct Environment {
        var home: URL
        var bundleURL: URL
        var bundleIdentifier: String
        var defaults: UserDefaults
        var registeredDefaults: [String: Any]
        var fileManager: FileManager = .default
        var systemApplications = URL(fileURLWithPath: "/Applications")
    }

    static let shared = AppStoreMigration(environment: Environment(
        home: URL(fileURLWithPath: NSHomeDirectory()),
        bundleURL: Bundle.main.bundleURL,
        bundleIdentifier: Bundle.main.bundleIdentifier ?? "com.dwarvesv.minimalbar",
        defaults: AppDefaults.store,
        registeredDefaults: AppDelegate.defaultPreferenceValues))

    let environment: Environment
    private var ledger: MigrationOfferLedger { MigrationOfferLedger(defaults: environment.defaults) }

    init(environment: Environment) {
        self.environment = environment
    }

    #if DEBUG
    /// Debug builds run from DerivedData; launch with `-forceAppStoreMigration YES`
    /// to take the offers anyway.
    private static var isEnabled: Bool { AppDefaults.allowsHostSideEffects && AppDefaults.store.bool(forKey: "forceAppStoreMigration") }
    #else
    private static var isEnabled: Bool { AppDefaults.allowsHostSideEffects }
    #endif

    /// Called once from `applicationDidFinishLaunching`.
    func runAtLaunchIfNeeded(afterImport: @escaping () -> Void) {
        guard Self.isEnabled else { return }
        DispatchQueue.main.async { [self] in
            if offerImportIfNeeded() { afterImport() }
            // The move check waits for the Trash, so a copy just trashed from
            // /Applications frees that slot instead of pushing us elsewhere.
            offerTrashIfNeeded { [self] in offerMoveIfNeeded() }
        }
    }

    // MARK: Another copy already running

    /// Called before anything else at launch. Returns false when this process
    /// is quitting in favor of the copy already running.
    func resolveOtherRunningCopy() -> Bool {
        let current = ProcessInfo.processInfo.processIdentifier
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.bundleIdentifier == environment.bundleIdentifier && $0.processIdentifier != current
        }
        let others = apps.map { app in
            // Two bundles with one id can confuse Launch Services, so bundleURL
            // may name the other copy; the executable path is the process's own.
            let bundle = app.executableURL.map {
                $0.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            } ?? app.bundleURL
            return OtherRunningCopy.Instance(
                pid: app.processIdentifier, bundleURL: bundle,
                isAppStoreBuild: bundle.map {
                    AppStoreCopyFinder.isAppStoreBuild($0, fileManager: environment.fileManager)
                        || AppStoreCopyFinder.hasAppStoreSignature($0)
                } ?? false)
        }
        #if DEBUG
        let decision = OtherRunningCopy.decide(others: others, runningBundle: environment.bundleURL,
                                               countsOtherPaths: false, countsAppStoreCopies: Self.isEnabled)
        #else
        let decision = OtherRunningCopy.decide(others: others, runningBundle: environment.bundleURL)
        #endif
        NSLog("AppStoreMigration: other running copy decision \(decision)")

        switch decision {
        case .launch:
            return true
        case .quitInFavorOf(let pid):
            quit(inFavorOf: apps.first { $0.processIdentifier == pid })
            return false
        case .offerToReplaceAppStoreCopy(let pid):
            let appStoreCopy = apps.first { $0.processIdentifier == pid }
            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.messageText = "Hidden Bar from the App Store is running. Quit it and switch to this version?".localized
            alert.informativeText = "Only one Hidden Bar can run at a time. The App Store version stays installed until you choose otherwise.".localized
            alert.addButton(withTitle: "Quit and Switch".localized)
            alert.addButton(withTitle: "Cancel".localized)
            guard run(alert, id: "switch") == .alertFirstButtonReturn, let appStoreCopy else {
                quit(inFavorOf: appStoreCopy)
                return false
            }
            guard Self.terminate(appStoreCopy) else {
                NSLog("AppStoreMigration: the App Store copy did not quit")
                quit(inFavorOf: appStoreCopy)
                return false
            }
            return true
        }
    }

    private func quit(inFavorOf app: NSRunningApplication?) {
        app?.activate(options: [.activateAllWindows])
        NSApp.terminate(nil)
    }

    /// Asks the app to quit, then forces it; true once it has exited.
    private static func terminate(_ app: NSRunningApplication) -> Bool {
        func wait(_ seconds: TimeInterval) {
            let deadline = Date().addingTimeInterval(seconds)
            while !app.isTerminated && Date() < deadline {
                RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            }
        }
        app.terminate()
        wait(5)
        if !app.isTerminated {
            app.forceTerminate()
            wait(2)
        }
        return app.isTerminated
    }

    // MARK: Import

    private var containerValues: [String: Any]? {
        AppStoreSettingsImport.readPlist(at: AppStoreSettingsImport.containerPreferencesURL(
            home: environment.home, bundleIdentifier: environment.bundleIdentifier))
    }

    private var directValues: [String: Any] {
        environment.defaults.dictionaryRepresentation()
    }

    /// Returns true when settings were imported.
    @discardableResult
    func offerImportIfNeeded() -> Bool {
        let container = containerValues
        guard AppStoreSettingsImport.shouldOffer(containerValues: container,
                                                 directValues: directValues,
                                                 registeredDefaults: environment.registeredDefaults,
                                                 alreadyAnswered: ledger.isAnswered(MigrationOfferLedger.importKey)),
              let container else { return false }

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Import your settings from the App Store version?".localized
        alert.informativeText = "Hidden Bar from the App Store keeps its settings in a separate place. Import them so this version starts the way you set it up.".localized
        alert.addButton(withTitle: "Import".localized)
        alert.addButton(withTitle: "Not now".localized)

        switch run(alert, id: "import") {
        case .alertFirstButtonReturn:
            ledger.recordAnswer(MigrationOfferLedger.importKey)
            AppStoreSettingsImport.apply(container, to: environment.defaults)
            return true
        case .alertSecondButtonReturn:
            ledger.recordAnswer(MigrationOfferLedger.importKey)
            return false
        default:
            return false
        }
    }

    // MARK: Trash the App Store copy

    private var appStoreCopies: [URL] {
        let appName = environment.bundleURL.deletingPathExtension().lastPathComponent
        let known = NSWorkspace.shared.urlsForApplications(withBundleIdentifier: environment.bundleIdentifier)
        return AppStoreCopyFinder.appStoreCopies(
            candidates: known + AppStoreCopyFinder.wellKnownCandidates(home: environment.home, appName: appName),
            bundleIdentifier: environment.bundleIdentifier,
            runningBundle: environment.bundleURL,
            fileManager: environment.fileManager)
    }

    /// `then` runs once the offer is answered and any Trash move has finished.
    func offerTrashIfNeeded(then next: @escaping () -> Void = {}) {
        guard !ledger.isAnswered(MigrationOfferLedger.trashKey) else { return next() }
        let copies = appStoreCopies
        guard !copies.isEmpty else { return next() }

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Move the App Store copy to the Trash?".localized
        alert.informativeText = String(format: "The App Store version of Hidden Bar is still installed:\n%@\nYou can restore it from the Trash later.".localized,
                                       copies.map(\.path).joined(separator: "\n"))
        alert.addButton(withTitle: "Move to Trash".localized)
        alert.addButton(withTitle: "Not now".localized)

        switch run(alert, id: "trash") {
        case .alertFirstButtonReturn:
            ledger.recordAnswer(MigrationOfferLedger.trashKey)
            NSWorkspace.shared.recycle(copies) { _, error in
                if let error { NSLog("AppStoreMigration: recycle failed: \(error.localizedDescription)") }
                DispatchQueue.main.async(execute: next)
            }
        case .alertSecondButtonReturn:
            ledger.recordAnswer(MigrationOfferLedger.trashKey)
            next()
        default:
            next()
        }
    }

    // MARK: Move into /Applications

    var movePlan: MoveToApplications.Plan { movePlan(ignoringAnswer: false) }

    private func movePlan(ignoringAnswer: Bool) -> MoveToApplications.Plan {
        let fm = environment.fileManager
        let running = environment.bundleURL
        return MoveToApplications.plan(
            runningBundle: running,
            alreadyAnswered: !ignoringAnswer && ledger.isAnswered(MigrationOfferLedger.moveKey),
            applicationsWritable: fm.isWritableFile(atPath: environment.systemApplications.path),
            applicationsHoldsAppStoreCopy: AppStoreCopyFinder.isAppStoreBuild(
                MoveToApplications.destination(for: running, in: environment.systemApplications), fileManager: fm),
            systemApplications: environment.systemApplications)
    }

    /// The Settings status card's "Move to Applications": the same offer, also
    /// when the launch offer was answered "Not now" before.
    func offerMoveFromSettings() {
        guard AppDefaults.allowsHostSideEffects else { return }
        offerMoveIfNeeded(ignoringAnswer: true)
    }

    func offerMoveIfNeeded(ignoringAnswer: Bool = false) {
        let fm = environment.fileManager
        let destination: URL
        let info: String
        switch movePlan(ignoringAnswer: ignoringAnswer) {
        case .none:
            return
        case .explainAppStoreCopyKept:
            explainMove("The App Store copy is in /Applications. Quit Hidden Bar, move /Applications/Hidden Bar.app to the Trash, drag this copy into Applications, then open it from there.".localized)
            return
        case .explainNotWritable:
            explainMove("This account can't add apps to /Applications. Ask an administrator to drag Hidden Bar into /Applications, then open it from there.".localized)
            return
        case .moveToApplications(let url):
            destination = url
            info = fm.fileExists(atPath: url.path)
                ? "Hidden Bar is running from outside Applications. The copy already in Applications goes to the Trash, then Hidden Bar relaunches from there.".localized
                : "Hidden Bar is running from outside Applications. Move it there so it keeps working after you empty Downloads, then relaunch.".localized
        }

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Move Hidden Bar to the Applications folder?".localized
        alert.informativeText = info
        alert.addButton(withTitle: "Move to Applications".localized)
        alert.addButton(withTitle: "Not now".localized)

        switch run(alert, id: "move") {
        case .alertFirstButtonReturn:
            ledger.recordAnswer(MigrationOfferLedger.moveKey)
            moveAndRelaunch(from: environment.bundleURL, to: destination)
        case .alertSecondButtonReturn:
            ledger.recordAnswer(MigrationOfferLedger.moveKey)
        default:
            break
        }
    }

    /// Shown once: macOS 27 hides nothing for a copy outside /Applications.
    private func explainMove(_ steps: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Hidden Bar can hide icons only from /Applications".localized
        alert.informativeText = steps
        alert.addButton(withTitle: "OK".localized)
        run(alert, id: "explain")
        ledger.recordAnswer(MigrationOfferLedger.moveKey)
    }

    private func moveAndRelaunch(from source: URL, to destination: URL) {
        let fm = environment.fileManager
        do {
            if fm.fileExists(atPath: destination.path) {
                try fm.trashItem(at: destination, resultingItemURL: nil)
            }
            try fm.copyItem(at: source, to: destination)
        } catch {
            let failure = NSAlert(error: error)
            run(failure, id: "error")
            return
        }
        // A translocated copy is a read-only view of the original; leave the
        // original where it is.
        if !MoveToApplications.isTranslocated(source) {
            try? fm.trashItem(at: source, resultingItemURL: nil)
        }
        relaunch(at: destination)
    }

    /// Opens the new copy once this process has exited, so the new instance does
    /// not see this one and quit as a duplicate.
    private func relaunch(at url: URL) {
        let waiter = Process()
        waiter.executableURL = URL(fileURLWithPath: "/bin/sh")
        waiter.arguments = ["-c", "while /bin/kill -0 \"$1\" 2>/dev/null; do /bin/sleep 0.2; done; /usr/bin/open \"$2\"",
                            "sh", String(ProcessInfo.processInfo.processIdentifier), url.path]
        do {
            try waiter.run()
            NSApp.terminate(nil)
        } catch {
            NSLog("AppStoreMigration: relaunch failed: \(error.localizedDescription)")
        }
    }

    @discardableResult
    private func run(_ alert: NSAlert, id: String) -> NSApplication.ModalResponse {
        NSApp.activate(ignoringOtherApps: true)
        #if DEBUG
        Self.scheduleDebugAnswer(for: id)
        #endif
        return alert.runModal()
    }

    #if DEBUG
    /// Test hook: launch with `-debugAnswerAlerts "switch=first,move=second"`.
    /// Each named alert (switch, import, trash, move, explain, error) gets that
    /// answer after 3 seconds, time for a screenshot; any alert not named is
    /// aborted, which records nothing and moves nothing.
    private static let debugAnswers: [String: String]? = AppDefaults.store.string(forKey: "debugAnswerAlerts").map {
        Dictionary($0.split(separator: ",").compactMap { pair -> (String, String)? in
            let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
            return parts.count == 2 ? (parts[0], parts[1]) : nil
        }, uniquingKeysWith: { _, last in last })
    }

    private static func scheduleDebugAnswer(for id: String) {
        guard let debugAnswers else { return }
        let answer = debugAnswers[id] ?? "abort"
        let timer = Timer(timeInterval: 3, repeats: false) { _ in
            NSLog("AppStoreMigration: debug answer \(id)=\(answer)")
            switch answer {
            case "first": NSApp.stopModal(withCode: .alertFirstButtonReturn)
            case "second": NSApp.stopModal(withCode: .alertSecondButtonReturn)
            default: NSApp.abortModal()
            }
        }
        RunLoop.main.add(timer, forMode: .modalPanel)
    }
    #endif
}

#endif
