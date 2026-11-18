//
//  AppLogTests.swift
//  HiddenBarTests
//
//  Copyright © 2026 Console Labs. All rights reserved.
//

import XCTest

final class AppLogTests: XCTestCase {

    func testNoArgumentsKeepsThePercentSignsOfAnAlreadyComposedMessage() {
        // A call site that interpolates passes the finished text as the format.
        XCTAssertEqual(AppLog.message("AutoCollapse: holding for 100% of /tmp/a%20b %@ %d", []),
                       "AutoCollapse: holding for 100% of /tmp/a%20b %@ %d")
    }

    func testFormatArgumentsAreSubstituted() {
        XCTAssertEqual(AppLog.message("AutoCollapse: a popup has been open for %.0f s", [12.4 as Double]),
                       "AutoCollapse: a popup has been open for 12 s")
        XCTAssertEqual(AppLog.message("SettingsSnapshot: %@ %.0fx%.0f", ["a.png", 480.0 as Double, 320.0 as Double]),
                       "SettingsSnapshot: a.png 480x320")
    }

    func testObjectArgumentWithPercentSignsIsInsertedVerbatim() {
        // The guard logs through NSLog("%@", text); the text is data, not a format.
        let text = "AutoCollapse: holding for a popup from com.example.app%d at layer 25"
        XCTAssertEqual(AppLog.message("%@", [text]), text)
    }

    func testMessageStartsWithTheCallSiteText() {
        // `log show` predicates use eventMessage BEGINSWITH "AutoCollapse".
        XCTAssertTrue(AppLog.message("AutoCollapse: holding for %@", ["the palette"]).hasPrefix("AutoCollapse"))
    }

    func testStderrLineKeepsTheNSLogShape() {
        XCTAssertEqual(AppLog.stderrLine("AutoStart: status = 1", timestamp: "2026-11-18 09:00:00.123",
                                         process: "Hidden Bar", pid: 321, thread: 4567),
                       "2026-11-18 09:00:00.123 Hidden Bar[321:4567] AutoStart: status = 1\n")
    }

    func testShadowedNSLogWritesTheLineToStderr() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("applog-\(UUID().uuidString).txt")
        FileManager.default.createFile(atPath: file.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: file) }
        let saved = dup(STDERR_FILENO)
        let handle = try FileHandle(forWritingTo: file)
        dup2(handle.fileDescriptor, STDERR_FILENO)
        NSLog("AutoStart: status = %d, name %@", 1, "50%")
        fflush(stderr)
        dup2(saved, STDERR_FILENO)
        close(saved)
        try handle.close()
        let written = try String(contentsOf: file, encoding: .utf8)
        XCTAssertTrue(written.hasSuffix("] AutoStart: status = 1, name 50%\n"), written)
    }
}
