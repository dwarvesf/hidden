//
//  Constant.swift
//  vanillaClone
//
//  Created by Thanh Nguyen on 1/30/19.
//  Copyright © 2019 Console Labs. All rights reserved.
//

import Foundation
import os

enum Constant {
    static let appName = "Hidden Bar"

    static var isUsingLTRLanguage = false
}

// Foundation's NSLog marks every value <private> in the unified log on recent
// macOS, so Console and `log show` showed "<private>" for each of our lines.
// This module-level NSLog shadows it for every caller in the target: the
// message is logged public (call sites keep user content out of it) and also
// written to stderr, which os_log alone does not reach.
enum AppLog {
    static let category = "app"

    private static let log = OSLog(subsystem: Bundle.main.bundleIdentifier ?? "com.dwarvesv.minimalbar", category: category)
    private static let timestamps: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()

    // No arguments: the text is already composed (most call sites interpolate),
    // so a "%" in it, such as a file name, must not be read as a format.
    static func message(_ format: String, _ args: [CVarArg]) -> String {
        args.isEmpty ? format : String(format: format, arguments: args)
    }

    // The line NSLog wrote to stderr, which RUNBOOK checks read.
    static func stderrLine(_ message: String, timestamp: String, process: String, pid: Int32, thread: UInt32) -> String {
        "\(timestamp) \(process)[\(pid):\(thread)] \(message)\n"
    }

    static func write(_ message: String) {
        os_log("%{public}@", log: log, type: .default, message)
        let line = stderrLine(message,
                              timestamp: timestamps.string(from: Date()),
                              process: ProcessInfo.processInfo.processName,
                              pid: ProcessInfo.processInfo.processIdentifier,
                              thread: pthread_mach_thread_np(pthread_self()))
        fputs(line, stderr)
    }
}

func NSLog(_ format: String, _ args: CVarArg...) {
    AppLog.write(AppLog.message(format, args))
}
