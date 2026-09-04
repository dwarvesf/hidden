import XCTest
@testable import Hidden_Bar

final class PlaceholderTests: XCTestCase {
    func test_testTargetIsWired() {
        // Given the test target links against the app target
        // When a trivial assertion runs
        // Then it passes, proving the test host / bundle loader wiring works
        XCTAssertTrue(true, "test target should build and run against the app host")
    }
}
