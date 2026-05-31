//
//  HiddenItemsBarPanelController.swift
//  Hidden Bar
//
//  Copyright © 2026 Dwarves Foundation. All rights reserved.
//

import AppKit

struct HiddenItemsBarCapture {
    let items: [HiddenItemsBarItem]
    let screen: NSScreen
}

struct HiddenItemsBarItem {
    let image: NSImage
    let sourceRect: CGRect
}

final class HiddenItemsBarPanelController: NSObject {
    private let panel: NSPanel
    private let scrollView: NSScrollView
    private let contentView: HiddenItemsBarView

    var isVisible: Bool {
        panel.isVisible
    }

    override init() {
        contentView = HiddenItemsBarView(frame: .zero)
        scrollView = NSScrollView(frame: .zero)
        panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        super.init()

        scrollView.documentView = contentView
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay

        panel.contentView = scrollView
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.ignoresMouseEvents = false
    }

    func show(capture: HiddenItemsBarCapture, clickHandler: @escaping (CGFloat) -> Void) {
        contentView.configure(items: capture.items, clickHandler: clickHandler)

        let contentSize = contentView.preferredContentSize
        let panelWidth = max(160, min(contentSize.width, capture.screen.visibleFrame.width - 16))
        let needsHorizontalScroll = contentSize.width > panelWidth
        let scrollerHeight = needsHorizontalScroll ? NSScroller.scrollerWidth(for: .regular, scrollerStyle: .overlay) : 0
        let panelHeight = max(28, contentSize.height + scrollerHeight)
        let screenFrame = capture.screen.frame
        let visibleFrame = capture.screen.visibleFrame
        let itemsMidX = capture.items.reduce(0) { $0 + $1.sourceRect.midX } / CGFloat(max(capture.items.count, 1))
        let centeredX = itemsMidX - panelWidth / 2
        let minX = screenFrame.minX + 8
        let maxX = screenFrame.maxX - panelWidth - 8
        let panelX = min(max(centeredX, minX), maxX)
        let panelY = max(visibleFrame.maxY - panelHeight - 4, visibleFrame.minY + 8)

        contentView.frame = NSRect(origin: .zero, size: contentSize)
        scrollView.hasHorizontalScroller = needsHorizontalScroll
        scrollView.frame = NSRect(origin: .zero, size: CGSize(width: panelWidth, height: panelHeight))
        panel.setFrame(NSRect(x: panelX, y: panelY, width: panelWidth, height: panelHeight), display: true)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }
}

final class HiddenItemsBarCaptureShieldController: NSObject {
    private let panel: NSPanel

    override init() {
        panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        super.init()

        panel.backgroundColor = .black
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.ignoresMouseEvents = true
    }

    func show(on screen: NSScreen, near expandCollapseFrame: CGRect) {
        let menuBarHeight = max(22, screen.frame.maxY - screen.visibleFrame.maxY)
        let shieldPadding: CGFloat = 12
        let shieldFrame: CGRect

        if Constant.isUsingLTRLanguage {
            let minX = max(screen.frame.minX, expandCollapseFrame.minX - 360)
            shieldFrame = CGRect(
                x: minX,
                y: screen.frame.maxY - menuBarHeight,
                width: max(0, expandCollapseFrame.minX - minX + shieldPadding),
                height: menuBarHeight
            )
        } else {
            let maxX = min(screen.frame.maxX, expandCollapseFrame.maxX + 360)
            shieldFrame = CGRect(
                x: expandCollapseFrame.maxX - shieldPadding,
                y: screen.frame.maxY - menuBarHeight,
                width: max(0, maxX - expandCollapseFrame.maxX + shieldPadding),
                height: menuBarHeight
            )
        }

        guard shieldFrame.width > 1 && shieldFrame.height > 1 else { return }
        panel.setFrame(shieldFrame, display: true)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }
}

final class HiddenItemsBarView: NSView {
    private enum Metrics {
        static let paddingX: CGFloat = 12
        static let paddingY: CGFloat = 5
        static let spacing: CGFloat = 2
        static let minItemHeight: CGFloat = 18
    }

    private var items: [HiddenItemsBarItem] = []
    private var itemRects: [CGRect] = []
    private var clickHandler: ((CGFloat) -> Void)?

    var preferredContentSize: CGSize {
        let itemWidth = items.reduce(CGFloat(0)) { $0 + max($1.image.size.width, 1) }
        let spacingWidth = CGFloat(max(items.count - 1, 0)) * Metrics.spacing
        let itemHeight = items.map { max($0.image.size.height, Metrics.minItemHeight) }.max() ?? Metrics.minItemHeight
        return CGSize(
            width: itemWidth + spacingWidth + Metrics.paddingX * 2,
            height: itemHeight + Metrics.paddingY * 2
        )
    }

    func configure(items: [HiddenItemsBarItem], clickHandler: @escaping (CGFloat) -> Void) {
        self.items = items
        itemRects = []
        self.clickHandler = clickHandler
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let path = NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8)
        NSColor.windowBackgroundColor.withAlphaComponent(0.92).setFill()
        path.fill()

        let strokeColor: NSColor
        if #available(OSX 10.14, *) {
            strokeColor = NSColor.separatorColor
        } else {
            strokeColor = NSColor.lightGray
        }
        strokeColor.withAlphaComponent(0.35).setStroke()
        path.lineWidth = 1
        path.stroke()

        guard !items.isEmpty else {
            drawEmptyState()
            return
        }

        itemRects = layoutItemRects()
        for (index, item) in items.enumerated() {
            guard itemRects.indices.contains(index) else { continue }
            item.image.draw(in: itemRects[index], from: .zero, operation: .sourceOver, fraction: 1)
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard !items.isEmpty else { return }

        let location = convert(event.locationInWindow, from: nil)
        let rects = itemRects.isEmpty ? layoutItemRects() : itemRects
        guard let index = rects.firstIndex(where: { $0.contains(location) }) else { return }
        clickHandler?(items[index].sourceRect.midX)
    }

    private func layoutItemRects() -> [CGRect] {
        let contentSize = preferredContentSize
        var currentX = (bounds.width - (contentSize.width - Metrics.paddingX * 2)) / 2
        let itemHeight = contentSize.height - Metrics.paddingY * 2
        let originY = (bounds.height - itemHeight) / 2

        return items.map { item in
            let size = item.image.size
            let rect = CGRect(
                x: currentX,
                y: originY + (itemHeight - size.height) / 2,
                width: size.width,
                height: size.height
            )
            currentX += size.width + Metrics.spacing
            return rect
        }
    }

    private func drawEmptyState() {
        let text = "Hidden items unavailable".localized
        let attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.secondaryLabelColor,
            .font: NSFont.systemFont(ofSize: 12)
        ]
        let size = text.size(withAttributes: attributes)
        text.draw(
            at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2),
            withAttributes: attributes
        )
    }
}
