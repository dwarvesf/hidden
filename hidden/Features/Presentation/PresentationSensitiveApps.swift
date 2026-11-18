//
//  PresentationSensitiveApps.swift
//  Hidden Bar
//
//  Copyright © 2026 Console Labs. All rights reserved.
//

#if HIDDENBAR_NATIVE_VISIBILITY
import AppKit

// The "Sensitive apps" row's control: the chosen apps as chips, and the Edit
// button that opens the picker. The button's identifier is the preference key.
final class PresentationSensitiveAppsControl: NSStackView {
    static let maxChips = 4
    static let chipsWidth: CGFloat = 230

    let editButton = NSButton(title: "Edit...".localized, target: nil, action: nil)
    private let chipsHost = NSStackView()
    private let apps: () -> [PresentationAppChip]

    init(apps: @escaping () -> [PresentationAppChip]) {
        self.apps = apps
        super.init(frame: .zero)
        editButton.bezelStyle = .rounded
        editButton.identifier = NSUserInterfaceItemIdentifier(UserDefaults.Key.presentationSensitiveApps)
        chipsHost.orientation = .vertical
        chipsHost.alignment = .trailing
        orientation = .horizontal
        spacing = 10
        alignment = .centerY
        setViews([chipsHost, editButton], in: .leading)
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func refresh() {
        chipsHost.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let chips = apps()
        if chips.isEmpty {
            let none = NSTextField(labelWithString: "None".localized)
            none.textColor = .secondaryLabelColor
            none.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            chipsHost.addArrangedSubview(none)
        } else {
            let shown = Array(chips.prefix(Self.maxChips))
            chipsHost.addArrangedSubview(PresentationChipFlow(chips: shown, overflow: chips.count - shown.count,
                                                              width: Self.chipsWidth))
        }
    }

    #if DEBUG
    // Snapshots show fixture apps instead of this Mac's.
    static var snapshotChips: [PresentationAppChip]?
    #endif

    // The chosen apps, by name, with each one's icon.
    static func chips(for bundles: Set<String>, catalog: MenuBarItemCatalog = .shared) -> [PresentationAppChip] {
        #if DEBUG
        if let fixture = snapshotChips { return fixture }
        #endif
        let resolver = WorkspaceAppResolver()
        return bundles.map { bundle -> PresentationAppChip in
            if let entry = catalog.entry(for: bundle) { return PresentationAppChip(name: entry.name, icon: entry.icon) }
            return PresentationAppChip(name: resolver.name(of: bundle) ?? bundle, icon: resolver.icon(of: bundle))
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

// The picker: every app Hidden Bar has seen in the menu bar, with a checkbox.
// Apps already chosen that Hidden Bar no longer sees stay listed, so they can
// be taken off. Reads and writes the stored set directly.
final class PresentationSensitiveAppsEditor: NSViewController {
    static func checkboxIdentifier(for bundle: String) -> NSUserInterfaceItemIdentifier {
        return NSUserInterfaceItemIdentifier("presentationSensitive.\(bundle)")
    }

    private let rows: [(bundle: String, name: String, icon: NSImage?)]
    private let read: () -> Set<String>
    private let write: (Set<String>) -> Void
    private(set) var checkboxes: [NSButton] = []

    init(entries: [MenuBarCatalogEntry] = MenuBarItemCatalog.shared.entries,
         read: @escaping () -> Set<String> = { Preferences.presentationSensitiveApps },
         write: @escaping (Set<String>) -> Void = { Preferences.presentationSensitiveApps = $0 }) {
        var list = entries.map { (bundle: $0.bundleIdentifier, name: $0.name, icon: Optional($0.icon)) }
        let known = Set(list.map { $0.bundle })
        for bundle in read().subtracting(known) {
            let resolver = WorkspaceAppResolver()
            list.append((bundle, resolver.name(of: bundle) ?? bundle, resolver.icon(of: bundle)))
        }
        rows = list.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        self.read = read
        self.write = write
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func loadView() {
        let title = SettingsForm.sectionTitle("Sensitive apps".localized)
        let note = SettingsForm.caption("Choose the apps that stay hidden while presenting, even when you click the arrow, except while hiding is paused for the camera or microphone.".localized)
        note.preferredMaxLayoutWidth = 300
        let list = NSStackView()
        list.orientation = .vertical
        list.alignment = .leading
        list.spacing = 4
        if rows.isEmpty {
            list.addArrangedSubview(SettingsForm.caption("Apps with a menu bar icon appear here once Hidden Bar has seen them.".localized))
        }
        let chosen = read()
        for row in rows {
            let box = NSButton(checkboxWithTitle: row.name, target: self, action: #selector(toggled(_:)))
            box.identifier = Self.checkboxIdentifier(for: row.bundle)
            box.state = chosen.contains(row.bundle) ? .on : .off
            if let icon = row.icon {
                let small = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
                    icon.draw(in: rect)
                    return true
                }
                box.image = small
                box.imagePosition = .imageLeading
            }
            checkboxes.append(box)
            list.addArrangedSubview(box)
        }
        let scroll = NSScrollView()
        scroll.documentView = list
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        list.translatesAutoresizingMaskIntoConstraints = false
        let height = min(CGFloat(max(rows.count, 1)) * 22 + 8, 260)
        let root = NSStackView(views: [title, note, scroll])
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 8
        root.edgeInsets = NSEdgeInsets(top: 14, left: 16, bottom: 14, right: 16)
        NSLayoutConstraint.activate([
            scroll.widthAnchor.constraint(equalToConstant: 300),
            scroll.heightAnchor.constraint(equalToConstant: height),
            list.widthAnchor.constraint(equalToConstant: 284),
        ])
        view = root
        preferredContentSize = root.fittingSize
    }

    @objc private func toggled(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue, raw.hasPrefix("presentationSensitive.") else { return }
        let bundle = String(raw.dropFirst("presentationSensitive.".count))
        var chosen = read()
        if sender.state == .on { chosen.insert(bundle) } else { chosen.remove(bundle) }
        write(chosen)
    }
}
#endif
