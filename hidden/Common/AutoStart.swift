//
//  AutoStart.swift
//  Hidden Bar
//
//  Copyright © 2026 Console Labs. All rights reserved.
//

import Foundation
import ServiceManagement

// The login-item surface of SMAppService behind a protocol so the apply logic is
// unit-testable without touching the real system registration.
protocol LoginItemServing {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
}

extension SMAppService: LoginItemServing {}

// Builds before the SMAppService migration (v1.10 and older, all sandboxed)
// registered a LauncherApplication helper in BTM. macOS never garbage-collects
// that record (TN3111), and SMLoginItemSetEnabled cannot reach it once the bundle
// no longer ships the helper: it fails with 22 on every call. What does
// remove it is unregistering the main app's own SMAppService item, which drops
// every record under the app, so the migration turns launch at login off and on
// once.
enum LegacyLoginItem {
    static let migratedKey = "smAppServiceMigrated"
    static let failureHint = "Hidden Bar could not remove the login item an old version left. System Settings > General > Login Items & Extensions lists it inside \"Hidden Bar\" under Allow in the Background, not as a row of its own. To remove it, turn \"Open Hidden Bar at login\" off and on again in Hidden Bar's Settings."

    enum Step: Equatable {
        case none       // already migrated
        case markDone   // no launcher-era install here, nothing to remove
        case wait       // a legacy record may exist, launch at login is off: touch nothing yet
        case reset      // unregister and re-register the main app once
    }

    static func step(migrated: Bool, mayHaveLegacyRecord: Bool, autoStart: Bool) -> Step {
        if migrated { return .none }
        if !mayHaveLegacyRecord { return .markDone }
        return autoStart ? .reset : .wait
    }

    // A launcher-era build was sandboxed, so it left a container behind. The
    // sandboxed App Store build runs inside that container itself.
    static func mayHaveLegacyRecord(
        home: URL = URL(fileURLWithPath: NSHomeDirectory()),
        bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "com.dwarvesv.minimalbar",
        sandboxed: Bool = ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil,
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> Bool {
        sandboxed || fileExists(home.appendingPathComponent("Library/Containers/\(bundleIdentifier)").path)
    }

    // One bounded attempt: the flag is set after the reset whatever its result,
    // so a failure is reported once instead of on every launch.
    @discardableResult
    static func migrate(
        defaults: UserDefaults = AppDefaults.store,
        autoStart: Bool,
        mayHaveLegacyRecord: Bool,
        service: LoginItemServing = SMAppService.mainApp,
        report: (String) -> Void = { NSLog("%@", $0) }
    ) -> Step {
        let next = step(migrated: defaults.bool(forKey: migratedKey),
                        mayHaveLegacyRecord: mayHaveLegacyRecord,
                        autoStart: autoStart)
        switch next {
        case .none, .wait:
            break
        case .markDone:
            defaults.set(true, forKey: migratedKey)
        case .reset:
            do { try service.unregister() } catch { report("LegacyLoginItem: unregister failed: \(error.localizedDescription)") }
            do { try service.register() } catch { report("LegacyLoginItem: register failed: \(error.localizedDescription)") }
            if service.status != .enabled { report(failureHint) }
            defaults.set(true, forKey: migratedKey)
        }
        return next
    }

    // The entry point the app uses. Tests and Debug builds share the real prefs
    // domain, so they neither touch login items nor mark the migration done.
    static func migrateUnlessTesting(autoStart: Bool, touchLoginItems: Bool = AutoStart.shouldTouchLoginItems()) {
        guard touchLoginItems else { return }
        let step = migrate(autoStart: autoStart, mayHaveLegacyRecord: mayHaveLegacyRecord())
        NSLog("LegacyLoginItem: \(step)")
    }
}

enum AutoStart {
    // A test host launched from the build cache would otherwise register itself
    // as a second "Hidden Bar" login item whenever the developer's real prefs
    // have start-at-login on, so tests and Debug builds never touch the system
    // registration. Release behaviour is unchanged.
    static var isRunningUnderXCTest: Bool { AppDefaults.isRunningUnderXCTest }

    // Xcode parallel testing launches several clones of the host app from one
    // bundle path. The single-instance check would quit every clone after the
    // first, and each exits 0 before the test runner connects. A test host
    // never enforces it; a real launch always does.
    static func shouldEnforceSingleInstance(underXCTest: Bool = isRunningUnderXCTest) -> Bool {
        !underXCTest
    }

    static var isDebugBuild: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    static func shouldTouchLoginItems(
        underXCTest: Bool = isRunningUnderXCTest,
        debugBuild: Bool = isDebugBuild
    ) -> Bool {
        !underXCTest && !debugBuild
    }

    // The entry point the app uses: apply(), unless this is a test or Debug run.
    // Skipping reports success so a Preferences toggle still sticks in Debug.
    @discardableResult
    static func applyUnlessTesting(
        enabled: Bool,
        service: LoginItemServing = SMAppService.mainApp,
        touchLoginItems: Bool = shouldTouchLoginItems()
    ) -> Bool {
        guard touchLoginItems else {
            NSLog("AutoStart: skipped (test or Debug build), login items untouched")
            return true
        }
        return apply(enabled: enabled, service: service)
    }

    // Returns whether the system ended up in the desired state. A throw is one
    // failure mode; a register() that lands on .requiresApproval (or any status
    // other than the terminal one) is another, so the post-call status is what
    // decides, not the absence of an error.
    @discardableResult
    static func apply(enabled: Bool, service: LoginItemServing = SMAppService.mainApp) -> Bool {
        do {
            if enabled {
                if service.status != .enabled { try service.register() }
            } else {
                if service.status != .notRegistered { try service.unregister() }
            }
        } catch {
            NSLog("AutoStart: \(enabled ? "register" : "unregister") failed: \(error.localizedDescription)")
        }
        let ok = service.status == (enabled ? SMAppService.Status.enabled : .notRegistered)
        NSLog("AutoStart: status = \(service.status.rawValue)")
        return ok
    }
}
