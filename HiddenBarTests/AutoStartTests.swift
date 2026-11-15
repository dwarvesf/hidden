//
//  AutoStartTests.swift
//  HiddenBarTests
//
//  Copyright © 2026 Dwarves Foundation. All rights reserved.
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

    func testSuccessfulRemovalSetsMigratedFlag() {
        let defaults = makeDefaults()
        var asked: [String] = []
        let ok = LegacyLoginItem.remove(defaults: defaults, disable: { asked.append($0); return true }, report: { _ in })
        XCTAssertTrue(ok)
        XCTAssertEqual(asked, [LegacyLoginItem.helperBundleID])
        XCTAssertTrue(defaults.bool(forKey: LegacyLoginItem.migratedKey))
    }

    // #456: a failed SMLoginItemSetEnabled must not mark the migration done.
    func testFailedRemovalLeavesFlagUnsetAndReportsHint() {
        let defaults = makeDefaults()
        var reports: [String] = []
        let ok = LegacyLoginItem.remove(defaults: defaults, disable: { _ in false }, report: { reports.append($0) })
        XCTAssertFalse(ok)
        XCTAssertFalse(defaults.bool(forKey: LegacyLoginItem.migratedKey))
        XCTAssertEqual(reports, [LegacyLoginItem.failureHint])
    }

    func testFailedRemovalIsRetriedOnNextLaunch() {
        let defaults = makeDefaults()
        _ = LegacyLoginItem.remove(defaults: defaults, disable: { _ in false }, report: { _ in })
        var calls = 0
        let ok = LegacyLoginItem.remove(defaults: defaults, disable: { _ in calls += 1; return true }, report: { _ in })
        XCTAssertTrue(ok)
        XCTAssertEqual(calls, 1)
        XCTAssertTrue(defaults.bool(forKey: LegacyLoginItem.migratedKey))
    }

    func testAlreadyMigratedSkipsTheSystemCall() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: LegacyLoginItem.migratedKey)
        var calls = 0
        XCTAssertTrue(LegacyLoginItem.remove(defaults: defaults, disable: { _ in calls += 1; return false }, report: { _ in }))
        XCTAssertEqual(calls, 0)
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
