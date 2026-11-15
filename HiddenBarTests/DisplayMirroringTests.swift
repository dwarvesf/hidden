//
//  DisplayMirroringTests.swift
//  HiddenBarTests
//
//  Copyright © 2026 Dwarves Foundation. All rights reserved.
//

import CoreGraphics
import XCTest

// The mirror read behind the automatic trigger, on fixture displays: no real
// display is mirrored or touched.
final class DisplayMirroringTests: XCTestCase {
    private func reader(online: [CGDirectDisplayID], mirrored: Set<CGDirectDisplayID>,
                        mirroring: Set<CGDirectDisplayID> = [], names: [CGDirectDisplayID: String] = [:]) -> DisplayMirrorReader {
        return DisplayMirrorReader(onlineDisplays: { online },
                                   isInMirrorSet: { mirrored.contains($0) },
                                   mirrorsAnother: { mirroring.contains($0) },
                                   name: { names[$0] })
    }

    // Given two displays and none mirrored
    // When reading
    // Then there is no mirror
    func testNoMirrorSet() {
        XCTAssertNil(reader(online: [1, 2], mirrored: []).current())
    }

    // Given a mirrored pair
    // When reading
    // Then the display that shows the other's picture is named
    func testNamesTheDisplayThatMirrorsAnother() {
        let read = reader(online: [1, 2], mirrored: [1, 2], mirroring: [2], names: [1: "Built-in Display", 2: "Meeting Room TV"])
        XCTAssertEqual(read.current(), PresentationMirror(displayName: "Meeting Room TV"))
    }

    // Given a mirrored pair whose mirroring display has no name
    // When reading
    // Then no name is given, rather than the Mac's own screen
    func testNeverNamesTheMacsOwnScreen() {
        let read = reader(online: [1, 2], mirrored: [1, 2], mirroring: [2], names: [1: "Built-in Display"])
        XCTAssertEqual(read.current(), PresentationMirror(displayName: nil))
    }

    // Given a display that is online but not in a mirror set
    // When another is mirrored
    // Then only the mirror set counts
    func testIgnoresDisplaysOutsideTheMirrorSet() {
        let read = reader(online: [1, 2, 3], mirrored: [2, 3], mirroring: [3], names: [1: "Desk", 3: "Projector"])
        XCTAssertEqual(read.current(), PresentationMirror(displayName: "Projector"))
    }
}
