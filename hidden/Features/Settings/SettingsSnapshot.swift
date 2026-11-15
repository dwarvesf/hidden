//
//  SettingsSnapshot.swift
//  Hidden Bar
//
//  Copyright © 2026 Dwarves Foundation. All rights reserved.
//

#if DEBUG
import AppKit

/// Debug builds only. Launch with `-settingsSnapshotDir DIR` to draw every
/// Settings pane, light and dark, and every status card state into DIR as PNGs,
/// then quit. Writes no preference. Windows are drawn into a bitmap, never shown, so no screen
/// recording permission is needed. Runs before launch touches login items,
/// hotkeys or the hiding engine, and quits before the launch collapse.
enum SettingsSnapshot {
    static func runIfRequested() -> Bool {
        guard let path = UserDefaults.standard.string(forKey: "settingsSnapshotDir") else { return false }
        let dir = URL(fileURLWithPath: path)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        render(to: dir)
        exit(0)
    }

    private static let appearances: [(NSAppearance.Name, String)] = [(.aqua, "light"), (.darkAqua, "dark")]

    static func render(to dir: URL) {
        let build = SettingsBuild.current == .direct ? "direct" : "appstore"
        var live = SettingsContext.live
        live.previewAlwaysHidden = false
        for (appearance, mode) in appearances {
            for tab in live.visibleTabs {
                shoot(PreferencesWindowController(context: live), tab: tab, appearance: appearance,
                      to: dir.appendingPathComponent("\(build)-\(tab.rawValue)-\(mode).png"))
            }
            // Every status card state, through the same General pane.
            for status in [SettingsStatus.working, .needsAccessibility, .outsideApplications, .appStoreOnMacOS27] {
                var context = live
                context.statusOverride = status
                if status == .appStoreOnMacOS27 { context.build = .appStore }
                shoot(PreferencesWindowController(context: context), tab: .general, appearance: appearance,
                      to: dir.appendingPathComponent("\(build)-status-\(status)-\(mode).png"))
            }
            // The Icons pane with the pinned sections on, off and empty, from
            // fixed data: the live table would put this Mac's apps in the shots.
            let registered = MenuBarAppsPane.makeViewController
            for (state, store) in SnapshotMenuBarAppsStore.states {
                var context = live
                context.build = .direct
                context.osMajorVersion = 27
                context.menuBarAppsAvailable = true
                MenuBarAppsPane.makeViewController = { MenuBarAppsSettingsViewController(context: context, store: store) }
                shoot(PreferencesWindowController(context: context), tab: .menuBarApps, appearance: appearance,
                      to: dir.appendingPathComponent("\(build)-menubarapps-\(state)-\(mode).png"))
            }
            MenuBarAppsPane.makeViewController = registered
            #if HIDDENBAR_NATIVE_VISIBILITY
            ArrivalsSnapshot.render(appearance: appearance, mode: mode, to: dir)
            #endif
            // Presentation mode: the capsule, panels and note, then the General
            // pane (which now scrolls) at the Presentation group.
            #if HIDDENBAR_NATIVE_VISIBILITY
            PresentationSnapshot.render(to: dir, appearance: appearance, mode: mode)
            var presentation = live
            presentation.build = .direct
            presentation.osMajorVersion = 27
            presentation.statusOverride = .working
            PresentationSensitiveAppsControl.snapshotChips = PresentationSnapshot.sensitiveChipsFixture
            shoot(PreferencesWindowController(context: presentation), tab: .general, appearance: appearance,
                  to: dir.appendingPathComponent("\(build)-present-settings-\(mode).png"), scrollsToEnd: true)
            PresentationSensitiveAppsControl.snapshotChips = nil
            #endif
            // The preview strip per engine, with the always-hidden section on.
            for (os, engine) in [(27, "macos27"), (26, "macos26")] {
                var context = live
                context.osMajorVersion = os
                context.previewAlwaysHidden = true
                context.statusOverride = .working
                shoot(PreferencesWindowController(context: context), tab: .general, appearance: appearance,
                      to: dir.appendingPathComponent("\(build)-preview-\(engine)-alwayshidden-\(mode).png"))
            }
        }
        // Type-to-find palette: its states, from fixture apps, and the General tab with its shortcut set.
        #if HIDDENBAR_NATIVE_VISIBILITY
        PaletteSnapshot.render(to: dir, build: build)
        #endif
    }

    static func shoot(_ controller: PreferencesWindowController, tab: SettingsTab,
                              appearance: NSAppearance.Name, to url: URL, scrollsToEnd: Bool = false) {
        guard let window = controller.window else { return }
        window.appearance = NSAppearance(named: appearance)
        (window as? SettingsWindow)?.drawsAsKey = true
        controller.select(tab, animate: false)
        window.layoutIfNeeded()
        if scrollsToEnd, let document = controller.paneScroll.documentView {
            // A pane taller than the window scrolls: show its end.
            controller.paneScroll.contentView.scroll(to: NSPoint(x: 0, y: max(0, document.frame.height - controller.paneScroll.contentView.bounds.height)))
            controller.paneScroll.reflectScrolledClipView(controller.paneScroll.contentView)
        }
        window.displayIfNeeded()
        guard let frameView = window.contentView?.superview,
              let rep = frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds) else { return }
        frameView.cacheDisplay(in: frameView.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
        NSLog("SettingsSnapshot: %@ %.0fx%.0f", url.lastPathComponent, frameView.bounds.width, frameView.bounds.height)
        window.close()
    }
}
#endif
