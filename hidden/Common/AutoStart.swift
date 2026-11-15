//
//  AutoStart.swift
//  Hidden Bar
//
//  Copyright © 2026 Dwarves Foundation. All rights reserved.
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

// Builds before the SMAppService migration registered a helper app in BTM;
// macOS never garbage-collects that record (TN3111), so deauthorize it once.
enum LegacyLoginItem {
    static let migratedKey = "smAppServiceMigrated"
    static let helperBundleID = "com.dwarvesv.LauncherApplication"
    static let failureHint = "Hidden Bar could not remove its old login item; remove \"LauncherApplication\" in System Settings > General > Login Items."

    // The migrated flag is set only when the system confirms the removal, so a
    // failed attempt is retried on the next launch instead of being forgotten.
    @discardableResult
    static func remove(
        defaults: UserDefaults = .standard,
        disable: (String) -> Bool = { SMLoginItemSetEnabled($0 as CFString, false) },
        report: (String) -> Void = { NSLog("%@", $0) }
    ) -> Bool {
        guard !defaults.bool(forKey: migratedKey) else { return true }
        guard disable(helperBundleID) else {
            report(failureHint)
            return false
        }
        defaults.set(true, forKey: migratedKey)
        return true
    }
}

enum AutoStart {
    // A test host launched from the build cache would otherwise register itself
    // as a second "Hidden Bar" login item whenever the developer's real prefs
    // have start-at-login on, so tests and Debug builds never touch the system
    // registration. Release behaviour is unchanged.
    static var isRunningUnderXCTest: Bool {
        NSClassFromString("XCTestCase") != nil
            || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

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
