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
