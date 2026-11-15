//
//  MenuBarAppIdentity.swift
//  Hidden Bar
//
//  Copyright © 2026 Dwarves Foundation. All rights reserved.
//

import AppKit

/// How the Icons pane names and draws one app. `resolve` is a pure function of
/// the bundle id and two lookups, so it tests without NSWorkspace.
enum MenuBarAppIdentity {
    enum IconSource: Equatable {
        case app(URL)
        case symbol(String)
        case generic
    }

    struct Resolved: Equatable {
        let name: String
        let icon: IconSource
        let caption: String?
    }

    /// The one place that names macOS services which own a menu bar icon but
    /// ship no app bundle or no user-facing name. `app` is the related app
    /// whose icon fits; the SF Symbol stands in when it is not installed.
    private static let services: [String: (label: String, app: String?, symbol: String)] = [
        "com.apple.chronod": ("Widgets and Live Activities", nil, "widget.small"),
        "com.apple.calaccessd": ("Calendar", "com.apple.iCal", "calendar"),
        "com.apple.sharingd": ("AirDrop and Sharing", nil, "dot.radiowaves.left.and.right"),
        "com.apple.siriactionsd": ("Shortcuts", "com.apple.shortcuts", "bolt"),
        "com.apple.photolibraryd": ("Photos", "com.apple.Photos", "photo"),
        "com.apple.print.daemon.printtool": ("Printing", nil, "printer"),
        "com.apple.screensharing.agent": ("Screen Sharing", "com.apple.ScreenSharing", "display"),
        "com.apple.SSMenuAgent": ("Screen Sharing", "com.apple.ScreenSharing", "display"),
        "com.apple.UIKitSystemApp": ("iPhone and iPad Apps", nil, "ipad.and.iphone"),
        "com.apple.backgroundtaskmanagement.agent": ("Background Items", nil, "gearshape"),
        "com.apple.wifi.WiFiAgent": ("Wi-Fi", nil, "wifi"),
    ]

    static func resolve(bundle: String, appURL: (String) -> URL?, runningName: (String) -> String?,
                        displayName: (URL) -> String? = { _ in nil }) -> Resolved {
        if let service = services[bundle] {
            let icon = service.app.flatMap(appURL).map(IconSource.app) ?? .symbol(service.symbol)
            return Resolved(name: service.label.localized, icon: icon, caption: "macOS".localized)
        }
        guard let url = appURL(bundle) else {
            return Resolved(name: runningName(bundle) ?? bundle, icon: .generic, caption: nil)
        }
        // A helper inside another app shows as that app: "Discord", not "Discord Helper (Renderer)".
        let app = outermostApp(url)
        return Resolved(name: appName(app, displayName: displayName), icon: .app(app), caption: nil)
    }

    /// Finder's name ("Control Center", not "ControlCenter"), without ".app" whatever the extension setting says.
    static func appName(_ app: URL, displayName: (URL) -> String?) -> String {
        let shown = displayName(app).map { $0.hasSuffix(".app") ? String($0.dropLast(4)) : $0 }
        return shown.flatMap { $0.isEmpty ? nil : $0 } ?? app.deletingPathExtension().lastPathComponent
    }

    static func outermostApp(_ url: URL) -> URL {
        let parts = url.pathComponents
        guard let index = parts.firstIndex(where: { $0.hasSuffix(".app") }) else { return url }
        return URL(fileURLWithPath: NSString.path(withComponents: Array(parts[0...index])))
    }

    /// Rows whose name another row shares get the bundle id as caption, after any caption they have;
    /// rows in `notRunning` end with "Not running".
    static func captions(for rows: [(bundle: String, name: String, caption: String?)],
                         notRunning: Set<String> = []) -> [String: String] {
        var counts: [String: Int] = [:]
        rows.forEach { counts[$0.name.lowercased(), default: 0] += 1 }
        var result: [String: String] = [:]
        for row in rows {
            var parts = [row.caption].compactMap { $0 }
            if counts[row.name.lowercased(), default: 0] > 1 { parts.append(row.bundle) }
            if notRunning.contains(row.bundle) { parts.append("Not running".localized) }
            if !parts.isEmpty { result[row.bundle] = parts.joined(separator: ", ") }
        }
        return result
    }
}

/// Names and icons resolved once per bundle id. Loading an icon costs 10 to 20
/// ms per app, which made every tab switch lag when each visit reloaded them.
final class MenuBarAppIdentityCache {
    static let iconSide: CGFloat = 18

    private let appURL: (String) -> URL?
    private let runningName: (String) -> String?
    private let displayName: (URL) -> String?
    private let loadIcon: (MenuBarAppIdentity.IconSource) -> NSImage
    private var identities: [String: MenuBarAppIdentity.Resolved] = [:]
    private var icons: [String: NSImage] = [:]

    init(appURL: @escaping (String) -> URL? = { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) },
         runningName: @escaping (String) -> String? = { NSRunningApplication.runningApplications(withBundleIdentifier: $0).first?.localizedName },
         displayName: @escaping (URL) -> String? = { FileManager.default.displayName(atPath: $0.path) },
         loadIcon: @escaping (MenuBarAppIdentity.IconSource) -> NSImage = MenuBarAppIdentityCache.systemIcon) {
        self.appURL = appURL
        self.runningName = runningName
        self.displayName = displayName
        self.loadIcon = loadIcon
    }

    func identity(for bundle: String) -> MenuBarAppIdentity.Resolved {
        if let known = identities[bundle] { return known }
        let resolved = MenuBarAppIdentity.resolve(bundle: bundle, appURL: appURL, runningName: runningName, displayName: displayName)
        // An app that is not installed may be later; looking again costs a lookup, not an icon load.
        if resolved.icon != .generic { identities[bundle] = resolved }
        return resolved
    }

    func icon(for bundle: String) -> NSImage {
        if let known = icons[bundle] { return known }
        let source = identity(for: bundle).icon
        let image = loadIcon(source)
        if source != .generic { icons[bundle] = image }
        return image
    }

    static func systemIcon(_ source: MenuBarAppIdentity.IconSource) -> NSImage {
        let size = NSSize(width: iconSide, height: iconSide)
        switch source {
        case .app(let url):
            // A copy: sizing the workspace's shared image would resize it for every other caller.
            let image = (NSWorkspace.shared.icon(forFile: url.path).copy() as? NSImage) ?? NSImage()
            image.size = size
            return image
        case .symbol(let name):
            let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 13, weight: .regular))
            image?.isTemplate = true
            return image ?? systemIcon(.generic)
        case .generic:
            let image = (NSWorkspace.shared.icon(for: .applicationBundle).copy() as? NSImage) ?? NSImage()
            image.size = size
            return image
        }
    }
}
