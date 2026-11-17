//
//  ShortcutRecorderRow.swift
//  Hidden Bar
//
//  Copyright © 2026 Console Labs. All rights reserved.
//

import AppKit
import HotKey

/// The control for one global shortcut: a button that records the next key
/// combination, and a clear button. It is bound to a `Data` preference key
/// holding `GlobalKeybindPreferences` JSON; the shortcut goes live through
/// `HotKeyRegistry`, which re-reads that key on `.prefsChanged`. Place it in a
/// `SettingsForm.row` as the control, and call `refresh()` from `onRefresh`.
///
/// While it listens, a local key monitor (this app's events only, so no Input
/// Monitoring permission) takes every key, so a combination such as Cmd+W can be
/// recorded instead of closing the window. Escape cancels.
final class ShortcutRecorderRow: NSStackView {
    let key: String
    /// The button that shows the shortcut; its identifier is the preference key.
    let button = NSButton(title: "", target: nil, action: nil)
    let clearButton = NSButton(title: "", target: nil, action: nil)
    /// An orange triangle, shown only while another shortcut uses the same combination.
    let clashIcon = NSImageView()

    private let defaults: UserDefaults
    private let registry: HotKeyRegistry
    private var monitor: Any?
    // The name of the shortcut that used the combination the user just tried; it
    // was not saved, and the warning stays until the next recording or clear.
    private var refusedClash: String?
    private var resignObserver: NSObjectProtocol?
    private(set) var isListening = false {
        didSet { listeningChanged() }
    }

    /// The recorder that is listening right now, if any.
    private static weak var active: ShortcutRecorderRow?
    static var isRecording: Bool { active != nil }

    init(key: String, registry: HotKeyRegistry = .shared, defaults: UserDefaults = AppDefaults.store) {
        self.key = key
        self.registry = registry
        self.defaults = defaults
        super.init(frame: .zero)

        button.bezelStyle = .rounded
        button.identifier = NSUserInterfaceItemIdentifier(key)
        button.target = self
        button.action = #selector(beginRecording)
        clearButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Clear".localized)
        clearButton.isBordered = false
        clearButton.contentTintColor = .tertiaryLabelColor
        clearButton.target = self
        clearButton.action = #selector(clearPressed)
        clashIcon.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: nil)
        clashIcon.contentTintColor = .systemOrange
        clashIcon.isHidden = true

        orientation = .horizontal
        spacing = 4
        setViews([clashIcon, button, clearButton], in: .leading)
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    deinit {
        stopMonitoring()
    }

    // MARK: State

    /// The stored shortcut, nil when none is set.
    var shortcut: GlobalKeybindPreferences? { registry.shortcut(for: key) }

    /// The name of another Hidden Bar shortcut with the same combination, if any.
    var clashingTitle: String? {
        shortcut.flatMap { registry.clashingTitle(for: $0, excluding: key) }
    }

    /// Redraws from the stored preference. Does nothing while recording, so a
    /// preference change elsewhere cannot overwrite the prompt.
    func refresh() {
        guard !isListening else { return }
        let stored = shortcut
        button.title = stored?.description ?? "Set Shortcut".localized
        clearButton.isHidden = stored == nil
        let clash = clashingTitle ?? refusedClash
        clashIcon.isHidden = clash == nil
        let message = clash.map { String(format: "Also used by %@".localized, $0) }
        clashIcon.toolTip = message
        clashIcon.setAccessibilityLabel(message)
        clashIcon.setAccessibilityElement(message != nil)
    }

    // MARK: Recording

    @objc private func beginRecording() {
        refusedClash = nil
        isListening = true
        window?.makeFirstResponder(nil)
    }

    @objc private func clearPressed() {
        clear()
    }

    /// Removes the stored shortcut.
    func clear() {
        isListening = false
        refusedClash = nil
        defaults.removeObject(forKey: key)
        NotificationCenter.default.post(name: .prefsChanged, object: nil)
        refresh()
    }

    /// Stops listening and shows the stored shortcut again.
    func cancelRecording() {
        isListening = false
        refresh()
    }

    /// Takes one key event while listening. Returns true when the event was used.
    @discardableResult
    func handle(_ event: NSEvent) -> Bool {
        guard isListening else { return false }
        switch event.type {
        case .keyDown:
            if event.keyCode == 53, Self.modifiers(of: event).isEmpty {
                cancelRecording()
            } else {
                record(event)
            }
            return true
        case .flagsChanged:
            showModifiers(of: event)
            return true
        default:
            return false
        }
    }

    private func record(_ event: NSEvent) {
        guard let characters = event.charactersIgnoringModifiers else { return cancelRecording() }
        let flags = Self.modifiers(of: event)
        let keybind = GlobalKeybindPreferences(
            function: flags.contains(.function),
            control: flags.contains(.control),
            command: flags.contains(.command),
            shift: flags.contains(.shift),
            option: flags.contains(.option),
            capsLock: flags.contains(.capsLock),
            carbonFlags: flags.carbonFlags,
            characters: characters,
            keyCode: UInt32(event.keyCode))
        // A bare letter would fire while typing; keep the old shortcut.
        guard keybind.isAcceptable, let data = try? JSONEncoder().encode(keybind) else { return cancelRecording() }
        // Two shortcuts on one combination cannot both work: macOS keeps the first
        // and refuses the second without a word. Keep the old shortcut and say why.
        if let clash = registry.clashingTitle(for: keybind, excluding: key) {
            refusedClash = clash
            return cancelRecording()
        }
        isListening = false
        defaults.set(data, forKey: key)
        NotificationCenter.default.post(name: .prefsChanged, object: nil)
        refresh()
    }

    private func showModifiers(of event: NSEvent) {
        let flags = Self.modifiers(of: event)
        let held = GlobalKeybindPreferences(
            function: flags.contains(.function),
            control: flags.contains(.control),
            command: flags.contains(.command),
            shift: flags.contains(.shift),
            option: flags.contains(.option),
            capsLock: flags.contains(.capsLock),
            carbonFlags: 0,
            characters: nil,
            keyCode: UInt32(event.keyCode))
        // Every modifier let go with no key pressed: give up, keep the old shortcut.
        if held.description.isEmpty {
            cancelRecording()
        } else {
            button.title = held.description
        }
    }

    private static func modifiers(of event: NSEvent) -> NSEvent.ModifierFlags {
        event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    }

    private func listeningChanged() {
        if isListening {
            Self.active = self
            startMonitoring()
            button.highlight(true)
            button.title = "Type a Shortcut…".localized
        } else {
            if Self.active === self { Self.active = nil }
            stopMonitoring()
            button.highlight(false)
        }
    }

    private func startMonitoring() {
        stopMonitoring()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self, self.handle(event) else { return event }
            return nil
        }
        guard let window else { return }
        resignObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification,
                                                                object: window, queue: .main) { [weak self] _ in
            self?.cancelRecording()
        }
    }

    private func stopMonitoring() {
        monitor.map(NSEvent.removeMonitor)
        monitor = nil
        resignObserver.map(NotificationCenter.default.removeObserver)
        resignObserver = nil
    }
}
