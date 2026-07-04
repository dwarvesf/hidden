//
//  SecondaryBarWindowController.swift
//  Hidden Bar
//
//  Phase 1: UI foundation for a Bartender-style secondary bar.
//  Displays sample icons below the menu bar. No Screen Recording,
//  no Accessibility, no real menu-bar item capture yet.
//

import AppKit

final class SecondaryBarWindowController: NSWindowController {

    // MARK: - Singleton

    static let shared = SecondaryBarWindowController()

    // MARK: - UI

    private let stackView = NSStackView()
    private let visualEffectView = NSVisualEffectView()
    private var sampleIconButtons: [NSButton] = []

    // MARK: - Event monitors (active only while visible)

    private var localMonitor: Any?
    private var globalMonitor: Any?

    // MARK: - Constants

    private enum Metrics {
        static let barHeight: CGFloat = 44
        static let iconSize: CGFloat = 28
        static let stackSpacing: CGFloat = 4
        static let edgePadding: CGFloat = 10
        static let cornerRadius: CGFloat = 8
    }

    // MARK: - Init

    private init() {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init(window: panel)
        configureWindow(panel)
        buildContent(for: panel)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        removeEventMonitors()
    }

    // MARK: - Window configuration

    private func configureWindow(_ panel: NSPanel) {
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.hasShadow = true
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
    }

    // MARK: - Content

    private func buildContent(for panel: NSPanel) {
        visualEffectView.material = .menu
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.state = .active
        visualEffectView.wantsLayer = true
        visualEffectView.layer?.cornerRadius = Metrics.cornerRadius
        visualEffectView.layer?.masksToBounds = true
        visualEffectView.translatesAutoresizingMaskIntoConstraints = false

        stackView.orientation = .horizontal
        stackView.spacing = Metrics.stackSpacing
        stackView.distribution = .equalSpacing
        stackView.alignment = .centerY
        stackView.setHuggingPriority(.defaultHigh, for: .horizontal)
        stackView.translatesAutoresizingMaskIntoConstraints = false

        visualEffectView.addSubview(stackView)

        let contentView = NSView(frame: .zero)
        contentView.addSubview(visualEffectView)
        panel.contentView = contentView

        NSLayoutConstraint.activate([
            visualEffectView.topAnchor.constraint(equalTo: contentView.topAnchor),
            visualEffectView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            visualEffectView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            visualEffectView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),

            stackView.topAnchor.constraint(equalTo: visualEffectView.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: visualEffectView.bottomAnchor),
            stackView.leadingAnchor.constraint(equalTo: visualEffectView.leadingAnchor, constant: Metrics.edgePadding),
            stackView.trailingAnchor.constraint(equalTo: visualEffectView.trailingAnchor, constant: -Metrics.edgePadding),
        ])

        populateSampleIcons()
    }

    private func populateSampleIcons() {
        let symbolNames = [
            "wifi",
            "battery.100",
            "magnifyingglass",
            "bell.fill",
            "gearshape",
            "lock.fill",
            "icloud",
            "clock",
        ]

        for name in symbolNames {
            guard let image = NSImage(
                systemSymbolName: name,
                accessibilityDescription: nil
            ) else { continue }

            let button = NSButton(frame: NSRect(x: 0, y: 0, width: Metrics.iconSize, height: Metrics.iconSize))
            button.image = image
            button.isBordered = false
            button.bezelStyle = .texturedRounded
            button.imageScaling = .scaleProportionallyDown
            button.target = self
            button.action = #selector(sampleIconClicked(_:))
            button.toolTip = name

            stackView.addArrangedSubview(button)
            sampleIconButtons.append(button)
        }
    }

    @objc private func sampleIconClicked(_ sender: NSButton) {
        NSLog("SecondaryBar: sample icon tapped – \(sender.toolTip ?? "?")")
    }

    // MARK: - Show / Hide

    func show() {
        guard let window = window else { return }

        positionOnActiveScreen()
        installEventMonitors()
        window.orderFrontRegardless()
    }

    func hide() {
        removeEventMonitors()
        window?.orderOut(nil)
    }

    var isBarVisible: Bool {
        window?.isVisible ?? false
    }

    // MARK: - Positioning

    private func positionOnActiveScreen() {
        guard let window = window else { return }

        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouseLocation) }
            ?? NSScreen.main
            ?? NSScreen.screens.first!
        let menuBarHeight = NSStatusBar.system.thickness

        let maxWidth = min(screen.frame.width - 40, 600)
        let barWidth = max(maxWidth, 200)

        let x = screen.frame.minX + (screen.frame.width - barWidth) / 2
        let y = screen.frame.maxY - menuBarHeight - Metrics.barHeight

        window.setFrame(NSRect(x: x, y: y, width: barWidth, height: Metrics.barHeight), display: true)
    }

    // MARK: - Event monitors

    private func installEventMonitors() {
        guard localMonitor == nil, globalMonitor == nil else { return }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self = self, self.isBarVisible else { return event }

            if event.type == .keyDown, event.keyCode == 53 {
                self.hide()
                return nil
            }

            if event.type == .leftMouseDown || event.type == .rightMouseDown {
                if !self.isClickInsideBar(event.windowNumber) {
                    self.hide()
                }
            }

            return event
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self = self, self.isBarVisible else { return }
            DispatchQueue.main.async {
                self.hide()
            }
        }
    }

    private func removeEventMonitors() {
        if let m = localMonitor {
            NSEvent.removeMonitor(m)
            localMonitor = nil
        }
        if let m = globalMonitor {
            NSEvent.removeMonitor(m)
            globalMonitor = nil
        }
    }

    private func isClickInsideBar(_ windowNumber: Int) -> Bool {
        guard let barWindow = window else { return false }
        return barWindow.windowNumber == windowNumber
    }
}
