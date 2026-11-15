//
//  PresentationState.swift
//  Hidden Bar
//
//  Copyright © 2026 Dwarves Foundation. All rights reserved.
//

import Foundation

// Why presentation mode is on.
enum PresentationCause: Equatable {
    // The user started it (shortcut, arrow menu, the capsule). Only the user ends it.
    case manual
    // A display is mirrored. Ends when mirroring ends.
    case mirroring(displayName: String?)
}

enum PresentationPhase: Equatable {
    case off
    // On and holding the strict list.
    case presenting
    // On, but the restriction is lifted because a camera or microphone is in use
    // (or was a moment ago): the restriction also hides the capsule macOS shows
    // for the app that records (#437).
    case paused
    // On, but macOS refused the strict list, so every icon is showing.
    case couldNotHide
}

// What is wanted from the menu bar, as a pure value: the causes that turned the
// mode on, the capture level, and whether the last hold failed. It holds no
// timers and reads no clock; the caller passes the time. NativeVisibilityEngine
// turns the resulting phase into the one list it holds.
struct PresentationState: Equatable {
    // The microphone or camera must be quiet this long before hiding resumes, so
    // a mic that flaps for a second does not flap the bar. Pausing is immediate.
    static let resumeDelay: TimeInterval = 2.5

    private(set) var isManual = false
    private(set) var mirror: PresentationMirror?
    // The user stopped while a mirror cause still applied. The mirror cause stays
    // quiet until mirroring ends and starts again.
    private(set) var mirrorSuppressed = false
    // When capture was last seen on, or seen ending: the quiet period starts there.
    private(set) var lastCaptureAt: TimeInterval?
    private(set) var captureWasActive = false
    private(set) var hideFailed = false

    var isOn: Bool {
        return isManual || (mirror != nil && !mirrorSuppressed)
    }

    // The reason to show the user: a manual start wins over a mirror, since only
    // the user can end it.
    var cause: PresentationCause? {
        if isManual { return .manual }
        if let mirror, !mirrorSuppressed { return .mirroring(displayName: mirror.displayName) }
        return nil
    }

    mutating func startManually() {
        isManual = true
        hideFailed = false
    }

    // Ends the whole mode, whatever started it.
    mutating func stop() {
        isManual = false
        if mirror != nil { mirrorSuppressed = true }
        hideFailed = false
    }

    mutating func mirrorChanged(_ newMirror: PresentationMirror?) {
        let wasOn = isOn
        mirror = newMirror
        if newMirror == nil { mirrorSuppressed = false }
        if !wasOn && isOn { hideFailed = false }
    }

    mutating func hideDidFail() {
        hideFailed = true
    }

    mutating func hideDidSucceed() {
        hideFailed = false
    }

    // Level-triggered: the caller reads the capture state at this moment, every
    // time, rather than relying on a stored edge. Capture seen now, or seen
    // ending now, keeps the mode paused until it has been quiet for `resumeDelay`.
    mutating func resolve(captureActive: Bool, now: TimeInterval) -> PresentationPhase {
        guard isOn else {
            // Nothing is waiting on capture while the mode is off, and a stale
            // quiet period must not pause the next start.
            lastCaptureAt = nil
            captureWasActive = false
            return .off
        }
        if captureActive || captureWasActive { lastCaptureAt = now }
        captureWasActive = captureActive
        if captureActive { return .paused }
        if let last = lastCaptureAt, now < last + Self.resumeDelay { return .paused }
        return hideFailed ? .couldNotHide : .presenting
    }

    // Seconds until a quiet period ends, nil when there is none to wait for.
    func resumeWait(now: TimeInterval) -> TimeInterval? {
        guard isOn, let last = lastCaptureAt, now < last + Self.resumeDelay else { return nil }
        return last + Self.resumeDelay - now
    }
}

struct PresentationMirror: Equatable {
    // The display the room sees, when macOS names it.
    let displayName: String?
}
