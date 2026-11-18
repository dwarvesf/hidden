//
//  ArrivalsSnapshot.swift
//  Hidden Bar
//
//  Copyright © 2026 Console Labs. All rights reserved.
//

#if DEBUG && HIDDENBAR_NATIVE_VISIBILITY
import AppKit

/// Debug builds only: draws the arrivals prompt into PNGs for `-settingsSnapshotDir`,
/// from fixture apps (no Accessibility read, no live catalog), as a menu bar strip
/// with the arrow and the prompt under it, like the design boards.
enum ArrivalsSnapshot {
    struct Scene {
        let name: String
        let model: ArrivalsPromptModel?
        let dot: Bool
    }

    static func render(appearance: NSAppearance.Name, mode: String, to dir: URL) {
        for scene in scenes() {
            let view = ArrivalsSceneView(scene: scene, mode: mode)
            view.appearance = NSAppearance(named: appearance)
            view.layoutSubtreeIfNeeded()
            guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
            view.cacheDisplay(in: view.bounds, to: rep)
            let url = dir.appendingPathComponent("direct-arrivals-\(scene.name)-\(mode).png")
            try? rep.representation(using: .png, properties: [:])?.write(to: url)
            NSLog("ArrivalsSnapshot: %@ %.0fx%.0f", url.lastPathComponent, view.bounds.width, view.bounds.height)
        }
    }

    static func scenes() -> [Scene] {
        let now = Date()
        func info(_ bundle: String, _ name: String, symbol: String, color: NSColor, ago: TimeInterval = 5,
                  running: Bool = true, icons: Int = 1) -> ArrivalInfo {
            ArrivalInfo(bundle: bundle, name: name, icon: icon(symbol, color), firstSeen: now.addingTimeInterval(-ago),
                        isRunning: running, iconCount: icons)
        }
        let raycast = info("com.raycast.macos", "Raycast", symbol: "bolt.fill", color: NSColor(srgbRed: 0.90, green: 0.28, blue: 0.30, alpha: 1))
        let tailscale = info("io.tailscale.ipn.macos", "Tailscale", symbol: "network", color: NSColor(srgbRed: 0.18, green: 0.18, blue: 0.20, alpha: 1),
                             ago: 2 * 3600)
        let drive = info("com.google.drivefs", "Google Drive", symbol: "externaldrive.fill", color: NSColor(srgbRed: 0.12, green: 0.64, blue: 0.39, alpha: 1))
        let docker = info("com.docker.docker", "Docker Desktop", symbol: "shippingbox.fill", color: NSColor(srgbRed: 0.11, green: 0.39, blue: 0.93, alpha: 1),
                          icons: 2)
        let more = [
            info("com.example.one", "Bartender Helper", symbol: "ellipsis.circle.fill", color: .systemIndigo),
            info("com.example.two", "Clipboard Tool", symbol: "doc.on.clipboard.fill", color: .systemTeal),
            info("com.example.three", "Menu Weather", symbol: "cloud.sun.fill", color: .systemOrange),
        ]
        func model(_ infos: [ArrivalInfo]) -> ArrivalsPromptModel { ArrivalsPromptModel.make(infos: infos, now: now) }

        var known = model([])
        known.title = "No question for a known app"
        known.subtitle = nil
        known.rows = [ArrivalsPromptModel.Row(bundle: "com.tinyspeck.slackmacgap", name: "Slack",
                                              caption: "10:02 quit to update. 10:03 back in Hidden, where you put it.",
                                              icon: icon("number", NSColor(srgbRed: 0.29, green: 0.08, blue: 0.29, alpha: 1)), style: .kept)]
        known.footer = .text("Only apps Hidden Bar has never seen are asked about.")

        var system = model([])
        system.subtitle = nil
        system.rows = [ArrivalsPromptModel.Row(bundle: "com.apple.controlcenter", name: "Timer (Live Activity)",
                                               caption: "A macOS item. macOS decides when it shows; Hidden Bar can't keep it shown while hiding.",
                                               icon: icon("timer", NSColor.systemGray), style: .notice)]
        system.footer = .none

        return [
            Scene(name: "entry", model: nil, dot: true),
            Scene(name: "prompt", model: model([raycast, tailscale]), dot: true),
            Scene(name: "edge-multi-icon", model: model([docker]), dot: true),
            Scene(name: "edge-many", model: model([raycast, tailscale, drive] + more), dot: true),
            Scene(name: "edge-known", model: known, dot: false),
            Scene(name: "edge-system", model: system, dot: false),
            Scene(name: "edge-not-running", model: model([raycast,
                info("com.example.gone", "Fantastical Helper", symbol: "calendar", color: .systemRed, ago: 3 * 3600, running: false)]), dot: true),
        ]
    }

    // A stand-in app icon: a colored rounded square with a white symbol.
    static func icon(_ symbol: String, _ color: NSColor) -> NSImage {
        let size = NSSize(width: 28, height: 28)
        return NSImage(size: size, flipped: false) { rect in
            color.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7).fill()
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
            if let glyph = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(config) {
                let tinted = NSImage(size: glyph.size, flipped: false) { glyphRect in
                    glyph.draw(in: glyphRect)
                    NSColor.white.set()
                    glyphRect.fill(using: .sourceAtop)
                    return true
                }
                tinted.draw(in: NSRect(x: (rect.width - glyph.size.width) / 2, y: (rect.height - glyph.size.height) / 2,
                                       width: glyph.size.width, height: glyph.size.height))
            }
            return true
        }
    }
}

/// The wallpaper, a 26 pt menu bar with the arrow (and its dot), and the prompt under it.
private final class ArrivalsSceneView: NSView {
    private let scene: ArrivalsSnapshot.Scene
    private let isDark: Bool
    static let width: CGFloat = 560
    static let barHeight: CGFloat = 26

    init(scene: ArrivalsSnapshot.Scene, mode: String) {
        self.scene = scene
        isDark = mode == "dark"
        super.init(frame: .zero)
        var height = Self.barHeight + 150
        if let model = scene.model {
            let prompt = ArrivalsPromptView(model: model)
            let panel = PromptPanel()
            panel.translatesAutoresizingMaskIntoConstraints = false
            prompt.translatesAutoresizingMaskIntoConstraints = false
            panel.addSubview(prompt)
            addSubview(panel)
            let size = prompt.fittingContentSize
            NSLayoutConstraint.activate([
                prompt.topAnchor.constraint(equalTo: panel.topAnchor),
                prompt.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
                prompt.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
                prompt.bottomAnchor.constraint(equalTo: panel.bottomAnchor),
                panel.widthAnchor.constraint(equalToConstant: size.width),
                panel.heightAnchor.constraint(equalToConstant: size.height),
                panel.topAnchor.constraint(equalTo: topAnchor, constant: Self.barHeight + 6),
                panel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            ])
            height = Self.barHeight + 6 + size.height + 28
        }
        frame = NSRect(x: 0, y: 0, width: Self.width, height: height)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let colors: [NSColor] = isDark
            ? [NSColor(srgbRed: 0.06, green: 0.10, blue: 0.19, alpha: 1), NSColor(srgbRed: 0.18, green: 0.11, blue: 0.20, alpha: 1)]
            : [NSColor(srgbRed: 0.84, green: 0.89, blue: 0.96, alpha: 1), NSColor(srgbRed: 0.95, green: 0.89, blue: 0.84, alpha: 1)]
        NSGradient(colors: colors)?.draw(in: bounds, angle: -20)
        (isDark ? NSColor.black.withAlphaComponent(0.30) : NSColor.white.withAlphaComponent(0.45)).setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: Self.barHeight).fill()
        let ink: NSColor = isDark ? NSColor(white: 0.96, alpha: 1) : NSColor(white: 0.11, alpha: 1)
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: ink]
        let bold: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13, weight: .bold), .foregroundColor: ink]
        ("Finder" as NSString).draw(at: NSPoint(x: 14, y: 4), withAttributes: bold)
        ("File" as NSString).draw(at: NSPoint(x: 68, y: 4), withAttributes: attributes)
        ("Edit" as NSString).draw(at: NSPoint(x: 100, y: 4), withAttributes: attributes)
        ("9:41" as NSString).draw(at: NSPoint(x: bounds.width - 44, y: 4), withAttributes: attributes)
        var x = bounds.width - 130
        for symbol in ["wifi", "battery.100", "chevron.left"].reversed() {
            guard let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) else { continue }
            let tinted = NSImage(size: image.size, flipped: false) { rect in
                image.draw(in: rect)
                ink.set()
                rect.fill(using: .sourceAtop)
                return true
            }
            x -= tinted.size.width + 12
            tinted.draw(in: NSRect(x: x, y: 5, width: tinted.size.width, height: tinted.size.height))
            if symbol == "chevron.left", scene.dot {
                NSColor.controlAccentColor.setFill()
                NSBezierPath(ovalIn: NSRect(x: x + tinted.size.width - 2, y: 2, width: ArrivalsArrowDot.diameter,
                                            height: ArrivalsArrowDot.diameter)).fill()
            }
        }
    }
}

/// What the popover draws around the prompt: the system's material, as a flat fill.
private final class PromptPanel: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 14, yRadius: 14)
        NSColor.windowBackgroundColor.setFill()
        path.fill()
        NSColor.separatorColor.setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}
#endif
