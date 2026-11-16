//
//  UpdateController.swift
//  Hidden Bar
//
//  Sparkle auto-update for the direct (GitHub / Homebrew) build only. The
//  "Hidden Bar Direct" target compiles this file and defines HIDDENBAR_SPARKLE;
//  the App Store target does neither, so Sparkle never reaches that binary.
//

#if HIDDENBAR_SPARKLE
import AppKit
import Sparkle

final class UpdateController: NSObject, SPUStandardUserDriverDelegate {
    static let shared = UpdateController()

    private var standardController: SPUStandardUpdaterController!

    override init() {
        super.init()
        // A test host never starts the updater: no scheduled check, no feed fetch.
        standardController = SPUStandardUpdaterController(startingUpdater: AppDefaults.allowsHostSideEffects,
                                                          updaterDelegate: nil,
                                                          userDriverDelegate: self)
    }

    /// Persisted by Sparkle itself (SUEnableAutomaticChecks in user defaults).
    var automaticallyChecksForUpdates: Bool {
        get { AppDefaults.allowsHostSideEffects ? standardController.updater.automaticallyChecksForUpdates : AppDefaults.store.bool(forKey: Self.checksKey) }
        set {
            // Sparkle stores this in the app's real preferences domain; a test
            // host keeps the same key in the test suite instead.
            if AppDefaults.allowsHostSideEffects {
                standardController.updater.automaticallyChecksForUpdates = newValue
            } else {
                AppDefaults.store.set(newValue, forKey: Self.checksKey)
            }
        }
    }

    private static let checksKey = "SUEnableAutomaticChecks"

    var lastUpdateCheckDate: Date? {
        AppDefaults.allowsHostSideEffects ? standardController.updater.lastUpdateCheckDate : nil
    }

    /// The About pane's button: the same user-initiated check as the menu item.
    func checkForUpdates() {
        guard AppDefaults.allowsHostSideEffects else { return }
        standardController.checkForUpdates(nil)
    }

    func makeMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Check for Updates...".localized,
                              action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)),
                              keyEquivalent: "")
        item.target = standardController
        return item
    }

    // MARK: SPUStandardUserDriverDelegate

    // The app is LSUIElement (no Dock icon, never frontmost), so a scheduled
    // update alert would open behind other windows. Opt in to gentle reminders
    // and bring the alert forward ourselves.
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool,
                                                   forUpdate update: SUAppcastItem,
                                                   state: SPUUserUpdateState) {
        guard handleShowingUpdate else { return }
        NSApp.activate(ignoringOtherApps: true)
    }
}
#endif
