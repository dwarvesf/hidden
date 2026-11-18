//
//  MacOS27Notice.swift
//  Hidden Bar
//
//  Copyright © 2026 Console Labs. All rights reserved.
//

import AppKit

// App Store variant only. The sandboxed build cannot read Accessibility on
// macOS 27, so it cannot hide icons there. Tell the user once, and point them
// at the build that works. The direct build defines HIDDENBAR_NATIVE_VISIBILITY
// and compiles none of this.
//
// App Review 2.4.5(iv): a Mac App Store app must not fetch or install other
// apps, and 2.4.5(vii): updates come only through the Mac App Store. So this
// opens a web page, never a direct .zip link (a button that downloads the newer
// build reads as an update channel), and shows the Homebrew command as text the
// user can copy and run themselves.
#if !HIDDENBAR_NATIVE_VISIBILITY

/// The "when to show" decision, kept free of AppKit so it can be unit tested
/// with an injected `UserDefaults` suite.
struct MacOS27NoticePolicy {
    static let suppressedKey = "macOS27NoticeSuppressed"
    static let lastShownVersionKey = "macOS27NoticeLastShownVersion"
    static let firstAffectedMajorVersion = 27

    let osMajorVersion: Int
    let appVersion: String
    let defaults: UserDefaults

    var appliesToThisOS: Bool {
        osMajorVersion >= Self.firstAffectedMajorVersion
    }

    /// Shown at most once per app version, never again once the user chose
    /// "Don't show again".
    func shouldShowAtLaunch() -> Bool {
        guard appliesToThisOS else { return false }
        if defaults.bool(forKey: Self.suppressedKey) { return false }
        return defaults.string(forKey: Self.lastShownVersionKey) != appVersion
    }

    func recordShown() {
        defaults.set(appVersion, forKey: Self.lastShownVersionKey)
    }

    func suppressForever() {
        defaults.set(true, forKey: Self.suppressedKey)
    }
}

final class MacOS27Notice: NSObject {
    static let shared = MacOS27Notice()
    static let pageURL = URL(string: "https://github.com/consolelabs/hidden")!
    static let brewCommand = "brew install --cask hiddenbar"
    static let brewFirstStep = "Quit this App Store version and move it to the Trash first. Homebrew does not install over it."

    #if DEBUG
    /// Launch with `-forceMacOS27Notice YES` to take the macOS 27 path on any
    /// OS. The forced path ignores and never writes the "shown" state.
    private static var isForced: Bool {
        AppDefaults.store.bool(forKey: "forceMacOS27Notice")
    }
    #else
    private static var isForced: Bool { false }
    #endif

    private var policy: MacOS27NoticePolicy {
        let osMajor = Self.isForced
            ? MacOS27NoticePolicy.firstAffectedMajorVersion
            : ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        return MacOS27NoticePolicy(osMajorVersion: osMajor, appVersion: version, defaults: AppDefaults.store)
    }

    private var isPresenting = false

    /// Called once from `applicationDidFinishLaunching`.
    func showAtLaunchIfNeeded() {
        guard AppDefaults.allowsHostSideEffects else { return }
        let policy = self.policy
        guard Self.isForced || policy.shouldShowAtLaunch() else { return }
        // Let launch finish before blocking on a modal alert.
        DispatchQueue.main.async { [weak self] in
            self?.present(recordingShown: !Self.isForced)
        }
    }

    /// The menu entry that lets users find the notice again. Nil off macOS 27.
    func makeMenuItem() -> NSMenuItem? {
        guard policy.appliesToThisOS else { return nil }
        let item = NSMenuItem(title: "macOS 27: get the working version...".localized,
                              action: #selector(showFromMenu),
                              keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func showFromMenu() {
        present(recordingShown: false)
    }

    /// The status card's "Learn More…" in Settings: the same notice.
    func showFromSettings() {
        present(recordingShown: false)
    }

    private func present(recordingShown: Bool) {
        guard AppDefaults.allowsHostSideEffects, !isPresenting else { return }
        isPresenting = true
        defer { isPresenting = false }

        if recordingShown { policy.recordShown() }

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Hidden Bar cannot hide icons on macOS 27".localized
        alert.informativeText = "macOS 27 no longer lets App Store apps hide menu-bar icons. Hidden Bar from github.com/consolelabs/hidden (free, open source) works on macOS 27.".localized
        alert.addButton(withTitle: "Open github.com/consolelabs/hidden".localized)
        alert.addButton(withTitle: "Close".localized)
        alert.addButton(withTitle: "Don't show again".localized)
        alert.window.title = "Hidden Bar on macOS 27".localized
        alert.accessoryView = Self.makeBrewCommandView()

        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            NSWorkspace.shared.open(Self.pageURL)
        case .alertThirdButtonReturn:
            policy.suppressForever()
        default:
            break
        }
    }

    /// "Or with Homebrew:" plus the command in a selectable monospaced field.
    static func makeBrewCommandView() -> NSView {
        let label = NSTextField(labelWithString: "Or install it with Homebrew:".localized)
        label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        let command = NSTextField(labelWithString: brewCommand)
        command.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        command.isSelectable = true
        // Homebrew refuses while this copy sits in /Applications.
        let first = NSTextField(wrappingLabelWithString: brewFirstStep.localized)
        first.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        first.preferredMaxLayoutWidth = 300
        let stack = NSStackView(views: [label, command, first])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        stack.frame = NSRect(x: 0, y: 0, width: 300, height: stack.fittingSize.height)
        return stack
    }
}

#endif
