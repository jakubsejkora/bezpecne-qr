import XCTest

@MainActor final class SettingsFooterUITests: RCUIBase {
    func testHistoryExportPreviewsActualContentAndOpensNativeSharing() throws {
        launch(open: "settings")
        let toggle = app.switches["Keep history"]
        scrollTo(toggle)
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        if toggle.value as? String == "0" { toggle.tap() }
        app.terminate()
        let note = "RC export example note"
        launch(extra: ["-BQDebugURL", note])
        XCTAssertTrue(close().waitForExistence(timeout: 15)); close().tap()
        app.tabBars.buttons["Settings"].tap()
        let history = app.buttons["History"]
        scrollTo(history); history.tap()
        let export = app.buttons["Export history"]
        scrollTo(export)
        XCTAssertTrue(export.waitForExistence(timeout: 8)); export.tap()
        let share = app.buttons["Share JSON file"]
        scrollTo(share)
        XCTAssertTrue(share.waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", note)).firstMatch.exists)
        try save("history-export-preview")
        share.tap()
        XCTAssertTrue(close().waitForExistence(timeout: 8)); close().tap()
        XCTAssertTrue(share.isHittable)
    }
    func testCoffeeCreditsAndVersionAreVisible() throws {
        launch(open: "settings", language: "cs")
        let credit = app.staticTexts["Vytvořil Jakub Sejkora"]
        scrollTo(credit)
        XCTAssertTrue(credit.isHittable)
        let shop = app.descendants(matching: .any)["credits.shop"].firstMatch
        scrollTo(shop)
        XCTAssertTrue(shop.exists)
        try save("settings-coffee-cs")
    }
}
