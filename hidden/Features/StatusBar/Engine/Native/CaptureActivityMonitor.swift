//
//  CaptureActivityMonitor.swift
//  Hidden Bar
//
//  Copyright © 2026 Dwarves Foundation. All rights reserved.
//

import CoreAudio
import CoreMediaIO
import Foundation

// Whether any app is recording from a microphone or using a camera. macOS 27
// runs every native visibility restriction in assessment mode, which also hides
// the menu-bar capsule naming the app that records (#437), so
// NativeVisibilityEngine holds no restriction while this is active.
protocol CaptureActivityMonitoring: AnyObject {
    var isActive: Bool { get }

    // Called on the main queue whenever isActive may have changed.
    var onChange: (() -> Void)? { get set }
}

// Reads the same public state the recording indicators reflect, for every
// process, without the microphone or camera permission:
// - microphone: each audio process object's "is running input" (macOS 14.2+).
//   Device-level "running somewhere" would also fire for a headset that is
//   only playing audio.
// - camera: each camera device's "running somewhere".
// Screen recording has no public equivalent, so it is not covered.
final class CaptureActivityMonitor: CaptureActivityMonitoring {
    var onChange: (() -> Void)?

    private var processes: [AudioObjectID] = []
    private var cameras: [CMIOObjectID] = []
    private var audioListener: AudioObjectPropertyListenerBlock!
    private var cameraListener: CMIOObjectPropertyListenerBlock!

    init() {
        // One block for every registration, so each can be removed again.
        audioListener = { [weak self] _, _ in self?.devicesDidChange() }
        cameraListener = { [weak self] _, _ in self?.devicesDidChange() }
        if #available(macOS 14.2, *) {
            var processList = Self.audioAddress(kAudioHardwarePropertyProcessObjectList)
            AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &processList, .main, audioListener)
        }
        var cameraList = Self.cameraAddress(CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices))
        CMIOObjectAddPropertyListenerBlock(CMIOObjectID(kCMIOObjectSystemObject), &cameraList, .main, cameraListener)
        track()
    }

    deinit {
        untrack()
        if #available(macOS 14.2, *) {
            var processList = Self.audioAddress(kAudioHardwarePropertyProcessObjectList)
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &processList, .main, audioListener)
        }
        var cameraList = Self.cameraAddress(CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices))
        CMIOObjectRemovePropertyListenerBlock(CMIOObjectID(kCMIOObjectSystemObject), &cameraList, .main, cameraListener)
    }

    var isActive: Bool {
        if #available(macOS 14.2, *) {
            if processes.contains(where: { Self.audioFlag(kAudioProcessPropertyIsRunningInput, of: $0) }) {
                return true
            }
        }
        return cameras.contains { Self.cameraIsRunning($0) }
    }

    // Processes and cameras come and go, so any change re-registers on the
    // current set before reporting.
    private func devicesDidChange() {
        untrack()
        track()
        onChange?()
    }

    private func track() {
        if #available(macOS 14.2, *) {
            processes = Self.audioObjects(kAudioHardwarePropertyProcessObjectList)
            var running = Self.audioAddress(kAudioProcessPropertyIsRunningInput)
            for process in processes {
                AudioObjectAddPropertyListenerBlock(process, &running, .main, audioListener)
            }
        }
        cameras = Self.cameraObjects()
        var running = Self.cameraAddress(CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere))
        for camera in cameras {
            CMIOObjectAddPropertyListenerBlock(camera, &running, .main, cameraListener)
        }
    }

    // Removing from an object that has already gone away fails harmlessly.
    private func untrack() {
        if #available(macOS 14.2, *) {
            var running = Self.audioAddress(kAudioProcessPropertyIsRunningInput)
            for process in processes {
                AudioObjectRemovePropertyListenerBlock(process, &running, .main, audioListener)
            }
        }
        var running = Self.cameraAddress(CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere))
        for camera in cameras {
            CMIOObjectRemovePropertyListenerBlock(camera, &running, .main, cameraListener)
        }
        processes = []
        cameras = []
    }

    // MARK: - CoreAudio

    private static func audioAddress(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        return AudioObjectPropertyAddress(mSelector: selector,
                                          mScope: kAudioObjectPropertyScopeGlobal,
                                          mElement: kAudioObjectPropertyElementMain)
    }

    private static func audioObjects(_ selector: AudioObjectPropertySelector) -> [AudioObjectID] {
        var address = audioAddress(selector)
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var objects = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &objects) == noErr else { return [] }
        return Array(objects.prefix(Int(size) / MemoryLayout<AudioObjectID>.size))
    }

    private static func audioFlag(_ selector: AudioObjectPropertySelector, of object: AudioObjectID) -> Bool {
        var address = audioAddress(selector)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr && value != 0
    }

    // MARK: - CoreMediaIO

    private static func cameraAddress(_ selector: CMIOObjectPropertySelector) -> CMIOObjectPropertyAddress {
        return CMIOObjectPropertyAddress(mSelector: selector,
                                         mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                                         mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
    }

    private static func cameraObjects() -> [CMIOObjectID] {
        var address = cameraAddress(CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices))
        let system = CMIOObjectID(kCMIOObjectSystemObject)
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var objects = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(system, &address, 0, nil, size, &used, &objects) == noErr else { return [] }
        return Array(objects.prefix(Int(used) / MemoryLayout<CMIOObjectID>.size))
    }

    private static func cameraIsRunning(_ camera: CMIOObjectID) -> Bool {
        var address = cameraAddress(CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere))
        var value: UInt32 = 0
        var used: UInt32 = 0
        return CMIOObjectGetPropertyData(camera, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &used, &value) == noErr
            && value != 0
    }
}
