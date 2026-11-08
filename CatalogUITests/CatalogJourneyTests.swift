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
    func testSearchSaysHowManyMatch() {
        let app = launched(scenario: "catalog")
        let field = openSearch(app)
        field.typeText("red")

        XCTAssertTrue(app.element("search-text-count").waitForExistence(timeout: 5))
        XCTAssertTrue(app.element("search-cell-4").exists)
    }

    @MainActor
    func testSearchWithNoMatchSaysSo() {
        let app = launched(scenario: "catalog")
        let field = openSearch(app)
        field.typeText("qwerty")

        XCTAssertTrue(app.element("search-text-empty").waitForExistence(timeout: 5))
        XCTAssertFalse(app.element("search-text-count").exists)
    }

    @MainActor
    func testSortByPriceReordersTheList() {
        let app = launched(scenario: "catalog")
        let seeAll = app.element("home-button-seeAll-groceries")
        swipeUp(app, until: seeAll)
        seeAll.tap()
        let firstCell = app.element("list-cell-16")
        XCTAssertTrue(firstCell.waitForExistence(timeout: 5))
        let firstFrame = firstCell.frame

        app.element("list-button-sortFilter").tap()
        app.element("sort-option-priceLow").tap()
        app.element("sort-button-done").tap()

        // The cheapest grocery, 31, is not on the unsorted first page; sorted by price it takes the first cell.
        let cheapest = app.element("list-cell-31")
        XCTAssertTrue(cheapest.waitForExistence(timeout: 5))
        XCTAssertEqual(cheapest.frame.minX, firstFrame.minX, accuracy: 1)
        XCTAssertEqual(cheapest.frame.minY, firstFrame.minY, accuracy: 1)
    }

    @MainActor
    func testOfflineRetryKeepsTheError() {
        let app = launched(scenario: "offline")
        let retry = app.element("home-button-retry")
        XCTAssertTrue(retry.waitForExistence(timeout: 5))

        retry.tap()

        XCTAssertTrue(retry.waitForExistence(timeout: 5))
        XCTAssertEqual(app.state, .runningForeground)
    }

    @MainActor
    private func launched(scenario: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-test-scenario", scenario]
        app.launch()
        return app
    }

    /// Focuses Home's search field, which searches in place, and returns it.
    @MainActor
    private func openSearch(_ app: XCUIApplication) -> XCUIElement {
        let field = app.element("search-field-query")
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        return field
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
