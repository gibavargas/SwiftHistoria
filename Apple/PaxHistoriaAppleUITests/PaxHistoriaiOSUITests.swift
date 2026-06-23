import XCTest

@MainActor
final class PaxHistoriaiOSUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testCountrySelectionStartsNativeGameAndNavigatesCoreTabs() {
        let app = launchResetApp()

        let continueButton = app.buttons["native-country-continue"]
        XCTAssertTrue(continueButton.waitForExistence(timeout: 8))
        continueButton.tap()

        let appleProvider = app.buttons["native-provider-appleFoundation"]
        XCTAssertTrue(appleProvider.waitForExistence(timeout: 8))
        appleProvider.tap()

        let providerContinueButton = app.buttons["native-provider-continue"]
        XCTAssertTrue(providerContinueButton.waitForExistence(timeout: 4))
        XCTAssertTrue(providerContinueButton.isEnabled)
        providerContinueButton.tap()

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

    func testPlayerCanIssueOrderAskAdvisorSendDiplomacyAndAdvanceTurn() {
        let app = launchResetApp(fakeAI: true)
        startBrazilCampaign(in: app)

        tapButton(identifier: "native-map-command-orders", in: app)
        XCTAssertTrue(firstElement("native-orders-editor", in: app).waitForExistence(timeout: 4))

        let orderEditor = firstElement("native-action-editor", in: app)
        XCTAssertTrue(orderEditor.waitForExistence(timeout: 4))
        orderEditor.tap()
        orderEditor.typeText("Fund UI test rail corridor buffers.")
        dismissKeyboardIfPresent(in: app)

        tapButton(identifier: "native-add-order", in: app)
        XCTAssertTrue(app.staticTexts["Fund UI test rail corridor buffers"].waitForExistence(timeout: 4))

        tapTab(named: "Map", identifier: "native-map-tab", in: app)
        tapButton(identifier: "native-map-command-advisor", in: app)
        let advisorQuestion = firstElement("native-advisor-question", in: app)
        XCTAssertTrue(advisorQuestion.waitForExistence(timeout: 4))
        advisorQuestion.tap()
        advisorQuestion.typeText("What should we prioritize next?")
        dismissKeyboardIfPresent(in: app)
        tapButton(identifier: "native-ask-advisor", in: app)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "UI Test Advisor Response")).firstMatch.waitForExistence(timeout: 8))

        tapButton(identifier: "native-intel-section-diplomacy", in: app)
        let diplomacyMessage = firstElement("native-diplomacy-message", in: app)
        XCTAssertTrue(diplomacyMessage.waitForExistence(timeout: 4))
        diplomacyMessage.tap()
        diplomacyMessage.typeText("Coordinate UI test trade resilience.")
        dismissKeyboardIfPresent(in: app)
        tapButton(identifier: "native-send-diplomacy", in: app)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "UI Test Diplomatic Response")).firstMatch.waitForExistence(timeout: 8))

        tapTab(named: "Map", identifier: "native-map-tab", in: app)
        tapButton(identifier: "native-advance-menu", in: app)
        tapMenuButton(title: "1 month", identifier: "native-advance-1", in: app)

        XCTAssertTrue(firstElement("native-turn-report", in: app).waitForExistence(timeout: 12), "Missing turn report:\n\(app.debugDescription)")
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "UI Test Order Resolved")).firstMatch.waitForExistence(timeout: 4))
        tapButton(identifier: "native-report-close", in: app)

        tapButton(identifier: "native-map-command-orders", in: app)
        XCTAssertTrue(app.staticTexts["Fund UI test rail corridor buffers"].waitForExistence(timeout: 4))
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
        for _ in 0 ..< 4 where !button.isHittable {
            app.swipeUp()
        }
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

    private func dismissKeyboardIfPresent(in app: XCUIApplication) {
        guard app.keyboards.firstMatch.exists else { return }
        app.swipeDown()

        if app.keyboards.firstMatch.waitForExistence(timeout: 1) {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).tap()
        }
    }

    private func tapMenuButton(title: String, identifier: String, in app: XCUIApplication) {
        let identifiedButton = app.buttons[identifier]
        if identifiedButton.waitForExistence(timeout: 2) {
            identifiedButton.tap()
            return
        }

        let titledButton = app.buttons[title]
        XCTAssertTrue(titledButton.waitForExistence(timeout: 4), "Missing menu item \(title):\n\(app.debugDescription)")
        titledButton.tap()
    }

    private func launchResetApp(fakeAI: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["PAX_HISTORIA_UI_TEST_RESET"] = "1"
        app.launchEnvironment["PAX_HISTORIA_SKIP_ONBOARDING"] = "1"
        app.launchArguments = ["--pax-historia-ui-test-reset", "--pax-historia-skip-onboarding"]
        if fakeAI {
            app.launchEnvironment["PAX_HISTORIA_UI_TEST_FAKE_AI"] = "1"
            app.launchArguments.append("--pax-historia-ui-test-fake-ai")
        }
        app.launch()
        return app
    }

    private func startBrazilCampaign(in app: XCUIApplication) {
        let continueButton = app.buttons["native-country-continue"]
        XCTAssertTrue(continueButton.waitForExistence(timeout: 8))
        continueButton.tap()

        let appleProvider = app.buttons["native-provider-appleFoundation"]
        XCTAssertTrue(appleProvider.waitForExistence(timeout: 8))
        appleProvider.tap()

        let providerContinueButton = app.buttons["native-provider-continue"]
        XCTAssertTrue(providerContinueButton.waitForExistence(timeout: 4))
        providerContinueButton.tap()

        let searchField = app.textFields["native-country-search"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 8))
        searchField.tap()
        searchField.typeText("Brazil")

        let brazilOption = app.buttons["native-country-option-BRA"]
        XCTAssertTrue(brazilOption.waitForExistence(timeout: 4))
        brazilOption.tap()

        let mapScreen = firstElement("native-map-screen", in: app)
        XCTAssertTrue(mapScreen.waitForExistence(timeout: 8), "Post-country hierarchy:\n\(app.debugDescription)")
    }
}
