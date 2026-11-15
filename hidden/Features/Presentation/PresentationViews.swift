//
//  PresentationViews.swift
//  Hidden Bar
//
//  Copyright © 2026 Dwarves Foundation. All rights reserved.
//

import AppKit

// The capsule in the menu bar, the panel that opens from it, and the note that
// shows when the arrow is clicked while presenting. Pure views over a model, so
// the offscreen snapshots draw the same code the app runs.

struct PresentationAppChip {
    let name: String
    let icon: NSImage?
}

struct PresentationPanelModel {
    enum Kind {
        case presenting
        case paused
        case couldNotHide
    }

    var kind: Kind
    var cause: PresentationCause?
    // Counts only: the panel is on the shared screen, so it never names an app.
    // Sensitive apps are named only in Settings.
    var hiddenCount = 0
    var sensitiveCount = 0
}

// MARK: - Capsule

enum PresentationCapsule {
    static let height: CGFloat = 18

    static func title(for phase: PresentationPhase) -> String {
        switch phase {
        case .off, .presenting: return "Presenting".localized
        case .paused: return "Paused".localized
        case .couldNotHide: return "Couldn't hide".localized
        }
    }

    // Drawn in the appearance the menu bar uses at the time, so it follows
    // light and dark without a second image.
    static func image(for phase: PresentationPhase) -> NSImage {
        let title = title(for: phase)
        let font = NSFont.systemFont(ofSize: 12, weight: .medium)
        let textSize = (title as NSString).size(withAttributes: [.font: font])
        let symbol: String? = {
            switch phase {
            case .off, .presenting: return "rectangle.on.rectangle"
            case .paused: return nil
            case .couldNotHide: return "exclamationmark.triangle.fill"
            }
        }()
        let iconWidth: CGFloat = symbol == nil ? 0 : 20
        let size = NSSize(width: ceil(textSize.width) + iconWidth + 18, height: height)
        let image = NSImage(size: size, flipped: false) { rect in
            let fill: NSColor
            let ink: NSColor
            switch phase {
            case .off, .presenting: fill = .systemBlue; ink = .white
            case .paused: fill = NSColor.labelColor.withAlphaComponent(0.2); ink = .labelColor
            case .couldNotHide: fill = .systemOrange; ink = .white
            }
            fill.setFill()
            NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2).fill()
            var x: CGFloat = 9
            if let symbol, let glyph = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)) {
                let tinted = glyph.tinted(ink)
                let glyphSize = tinted.size
                tinted.draw(in: NSRect(x: x, y: (rect.height - glyphSize.height) / 2, width: glyphSize.width, height: glyphSize.height))
                x += iconWidth
            }
            (title as NSString).draw(at: NSPoint(x: x, y: (rect.height - textSize.height) / 2),
                                     withAttributes: [.font: font, .foregroundColor: ink])
            return true
        }
        image.isTemplate = false
        return image
    }
}

// MARK: - Chips

// One app: its icon and name on a soft pill, drawn by hand so its size is exact.
final class PresentationChipView: NSView {
    private let text: String
    private let icon: NSImage?
    private static let font = NSFont.systemFont(ofSize: 12)
    static let height: CGFloat = 22

    init(name: String, icon: NSImage?) {
        self.text = name
        self.icon = icon
        let textWidth = ceil((name as NSString).size(withAttributes: [.font: Self.font]).width)
        let iconWidth: CGFloat = icon == nil ? 0 : 18
        super.init(frame: NSRect(x: 0, y: 0, width: textWidth + iconWidth + 18, height: Self.height))
        setAccessibilityLabel(name)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.labelColor.withAlphaComponent(0.08).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2).fill()
        var x: CGFloat = 8
        if let icon {
            icon.draw(in: NSRect(x: x, y: (bounds.height - 14) / 2, width: 14, height: 14), from: .zero, operation: .sourceOver,
                      fraction: 1, respectFlipped: true, hints: nil)
            x += 18
        }
        let size = (text as NSString).size(withAttributes: [.font: Self.font])
        (text as NSString).draw(at: NSPoint(x: x, y: (bounds.height - size.height) / 2),
                                withAttributes: [.font: Self.font, .foregroundColor: NSColor.labelColor])
    }
}

// Chips on rows that wrap at a fixed width.
final class PresentationChipFlow: NSView {
    override var isFlipped: Bool { true }

    init(chips: [PresentationAppChip], overflow: Int, width: CGFloat) {
        super.init(frame: .zero)
        var views = chips.map { PresentationChipView(name: $0.name, icon: $0.icon) }
        if overflow > 0 {
            views.append(PresentationChipView(name: String(format: "+%d more".localized, overflow), icon: nil))
        }
        let gap: CGFloat = 6
        var x: CGFloat = 0
        var y: CGFloat = 0
        for view in views {
            if x > 0, x + view.frame.width > width {
                x = 0
                y += PresentationChipView.height + gap
            }
            view.frame.origin = NSPoint(x: x, y: y)
            addSubview(view)
            x += view.frame.width + gap
        }
        let height = views.isEmpty ? 0 : y + PresentationChipView.height
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: width).isActive = true
        heightAnchor.constraint(equalToConstant: height).isActive = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

// MARK: - Buttons

// A flat button that draws itself, so it looks the same in a popover and in an
// offscreen snapshot, where no window is key to tint a default button.
final class PresentationButton: NSButton {
    enum Style { case prominent, plain }
    private let style: Style

    init(title: String, style: Style, target: AnyObject?, action: Selector?) {
        self.style = style
        super.init(frame: .zero)
        self.title = title
        self.target = target
        self.action = action
        isBordered = false
        setButtonType(.momentaryChange)
        font = .systemFont(ofSize: 12)
        translatesAutoresizingMaskIntoConstraints = false
        let width = ceil((title as NSString).size(withAttributes: [.font: font as Any]).width) + 20
        widthAnchor.constraint(equalToConstant: max(width, 44)).isActive = true
        heightAnchor.constraint(equalToConstant: 22).isActive = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
        let ink: NSColor
        switch style {
        case .prominent:
            NSColor.controlAccentColor.setFill()
            path.fill()
            ink = .white
        case .plain:
            NSColor.labelColor.withAlphaComponent(0.05).setFill()
            path.fill()
            NSColor.labelColor.withAlphaComponent(0.18).setStroke()
            path.lineWidth = 1
            path.stroke()
            ink = .labelColor
        }
        let text = title as NSString
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: ink]
        let size = text.size(withAttributes: attributes)
        text.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2), withAttributes: attributes)
    }
}

// MARK: - Panel

final class PresentationPanelView: NSView {
    static let width: CGFloat = 384
    private static let inset: CGFloat = 12

    var onStop: (() -> Void)?
    /// "Hide again" on the paused panel: hide now, with the camera or microphone still on.
    var onHideAgain: (() -> Void)?
    let model: PresentationPanelModel

    init(model: PresentationPanelModel) {
        self.model = model
        super.init(frame: .zero)
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: Self.inset, left: Self.inset, bottom: Self.inset, right: Self.inset)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            widthAnchor.constraint(equalToConstant: Self.width),
        ])
        switch model.kind {
        case .presenting: buildPresenting(in: stack)
        case .paused: buildPaused(in: stack)
        case .couldNotHide: buildCouldNotHide(in: stack)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private var contentWidth: CGFloat { Self.width - 2 * Self.inset }

    private func heading(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        return label
    }

    private func body(_ text: String, size: CGFloat = 11) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: size)
        label.textColor = .secondaryLabelColor
        label.isSelectable = false
        label.preferredMaxLayoutWidth = contentWidth
        return label
    }

    private func line() -> NSView {
        let view = SettingsHairline()
        view.widthAnchor.constraint(equalToConstant: contentWidth).isActive = true
        return view
    }

    private func footer(note: String, button: NSButton) -> NSView {
        let label = NSTextField(labelWithString: note)
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let row = NSStackView(views: [label, spacer, button])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.translatesAutoresizingMaskIntoConstraints = false
        row.widthAnchor.constraint(equalToConstant: contentWidth).isActive = true
        return row
    }

    private func buildPresenting(in stack: NSStackView) {
        stack.addArrangedSubview(heading("Presentation mode is on".localized))
        stack.addArrangedSubview(body(Self.causeText(model.cause)))
        stack.setCustomSpacing(10, after: stack.arrangedSubviews.last!)
        let count = model.hiddenCount
        let hiddenTitle = count == 1 ? "Hidden now: 1 app".localized : String(format: "Hidden now: %d apps".localized, count)
        stack.addArrangedSubview(body(hiddenTitle))
        if model.sensitiveCount > 0 {
            stack.setCustomSpacing(6, after: stack.arrangedSubviews.last!)
            let lock = NSImageView(image: NSImage(systemSymbolName: "lock", accessibilityDescription: nil) ?? NSImage())
            lock.contentTintColor = .secondaryLabelColor
            lock.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 10, weight: .regular)
            let text = model.sensitiveCount == 1
                ? "1 sensitive app stays hidden even if you click the arrow".localized
                : String(format: "%d sensitive apps stay hidden even if you click the arrow".localized, model.sensitiveCount)
            let title = NSStackView(views: [lock, body(text)])
            title.spacing = 4
            stack.addArrangedSubview(title)
        }
        stack.setCustomSpacing(10, after: stack.arrangedSubviews.last!)
        stack.addArrangedSubview(line())
        stack.setCustomSpacing(8, after: stack.arrangedSubviews.last!)
        let stop = PresentationButton(title: "Stop Presenting".localized, style: .prominent, target: self, action: #selector(stopPressed))
        stop.identifier = NSUserInterfaceItemIdentifier("presentationStop")
        stack.addArrangedSubview(footer(note: "macOS's own items stay.".localized, button: stop))
    }

    private func buildPaused(in stack: NSStackView) {
        stack.addArrangedSubview(heading("Hiding paused: camera or microphone in use".localized))
        stack.addArrangedSubview(body("Nothing is hidden right now, sensitive apps included. macOS 27 hides the capsule that names the app using your camera or microphone along with other icons, so Hidden Bar shows every icon when one turns on.".localized))
        stack.setCustomSpacing(10, after: stack.arrangedSubviews.last!)
        stack.addArrangedSubview(body("To keep apps out of a shared screen during a call:".localized))
        stack.setCustomSpacing(6, after: stack.arrangedSubviews.last!)
        stack.addArrangedSubview(tip(symbol: "rectangle.on.rectangle", title: "Share one window, not the whole screen".localized,
                                     detail: "The menu bar is not in the picture.".localized))
        stack.addArrangedSubview(tip(symbol: "lock", title: "Quit sensitive apps before the call".localized,
                                     detail: "Hidden Bar will not quit apps for you.".localized))
        stack.setCustomSpacing(10, after: stack.arrangedSubviews.last!)
        stack.addArrangedSubview(line())
        stack.setCustomSpacing(8, after: stack.arrangedSubviews.last!)
        let again = PresentationButton(title: "Hide again".localized, style: .prominent, target: self, action: #selector(hideAgainPressed))
        again.identifier = NSUserInterfaceItemIdentifier("presentationHideAgain")
        stack.addArrangedSubview(footer(note: "Resumes on its own.".localized, button: again))
    }

    private func buildCouldNotHide(in stack: NSStackView) {
        stack.addArrangedSubview(heading("Hidden Bar could not hide your icons".localized))
        stack.addArrangedSubview(body("macOS did not accept the request, so every icon is showing. Stop presentation mode and start it again, or quit the sensitive apps first.".localized))
        stack.setCustomSpacing(10, after: stack.arrangedSubviews.last!)
        stack.addArrangedSubview(line())
        stack.setCustomSpacing(8, after: stack.arrangedSubviews.last!)
        let stop = PresentationButton(title: "Stop Presenting".localized, style: .prominent, target: self, action: #selector(stopPressed))
        stop.identifier = NSUserInterfaceItemIdentifier("presentationStop")
        stack.addArrangedSubview(footer(note: "", button: stop))
    }

    private func tip(symbol: String, title: String, detail: String) -> NSView {
        let badge = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil) ?? NSImage())
        badge.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
        badge.contentTintColor = .white
        badge.translatesAutoresizingMaskIntoConstraints = false
        let tile = TipTile()
        tile.translatesAutoresizingMaskIntoConstraints = false
        tile.addSubview(badge)
        NSLayoutConstraint.activate([
            tile.widthAnchor.constraint(equalToConstant: 28),
            tile.heightAnchor.constraint(equalToConstant: 28),
            badge.centerXAnchor.constraint(equalTo: tile.centerXAnchor),
            badge.centerYAnchor.constraint(equalTo: tile.centerYAnchor),
        ])
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 12)
        let detailLabel = NSTextField(labelWithString: detail)
        detailLabel.font = .systemFont(ofSize: 11)
        detailLabel.textColor = .secondaryLabelColor
        let texts = NSStackView(views: [titleLabel, detailLabel])
        texts.orientation = .vertical
        texts.alignment = .leading
        texts.spacing = 1
        let row = NSStackView(views: [tile, texts])
        row.spacing = 10
        row.alignment = .centerY
        return row
    }

    static func causeText(_ cause: PresentationCause?) -> String {
        switch cause {
        case .mirroring(let name?):
            return String(format: "Started because \"%@\" is mirrored. Ends when mirroring stops.".localized, name)
        case .mirroring(nil):
            return "Started because a display is mirrored. Ends when mirroring stops.".localized
        case .manual, nil:
            return "Started by you. It stays on until you stop it.".localized
        }
    }

    @objc private func stopPressed() { onStop?() }
    @objc private func hideAgainPressed() { onHideAgain?() }
}

private final class TipTile: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.secondaryLabelColor.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 7, yRadius: 7).fill()
    }
}

// MARK: - Note on the arrow click

// "2 apps stay hidden": shown for a moment under the arrow when it is clicked
// while presenting. It gives a count and no names, since the room sees it.
final class PresentationNoteView: NSView {
    init(count: Int) {
        super.init(frame: .zero)
        let lock = NSImageView(image: NSImage(systemSymbolName: "lock", accessibilityDescription: nil) ?? NSImage())
        lock.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 11, weight: .regular)
        lock.contentTintColor = .labelColor
        let label = NSTextField(labelWithString: Self.text(count: count))
        label.font = .systemFont(ofSize: 12, weight: .medium)
        let row = NSStackView(views: [lock, label])
        row.spacing = 6
        row.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: topAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    static func text(count: Int) -> String {
        return count == 1 ? "1 app stays hidden".localized : String(format: "%d apps stay hidden".localized, count)
    }
}
