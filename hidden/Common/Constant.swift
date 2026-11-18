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

// Foundation's NSLog marks every value <private> in the unified log, which keeps
// bundle ids and error texts out of Console and sysdiagnoses. That stays the
// default. A line that needs to be readable there goes through publicLine: it
// takes a StaticString, so the compiler rejects anything built at run time and
// no user data can reach the public log. The same line also goes to stderr, as
// NSLog does, because os_log alone does not reach it.
enum AppLog {
    private static let log = OSLog(subsystem: Bundle.main.bundleIdentifier ?? "com.dwarvesv.minimalbar", category: "events")
    private static let timestamps: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()

    static func publicLine(_ text: StaticString) {
        let message = "\(text)"
        os_log("%{public}@", log: log, type: .default, message)
        fputs(stderrLine(message,
                         timestamp: timestamps.string(from: Date()),
                         process: ProcessInfo.processInfo.processName,
                         pid: ProcessInfo.processInfo.processIdentifier,
                         thread: pthread_mach_thread_np(pthread_self())),
              stderr)
    }

    // The shape NSLog writes to stderr, so a captured file reads the same.
    static func stderrLine(_ message: String, timestamp: String, process: String, pid: Int32, thread: UInt32) -> String {
        "\(timestamp) \(process)[\(pid):\(thread)] \(message)\n"
    }
}
