//
//  AboutViewController.swift
//  Hidden Bar
//
//  Created by phucld on 12/19/19.
//  Copyright © 2019 Dwarves Foundation. All rights reserved.
//

import Cocoa

/// Version and build, updates (direct build only), and where to get help.
final class AboutViewController: SettingsPaneController {
    static let changelogURL = URL(string: "https://github.com/dwarvesf/hidden/blob/develop/CHANGELOG.md")!
    static let sourceURL = URL(string: "https://github.com/dwarvesf/hidden")!
    static let issuesURL = URL(string: "https://github.com/dwarvesf/hidden/issues")!
    static let websiteURL = URL(string: "https://dwarves.foundation/")!
    static let xURL = URL(string: "https://x.com/dwarvesf")!
    static let emailAddress = "macos@d.foundation"
    static let checkForUpdatesIdentifier = NSUserInterfaceItemIdentifier("checkForUpdates")

    /// "Version 1.12 (18) · Direct download"; support needs to know which build.
    static func versionLine(version: String?, build: String?, kind: SettingsBuild) -> String {
        var line = "Version".localized + " " + (version ?? "?")
        if let build { line += " (\(build))" }
        return line + " · " + (kind == .direct ? "Direct download" : "Mac App Store").localized
    }

    private var lastCheckedCaption: NSTextField?

    override func buildForm() {
        let whatsNew = SettingsForm.link("What's new".localized, url: Self.changelogURL)
        if context.build == .direct {
            let autoCheck = boundSwitch("SUEnableAutomaticChecks", read: { Self.automaticallyChecksForUpdates },
                                        write: { Self.automaticallyChecksForUpdates = $0 })
            let autoRow = SettingsForm.row("Check for updates automatically".localized, caption: Self.lastCheckedText(), control: autoCheck)
            let check = NSButton(title: "Check for Updates…".localized, target: self, action: #selector(checkForUpdates(_:)))
            check.identifier = Self.checkForUpdatesIdentifier
            check.bezelStyle = .rounded
            let linkRow = Self.linkRow(whatsNew, trailing: check)
            addSection(nil, rows: [header(), autoRow, linkRow])
        } else {
            addSection(nil, rows: [header(), Self.linkRow(whatsNew, caption: "Updates come from the Mac App Store.".localized)])
        }

        let email = NSTextField(labelWithString: Self.emailAddress)
        email.textColor = .secondaryLabelColor
        email.isSelectable = true
        addSection("Help and feedback".localized, rows: [
            Self.linkRow(SettingsForm.link("Report a problem".localized, url: Self.issuesURL),
                         caption: "On GitHub. Please say your macOS version and which Hidden Bar you use.".localized),
            SettingsForm.row("Email".localized, control: email),
            Self.linkRow(SettingsForm.link("Source code".localized, url: Self.sourceURL),
                         caption: "Free and open source, MIT license.".localized),
            Self.linkRow(SettingsForm.link("Follow @dwarvesf on X".localized, url: Self.xURL, image: Self.xLogo)),
            Self.linkRow(SettingsForm.link("Made by Dwarves Foundation".localized, url: Self.websiteURL)),
        ])
    }

    private func header() -> NSView {
        let icon = NSImageView(image: NSImage(named: "AppIcon") ?? NSApp.applicationIconImage ?? NSImage())
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 72).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 72).isActive = true
        let name = NSTextField(labelWithString: "Hidden Bar")
        name.font = .systemFont(ofSize: 20, weight: .bold)
        let tagline = NSTextField(labelWithString: "Keeps your menu bar tidy.".localized)
        tagline.textColor = .secondaryLabelColor
        let version = NSTextField(labelWithString: Self.versionLine(version: Bundle.main.releaseVersionNumber,
                                                                  build: Bundle.main.buildVersionNumber, kind: context.build))
        version.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        version.textColor = .secondaryLabelColor
        version.isSelectable = true
        let texts = NSStackView(views: [name, tagline, version])
        texts.orientation = .vertical
        texts.alignment = .leading
        texts.spacing = 3
        texts.setCustomSpacing(6, after: tagline)
        let row = NSStackView(views: [icon, texts])
        row.spacing = 16
        row.edgeInsets = NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        row.alignment = .centerY
        return row
    }

    private static func linkRow(_ link: NSButton, caption: String? = nil, trailing: NSView? = nil) -> NSView {
        let row = SettingsForm.row("", caption: caption, control: trailing)
        // Put the link where the title label sits.
        func all(_ view: NSView) -> [NSView] { view.subviews + view.subviews.flatMap(all) }
        guard let title = all(row).compactMap({ $0 as? NSTextField }).first(where: { $0.stringValue.isEmpty }),
              let texts = title.superview as? NSStackView else { return row }
        texts.insertArrangedSubview(link, at: 0)
        texts.removeArrangedSubview(title)
        title.removeFromSuperview()
        return row
    }

    private static func lastCheckedText() -> String? {
        #if HIDDENBAR_SPARKLE
        guard let date = UpdateController.shared.lastUpdateCheckDate else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        return String(format: "Last checked %@.".localized, formatter.string(from: date))
        #else
        return nil
        #endif
    }

    private static var automaticallyChecksForUpdates: Bool {
        get {
            #if HIDDENBAR_SPARKLE
            return UpdateController.shared.automaticallyChecksForUpdates
            #else
            return false
            #endif
        }
        set {
            #if HIDDENBAR_SPARKLE
            UpdateController.shared.automaticallyChecksForUpdates = newValue
            #endif
        }
    }

    @objc private func checkForUpdates(_ sender: Any?) {
        #if HIDDENBAR_SPARKLE
        UpdateController.shared.checkForUpdates()
        #endif
    }

    /// The X logo, drawn from its outline so no asset is needed.
    static let xLogo: NSImage = {
        let image = NSImage(size: NSSize(width: 13, height: 13), flipped: true) { rect in
            let scale = rect.width / 1200
            let outer: [(CGFloat, CGFloat)] = [(714, 519), (1161, 0), (1055, 0), (667, 451), (357, 0), (0, 0), (468, 682),
                                               (0, 1226), (106, 1226), (515, 750), (843, 1226), (1200, 1226)]
            let inner: [(CGFloat, CGFloat)] = [(569, 688), (144, 80), (307, 80), (1055, 1150), (892, 1150)]
            let path = NSBezierPath()
            for points in [outer, inner] {
                path.move(to: NSPoint(x: points[0].0 * scale, y: points[0].1 * scale * 1200 / 1227))
                points.dropFirst().forEach { path.line(to: NSPoint(x: $0.0 * scale, y: $0.1 * scale * 1200 / 1227)) }
                path.close()
            }
            path.windingRule = .evenOdd
            NSColor.black.setFill()
            path.fill()
            return true
        }
        image.isTemplate = true
        return image
    }()
}
