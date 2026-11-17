//
//  PresentationStateTests.swift
//  HiddenBarTests
//
//  Copyright © 2026 Console Labs. All rights reserved.
//

import XCTest

// The pure state machine behind presentation mode: what turned it on, and
// whether the camera or microphone has paused it, by the rule the main bar has
// followed since 1.12 (a start pauses once; the user may hide again). No clock,
// no engine.
final class PresentationStateTests: XCTestCase {
    private func resolved(_ state: inout PresentationState, capture: Bool = false, pauses: Bool = true,
                          at now: TimeInterval = 100) -> PresentationPhase {
        return state.resolve(captureActive: capture, pausesForCapture: pauses, now: now)
    }

    // Given a fresh state
    // When nothing started it
    // Then it is off
    func testStartsOff() {
        var state = PresentationState()
        XCTAssertFalse(state.isOn)
        XCTAssertEqual(resolved(&state), .off)
        XCTAssertNil(state.cause)
    }

    // Given a manual start
    // When capture is quiet
    // Then it is presenting, and only a stop ends it
    func testManualStartPresentsUntilStopped() {
        var state = PresentationState()
        state.startManually()
        XCTAssertEqual(state.cause, .manual)
        XCTAssertEqual(resolved(&state), .presenting)
        state.mirrorChanged(PresentationMirror(displayName: "TV"))
        state.mirrorChanged(nil)
        XCTAssertEqual(resolved(&state), .presenting, "a mirror ending must not end a manual start")
        state.stop()
        XCTAssertEqual(resolved(&state), .off)
    }

    // Given a mirrored display
    // When mirroring starts and stops
    // Then the mode follows it, naming the display
    func testMirrorTriggerFollowsItsCause() {
        var state = PresentationState()
        state.mirrorChanged(PresentationMirror(displayName: "Meeting Room TV"))
        XCTAssertEqual(resolved(&state), .presenting)
        XCTAssertEqual(state.cause, .mirroring(displayName: "Meeting Room TV"))
        state.mirrorChanged(nil)
        XCTAssertEqual(resolved(&state), .off)
    }

    // Given a mirror start, then a manual start on top
    // When mirroring stops
    // Then it stays on: the user's start outranks the automatic one
    func testManualStartOutlivesTheMirrorCause() {
        var state = PresentationState()
        state.mirrorChanged(PresentationMirror(displayName: "TV"))
        state.startManually()
        XCTAssertEqual(state.cause, .manual)
        state.mirrorChanged(nil)
        XCTAssertEqual(resolved(&state), .presenting)
    }

    // Given a mirror-started mode
    // When the user stops it while mirroring continues
    // Then it stays off until mirroring ends and starts again
    func testStoppingAMirrorStartSticksUntilMirroringEnds() {
        var state = PresentationState()
        state.mirrorChanged(PresentationMirror(displayName: "TV"))
        state.stop()
        XCTAssertEqual(resolved(&state), .off)
        state.mirrorChanged(PresentationMirror(displayName: "TV"))
        XCTAssertEqual(resolved(&state), .off, "the same mirroring must not switch it back on")
        state.mirrorChanged(nil)
        state.mirrorChanged(PresentationMirror(displayName: "TV"))
        XCTAssertEqual(resolved(&state), .presenting)
    }

    // Given the mode on
    // When a camera or microphone turns on
    // Then it pauses at once
    func testCaptureStartPausesAtOnce() {
        var state = PresentationState()
        state.startManually()
        XCTAssertEqual(resolved(&state, at: 10), .presenting)
        XCTAssertEqual(resolved(&state, capture: true, at: 11), .paused)
    }

    // Given capture already running when the mode starts (a call under way)
    // When it starts
    // Then it presents hidden, stays so while that capture runs, and only a fresh start pauses
    func testStartsHiddenWhenCaptureIsAlreadyActive() {
        var state = PresentationState()
        state.startManually()
        XCTAssertEqual(resolved(&state, capture: true, at: 5), .presenting)
        XCTAssertEqual(resolved(&state, capture: true, at: 500), .presenting)
        XCTAssertEqual(resolved(&state, capture: false, at: 600), .presenting)
        XCTAssertEqual(resolved(&state, capture: true, at: 700), .paused, "a fresh start while presenting lifts once")
    }

    // Given a pause
    // When capture ends
    // Then it resumes only after the quiet period, however long the capture ran
    func testResumesAfterTheQuietPeriod() {
        var state = PresentationState()
        state.startManually()
        _ = resolved(&state, at: 1)
        XCTAssertEqual(resolved(&state, capture: true, at: 10), .paused)
        // A long call: no event between its start and its end.
        XCTAssertEqual(resolved(&state, capture: false, at: 700), .paused, "the quiet period starts when capture ends")
        XCTAssertEqual(state.resumeWait(now: 700), PresentationState.resumeDelay)
        XCTAssertEqual(resolved(&state, at: 700 + PresentationState.resumeDelay - 0.1), .paused)
        XCTAssertEqual(resolved(&state, at: 700 + PresentationState.resumeDelay + 0.1), .presenting)
        XCTAssertNil(state.resumeWait(now: 710))
    }

    // Given capture that flaps for a second
    // When it stops and starts again inside the quiet period
    // Then the mode stays paused throughout
    func testAFlappingMicrophoneDoesNotFlapTheBar() {
        var state = PresentationState()
        state.startManually()
        _ = resolved(&state, at: 1)
        _ = resolved(&state, capture: true, at: 10)
        XCTAssertEqual(resolved(&state, capture: false, at: 11), .paused)
        XCTAssertEqual(resolved(&state, capture: true, at: 12), .paused)
        XCTAssertEqual(resolved(&state, capture: false, at: 13), .paused)
        XCTAssertEqual(resolved(&state, at: 14), .paused, "1 s after the last stop")
        XCTAssertEqual(resolved(&state, at: 16), .presenting, "past the quiet period")
    }

    // Given the mode off
    // When capture runs
    // Then nothing is paused or waited for, and a later start has no stale quiet period
    func testCaptureWhileOffLeavesNothingBehind() {
        var state = PresentationState()
        XCTAssertEqual(resolved(&state, capture: true, at: 10), .off)
        XCTAssertNil(state.resumeWait(now: 10))
        XCTAssertEqual(resolved(&state, capture: false, at: 11), .off)
        state.startManually()
        XCTAssertEqual(resolved(&state, at: 20), .presenting)
    }

    // Given a hold that macOS refused
    // When the phase is read
    // Then it says so instead of presenting, until a hold lands or the mode restarts
    func testARefusedHoldIsNotPresenting() {
        var state = PresentationState()
        state.startManually()
        state.hideDidFail()
        XCTAssertEqual(resolved(&state), .couldNotHide)
        state.hideDidSucceed()
        XCTAssertEqual(resolved(&state), .presenting)
        state.hideDidFail()
        state.stop()
        state.startManually()
        XCTAssertEqual(resolved(&state), .presenting, "a new start tries again")
    }

    // Given a refused hold
    // When a camera turns on
    // Then pause wins: the strict list is not being held anyway
    func testPauseWinsOverARefusedHold() {
        var state = PresentationState()
        state.startManually()
        state.hideDidFail()
        XCTAssertEqual(resolved(&state, at: 49), .couldNotHide)
        XCTAssertEqual(resolved(&state, capture: true, at: 50), .paused)
    }

    // Given the switch "show the whole bar when a camera or microphone turns on" is off
    // When capture starts, or is already running when the mode starts
    // Then the mode never pauses, like the main bar
    func testSwitchOffNeverPauses() {
        var state = PresentationState()
        state.startManually()
        XCTAssertEqual(resolved(&state, capture: true, pauses: false, at: 5), .presenting, "already active at start")
        XCTAssertEqual(resolved(&state, capture: false, pauses: false, at: 6), .presenting)
        XCTAssertEqual(resolved(&state, capture: true, pauses: false, at: 7), .presenting, "a start while presenting")
        XCTAssertNil(state.resumeWait(now: 7))
    }

    // Given a pause for a camera that is still on
    // When the user hides again
    // Then the mode presents while capture continues, and only a new start pauses again
    func testUserResumeDuringCaptureHoldsUntilTheNextStart() {
        var state = PresentationState()
        state.startManually()
        _ = resolved(&state, at: 1)
        XCTAssertEqual(resolved(&state, capture: true, at: 10), .paused)
        state.resumeHiding()
        XCTAssertEqual(resolved(&state, capture: true, at: 11), .presenting)
        XCTAssertEqual(resolved(&state, capture: true, at: 600), .presenting, "capture running all day does not pause again")
        XCTAssertEqual(resolved(&state, capture: false, at: 700), .presenting, "no quiet period after a user resume")
        XCTAssertNil(state.resumeWait(now: 700))
        XCTAssertEqual(resolved(&state, capture: true, at: 800), .paused, "a new start pauses again")
    }

    // Given a pause
    // When the switch is turned off
    // Then the mode presents
    func testTurningTheSwitchOffEndsAPause() {
        var state = PresentationState()
        state.startManually()
        _ = resolved(&state, at: 1)
        XCTAssertEqual(resolved(&state, capture: true, at: 5), .paused)
        XCTAssertEqual(resolved(&state, capture: true, pauses: false, at: 6), .presenting)
    }
}
