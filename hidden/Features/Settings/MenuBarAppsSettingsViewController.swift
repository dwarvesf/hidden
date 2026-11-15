//
//  MenuBarAppsSettingsViewController.swift
//  Hidden Bar
//
//  Copyright © 2026 Dwarves Foundation. All rights reserved.
//

import AppKit
import UniformTypeIdentifiers

/// Where the Menu Bar Apps pane reads and writes the pinned sections (beta).
/// The live store is the app's preferences; snapshots pass fixed data.
protocol MenuBarAppsStore {
    var isEnabled: Bool { get }
    func entries() -> [PinnedSectionsList.Entry]
    func icon(for bundle: String) -> NSImage?
    func set(_ section: MenuBarSection, for bundle: String)
    func resetAllToVisible()
    func enable()
}

struct LiveMenuBarAppsStore: MenuBarAppsStore {
    var isEnabled: Bool { Preferences.pinnedSectionsEnabled }

    func entries() -> [PinnedSectionsList.Entry] {
        PinnedSectionsList.entries(table: UserDefaultsPinnedSections().sections, name: Self.appName)
    }

    // "Safari", without ".app" even when Finder shows extensions.
    static func appName(_ bundle: String) -> String? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle)?.deletingPathExtension().lastPathComponent
    }

    // The app's own icon, from its bundle: no screen capture.
    func icon(for bundle: String) -> NSImage? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle).map { NSWorkspace.shared.icon(forFile: $0.path) }
    }

    func set(_ section: MenuBarSection, for bundle: String) {
        PinnedSectionEdits.set(section, for: bundle, in: UserDefaultsPinnedSections())
    }

    func resetAllToVisible() {
        PinnedSectionEdits.resetAllToVisible(in: UserDefaultsPinnedSections())
    }

    func enable() {
        Preferences.pinnedSectionsEnabled = true
    }
}

/// Menu Bar Apps: one row per app the pinned sections know, with its icon, its
/// name and a section popup that applies at once, then "Reset all to visible".
final class MenuBarAppsSettingsViewController: SettingsPaneController {
    static let sectionTitles: [(MenuBarSection, String)] = [
        (.visible, "Visible"), (.hidden, "Hidden"), (.alwaysHidden, "Always hidden"),
    ]
    /// Identifier of each row's popup: the defaults key, then the bundle id.
    static func popupIdentifier(for bundle: String) -> String {
        "\(UserDefaultsPinnedSections.key).\(bundle)"
    }
    static let maxListHeight: CGFloat = 360

    private let store: MenuBarAppsStore
    private let content = NSStackView()

    init(context: SettingsContext, store: MenuBarAppsStore = LiveMenuBarAppsStore()) {
        self.store = store
        super.init(context: context)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func buildForm() {
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 6
        addFullWidth(content)
        onRefresh { [weak self] in self?.rebuild() }
        NotificationCenter.default.addObserver(self, selector: #selector(refreshAll), name: .pinnedSectionsChanged, object: nil)
        rebuild()
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        // A collapse adds apps to the table while the window is closed.
        rebuild()
    }

    private func rebuild() {
        content.arrangedSubviews.forEach { $0.removeFromSuperview() }
        guard store.isEnabled else {
            let turnOn = NSButton(title: "Turn On".localized, target: self, action: #selector(turnOn))
            turnOn.controlSize = .small
            add(SettingsGroupView(rows: [SettingsForm.row(
                "Pinned sections is off".localized,
                caption: "Icons follow where macOS puts them. Turn on Pinned sections (beta) in Advanced to choose a section for each app.".localized,
                control: turnOn)]))
            return
        }
        let entries = store.entries()
        add(SettingsForm.caption("Each app stays in the section you pick, also after it restarts. ⌘-dragging an icon across the arrow moves it too.".localized))
        if entries.isEmpty {
            add(SettingsGroupView(rows: [SettingsForm.row(
                "No apps yet".localized,
                caption: "Apps with a menu bar icon appear here after the bar collapses once.".localized,
                control: nil)]))
        } else {
            add(list(entries))
        }
        let reset = NSButton(title: "Reset".localized, target: self, action: #selector(resetAll))
        reset.controlSize = .small
        reset.identifier = NSUserInterfaceItemIdentifier("pinnedSectionsReset")
        add(SettingsGroupView(rows: [SettingsForm.row(
            "Reset all to visible".localized,
            caption: "Shows every app, including ones that are not running now.".localized,
            control: reset)]))
    }

    private func add(_ view: NSView) {
        content.addArrangedSubview(view)
        view.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
    }

    // The group scrolls once it is taller than the window should grow.
    private func list(_ entries: [PinnedSectionsList.Entry]) -> NSView {
        let group = SettingsGroupView(rows: entries.map(row))
        let height = min(group.fittingSize.height, Self.maxListHeight)
        guard group.fittingSize.height > Self.maxListHeight else { return group }
        let document = FlippedView()
        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(group)
        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.documentView = document
        NSLayoutConstraint.activate([
            group.topAnchor.constraint(equalTo: document.topAnchor),
            group.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            group.trailingAnchor.constraint(equalTo: document.trailingAnchor),
            group.bottomAnchor.constraint(equalTo: document.bottomAnchor),
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            scroll.heightAnchor.constraint(equalToConstant: height),
        ])
        return scroll
    }

    private func row(_ entry: PinnedSectionsList.Entry) -> NSView {
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.controlSize = .small
        for (section, title) in Self.sectionTitles {
            popup.addItem(withTitle: title.localized)
            popup.lastItem?.tag = section.rawValue
        }
        popup.selectItem(withTag: entry.section.rawValue)
        popup.identifier = NSUserInterfaceItemIdentifier(Self.popupIdentifier(for: entry.bundle))
        popup.target = self
        popup.action = #selector(sectionPicked(_:))

        let row = SettingsForm.row(entry.name, control: popup)
        row.toolTip = entry.bundle
        let icon = NSImageView(image: store.icon(for: entry.bundle) ?? NSWorkspace.shared.icon(for: .applicationBundle))
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.imageScaling = .scaleProportionallyUpOrDown
        row.addSubview(icon)
        // Make room for the icon: move the title's leading edge right of it.
        if let texts = row.subviews.first(where: { $0 is NSStackView }) {
            row.constraints.first { $0.firstItem === texts && $0.firstAttribute == .leading }?.constant = SettingsMetrics.rowInset + 26
        }
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: SettingsMetrics.rowInset),
            icon.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 18),
            icon.heightAnchor.constraint(equalToConstant: 18),
        ])
        return row
    }

    @objc private func sectionPicked(_ sender: NSPopUpButton) {
        guard let raw = sender.identifier?.rawValue,
              let section = sender.selectedItem.flatMap({ MenuBarSection(rawValue: $0.tag) }) else { return }
        store.set(section, for: String(raw.dropFirst(UserDefaultsPinnedSections.key.count + 1)))
    }

    @objc private func resetAll() {
        store.resetAllToVisible()
    }

    @objc private func turnOn() {
        store.enable()
    }
}

/// A scroll view's document grows downward only when flipped.
private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

#if DEBUG
/// Fixed content for `-settingsSnapshotDir`: the pane on, off and empty.
struct SnapshotMenuBarAppsStore: MenuBarAppsStore {
    var isEnabled: Bool
    var table: [String: MenuBarSection]

    static let states: [(String, SnapshotMenuBarAppsStore)] = [
        ("on", SnapshotMenuBarAppsStore(isEnabled: true, table: [
            "com.apple.Safari": .visible, "com.apple.Notes": .hidden, "com.apple.Music": .alwaysHidden,
            "com.apple.controlcenter": .visible, "com.apple.ActivityMonitor": .hidden,
            "com.example.uninstalled": .hidden,
        ])),
        ("off", SnapshotMenuBarAppsStore(isEnabled: false, table: [:])),
        ("empty", SnapshotMenuBarAppsStore(isEnabled: true, table: [:])),
    ]

    func entries() -> [PinnedSectionsList.Entry] {
        PinnedSectionsList.entries(table: table, name: LiveMenuBarAppsStore.appName)
    }

    func icon(for bundle: String) -> NSImage? { LiveMenuBarAppsStore().icon(for: bundle) }
    func set(_ section: MenuBarSection, for bundle: String) {}
    func resetAllToVisible() {}
    func enable() {}
}
#endif
