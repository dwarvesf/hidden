//
//  AppLogTests.swift
//  HiddenBarTests
//
//  Copyright © 2026 Console Labs. All rights reserved.
//

import XCTest

final class AppLogTests: XCTestCase {

    func testStderrLineKeepsTheNSLogShape() {
        XCTAssertEqual(AppLog.stderrLine("AutoCollapse: holding for the palette", timestamp: "2026-11-18 09:00:00.123",
                                         process: "Hidden Bar", pid: 321, thread: 4567),
                       "2026-11-18 09:00:00.123 Hidden Bar[321:4567] AutoCollapse: holding for the palette\n")
    }

    func testPublicLineWritesTheTextOnceToStderr() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("applog-\(UUID().uuidString).txt")
        FileManager.default.createFile(atPath: file.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: file) }
        let saved = dup(STDERR_FILENO)
        let handle = try FileHandle(forWritingTo: file)
        dup2(handle.fileDescriptor, STDERR_FILENO)
        AppLog.publicLine("AutoCollapse: holding for the palette 100%")
        fflush(stderr)
        dup2(saved, STDERR_FILENO)
        close(saved)
        try handle.close()
        let written = try String(contentsOf: file, encoding: .utf8)
        // Under Xcode and xcodebuild os_log also mirrors the line to stderr in its own
        // shape ("[events] ..."); ours is the one with "[pid:thread]" before the text.
        let ours = try NSRegularExpression(pattern: #"\[\d+:\d+\] AutoCollapse: holding for the palette 100%$"#, options: .anchorsMatchLines)
        XCTAssertEqual(ours.numberOfMatches(in: written, range: NSRange(written.startIndex..., in: written)), 1, written)
    }
}
