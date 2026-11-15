//
//  PresentationSnapshot.swift
//  Hidden Bar
//
//  Copyright © 2026 Dwarves Foundation. All rights reserved.
//

#if DEBUG && HIDDENBAR_NATIVE_VISIBILITY
import AppKit

/// Debug builds only. The presentation surfaces drawn offscreen from fixture
/// data, one PNG per state on the design boards: the capsule with its panel, the
/// paused explanation, the arrow-click note, and the could-not-hide state.
/// Fixtures only: no live Accessibility read, no preference written.
enum PresentationSnapshot {
    static func render(to dir: URL, appearance: NSAppearance.Name, mode: String) {
        let barRight: [(PresentationPhase, String)] = [(.presenting, "pill"), (.paused, "paused"), (.couldNotHide, "failed")]
        for (phase, name) in barRight {
            let model = fixtureModel(for: phase)
            shoot(size: NSSize(width: 760, height: 380), appearance: appearance,
                  to: dir.appendingPathComponent("direct-present-\(name)-\(mode).png")) { scene in
                _ = addMenuBar(to: scene, phase: phase, showsHiddenIcons: phase == .paused)
                let panel = PresentationPanelView(model: model)
                let size = panel.fittingSize
                panel.frame = NSRect(origin: .zero, size: size)
                let chrome = PanelChrome(content: panel)
                chrome.frame.origin = NSPoint(x: scene.bounds.width - 16 - chrome.frame.width, y: 34)
                scene.addSubview(chrome)
            }
        }
        shoot(size: NSSize(width: 760, height: 150), appearance: appearance,
              to: dir.appendingPathComponent("direct-present-click-\(mode).png")) { scene in
            let strip = addMenuBar(to: scene, phase: nil, showsHiddenIcons: true)
            let note = PresentationNoteView(count: 3)
            note.frame = NSRect(origin: .zero, size: note.fittingSize)
            let chrome = PanelChrome(content: note, radius: note.frame.height / 2)
            chrome.frame.origin = NSPoint(x: strip.arrowFrame.midX - chrome.frame.width / 2, y: 38)
            scene.addSubview(chrome)
        }
    }

    // MARK: Fixtures

    static func fixtureModel(for phase: PresentationPhase) -> PresentationPanelModel {
        let kind: PresentationPanelModel.Kind = phase == .paused ? .paused : (phase == .couldNotHide ? .couldNotHide : .presenting)
        return PresentationPanelModel(kind: kind, cause: .mirroring(displayName: "Meeting Room TV"), hiddenCount: 11, sensitiveCount: 3)
    }

    // Settings is where sensitive apps are named.
    static var sensitiveChipsFixture: [PresentationAppChip] {
        let named: [(String, String, NSColor)] = [
            ("Slack", "number", .systemPurple), ("1Password", "key.fill", .systemBlue), ("Tailscale", "circle.grid.3x3.fill", .darkGray),
            ("Dropbox", "shippingbox.fill", .systemBlue), ("Docker Desktop", "shippingbox", .systemTeal), ("Paste", "doc.on.clipboard", .systemIndigo),
        ]
        return named.prefix(3).map { PresentationAppChip(name: $0.0, icon: icon($0.1, $0.2)) }
    }

    // Stand-ins for the apps' own icons.
    static func icon(_ symbol: String, _ color: NSColor) -> NSImage {
        let image = NSImage(size: NSSize(width: 14, height: 14), flipped: false) { rect in
            color.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 3.5, yRadius: 3.5).fill()
            if let glyph = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 8, weight: .bold)) {
                let tinted = glyph.tinted(.white)
                tinted.draw(in: NSRect(x: (rect.width - tinted.size.width) / 2, y: (rect.height - tinted.size.height) / 2,
                                       width: tinted.size.width, height: tinted.size.height))
            }
            return true
        }
        return image
    }

    // MARK: Drawing

    private struct Strip {
        var capsuleFrame: NSRect
        var arrowFrame: NSRect
    }

    private static func shoot(size: NSSize, appearance: NSAppearance.Name, to url: URL, build: (TopLeftPaneContent) -> Void) {
        let scene = ScenePlate(frame: NSRect(origin: .zero, size: size))
        scene.appearance = NSAppearance(named: appearance)
        build(scene)
        scene.layoutSubtreeIfNeeded()
        guard let rep = scene.bitmapImageRepForCachingDisplay(in: scene.bounds) else { return }
        scene.cacheDisplay(in: scene.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
        NSLog("SettingsSnapshot: %@ %.0fx%.0f", url.lastPathComponent, size.width, size.height)
    }

    // The menu bar across the top: app menus on the left; on the right the
    // capsule (or the arrow, for the click note) and the clock.
    private static func addMenuBar(to scene: TopLeftPaneContent, phase: PresentationPhase?, showsHiddenIcons: Bool) -> Strip {
        let bar = NSView(frame: NSRect(x: 0, y: 0, width: scene.bounds.width, height: 28))
        let backdrop = BarBackdrop(frame: bar.bounds)
        bar.addSubview(backdrop)
        var x: CGFloat = 16
        for (index, title) in ["", "Keynote", "File", "Edit", "Play"].enumerated() {
            let label = NSTextField(labelWithString: title)
            label.font = index == 1 ? .boldSystemFont(ofSize: 13) : .systemFont(ofSize: 13)
            label.textColor = .labelColor
            label.sizeToFit()
            label.frame.origin = NSPoint(x: x, y: (28 - label.frame.height) / 2)
            bar.addSubview(label)
            x += label.frame.width + 14
        }
        var right = scene.bounds.width - 16
        let clock = NSTextField(labelWithString: "Mon 16 Nov 9:41")
        clock.font = .systemFont(ofSize: 13)
        clock.sizeToFit()
        right -= clock.frame.width
        clock.frame.origin = NSPoint(x: right, y: (28 - clock.frame.height) / 2)
        bar.addSubview(clock)
        right -= 12
        func place(_ view: NSView, gap: CGFloat = 12) -> NSRect {
            right -= view.frame.width
            view.frame.origin = NSPoint(x: right, y: (28 - view.frame.height) / 2)
            bar.addSubview(view)
            right -= gap
            return view.frame
        }
        func glyph(_ symbol: String) -> NSImageView {
            let view = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil) ?? NSImage())
            view.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
            view.contentTintColor = .labelColor
            view.frame.size = NSSize(width: 18, height: 18)
            return view
        }
        _ = place(glyph("battery.100"))
        var capsuleFrame = NSRect.zero
        var arrowFrame = NSRect.zero
        if let phase {
            if phase == .paused {
                let camera = NSImageView(image: NSImage(systemSymbolName: "video.fill", accessibilityDescription: nil) ?? NSImage())
                camera.contentTintColor = .white
                camera.frame.size = NSSize(width: 30, height: 18)
                let dot = NSView(frame: camera.frame)
                dot.wantsLayer = true
                dot.layer?.backgroundColor = NSColor.systemGreen.cgColor
                dot.layer?.cornerRadius = 9
                dot.addSubview(camera)
                camera.frame.origin = .zero
                _ = place(dot)
            }
            if showsHiddenIcons {
                _ = place(glyph("chevron.right"))
                for symbol in ["chart.bar.fill", "square.stack.3d.up", "circle.grid.3x3.fill", "key.fill", "number"] {
                    _ = place(glyph(symbol), gap: 12)
                }
            }
            let image = PresentationCapsule.image(for: phase)
            let view = NSImageView(image: image)
            view.frame.size = image.size
            capsuleFrame = place(view)
        } else {
            for symbol in ["square.stack.3d.up", "tray.full", "doc.on.clipboard"].reversed() { _ = place(glyph(symbol)) }
            arrowFrame = place(glyph("chevron.right"))
        }
        scene.addSubview(bar)
        return Strip(capsuleFrame: capsuleFrame, arrowFrame: arrowFrame)
    }
}

/// The slide behind the menu bar: a flat card on a soft ground.
private final class ScenePlate: TopLeftPaneContent {
    override func draw(_ dirtyRect: NSRect) {
        (effectiveAppearance.isDark ? NSColor(white: 0.14, alpha: 1) : NSColor(red: 0.93, green: 0.92, blue: 0.95, alpha: 1)).setFill()
        bounds.fill()
        let card = NSRect(x: 40, y: 60, width: 300, height: min(bounds.height - 90, 230))
        NSColor(red: 0.14, green: 0.27, blue: 0.45, alpha: 1).setFill()
        NSBezierPath(roundedRect: card, xRadius: 8, yRadius: 8).fill()
        let title = NSAttributedString(string: "Q4 roadmap", attributes: [.font: NSFont.boldSystemFont(ofSize: 22), .foregroundColor: NSColor.white])
        title.draw(at: NSPoint(x: card.midX - title.size().width / 2, y: card.midY - 14))
    }
}

private final class BarBackdrop: NSView {
    override func draw(_ dirtyRect: NSRect) {
        SettingsColors.menuBarFill.setFill()
        bounds.fill()
    }
}

/// Popover chrome for a snapshot: a rounded card with a hairline.
private final class PanelChrome: NSView {
    private let radius: CGFloat

    init(content: NSView, radius: CGFloat = 12) {
        self.radius = radius
        super.init(frame: NSRect(origin: .zero, size: content.frame.size))
        addSubview(content)
        content.frame.origin = .zero
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius)
        NSColor.windowBackgroundColor.setFill()
        path.fill()
        NSColor.separatorColor.setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}
#endif
