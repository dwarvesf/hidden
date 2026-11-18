//
//  AppDefaults.swift
//  Hidden Bar
//
//  Copyright © 2026 Console Labs. All rights reserved.
//

import Foundation

/// The one place the app reads its preferences store and decides whether this
/// process may touch the real install.
///
/// A test host launches with the shipping bundle id, so `UserDefaults.standard`
/// there is the user's real `com.dwarvesv.minimalbar` domain. Under XCTest the
/// store is a dedicated suite, wiped the first time it is read, and side effects
/// that act on the real machine (moving or trashing the app, login items,
/// Sparkle, quitting for a second copy) are skipped. A shipping launch keeps
/// `UserDefaults.standard` and every side effect.
enum AppDefaults {
    static let testSuiteName = "com.dwarvesv.minimalbar.tests"

    /// Set to `1` in a test run's environment to let the launch side effects run.
    static let sideEffectsOptInVariable = "HIDDEN_BAR_TEST_HOST_SIDE_EFFECTS"

    /// A test sets this to run a side effect on purpose, for itself only.
    static var sideEffectsOptIn = false

    /// The preferences store every setting, notice and ledger reads and writes.
    static let store: UserDefaults = makeStore(underXCTest: isRunningUnderXCTest)

    static var isRunningUnderXCTest: Bool {
        NSClassFromString("XCTestCase") != nil
            || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    /// False in a test host unless a test or the environment opted in.
    static var allowsHostSideEffects: Bool {
        allowsHostSideEffects(underXCTest: isRunningUnderXCTest, optedIn: sideEffectsOptIn,
                              environment: ProcessInfo.processInfo.environment)
    }

    static func allowsHostSideEffects(underXCTest: Bool, optedIn: Bool, environment: [String: String]) -> Bool {
        !underXCTest || optedIn || environment[sideEffectsOptInVariable] == "1"
    }

    static func makeStore(underXCTest: Bool) -> UserDefaults {
        guard underXCTest, let suite = UserDefaults(suiteName: testSuiteName) else { return .standard }
        suite.removePersistentDomain(forName: testSuiteName)
        return suite
    }
}
