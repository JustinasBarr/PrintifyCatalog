import XCTest

/// The main journeys on recorded responses (`-ui-test-scenario`), so they run the same with or without a
/// connection. Elements are found by accessibility identifier only, never by visible text.
final class CatalogJourneyTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testSeeAllCategory() {
        let app = launched(scenario: "catalog")
        let seeAll = app.element("home-button-seeAll-groceries")
        swipeUp(app, until: seeAll)
        seeAll.tap()

        let grid = app.element("list-grid-products")
        XCTAssertTrue(grid.waitForExistence(timeout: 5))
        XCTAssertTrue(app.element("list-cell-16").waitForExistence(timeout: 5))
        // The recorded first page ends at product 27; 28 opens the second page.
        swipeUp(grid, until: app.element("list-cell-28"))
    }

    @MainActor
    func testOfflineShowsRetry() {
        let app = launched(scenario: "offline")
        XCTAssertTrue(app.element("home-button-retry").waitForExistence(timeout: 5))
    }

    @MainActor
    private func launched(scenario: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-test-scenario", scenario]
        app.launch()
        return app
    }

    /// Swipes `container` up until `target` can be tapped; a lazy list draws a row only near the screen.
    @MainActor
    private func swipeUp(_ container: XCUIElement, until target: XCUIElement) {
        for _ in 0..<12 {
            if target.waitForExistence(timeout: 1), target.isHittable { return }
            container.swipeUp()
        }
        XCTFail("\(target) never appeared")
    }
}

extension XCUIApplication {
    fileprivate func element(_ identifier: String) -> XCUIElement {
        descendants(matching: .any).matching(identifier: identifier).firstMatch
    }
}
