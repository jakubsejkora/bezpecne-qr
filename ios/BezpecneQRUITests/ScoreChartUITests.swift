import XCTest

@MainActor final class ScoreChartUITests: RCUIBase {
    func testOnlyRemainingDesignComparisonsAreAvailable() throws {
        launch(open: "lab")
        let charts = app.buttons["scoreChart.open"]
        XCTAssertTrue(charts.waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["review.statusBarPreference"].exists)
        XCTAssertFalse(app.staticTexts["Signal · header style"].exists)
        charts.tap()
        let dots = app.buttons["scoreChart.option.dots"]
        scrollTo(dots); XCTAssertTrue(dots.isHittable); dots.tap()
        XCTAssertTrue(dots.isSelected)
        try save("remaining-score-choices")
        app.terminate()
        launch(open: "scores")
        scrollTo(app.buttons["scoreChart.option.dots"])
        XCTAssertTrue(app.buttons["scoreChart.option.dots"].isSelected)
        let spectrum = app.buttons["scoreChart.option.spectrum"]
        for _ in 0..<5 { if spectrum.isHittable { break }; app.swipeDown() }
        spectrum.tap()
    }
}
