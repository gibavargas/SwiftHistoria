import XCTest

@MainActor
final class PaxHistoriaiOSUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testCountrySelectionStartsNativeGameAndNavigatesCoreTabs() throws {
        let app = XCUIApplication()
        app.launchEnvironment["PAX_HISTORIA_UI_TEST_RESET"] = "1"
        app.launchArguments = ["--pax-historia-ui-test-reset"]
        app.launch()

        let continueButton = app.buttons["native-country-continue"]
        XCTAssertTrue(continueButton.waitForExistence(timeout: 8))
        continueButton.tap()

        let searchField = app.textFields["native-country-search"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 8))
        XCTAssertTrue(element("native-country-list", in: app).waitForExistence(timeout: 4))
        searchField.tap()
        searchField.typeText("Brazil")

        let brazilOption = app.buttons["native-country-option-BRA"]
        XCTAssertTrue(brazilOption.waitForExistence(timeout: 4))
        brazilOption.tap()

        let mapScreen = firstElement("native-map-screen", in: app)
        XCTAssertTrue(mapScreen.waitForExistence(timeout: 8), "Post-country hierarchy:\n\(app.debugDescription)")
        XCTAssertTrue(mapScreen.label.localizedCaseInsensitiveContains("Strategic map"))

        let ordersTab = app.buttons["native-orders-tab"]
        XCTAssertTrue(ordersTab.waitForExistence(timeout: 4))
        ordersTab.tap()

        XCTAssertTrue(firstElement("native-orders-screen", in: app).waitForExistence(timeout: 4))
        XCTAssertTrue(firstElement("native-orders-editor", in: app).waitForExistence(timeout: 4))

        let mapTab = app.buttons["native-map-tab"]
        XCTAssertTrue(mapTab.waitForExistence(timeout: 4))
        mapTab.tap()
        XCTAssertTrue(firstElement("native-map-screen", in: app).waitForExistence(timeout: 4))

        let intelTab = app.buttons["native-intel-tab"]
        XCTAssertTrue(intelTab.waitForExistence(timeout: 4))
        intelTab.tap()
        XCTAssertTrue(firstElement("native-intel-screen", in: app).waitForExistence(timeout: 4))

        let eventsSection = firstElement("native-intel-section-events", in: app)
        XCTAssertTrue(eventsSection.waitForExistence(timeout: 4))
        eventsSection.tap()
        XCTAssertTrue(firstElement("native-events-panel", in: app).waitForExistence(timeout: 4))
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    private func firstElement(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }
}
