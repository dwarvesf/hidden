//
//  PaletteSnapshot.swift
//  Hidden Bar
//
//  Copyright © 2026 Dwarves Foundation. All rights reserved.
//

#if DEBUG && HIDDENBAR_NATIVE_VISIBILITY
import AppKit

/// Debug builds only. Draws every state on the Palette boards, light and dark,
/// from fixture apps into `direct-palette-<state>-<light|dark>.png`, and the
/// General tab with the find shortcut set. Offscreen, like the Settings
/// snapshots: no Accessibility read, no Screen Recording, no preference written.
enum PaletteSnapshot {
    private static let ready = PaletteEnvironment(accessibilityTrusted: true, engineAvailable: true)

    private static func app(_ name: String, _ bundle: String, _ section: MenuBarSection, running: Bool = true) -> PaletteCandidate {
        return PaletteCandidate(bundleIdentifier: bundle, name: name, section: section, isRunning: running)
    }

    private static let paste = app("Paste", "com.wiheads.paste", .hidden)
    private static let password = app("1Password", "com.1password.1password", .hidden)
    private static let amphetamine = app("Amphetamine", "com.if.Amphetamine", .alwaysHidden)
    private static let dropbox = app("Dropbox", "com.getdropbox.dropbox", .alwaysHidden)
    private static let zoom = app("zoom.us", "us.zoom.xos", .visible)

    /// The board's tile colours, one per fixture app.
    private static let tiles: [String: NSColor] = [
        "com.wiheads.paste": NSColor(srgbRed: 0.357, green: 0.341, blue: 0.839, alpha: 1),
        "com.1password.1password": NSColor(srgbRed: 0.102, green: 0.420, blue: 0.878, alpha: 1),
        "com.if.Amphetamine": NSColor(srgbRed: 0.910, green: 0.576, blue: 0.047, alpha: 1),
        "com.getdropbox.dropbox": NSColor(srgbRed: 0, green: 0.380, blue: 1, alpha: 1),
        "us.zoom.xos": NSColor(srgbRed: 0.18, green: 0.55, blue: 1, alpha: 1),
    ]

    struct Scene {
        let name: String
        let query: String
        let candidates: [PaletteCandidate]
        var environment = PaletteSnapshot.ready
        var opening: String?
        var failure: String?
    }

    /// Every state on the Light, Dark, Open and Edge boards, plus the whole list
    /// and the two edge states the boards do not draw.
    static var scenes: [Scene] {
        let hidden = [paste, password, amphetamine]
        return [
            Scene(name: "results", query: "pa", candidates: hidden + [zoom]),
            Scene(name: "all", query: "", candidates: hidden + [dropbox, zoom]),
            Scene(name: "opening", query: "pa", candidates: hidden + [zoom], opening: paste.bundleIdentifier),
            Scene(name: "nomatch", query: "zoom", candidates: hidden + [zoom]),
            Scene(name: "nothinghidden", query: "", candidates: [zoom]),
            Scene(name: "accessibilityoff", query: "", candidates: hidden,
                  environment: PaletteEnvironment(accessibilityTrusted: false, engineAvailable: true)),
            Scene(name: "macositem", query: "focus", candidates: hidden + [zoom]),
            Scene(name: "appquit", query: "drop", candidates: hidden + [app("Dropbox", "com.getdropbox.dropbox", .alwaysHidden, running: false)]),
            Scene(name: "cannotopen", query: "dro", candidates: hidden + [dropbox], failure: "Dropbox"),
            Scene(name: "presenting", query: "", candidates: hidden + [dropbox, zoom],
                  environment: PaletteEnvironment(accessibilityTrusted: true, engineAvailable: true,
                                                  hiddenWhilePresenting: [password.bundleIdentifier, dropbox.bundleIdentifier])),
            Scene(name: "nopins", query: "pa", candidates: hidden + [zoom],
                  environment: PaletteEnvironment(accessibilityTrusted: true, engineAvailable: true, pinsSections: false)),
            Scene(name: "enginedown", query: "", candidates: hidden,
                  environment: PaletteEnvironment(accessibilityTrusted: true, engineAvailable: false)),
        ]
    }

    static func viewState(for scene: Scene) -> PaletteViewState {
        var model = PaletteModel(candidates: scene.candidates, environment: scene.environment)
        model.setQuery(scene.query)
        if let failure = scene.failure { model.showCannotOpen(appName: failure) }
        if let opening = scene.opening { model.select(bundle: opening) }
        return PaletteViewState(query: model.query, content: model.content, selectedIndex: model.selectedIndex,
                                openingBundle: scene.opening, pinsSections: scene.environment.pinsSections)
    }

    static func render(to dir: URL, build: String) {
        for (appearance, mode) in [(NSAppearance.Name.aqua, "light"), (.darkAqua, "dark")] {
            for scene in scenes {
                draw(viewState(for: scene), appearance: appearance,
                     to: dir.appendingPathComponent("\(build)-palette-\(scene.name)-\(mode).png"))
            }
            renderSettings(appearance: appearance, to: dir.appendingPathComponent("\(build)-palette-settings-\(mode).png"))
        }
    }

    /// The General tab with the shortcut set, from a throwaway defaults suite.
    private static func renderSettings(appearance: NSAppearance.Name, to url: URL) {
        let suite = "PaletteSnapshot.\(UUID().uuidString)"
        guard let fixture = UserDefaults(suiteName: suite) else { return }
        defer { fixture.removePersistentDomain(forName: suite) }
        let shortcut = GlobalKeybindPreferences(function: false, control: false, command: true, shift: false, option: true,
                                                capsLock: false, carbonFlags: 2304, characters: "k", keyCode: 40)
        fixture.set(try? JSONEncoder().encode(shortcut), forKey: UserDefaults.Key.findHiddenIconShortcut)
        var context = SettingsContext.live
        context.build = .direct
        context.osMajorVersion = 27
        context.statusOverride = .working
        context.previewAlwaysHidden = false
        context.shortcutFixtureDefaults = fixture
        SettingsSnapshot.shoot(PreferencesWindowController(context: context), tab: .general, appearance: appearance, to: url)
    }

    private static func draw(_ state: PaletteViewState, appearance: NSAppearance.Name, to url: URL) {
        let content = PaletteContentView(flat: true)
        content.apply(state, icon: { icon(for: $0) })
        let margin: CGFloat = 28
        let backdrop = NSView()
        backdrop.wantsLayer = true
        backdrop.addSubview(content)
        content.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: backdrop.topAnchor, constant: margin),
            content.leadingAnchor.constraint(equalTo: backdrop.leadingAnchor, constant: margin),
        ])
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: appearance)
        window.contentView = backdrop
        backdrop.layoutSubtreeIfNeeded()
        let size = content.fittingSize
        window.setContentSize(NSSize(width: size.width + margin * 2, height: size.height + margin * 2))
        window.layoutIfNeeded()
        // The board's wallpaper behind the glass, so the translucent fill reads as it does there.
        let wallpaper = CAGradientLayer()
        wallpaper.frame = backdrop.bounds
        wallpaper.startPoint = CGPoint(x: 0, y: 1)
        wallpaper.endPoint = CGPoint(x: 1, y: 0)
        wallpaper.colors = (appearance == .darkAqua ? [0x101A30, 0x1D1A36, 0x2E1C2E] : [0xD6E3F5, 0xE3DAF0, 0xF2E2D6]).map { hex in
            NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                    blue: CGFloat(hex & 0xFF) / 255, alpha: 1).cgColor
        }
        backdrop.layer?.insertSublayer(wallpaper, at: 0)
        window.displayIfNeeded()
        guard let rep = backdrop.bitmapImageRepForCachingDisplay(in: backdrop.bounds) else { return }
        backdrop.cacheDisplay(in: backdrop.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
        NSLog("PaletteSnapshot: %@ %.0fx%.0f", url.lastPathComponent, backdrop.bounds.width, backdrop.bounds.height)
        window.close()
    }

    /// A tile with the app's first letter: fixture apps have no bundle to take an icon from.
    private static func icon(for bundle: String) -> NSImage {
        let color = tiles[bundle] ?? .systemGray
        let letter = (scenes.lazy.flatMap(\.candidates).first { $0.bundleIdentifier == bundle }?.name.first).map(String.init) ?? "?"
        return NSImage(size: NSSize(width: 48, height: 48), flipped: false) { rect in
            color.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 11, yRadius: 11).fill()
            let style = NSMutableParagraphStyle()
            style.alignment = .center
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 26, weight: .bold),
                                                              .foregroundColor: NSColor.white, .paragraphStyle: style]
            let text = NSAttributedString(string: letter, attributes: attributes)
            let height = text.size().height
            text.draw(in: NSRect(x: 0, y: (rect.height - height) / 2, width: rect.width, height: height))
            return true
        }
    }
}
#endif
