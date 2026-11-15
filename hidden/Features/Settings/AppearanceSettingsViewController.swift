//
//  AppearanceSettingsViewController.swift
//  Hidden Bar
//
//  Copyright © 2026 Dwarves Foundation. All rights reserved.
//

import AppKit

/// Arrow style as four tiles you pick by looking, plus the fade switch.
final class AppearanceSettingsViewController: SettingsPaneController {
    static let tileIdentifierPrefix = UserDefaults.Key.arrowStyle + "."

    private(set) var tiles: [ArrowStyleTile] = []

    override func buildForm() {
        tiles = ArrowStyle.allCases.map { style in
            let tile = ArrowStyleTile(style: style)
            tile.identifier = NSUserInterfaceItemIdentifier(Self.tileIdentifierPrefix + style.rawValue)
            tile.target = self
            tile.action = #selector(tilePicked(_:))
            return tile
        }
        let tileRow = NSStackView(views: tiles)
        tileRow.distribution = .fillEqually
        tileRow.spacing = 10
        tileRow.edgeInsets = NSEdgeInsets(top: 10, left: 10, bottom: 6, right: 10)
        tileRow.translatesAutoresizingMaskIntoConstraints = false

        let fade = boundSwitch(UserDefaults.Key.stealthExpandIconEnabled, read: { Preferences.stealthExpandIconEnabled },
                               write: { Preferences.stealthExpandIconEnabled = $0 })
        addSection("Arrow".localized, rows: [
            tileRow,
            SettingsForm.row("Fade the arrow when icons are hidden".localized,
                             caption: "The arrow turns almost invisible until you need it. It is still there to click.".localized,
                             control: fade),
        ])
        addFootnote("Each preview shows the arrow with icons hidden, then shown.".localized)
        onRefresh { [weak self] in
            self?.tiles.forEach { $0.isSelected = $0.style == Preferences.arrowStyle }
        }
        refreshAll()
    }

    @objc private func tilePicked(_ sender: ArrowStyleTile) {
        Preferences.arrowStyle = sender.style
        refreshAll()
    }
}

/// A button drawn as a small menu bar with the collapsed and expanded arrow.
final class ArrowStyleTile: NSButton {
    let style: ArrowStyle
    var isSelected = false { didSet { needsDisplay = true } }

    init(style: ArrowStyle) {
        self.style = style
        super.init(frame: .zero)
        title = style.localizedName
        isBordered = false
        setButtonType(.momentaryChange)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 68).isActive = true
        setAccessibilityLabel(style.localizedName)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var intrinsicContentSize: NSSize { NSSize(width: 120, height: 68) }

    override func draw(_ dirtyRect: NSRect) {
        let outer = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 8, yRadius: 8)
        (isSelected ? NSColor.controlAccentColor.withAlphaComponent(0.08) : SettingsColors.groupFill).setFill()
        outer.fill()
        if isSelected {
            NSColor.controlAccentColor.setStroke()
            outer.lineWidth = 2
        } else {
            SettingsColors.groupStroke.setStroke()
            outer.lineWidth = 1
        }
        outer.stroke()

        // Buttons are flipped: y grows downward.
        let bar = NSRect(x: 7, y: 7, width: bounds.width - 14, height: 24)
        SettingsColors.menuBarFill.setFill()
        NSBezierPath(roundedRect: bar, xRadius: 5, yRadius: 5).fill()
        let glyphs = [style.expandImage(), style.collapseImage()].compactMap { $0 }
        let cell: CGFloat = 18, gap: CGFloat = 12
        var x = bar.midX - (CGFloat(glyphs.count) * cell + CGFloat(glyphs.count - 1) * gap) / 2
        for glyph in glyphs {
            let size = glyph.size
            let scale = min(1, 16 / max(size.height, 1))
            let drawn = NSSize(width: size.width * scale, height: size.height * scale)
            glyph.tinted(.labelColor).draw(in: NSRect(x: x + (cell - drawn.width) / 2, y: bar.midY - drawn.height / 2,
                                                      width: drawn.width, height: drawn.height),
                                           from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            x += cell + gap
        }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: isSelected ? .medium : .regular),
            .foregroundColor: NSColor.labelColor,
        ]
        let text = style.localizedName as NSString
        let size = text.size(withAttributes: attributes)
        text.draw(at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.height - 10 - size.height), withAttributes: attributes)
    }
}
