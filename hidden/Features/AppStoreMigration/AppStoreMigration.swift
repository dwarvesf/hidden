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
//   3. move itself into /Applications.
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
    enum Kind { case number, string, data }

    /// Every preference the app defines, with the plist type it is stored as.
    /// Anything else in the container (Sparkle SU* keys, window frames, status
    /// item positions, internal flags) is never copied.
    static let importableKeys: [String: Kind] = [
        UserDefaults.Key.globalKey: .data,
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
        UserDefaults.Key.notchOverflowEnabled: .number,
        UserDefaults.Key.pauseHidingForUnkeepableItems: .number,
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
}

/// Whether to offer moving the running copy into /Applications.
enum MoveToApplications {
    static func isInApplicationsFolder(_ bundleURL: URL, home: URL) -> Bool {
        let path = bundleURL.resolvingSymlinksInPath().standardizedFileURL.path
        let roots = ["/Applications/", home.appendingPathComponent("Applications").standardizedFileURL.path + "/"]
        return roots.contains { path.hasPrefix($0) }
    }

    /// Gatekeeper runs a quarantined app from a read-only random path.
    static func isTranslocated(_ bundleURL: URL) -> Bool {
        bundleURL.path.contains("/AppTranslocation/")
    }

    static func destination(for bundleURL: URL) -> URL {
        URL(fileURLWithPath: "/Applications").appendingPathComponent(bundleURL.lastPathComponent)
    }

    static func shouldOffer(runningBundle: URL, home: URL, alreadyAnswered: Bool,
                            destinationIsAppStoreCopy: Bool, applicationsWritable: Bool) -> Bool {
        guard !alreadyAnswered, applicationsWritable else { return false }
        // The App Store copy sits where we would go; the Trash offer comes first.
        guard !destinationIsAppStoreCopy else { return false }
        return !isInApplicationsFolder(runningBundle, home: home)
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
    }

    static let shared = AppStoreMigration(environment: Environment(
        home: URL(fileURLWithPath: NSHomeDirectory()),
        bundleURL: Bundle.main.bundleURL,
        bundleIdentifier: Bundle.main.bundleIdentifier ?? "com.dwarvesv.minimalbar",
        defaults: .standard,
        registeredDefaults: AppDelegate.defaultPreferenceValues))

    let environment: Environment
    private var ledger: MigrationOfferLedger { MigrationOfferLedger(defaults: environment.defaults) }

    init(environment: Environment) {
        self.environment = environment
    }

    #if DEBUG
    /// Debug builds run from DerivedData; launch with `-forceAppStoreMigration YES`
    /// to take the offers anyway.
    private static var isEnabled: Bool { UserDefaults.standard.bool(forKey: "forceAppStoreMigration") }
    #else
    private static var isEnabled: Bool { true }
    #endif

    /// Called once from `applicationDidFinishLaunching`.
    func runAtLaunchIfNeeded(afterImport: @escaping () -> Void) {
        guard Self.isEnabled else { return }
        DispatchQueue.main.async { [self] in
            if offerImportIfNeeded() { afterImport() }
            offerTrashIfNeeded()
            offerMoveIfNeeded()
        }
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

        switch run(alert) {
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

    func offerTrashIfNeeded() {
        guard !ledger.isAnswered(MigrationOfferLedger.trashKey) else { return }
        let copies = appStoreCopies
        guard !copies.isEmpty else { return }

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Move the App Store copy to the Trash?".localized
        alert.informativeText = String(format: "The App Store version of Hidden Bar is still installed:\n%@\nYou can restore it from the Trash later.".localized,
                                       copies.map(\.path).joined(separator: "\n"))
        alert.addButton(withTitle: "Move to Trash".localized)
        alert.addButton(withTitle: "Not now".localized)

        switch run(alert) {
        case .alertFirstButtonReturn:
            ledger.recordAnswer(MigrationOfferLedger.trashKey)
            NSWorkspace.shared.recycle(copies) { _, error in
                if let error { NSLog("AppStoreMigration: recycle failed: \(error.localizedDescription)") }
            }
        case .alertSecondButtonReturn:
            ledger.recordAnswer(MigrationOfferLedger.trashKey)
        default:
            break
        }
    }

    // MARK: Move into /Applications

    func offerMoveIfNeeded() {
        let running = environment.bundleURL
        let destination = MoveToApplications.destination(for: running)
        let fm = environment.fileManager
        guard MoveToApplications.shouldOffer(
            runningBundle: running,
            home: environment.home,
            alreadyAnswered: ledger.isAnswered(MigrationOfferLedger.moveKey),
            destinationIsAppStoreCopy: AppStoreCopyFinder.isAppStoreBuild(destination, fileManager: fm),
            applicationsWritable: fm.isWritableFile(atPath: "/Applications")) else { return }

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Move Hidden Bar to the Applications folder?".localized
        alert.informativeText = fm.fileExists(atPath: destination.path)
            ? "Hidden Bar is running from outside Applications. The copy already in Applications goes to the Trash, then Hidden Bar relaunches from there.".localized
            : "Hidden Bar is running from outside Applications. Move it there so it keeps working after you empty Downloads, then relaunch.".localized
        alert.addButton(withTitle: "Move to Applications".localized)
        alert.addButton(withTitle: "Not now".localized)

        switch run(alert) {
        case .alertFirstButtonReturn:
            ledger.recordAnswer(MigrationOfferLedger.moveKey)
            moveAndRelaunch(from: running, to: destination)
        case .alertSecondButtonReturn:
            ledger.recordAnswer(MigrationOfferLedger.moveKey)
        default:
            break
        }
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
            run(failure)
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
    private func run(_ alert: NSAlert) -> NSApplication.ModalResponse {
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal()
    }
}

#endif
