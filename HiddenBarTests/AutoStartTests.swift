//
//  AutoStartTests.swift
//  HiddenBarTests
//
//  Copyright © 2026 Console Labs. All rights reserved.
//

import ServiceManagement
import XCTest

private final class FakeLoginItem: LoginItemServing {
    struct StubbedError: Error {}

    var status: SMAppService.Status
    var error: Error?
    private(set) var registerCalls = 0
    private(set) var unregisterCalls = 0

    init(status: SMAppService.Status) {
        self.status = status
    }

    func register() throws {
        registerCalls += 1
        if let error { throw error }
    }

    func unregister() throws {
        unregisterCalls += 1
        if let error { throw error }
    }
}

final class AutoStartTests: XCTestCase {

    func testEnableCallsRegisterWhenNotRegistered() {
        let service = FakeLoginItem(status: .notRegistered)
        _ = AutoStart.apply(enabled: true, service: service)
        XCTAssertEqual(service.registerCalls, 1)
        XCTAssertEqual(service.unregisterCalls, 0)
    }

    func testEnableSucceedsWhenRegistrationLandsEnabled() {
        let service = TransitioningLoginItem(finalStatus: .enabled)
        XCTAssertTrue(AutoStart.apply(enabled: true, service: service))
    }

    func testEnableIsNoOpWhenAlreadyEnabled() {
        let service = FakeLoginItem(status: .enabled)
        XCTAssertTrue(AutoStart.apply(enabled: true, service: service))
        XCTAssertEqual(service.registerCalls, 0)
    }

    func testDisableUnregistersWhenEnabled() {
        let service = TransitioningLoginItem(initialStatus: .enabled, finalStatus: .notRegistered)
        XCTAssertTrue(AutoStart.apply(enabled: false, service: service))
    }

    func testDisableIsNoOpWhenNotRegistered() {
        let service = FakeLoginItem(status: .notRegistered)
        XCTAssertTrue(AutoStart.apply(enabled: false, service: service))
        XCTAssertEqual(service.unregisterCalls, 0)
    }

    func testEnableReportsFailureWhenRegisterThrows() {
        let service = FakeLoginItem(status: .notRegistered)
        service.error = FakeLoginItem.StubbedError()
        XCTAssertFalse(AutoStart.apply(enabled: true, service: service))
    }

    // register() not throwing is not proof of success: a registration that lands
    // on .requiresApproval must still surface as failure so the checkbox reverts.
    func testEnableReportsFailureOnRequiresApproval() {
        let service = TransitioningLoginItem(finalStatus: .requiresApproval)
        XCTAssertFalse(AutoStart.apply(enabled: true, service: service))
    }

    func testDisableReportsFailureWhenUnregisterThrows() {
        let service = FakeLoginItem(status: .enabled)
        service.error = FakeLoginItem.StubbedError()
        XCTAssertFalse(AutoStart.apply(enabled: false, service: service))
    }
}

final class LoginItemGateTests: XCTestCase {

    func testSkipsUnderXCTestEvenInRelease() {
        XCTAssertFalse(AutoStart.shouldTouchLoginItems(underXCTest: true, debugBuild: false))
    }

    func testSkipsInDebugBuild() {
        XCTAssertFalse(AutoStart.shouldTouchLoginItems(underXCTest: false, debugBuild: true))
    }

    func testReleaseOutsideXCTestStillTouchesLoginItems() {
        XCTAssertTrue(AutoStart.shouldTouchLoginItems(underXCTest: false, debugBuild: false))
    }

    // The test host itself must be recognised, or every test run registers the
    // build-cache app as a second login item.
    func testCurrentProcessIsDetectedAsXCTest() {
        XCTAssertTrue(AutoStart.isRunningUnderXCTest)
        XCTAssertFalse(AutoStart.shouldTouchLoginItems())
    }

    // Parallel test hosts share one bundle path; each must launch, not quit as
    // a second copy before the test runner connects.
    func testTestHostSkipsTheSingleInstanceCheck() {
        XCTAssertFalse(AutoStart.shouldEnforceSingleInstance(underXCTest: true))
        XCTAssertFalse(AutoStart.shouldEnforceSingleInstance())
    }

    func testRealLaunchStillEnforcesSingleInstance() {
        XCTAssertTrue(AutoStart.shouldEnforceSingleInstance(underXCTest: false))
    }

    func testApplyUnlessTestingSkipsServiceWhenGateIsClosed() {
        let service = FakeLoginItem(status: .notRegistered)
        XCTAssertTrue(AutoStart.applyUnlessTesting(enabled: true, service: service, touchLoginItems: false))
        XCTAssertEqual(service.registerCalls, 0)
        XCTAssertEqual(service.unregisterCalls, 0)
    }

    func testApplyUnlessTestingSkipsUnregisterWhenGateIsClosed() {
        let service = FakeLoginItem(status: .enabled)
        XCTAssertTrue(AutoStart.applyUnlessTesting(enabled: false, service: service, touchLoginItems: false))
        XCTAssertEqual(service.unregisterCalls, 0)
    }

    func testApplyUnlessTestingRegistersWhenGateIsOpen() {
        let service = FakeLoginItem(status: .notRegistered)
        _ = AutoStart.applyUnlessTesting(enabled: true, service: service, touchLoginItems: true)
        XCTAssertEqual(service.registerCalls, 1)
    }
}

final class LegacyLoginItemTests: XCTestCase {

    private func makeDefaults() -> UserDefaults {
        let suite = "LegacyLoginItemTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return defaults
    }

    func testDecisionTable() {
        XCTAssertEqual(LegacyLoginItem.step(migrated: true, mayHaveLegacyRecord: true, autoStart: true), .none)
        XCTAssertEqual(LegacyLoginItem.step(migrated: false, mayHaveLegacyRecord: false, autoStart: true), .markDone)
        XCTAssertEqual(LegacyLoginItem.step(migrated: false, mayHaveLegacyRecord: false, autoStart: false), .markDone)
        XCTAssertEqual(LegacyLoginItem.step(migrated: false, mayHaveLegacyRecord: true, autoStart: false), .wait)
        XCTAssertEqual(LegacyLoginItem.step(migrated: false, mayHaveLegacyRecord: true, autoStart: true), .reset)
    }

    // The upgrade path: launch at login on, a launcher-era record possible. The
    // main app item goes off and on once, ends enabled, and the flag is set.
    func testResetUnregistersThenRegistersOnceAndMarksDone() {
        let defaults = makeDefaults()
        let service = RecordingLoginItem(status: .enabled)
        var reports: [String] = []
        let step = LegacyLoginItem.migrate(defaults: defaults, autoStart: true, mayHaveLegacyRecord: true,
                                           service: service, report: { reports.append($0) })
        XCTAssertEqual(step, .reset)
        XCTAssertEqual(service.calls, ["unregister", "register"])
        XCTAssertEqual(service.status, .enabled)
        XCTAssertTrue(defaults.bool(forKey: LegacyLoginItem.migratedKey))
        XCTAssertEqual(reports, [])
    }

    // Bounded: a reset that does not land enabled reports the hint once and is
    // not retried on the next launch.
    func testFailedResetReportsHintOnceAndDoesNotLoop() {
        let defaults = makeDefaults()
        let service = RecordingLoginItem(status: .enabled)
        service.registerError = RecordingLoginItem.StubbedError()
        var reports: [String] = []
        LegacyLoginItem.migrate(defaults: defaults, autoStart: true, mayHaveLegacyRecord: true,
                                service: service, report: { reports.append($0) })
        XCTAssertTrue(defaults.bool(forKey: LegacyLoginItem.migratedKey))
        XCTAssertEqual(reports.last, LegacyLoginItem.failureHint)

        let again = LegacyLoginItem.migrate(defaults: defaults, autoStart: true, mayHaveLegacyRecord: true,
                                            service: service, report: { reports.append($0) })
        XCTAssertEqual(again, .none)
        XCTAssertEqual(service.calls, ["unregister", "register"])
    }

    // Launch at login off: nothing is touched and the migration stays pending,
    // so it runs at the first launch after the user turns it on.
    func testLaunchAtLoginOffWaitsWithoutTouchingLoginItems() {
        let defaults = makeDefaults()
        let service = RecordingLoginItem(status: .notRegistered)
        XCTAssertEqual(LegacyLoginItem.migrate(defaults: defaults, autoStart: false, mayHaveLegacyRecord: true,
                                               service: service, report: { _ in }), .wait)
        XCTAssertEqual(service.calls, [])
        XCTAssertFalse(defaults.bool(forKey: LegacyLoginItem.migratedKey))

        XCTAssertEqual(LegacyLoginItem.migrate(defaults: defaults, autoStart: true, mayHaveLegacyRecord: true,
                                               service: service, report: { _ in }), .reset)
        XCTAssertEqual(service.calls, ["unregister", "register"])
    }

    // A fresh install: no container, so login items are never touched.
    func testFreshInstallIsMarkedDoneWithoutTouchingLoginItems() {
        let defaults = makeDefaults()
        let service = RecordingLoginItem(status: .enabled)
        XCTAssertEqual(LegacyLoginItem.migrate(defaults: defaults, autoStart: true, mayHaveLegacyRecord: false,
                                               service: service, report: { _ in }), .markDone)
        XCTAssertEqual(service.calls, [])
        XCTAssertTrue(defaults.bool(forKey: LegacyLoginItem.migratedKey))
    }

    func testAlreadyMigratedTouchesNothing() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: LegacyLoginItem.migratedKey)
        let service = RecordingLoginItem(status: .enabled)
        XCTAssertEqual(LegacyLoginItem.migrate(defaults: defaults, autoStart: true, mayHaveLegacyRecord: true,
                                               service: service, report: { _ in }), .none)
        XCTAssertEqual(service.calls, [])
    }

    func testLegacyRecordSignalIsTheSandboxContainer() {
        let home = URL(fileURLWithPath: "/Users/someone")
        var asked: [String] = []
        XCTAssertTrue(LegacyLoginItem.mayHaveLegacyRecord(home: home, bundleIdentifier: "com.dwarvesv.minimalbar",
                                                          sandboxed: false, fileExists: { asked.append($0); return true }))
        XCTAssertEqual(asked, ["/Users/someone/Library/Containers/com.dwarvesv.minimalbar"])
        XCTAssertFalse(LegacyLoginItem.mayHaveLegacyRecord(home: home, bundleIdentifier: "com.dwarvesv.minimalbar",
                                                           sandboxed: false, fileExists: { _ in false }))
    }

    // The App Store build runs inside its own container, which App Store 1.8
    // and older (launcher era) share.
    func testSandboxedBuildAlwaysMayHaveALegacyRecord() {
        XCTAssertTrue(LegacyLoginItem.mayHaveLegacyRecord(home: URL(fileURLWithPath: "/x"), bundleIdentifier: "b",
                                                          sandboxed: true, fileExists: { _ in false }))
    }

    func testHintNamesTheRowUsersSee() {
        XCTAssertTrue(LegacyLoginItem.failureHint.contains("\"Hidden Bar\" under Allow in the Background"))
        XCTAssertFalse(LegacyLoginItem.failureHint.contains("LauncherApplication"))
    }

    func testGateClosedTouchesNothing() {
        // Under XCTest the real entry point must return before any system call
        // or prefs write; the shared prefs domain must keep no migrated flag from it.
        let before = AppDefaults.store.object(forKey: LegacyLoginItem.migratedKey)
        LegacyLoginItem.migrateUnlessTesting(autoStart: true, touchLoginItems: false)
        XCTAssertEqual(AppDefaults.store.object(forKey: LegacyLoginItem.migratedKey) as? Bool, before as? Bool)
    }
}

// Records call order; register lands enabled and unregister notRegistered unless stubbed to throw.
private final class RecordingLoginItem: LoginItemServing {
    struct StubbedError: Error {}

    var status: SMAppService.Status
    var registerError: Error?
    private(set) var calls: [String] = []

    init(status: SMAppService.Status) {
        self.status = status
    }

    func register() throws {
        calls.append("register")
        if let registerError { throw registerError }
        status = .enabled
    }

    func unregister() throws {
        calls.append("unregister")
        status = .notRegistered
    }
}

// A fake whose register/unregister moves status to a given terminal value, like
// the real SMAppService does on success.
private final class TransitioningLoginItem: LoginItemServing {
    var status: SMAppService.Status
    private let finalStatus: SMAppService.Status

    init(initialStatus: SMAppService.Status = .notRegistered, finalStatus: SMAppService.Status) {
        self.status = initialStatus
        self.finalStatus = finalStatus
    }

    func register() throws { status = finalStatus }
    func unregister() throws { status = finalStatus }
}
