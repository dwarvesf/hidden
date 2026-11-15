//
//  MenuBarAppIdentityTests.swift
//  HiddenTests
//
//  Copyright © 2026 Dwarves Foundation. All rights reserved.
//

import XCTest
import AppKit
@testable import Hidden_Bar

/// Contract: the Icons pane names and draws each app from its bundle id, the
/// same way every time, and loads each icon once.
/// Serves: MenuBarAppIdentity, MenuBarAppIdentityCache, MenuBarAppsSettingsViewController.
/// Mock boundary: the URL and running-app lookups and the icon loader are
/// injected; nothing here asks NSWorkspace.
final class MenuBarAppIdentityTests: XCTestCase {

    private func resolve(_ bundle: String, installed: [String: String] = [:], running: [String: String] = [:]) -> MenuBarAppIdentity.Resolved {
        MenuBarAppIdentity.resolve(bundle: bundle,
                                   appURL: { installed[$0].map { URL(fileURLWithPath: $0) } },
                                   runningName: { running[$0] })
    }

    // Given each Apple service bundle that has no user-facing name
    // When resolving it with nothing installed
    // Then it gets the plain label, a symbol icon and the macOS caption
    func test_appleServices_getPlainLabelsAndSymbols() {
        let expected: [(String, String, String)] = [
            ("com.apple.chronod", "Widgets and Live Activities", "widget.small"),
            ("com.apple.calaccessd", "Calendar", "calendar"),
            ("com.apple.sharingd", "AirDrop and Sharing", "dot.radiowaves.left.and.right"),
            ("com.apple.siriactionsd", "Shortcuts", "bolt"),
            ("com.apple.photolibraryd", "Photos", "photo"),
            ("com.apple.print.daemon.printtool", "Printing", "printer"),
            ("com.apple.screensharing.agent", "Screen Sharing", "display"),
            ("com.apple.SSMenuAgent", "Screen Sharing", "display"),
            ("com.apple.UIKitSystemApp", "iPhone and iPad Apps", "ipad.and.iphone"),
            ("com.apple.backgroundtaskmanagement.agent", "Background Items", "gearshape"),
            ("com.apple.wifi.WiFiAgent", "Wi-Fi", "wifi"),
        ]
        for (bundle, label, symbol) in expected {
            let resolved = resolve(bundle)
            XCTAssertEqual(resolved.name, label.localized, bundle)
            XCTAssertEqual(resolved.icon, .symbol(symbol), bundle)
            XCTAssertEqual(resolved.caption, "macOS".localized, bundle)
        }
    }

    // Given a service whose related app is installed, even when the service itself resolves to a technical name
    // When resolving it
    // Then the related app's icon is used and the service's own bundle is ignored
    func test_appleService_usesTheRelatedAppIcon() {
        let resolved = resolve("com.apple.siriactionsd", installed: [
            "com.apple.shortcuts": "/System/Applications/Shortcuts.app",
            "com.apple.siriactionsd": "/System/Library/CoreServices/SiriActions.app",
        ])
        XCTAssertEqual(resolved.name, "Shortcuts".localized)
        XCTAssertEqual(resolved.icon, .app(URL(fileURLWithPath: "/System/Applications/Shortcuts.app")))
        XCTAssertEqual(resolve("com.apple.UIKitSystemApp", installed: ["com.apple.UIKitSystemApp": "/System/Library/UIKitSystem.app"]).name,
                       "iPhone and iPad Apps".localized)
    }

    // Given a helper app that sits inside another app
    // When resolving it
    // Then the outermost app's name and icon stand for it
    func test_nestedHelper_showsTheOutermostApp() {
        let discord = resolve("com.hnc.Discord.helper.Renderer", installed: [
            "com.hnc.Discord.helper.Renderer": "/Applications/Discord.app/Contents/Frameworks/Discord Helper (Renderer).app"])
        XCTAssertEqual(discord.name, "Discord")
        XCTAssertEqual(discord.icon, .app(URL(fileURLWithPath: "/Applications/Discord.app")))
        XCTAssertNil(discord.caption)

        let snitch = resolve("at.obdev.littlesnitch.agent", installed: [
            "at.obdev.littlesnitch.agent": "/Applications/Little Snitch.app/Contents/Components/Little Snitch Agent.app"])
        XCTAssertEqual(snitch.name, "Little Snitch")
        XCTAssertEqual(snitch.icon, .app(URL(fileURLWithPath: "/Applications/Little Snitch.app")))
    }

    // Given a plain installed app
    // When resolving it
    // Then its own name and icon are used, without ".app"
    func test_installedApp_usesItsOwnNameAndIcon() {
        let safari = resolve("com.apple.Safari", installed: ["com.apple.Safari": "/Applications/Safari.app"])
        XCTAssertEqual(safari, MenuBarAppIdentity.Resolved(name: "Safari", icon: .app(URL(fileURLWithPath: "/Applications/Safari.app")), caption: nil))
    }

    // Given Finder shows "Control Center" for ControlCenter.app, with or without the ".app" extension
    // When resolving it, and when Finder gives no name
    // Then the Finder name is used without ".app"; the file name is the fallback
    func test_installedApp_usesFinderDisplayName() {
        let url = "/System/Library/CoreServices/ControlCenter.app"
        for shown in ["Control Center", "Control Center.app"] {
            let resolved = MenuBarAppIdentity.resolve(bundle: "com.apple.controlcenter", appURL: { _ in URL(fileURLWithPath: url) },
                                                      runningName: { _ in nil }, displayName: { _ in shown })
            XCTAssertEqual(resolved.name, "Control Center")
        }
        let plain = MenuBarAppIdentity.resolve(bundle: "com.apple.controlcenter", appURL: { _ in URL(fileURLWithPath: url) },
                                               runningName: { _ in nil }, displayName: { _ in nil })
        XCTAssertEqual(plain.name, "ControlCenter")
    }

    // Given an app that is not installed
    // When it is running, then when it is not
    // Then the running app's name is used, then the bundle id, both with the generic icon
    func test_notInstalled_fallsBackToRunningNameThenBundleID() {
        let running = resolve("com.example.gone", running: ["com.example.gone": "Gone Helper"])
        XCTAssertEqual(running, MenuBarAppIdentity.Resolved(name: "Gone Helper", icon: .generic, caption: nil))
        let neither = resolve("com.example.gone")
        XCTAssertEqual(neither, MenuBarAppIdentity.Resolved(name: "com.example.gone", icon: .generic, caption: nil))
    }

    // Given three rows named Share Bar, one unique row and a pair of services with one name
    // When asking for captions
    // Then each same-named row gets its bundle id (after "macOS" for services), and the unique one gets none
    func test_sameNamedRows_getTheirBundleIDAsCaption() {
        let captions = MenuBarAppIdentity.captions(for: [
            ("com.dwarves.sharebar.shots", "Share Bar", nil),
            ("com.dwarves.sharebar.shots.settings", "share bar", nil),
            ("foundation.d.share.bar", "Share Bar", nil),
            ("com.apple.Safari", "Safari", nil),
            ("com.apple.screensharing.agent", "Screen Sharing", "macOS"),
            ("com.apple.SSMenuAgent", "Screen Sharing", "macOS"),
            ("com.apple.sharingd", "AirDrop and Sharing", "macOS"),
        ])
        XCTAssertEqual(captions["com.dwarves.sharebar.shots"], "com.dwarves.sharebar.shots")
        XCTAssertEqual(captions["com.dwarves.sharebar.shots.settings"], "com.dwarves.sharebar.shots.settings")
        XCTAssertEqual(captions["foundation.d.share.bar"], "foundation.d.share.bar")
        XCTAssertNil(captions["com.apple.Safari"])
        XCTAssertEqual(captions["com.apple.screensharing.agent"], "macOS, com.apple.screensharing.agent")
        XCTAssertEqual(captions["com.apple.SSMenuAgent"], "macOS, com.apple.SSMenuAgent")
        XCTAssertEqual(captions["com.apple.sharingd"], "macOS")
    }

    // Given rows that are not running, some with a caption or a same-named twin
    // When asking for captions
    // Then "Not running" comes last, after "macOS" and the bundle id, and running rows are unchanged
    func test_notRunningRows_endTheirCaptionWithNotRunning() {
        let captions = MenuBarAppIdentity.captions(for: [
            ("com.dwarves.sharebar.shots", "Share Bar", nil),
            ("foundation.d.share.bar", "Share Bar", nil),
            ("com.apple.sharingd", "AirDrop and Sharing", "macOS"),
            ("com.apple.Safari", "Safari", nil),
            ("com.apple.Notes", "Notes", nil),
        ], notRunning: ["com.dwarves.sharebar.shots", "com.apple.sharingd", "com.apple.Notes"])
        XCTAssertEqual(captions["com.dwarves.sharebar.shots"], "com.dwarves.sharebar.shots, Not running")
        XCTAssertEqual(captions["foundation.d.share.bar"], "foundation.d.share.bar")
        XCTAssertEqual(captions["com.apple.sharingd"], "macOS, Not running")
        XCTAssertEqual(captions["com.apple.Notes"], "Not running")
        XCTAssertNil(captions["com.apple.Safari"])
    }

    // Given the cache with counting lookups
    // When asking twice for the same installed app's name and icon
    // Then the URL is resolved and the icon loaded once; an app that is not installed is looked up again
    func test_cache_resolvesAndLoadsEachBundleOnce() {
        var urlLookups = 0
        var iconLoads = 0
        var installed = false
        let cache = MenuBarAppIdentityCache(
            appURL: { _ in urlLookups += 1; return installed ? URL(fileURLWithPath: "/Applications/Safari.app") : nil },
            runningName: { _ in nil },
            loadIcon: { _ in iconLoads += 1; return NSImage() })

        installed = true
        for _ in 0..<3 {
            XCTAssertEqual(cache.identity(for: "com.apple.Safari").name, "Safari")
            _ = cache.icon(for: "com.apple.Safari")
        }
        XCTAssertEqual(urlLookups, 1)
        XCTAssertEqual(iconLoads, 1)

        installed = false
        XCTAssertEqual(cache.identity(for: "com.example.late").name, "com.example.late")
        installed = true
        XCTAssertEqual(cache.identity(for: "com.example.late").name, "Safari", "an app installed later is found")
    }
}

/// Contract: opening the Icons tab again changes nothing when nothing changed.
/// Mock boundary: a fake store that counts icon loads.
final class MenuBarAppsPaneTimingTests: XCTestCase {

    private final class CountingStore: MenuBarAppsStore {
        var isEnabled = true
        var table: [String: MenuBarSection]
        var iconLoads = 0

        init(count: Int) {
            table = Dictionary(uniqueKeysWithValues: (0..<count).map { (String(format: "com.test.app%02d", $0), MenuBarSection.visible) })
        }

        func entries() -> [PinnedSectionsList.Entry] {
            table.map { PinnedSectionsList.Entry(bundle: $0.key, name: "App " + $0.key.suffix(2), section: $0.value) }
                .sorted { $0.bundle < $1.bundle }
        }
        func identity(for bundle: String) -> MenuBarAppIdentity.Resolved {
            MenuBarAppIdentity.Resolved(name: "App " + bundle.suffix(2), icon: .generic, caption: nil)
        }
        func icon(for bundle: String) -> NSImage { iconLoads += 1; return NSImage() }
        func runningBundles() -> Set<String> { Set(table.keys) }
        func set(_ section: MenuBarSection, for bundle: String) { table[bundle] = section }
        func setIgnoresDrags(_ ignores: Bool, for bundle: String) {}
        func resetAllToVisible() {}
        func remove(_ bundle: String) {}
        func enable() {}
    }

    private func popup(_ bundle: String, in pane: NSViewController) -> NSView? {
        func search(_ view: NSView) -> NSView? {
            if view.identifier?.rawValue == MenuBarAppsSettingsViewController.popupIdentifier(for: bundle) { return view }
            return view.subviews.lazy.compactMap(search).first
        }
        return search(pane.view)
    }

    // Given a pane built on 40 entries
    // When the tab appears twice more with nothing changed, then once after one entry changed
    // Then the first build loads 40 icons, the repeats load none and keep the same rows, and the change rebuilds
    func test_secondAppearance_reloadsNothingAndKeepsTheRows() throws {
        let store = CountingStore(count: 40)
        let pane = MenuBarAppsSettingsViewController(context: .live, store: store)
        _ = pane.view
        XCTAssertEqual(store.iconLoads, 40)
        let firstRow = try XCTUnwrap(popup("com.test.app05", in: pane))

        pane.viewWillAppear()
        pane.viewWillAppear()
        XCTAssertEqual(store.iconLoads, 40, "icons are not reloaded on a repeat visit")
        XCTAssertTrue(firstRow === popup("com.test.app05", in: pane), "rows are not rebuilt on a repeat visit")

        store.table["com.test.app05"] = .hidden
        pane.viewWillAppear()
        XCTAssertEqual(store.iconLoads, 80, "a changed entry rebuilds the rows")
        XCTAssertFalse(firstRow === popup("com.test.app05", in: pane))
    }
}
