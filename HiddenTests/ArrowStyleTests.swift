import XCTest
import AppKit
@testable import Hidden_Bar

/// Contract: the user picks the expand/collapse arrow from a short list of
/// styles (issue #310), stored as one preference. The default look is the
/// current arrow, and the style composes with stealth mode (issue #173).
/// Serves: Assets (images), Preferences (storage), StatusBarController, and
/// the Preferences popup.
/// Behaviors covered: default style, stored-value mapping (known, unknown,
/// missing), setter round-trip + notification, every style has distinct
/// template images for both states, the default style is pixel-identical to
/// the legacy arrow in both directions, stealth fades any style only while
/// collapsed, every locale carries every new string key, and a PNG render of
/// each style (light and dark menu bar, normal and stealth).
/// Mock boundary: none; the preference tests use the real `AppDefaults.store`
/// and restore the prior value, like StealthExpandIconTests.
final class ArrowStyleTests: XCTestCase {

    private var priorStyle: Any?

    override func setUp() {
        super.setUp()
        priorStyle = AppDefaults.store.object(forKey: UserDefaults.Key.arrowStyle)
    }

    override func tearDown() {
        if let priorStyle {
            AppDefaults.store.set(priorStyle, forKey: UserDefaults.Key.arrowStyle)
        } else {
            AppDefaults.store.removeObject(forKey: UserDefaults.Key.arrowStyle)
        }
        super.tearDown()
    }

    // MARK: default

    // Given a fresh install
    // When reading the declared defaults and the preference with nothing stored
    // Then the style is the current arrow, so nothing changes for existing users
    func test_default_isTheCurrentArrow() {
        AppDefaults.store.removeObject(forKey: UserDefaults.Key.arrowStyle)

        XCTAssertEqual(ArrowStyle.default, .arrow)
        XCTAssertEqual(AppDelegate.defaultPreferenceValues[UserDefaults.Key.arrowStyle] as? String, "arrow")
        XCTAssertEqual(Preferences.arrowStyle, .arrow)
    }

    // MARK: mapping

    // Given the four styles
    // When listing them and reading their stored names
    // Then the order and the stored names are fixed (the names live in users' defaults)
    func test_styles_haveStableOrderAndStoredNames() {
        XCTAssertEqual(ArrowStyle.allCases, [.arrow, .chevron, .dot, .line])
        XCTAssertEqual(ArrowStyle.allCases.map(\.rawValue), ["arrow", "chevron", "dot", "line"])
    }

    // Given a stored value
    // When mapping it to a style
    // Then known names map to their style; unknown or missing falls back to the arrow
    func test_storedValue_mapsToStyle() {
        XCTAssertEqual(ArrowStyle(storedValue: "arrow"), .arrow)
        XCTAssertEqual(ArrowStyle(storedValue: "chevron"), .chevron)
        XCTAssertEqual(ArrowStyle(storedValue: "dot"), .dot)
        XCTAssertEqual(ArrowStyle(storedValue: "line"), .line)
        XCTAssertEqual(ArrowStyle(storedValue: "sparkles"), .arrow)
        XCTAssertEqual(ArrowStyle(storedValue: ""), .arrow)
        XCTAssertEqual(ArrowStyle(storedValue: nil), .arrow)
    }

    // Given each style
    // When it is set and read back
    // Then the preference reports it and keeps it as one string key
    func test_settingPreference_roundTripsEveryStyle() {
        for style in ArrowStyle.allCases {
            Preferences.arrowStyle = style
            XCTAssertEqual(Preferences.arrowStyle, style)
            XCTAssertEqual(AppDefaults.store.string(forKey: UserDefaults.Key.arrowStyle), style.rawValue)
        }
    }

    // Given garbage stored under the key
    // When reading the preference
    // Then it reads as the default arrow instead of crashing or showing nothing
    func test_garbageStoredValue_readsAsDefault() {
        AppDefaults.store.set("not-a-style", forKey: UserDefaults.Key.arrowStyle)

        XCTAssertEqual(Preferences.arrowStyle, .arrow)
    }

    // Given an observer of the style notification
    // When the style changes
    // Then the observer is told, so the status item redraws at once
    func test_settingPreference_postsNotification() {
        let posted = expectation(forNotification: .arrowStyleChanged, object: nil)

        Preferences.arrowStyle = .dot

        wait(for: [posted], timeout: 1)
    }

    // MARK: images

    // Given every style, in both text directions
    // When asking for the collapsed (expand) and expanded (collapse) images
    // Then each exists, is a template (tints in light and dark menu bars), and
    // the two states look different from each other
    func test_everyStyle_hasTemplateImagesThatDifferByState() {
        for style in ArrowStyle.allCases {
            for isLTR in [true, false] {
                guard let expand = style.expandImage(isLTR: isLTR),
                      let collapse = style.collapseImage(isLTR: isLTR) else {
                    XCTFail("\(style) has no image (LTR \(isLTR))")
                    continue
                }
                XCTAssertTrue(expand.isTemplate, "\(style) expand must be a template")
                XCTAssertTrue(collapse.isTemplate, "\(style) collapse must be a template")
                XCTAssertNotEqual(Self.pixels(expand), Self.pixels(collapse), "\(style) states must differ (LTR \(isLTR))")
            }
        }
    }

    // Given the four styles
    // When comparing their collapsed images
    // Then no two styles look alike, so the popup choice is meaningful
    func test_styles_lookDifferentFromEachOther() {
        let looks = ArrowStyle.allCases.map { Self.pixels($0.expandImage(isLTR: true)!) }

        XCTAssertEqual(Set(looks).count, ArrowStyle.allCases.count)
    }

    // Given the default style
    // When asking for its images
    // Then they are the shipped arrow assets, in the legacy direction for each text direction
    func test_defaultStyle_matchesLegacyArrowAssets() {
        let legacyExpand = NSImage(named: NSImage.Name("ic_expand"))!
        let legacyCollapse = NSImage(named: NSImage.Name("ic_collapse"))!

        XCTAssertEqual(Self.pixels(ArrowStyle.arrow.expandImage(isLTR: true)!), Self.pixels(legacyExpand))
        XCTAssertEqual(Self.pixels(ArrowStyle.arrow.collapseImage(isLTR: true)!), Self.pixels(legacyCollapse))
        XCTAssertEqual(Self.pixels(ArrowStyle.arrow.expandImage(isLTR: false)!), Self.pixels(legacyCollapse))
        XCTAssertEqual(Self.pixels(ArrowStyle.arrow.collapseImage(isLTR: false)!), Self.pixels(legacyExpand))
    }

    // MARK: composition with stealth

    // Given any style
    // When stealth is on
    // Then only the collapsed image is faded (and stays a template); the expanded
    // image and every stealth-off image stay fully opaque
    func test_stealth_fadesAnyStyleOnlyWhileCollapsed() {
        for style in ArrowStyle.allCases {
            let faded = Assets.toggleImage(style: style, isCollapsed: true, stealthEnabled: true, isLTR: true)!
            let plain = Assets.toggleImage(style: style, isCollapsed: true, stealthEnabled: false, isLTR: true)!
            let expandedStealth = Assets.toggleImage(style: style, isCollapsed: false, stealthEnabled: true, isLTR: true)!
            let expandedPlain = Assets.toggleImage(style: style, isCollapsed: false, stealthEnabled: false, isLTR: true)!

            XCTAssertLessThanOrEqual(Self.maxAlpha(faded), Assets.stealthExpandIconAlpha + 0.02, "\(style) collapsed + stealth")
            XCTAssertGreaterThan(Self.maxAlpha(faded), 0, "\(style) must not vanish")
            XCTAssertTrue(faded.isTemplate, "\(style) faded image must stay a template")
            XCTAssertGreaterThan(Self.maxAlpha(plain), 0.9, "\(style) collapsed, no stealth")
            XCTAssertGreaterThan(Self.maxAlpha(expandedStealth), 0.9, "\(style) expanded + stealth")
            XCTAssertEqual(Self.pixels(expandedStealth), Self.pixels(expandedPlain), "\(style) expanded ignores stealth")
        }
    }

    // Given stealth on and a chosen style
    // When asking for the collapsed image
    // Then it is that style's shape, faded, not the default arrow's shape
    func test_stealth_keepsTheChosenShape() {
        let fadedChevron = Assets.toggleImage(style: .chevron, isCollapsed: true, stealthEnabled: true, isLTR: true)!
        let fadedArrow = Assets.toggleImage(style: .arrow, isCollapsed: true, stealthEnabled: true, isLTR: true)!

        XCTAssertNotEqual(Self.pixels(fadedChevron), Self.pixels(fadedArrow))
    }

    // Given the stored preferences
    // When the status item asks for its images
    // Then they follow the stored style and the stealth preference
    func test_assetsFollowStoredPreferences() {
        Preferences.arrowStyle = .line

        XCTAssertEqual(Self.pixels(Assets.expandImage!), Self.pixels(ArrowStyle.line.expandImage()!))
        XCTAssertEqual(Self.pixels(Assets.collapseImage!), Self.pixels(ArrowStyle.line.collapseImage()!))
    }

    // MARK: strings and preview

    // Given the new popup strings
    // When looking in every Localizable.strings the app ships
    // Then each locale carries each key (English text is fine), so none shows a raw key
    func test_everyLocale_carriesEveryArrowStyleKey() {
        let keys = ["Arrow style"] + ArrowStyle.allCases.map(\.localizedNameKey)
        let localizations = Bundle.main.localizations.filter { $0 != "Base" }

        XCTAssertGreaterThan(localizations.count, 5)
        for locale in localizations {
            guard let path = Bundle.main.path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: locale),
                  let table = NSDictionary(contentsOfFile: path) as? [String: String] else {
                XCTFail("no Localizable.strings for \(locale)")
                continue
            }
            for key in keys {
                XCTAssertNotNil(table[key], "\(locale) is missing \"\(key)\"")
            }
        }
    }

    // Given each style
    // When building its popup preview
    // Then it is a template image showing the collapsed and expanded glyphs side by side
    func test_previewImage_isTemplateAndWiderThanOneGlyph() {
        for style in ArrowStyle.allCases {
            let preview = style.previewImage()

            XCTAssertTrue(preview.isTemplate)
            XCTAssertGreaterThan(Self.maxAlpha(preview, aspectPreserved: true), 0.9)
            XCTAssertGreaterThan(preview.size.width, style.expandImage()!.size.width)
        }
    }

    // MARK: render

    // Given every style
    // When rendered as the menu bar would tint them (light and dark bar, with and
    // without stealth)
    // Then each style produces a non-empty PNG; set ARROW_STYLE_PNG_DIR to keep them
    func test_renderEachStyleToPNG() throws {
        let dir = ProcessInfo.processInfo.environment["ARROW_STYLE_PNG_DIR"]
            ?? NSTemporaryDirectory() + "arrow-styles-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        for style in ArrowStyle.allCases {
            let png = Self.renderSheet(for: style)
            XCTAssertGreaterThan(png.count, 500, "\(style) sheet is empty")
            try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("arrow-style-\(style.rawValue).png"))
        }
    }

    // MARK: helpers

    /// Pixel bytes of `image` drawn at a fixed size, for equality checks.
    private static func pixels(_ image: NSImage, side: Int = 36) -> Data {
        bitmap(of: image, side: side).bitmapData.map { Data(bytes: $0, count: side * side * 4) } ?? Data()
    }

    private static func maxAlpha(_ image: NSImage, aspectPreserved: Bool = false) -> CGFloat {
        let rep = aspectPreserved
            ? bitmap(of: image, width: Int(image.size.width * 4), height: Int(image.size.height * 4))
            : bitmap(of: image, side: 36)
        var maxValue: CGFloat = 0
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide {
                maxValue = max(maxValue, rep.colorAt(x: x, y: y)?.alphaComponent ?? 0)
            }
        }
        return maxValue
    }

    private static func bitmap(of image: NSImage, side: Int) -> NSBitmapImageRep {
        bitmap(of: image, width: side, height: side)
    }

    private static func bitmap(of image: NSImage, width: Int, height: Int) -> NSBitmapImageRep {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: width * 4, bitsPerPixel: 32)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: width, height: height))
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    /// `image` filled with `color` where it has alpha, the way the menu bar tints a template.
    private static func tinted(_ image: NSImage, _ color: NSColor) -> NSImage {
        NSImage(size: image.size, flipped: false) { rect in
            image.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
    }

    /// One PNG per style: rows are the light and the dark menu bar; columns are
    /// collapsed, expanded, collapsed with stealth.
    private static func renderSheet(for style: ArrowStyle) -> Data {
        let cell: Int = 18, scale: Int = 8, pad: Int = 4
        let columns: [(collapsed: Bool, stealth: Bool)] = [(true, false), (false, false), (true, true)]
        let light: NSColor = NSColor(white: 0.93, alpha: 1)
        let dark: NSColor = NSColor(white: 0.14, alpha: 1)
        let rows: [(bar: NSColor, ink: NSColor)] = [(light, NSColor.black), (dark, NSColor.white)]
        let step: Int = (cell + pad) * scale
        let width: Int = step * columns.count + pad * scale
        let height: Int = step * rows.count + pad * scale
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 32)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        for (rowIndex, row) in rows.enumerated() {
            let barY: CGFloat = CGFloat(height - (rowIndex + 1) * step - pad * scale / 2)
            let bar = NSRect(x: 0, y: barY, width: CGFloat(width), height: CGFloat(step))
            row.bar.setFill()
            bar.fill()
            for (columnIndex, column) in columns.enumerated() {
                guard let image = Assets.toggleImage(style: style, isCollapsed: column.collapsed,
                                                     stealthEnabled: column.stealth, isLTR: true) else { continue }
                let x: CGFloat = CGFloat(pad * scale + columnIndex * step)
                let y: CGFloat = bar.minY + CGFloat(pad * scale / 2)
                let target = NSRect(x: x, y: y, width: CGFloat(cell * scale), height: CGFloat(cell * scale))
                tinted(image, row.ink).draw(in: target)
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:]) ?? Data()
    }
}
