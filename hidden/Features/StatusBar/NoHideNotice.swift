//
//  NoHideNotice.swift
//  Hidden Bar
//
//  Copyright © 2026 Console Labs. All rights reserved.
//

import AppKit

// A click on the arrow that ends with nothing hidden used to say nothing; the
// engine knew why and only wrote it to the log. This is the one short notice
// under the arrow that says why and what to do. The decisions are plain values
// so a test reads them; the popover is direct-build only, like the engine.

protocol NoHideNoticePresenting: AnyObject {
    var isShown: Bool { get }
    // False when the notice could not be put up (no arrow on screen).
    @discardableResult
    func show(_ reason: NoHideReason, from button: NSStatusBarButton?) -> Bool
    func close()
}

// Manual requests only: a timer attempt retries on its own and the user did not
// ask. Once per reason per launch, and never over a notice that is still up.
struct NoHideNoticePolicy {
    private var shown: Set<NoHideReason.Kind> = []

    func shouldShow(_ reason: NoHideReason, userInitiated: Bool, isNoticeShowing: Bool) -> Bool {
        return userInitiated && !isNoticeShowing && !shown.contains(reason.kind)
    }

    mutating func recordShown(_ reason: NoHideReason) {
        shown.insert(reason.kind)
    }
}

struct NoHideNoticeModel: Equatable {
    enum Action: Equatable {
        case moveToApplications
        case openSettings(SettingsTab)
    }

    let title: String
    let text: String
    let action: Action?

    var buttonTitle: String? {
        switch action {
        case .moveToApplications: return "Move to Applications".localized
        case .openSettings: return "Open Settings…".localized
        case nil: return nil
        }
    }

    // The status card's words where the card already says it.
    static func make(_ reason: NoHideReason, runningFolder: String) -> NoHideNoticeModel {
        switch reason {
        case .outsideApplications:
            return NoHideNoticeModel(
                title: "Move Hidden Bar to Applications".localized,
                text: String(format: "It is running from %@. macOS 27 hides icons only for apps in the Applications folder, so nothing is hidden yet.".localized,
                             runningFolder),
                action: .moveToApplications)
        case .unkeepableIcons(let names):
            let list = names.isEmpty ? "icons with no name".localized : ListFormatter.localizedString(byJoining: names)
            return NoHideNoticeModel(
                title: "Hiding is paused".localized,
                text: String(format: "macOS hides these icons whatever Hidden Bar allows: %@. They sit right of the arrow, so the pause switch in Advanced keeps everything visible while they are there.".localized,
                             list),
                action: .openSettings(.advanced))
        case .accessibilityNeeded:
            return NoHideNoticeModel(
                title: "Hidden Bar needs Accessibility access".localized,
                text: "macOS 27 lets Hidden Bar hide icons only with this permission. Nothing is hidden until you turn it on.".localized,
                action: .openSettings(.general))
        case .everythingRightOfArrow:
            return NoHideNoticeModel(
                title: "Nothing to hide".localized,
                text: "Every icon is right of the arrow, so there is nothing to hide. Hold Command and drag the arrow to the right of the icons you want to hide.".localized,
                action: nil)
        }
    }
}

#if HIDDENBAR_NATIVE_VISIBILITY

// Same look as the presentation tip: heading, grey text, one prominent button.
final class NoHideNoticeView: NSView {
    static let width: CGFloat = 300
    static let buttonIdentifier = "noHideNoticeButton"
    private static let inset: CGFloat = 12

    var onAction: (() -> Void)?

    init(model: NoHideNoticeModel) {
        super.init(frame: .zero)
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: Self.inset, left: Self.inset, bottom: Self.inset, right: Self.inset)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            widthAnchor.constraint(equalToConstant: Self.width),
        ])
        let heading = NSTextField(wrappingLabelWithString: model.title)
        heading.font = .systemFont(ofSize: 13, weight: .semibold)
        heading.isSelectable = false
        heading.preferredMaxLayoutWidth = Self.width - 2 * Self.inset
        stack.addArrangedSubview(heading)
        let text = NSTextField(wrappingLabelWithString: model.text)
        text.font = .systemFont(ofSize: 12)
        text.textColor = .secondaryLabelColor
        text.isSelectable = false
        text.preferredMaxLayoutWidth = Self.width - 2 * Self.inset
        stack.addArrangedSubview(text)
        guard let title = model.buttonTitle else { return }
        let button = PresentationButton(title: title, style: .prominent, target: self, action: #selector(pressed))
        button.identifier = NSUserInterfaceItemIdentifier(Self.buttonIdentifier)
        stack.setCustomSpacing(10, after: text)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let footer = NSStackView(views: [spacer, button])
        footer.orientation = .horizontal
        footer.translatesAutoresizingMaskIntoConstraints = false
        footer.widthAnchor.constraint(equalToConstant: Self.width - 2 * Self.inset).isActive = true
        stack.addArrangedSubview(footer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    @objc private func pressed() { onAction?() }
}

// A popover under the arrow, like the arrivals prompt: it stays until answered
// or clicked away.
final class ArrowNoticePresenter: NSObject, NSPopoverDelegate, NoHideNoticePresenting {
    private let runningFolder: () -> String
    private let perform: (NoHideNoticeModel.Action) -> Void
    private let showPopover: (NSPopover, NSStatusBarButton) -> Void
    private var popover: NSPopover?

    init(runningFolder: @escaping () -> String = { RunningFolder.displayName(of: Bundle.main.bundleURL) },
         perform: @escaping (NoHideNoticeModel.Action) -> Void = ArrowNoticePresenter.performAction,
         showPopover: @escaping (NSPopover, NSStatusBarButton) -> Void = { popover, button in
             popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
         }) {
        self.runningFolder = runningFolder
        self.perform = perform
        self.showPopover = showPopover
    }

    var isShown: Bool { popover?.isShown ?? false }

    static func performAction(_ action: NoHideNoticeModel.Action) {
        switch action {
        case .moveToApplications:
            AppStoreMigration.shared.offerMoveFromSettings()
        case .openSettings(let tab):
            Util.showPrefWindow()
            PreferencesWindowController.shared.select(tab)
        }
    }

    // An arrow macOS moved into its « button has no screen to hang from; the
    // overflow notice covers that.
    func show(_ reason: NoHideReason, from button: NSStatusBarButton?) -> Bool {
        guard let button, button.window?.screen != nil, !isShown else { return false }
        let model = NoHideNoticeModel.make(reason, runningFolder: runningFolder())
        let view = NoHideNoticeView(model: model)
        let content = NSViewController()
        let size = view.fittingSize
        view.translatesAutoresizingMaskIntoConstraints = true
        view.frame = NSRect(origin: .zero, size: size)
        content.view = view
        content.preferredContentSize = size
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = content
        popover.delegate = self
        view.onAction = { [weak self] in
            self?.close()
            if let action = model.action { self?.perform(action) }
        }
        self.popover = popover
        showPopover(popover, button)
        return true
    }

    func close() {
        popover?.close()
    }

    func popoverDidClose(_ notification: Notification) {
        popover = nil
    }
}

#endif
