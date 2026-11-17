//
//  MenuBarAppsSettingsViewController.swift
//  Hidden Bar
//
//  Copyright © 2026 Console Labs. All rights reserved.
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
    /// What an app that adds its first icon gets: asked, shown or hidden.
    var newAppDefault: NewAppDefault { get }
    func setNewAppDefault(_ choice: NewAppDefault)
}

extension MenuBarAppsStore {
    var newAppDefault: NewAppDefault { Preferences.newAppDefaultSection }
    func setNewAppDefault(_ choice: NewAppDefault) { Preferences.newAppDefaultSection = choice }
}

struct LiveMenuBarAppsStore: MenuBarAppsStore {
    /// A class, so copies of the store share what it resolved.
    let identities = MenuBarAppIdentityCache()

    var isEnabled: Bool { Preferences.pinnedSectionsEnabled }

    func entries() -> [PinnedSectionsList.Entry] {
        PinnedSectionsList.entries(table: UserDefaultsPinnedSections().sections, name: { identities.identity(for: $0).name },
                                   ignoringDrags: UserDefaultsDragLocks().bundles,
                                   pending: Set(UserDefaultsArrivalsPending().bundles))
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
    /// Identifier of the "When an app adds a new icon" popup: the defaults key.
    static let newAppDefaultIdentifier = UserDefaults.Key.newAppDefaultSection
    static let newAppDefaultTitles: [(NewAppDefault, String)] = [(.ask, "Ask Me"), (.show, "Show It"), (.hide, "Hide It")]
    /// What the popup's current choice does, in a line.
    static func newAppCaption(for choice: NewAppDefault) -> String {
        switch choice {
        case .ask: return "Ask puts a dot on the arrow and keeps the icon shown until you choose.".localized
        case .show: return "Show leaves a new icon where macOS puts it. Nothing is asked.".localized
        case .hide: return "Hide moves a new icon to Hidden at once. Nothing is asked.".localized
        }
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
        addNewAppDefaultRow()
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 6
        addFullWidth(content)
        onRefresh { [weak self] in self?.rebuild() }
        NotificationCenter.default.addObserver(self, selector: #selector(refreshAll), name: .pinnedSectionsChanged, object: nil)
        #if HIDDENBAR_NATIVE_VISIBILITY
        NotificationCenter.default.addObserver(self, selector: #selector(refreshAll), name: .arrivalsChanged, object: nil)
        #endif
        rebuild()
    }

    // "When an app adds a new icon": one popup above the list. With Pinned sections
    // off nothing places a new app, so the popup stays but cannot be changed.
    private func addNewAppDefaultRow() {
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.controlSize = .small
        for (choice, title) in Self.newAppDefaultTitles {
            popup.addItem(withTitle: title.localized)
            popup.lastItem?.tag = choice.rawValue
        }
        popup.identifier = NSUserInterfaceItemIdentifier(Self.newAppDefaultIdentifier)
        popup.target = self
        popup.action = #selector(newAppDefaultPicked(_:))
        let row = SettingsForm.row("When an app adds a new icon".localized,
                                   caption: Self.newAppCaption(for: store.newAppDefault), control: popup)
        addSection(nil, rows: [row])
        let caption = (row.subviews.first { $0 is NSStackView } as? NSStackView)?.arrangedSubviews.last as? NSTextField
        onRefresh { [weak self, weak popup, weak caption] in
            guard let self, let popup else { return }
            popup.selectItem(withTag: self.store.newAppDefault.rawValue)
            popup.isEnabled = self.store.isEnabled
            caption?.stringValue = Self.newAppCaption(for: self.store.newAppDefault)
        }
        popup.selectItem(withTag: store.newAppDefault.rawValue)
        popup.isEnabled = store.isEnabled
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
        add(SettingsForm.caption("Each app stays in the section you pick, also after it restarts. ⌘-dragging an icon across the arrow moves it too. Ignore drags keeps an app in its section even when its icon moves on its own (SwiftBar, BitBar).".localized))
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
        let group = SettingsGroupView(rows: entries.map { entry in
            let canRemove = notRunning.contains(entry.bundle)
            let caption = entry.isNew ? (canRemove ? "Not chosen yet. Not running now.".localized : "Not chosen yet".localized) : captions[entry.bundle]
            return row(entry, caption: caption, canRemove: canRemove)
        })
        let fittingHeight = group.fittingSize.height
        guard fittingHeight > Self.maxListHeight else { return group }
        // Same rows, scrolling inside one card (the scroller stays inside its frame).
        return SettingsScrollCard(group: group, height: Self.maxListHeight)
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
        lock.toolTip = "Ignore drags keeps this app in its section even when its icon moves on its own (SwiftBar, BitBar). Dragging then changes nothing; the popup still does.".localized
        let controls = NSStackView(views: [lock, popup])
        controls.spacing = 10

        let row = SettingsForm.row(entry.name, caption: caption, control: controls)
        if canRemove { addRemoveLink(to: row, for: entry) }
        if entry.isNew { markNew(row) }
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

    // An app that waits for an answer: a tinted row and a NEW tag after its name.
    private func markNew(_ row: NSView) {
        let tint = NewRowTint()
        tint.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(tint, positioned: .below, relativeTo: nil)
        NSLayoutConstraint.activate([
            tint.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            tint.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            tint.topAnchor.constraint(equalTo: row.topAnchor),
            tint.bottomAnchor.constraint(equalTo: row.bottomAnchor),
        ])
        guard let texts = row.subviews.first(where: { $0 is NSStackView }) as? NSStackView,
              let title = texts.arrangedSubviews.first else { return }
        texts.removeArrangedSubview(title)
        let line = NSStackView(views: [title, NewTag()])
        line.spacing = 6
        line.alignment = .centerY
        texts.insertArrangedSubview(line, at: 0)
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
        // As tall as the caption it follows, so a row with Remove is no taller than any captioned row.
        remove.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        remove.setContentHuggingPriority(.defaultLow, for: .vertical)

        texts.removeArrangedSubview(caption)
        let line = NSStackView(views: [caption, remove])
        line.spacing = 3
        line.alignment = .firstBaseline
        texts.addArrangedSubview(line)
        remove.heightAnchor.constraint(equalTo: caption.heightAnchor).isActive = true
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

    @objc private func newAppDefaultPicked(_ sender: NSPopUpButton) {
        guard let choice = sender.selectedItem.flatMap({ NewAppDefault(rawValue: $0.tag) }) else { return }
        store.setNewAppDefault(choice)
    }

    @objc private func resetAll() {
        store.resetAllToVisible()
    }

    @objc private func turnOn() {
        store.enable()
    }
}

/// The accent wash behind a row that waits for an answer.
private final class NewRowTint: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlAccentColor.withAlphaComponent(0.10).setFill()
        bounds.fill()
    }
}

/// "NEW": a small accent pill.
final class NewTag: NSView {
    static let identifier = NSUserInterfaceItemIdentifier("arrivalsNewTag")
    private let text = "NEW".localized
    private let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 9.5, weight: .bold), .foregroundColor: NSColor.white, .kern: 0.4,
    ]

    init() {
        super.init(frame: .zero)
        identifier = Self.identifier
        translatesAutoresizingMaskIntoConstraints = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var intrinsicContentSize: NSSize {
        let size = (text as NSString).size(withAttributes: attributes)
        return NSSize(width: ceil(size.width) + 12, height: 15)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlAccentColor.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 7.5, yRadius: 7.5).fill()
        let size = (text as NSString).size(withAttributes: attributes)
        (text as NSString).draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2),
                                withAttributes: attributes)
    }
}

#if DEBUG
/// Fixed content for `-settingsSnapshotDir`: the pane on, off and empty.
struct SnapshotMenuBarAppsStore: MenuBarAppsStore {
    var isEnabled: Bool
    var table: [String: MenuBarSection]
    var notRunning: Set<String> = []
    var pending: Set<String> = []
    var newAppDefault: NewAppDefault = .show
    let live = LiveMenuBarAppsStore()

    static let states: [(String, SnapshotMenuBarAppsStore)] = [
        ("on", SnapshotMenuBarAppsStore(isEnabled: true, table: [
            "com.apple.Safari": .visible, "com.apple.Notes": .hidden, "com.apple.Music": .alwaysHidden,
            "com.apple.controlcenter": .visible, "com.apple.ActivityMonitor": .hidden,
            "com.example.uninstalled": .hidden, "com.apple.chronod": .hidden, "com.apple.sharingd": .hidden,
            "com.apple.screensharing.agent": .hidden, "com.apple.SSMenuAgent": .visible,
            "com.hnc.Discord.helper.Renderer": .hidden,
        ], notRunning: ["com.example.uninstalled", "com.apple.chronod"])),
        // Ask Me, with two apps that have not been answered: listed first, tagged NEW.
        ("new", SnapshotMenuBarAppsStore(isEnabled: true, table: [
            "com.apple.Safari": .visible, "com.apple.Notes": .hidden, "com.apple.Music": .alwaysHidden,
            "com.apple.ActivityMonitor": .hidden, "com.apple.TextEdit": .visible, "com.apple.Preview": .visible,
        ], pending: ["com.apple.TextEdit", "com.apple.Preview"], newAppDefault: .ask)),
        ("off", SnapshotMenuBarAppsStore(isEnabled: false, table: [:])),
        ("empty", SnapshotMenuBarAppsStore(isEnabled: true, table: [:])),
    ]

    func entries() -> [PinnedSectionsList.Entry] {
        PinnedSectionsList.entries(table: table, name: { live.identity(for: $0).name }, pending: pending)
    }

    func identity(for bundle: String) -> MenuBarAppIdentity.Resolved { live.identity(for: bundle) }
    func icon(for bundle: String) -> NSImage { live.icon(for: bundle) }
    func runningBundles() -> Set<String> { Set(table.keys).subtracting(notRunning) }
    func set(_ section: MenuBarSection, for bundle: String) {}
    func setIgnoresDrags(_ ignores: Bool, for bundle: String) {}
    func resetAllToVisible() {}
    func remove(_ bundle: String) {}
    func enable() {}
    func setNewAppDefault(_ choice: NewAppDefault) {}
}
#endif
