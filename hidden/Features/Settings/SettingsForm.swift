//
//  SettingsForm.swift
//  Hidden Bar
//
//  Copyright © 2026 Console Labs. All rights reserved.
//

import AppKit

// Building blocks for the grouped, System Settings style form: a section title,
// a rounded group of rows, and a row with its label left and its control right.
// Everything draws in draw(_:), so the window also renders into a bitmap.

enum SettingsMetrics {
    static let contentWidth: CGFloat = 600
    static let sideInset: CGFloat = 20
    static let rowInset: CGFloat = 12
    static let rowMinHeight: CGFloat = 34
    static let groupRadius: CGFloat = 10
    static let sectionSpacing: CGFloat = 10
}

enum SettingsColors {
    static let groupFill = NSColor(name: nil) { appearance in
        appearance.isDark ? NSColor.white.withAlphaComponent(0.05) : NSColor.white.withAlphaComponent(0.85)
    }
    static let groupStroke = NSColor(name: nil) { appearance in
        appearance.isDark ? NSColor.white.withAlphaComponent(0.09) : NSColor.black.withAlphaComponent(0.07)
    }
    static let menuBarFill = NSColor(name: nil) { appearance in
        appearance.isDark ? NSColor(white: 0.24, alpha: 1) : NSColor(red: 0.84, green: 0.86, blue: 0.89, alpha: 1)
    }
}

extension NSAppearance {
    var isDark: Bool { bestMatch(from: [.aqua, .darkAqua]) == .darkAqua }
}

enum SettingsCardFrame {
    static func draw(in bounds: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
                                xRadius: SettingsMetrics.groupRadius, yRadius: SettingsMetrics.groupRadius)
        SettingsColors.groupFill.setFill()
        path.fill()
        SettingsColors.groupStroke.setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}

/// A rounded group of rows with hairlines between them. A group inside a
/// `SettingsScrollCard` draws no frame: the card draws it once, around the scroller.
final class SettingsGroupView: NSView {
    private let stack = NSStackView()
    var drawsFrame = true

    init(rows: [NSView]) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        rows.forEach(add)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func add(_ row: NSView) {
        if !stack.arrangedSubviews.isEmpty {
            let line = SettingsHairline()
            stack.addArrangedSubview(line)
            line.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -2 * SettingsMetrics.rowInset).isActive = true
            line.leadingAnchor.constraint(equalTo: stack.leadingAnchor, constant: SettingsMetrics.rowInset).isActive = true
            line.isHidden = row.isHidden
        }
        stack.addArrangedSubview(row)
        row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard drawsFrame else { return }
        SettingsCardFrame.draw(in: bounds)
    }
}

/// A group of rows taller than the card should grow: the rows scroll inside the
/// card, and the scroller sits inside the card's frame, so the card keeps the
/// same left and right edges as every other card whatever the scroller style.
final class SettingsScrollCard: NSView {
    let scroll = NSScrollView()

    init(group: SettingsGroupView, height: CGFloat) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        group.drawsFrame = false
        let document = SettingsFlippedView()
        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(group)
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.documentView = document
        addSubview(scroll)
        // One point in from the frame, so the scroller never covers the stroke.
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: topAnchor, constant: 1),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -1),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 1),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -1),
            group.topAnchor.constraint(equalTo: document.topAnchor),
            group.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            group.trailingAnchor.constraint(equalTo: document.trailingAnchor),
            group.bottomAnchor.constraint(equalTo: document.bottomAnchor),
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            heightAnchor.constraint(equalToConstant: height),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func draw(_ dirtyRect: NSRect) {
        SettingsCardFrame.draw(in: bounds)
    }
}

/// A scroll view's document grows downward only when flipped.
final class SettingsFlippedView: NSView {
    override var isFlipped: Bool { true }
}

final class SettingsHairline: NSView {
    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 1).isActive = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.separatorColor.setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: 0.5).fill()
    }
}

enum SettingsForm {
    static func sectionTitle(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        label.textColor = .labelColor
        return label
    }

    static func caption(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        label.textColor = .secondaryLabelColor
        label.isSelectable = false
        return label
    }

    /// Label (and optional caption) on the left, the control on the right.
    static func row(_ title: String, caption captionText: String? = nil, control: NSView?) -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false
        let titleLabel = NSTextField(wrappingLabelWithString: title)
        titleLabel.isSelectable = false
        titleLabel.font = .systemFont(ofSize: NSFont.systemFontSize)
        let texts = NSStackView(views: [titleLabel])
        texts.orientation = .vertical
        texts.alignment = .leading
        texts.spacing = 2
        if let captionText {
            texts.addArrangedSubview(caption(captionText))
        }
        texts.translatesAutoresizingMaskIntoConstraints = false
        texts.setContentHuggingPriority(.defaultLow, for: .horizontal)
        row.addSubview(texts)
        var constraints = [
            texts.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: SettingsMetrics.rowInset),
            texts.topAnchor.constraint(greaterThanOrEqualTo: row.topAnchor, constant: 7),
            texts.bottomAnchor.constraint(lessThanOrEqualTo: row.bottomAnchor, constant: -7),
            texts.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            row.heightAnchor.constraint(greaterThanOrEqualToConstant: SettingsMetrics.rowMinHeight),
        ]
        if let control {
            control.translatesAutoresizingMaskIntoConstraints = false
            control.setContentCompressionResistancePriority(.required, for: .horizontal)
            control.setContentHuggingPriority(.required, for: .horizontal)
            row.addSubview(control)
            constraints += [
                control.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -SettingsMetrics.rowInset),
                control.centerYAnchor.constraint(equalTo: row.centerYAnchor),
                control.leadingAnchor.constraint(greaterThanOrEqualTo: texts.trailingAnchor, constant: 16),
                control.topAnchor.constraint(greaterThanOrEqualTo: row.topAnchor, constant: 6),
            ]
        } else {
            constraints.append(texts.trailingAnchor.constraint(lessThanOrEqualTo: row.trailingAnchor, constant: -SettingsMetrics.rowInset))
        }
        NSLayoutConstraint.activate(constraints)
        return row
    }

    /// A borderless button that looks like a link and opens `url`.
    static func link(_ title: String, url: URL, image: NSImage? = nil) -> NSButton {
        let button = LinkButton(title: title, url: url)
        if let image {
            button.image = image
            button.imagePosition = .imageLeading
            button.imageHugsTitle = true
        }
        return button
    }
}

/// A switch bound to one stored preference. The identifier is the defaults key,
/// so tests can find the control for each key.
final class PrefSwitch: NSSwitch {
    private let read: () -> Bool
    private let write: (Bool) -> Void

    init(key: String, read: @escaping () -> Bool, write: @escaping (Bool) -> Void) {
        self.read = read
        self.write = write
        super.init(frame: .zero)
        identifier = NSUserInterfaceItemIdentifier(key)
        controlSize = .small
        target = self
        action = #selector(toggled)
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    @objc private func toggled() {
        write(state == .on)
        refresh()
    }

    func refresh() {
        state = read() ? .on : .off
    }
}

final class LinkButton: NSButton {
    let url: URL

    init(title: String, url: URL) {
        self.url = url
        super.init(frame: .zero)
        self.title = title
        isBordered = false
        setButtonType(.momentaryChange)
        attributedTitle = NSAttributedString(string: title, attributes: [
            .foregroundColor: NSColor.linkColor,
            .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
        ])
        contentTintColor = .linkColor
        target = self
        action = #selector(open)
        toolTip = url.absoluteString
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    @objc private func open() {
        NSWorkspace.shared.open(url)
    }
}

/// Base for every pane: a vertical form inside the window's width, refreshed
/// whenever a preference changes from anywhere (menu, hotkey, import).
class SettingsPaneController: NSViewController {
    let context: SettingsContext
    let form = NSStackView()
    private var refreshers: [() -> Void] = []

    init(context: SettingsContext) {
        self.context = context
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func loadView() {
        let root = NSView()
        form.orientation = .vertical
        form.alignment = .leading
        form.spacing = 6
        form.edgeInsets = NSEdgeInsets(top: 14, left: SettingsMetrics.sideInset, bottom: 18, right: SettingsMetrics.sideInset)
        form.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(form)
        NSLayoutConstraint.activate([
            form.topAnchor.constraint(equalTo: root.topAnchor),
            form.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            form.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            form.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])
        // The window is this wide, but a scroll view with an always-visible
        // scroller hands the pane less. The pane then yields (this is not
        // required) and the cards follow the width they get.
        let preferredWidth = root.widthAnchor.constraint(equalToConstant: SettingsMetrics.contentWidth + 2 * SettingsMetrics.sideInset)
        preferredWidth.priority = .defaultHigh
        preferredWidth.isActive = true
        view = root
        buildForm()
        for name: Notification.Name in [.prefsChanged, .alwayHideToggle, .useFullStatusBarToggle, .stealthExpandIconToggle,
                                        .arrowStyleChanged, .accessibilityPermissionChanged, .unkeepableSystemItemsChanged] {
            NotificationCenter.default.addObserver(self, selector: #selector(refreshAll), name: name, object: nil)
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    /// Subclasses add their sections here.
    func buildForm() {}

    func addSection(_ title: String?, rows: [NSView], spacingBefore: CGFloat = SettingsMetrics.sectionSpacing) {
        if let last = form.arrangedSubviews.last {
            form.setCustomSpacing(spacingBefore, after: last)
        }
        if let title {
            let label = SettingsForm.sectionTitle(title)
            form.addArrangedSubview(label)
            form.setCustomSpacing(6, after: label)
        }
        let group = SettingsGroupView(rows: rows)
        addFullWidth(group)
    }

    func addFullWidth(_ view: NSView) {
        view.translatesAutoresizingMaskIntoConstraints = false
        form.addArrangedSubview(view)
        view.widthAnchor.constraint(equalTo: form.widthAnchor, constant: -2 * SettingsMetrics.sideInset).isActive = true
    }

    func addFootnote(_ text: String) {
        let label = SettingsForm.caption(text)
        if let last = form.arrangedSubviews.last { form.setCustomSpacing(8, after: last) }
        form.addArrangedSubview(label)
        label.widthAnchor.constraint(equalTo: form.widthAnchor, constant: -2 * SettingsMetrics.sideInset).isActive = true
    }

    func boundSwitch(_ key: String, read: @escaping () -> Bool, write: @escaping (Bool) -> Void) -> PrefSwitch {
        let control = PrefSwitch(key: key, read: read, write: write)
        onRefresh { [weak control] in control?.refresh() }
        return control
    }

    func onRefresh(_ block: @escaping () -> Void) {
        refreshers.append(block)
    }

    @objc func refreshAll() {
        refreshers.forEach { $0() }
    }
}
