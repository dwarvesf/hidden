import Foundation

@main
struct CollapseLengthPolicyTests {
    static func expect(_ actual: Double, equals expected: Double, _ message: String) {
        guard actual == expected else {
            fatalError("\(message): expected \(expected), got \(actual)")
        }
    }

    static func main() {
        // macOS 27 discards a status item at half the display width. A single-display
        // collapse must stay beneath that cliff while legacy systems preserve their
        // existing oversized separator behavior.
        expect(
            CollapseLengthPolicy.collapsedLength(screenWidths: [1920], macOSMajorVersion: 27),
            equals: 896,
            "macOS 27 keeps the separator below half the display width"
        )

        expect(
            CollapseLengthPolicy.collapsedLength(screenWidths: [1920], macOSMajorVersion: 26),
            equals: 3840,
            "macOS 26 retains the existing collapse length"
        )

        expect(
            CollapseLengthPolicy.collapsedLength(screenWidths: [601], macOSMajorVersion: 27),
            equals: 236,
            "macOS 27 retains a usable lower bound on small displays"
        )

        expect(
            CollapseLengthPolicy.collapsedLength(screenWidths: [100], macOSMajorVersion: 27),
            equals: 49,
            "macOS 27 never reaches the half-width discard threshold"
        )

        expect(
            CollapseLengthPolicy.collapsedLength(screenWidths: [1920, 3440], macOSMajorVersion: 27),
            equals: 1784,
            "mixed displays remain unchanged by default"
        )

        expect(
            CollapseLengthPolicy.collapsedLength(
                screenWidths: [1920, 3440],
                macOSMajorVersion: 27,
                hideWithMixedDisplays: true
            ),
            equals: 896,
            "mixed displays can opt into hiding on the narrowest display"
        )

        print("CollapseLengthPolicy tests passed")
    }
}
