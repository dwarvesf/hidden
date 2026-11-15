//
//  PresentationController.swift
//  Hidden Bar
//
//  Copyright © 2026 Dwarves Foundation. All rights reserved.
//

#if HIDDENBAR_NATIVE_VISIBILITY
import AppKit

// The user-facing side of presentation mode: the capsule in the menu bar, the
// panel and note that open from it, the mirror trigger, and the manual switch.
// What is hidden, when, and the fail-open rules live in NativeVisibilityEngine
// and PresentationState; this only starts and stops the mode and shows its phase.
final class PresentationController {
    private let engine: NativeVisibilityEngine
    private let arrowButton: () -> NSStatusBarButton?
    private let mirrors: DisplayMirrorReader
    private let catalog: MenuBarItemCatalog

    private var capsule: NSStatusItem?
    private var panel: NSPopover?
    private var note: NSPopover?
    private var noteTimer: Timer?
    // The pause explains itself once per session; later the capsule just reads Paused.
    private var pauseExplained = false
    private var prefsObserver: NSObjectProtocol?

    init(engine: NativeVisibilityEngine,
         arrowButton: @escaping () -> NSStatusBarButton?,
         mirrors: DisplayMirrorReader = .live,
         catalog: MenuBarItemCatalog = .shared) {
        self.engine = engine
        self.arrowButton = arrowButton
        self.mirrors = mirrors
        self.catalog = catalog
        // A manual start does not survive a relaunch: a crash plus relaunch never
        // re-hides the bar on its own.
        Preferences.presentationModeActive = false
        engine.onPresentationChange = { [weak self] phase in self?.phaseChanged(phase) }
        prefsObserver = NotificationCenter.default.addObserver(forName: .prefsChanged, object: nil, queue: .main) { [weak self] _ in
            self?.syncMirror()
            self?.engine.sensitiveAppsDidChange()
        }
    }

    deinit {
        prefsObserver.map(NotificationCenter.default.removeObserver)
    }

    var isOn: Bool { return engine.isPresentationOn }

    var menuTitle: String {
        return (isOn ? "Stop Presentation Mode" : "Start Presentation Mode").localized
    }

    func toggle() {
        isOn ? stop() : start()
    }

    func start() {
        engine.startPresentation()
    }

    func stop() {
        engine.stopPresentation()
    }

    // The mirror trigger: on while a display is mirrored and the option is on.
    // Read from the screen-parameters notice, which fires once the change landed.
    func syncMirror() {
        engine.presentationMirrorChanged(Preferences.presentationAutoMirrorEnabled ? mirrors.current() : nil)
    }

    // The bar was expanded while presenting: say how many apps stay hidden anyway.
    // Never which: the room sees this note.
    func barExpanded() {
        let sensitive = Preferences.presentationSensitiveApps
        guard engine.currentPhase() == .presenting, !sensitive.isEmpty, let button = arrowButton() else { return }
        let view = PresentationNoteView(count: sensitive.count)
        let popover = makePopover(view)
        note?.close()
        note = popover
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        noteTimer?.invalidate()
        noteTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { [weak popover] _ in popover?.close() }
    }

    // MARK: Phase

    private func phaseChanged(_ phase: PresentationPhase) {
        Preferences.presentationModeActive = phase != .off
        switch phase {
        case .off:
            panel?.close()
            note?.close()
            if let item = capsule { NSStatusBar.system.removeStatusItem(item) }
            capsule = nil
        case .presenting, .paused, .couldNotHide:
            let item = capsule ?? makeCapsule()
            item.button?.image = PresentationCapsule.image(for: phase)
            item.button?.setAccessibilityLabel(PresentationCapsule.title(for: phase))
            if panel?.isShown == true { showPanel() }
            if phase == .paused, !pauseExplained {
                pauseExplained = true
                showPanel()
            }
        }
    }

    private func makeCapsule() -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.target = self
        item.button?.action = #selector(capsuleClicked)
        item.button?.sendAction(on: [.leftMouseUp])
        item.button?.imagePosition = .imageOnly
        capsule = item
        return item
    }

    @objc private func capsuleClicked() {
        if panel?.isShown == true { return panel?.close() ?? () }
        showPanel()
    }

    // MARK: Panel

    private func showPanel() {
        guard let button = capsule?.button else { return }
        let phase = engine.currentPhase()
        guard phase != .off else { return }
        let view = PresentationPanelView(model: panelModel(for: phase))
        view.onStop = { [weak self] in
            self?.panel?.close()
            self?.stop()
        }
        view.onHideAgain = { [weak self] in
            self?.panel?.close()
            self?.engine.resumePresentationHiding()
        }
        panel?.close()
        let popover = makePopover(view)
        panel = popover
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    private func makePopover(_ view: NSView) -> NSPopover {
        let controller = NSViewController()
        let size = view.fittingSize
        view.translatesAutoresizingMaskIntoConstraints = true
        view.frame = NSRect(origin: .zero, size: size)
        controller.view = view
        controller.preferredContentSize = size
        let popover = NSPopover()
        popover.contentViewController = controller
        popover.behavior = .transient
        popover.animates = true
        return popover
    }

    private func panelModel(for phase: PresentationPhase) -> PresentationPanelModel {
        let kind: PresentationPanelModel.Kind
        switch phase {
        case .paused: kind = .paused
        case .couldNotHide: kind = .couldNotHide
        case .off, .presenting: kind = .presenting
        }
        return PresentationPanelModel(kind: kind, cause: engine.presentationCause,
                                      hiddenCount: engine.presentationHiddenBundles.count,
                                      sensitiveCount: Preferences.presentationSensitiveApps.count)
    }
}

extension NSMenuItem {
    // Shows a global shortcut beside the item, as the board draws it. The menu
    // only honors it while it is open; the global one is the HotKeyRegistry's.
    func setShortcut(_ shortcut: GlobalKeybindPreferences?) {
        guard let shortcut, let key = shortcut.characters?.lowercased(), key.count == 1 else { return }
        var mask: NSEvent.ModifierFlags = []
        if shortcut.control { mask.insert(.control) }
        if shortcut.option { mask.insert(.option) }
        if shortcut.shift { mask.insert(.shift) }
        if shortcut.command { mask.insert(.command) }
        keyEquivalent = key
        keyEquivalentModifierMask = mask
    }
}
#endif
