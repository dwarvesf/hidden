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
    // On, but nothing is hidden: a camera or microphone turned on while the mode
    // was on, so the restriction is lifted once, as on the main bar (1.12). A
    // capture already running when the mode starts does not pause it: its capsule
    // showed when it began. The restriction also hides the capsule macOS shows for the app that
    // records (#437). The user can resume hiding; it also resumes by itself when
    // capture ends.
    case paused
    // On, but macOS refused the strict list, so every icon is showing.
    case couldNotHide
}

// What is wanted from the menu bar, as a pure value: the causes that turned the
// mode on, the capture level, and whether the last hold failed. It holds no
// timers and reads no clock; the caller passes the time. NativeVisibilityEngine
// turns the resulting phase into the one list it holds.
struct PresentationState: Equatable {
    // The microphone or camera must be quiet this long before hiding resumes by
    // itself, so a mic that flaps for a second does not flap the bar. Pausing is
    // immediate.
    static let resumeDelay: TimeInterval = 2.5

    private(set) var isManual = false
    private(set) var mirror: PresentationMirror?
    // The user stopped while a mirror cause still applied. The mirror cause stays
    // quiet until mirroring ends and starts again.
    private(set) var mirrorSuppressed = false
    // When capture was last seen on, or seen ending: the quiet period starts there.
    private(set) var lastCaptureAt: TimeInterval?
    private(set) var captureWasActive = false
    // A capture start paused the mode and the user has not resumed hiding since.
    private(set) var capturePaused = false
    // The mode has resolved at least once since it came on, so a capture seen
    // later is a start and one seen first was already running.
    private(set) var captureSeen = false
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

    // The user chose to hide again while capture continues (the capsule action or
    // a collapse). The next capture start pauses again.
    mutating func resumeHiding() {
        capturePaused = false
        hideFailed = false
    }

    // The capture rule is the one the main bar follows (1.12): a camera or
    // microphone that turns on pauses the mode once, `pausesForCapture` being the
    // "show the whole bar when capture starts" switch. Capture already on when the
    // mode starts is not a start (a collapsed main bar does not expand for it
    // either), so the mode starts hidden. With the switch off nothing ever pauses.
    // The caller reads the capture state at this moment, every time; the start is
    // seen here as an off-to-on change, and a pause ends when the user resumes or
    // when capture has been quiet for `resumeDelay`.
    mutating func resolve(captureActive: Bool, pausesForCapture: Bool = true, now: TimeInterval) -> PresentationPhase {
        guard isOn else {
            // Nothing is waiting on capture while the mode is off, and a stale
            // pause must not carry into the next start.
            lastCaptureAt = nil
            captureWasActive = false
            capturePaused = false
            captureSeen = false
            return .off
        }
        guard pausesForCapture else {
            lastCaptureAt = nil
            captureWasActive = captureActive
            capturePaused = false
            captureSeen = true
            return hideFailed ? .couldNotHide : .presenting
        }
        if captureActive && !captureWasActive && captureSeen { capturePaused = true }
        captureSeen = true
        if captureActive || captureWasActive { lastCaptureAt = now }
        captureWasActive = captureActive
        if capturePaused {
            if captureActive { return .paused }
            if let last = lastCaptureAt, now < last + Self.resumeDelay { return .paused }
            capturePaused = false
        }
        return hideFailed ? .couldNotHide : .presenting
    }

    // Seconds until a quiet period ends, nil when there is none to wait for.
    func resumeWait(now: TimeInterval) -> TimeInterval? {
        guard isOn, capturePaused, let last = lastCaptureAt, now < last + Self.resumeDelay else { return nil }
        return last + Self.resumeDelay - now
    }
}

struct PresentationMirror: Equatable {
    // The display the room sees, when macOS names it.
    let displayName: String?
}
