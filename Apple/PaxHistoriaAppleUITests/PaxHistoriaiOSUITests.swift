import XCTest

@MainActor
final class PaxHistoriaiOSUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testCountrySelectionStartsNativeGameAndNavigatesCoreTabs() {
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
        dismissOnboardingIfPresent(in: app)

        tapButton(identifier: "native-map-command-orders", in: app)

        XCTAssertTrue(firstElement("native-orders-screen", in: app).waitForExistence(timeout: 4))
        XCTAssertTrue(firstElement("native-orders-editor", in: app).waitForExistence(timeout: 4))
        XCTAssertTrue(firstElement("native-campaign-objectives-panel", in: app).waitForExistence(timeout: 4))

        tapTab(named: "Map", identifier: "native-map-tab", in: app)
        XCTAssertTrue(firstElement("native-map-screen", in: app).waitForExistence(timeout: 4))

        tapButton(identifier: "native-map-command-advisor", in: app)
        XCTAssertTrue(firstElement("native-intel-screen", in: app).waitForExistence(timeout: 4))

        let diplomacySection = firstElement("native-intel-section-diplomacy", in: app)
        XCTAssertTrue(diplomacySection.waitForExistence(timeout: 4))
        diplomacySection.tap()
        XCTAssertTrue(firstElement("native-diplomacy-panel", in: app).waitForExistence(timeout: 4))

        let diplomaticNetwork = firstElement("native-diplomatic-network", in: app)
        if !diplomaticNetwork.waitForExistence(timeout: 2) {
            app.swipeUp()
        }
        XCTAssertTrue(diplomaticNetwork.waitForExistence(timeout: 4), "Missing diplomatic network:\n\(app.debugDescription)")

        let eventsSection = firstElement("native-intel-section-events", in: app)
        if !eventsSection.waitForExistence(timeout: 2) {
            app.swipeDown()
        }
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

    private func tapTab(named label: String, identifier: String, in app: XCUIApplication) {
        let tabBarButton = app.tabBars.buttons[label]
        if tabBarButton.waitForExistence(timeout: 4) {
            tabBarButton.tap()
            return
        }

        let fallbackButton = app.buttons[identifier]
        XCTAssertTrue(fallbackButton.waitForExistence(timeout: 4))
        fallbackButton.tap()
    }

    private func tapButton(identifier: String, in app: XCUIApplication) {
        let button = app.buttons[identifier]
        XCTAssertTrue(button.waitForExistence(timeout: 4), "Missing button \(identifier):\n\(app.debugDescription)")
        XCTAssertTrue(button.isHittable, "Unhittable button \(identifier):\n\(button.debugDescription)\n\nApp hierarchy:\n\(app.debugDescription)")
        button.tap()
    }

    private func dismissOnboardingIfPresent(in app: XCUIApplication) {
        let skipButton = app.buttons["native-onboarding-skip"]
        if skipButton.waitForExistence(timeout: 2) {
            skipButton.tap()
            XCTAssertFalse(skipButton.waitForExistence(timeout: 2))
        }
    }
}
