import XCTest

@MainActor final class FadeReviewUITests: RCUIBase {
    func testNativeNavigationAndUnboxedHeadings() throws {
        launch(extra: ["-BQAimPreview", "YES"])
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 15))
        XCTAssertEqual(app.tabBars.buttons.count, 3)
        XCTAssertFalse(app.tabBars.buttons["History"].exists)
        XCTAssertFalse(app.buttons["review.menu"].exists)
        XCTAssertFalse(app.statusBars.firstMatch.exists)
        try save("scan-en")
        app.tabBars.buttons["Help"].tap()
        XCTAssertTrue(app.staticTexts["Practical help when you need it."].waitForExistence(timeout: 5))
        try save("help-en")
        app.tabBars.buttons["Settings"].tap()
        let history = app.buttons["History"]
        XCTAssertTrue(history.waitForExistence(timeout: 5))
        try save("settings-en")
        history.tap()
        XCTAssertFalse(app.statusBars.firstMatch.exists)
        try save("history-en")
        app.tabBars.buttons["Scan"].tap()
        XCTAssertTrue(app.staticTexts["Bezpečné QR"].firstMatch.waitForExistence(timeout: 5))
        try save("scan-after-history")
    }
    func testPhotoPickerCancellationReturnsToScanner() throws {
        launch()
        let photos = app.buttons["scan.photos"]
        XCTAssertTrue(photos.waitForExistence(timeout: 15)); photos.tap()
        let cancel = app.buttons["Cancel"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 8)); cancel.tap()
        XCTAssertTrue(photos.waitForExistence(timeout: 8))
        XCTAssertTrue(photos.isHittable)
        app.tabBars.buttons["Settings"].tap()
        app.tabBars.buttons["Scan"].tap()
        XCTAssertTrue(photos.isHittable)
    }
    func testNavigationTransitionsRecording() throws {
        launch(extra: ["-BQAimPreview", "YES"])
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 15))
        for _ in 0..<2 {
            for name in ["Help", "Scan", "Settings", "Scan"] {
                app.tabBars.buttons[name].tap()
                XCTAssertTrue(app.tabBars.buttons[name].isSelected)
                XCTAssertFalse(app.statusBars.firstMatch.exists)
            }
        }
    }
}
