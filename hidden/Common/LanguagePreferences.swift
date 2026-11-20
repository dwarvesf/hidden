//
//  LanguagePreferences.swift
//  Hidden Bar
//
//  Copyright © 2026 Console Labs. All rights reserved.
//

import AppKit
import Foundation

/// The language Hidden Bar opens in.
///
/// The choice is stored as `AppleLanguages` in the app's preferences, the key
/// CFBundle reads while it resolves a localization, so it takes effect on the
/// next launch. macOS's per-app language setting writes the same key, which
/// keeps both controls on one value. No key means follow the system language.
enum LanguagePreferences {
    /// CFBundle reads this key, so writing it is the whole override. macOS's
    /// per-app language setting uses it too.
    static let appleLanguagesKey = "AppleLanguages"

    /// What the App language row picked. Separate from AppleLanguages because
    /// UserDefaults falls back to the global domain, where macOS keeps the
    /// system language: an absent AppleLanguages here must still mean "system",
    /// not the system's first language.
    static let selectionKey = "appLanguage"

    struct Language: Equatable {
        /// The localization code, such as "zh-Hans".
        let code: String
        /// The language's own name, readable while the app is in another one.
        let name: String
    }

    /// What the app ships, by native name. "Base" is not a language.
    static func languages(in bundle: Bundle = .main) -> [Language] {
        bundle.localizations
            .filter { $0 != "Base" }
            .map { Language(code: $0, name: nativeName(of: $0)) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func nativeName(of code: String) -> String {
        Locale(identifier: code).localizedString(forIdentifier: code) ?? code
    }

    /// The stored override, or nil when the app follows the system language.
    static func override(in store: UserDefaults = AppDefaults.store) -> String? {
        if let code = store.string(forKey: selectionKey), !code.isEmpty { return code }
        // macOS's per-app language panel writes AppleLanguages into this app's
        // own domain. Read that domain, not the store, so the global domain
        // (the system language) still reads as "follow the system".
        guard store === UserDefaults.standard,
              let bundleID = Bundle.main.bundleIdentifier,
              let domain = store.persistentDomain(forName: bundleID),
              let codes = domain[appleLanguagesKey] as? [String],
              let code = codes.first, !code.isEmpty else { return nil }
        return code
    }

    /// What the next launch will use. A code this build no longer ships falls
    /// back to the system choice instead of leaving the bundle with nothing.
    static func effective(in bundle: Bundle = .main, store: UserDefaults = AppDefaults.store) -> String {
        if let code = override(in: store), bundle.localizations.contains(code) { return code }
        return bundle.preferredLocalizations.first ?? bundle.developmentLocalization ?? "en"
    }

    /// nil restores the system choice.
    static func setOverride(_ code: String?, in store: UserDefaults = AppDefaults.store) {
        if let code, !code.isEmpty {
            store.set(code, forKey: selectionKey)
            store.set([code], forKey: appleLanguagesKey)
        } else {
            store.removeObject(forKey: selectionKey)
            store.removeObject(forKey: appleLanguagesKey)
        }
    }
}

/// Reopens the running bundle after this process exits. A short delay lets the
/// old instance leave before the new one checks for a duplicate.
enum AppRelaunch {
    static func now() {
        guard AppDefaults.allowsHostSideEffects else { return }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 1; /usr/bin/open \"$1\"", "relaunch", Bundle.main.bundleURL.path]
        try? task.run()
        NSApp.terminate(nil)
    }
}
