import XCTest

/// The light/dark button in the bottom-right corner: a tap flips the look, and the choice survives a relaunch.
final class AppearanceJourneyTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testAppearanceButtonToggles() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-test-scenario", "catalog"]
        app.launch()
        let toggle = app.element("app-button-appearance")
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        let before = toggle.value as? String

        toggle.tap()
        let after = before == "1" ? "0" : "1"
        wait(for: toggle, value: after)

        app.terminate()
        app.launch()
        wait(for: toggle, value: after)

        // Back to how the run found it, so the next journey starts on the same look.
        toggle.tap()
        wait(for: toggle, value: before ?? "0")
    }

    @MainActor
    private func wait(for toggle: XCUIElement, value: String) {
        let isValue = NSPredicate(format: "value == %@", value)
        let expectation = XCTNSPredicateExpectation(predicate: isValue, object: toggle)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed, "toggle value is not \(value)")
    }
}

extension XCUIApplication {
    fileprivate func element(_ identifier: String) -> XCUIElement {
        descendants(matching: .any).matching(identifier: identifier).firstMatch
    }
}
