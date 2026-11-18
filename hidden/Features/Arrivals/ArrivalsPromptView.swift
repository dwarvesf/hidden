//
//  ArrivalsPromptView.swift
//  Hidden Bar
//
//  Copyright © 2026 Console Labs. All rights reserved.
//

#if HIDDENBAR_NATIVE_VISIBILITY
import AppKit

// What the prompt shows, decided apart from any view so a test can read it.
struct ArrivalsPromptModel {
    enum Style: Equatable {
        // Show / Hide, and Always hide behind the ellipsis.
        case question
        // A known app came back where the user put it: told, not asked.
        case kept
        // Something Hidden Bar cannot keep shown: told once, OK.
        case notice
    }

    struct Row {
        let bundle: String
        let name: String
        let caption: String
        let icon: NSImage
        let style: Style
    }

    enum Footer: Equatable {
        // "Not sure?" and a way to Settings.
        case hint
        // "and N more", with one answer for everything waiting.
        case bulk(more: Int)
        case text(String)
        case none
    }

    var title: String
    var subtitle: String?
    var rows: [Row]
    var footer: Footer

    // More than this and the rest sit behind "and N more" with Hide All / Show All.
    static let visibleRows = 3

    // `infos` is newest first.
    static func make(infos: [ArrivalInfo], now: Date) -> ArrivalsPromptModel {
        let more = max(infos.count - visibleRows, 0)
        let title = infos.count > visibleRows
            ? String(format: "%d new apps in your menu bar".localized, infos.count)
            : "New in your menu bar".localized
        let rows = infos.prefix(visibleRows).map {
            Row(bundle: $0.bundle, name: $0.name, caption: caption(for: $0, now: now), icon: $0.icon, style: .question)
        }
        return ArrivalsPromptModel(title: title,
                                   subtitle: "Choose once. Hidden Bar remembers, also after the app or your Mac restarts.".localized,
                                   rows: rows, footer: more > 0 ? .bulk(more: more) : .hint)
    }

    static func caption(for info: ArrivalInfo, now: Date) -> String {
        if !info.isRunning {
            return "Not running now. It stays shown until you choose.".localized
        }
        if info.iconCount > 1 {
            return String(format: "Added %d icons. They show or hide together.".localized, info.iconCount)
        }
        return String(format: "Added an icon %@".localized, since(info.firstSeen, now: now))
    }

    static func since(_ date: Date, now: Date) -> String {
        guard now.timeIntervalSince(date) >= 60 else { return "just now".localized }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: now)
    }
}

// The inbox as the board draws it: a title, one row per waiting app with Show and
// Hide (and Always hide behind the ellipsis), and a footer. It owns no state.
final class ArrivalsPromptView: NSView {
    static let width: CGFloat = 360
    static let padding: CGFloat = 12

    static func showIdentifier(_ bundle: String) -> String { "arrivalsAnswer.\(bundle)" }
    static func alwaysHideIdentifier(_ bundle: String) -> String { "arrivalsAlwaysHide.\(bundle)" }
    static func okIdentifier(_ bundle: String) -> String { "arrivalsOK.\(bundle)" }
    static let hideAllIdentifier = "arrivalsHideAll"
    static let showAllIdentifier = "arrivalsShowAll"
    static let settingsIdentifier = "arrivalsSettings"

    var onAnswer: (String, ArrivalAnswer) -> Void = { _, _ in }
    var onAnswerAll: (ArrivalAnswer) -> Void = { _ in }
    var onDismiss: (String) -> Void = { _ in }
    var onOpenSettings: () -> Void = {}

    private(set) var model: ArrivalsPromptModel
    private let stack = NSStackView()

    init(model: ArrivalsPromptModel) {
        self.model = model
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        let pad = Self.padding
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: Self.width),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: pad),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: pad),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -pad),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -pad),
        ])
        build()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func update(_ model: ArrivalsPromptModel) {
        self.model = model
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        build()
    }

    // The size the popover needs.
    var fittingContentSize: NSSize {
        layoutSubtreeIfNeeded()
        return NSSize(width: Self.width, height: fittingSize.height)
    }

    private var innerWidth: CGFloat { Self.width - 2 * Self.padding }

    private func build() {
        let title = NSTextField(labelWithString: model.title)
        title.font = .systemFont(ofSize: 13.5, weight: .semibold)
        add(title, spacingAfter: model.subtitle == nil ? 8 : 2)
        if let subtitle = model.subtitle {
            let sub = NSTextField(wrappingLabelWithString: subtitle)
            sub.font = .systemFont(ofSize: 11.5)
            sub.textColor = .secondaryLabelColor
            sub.preferredMaxLayoutWidth = innerWidth
            add(sub, spacingAfter: 4)
        }
        for row in model.rows {
            add(separator(), fullWidth: true)
            add(rowView(row), fullWidth: true)
        }
        if model.footer != .none {
            add(separator(), fullWidth: true)
            add(footerView(), fullWidth: true)
        }
    }

    private func add(_ view: NSView, spacingAfter: CGFloat = 0, fullWidth: Bool = false) {
        view.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(view)
        stack.setCustomSpacing(spacingAfter, after: view)
        if fullWidth { view.widthAnchor.constraint(equalToConstant: innerWidth).isActive = true }
    }

    private func separator() -> NSView {
        let line = NSBox()
        line.boxType = .separator
        return line
    }

    private func rowView(_ row: ArrivalsPromptModel.Row) -> NSView {
        let icon = NSImageView(image: row.icon)
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.wantsLayer = true
        icon.layer?.cornerRadius = 7
        icon.layer?.masksToBounds = true
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 28).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 28).isActive = true

        let name = NSTextField(labelWithString: row.name)
        name.font = .systemFont(ofSize: 13)
        name.lineBreakMode = .byTruncatingTail
        let caption = NSTextField(wrappingLabelWithString: row.caption)
        caption.font = .systemFont(ofSize: 11)
        caption.textColor = .secondaryLabelColor
        caption.maximumNumberOfLines = 3
        let controls = controlsView(for: row)
        // Every row gives its text the same width, so the controls line up in a column.
        let textWidth = innerWidth - 8 - 28 - 20 - controls.fittingSize.width
        caption.preferredMaxLayoutWidth = textWidth
        let texts = NSStackView(views: [name, caption])
        texts.orientation = .vertical
        texts.alignment = .leading
        texts.spacing = 1
        texts.widthAnchor.constraint(equalToConstant: textWidth).isActive = true

        let line = NSStackView(views: [icon, texts, controls])
        line.orientation = .horizontal
        line.alignment = .centerY
        line.spacing = 10
        line.edgeInsets = NSEdgeInsets(top: 11, left: 4, bottom: 11, right: 4)
        return line
    }

    private func controlsView(for row: ArrivalsPromptModel.Row) -> NSView {
        switch row.style {
        case .question:
            let segments = NSSegmentedControl(labels: ["Show".localized, "Hide".localized], trackingMode: .selectOne,
                                              target: self, action: #selector(segmentPressed(_:)))
            segments.controlSize = .small
            segments.identifier = NSUserInterfaceItemIdentifier(Self.showIdentifier(row.bundle))
            segments.setAccessibilityLabel(row.name)
            let more = NSButton(title: "", target: self, action: #selector(morePressed(_:)))
            more.image = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: "More".localized)
            more.isBordered = false
            more.imagePosition = .imageOnly
            more.contentTintColor = .secondaryLabelColor
            more.wantsLayer = true
            more.layer?.cornerRadius = 6
            more.layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor
            more.identifier = NSUserInterfaceItemIdentifier(Self.alwaysHideIdentifier(row.bundle))
            more.setAccessibilityLabel("More".localized + " " + row.name)
            more.translatesAutoresizingMaskIntoConstraints = false
            more.widthAnchor.constraint(equalToConstant: 22).isActive = true
            more.heightAnchor.constraint(equalToConstant: 22).isActive = true
            let menu = NSMenu()
            let item = NSMenuItem(title: "Always hide".localized, action: #selector(alwaysHidePicked(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = row.bundle
            menu.addItem(item)
            more.menu = menu
            let controls = NSStackView(views: [segments, more])
            controls.spacing = 6
            return controls
        case .kept:
            let pill = NSTextField(labelWithString: "\u{25CF} " + "Kept".localized)
            pill.font = .systemFont(ofSize: 11, weight: .medium)
            pill.textColor = .systemGreen
            return pill
        case .notice:
            let ok = NSButton(title: "OK".localized, target: self, action: #selector(okPressed(_:)))
            ok.bezelStyle = .rounded
            ok.controlSize = .small
            ok.identifier = NSUserInterfaceItemIdentifier(Self.okIdentifier(row.bundle))
            return ok
        }
    }

    private func footerView() -> NSView {
        let footer = NSStackView()
        footer.orientation = .horizontal
        footer.alignment = .centerY
        footer.edgeInsets = NSEdgeInsets(top: 8, left: 4, bottom: 0, right: 4)
        func label(_ text: String, width: CGFloat) -> NSTextField {
            let field = NSTextField(wrappingLabelWithString: text)
            field.font = .systemFont(ofSize: 11)
            field.textColor = .secondaryLabelColor
            field.preferredMaxLayoutWidth = width
            field.translatesAutoresizingMaskIntoConstraints = false
            field.widthAnchor.constraint(equalToConstant: width).isActive = true
            return field
        }
        func button(_ title: String, _ identifier: String, _ action: Selector) -> NSButton {
            let button = NSButton(title: title, target: self, action: action)
            button.bezelStyle = .rounded
            button.controlSize = .small
            button.identifier = NSUserInterfaceItemIdentifier(identifier)
            return button
        }
        switch model.footer {
        case .hint:
            footer.addArrangedSubview(label("Not sure? It stays shown until you choose.".localized, width: innerWidth - 8 - 80))
            let settings = NSButton(title: "Settings\u{2026}".localized, target: self, action: #selector(settingsPressed))
            settings.isBordered = false
            settings.controlSize = .small
            settings.attributedTitle = NSAttributedString(string: "Settings\u{2026}".localized, attributes: [
                .font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.linkColor,
            ])
            settings.identifier = NSUserInterfaceItemIdentifier(Self.settingsIdentifier)
            footer.addArrangedSubview(settings)
        case .bulk(let more):
            footer.addArrangedSubview(label(String(format: "and %d more".localized, more), width: innerWidth - 8 - 160))
            let buttons = NSStackView(views: [button("Hide All".localized, Self.hideAllIdentifier, #selector(hideAllPressed)),
                                              button("Show All".localized, Self.showAllIdentifier, #selector(showAllPressed))])
            buttons.spacing = 6
            footer.addArrangedSubview(buttons)
        case .text(let text):
            footer.addArrangedSubview(label(text, width: innerWidth - 8))
        case .none:
            break
        }
        return footer
    }

    @objc private func segmentPressed(_ sender: NSSegmentedControl) {
        guard let raw = sender.identifier?.rawValue else { return }
        let bundle = String(raw.dropFirst(Self.showIdentifier("").count))
        let answer: ArrivalAnswer = sender.selectedSegment == 0 ? .show : .hide
        // Neither side stays pressed: the row is about to go.
        sender.selectedSegment = -1
        onAnswer(bundle, answer)
    }

    @objc private func morePressed(_ sender: NSButton) {
        guard let menu = sender.menu else { return }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 2), in: sender)
    }

    @objc private func alwaysHidePicked(_ sender: NSMenuItem) {
        guard let bundle = sender.representedObject as? String else { return }
        onAnswer(bundle, .alwaysHide)
    }

    @objc private func okPressed(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue else { return }
        onDismiss(String(raw.dropFirst(Self.okIdentifier("").count)))
    }

    @objc private func hideAllPressed() { onAnswerAll(.hide) }
    @objc private func showAllPressed() { onAnswerAll(.show) }
    @objc private func settingsPressed() { onOpenSettings() }
}
#endif
