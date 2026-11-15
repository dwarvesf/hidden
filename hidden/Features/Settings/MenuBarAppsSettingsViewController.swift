//
//  MenuBarAppsSettingsViewController.swift
//  Hidden Bar
//
//  Copyright © 2026 Dwarves Foundation. All rights reserved.
//

import AppKit
import UniformTypeIdentifiers

/// Where the Icons pane reads and writes the pinned sections (beta).
/// The live store is the app's preferences; snapshots pass fixed data.
protocol MenuBarAppsStore {
    var isEnabled: Bool { get }
    func entries() -> [PinnedSectionsList.Entry]
    func identity(for bundle: String) -> MenuBarAppIdentity.Resolved
    func icon(for bundle: String) -> NSImage
    /// Bundle ids with a running process, read once per rebuild of the pane.
    func runningBundles() -> Set<String>
    func set(_ section: MenuBarSection, for bundle: String)
    func setIgnoresDrags(_ ignores: Bool, for bundle: String)
    func resetAllToVisible()
    func remove(_ bundle: String)
    func enable()
}

struct LiveMenuBarAppsStore: MenuBarAppsStore {
    /// A class, so copies of the store share what it resolved.
    let identities = MenuBarAppIdentityCache()

    var isEnabled: Bool { Preferences.pinnedSectionsEnabled }

    func entries() -> [PinnedSectionsList.Entry] {
        PinnedSectionsList.entries(table: UserDefaultsPinnedSections().sections, name: { identities.identity(for: $0).name },
                                   ignoringDrags: UserDefaultsDragLocks().bundles)
    }

    func identity(for bundle: String) -> MenuBarAppIdentity.Resolved { identities.identity(for: bundle) }

    // The app's own icon, from its bundle: no screen capture.
    func icon(for bundle: String) -> NSImage { identities.icon(for: bundle) }

    func runningBundles() -> Set<String> {
        Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
    }

    func set(_ section: MenuBarSection, for bundle: String) {
        PinnedSectionEdits.set(section, for: bundle, in: UserDefaultsPinnedSections())
    }

    func setIgnoresDrags(_ ignores: Bool, for bundle: String) {
        let locks = UserDefaultsDragLocks()
        if ignores { locks.bundles.insert(bundle) } else { locks.bundles.remove(bundle) }
    }

    func resetAllToVisible() {
        PinnedSectionEdits.resetAllToVisible(in: UserDefaultsPinnedSections())
    }

    func remove(_ bundle: String) {
        PinnedSectionEdits.remove(bundle, in: UserDefaultsPinnedSections())
    }

    func enable() {
        Preferences.pinnedSectionsEnabled = true
    }
}

/// Icons: one row per app the pinned sections know, with its icon, its
/// name and a section popup that applies at once, then "Reset all to visible".
/// An app that is not running can also be removed from the list.
final class MenuBarAppsSettingsViewController: SettingsPaneController {
    static let sectionTitles: [(MenuBarSection, String)] = [
        (.visible, "Visible"), (.hidden, "Hidden"), (.alwaysHidden, "Always hidden"),
    ]
    /// Identifier of each row's popup: the defaults key, then the bundle id.
    static func popupIdentifier(for bundle: String) -> String {
        "\(UserDefaultsPinnedSections.key).\(bundle)"
    }
    /// Identifier of each row's "Ignore drags" checkbox.
    static func lockIdentifier(for bundle: String) -> String {
        "\(UserDefaultsDragLocks.key).\(bundle)"
    }
    /// Identifier of the "Remove" button of an app that is not running.
    static func removeIdentifier(for bundle: String) -> String {
        "pinnedSectionsRemove.\(bundle)"
    }
    /// The rows that show "Not running" and Remove. Never the macOS extras row: it is no app.
    static func notRunning(_ bundles: [String], running: Set<String>) -> Set<String> {
        Set(bundles.filter { $0 != MenuBarLayoutResolver.systemExtrasBundle && !running.contains($0) })
    }
    static let maxListHeight: CGFloat = 360

    private let store: MenuBarAppsStore
    private let content = NSStackView()
    /// What the rows were last built from: switching back to the tab changes nothing unless this does.
    private var built: (isEnabled: Bool, entries: [PinnedSectionsList.Entry], notRunning: Set<String>)?

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
        let isEnabled = store.isEnabled
        let entries = isEnabled ? store.entries() : []
        let notRunning = Self.notRunning(entries.map(\.bundle), running: entries.isEmpty ? [] : store.runningBundles())
        if let built, built.isEnabled == isEnabled, built.entries == entries, built.notRunning == notRunning { return }
        built = (isEnabled, entries, notRunning)
        content.arrangedSubviews.forEach { $0.removeFromSuperview() }
        guard isEnabled else {
            let turnOn = NSButton(title: "Turn On".localized, target: self, action: #selector(turnOn))
            turnOn.controlSize = .small
            add(SettingsGroupView(rows: [SettingsForm.row(
                "Pinned sections is off".localized,
                caption: "Icons follow where macOS puts them. Turn on Pinned sections (beta) in Advanced to choose a section for each app.".localized,
                control: turnOn)]))
            return
        }
        add(SettingsForm.caption("Each app stays in the section you pick, also after it restarts. ⌘-dragging an icon across the arrow moves it too.".localized))
        if entries.isEmpty {
            add(SettingsGroupView(rows: [SettingsForm.row(
                "No apps yet".localized,
                caption: "Apps with a menu bar icon appear here after the bar collapses once.".localized,
                control: nil)]))
        } else {
            add(list(entries, notRunning: notRunning))
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
    private func list(_ entries: [PinnedSectionsList.Entry], notRunning: Set<String>) -> NSView {
        let captions = MenuBarAppIdentity.captions(for: entries.map { ($0.bundle, $0.name, store.identity(for: $0.bundle).caption) },
                                                   notRunning: notRunning)
        let group = SettingsGroupView(rows: entries.map { row($0, caption: captions[$0.bundle], canRemove: notRunning.contains($0.bundle)) })
        let fittingHeight = group.fittingSize.height
        let height = min(fittingHeight, Self.maxListHeight)
        guard fittingHeight > Self.maxListHeight else { return group }
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

    private func row(_ entry: PinnedSectionsList.Entry, caption: String?, canRemove: Bool) -> NSView {
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

        let lock = NSButton(checkboxWithTitle: "Ignore drags".localized, target: self, action: #selector(lockToggled(_:)))
        lock.controlSize = .small
        lock.state = entry.ignoresDrags ? .on : .off
        lock.identifier = NSUserInterfaceItemIdentifier(Self.lockIdentifier(for: entry.bundle))
        lock.toolTip = "Keep this app in its section even when its icon moves on its own, as BitBar and SwiftBar do. Dragging no longer changes it; the popup still does.".localized
        let controls = NSStackView(views: [lock, popup])
        controls.spacing = 10

        let row = SettingsForm.row(entry.name, caption: caption, control: controls)
        if canRemove { addRemoveLink(to: row, for: entry) }
        row.toolTip = entry.bundle
        let image = store.icon(for: entry.bundle)
        let icon = NSImageView(image: image)
        icon.translatesAutoresizingMaskIntoConstraints = false
        // SF Symbols are templates: tint them like secondary text instead of black.
        icon.contentTintColor = image.isTemplate ? .secondaryLabelColor : nil
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

    // Remove sits in the caption line, not the controls column, so every row's controls line up.
    private func addRemoveLink(to row: NSView, for entry: PinnedSectionsList.Entry) {
        guard let texts = row.subviews.first(where: { $0 is NSStackView }) as? NSStackView,
              let caption = texts.arrangedSubviews.last as? NSTextField else { return }
        caption.stringValue += " \u{B7}"
        caption.lineBreakMode = .byTruncatingTail
        caption.maximumNumberOfLines = 1
        caption.setContentHuggingPriority(.required, for: .horizontal)

        let title = "Remove".localized
        let remove = NSButton(title: title, target: self, action: #selector(removeTapped(_:)))
        remove.isBordered = false
        remove.controlSize = .small
        remove.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.linkColor,
        ])
        remove.identifier = NSUserInterfaceItemIdentifier(Self.removeIdentifier(for: entry.bundle))
        remove.setAccessibilityLabel("\(title) \(entry.name)")
        remove.heightAnchor.constraint(greaterThanOrEqualToConstant: 16).isActive = true

        texts.removeArrangedSubview(caption)
        let line = NSStackView(views: [caption, remove])
        line.spacing = 3
        line.alignment = .firstBaseline
        texts.addArrangedSubview(line)
    }

    @objc private func sectionPicked(_ sender: NSPopUpButton) {
        guard let raw = sender.identifier?.rawValue,
              let section = sender.selectedItem.flatMap({ MenuBarSection(rawValue: $0.tag) }) else { return }
        store.set(section, for: String(raw.dropFirst(UserDefaultsPinnedSections.key.count + 1)))
    }

    @objc private func lockToggled(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue else { return }
        store.setIgnoresDrags(sender.state == .on, for: String(raw.dropFirst(UserDefaultsDragLocks.key.count + 1)))
    }

    @objc private func removeTapped(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue else { return }
        store.remove(String(raw.dropFirst(Self.removeIdentifier(for: "").count)))
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
    var notRunning: Set<String> = []
    let live = LiveMenuBarAppsStore()

    static let states: [(String, SnapshotMenuBarAppsStore)] = [
        ("on", SnapshotMenuBarAppsStore(isEnabled: true, table: [
            "com.apple.Safari": .visible, "com.apple.Notes": .hidden, "com.apple.Music": .alwaysHidden,
            "com.apple.controlcenter": .visible, "com.apple.ActivityMonitor": .hidden,
            "com.example.uninstalled": .hidden, "com.apple.chronod": .hidden, "com.apple.sharingd": .hidden,
            "com.apple.screensharing.agent": .hidden, "com.apple.SSMenuAgent": .visible,
            "com.hnc.Discord.helper.Renderer": .hidden,
        ], notRunning: ["com.example.uninstalled", "com.apple.chronod"])),
        ("off", SnapshotMenuBarAppsStore(isEnabled: false, table: [:])),
        ("empty", SnapshotMenuBarAppsStore(isEnabled: true, table: [:])),
    ]

    func entries() -> [PinnedSectionsList.Entry] {
        PinnedSectionsList.entries(table: table, name: { live.identity(for: $0).name })
    }

    func identity(for bundle: String) -> MenuBarAppIdentity.Resolved { live.identity(for: bundle) }
    func icon(for bundle: String) -> NSImage { live.icon(for: bundle) }
    func runningBundles() -> Set<String> { Set(table.keys).subtracting(notRunning) }
    func set(_ section: MenuBarSection, for bundle: String) {}
    func setIgnoresDrags(_ ignores: Bool, for bundle: String) {}
    func resetAllToVisible() {}
    func remove(_ bundle: String) {}
    func enable() {}
}
#endif
