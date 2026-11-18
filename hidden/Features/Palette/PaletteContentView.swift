//
//  PaletteContentView.swift
//  Hidden Bar
//
//  Copyright © 2026 Console Labs. All rights reserved.
//

#if HIDDENBAR_NATIVE_VISIBILITY
import AppKit

/// What the palette draws: the query, what it gives, which row is selected, and
/// which app a Return is opening right now.
struct PaletteViewState: Equatable {
    var query: String
    var content: PaletteContent
    var selectedIndex: Int
    var openingBundle: String?
    /// False hides the two hints that move an app between sections.
    var pinsSections = true
}

/// The buttons an edge state offers.
enum PaletteEdgeAction {
    case openAccessibilitySettings
    case openMenuBarApps
}

/// The palette's contents: a search field over a list, or over one of the
/// edge states, with the key hints under the list. Drawn from a
/// `PaletteViewState` and nothing else, so a snapshot can draw any state from
/// fixture data. Widths and type sizes follow the Palette boards.
final class PaletteContentView: NSView, NSTextFieldDelegate {
    static let width: CGFloat = 380
    static let rowHeight: CGFloat = 38
    static let headerHeight: CGFloat = 24
    static let maxListHeight: CGFloat = 308

    let searchField = NSTextField()
    var onQueryChange: ((String) -> Void)?
    var onRowClick: ((String) -> Void)?
    var onAction: ((PaletteEdgeAction) -> Void)?

    private let background: NSView
    private let stack = NSStackView()
    private let queryRow = NSView()
    private let magnifier = NSImageView()
    private var scroll: NSScrollView?
    private var rowViews: [String: NSView] = [:]
    private let flat: Bool

    /// `flat` draws the glass as a fixed fill, for snapshots: a blur behind a
    /// window that is never on screen draws nothing.
    init(flat: Bool = false) {
        self.flat = flat
        if flat {
            let fill = NSView()
            fill.wantsLayer = true
            background = fill
        } else {
            let blur = NSVisualEffectView()
            blur.material = .popover
            blur.blendingMode = .behindWindow
            blur.state = .active
            background = blur
        }
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 16
        layer?.masksToBounds = true
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor.separatorColor.cgColor

        background.translatesAutoresizingMaskIntoConstraints = false
        addSubview(background)
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: Self.width),
            background.leadingAnchor.constraint(equalTo: leadingAnchor),
            background.trailingAnchor.constraint(equalTo: trailingAnchor),
            background.topAnchor.constraint(equalTo: topAnchor),
            background.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        buildQueryRow()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateBackground()
        layer?.borderColor = NSColor.separatorColor.cgColor
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateBackground()
    }

    /// The glass of the boards: light 70% white, dark 66% near black.
    private func updateBackground() {
        guard flat else { return }
        effectiveAppearance.performAsCurrentDrawingAppearance {
            background.layer?.backgroundColor = Self.flatGlass.cgColor
        }
    }

    static let flatGlass = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.141, green: 0.141, blue: 0.157, alpha: 0.66)
            : NSColor(srgbRed: 0.980, green: 0.980, blue: 0.988, alpha: 0.70)
    }

    // MARK: Search row

    private func buildQueryRow() {
        magnifier.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)
        magnifier.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        magnifier.contentTintColor = .secondaryLabelColor
        magnifier.translatesAutoresizingMaskIntoConstraints = false

        searchField.isBordered = false
        searchField.drawsBackground = false
        searchField.focusRingType = .none
        searchField.font = .systemFont(ofSize: 17)
        searchField.placeholderString = "Find a hidden icon".localized
        searchField.cell?.sendsActionOnEndEditing = false
        searchField.delegate = self
        searchField.setAccessibilityLabel("Find a hidden icon".localized)
        searchField.translatesAutoresizingMaskIntoConstraints = false

        queryRow.translatesAutoresizingMaskIntoConstraints = false
        queryRow.addSubview(magnifier)
        queryRow.addSubview(searchField)
        NSLayoutConstraint.activate([
            queryRow.heightAnchor.constraint(equalToConstant: 46),
            magnifier.leadingAnchor.constraint(equalTo: queryRow.leadingAnchor, constant: 14),
            magnifier.centerYAnchor.constraint(equalTo: queryRow.centerYAnchor),
            magnifier.widthAnchor.constraint(equalToConstant: 16),
            searchField.leadingAnchor.constraint(equalTo: magnifier.trailingAnchor, constant: 9),
            searchField.trailingAnchor.constraint(equalTo: queryRow.trailingAnchor, constant: -14),
            searchField.centerYAnchor.constraint(equalTo: queryRow.centerYAnchor),
        ])
    }

    func controlTextDidChange(_ notification: Notification) {
        onQueryChange?(searchField.stringValue)
    }

    // MARK: Drawing a state

    func apply(_ state: PaletteViewState, icon: (String) -> NSImage?) {
        if searchField.stringValue != state.query {
            searchField.stringValue = state.query
        }
        scroll = nil
        rowViews = [:]
        var views: [NSView] = [queryRow, Self.divider()]
        switch state.content {
        case .results(let items):
            views.append(resultsView(items, state: state, icon: icon))
            views.append(Self.divider())
            views.append(keyHints(pinsSections: state.pinsSections))
        case .noMatch(let query, let shownApp, let quitApp):
            let detail: String
            if let shownApp {
                detail = String(format: "%@ is shown in the menu bar now.".localized, shownApp)
            } else if let quitApp {
                detail = String(format: "%@ is not running.".localized, quitApp)
            } else {
                detail = "Only hidden icons are listed. Shown icons are already one click away.".localized
            }
            views.append(emptyState(title: String(format: "No hidden icon matches \"%@\"".localized, query), detail: detail))
        case .nothingHidden:
            views.append(emptyState(title: "Nothing is hidden right now".localized,
                                    detail: "Hold ⌘ and drag an icon left of the arrow, or pick sections in Settings.".localized,
                                    button: ("Open Menu Bar Apps".localized, false, .openMenuBarApps)))
        case .accessibilityOff:
            views.append(emptyState(title: "Hidden Bar needs Accessibility access".localized,
                                    detail: "It reads which apps are in the menu bar and opens their menus. It never reads what is on your screen.".localized,
                                    badge: "lock.fill",
                                    button: ("Open System Settings".localized, true, .openAccessibilitySettings)))
        case .systemItem(let name):
            views.append(emptyState(title: String(format: "%@ can't be opened from here".localized, name),
                                    detail: "macOS hides Focus, Siri and Now Playing whenever Hidden Bar hides icons. Click the arrow to show everything.".localized))
        case .engineUnavailable:
            views.append(emptyState(title: "Hidden Bar is not hiding icons right now".localized,
                                    detail: "Every icon is already in the menu bar, so there is nothing to find. Open Settings to see why.".localized,
                                    badge: "exclamationmark.triangle.fill"))
        case .cannotOpen(let appName):
            views.append(emptyState(title: String(format: "%@ can't be opened from here".localized, appName),
                                    detail: "Its icon does not answer Accessibility. Click the arrow to show everything, then click its icon.".localized,
                                    badge: "exclamationmark.triangle.fill"))
        }
        stack.setViews(views, in: .top)
        if let selected = selectedBundle(in: state), let row = rowViews[selected] {
            scroll?.documentView?.layoutSubtreeIfNeeded()
            row.scrollToVisible(row.bounds)
        }
    }

    private func selectedBundle(in state: PaletteViewState) -> String? {
        guard case .results(let items) = state.content else { return nil }
        let matches = items.compactMap { item -> PaletteMatch? in
            if case .row(let match) = item { return match }
            return nil
        }
        return matches.indices.contains(state.selectedIndex) ? matches[state.selectedIndex].candidate.bundleIdentifier : nil
    }

    private static func divider() -> NSView {
        let line = NSBox()
        line.boxType = .separator
        line.translatesAutoresizingMaskIntoConstraints = false
        return line
    }

    // MARK: Results

    private func resultsView(_ items: [PaletteListItem], state: PaletteViewState, icon: (String) -> NSImage?) -> NSView {
        let list = FlippedStackView()
        list.orientation = .vertical
        list.alignment = .leading
        list.spacing = 0
        list.edgeInsets = NSEdgeInsets(top: 6, left: 6, bottom: 6, right: 6)
        list.translatesAutoresizingMaskIntoConstraints = false
        let showsSection = !items.contains { if case .header = $0 { return true } else { return false } }
        var height: CGFloat = 12
        var rowIndex = 0
        for item in items {
            switch item {
            case .header(let section):
                let header = PaletteHeaderView(title: Self.sectionTitle(section))
                list.addArrangedSubview(header)
                header.widthAnchor.constraint(equalTo: list.widthAnchor, constant: -12).isActive = true
                height += Self.headerHeight
            case .row(let match):
                let bundle = match.candidate.bundleIdentifier
                let selected = rowIndex == state.selectedIndex
                let row = PaletteRowView(match: match, icon: icon(bundle), selected: selected,
                                         opening: selected && state.openingBundle == bundle,
                                         dimmed: state.openingBundle != nil && state.openingBundle != bundle,
                                         showsSection: showsSection || !selected)
                row.onClick = { [weak self] in self?.onRowClick?(bundle) }
                list.addArrangedSubview(row)
                row.widthAnchor.constraint(equalTo: list.widthAnchor, constant: -12).isActive = true
                rowViews[bundle] = row
                height += Self.rowHeight
                rowIndex += 1
            }
        }
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = height > Self.maxListHeight
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        let clip = FlippedClipView()
        clip.drawsBackground = false
        scrollView.contentView = clip
        scrollView.documentView = list
        NSLayoutConstraint.activate([
            scrollView.heightAnchor.constraint(equalToConstant: min(height, Self.maxListHeight)),
            list.leadingAnchor.constraint(equalTo: clip.leadingAnchor),
            list.trailingAnchor.constraint(equalTo: clip.trailingAnchor),
            list.topAnchor.constraint(equalTo: clip.topAnchor),
        ])
        scroll = scrollView
        return scrollView
    }

    static func sectionTitle(_ section: MenuBarSection) -> String {
        switch section {
        case .visible: return "Visible".localized
        case .hidden: return "Hidden".localized
        case .alwaysHidden: return "Always hidden".localized
        }
    }

    // MARK: Edge states

    private func emptyState(title: String, detail: String, badge: String? = nil,
                            button: (title: String, primary: Bool, action: PaletteEdgeAction)? = nil) -> NSView {
        let wrapper = NSView()
        wrapper.translatesAutoresizingMaskIntoConstraints = false
        let column = NSStackView()
        column.orientation = .vertical
        column.alignment = .centerX
        column.spacing = 4
        column.translatesAutoresizingMaskIntoConstraints = false
        if let badge {
            let badgeView = PaletteBadgeView(symbol: badge)
            column.addArrangedSubview(badgeView)
            column.setCustomSpacing(8, after: badgeView)
        }
        let titleLabel = NSTextField(wrappingLabelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13.5, weight: .semibold)
        let detailLabel = NSTextField(wrappingLabelWithString: detail)
        detailLabel.font = .systemFont(ofSize: 12)
        detailLabel.textColor = .secondaryLabelColor
        for label in [titleLabel, detailLabel] {
            label.alignment = .center
            label.isSelectable = false
            label.preferredMaxLayoutWidth = Self.width - 36
            label.widthAnchor.constraint(equalToConstant: Self.width - 36).isActive = true
            column.addArrangedSubview(label)
        }
        if let button {
            let control = NSButton(title: button.title, target: self, action: #selector(edgeButtonPressed(_:)))
            control.bezelStyle = .rounded
            control.controlSize = .small
            control.keyEquivalent = ""
            if button.primary { control.bezelColor = .controlAccentColor }
            edgeAction = button.action
            column.addArrangedSubview(control)
            column.setCustomSpacing(12, after: detailLabel)
        }
        wrapper.addSubview(column)
        NSLayoutConstraint.activate([
            column.centerXAnchor.constraint(equalTo: wrapper.centerXAnchor),
            column.topAnchor.constraint(equalTo: wrapper.topAnchor, constant: 22),
            column.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor, constant: -20),
        ])
        return wrapper
    }

    private var edgeAction: PaletteEdgeAction?

    @objc private func edgeButtonPressed(_ sender: NSButton) {
        if let edgeAction { onAction?(edgeAction) }
    }

    // MARK: Key hints

    // The board wraps the four hints; at this width the last one takes a second line.
    private func keyHints(pinsSections: Bool) -> NSView {
        // Without the pinned-sections beta the two move keys do nothing, so they
        // are not offered.
        let hints: [([String], String)] = pinsSections
            ? [(["↵"], "Open its menu"), (["⌘", "↵"], "Keep shown"), (["⌥", "↵"], "Always hide"), (["esc"], "Close")]
            : [(["↵"], "Open its menu"), (["esc"], "Close")]
        func line(_ items: ArraySlice<([String], String)>) -> NSStackView {
            let row = NSStackView()
            row.orientation = .horizontal
            row.spacing = 14
            row.alignment = .centerY
            for (keys, text) in items {
                let caps = NSStackView(views: keys.map { PaletteKeyCap(text: $0) })
                caps.spacing = 2
                let label = NSTextField(labelWithString: text.localized)
                label.font = .systemFont(ofSize: 11)
                label.textColor = .secondaryLabelColor
                let hint = NSStackView(views: [caps, label])
                hint.spacing = 4
                hint.setContentHuggingPriority(.required, for: .horizontal)
                row.addArrangedSubview(hint)
            }
            // Takes the slack, so the hints stay together at the left.
            let spacer = NSView()
            spacer.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
            row.addArrangedSubview(spacer)
            return row
        }
        let lines = NSStackView(views: pinsSections ? [line(hints[0..<3]), line(hints[3...])] : [line(hints[...])])
        lines.orientation = .vertical
        lines.alignment = .width
        lines.spacing = 4
        lines.edgeInsets = NSEdgeInsets(top: 8, left: 14, bottom: 10, right: 14)
        lines.translatesAutoresizingMaskIntoConstraints = false
        return lines
    }
}

// MARK: - Pieces

private final class FlippedStackView: NSStackView {
    override var isFlipped: Bool { true }
}

private final class FlippedClipView: NSClipView {
    override var isFlipped: Bool { true }
}

private final class PaletteHeaderView: NSView {
    init(title: String) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: PaletteContentView.headerHeight),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3),
        ])
        setAccessibilityRole(.staticText)
        setAccessibilityLabel(title)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

private final class PaletteRowView: NSView {
    var onClick: (() -> Void)?
    private let isSelectedRow: Bool

    init(match: PaletteMatch, icon: NSImage?, selected: Bool, opening: Bool, dimmed: Bool, showsSection: Bool) {
        isSelectedRow = selected
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 9
        alphaValue = dimmed ? 0.55 : 1
        let primary: NSColor = selected ? .white : .labelColor
        let secondary: NSColor = selected ? NSColor.white.withAlphaComponent(0.8) : .secondaryLabelColor
        let iconView = NSImageView(image: icon ?? NSImage())
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false

        let name = NSTextField(labelWithAttributedString: Self.styledName(match, color: primary))
        name.lineBreakMode = .byTruncatingTail
        let bundle = NSTextField(labelWithString: match.candidate.bundleIdentifier)
        bundle.font = .systemFont(ofSize: 10.5)
        bundle.textColor = secondary
        bundle.lineBreakMode = .byTruncatingMiddle
        let texts = NSStackView(views: [name, bundle])
        texts.orientation = .vertical
        texts.alignment = .leading
        texts.spacing = 0
        texts.setHuggingPriority(.defaultLow, for: .horizontal)
        texts.translatesAutoresizingMaskIntoConstraints = false

        let trailing = NSTextField(labelWithString: opening ? "Opening…".localized
                                   : selected ? "↵ " + "Open".localized
                                   : PaletteContentView.sectionTitle(match.candidate.section))
        trailing.font = .systemFont(ofSize: 11.5, weight: selected ? .semibold : .regular)
        trailing.textColor = selected ? NSColor.white.withAlphaComponent(opening ? 0.8 : 1) : .secondaryLabelColor
        trailing.isHidden = !showsSection && !selected
        trailing.setContentCompressionResistancePriority(.required, for: .horizontal)
        trailing.translatesAutoresizingMaskIntoConstraints = false

        addSubview(iconView)
        addSubview(texts)
        addSubview(trailing)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: PaletteContentView.rowHeight),
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 24),
            iconView.heightAnchor.constraint(equalToConstant: 24),
            texts.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
            texts.centerYAnchor.constraint(equalTo: centerYAnchor),
            texts.trailingAnchor.constraint(lessThanOrEqualTo: trailing.leadingAnchor, constant: -8),
            trailing.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            trailing.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        setAccessibilityRole(.button)
        setAccessibilityLabel("\(match.candidate.name), \(PaletteContentView.sectionTitle(match.candidate.section))")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        paintSelection()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        paintSelection()
    }

    private func paintSelection() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = isSelectedRow ? NSColor.controlAccentColor.cgColor : nil
        }
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }

    /// The name with the characters the query matched in bold.
    static func styledName(_ match: PaletteMatch, color: NSColor) -> NSAttributedString {
        let regular = NSFont.systemFont(ofSize: 13.5, weight: .medium)
        let bold = NSFont.systemFont(ofSize: 13.5, weight: .bold)
        let text = NSMutableAttributedString()
        let highlighted = Set(match.highlighted)
        for (offset, character) in match.candidate.name.enumerated() {
            text.append(NSAttributedString(string: String(character),
                                           attributes: [.font: highlighted.contains(offset) ? bold : regular, .foregroundColor: color]))
        }
        return text
    }
}

private final class PaletteKeyCap: NSView {
    private let label: NSTextField

    init(text: String) {
        label = NSTextField(labelWithString: text)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 5
        layer?.borderWidth = 0.5
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var intrinsicContentSize: NSSize {
        return NSSize(width: max(17, label.intrinsicContentSize.width + 8), height: 17)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        viewDidChangeEffectiveAppearance()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
            layer?.borderColor = NSColor.separatorColor.cgColor
        }
    }
}

private final class PaletteBadgeView: NSView {
    init(symbol: String) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.backgroundColor = NSColor.systemOrange.cgColor
        let image = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil) ?? NSImage())
        image.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        image.contentTintColor = .white
        image.translatesAutoresizingMaskIntoConstraints = false
        addSubview(image)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 30),
            heightAnchor.constraint(equalToConstant: 30),
            image.centerXAnchor.constraint(equalTo: centerXAnchor),
            image.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}
#endif
