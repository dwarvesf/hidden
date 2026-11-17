//
//  SettingsViews.swift
//  Hidden Bar
//
//  Copyright © 2026 Console Labs. All rights reserved.
//

import AppKit

// The two drawn pieces of General: the status card and the menu bar preview.

/// One line of state at the top of General, with at most one button.
final class StatusCardView: NSView {
    private let badge = StatusBadgeView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let captionLabel = SettingsForm.caption("")
    private let button = NSButton(title: "", target: nil, action: nil)
    private(set) var status: SettingsStatus = .working
    var onAction: ((SettingsStatus) -> Void)?

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        titleLabel.lineBreakMode = .byWordWrapping
        titleLabel.maximumNumberOfLines = 2
        button.bezelStyle = .rounded
        button.bezelColor = .controlAccentColor
        button.target = self
        button.action = #selector(buttonPressed)
        button.identifier = NSUserInterfaceItemIdentifier("statusCardButton")
        let texts = NSStackView(views: [titleLabel, captionLabel])
        texts.orientation = .vertical
        texts.alignment = .leading
        texts.spacing = 2
        for view in [badge, texts, button] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        texts.setContentHuggingPriority(.defaultLow, for: .horizontal)
        texts.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        NSLayoutConstraint.activate([
            badge.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            badge.centerYAnchor.constraint(equalTo: centerYAnchor),
            badge.widthAnchor.constraint(equalToConstant: 28),
            badge.heightAnchor.constraint(equalToConstant: 28),
            texts.leadingAnchor.constraint(equalTo: badge.trailingAnchor, constant: 14),
            texts.topAnchor.constraint(equalTo: topAnchor, constant: 11),
            texts.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -11),
            button.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            button.centerYAnchor.constraint(equalTo: centerYAnchor),
            button.leadingAnchor.constraint(greaterThanOrEqualTo: texts.trailingAnchor, constant: 16),
            texts.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -14),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 54),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    var title: String { titleLabel.stringValue }
    var buttonTitle: String? { button.isHidden ? nil : button.title }

    func configure(_ status: SettingsStatus, shortcut: String?, runningFolder: String?) {
        self.status = status
        badge.status = status
        let buttonKey: String?
        switch status {
        case .working:
            titleLabel.stringValue = "Hidden Bar is working".localized
            captionLabel.stringValue = shortcut.map { String(format: "Click the arrow in the menu bar, or press %@, to show hidden icons.".localized, $0) }
                ?? "Click the arrow in the menu bar to show hidden icons.".localized
            buttonKey = nil
        case .needsAccessibility:
            titleLabel.stringValue = "Hidden Bar needs Accessibility access".localized
            captionLabel.stringValue = "macOS 27 lets Hidden Bar hide icons only with this permission. Nothing is hidden until you turn it on.".localized
            buttonKey = "Open System Settings"
        case .outsideApplications:
            titleLabel.stringValue = "Move Hidden Bar to Applications".localized
            captionLabel.stringValue = String(format: "It is running from %@. macOS 27 hides icons only for apps in the Applications folder, so nothing is hidden yet.".localized,
                                              runningFolder ?? "Downloads")
            buttonKey = "Move to Applications"
        case .appStoreOnMacOS27:
            titleLabel.stringValue = "This App Store version can't hide icons on macOS 27".localized
            captionLabel.stringValue = "Apple's sandbox blocks hiding on macOS 27. Your settings below are kept.".localized
            buttonKey = "Learn More…"
        }
        button.isHidden = buttonKey == nil
        button.title = buttonKey?.localized ?? ""
        needsDisplay = true
    }

    @objc private func buttonPressed() {
        onAction?(status)
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 10, yRadius: 10)
        SettingsColors.groupFill.setFill()
        path.fill()
        (status.isWarning ? NSColor.systemOrange.withAlphaComponent(0.6) : SettingsColors.groupStroke).setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}

private final class StatusBadgeView: NSView {
    var status: SettingsStatus = .working { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        (status.isWarning ? NSColor.systemOrange : NSColor.systemGreen).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 7, yRadius: 7).fill()
        let symbol: String
        switch status {
        case .working: symbol = "checkmark"
        case .needsAccessibility: symbol = "exclamationmark"
        case .outsideApplications: symbol = "folder"
        case .appStoreOnMacOS27: symbol = "bag"
        }
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .bold)
        guard let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(config) else { return }
        let tinted = image.tinted(.white)
        let size = tinted.size
        tinted.draw(in: NSRect(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2,
                               width: size.width, height: size.height))
    }
}

/// A drawn menu bar with brackets naming each zone. The edge between hidden and
/// shown icons is the arrow on the native engine and the "|" separator on the
/// separator engine; with the always-hidden section on, the translucent bar too.
final class MenuBarPreviewView: NSView {
    var boundary: PreviewBoundary = .separator { didSet { needsDisplay = true; invalidateIntrinsicContentSize() } }
    var showsAlwaysHidden = false { didSet { needsDisplay = true; invalidateIntrinsicContentSize() } }

    private enum Item {
        case symbol(String, dimmed: Bool)
        case translucentBar
        case separator
        case arrow
        case clock
    }

    private struct Zone {
        let titleKey: String
        let range: ClosedRange<Int>
        let isEdge: Bool
    }

    override var isFlipped: Bool { true }
    // Labels that would collide take a second line: the separator sits next to
    // the arrow, and the always-hidden section adds the translucent bar.
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: showsAlwaysHidden || boundary == .separator ? 72 : 56)
    }

    static let clockText: String = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEE jmm")
        return formatter.string(from: Date())
    }()

    private func layout() -> ([Item], [Zone]) {
        var items: [Item] = []
        var zones: [Zone] = []
        func add(_ new: [Item], zone key: String?, edge: Bool = false) {
            let start = items.count
            items += new
            if let key { zones.append(Zone(titleKey: key, range: start...(items.count - 1), isEdge: edge)) }
        }
        if showsAlwaysHidden {
            add([.symbol("cloud", dimmed: true), .symbol("music.note", dimmed: true)], zone: "Always hidden")
            add([.translucentBar], zone: "Translucent bar", edge: true)
        }
        add([.symbol("drop", dimmed: false), .symbol("cylinder", dimmed: false), .symbol("gamecontroller", dimmed: false)], zone: "Hidden")
        switch boundary {
        case .arrow:
            add([.arrow], zone: "Arrow", edge: true)
        case .separator:
            add([.separator], zone: "Separator", edge: true)
            add([.arrow], zone: "Arrow")
        }
        add([.symbol("battery.75percent", dimmed: false), .symbol("wifi", dimmed: false),
             .symbol("magnifyingglass", dimmed: false), .symbol("switch.2", dimmed: false)], zone: "Always shown")
        add([.clock], zone: nil)
        return (items, zones)
    }

    private func width(of item: Item) -> CGFloat {
        if case .clock = item {
            return (Self.clockText as NSString).size(withAttributes: [.font: NSFont.menuBarFont(ofSize: 13)]).width + 4
        }
        return 22
    }

    override func draw(_ dirtyRect: NSRect) {
        let (items, zones) = layout()
        let barRect = NSRect(x: 0, y: 0, width: bounds.width, height: 26)
        SettingsColors.menuBarFill.setFill()
        NSBezierPath(roundedRect: barRect, xRadius: 6, yRadius: 6).fill()

        // Wider gaps where one zone ends and the next starts, so each bracket
        // and its label have room.
        let zoneStarts = Set(zones.map(\.range.lowerBound))
        let widths = items.map(width(of:))
        let gaps = items.indices.dropFirst().map { zoneStarts.contains($0) ? CGFloat(12) : 5 }
        let total = widths.reduce(0, +) + gaps.reduce(0, +)
        var x = (bounds.width - total) / 2
        var frames: [NSRect] = []
        for (index, item) in items.enumerated() {
            if index > 0 { x += gaps[index - 1] }
            let frame = NSRect(x: x, y: 2, width: widths[index], height: 22)
            frames.append(frame)
            draw(item, in: frame, highlighted: zones.contains { $0.isEdge && $0.range.contains(index) })
            x += widths[index]
        }

        var placed: [NSRect] = []
        for zone in zones {
            let first = frames[zone.range.lowerBound], last = frames[zone.range.upperBound]
            let midX = (first.minX + last.maxX) / 2
            let color: NSColor = zone.isEdge ? .controlAccentColor : .tertiaryLabelColor
            color.setFill()
            if zone.isEdge {
                NSRect(x: midX - 0.75, y: 30, width: 1.5, height: 7).fill()
            } else {
                let left = first.minX + 1, right = last.maxX - 1
                NSRect(x: left, y: 36, width: right - left, height: 1).fill()
                NSRect(x: left, y: 30, width: 1, height: 7).fill()
                NSRect(x: right - 1, y: 30, width: 1, height: 7).fill()
            }
            let font = zone.isEdge ? NSFont.systemFont(ofSize: 11, weight: .semibold) : NSFont.systemFont(ofSize: 11)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font, .foregroundColor: zone.isEdge ? NSColor.controlAccentColor : NSColor.secondaryLabelColor,
            ]
            let text = zone.titleKey.localized as NSString
            let size = text.size(withAttributes: attributes)
            // A label that would touch its neighbour drops to a second line.
            var rect = NSRect(x: midX - size.width / 2, y: 40, width: size.width, height: size.height)
            if placed.contains(where: { $0.insetBy(dx: -4, dy: 0).intersects(rect) }) {
                rect.origin.y += size.height + 1
                NSRect(x: midX - 0.5, y: 40, width: 1, height: rect.minY - 40).fill()
            }
            placed.append(rect)
            text.draw(at: rect.origin, withAttributes: attributes)
        }
    }

    private func draw(_ item: Item, in frame: NSRect, highlighted: Bool) {
        if highlighted {
            NSColor.controlAccentColor.setStroke()
            let ring = NSBezierPath(roundedRect: frame.insetBy(dx: 0.75, dy: 0.75), xRadius: 5, yRadius: 5)
            ring.lineWidth = 1.5
            ring.stroke()
        }
        switch item {
        case .symbol(let name, let dimmed):
            drawSymbol(name, in: frame, color: dimmed ? NSColor.labelColor.withAlphaComponent(0.35) : .labelColor)
        case .arrow:
            drawSymbol("chevron.right", in: frame, color: .labelColor)
        case .translucentBar:
            NSColor.labelColor.withAlphaComponent(0.3).setFill()
            NSBezierPath(roundedRect: NSRect(x: frame.midX - 2.5, y: frame.midY - 7, width: 5, height: 14), xRadius: 2, yRadius: 2).fill()
        case .separator:
            NSColor.labelColor.setFill()
            NSBezierPath(roundedRect: NSRect(x: frame.midX - 1, y: frame.midY - 7, width: 2, height: 14), xRadius: 1, yRadius: 1).fill()
        case .clock:
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.menuBarFont(ofSize: 13), .foregroundColor: NSColor.labelColor]
            let size = (Self.clockText as NSString).size(withAttributes: attributes)
            (Self.clockText as NSString).draw(at: NSPoint(x: frame.minX + 2, y: frame.midY - size.height / 2), withAttributes: attributes)
        }
    }

    private func drawSymbol(_ name: String, in frame: NSRect, color: NSColor) {
        let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config) else { return }
        let tinted = image.tinted(color)
        let size = tinted.size
        tinted.draw(in: NSRect(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2, width: size.width, height: size.height),
                    from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }
}

extension NSImage {
    /// A copy filled with `color`, resolved when drawn so it follows the appearance.
    func tinted(_ color: NSColor) -> NSImage {
        let source = self
        let image = NSImage(size: size, flipped: false) { rect in
            source.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        return image
    }
}
