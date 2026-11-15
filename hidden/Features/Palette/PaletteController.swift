//
//  PaletteController.swift
//  Hidden Bar
//
//  Copyright © 2026 Dwarves Foundation. All rights reserved.
//

#if HIDDENBAR_NATIVE_VISIBILITY
import AppKit

/// The palette's window: our own panel, so typing needs no key monitor and no
/// permission. It takes keys without making Hidden Bar the active app, so the
/// app the user was in keeps its place, and it closes when it stops being key.
final class PalettePanel: NSPanel {
    var onKey: ((PaletteKeyAction) -> Void)?
    var onResignKey: (() -> Void)?

    init(content: NSView) {
        super.init(contentRect: NSRect(origin: .zero, size: content.fittingSize),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        contentView = content
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Return, Escape and the up and down arrows act on the list; everything
    /// else goes to the search field.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown,
           let action = PaletteKeyAction.resolve(keyCode: event.keyCode, modifiers: event.modifierFlags) {
            onKey?(action)
            return
        }
        super.sendEvent(event)
    }

    override func resignKey() {
        super.resignKey()
        onResignKey?()
    }
}

/// What the palette asks of the rest of the app.
struct PaletteHost {
    var environment: () -> PaletteEnvironment
    /// The arrow's window frame in screen coordinates, nil when it is not on screen.
    var arrowFrame: () -> CGRect?
    /// Allows the app, presses its icon and re-hides it when its menu closes.
    var open: (String, @escaping (PaletteOpenResult) -> Void) -> Void
    var move: (MenuBarSection, String) -> Void
    var openAccessibilitySettings: () -> Void
    var openMenuBarApps: () -> Void
}

/// The type-to-find palette: lists the hidden and always-hidden apps from the
/// catalog, filters as you type, and opens the chosen app's own menu.
final class PaletteController {
    private let host: PaletteHost
    private let catalog: MenuBarItemCatalog
    private let screens: () -> [PaletteScreen]
    private let pointer: () -> CGPoint
    // Tests build the panel and read it but never put a window on the screen.
    private let ordersPanelFront: Bool
    private let notifications: NotificationCenter

    private var model: PaletteModel
    private var openingBundle: String?
    private(set) var panel: PalettePanel?
    private(set) var contentView: PaletteContentView?
    private var catalogObserver: NSObjectProtocol?

    init(host: PaletteHost,
         catalog: MenuBarItemCatalog = .shared,
         screens: @escaping () -> [PaletteScreen] = PaletteController.liveScreens,
         pointer: @escaping () -> CGPoint = { NSEvent.mouseLocation },
         notifications: NotificationCenter = .default,
         ordersPanelFront: Bool = true) {
        self.notifications = notifications
        self.ordersPanelFront = ordersPanelFront
        self.host = host
        self.catalog = catalog
        self.screens = screens
        self.pointer = pointer
        model = PaletteModel(candidates: [], environment: host.environment())
    }

    deinit {
        catalogObserver.map(notifications.removeObserver)
    }

    static func liveScreens() -> [PaletteScreen] {
        return NSScreen.screens.map { PaletteScreen(frame: $0.frame, visibleFrame: $0.visibleFrame) }
    }

    var isVisible: Bool { panel != nil }

    static func candidates(from entries: [MenuBarCatalogEntry]) -> [PaletteCandidate] {
        return entries.map {
            PaletteCandidate(bundleIdentifier: $0.bundleIdentifier, name: $0.name, section: $0.section, isRunning: $0.isRunning)
        }
    }

    // MARK: Showing

    /// The shortcut and the arrow's menu item: open when closed, close when open.
    func toggle() {
        isVisible ? close() : show()
    }

    func show(query: String = "") {
        close()
        // Read again now: the catalog and the permission may have changed since the last open.
        model = PaletteModel(candidates: Self.candidates(from: catalog.entries), environment: host.environment())
        model.setQuery(query)
        openingBundle = nil
        let content = PaletteContentView()
        content.onQueryChange = { [weak self] in self?.queryChanged($0) }
        content.onRowClick = { [weak self] in self?.rowClicked($0) }
        content.onAction = { [weak self] in self?.edgeAction($0) }
        let panel = PalettePanel(content: content)
        panel.onKey = { [weak self] in self?.perform($0) }
        panel.onResignKey = { [weak self] in self?.close() }
        self.panel = panel
        contentView = content
        render()
        if ordersPanelFront {
            panel.makeKeyAndOrderFront(nil)
            panel.makeFirstResponder(content.searchField)
        }
        catalogObserver = notifications.addObserver(forName: .menuBarCatalogChanged, object: nil, queue: .main) { [weak self] _ in
            self?.catalogChanged()
        }
    }

    func close() {
        catalogObserver.map(notifications.removeObserver)
        catalogObserver = nil
        let closing = panel
        panel = nil
        contentView = nil
        openingBundle = nil
        // Detach first: ordering out resigns key, which would call back in.
        closing?.onResignKey = nil
        if ordersPanelFront { closing?.orderOut(nil) }
    }

    // MARK: Input

    func setQuery(_ query: String) {
        model.setQuery(query)
        openingBundle = nil
        render()
    }

    func select(bundle: String) {
        model.select(bundle: bundle)
        render()
    }

    private func queryChanged(_ query: String) {
        model.setQuery(query)
        openingBundle = nil
        render()
    }

    private func rowClicked(_ bundle: String) {
        model.select(bundle: bundle)
        perform(.open)
    }

    private func catalogChanged() {
        model.update(candidates: Self.candidates(from: catalog.entries), environment: host.environment())
        render()
    }

    private func edgeAction(_ action: PaletteEdgeAction) {
        close()
        switch action {
        case .openAccessibilitySettings: host.openAccessibilitySettings()
        case .openMenuBarApps: host.openMenuBarApps()
        }
    }

    func perform(_ action: PaletteKeyAction) {
        switch action {
        case .moveUp:
            model.moveSelection(by: -1)
            render()
        case .moveDown:
            model.moveSelection(by: 1)
            render()
        case .close:
            close()
        case .open:
            open()
        case .keepShown:
            guard host.environment().pinsSections else { return }
            move(to: .visible)
        case .alwaysHide:
            guard host.environment().pinsSections else { return }
            move(to: .alwaysHidden)
        }
    }

    private func move(to section: MenuBarSection) {
        guard let selected = model.selected else { return }
        close()
        host.move(section, selected.bundleIdentifier)
    }

    private func open() {
        guard openingBundle == nil, let selected = model.selected else { return }
        openingBundle = selected.bundleIdentifier
        render()
        host.open(selected.bundleIdentifier) { [weak self] result in
            self?.opened(selected, result)
        }
    }

    private func opened(_ app: PaletteCandidate, _ result: PaletteOpenResult) {
        openingBundle = nil
        switch result {
        case .opened:
            close()
        case .noItem, .noPress:
            model.showCannotOpen(appName: app.name)
            render()
        case .sensitive:
            // Presentation mode started (or the sensitive set changed) while the
            // list was open: drop the app from it without naming it.
            model.update(candidates: model.candidates, environment: host.environment())
            render()
        case .unavailable:
            var environment = host.environment()
            environment.engineAvailable = false
            model.update(candidates: model.candidates, environment: environment)
            render()
        }
    }

    // MARK: Drawing

    private var viewState: PaletteViewState {
        return PaletteViewState(query: model.query, content: model.content, selectedIndex: model.selectedIndex,
                                openingBundle: openingBundle, pinsSections: model.environment.pinsSections)
    }

    private func render() {
        guard let panel, let contentView else { return }
        contentView.apply(viewState, icon: { [catalog] in catalog.entry(for: $0)?.icon })
        contentView.layoutSubtreeIfNeeded()
        let size = contentView.fittingSize
        let frame = PalettePlacement.frame(size: size, arrow: host.arrowFrame(), pointer: pointer(), screens: screens())
        panel.setFrame(frame ?? NSRect(origin: panel.frame.origin, size: size), display: true)
    }

    #if DEBUG
    var debugState: [String: Any] {
        return ["visible": isVisible,
                "query": model.query,
                "content": String(describing: model.content).prefix(200).description,
                "rows": model.rows.map { $0.candidate.bundleIdentifier },
                "selected": model.selected?.bundleIdentifier ?? NSNull(),
                "opening": openingBundle ?? NSNull()]
    }
    #endif
}
#endif
