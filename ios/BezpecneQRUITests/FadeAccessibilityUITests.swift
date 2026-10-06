import XCTest

@MainActor final class FadeAccessibilityUITests: RCUIBase {
    func testLargeTextKeepsVerdictAndCloseReachable() throws {
        for sample in ["url-parking-fake", "url-menu-shortener", "url-offline-menu", "text-plain"] {
            launch(sample: sample, language: "cs", extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
            XCTAssertTrue(close("cs").waitForExistence(timeout: 15))
            XCTAssertTrue(close("cs").isHittable)
            XCTAssertTrue(app.descendants(matching: .any)["result.verdict"].firstMatch.exists)
            try save("ax5-" + sample)
            app.swipeUp()
            XCTAssertTrue(close("cs").isHittable)
            close("cs").tap(); app.terminate()
        }
    }
}
