//
//  ArrivalsPresenter.swift
//  Hidden Bar
//
//  Copyright © 2026 Dwarves Foundation. All rights reserved.
//

#if HIDDENBAR_NATIVE_VISIBILITY
import AppKit

// The dot on the arrow that says an app is waiting for an answer.
final class ArrivalsArrowDot: NSView {
    static let diameter: CGFloat = 7

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlAccentColor.setFill()
        NSBezierPath(ovalIn: bounds).fill()
    }

    // Puts the dot top-right on `button`, or takes it away.
    static func sync(on button: NSStatusBarButton?, visible: Bool) {
        guard let button else { return }
        let existing = button.subviews.compactMap { $0 as? ArrivalsArrowDot }.first
        guard visible else {
            existing?.removeFromSuperview()
            return
        }
        guard existing == nil else { return }
        let dot = ArrivalsArrowDot(frame: NSRect(x: button.bounds.maxX - diameter - 1, y: 2, width: diameter, height: diameter))
        dot.autoresizingMask = [.minXMargin, .maxYMargin]
        dot.setAccessibilityElement(false)
        button.addSubview(dot)
    }
}

// Asks from the arrow: a popover under it with one row per waiting app. It opens
// when the user clicks the arrow while something waits (the click that shows the
// hidden icons), and it stays until it is answered or clicked away; the dot on
// the arrow stays while anything waits. While presentation mode is on it does not
// open at all: the question names apps, and the room sees the screen. It waits
// for the first arrow click after the mode ends.
final class ArrivalsPresenter: NSObject, NSPopoverDelegate {
    private let controller: ArrivalsController
    private let openSettings: () -> Void
    private let isSuppressed: () -> Bool
    private let showPopover: (NSPopover, NSStatusBarButton) -> Void
    private var popover: NSPopover?
    private var promptView: ArrivalsPromptView?
    private var observer: NSObjectProtocol?

    init(controller: ArrivalsController = .shared,
         isSuppressed: @escaping () -> Bool = { false },
         showPopover: @escaping (NSPopover, NSStatusBarButton) -> Void = { popover, button in
             popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
         },
         openSettings: @escaping () -> Void) {
        self.controller = controller
        self.isSuppressed = isSuppressed
        self.showPopover = showPopover
        self.openSettings = openSettings
        super.init()
        observer = NotificationCenter.default.addObserver(forName: .arrivalsChanged, object: nil, queue: .main) { [weak self] _ in
            // Not inside the button action that caused the change.
            DispatchQueue.main.async { self?.reload() }
        }
    }

    deinit {
        observer.map(NotificationCenter.default.removeObserver)
    }

    var isShown: Bool { popover?.isShown ?? false }

    func present(from button: NSStatusBarButton?) {
        guard let button, !isShown, !isSuppressed(), !controller.pending.isEmpty else { return }
        controller.refresh()
        guard !controller.pending.isEmpty else { return }
        let view = makeView()
        let content = NSViewController()
        content.view = view
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = content
        popover.contentSize = view.fittingContentSize
        popover.delegate = self
        self.popover = popover
        promptView = view
        showPopover(popover, button)
    }

    func close() {
        popover?.close()
    }

    func popoverDidClose(_ notification: Notification) {
        popover = nil
        promptView = nil
    }

    private func makeView() -> ArrivalsPromptView {
        let view = ArrivalsPromptView(model: ArrivalsPromptModel.make(infos: controller.waiting(), now: Date()))
        view.onAnswer = { [weak self] bundle, answer in self?.controller.answer(bundle, answer) }
        view.onAnswerAll = { [weak self] answer in self?.controller.answerAll(answer) }
        view.onOpenSettings = { [weak self] in
            self?.close()
            self?.openSettings()
        }
        return view
    }

    // The queue changed while the popover is open: redraw it, or close it when it is empty.
    private func reload() {
        guard let popover, let promptView else { return }
        guard !controller.pending.isEmpty else { return popover.close() }
        promptView.update(ArrivalsPromptModel.make(infos: controller.waiting(), now: Date()))
        popover.contentSize = promptView.fittingContentSize
    }
}
#endif
