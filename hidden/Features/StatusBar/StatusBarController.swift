//
//  StatusBarController.swift
//  vanillaClone
//
//  Created by Thanh Nguyen on 1/30/19.
//  Copyright © 2019 Dwarves Foundation. All rights reserved.
//

import AppKit
import ApplicationServices

class StatusBarController {

    //MARK: - Variables
    private var timer:Timer? = nil

    //MARK: - BarItems

    private let btnExpandCollapse = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let btnSeparate = NSStatusBar.system.statusItem(withLength: 1)
    private var btnAlwaysHidden:NSStatusItem? = nil

    private var btnHiddenLength: CGFloat = 20
    private var btnHiddenCollapseLength: CGFloat = 2000

    private var btnAlwaysHiddenLength: CGFloat = Preferences.alwaysHiddenSectionEnabled ? 20 : 0
    private var btnAlwaysHiddenEnableExpandCollapseLength: CGFloat = Preferences.alwaysHiddenSectionEnabled ? 2000 : 0

    private let imgIconLine = NSImage(named:NSImage.Name("ic_line"))
    private let hiddenItemsBarController = HiddenItemsBarPanelController()
    private let hiddenItemsCaptureShieldController = HiddenItemsBarCaptureShieldController()
    private let hiddenItemsSeparatorOverlayController = HiddenItemsBarSeparatorOverlayController()
    private var activeExpandCollapseFrame: CGRect?
    private var activeStatusItemScreen: NSScreen?
    private var configurationDragMonitor: Any?
    private var isTemporarilyExpandedForConfigurationDrag = false
    private var configurationDragCollapseWorkItem: DispatchWorkItem?

    private var isCollapsed: Bool {
        return self.btnSeparate.length == self.btnHiddenCollapseLength
    }

    private var isSeparateHiddenItemsBarVisible: Bool {
        return self.hiddenItemsBarController.isVisible
    }

    private var isBtnSeparateValidPosition: Bool {
        guard
            let btnExpandCollapseX = self.btnExpandCollapse.button?.getOrigin?.x,
            let btnSeparateX = self.btnSeparate.button?.getOrigin?.x
            else {return false}

        if Constant.isUsingLTRLanguage {
            return btnExpandCollapseX >= btnSeparateX
        } else {
            return btnExpandCollapseX <= btnSeparateX
        }
    }

    private var isBtnAlwaysHiddenValidPosition: Bool {
        if !Preferences.alwaysHiddenSectionEnabled { return true }

        guard
            let btnSeparateX = self.btnSeparate.button?.getOrigin?.x,
            let btnAlwaysHiddenX = self.btnAlwaysHidden?.button?.getOrigin?.x
            else {return false}

        if Constant.isUsingLTRLanguage {
            return btnSeparateX >= btnAlwaysHiddenX
        } else {
            return btnSeparateX <= btnAlwaysHiddenX
        }
    }

    private var isToggle = false

    //MARK: - Methods
    init() {
        updateCollapsedLengths()
        setupUI()
        setupAlwayHideStatusBar()
        setupConfigurationDragMonitor()
        NotificationCenter.default.addObserver(self, selector: #selector(handleScreenParametersChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handlePreferencesChanged), name: .prefsChanged, object: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: {
            self.collapseMenuBar()
        })

        if Preferences.areSeparatorsHidden {hideSeparators()}
        autoCollapseIfNeeded()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        if let configurationDragMonitor = configurationDragMonitor {
            NSEvent.removeMonitor(configurationDragMonitor)
        }
    }

    @objc private func handleScreenParametersChanged() {
        activeExpandCollapseFrame = nil
        activeStatusItemScreen = nil
        updateCollapsedLengths()
    }

    private func updateCollapsedLengths() {
        let screenWidth = NSScreen.main?.visibleFrame.width ?? 1728
        // Keep collapse length bounded to avoid pathological layout/memory behavior
        // on newer macOS versions while still fully hiding the trailing section.
        let boundedCollapseLength = max(500, min(screenWidth + 200, 4000))
        btnHiddenCollapseLength = boundedCollapseLength
        btnAlwaysHiddenEnableExpandCollapseLength = Preferences.alwaysHiddenSectionEnabled ? boundedCollapseLength : 0
    }

    @objc private func handlePreferencesChanged() {
        if !Preferences.showHiddenItemsInSeparateBar {
            hiddenItemsBarController.hide()
            hiddenItemsSeparatorOverlayController.hide()
            if let button = btnExpandCollapse.button {
                button.image = isCollapsed ? Assets.expandImage : Assets.collapseImage
            }
        }
        updateAutoCollapseMenuTitle()
        autoCollapseIfNeeded()
    }

    private func setupUI() {
        if let button = btnSeparate.button {
            button.image = self.imgIconLine
        }
        let menu = self.getContextMenu()
        btnSeparate.menu = menu

        updateAutoCollapseMenuTitle()

        if let button = btnExpandCollapse.button {
            button.image = Assets.collapseImage
            button.target = self

            button.action = #selector(self.btnExpandCollapsePressed(sender:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        btnExpandCollapse.autosaveName = "hiddenbar_expandcollapse";
        btnSeparate.autosaveName = "hiddenbar_separate";
    }

    @objc func btnExpandCollapsePressed(sender: NSStatusBarButton) {
        activeExpandCollapseFrame = sender.window?.frame
        activeStatusItemScreen = sender.window?.screen

        if let event = NSApp.currentEvent {

            let isOptionKeyPressed = event.modifierFlags.contains(NSEvent.ModifierFlags.option)

            if event.type == NSEvent.EventType.leftMouseUp && !isOptionKeyPressed{
                self.expandCollapseIfNeeded()
            } else {
                self.showHideSeparatorsAndAlwayHideArea()
            }
        }
    }

    func showHideSeparatorsAndAlwayHideArea() {
        Preferences.areSeparatorsHidden ? self.showSeparators() : self.hideSeparators()

        if self.isCollapsed {self.expandMenubar()}
    }

    private func showSeparators() {
        Preferences.areSeparatorsHidden = false

        if !self.isCollapsed {
            self.btnSeparate.length = self.btnHiddenLength
        }
        self.btnAlwaysHidden?.length = self.btnAlwaysHiddenLength
    }

    private func hideSeparators() {
        guard self.isBtnAlwaysHiddenValidPosition else {return}

        Preferences.areSeparatorsHidden = true
        hiddenItemsSeparatorOverlayController.hide()

        if !self.isCollapsed {
            self.btnSeparate.length = self.btnHiddenLength
        }
        self.btnAlwaysHidden?.length = self.btnAlwaysHiddenEnableExpandCollapseLength
    }

    func expandCollapseIfNeeded() {
        //prevented rapid click cause icon show many in Dock
        if isToggle {return}
        isToggle = true
        if self.isSeparateHiddenItemsBarVisible {
            self.collapseMenuBar()
        } else if self.isCollapsed && Preferences.showHiddenItemsInSeparateBar {
            self.expandHiddenItemsBar()
        } else {
            self.isCollapsed ? self.expandMenubar() : self.collapseMenuBar()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.isToggle = false
        }
    }

    private func collapseMenuBar() {
        hiddenItemsCaptureShieldController.hide()
        hiddenItemsBarController.hide()
        hiddenItemsSeparatorOverlayController.hide()

        guard self.isBtnSeparateValidPosition && !self.isCollapsed else {
            if !self.isBtnSeparateValidPosition {
                restoreInlineMenuBarAfterInvalidSeparatePosition()
                return
            }
            timer?.invalidate()
            autoCollapseIfNeeded()
            if let button = btnExpandCollapse.button {
                button.image = Assets.expandImage
            }
            return
        }

        btnSeparate.length = self.btnHiddenCollapseLength
        if let button = btnExpandCollapse.button {
            button.image = Assets.expandImage
        }
        if Preferences.useFullStatusBarOnExpandEnabled {
            NSApp.setActivationPolicy(.accessory)
            NSApp.deactivate()
        }
    }
    private func expandMenubar(force: Bool = false) {
        guard self.isCollapsed || force else {return}
        hiddenItemsCaptureShieldController.hide()
        hiddenItemsBarController.hide()
        hiddenItemsSeparatorOverlayController.hide()
        btnSeparate.length = btnHiddenLength
        if let button = btnExpandCollapse.button {
            button.image = Assets.collapseImage
        }
        autoCollapseIfNeeded()

        if Preferences.useFullStatusBarOnExpandEnabled {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)

        }
    }

    private func autoCollapseIfNeeded() {
        guard Preferences.isAutoHide else {return}
        guard !isCollapsed || isSeparateHiddenItemsBarVisible else { return }

        startTimerToAutoHide()
    }

    private func startTimerToAutoHide() {
        timer?.invalidate()
        self.timer = Timer.scheduledTimer(withTimeInterval: Preferences.numberOfSecondForAutoHide, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                if Preferences.isAutoHide {
                    self?.collapseMenuBar()
                }
            }
        }
    }

    private func getContextMenu() -> NSMenu {
        let menu = NSMenu()

        let prefItem = NSMenuItem(title: "Preferences...".localized, action: #selector(openPreferenceViewControllerIfNeeded), keyEquivalent: "P")
        prefItem.target = self
        menu.addItem(prefItem)

        let toggleAutoHideItem = NSMenuItem(title: "Toggle Auto Collapse".localized, action: #selector(toggleAutoHide), keyEquivalent: "t")
        toggleAutoHideItem.target = self
        toggleAutoHideItem.tag = 1
        NotificationCenter.default.addObserver(self, selector: #selector(updateAutoHide), name: .prefsChanged, object: nil)
        menu.addItem(toggleAutoHideItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit".localized, action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        return menu
    }

    private func updateAutoCollapseMenuTitle() {
        guard let toggleAutoHideItem = btnSeparate.menu?.item(withTag: 1) else { return }
        if Preferences.isAutoHide {
            toggleAutoHideItem.title = "Disable Auto Collapse".localized
        } else {
            toggleAutoHideItem.title = "Enable Auto Collapse".localized
        }
    }

    @objc func updateAutoHide() {
        handlePreferencesChanged()
    }

    @objc func openPreferenceViewControllerIfNeeded() {
        Util.showPrefWindow()
    }

    @objc func toggleAutoHide() {
        Preferences.isAutoHide.toggle()
    }
}

//MARK: - Configuration drag support
extension StatusBarController {
    private func setupConfigurationDragMonitor() {
        configurationDragMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged, .leftMouseUp]) { [weak self] event in
            DispatchQueue.main.async {
                self?.handleConfigurationDragEvent(event)
            }
        }
    }

    private func handleConfigurationDragEvent(_ event: NSEvent?) {
        guard let event = event else { return }

        switch event.type {
        case .leftMouseDragged:
            guard event.modifierFlags.contains(.command) else { return }
            temporarilyExpandForConfigurationDragIfNeeded()
        case .leftMouseUp:
            collapseAfterConfigurationDragIfNeeded()
        default:
            break
        }
    }

    private func temporarilyExpandForConfigurationDragIfNeeded() {
        guard
            Preferences.showHiddenItemsInSeparateBar,
            !Preferences.areSeparatorsHidden,
            isCollapsed
        else {
            return
        }

        configurationDragCollapseWorkItem?.cancel()
        hiddenItemsCaptureShieldController.hide()
        hiddenItemsBarController.hide()
        hiddenItemsSeparatorOverlayController.hide()
        btnSeparate.length = btnHiddenLength
        isTemporarilyExpandedForConfigurationDrag = true

        if let button = btnExpandCollapse.button {
            button.image = Assets.collapseImage
        }
    }

    private func collapseAfterConfigurationDragIfNeeded() {
        guard isTemporarilyExpandedForConfigurationDrag else { return }

        configurationDragCollapseWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.isTemporarilyExpandedForConfigurationDrag = false
            self.forceCollapseAfterConfigurationDrag()
        }
        configurationDragCollapseWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: workItem)
    }

    private func forceCollapseAfterConfigurationDrag() {
        hiddenItemsCaptureShieldController.hide()
        hiddenItemsBarController.hide()
        hiddenItemsSeparatorOverlayController.hide()
        btnSeparate.length = btnHiddenCollapseLength

        if let button = btnExpandCollapse.button {
            button.image = Assets.expandImage
        }
    }
}

//MARK: - Separate hidden items bar
extension StatusBarController {
    private enum SeparateBarTiming {
        static let shieldSettleDelay: DispatchTimeInterval = .milliseconds(40)
        static let captureDelay: DispatchTimeInterval = .milliseconds(80)
        static let showDelayAfterCollapse: DispatchTimeInterval = .milliseconds(160)
    }

    private func expandHiddenItemsBar() {
        guard self.isCollapsed else { return }
        guard self.isBtnSeparateValidPosition else {
            restoreInlineMenuBarAfterInvalidSeparatePosition()
            return
        }
        guard self.canCaptureScreenForSeparatePanel() else {
            self.expandMenubar()
            return
        }
        guard let expandCollapseGeometry = currentExpandCollapseGeometry() else { return }

        timer?.invalidate()
        hiddenItemsCaptureShieldController.show(
            on: expandCollapseGeometry.screen,
            near: expandCollapseGeometry.frame,
            covering: btnSeparate.button?.window?.frame
        )

        DispatchQueue.main.asyncAfter(deadline: .now() + SeparateBarTiming.shieldSettleDelay) { [weak self] in
            guard let self = self else { return }
            guard Preferences.showHiddenItemsInSeparateBar else {
                self.hiddenItemsCaptureShieldController.hide()
                self.collapseMenuBar()
                return
            }

            self.btnSeparate.length = self.btnHiddenLength
            if let button = self.btnExpandCollapse.button {
                button.image = Assets.collapseImage
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + SeparateBarTiming.captureDelay) { [weak self] in
                guard let self = self else { return }
                guard Preferences.showHiddenItemsInSeparateBar else {
                    self.hiddenItemsCaptureShieldController.hide()
                    self.collapseMenuBar()
                    return
                }

                guard let capture = self.captureExpandedHiddenItems() else {
                    self.hiddenItemsCaptureShieldController.hide()
                    self.expandMenubar(force: true)
                    return
                }

                guard self.collapseMenuBarForSeparatePanel() else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + SeparateBarTiming.showDelayAfterCollapse) { [weak self] in
                    guard let self = self else { return }
                    self.hiddenItemsCaptureShieldController.hide()
                    guard Preferences.showHiddenItemsInSeparateBar && self.isBtnSeparateValidPosition else {
                        if !self.isBtnSeparateValidPosition {
                            self.restoreInlineMenuBarAfterInvalidSeparatePosition()
                        }
                        return
                    }
                    let capture = self.captureByCoveringItemsStillVisibleInMenuBar(capture)

                    self.hiddenItemsBarController.show(capture: capture) { [weak self] sourceX in
                        self?.activateHiddenItem(atSourceX: sourceX, from: capture)
                    }
                    self.hiddenItemsSeparatorOverlayController.show(
                        frame: capture.menuBarOverlayFrame,
                        separatorFrame: capture.separatorFrame,
                        prefersDarkBackground: capture.prefersDarkBackground
                    )
                    if let button = self.btnExpandCollapse.button {
                        button.image = Assets.collapseImage
                    }
                    self.autoCollapseIfNeeded()
                }
            }
        }
    }

    private func canCaptureScreenForSeparatePanel() -> Bool {
        if #available(OSX 10.15, *) {
            guard CGPreflightScreenCaptureAccess() else {
                CGRequestScreenCaptureAccess()
                return false
            }
        }
        return true
    }

    private func collapseMenuBarForSeparatePanel() -> Bool {
        hiddenItemsBarController.hide()
        guard self.isBtnSeparateValidPosition else {
            restoreInlineMenuBarAfterInvalidSeparatePosition()
            return false
        }
        btnSeparate.length = btnHiddenCollapseLength
        if let button = btnExpandCollapse.button {
            button.image = Assets.expandImage
        }
        if Preferences.useFullStatusBarOnExpandEnabled {
            NSApp.setActivationPolicy(.accessory)
            NSApp.deactivate()
        }
        return true
    }

    private func restoreInlineMenuBarAfterInvalidSeparatePosition() {
        timer?.invalidate()
        hiddenItemsCaptureShieldController.hide()
        hiddenItemsBarController.hide()
        hiddenItemsSeparatorOverlayController.hide()
        btnSeparate.length = btnHiddenLength
        if let button = btnExpandCollapse.button {
            button.image = Assets.collapseImage
        }

        if Preferences.useFullStatusBarOnExpandEnabled {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func captureExpandedHiddenItems() -> HiddenItemsBarCapture? {
        guard let windowList = menuBarWindowList() else { return nil }

        for screen in preferredCaptureScreens() {
            guard
                let separatorQuartzRect = statusItemQuartzRect(named: "hiddenbar_separate", statusItem: btnSeparate, from: windowList, on: screen),
                let expandCollapseQuartzRect = statusItemQuartzRect(named: "hiddenbar_expandcollapse", statusItem: btnExpandCollapse, from: windowList, on: screen)
            else { continue }

            let items = captureVisibleHiddenSectionItems(
                from: windowList,
                separatorQuartzRect: separatorQuartzRect,
                expandCollapseQuartzRect: expandCollapseQuartzRect,
                on: screen
            )
            if !items.isEmpty {
                let separatorFrame = appKitRectFromQuartzRect(separatorQuartzRect, on: screen)
                return HiddenItemsBarCapture(
                    items: items,
                    screen: screen,
                    separatorFrame: separatorFrame,
                    menuBarOverlayFrame: menuBarOverlayFrame(
                        for: separatorFrame,
                        covering: [],
                        on: screen
                    ),
                    prefersDarkBackground: prefersDarkBackground(for: items)
                )
            }
        }

        return nil
    }

    private func captureVisibleHiddenSectionItems(from windowList: [[String: Any]], separatorQuartzRect: CGRect, expandCollapseQuartzRect: CGRect, on screen: NSScreen) -> [HiddenItemsBarItem] {
        let capturedItems = windowList.compactMap { info -> (item: HiddenItemsBarItem, quartzRect: CGRect)? in
            guard
                let windowNumber = info[kCGWindowNumber as String] as? Int,
                let quartzRect = visibleMenuBarItemQuartzRect(from: info, on: screen),
                let image = CGWindowListCreateImage(
                    .null,
                    [.optionIncludingWindow],
                    CGWindowID(windowNumber),
                    [.boundsIgnoreFraming, .bestResolution]
                )
            else {
                return nil
            }

            let appKitRect = appKitRectFromQuartzRect(quartzRect, on: screen)
            return (
                item: HiddenItemsBarItem(
                    image: NSImage(cgImage: image, size: appKitRect.size),
                    sourceRect: appKitRect,
                    windowNumber: windowNumber
                ),
                quartzRect: quartzRect
            )
        }
        .sorted { $0.item.sourceRect.minX < $1.item.sourceRect.minX }

        let hiddenSectionItems = capturedItems.filter {
            hiddenSectionCandidateLocation(
                $0.quartzRect,
                separatorQuartzRect: separatorQuartzRect,
                expandCollapseQuartzRect: expandCollapseQuartzRect
            ) != nil
        }

        if !hiddenSectionItems.isEmpty {
            return hiddenSectionItems.map { $0.item }
        }

        return []
    }

    private func captureByCoveringItemsStillVisibleInMenuBar(_ capture: HiddenItemsBarCapture) -> HiddenItemsBarCapture {
        guard let windowList = menuBarWindowList() else { return capture }

        let visibleRectsByWindowNumber = Dictionary(uniqueKeysWithValues: windowList.compactMap { info -> (Int, CGRect)? in
            guard
                let windowNumber = info[kCGWindowNumber as String] as? Int,
                let quartzRect = visibleMenuBarItemQuartzRect(from: info, on: capture.screen)
            else {
                return nil
            }

            return (windowNumber, appKitRectFromQuartzRect(quartzRect, on: capture.screen))
        })
        let visibleCapturedRects = capture.items.compactMap { visibleRectsByWindowNumber[$0.windowNumber] }
        guard !visibleCapturedRects.isEmpty else { return capture }

        return HiddenItemsBarCapture(
            items: capture.items,
            screen: capture.screen,
            separatorFrame: capture.separatorFrame,
            menuBarOverlayFrame: menuBarOverlayFrame(
                for: capture.separatorFrame,
                covering: visibleCapturedRects,
                on: capture.screen
            ),
            prefersDarkBackground: capture.prefersDarkBackground
        )
    }

    private func prefersDarkBackground(for items: [HiddenItemsBarItem]) -> Bool {
        var luminanceTotal: CGFloat = 0
        var sampleCount: CGFloat = 0

        for item in items {
            guard let cgImage = item.image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { continue }
            let bitmap = NSBitmapImageRep(cgImage: cgImage)
            let xStep = max(1, bitmap.pixelsWide / 8)
            let yStep = max(1, bitmap.pixelsHigh / 8)

            stride(from: 0, to: bitmap.pixelsWide, by: xStep).forEach { x in
                stride(from: 0, to: bitmap.pixelsHigh, by: yStep).forEach { y in
                    guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB),
                          color.alphaComponent > 0.2
                    else {
                        return
                    }

                    luminanceTotal += 0.2126 * color.redComponent + 0.7152 * color.greenComponent + 0.0722 * color.blueComponent
                    sampleCount += 1
                }
            }
        }

        guard sampleCount > 0 else { return false }
        return (luminanceTotal / sampleCount) > 0.55
    }

    private func menuBarOverlayFrame(for separatorFrame: CGRect, covering itemFrames: [CGRect], on screen: NSScreen) -> CGRect {
        let menuBarHeight = max(22, screen.frame.maxY - screen.visibleFrame.maxY)
        let minX = max(
            screen.frame.minX,
            itemFrames.reduce(separatorFrame.minX) { min($0, $1.minX) }
        )
        let maxX = min(
            screen.frame.maxX,
            itemFrames.reduce(separatorFrame.maxX) { max($0, $1.maxX) }
        )
        let width = max(btnHiddenLength, maxX - minX)

        return CGRect(
            x: minX,
            y: screen.frame.maxY - menuBarHeight,
            width: width,
            height: menuBarHeight
        )
    }

    private func menuBarWindowList() -> [[String: Any]]? {
        CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
    }

    private func visibleMenuBarItemQuartzRect(from info: [String: Any], on screen: NSScreen) -> CGRect? {
        let currentProcessID = ProcessInfo.processInfo.processIdentifier
        let screenQuartzRect = quartzRectFromAppKitRect(screen.frame)
        let menuBarHeight = max(22, screen.frame.maxY - screen.visibleFrame.maxY)
        let maxMenuBarQuartzY = screenQuartzRect.minY + menuBarHeight + 6
        let appBundleIdentifier = Bundle.main.bundleIdentifier

        guard
            (info[kCGWindowOwnerPID as String] as? Int32) != currentProcessID,
            !isHiddenBarStatusWindow(info, appBundleIdentifier: appBundleIdentifier),
            let layer = info[kCGWindowLayer as String] as? Int,
            layer == 25,
            let bounds = info[kCGWindowBounds as String] as? [String: Any],
            let quartzRect = rectFromWindowBounds(bounds),
            quartzRect.intersects(screenQuartzRect),
            quartzRect.minY >= screenQuartzRect.minY - 1,
            quartzRect.minY <= maxMenuBarQuartzY,
            quartzRect.height > 4,
            quartzRect.width > 4
        else {
            return nil
        }

        return quartzRect
    }

    private enum HiddenSectionCandidateLocation {
        case hiddenSection
    }

    private func hiddenSectionCandidateLocation(_ quartzRect: CGRect, separatorQuartzRect: CGRect, expandCollapseQuartzRect: CGRect) -> HiddenSectionCandidateLocation? {
        if expandCollapseQuartzRect.minX >= separatorQuartzRect.minX {
            if quartzRect.maxX <= separatorQuartzRect.minX + 1 {
                return .hiddenSection
            }
        } else {
            if quartzRect.minX >= separatorQuartzRect.maxX - 1 {
                return .hiddenSection
            }
        }

        return nil
    }

    private func preferredCaptureScreens() -> [NSScreen] {
        let preferred = btnExpandCollapse.button?.window?.screen ?? activeStatusItemScreen ?? NSScreen.main
        guard let first = preferred else { return NSScreen.screens }

        return [first] + NSScreen.screens.filter { $0 !== first }
    }

    private func currentExpandCollapseGeometry() -> (frame: CGRect, screen: NSScreen)? {
        if
            let frame = btnExpandCollapse.button?.window?.frame,
            let screen = btnExpandCollapse.button?.window?.screen
        {
            return (frame, screen)
        }

        guard let frame = activeExpandCollapseFrame else { return nil }
        let screen = activeStatusItemScreen
            ?? NSScreen.screens.first { $0.frame.intersects(frame) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let resolvedScreen = screen else { return nil }
        return (frame, resolvedScreen)
    }

    private func statusItemQuartzRect(named name: String, statusItem: NSStatusItem, from windowList: [[String: Any]], on screen: NSScreen) -> CGRect? {
        let screenQuartzRect = quartzRectFromAppKitRect(screen.frame)
        let menuBarQuartzRect = quartzMenuBarRect(on: screen)
        let appBundleIdentifier = Bundle.main.bundleIdentifier

        let namedWindows = windowList.compactMap { info -> CGRect? in
            guard
                (info[kCGWindowName as String] as? String) == name,
                let quartzRect = statusItemWindowQuartzRect(from: info, screenQuartzRect: screenQuartzRect, menuBarQuartzRect: menuBarQuartzRect)
            else {
                return nil
            }

            return quartzRect
        }
        if let namedWindow = namedWindows.sorted(by: { $0.minX < $1.minX }).first {
            return namedWindow
        }

        guard let expectedFrame = statusItem.button?.window?.frame else { return nil }
        let expectedQuartzRect = quartzRectFromAppKitRect(expectedFrame)
        let bundleWindows = windowList.compactMap { info -> CGRect? in
            guard
                let title = info[kCGWindowName as String] as? String,
                title == appBundleIdentifier || title.hasPrefix("hiddenbar_"),
                let quartzRect = statusItemWindowQuartzRect(from: info, screenQuartzRect: screenQuartzRect, menuBarQuartzRect: menuBarQuartzRect)
            else {
                return nil
            }

            return quartzRect
        }

        return bundleWindows.sorted {
            statusItemMatchScore($0, expectedQuartzRect: expectedQuartzRect) < statusItemMatchScore($1, expectedQuartzRect: expectedQuartzRect)
        }.first
    }

    private func statusItemWindowQuartzRect(from info: [String: Any], screenQuartzRect: CGRect, menuBarQuartzRect: CGRect) -> CGRect? {
        guard
            let layer = info[kCGWindowLayer as String] as? Int,
            layer == 25,
            let bounds = info[kCGWindowBounds as String] as? [String: Any],
            let quartzRect = rectFromWindowBounds(bounds),
            quartzRect.intersects(screenQuartzRect),
            quartzRect.intersects(menuBarQuartzRect)
        else {
            return nil
        }

        return quartzRect
    }

    private func statusItemMatchScore(_ quartzRect: CGRect, expectedQuartzRect: CGRect) -> CGFloat {
        let centerDistance = abs(quartzRect.midX - expectedQuartzRect.midX) + abs(quartzRect.midY - expectedQuartzRect.midY)
        let sizeDistance = abs(quartzRect.width - expectedQuartzRect.width) + abs(quartzRect.height - expectedQuartzRect.height)
        return centerDistance + sizeDistance
    }

    private func quartzMenuBarRect(on screen: NSScreen) -> CGRect {
        let screenQuartzRect = quartzRectFromAppKitRect(screen.frame)
        let menuBarHeight = max(22, screen.frame.maxY - screen.visibleFrame.maxY)
        return CGRect(
            x: screenQuartzRect.minX,
            y: screenQuartzRect.minY - 2,
            width: screen.frame.width,
            height: menuBarHeight + 4
        )
    }

    private func isHiddenBarStatusWindow(_ info: [String: Any], appBundleIdentifier: String?) -> Bool {
        let title = info[kCGWindowName as String] as? String
        return title == appBundleIdentifier || title?.hasPrefix("hiddenbar_") == true
    }

    private func rectFromWindowBounds(_ bounds: [String: Any]) -> CGRect? {
        guard
            let x = bounds["X"] as? NSNumber,
            let y = bounds["Y"] as? NSNumber,
            let width = bounds["Width"] as? NSNumber,
            let height = bounds["Height"] as? NSNumber
        else {
            return nil
        }
        return CGRect(
            x: CGFloat(truncating: x),
            y: CGFloat(truncating: y),
            width: CGFloat(truncating: width),
            height: CGFloat(truncating: height)
        )
    }

    private func appKitRectFromQuartzRect(_ quartzRect: CGRect, on screen: NSScreen) -> CGRect {
        let referenceMaxY = NSScreen.main?.frame.maxY ?? screen.frame.maxY
        return CGRect(
            x: quartzRect.minX,
            y: referenceMaxY - quartzRect.maxY,
            width: quartzRect.width,
            height: quartzRect.height
        )
    }

    private func quartzRectFromAppKitRect(_ appKitRect: CGRect) -> CGRect {
        let referenceMaxY = NSScreen.main?.frame.maxY ?? appKitRect.maxY
        return CGRect(
            x: appKitRect.minX,
            y: referenceMaxY - appKitRect.maxY,
            width: appKitRect.width,
            height: appKitRect.height
        )
    }

    private func activateHiddenItem(atSourceX sourceX: CGFloat, from capture: HiddenItemsBarCapture) {
        guard canForwardClicksToMenuBarItems() else { return }

        hiddenItemsBarController.hide()
        hiddenItemsSeparatorOverlayController.hide()
        btnSeparate.length = btnHiddenLength
        if let button = btnExpandCollapse.button {
            button.image = Assets.collapseImage
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            guard let self = self else { return }
            let clickPoint = CGPoint(
                x: sourceX,
                y: capture.items.first(where: { $0.sourceRect.minX <= sourceX && sourceX <= $0.sourceRect.maxX })?.sourceRect.midY ?? capture.screen.frame.maxY - 12
            )
            self.postClick(at: clickPoint)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                self?.collapseMenuBar()
            }
        }
    }

    private func postClick(at appKitPoint: CGPoint) {
        let referenceMaxY = NSScreen.main?.frame.maxY ?? appKitPoint.y
        let eventPoint = CGPoint(x: appKitPoint.x, y: referenceMaxY - appKitPoint.y)
        guard
            let mouseDown = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: eventPoint, mouseButton: .left),
            let mouseUp = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: eventPoint, mouseButton: .left)
        else { return }

        mouseDown.post(tap: CGEventTapLocation.cghidEventTap)
        mouseUp.post(tap: CGEventTapLocation.cghidEventTap)
    }

    private func canForwardClicksToMenuBarItems() -> Bool {
        guard !AXIsProcessTrusted() else { return true }

        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        return false
    }
}


//MARK: - Alway hide feature
extension StatusBarController {
    private func setupAlwayHideStatusBar() {
        NotificationCenter.default.addObserver(self, selector: #selector(toggleStatusBarIfNeeded), name: .alwayHideToggle, object: nil)
        toggleStatusBarIfNeeded()
    }
    @objc private func toggleStatusBarIfNeeded() {
        updateCollapsedLengths()

        if Preferences.alwaysHiddenSectionEnabled {
            if let existing = self.btnAlwaysHidden {
                NSStatusBar.system.removeStatusItem(existing)
            }
            self.btnAlwaysHidden = NSStatusBar.system.statusItem(withLength: btnAlwaysHiddenLength)
            if let button = btnAlwaysHidden?.button {
                button.image = self.imgIconLine
                button.appearsDisabled = true
            }
            self.btnAlwaysHidden?.autosaveName = "hiddenbar_terminate"
        } else {
            if let existing = self.btnAlwaysHidden {
                NSStatusBar.system.removeStatusItem(existing)
            }
            self.btnAlwaysHidden = nil
        }
    }
}
