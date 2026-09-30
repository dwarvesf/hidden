//
//  ViewController.swift
//  vanillaClone
//
//  Created by Thanh Nguyen on 1/24/19.
//  Copyright © 2019 Dwarves Foundation. All rights reserved.
//

import Cocoa
import Carbon
import HotKey
import SwiftUI

// The General tab. The storyboard scene only provides the (empty) view the
// tab controller displays; the content is the SwiftUI settings view below.
class PreferencesViewController: NSViewController {

    private let model = GeneralSettingsModel()
    private lazy var heightConstraint = view.heightAnchor.constraint(equalToConstant: preferredHeight)
    private var shortcutMonitor: Any?

    // The content scrolls for longer translations and smaller displays.
    private var preferredHeight: CGFloat {
        return Util.isAccessibilityPermissionMissing ? 415 : 370
    }

    public var listening = false {
        didSet {
            model.isRecordingShortcut = listening
            if listening {
                startShortcutMonitor()
            } else if let shortcutMonitor {
                NSEvent.removeMonitor(shortcutMonitor)
                self.shortcutMonitor = nil
            }
        }
    }

    //MARK: - VC Life cycle
    override func viewDidLoad() {
        super.viewDidLoad()
        model.onRecordShortcut = { [weak self] in self?.register() }
        model.onClearShortcut = { [weak self] in self?.unregister() }
        model.shortcutTitle = Preferences.globalKey?.description

        let hostingView = NSHostingView(rootView: GeneralSettingsView(model: model))
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.topAnchor.constraint(equalTo: view.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            hostingView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            view.widthAnchor.constraint(equalToConstant: 460),
            heightConstraint
        ])

        NotificationCenter.default.addObserver(model, selector: #selector(GeneralSettingsModel.refresh), name: .prefsChanged, object: nil)
        NotificationCenter.default.addObserver(model, selector: #selector(GeneralSettingsModel.refresh), name: .accessibilityPermissionChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(updateHeight), name: .accessibilityPermissionChanged, object: nil)
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        model.refresh()
        updateHeight()
    }

    @objc private func updateHeight() {
        heightConstraint.constant = preferredHeight
    }

    deinit {
        if let shortcutMonitor { NSEvent.removeMonitor(shortcutMonitor) }
        // Balance the viewDidLoad observers (PRs #335/#346).
        NotificationCenter.default.removeObserver(model)
        NotificationCenter.default.removeObserver(self)
    }

    static func initWithStoryboard() -> PreferencesViewController {
        let vc = NSStoryboard(name:"Main", bundle: nil).instantiateController(withIdentifier: "prefVC") as! PreferencesViewController
        return vc
    }

    //MARK: - Global shortcut
    // Recording goes through the window controller, which forwards keyDown and
    // flagsChanged here while `listening` is set.

    private func register() {
        listening = true
    }

    private func startShortcutMonitor() {
        guard shortcutMonitor == nil else { return }
        shortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self, self.listening, self.view.window?.isKeyWindow == true else { return event }
            if event.type == .flagsChanged {
                self.updateModiferFlags(event)
                return event
            }
            if event.keyCode == 53 { // Escape
                self.cancelShortcutRecording()
            } else {
                self.updateGlobalShortcut(event)
            }
            return nil
        }
    }

    func cancelShortcutRecording() {
        listening = false
    }

    // Clear the shortcut and tell AppDelegate to stop listening to the previous keybind.
    private func unregister() {
        let appDelegate = NSApplication.shared.delegate as! AppDelegate
        appDelegate.hotKey = nil
        model.shortcutTitle = nil
        listening = false

        // Remove globalkey from userdefault
        Preferences.globalKey = nil
    }

    public func updateGlobalShortcut(_ event: NSEvent) {
        self.listening = false

        guard let characters = event.charactersIgnoringModifiers else {return}

        let newGlobalKeybind = GlobalKeybindPreferences(
            function: event.modifierFlags.contains(.function),
            control: event.modifierFlags.contains(.control),
            command: event.modifierFlags.contains(.command),
            shift: event.modifierFlags.contains(.shift),
            option: event.modifierFlags.contains(.option),
            capsLock: event.modifierFlags.contains(.capsLock),
            carbonFlags: event.modifierFlags.carbonFlags,
            characters: characters,
            keyCode: uint32(event.keyCode))

        // Reject unmodified typing without deleting the existing shortcut.
        // Function keys are valid standalone global shortcuts.
        guard newGlobalKeybind.isValidGlobalShortcut else { return }

        Preferences.globalKey = newGlobalKeybind
        model.shortcutTitle = newGlobalKeybind.description

        let appDelegate = NSApplication.shared.delegate as! AppDelegate
        appDelegate.hotKey = HotKey(keyCombo: KeyCombo(carbonKeyCode: UInt32(event.keyCode), carbonModifiers: event.modifierFlags.carbonFlags))
    }

    // Shows the modifiers held so far while recording.
    public func updateModiferFlags(_ event: NSEvent) {
        let newGlobalKeybind = GlobalKeybindPreferences(
            function: event.modifierFlags.contains(.function),
            control: event.modifierFlags.contains(.control),
            command: event.modifierFlags.contains(.command),
            shift: event.modifierFlags.contains(.shift),
            option: event.modifierFlags.contains(.option),
            capsLock: event.modifierFlags.contains(.capsLock),
            carbonFlags: 0,
            characters: nil,
            keyCode: uint32(event.keyCode))

        model.recordingPreview = newGlobalKeybind.description
    }
}

//MARK: - Model

// Reads straight from Preferences, so a change made elsewhere (the context
// menu's auto-collapse toggle, a failed login-item update) shows up on refresh.
final class GeneralSettingsModel: ObservableObject {
    @Published var isRecordingShortcut = false {
        didSet { if !isRecordingShortcut { recordingPreview = "" } }
    }
    @Published var recordingPreview = ""
    @Published var shortcutTitle: String?
    @Published private(set) var isAccessibilityPermissionMissing = Util.isAccessibilityPermissionMissing

    var onRecordShortcut: () -> Void = {}
    var onClearShortcut: () -> Void = {}

    @objc func refresh() {
        isAccessibilityPermissionMissing = Util.isAccessibilityPermissionMissing
        objectWillChange.send()
    }

    func binding(_ get: @escaping () -> Bool, _ set: @escaping (Bool) -> Void) -> Binding<Bool> {
        return Binding(get: get, set: { [weak self] value in
            set(value)
            self?.objectWillChange.send()
        })
    }

    var autoStart: Binding<Bool> {
        return binding({ Preferences.isAutoStart }) { wanted in
            Preferences.isAutoStart = wanted
            // On failure the pref reverts; tell the user why instead of swallowing the error.
            if Preferences.isAutoStart != wanted {
                let alert = NSAlert()
                alert.messageText = "Could not update the login item".localized
                alert.informativeText = "Check System Settings > General > Login Items and make sure Hidden Bar is allowed.".localized
                alert.alertStyle = .warning
                alert.runModal()
            }
        }
    }

    var showPreferencesOnLaunch: Binding<Bool> {
        return binding({ Preferences.isShowPreference }) { Preferences.isShowPreference = $0 }
    }

    var autoHide: Binding<Bool> {
        return binding({ Preferences.isAutoHide }) { Preferences.isAutoHide = $0 }
    }

    var autoHideDelay: Binding<Int> {
        return Binding(get: { SelectedSecond.secondToPossition(seconds: Preferences.numberOfSecondForAutoHide) },
                       set: { [weak self] index in
                           if let seconds = SelectedSecond(rawValue: index)?.toSeconds() {
                               Preferences.numberOfSecondForAutoHide = seconds
                           }
                           self?.objectWillChange.send()
                       })
    }

    var useFullMenuBar: Binding<Bool> {
        return binding({ Preferences.useFullStatusBarOnExpandEnabled }) { Preferences.useFullStatusBarOnExpandEnabled = $0 }
    }

    var alwaysHiddenSection: Binding<Bool> {
        return binding({ Preferences.alwaysHiddenSectionEnabled }) { Preferences.alwaysHiddenSectionEnabled = $0 }
    }

    var notchOverflow: Binding<Bool> {
        return binding({ Preferences.notchOverflowEnabled }) { Preferences.notchOverflowEnabled = $0 }
    }
}

//MARK: - Views

struct GeneralSettingsView: View {
    @ObservedObject var model: GeneralSettingsModel
    @State private var showsAlwaysHiddenHelp = false

    // Strings shared with the old storyboard layout, trimmed of the punctuation
    // that only made sense there, so existing translations keep working.
    private static func label(_ key: String) -> String {
        return key.localized.trimmingCharacters(in: CharacterSet(charactersIn: ": "))
    }

    private let autoHideDelays = ["5 seconds", "10 seconds", "15 seconds", "30 seconds", "1 minute"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                tutorial
                if model.isAccessibilityPermissionMissing {
                    accessibilityNotice
                }
                Divider()
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        sectionLabel("Startup")
                        VStack(spacing: 0) {
                            settingsToggle("Start Hidden Bar when I log in", isOn: model.autoStart)
                            settingsToggle("Show preferences on launch", isOn: model.showPreferencesOnLaunch)
                        }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        sectionLabel("Menu Bar")
                        menuBarOptions
                    }
                    Divider()
                    HStack {
                        Text(verbatim: Self.label("Shortcut"))
                        Spacer()
                        shortcutRecorder
                    }
                    .frame(minHeight: 28)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity)
        }
        .font(.system(size: 13))
        .controlSize(.small)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func sectionLabel(_ key: String) -> some View {
        Text(verbatim: Self.label(key))
            .font(.caption)
            .fontWeight(.medium)
            .foregroundStyle(.secondary)
    }

    private func settingsToggle(_ key: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(verbatim: Self.label(key))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 16)
            switchControl(key, isOn: isOn)
        }
        .frame(minHeight: 28)
    }

    private func switchControl(_ key: String, isOn: Binding<Bool>) -> some View {
        Toggle("", isOn: isOn)
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
            .accessibilityLabel(Self.label(key))
    }

    private var tutorial: some View {
        VStack(spacing: 6) {
            MenuBarPreview(alwaysHidden: Preferences.alwaysHiddenSectionEnabled)
                .frame(maxWidth: .infinity)
            Text(verbatim: MenuBarEngineFactory.usesNativeVisibility
                 ? "Hold ⌘ and drag icons to the left of the arrow to hide them.".localized
                 : Self.label("In your Mac's menu bar, hold ⌘ and drag icons\nbetween sections to configure Hidden Bar.").replacingOccurrences(of: "\n", with: " "))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var accessibilityNotice: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(verbatim: "Hidden Bar needs Accessibility access to hide icons.".localized)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button("Open Settings…".localized) {
                Util.requestAccessibilityPermission()
            }
        }
    }

    private var menuBarOptions: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text(verbatim: Self.label("Automatically hide icon after: "))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 12)
                Picker("", selection: model.autoHideDelay) {
                    ForEach(autoHideDelays.indices, id: \.self) { index in
                        Text(verbatim: autoHideDelays[index].localized).tag(index)
                    }
                }
                .labelsHidden()
                .accessibilityLabel("Auto-hide delay".localized)
                .frame(width: 100)
                .disabled(!model.autoHide.wrappedValue)
                switchControl("Automatically hide icon after: ", isOn: model.autoHide)
            }
            .frame(minHeight: 28)
            settingsToggle("Use the full MenuBar on expanding", isOn: model.useFullMenuBar)
            HStack(spacing: 6) {
                Text(verbatim: Self.label("Enable always hidden section"))
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    showsAlwaysHiddenHelp.toggle()
                } label: {
                    Image(systemName: "questionmark.circle")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Always-hidden section help".localized)
                .popover(isPresented: $showsAlwaysHiddenHelp, arrowEdge: .trailing) {
                    Text(verbatim: MenuBarEngineFactory.usesNativeVisibility
                         ? "Place the always-hidden separator to the left of the arrow, then ⌘-drag icons to its left. Option-click the arrow to hide or reveal that section.".localized
                         : "Place the always-hidden separator to the left of the regular separator, then ⌘-drag icons to its left. Option-click the arrow to hide or reveal that section.".localized)
                        .padding()
                        .frame(width: 320)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 16)
                switchControl("Enable always hidden section", isOn: model.alwaysHiddenSection)
            }
            .frame(minHeight: 28)
            if NotchOverflowController.hasNotch {
                settingsToggle("Enable Notch Overflow (right-click ‹ to access hidden icons)", isOn: model.notchOverflow)
                    .help("Right-click the arrow to access icons behind the notch.".localized)
            }
        }
    }

    private var shortcutRecorder: some View {
        HStack(spacing: 8) {
            Button {
                model.onRecordShortcut()
            } label: {
                Text(verbatim: shortcutButtonTitle)
                    .frame(minWidth: 85)
            }
            if model.shortcutTitle != nil && !model.isRecordingShortcut {
                Button {
                    model.onClearShortcut()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear".localized)
                .help("Clear".localized)
            }
        }
    }

    private var shortcutButtonTitle: String {
        if model.isRecordingShortcut {
            return model.recordingPreview.isEmpty ? "Type Shortcut…".localized : model.recordingPreview
        }
        return model.shortcutTitle ?? "Set Shortcut".localized
    }
}

// A miniature menu bar: the icons left of the boundary are the hidden section.
// On macOS 27 the arrow is the boundary; before that it is the separator.
private struct MenuBarPreview: View {
    let alwaysHidden: Bool

    private let showsSeparator = !MenuBarEngineFactory.usesNativeVisibility

    var body: some View {
        HStack(spacing: 8) {
            if alwaysHidden {
                section(["cloud", "headphones"], title: GeneralSettingsView.labelAlwaysHidden, style: .tertiary)
                onIconRow(icon("seprated_1").foregroundStyle(.secondary))
            }
            section(alwaysHidden ? ["gamecontroller", "battery.100"] : ["cloud", "headphones", "gamecontroller"], title: "Hidden".localized, style: .secondary)
            if showsSeparator {
                onIconRow(icon("seprated"))
            }
            onIconRow(icon("ico_collapse")
                .frame(width: 22, height: 22)
                .background(Color.accentColor.opacity(0.2), in: RoundedRectangle(cornerRadius: 5)))
            section(["wifi", "magnifyingglass", "switch.2"], title: "Shown".localized, style: .primary)
        }
    }

    // Keeps an uncaptioned item on the icons' row, above the section captions.
    private func onIconRow<V: View>(_ content: V) -> some View {
        VStack(spacing: 3) {
            content.frame(height: 22)
            Text(verbatim: " ").font(.caption)
        }
    }

    private func icon(_ name: String) -> some View {
        let image = ["ico_collapse", "seprated", "seprated_1"].contains(name)
            ? Image(name) : Image(systemName: name)
        return image
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: 15, height: 15)
            .accessibilityHidden(true)
    }

    private func section<S: ShapeStyle>(_ icons: [String], title: String, style: S) -> some View {
        VStack(spacing: 3) {
            HStack(spacing: 10) {
                ForEach(icons, id: \.self) { icon($0) }
            }
            .foregroundStyle(style)
            .frame(height: 22)
            Text(verbatim: title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private extension GeneralSettingsView {
    static var labelAlwaysHidden: String {
        return "⭐️Always Hidden".localized.replacingOccurrences(of: "⭐️", with: "")
    }
}
