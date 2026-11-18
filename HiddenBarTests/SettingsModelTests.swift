//
//  SettingsModelTests.swift
//  HiddenBarTests
//
//  Copyright © 2026 Console Labs. All rights reserved.
//

import XCTest

/// Contract: the Settings window's decisions, per build. Runs in both schemes,
/// so `SettingsBuild.current` is the App Store build in one run and the direct
/// build in the other.
/// Serves: SettingsModel.swift (tabs, status card state, auto-hide popup, preview edge).
/// Mock boundary: none; pure values.
final class SettingsModelTests: XCTestCase {

    // MARK: tabs per build

    // Given this test bundle's build flags
    // When listing the Settings tabs on macOS 27 with the Icons pane registered
    // Then the direct build shows it second and the App Store build never shows it
    func test_currentBuild_tabsMatchItsFlags() {
        let tabs = SettingsTab.visibleTabs(build: .current, osMajorVersion: 27, menuBarAppsAvailable: true)
        #if HIDDENBAR_NATIVE_VISIBILITY
        XCTAssertEqual(SettingsBuild.current, .direct)
        XCTAssertEqual(tabs, [.general, .menuBarApps, .appearance, .advanced, .about])
        #else
        XCTAssertEqual(SettingsBuild.current, .appStore)
        XCTAssertEqual(tabs, [.general, .appearance, .advanced, .about])
        #endif
    }

    // Given each build, OS and registration
    // When listing the tabs
    // Then Icons needs all three: direct build, macOS 27, the pane registered
    func test_menuBarAppsTab_onlyWithPinnedSections() {
        let base: [SettingsTab] = [.general, .appearance, .advanced, .about]
        XCTAssertEqual(SettingsTab.visibleTabs(build: .direct, osMajorVersion: 27, menuBarAppsAvailable: false), base)
        XCTAssertEqual(SettingsTab.visibleTabs(build: .direct, osMajorVersion: 26, menuBarAppsAvailable: true), base)
        XCTAssertEqual(SettingsTab.visibleTabs(build: .appStore, osMajorVersion: 27, menuBarAppsAvailable: true), base)
        XCTAssertEqual(SettingsTab.visibleTabs(build: .direct, osMajorVersion: 28, menuBarAppsAvailable: true),
                       [.general, .menuBarApps, .appearance, .advanced, .about])
    }

    // MARK: status card

    // Given every combination of build, OS, install location and permission
    // When picking the status card
    // Then macOS 26 is always fine, the App Store build on 27 says so, and the
    //      direct build asks for the move before the permission
    func test_statusCard_picksTheMostBlockingState() {
        func status(_ build: SettingsBuild, _ os: Int, inApplications: Bool = true, axMissing: Bool = false) -> SettingsStatus {
            SettingsStatus.resolve(build: build, osMajorVersion: os, runsFromApplicationsFolder: inApplications, accessibilityMissing: axMissing)
        }
        XCTAssertEqual(status(.direct, 26, inApplications: false, axMissing: true), .working)
        XCTAssertEqual(status(.appStore, 26), .working)
        XCTAssertEqual(status(.appStore, 27), .appStoreOnMacOS27)
        XCTAssertEqual(status(.appStore, 27, inApplications: false, axMissing: true), .appStoreOnMacOS27)
        XCTAssertEqual(status(.direct, 27), .working)
        XCTAssertEqual(status(.direct, 27, axMissing: true), .needsAccessibility)
        XCTAssertEqual(status(.direct, 27, inApplications: false), .outsideApplications)
        XCTAssertEqual(status(.direct, 27, inApplications: false, axMissing: true), .outsideApplications)
        XCTAssertFalse(SettingsStatus.working.isWarning)
        XCTAssertTrue([SettingsStatus.needsAccessibility, .outsideApplications, .appStoreOnMacOS27].allSatisfy(\.isWarning))
    }

    // Given Hidden Bar opened from a translocated or temporary path
    // When the status card names the folder it runs from
    // Then it says "a temporary folder", not the random folder name ("d.")
    func test_statusCard_namesATemporaryFolderPlainly() {
        let temporary = ["/private/var/folders/ab/xyz/T/AppTranslocation/1234-ABCD/d/Hidden Bar.app",
                         "/var/folders/ab/xyz/T/Hidden Bar.app",
                         "/private/tmp/x/Hidden Bar.app",
                         "/tmp/Hidden Bar.app"]
        for path in temporary {
            XCTAssertTrue(RunningFolder.isTemporary(URL(fileURLWithPath: path)), path)
            XCTAssertEqual(RunningFolder.displayName(of: URL(fileURLWithPath: path), displayName: { _ in "d." }),
                           "a temporary folder".localized, path)
        }
        let downloads = URL(fileURLWithPath: "/Users/x/Downloads/Hidden Bar.app")
        XCTAssertFalse(RunningFolder.isTemporary(downloads))
        XCTAssertEqual(RunningFolder.displayName(of: downloads, displayName: { $0 == "/Users/x/Downloads" ? "Downloads" : "?" }), "Downloads")
    }

    // MARK: preview edge

    func test_previewBoundary_followsTheEngine() {
        XCTAssertEqual(PreviewBoundary.forEngine(native: true), .arrow)
        XCTAssertEqual(PreviewBoundary.forEngine(native: false), .separator)
        XCTAssertTrue(SettingsBuild.direct.usesNativeEngine(osMajorVersion: 27))
        XCTAssertFalse(SettingsBuild.direct.usesNativeEngine(osMajorVersion: 26))
        XCTAssertFalse(SettingsBuild.appStore.usesNativeEngine(osMajorVersion: 27))
    }

    // MARK: auto-hide popup

    // Given the stored pair (isAutoHide, delay)
    // When the popup reads it
    // Then off reads as Never, each known delay as its entry, and an unknown delay as 5 seconds like the old popup
    func test_autoHide_readsTheStoredPair() {
        XCTAssertEqual(AutoHideChoice(isAutoHide: false, seconds: 30), .never)
        for delay in AutoHideChoice.delays {
            XCTAssertEqual(AutoHideChoice(isAutoHide: true, seconds: delay), .after(seconds: delay))
        }
        XCTAssertEqual(AutoHideChoice(isAutoHide: true, seconds: 7), .after(seconds: 5))
        XCTAssertEqual(AutoHideChoice.all.count, 6)
        XCTAssertEqual(AutoHideChoice.all.first, .never)
    }

    // Given each popup entry
    // When it is picked
    // Then Never turns auto-hide off and leaves the delay alone; every other entry turns it on with its delay
    func test_autoHide_writesTheSameKeysAsBefore() {
        XCTAssertEqual(AutoHideChoice.never.stored.isAutoHide, false)
        XCTAssertNil(AutoHideChoice.never.stored.seconds)
        for choice in AutoHideChoice.all.dropFirst() {
            XCTAssertTrue(choice.stored.isAutoHide)
            let seconds = try? XCTUnwrap(choice.stored.seconds)
            XCTAssertEqual(AutoHideChoice(isAutoHide: true, seconds: seconds ?? -1), choice, "round trip for \(choice)")
            XCTAssertEqual(AutoHideChoice.all[choice.index], choice)
        }
    }
}
