import XCTest
import UIKit

@MainActor class RCUIBase: XCTestCase {
    var app = XCUIApplication()
    override func setUpWithError() throws { continueAfterFailure = false }
    func launch(sample: String? = nil, open: String = "scan", language: String = "en", extra: [String] = []) {
        app.launchArguments = ["-onboardingDone", "YES", "-AppleLanguages", "(\(language))", "-BQDebugOpen", open] + extra
        if let sample { app.launchArguments += ["-BQDebugSample", sample] }
        app.launch()
    }
    func save(_ name: String) throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let folder = root.appendingPathComponent(".context/rc-0.0.10/screenshots/ios" + UIDevice.current.systemVersion)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try XCUIScreen.main.screenshot().pngRepresentation.write(to: folder.appendingPathComponent(name + ".png"))
    }
    func close(_ language: String = "en") -> XCUIElement { app.buttons[language == "cs" ? "Zavřít" : "Close"].firstMatch }
    func scrollTo(_ element: XCUIElement, limit: Int = 8) {
        for _ in 0..<limit { if element.exists && element.isHittable { return }; app.swipeUp() }
    }
}

@MainActor final class ResultPresentationUITests: RCUIBase {
    func testResultsOpenInlineAndCloseWithoutRescan() throws {
        for sample in ["url-menu-shortener", "url-parking-fake", "url-offline-menu", "sms-premium-ano", "text-plain", "spd-basic"] {
            launch(sample: sample)
            XCTAssertTrue(close().waitForExistence(timeout: 15))
            XCTAssertTrue(app.descendants(matching: .any)["result.verdict"].firstMatch.exists)
            XCTAssertFalse(app.buttons["result.scanNext"].exists)
            XCTAssertFalse(app.buttons["result.details"].exists)
            XCTAssertFalse(app.buttons["review.menu"].exists)
            XCTAssertTrue(close().isHittable)
            try save(sample + "-en")
            close().tap()
            XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 8))
            app.terminate()
        }
    }
    func testMultipleCodesKeepComparisonAndSelection() throws {
        launch(extra: ["-BQComparisonPreview", "YES"])
        XCTAssertTrue(close().waitForExistence(timeout: 15))
        app.swipeUp()
        try save("multiple-codes")
        let row = app.buttons.containing(NSPredicate(format: "label CONTAINS[c] 'kavarnaulipy'")).firstMatch
        scrollTo(row)
        XCTAssertTrue(row.isHittable); row.tap()
        let all = app.buttons["All codes"]
        XCTAssertTrue(all.waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["result.verdict"].firstMatch.exists)
        all.tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        close().tap()
    }
    func testDetailsExpandOnSameSheetWithClosePinned() throws {
        launch(sample: "url-menu-shortener")
        XCTAssertTrue(close().waitForExistence(timeout: 15))
        let details = app.buttons["Check details"]
        scrollTo(details); XCTAssertTrue(details.isHittable); details.tap()
        XCTAssertTrue(close().isHittable)
        XCTAssertFalse(app.buttons["Back"].exists)
        try save("inline-details")
        close().tap()
    }
    func testDangerRetainsAccessibleConfirmation() throws {
        launch(sample: "url-parking-fake")
        XCTAssertTrue(close().waitForExistence(timeout: 15))
        let more = app.buttons["More options"]
        scrollTo(more)
        if more.isHittable { more.tap() }
        let alternative = app.buttons["Or open with a confirmation"]
        scrollTo(alternative)
        XCTAssertTrue(alternative.isHittable)
        alternative.tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.alerts.buttons["Cancel"].exists)
        app.alerts.buttons["Cancel"].tap()
        XCTAssertTrue(close().isHittable)
        try save("danger-confirmation-preserved")
    }
}
