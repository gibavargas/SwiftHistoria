import XCTest

@MainActor
final class PaxHistoriaiOSUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testCountrySelectionStartsNativeGameAndNavigatesCoreTabs() {
        let app = launchResetApp(fakeAI: true)

        let continueButton = app.buttons["native-country-continue"]
        XCTAssertTrue(continueButton.waitForExistence(timeout: 8))
        continueButton.tap()

        let nvidiaProvider = app.buttons["native-provider-nvidia"]
        XCTAssertTrue(nvidiaProvider.waitForExistence(timeout: 8))
        nvidiaProvider.tap()

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
        XCTAssertTrue(firstElement("native-decision-matrix", in: app).waitForExistence(timeout: 8))
        XCTAssertTrue(firstElement("native-decision-cell-0-0", in: app).waitForExistence(timeout: 4))
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

        tapButton(identifier: "native-console-toggle", in: app)
        XCTAssertTrue(firstElement("native-orders-editor", in: app).waitForExistence(timeout: 4))

        let orderEditor = firstElement("native-action-editor", in: app)
        XCTAssertTrue(orderEditor.waitForExistence(timeout: 4))
        orderEditor.tap()
        orderEditor.typeText("Fund UI test rail corridor buffers.")
        dismissKeyboardIfPresent(in: app)

        tapButton(identifier: "native-add-order", in: app)
        XCTAssertTrue(app.staticTexts["Fund UI test rail corridor buffers"].waitForExistence(timeout: 4))

        tapButton(identifier: "native-console-toggle", in: app)
        tapButton(identifier: "native-map-command-advisor", in: app)
        let advisorQuestion = firstElement("native-advisor-question", in: app)
        XCTAssertTrue(advisorQuestion.waitForExistence(timeout: 4))
        advisorQuestion.tap()
        advisorQuestion.typeText("What should we prioritize next?")
        dismissKeyboardIfPresent(in: app)
        tapButton(identifier: "native-ask-advisor", in: app)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "UI Test Advisor Response")).firstMatch.waitForExistence(timeout: 8))

        tapIntelSection(identifier: "native-intel-section-diplomacy", in: app)
        let diplomacyMessage = firstElement("native-diplomacy-message", in: app)
        XCTAssertTrue(diplomacyMessage.waitForExistence(timeout: 4))
        diplomacyMessage.tap()
        diplomacyMessage.typeText("Coordinate UI test trade resilience.")
        dismissKeyboardIfPresent(in: app)
        tapButton(identifier: "native-send-diplomacy", in: app)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "UI Test Diplomatic Response")).firstMatch.waitForExistence(timeout: 8))

        tapTab(named: "Map", identifier: "native-map-tab", in: app)
        tapButton(identifier: "native-advance-3", in: app)

        XCTAssertTrue(firstElement("native-turn-report", in: app).waitForExistence(timeout: 12), "Missing turn report:\n\(app.debugDescription)")
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "UI Test Order Resolved")).firstMatch.waitForExistence(timeout: 4))
        dismissTurnReport(in: app)

        tapButton(identifier: "native-map-command-orders", in: app)
        let resolvedOrder = app.staticTexts["Fund UI test rail corridor buffers"]
        let ordersScreen = firstElement("native-orders-screen", in: app)
        for _ in 0 ..< 8 where !resolvedOrder.exists {
            ordersScreen.swipeUp()
        }
        XCTAssertTrue(resolvedOrder.waitForExistence(timeout: 4), "Resolved order should remain in campaign history")
    }

    // MARK: - Expanded UI Regression Tests

    func testSetupScenarioSelectionChangesAccentAndAdvances() {
        let app = launchResetApp()
        let continueButton = app.buttons["native-country-continue"]
        XCTAssertTrue(continueButton.waitForExistence(timeout: 8), "Continue button should exist on scenario selection screen")

        // Tap any available scenario card and verify continue button stays enabled
        let scenarioCards = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "native-scenario-option-"))
        if scenarioCards.count > 0 {
            scenarioCards.element(boundBy: 0).tap()
        }
        XCTAssertTrue(continueButton.isEnabled, "Continue button should be enabled after selecting a scenario")
    }

    func testSetupProviderCardsAreAllTappable() {
        // The two supported provider cards should exist and be tappable.
        let app = launchResetApp()
        XCTAssertTrue(app.buttons["native-country-continue"].waitForExistence(timeout: 8))
        app.buttons["native-country-continue"].tap()
        for id in ["native-provider-nvidia", "native-provider-openRouter"] {
            let card = app.buttons[id]
            XCTAssertTrue(card.waitForExistence(timeout: 6), "Provider card \(id) not found")
            XCTAssertTrue(card.isHittable, "Provider card \(id) is not hittable")
            card.tap()
        }
    }

    func testSetupBackNavigationFromProviderStep() {
        let app = launchResetApp()
        app.buttons["native-country-continue"].tap()
        XCTAssertTrue(app.buttons["native-provider-nvidia"].waitForExistence(timeout: 8))
        app.buttons["native-provider-back"].tap()
        XCTAssertTrue(app.buttons["native-country-continue"].waitForExistence(timeout: 4))
    }

    func testSetupBackNavigationFromCountryStep() {
        let app = launchResetApp(fakeAI: true)
        app.buttons["native-country-continue"].tap()
        app.buttons["native-provider-nvidia"].tap()
        app.buttons["native-provider-continue"].tap()
        app.buttons["native-country-back"].tap()
        XCTAssertTrue(app.buttons["native-provider-continue"].waitForExistence(timeout: 4))
    }

    func testSetupClearSearchButton() {
        let app = launchResetApp(fakeAI: true)
        app.buttons["native-country-continue"].tap()
        app.buttons["native-provider-nvidia"].tap()
        app.buttons["native-provider-continue"].tap()
        let search = app.textFields["native-country-search"]
        search.tap()
        search.typeText("ZZZ")
        let clearSearch = app.buttons["native-country-clear-search"]
        XCTAssertTrue(clearSearch.waitForExistence(timeout: 4))
        clearSearch.tap()
        XCTAssertEqual(search.value as? String, "Search country or ISO code")
    }

    func testMapCommandBarOrdersButton() {
        let app = launchResetApp(fakeAI: true)
        startBrazilCampaign(in: app)
        tapButton(identifier: "native-map-command-orders", in: app)
        XCTAssertTrue(firstElement("native-orders-screen", in: app).waitForExistence(timeout: 4))
    }

    func testMapCommandBarAdvisorButton() {
        let app = launchResetApp(fakeAI: true)
        startBrazilCampaign(in: app)
        tapButton(identifier: "native-map-command-advisor", in: app)
        XCTAssertTrue(firstElement("native-intel-screen", in: app).waitForExistence(timeout: 4))
    }

    func testMapCommandBarDiplomacyButton() {
        // Diplomacy is accessed by opening Intel and tapping the diplomacy section
        let app = launchResetApp(fakeAI: true)
        startBrazilCampaign(in: app)
        tapButton(identifier: "native-map-command-advisor", in: app)
        tapButton(identifier: "native-intel-section-diplomacy", in: app)
        XCTAssertTrue(firstElement("native-diplomacy-panel", in: app).waitForExistence(timeout: 4))
    }

    func testMapAdvanceOnlyOffersFixedThreeMonthTurn() {
        let app = launchResetApp(fakeAI: true)
        startBrazilCampaign(in: app)
        XCTAssertTrue(app.buttons["native-advance-3"].exists)
        XCTAssertFalse(app.buttons["native-advance-1"].exists)
        XCTAssertFalse(app.buttons["native-advance-12"].exists)
    }

    func testMapAdvance3MonthsStartsTurnReport() {
        let app = launchResetApp(fakeAI: true)
        startBrazilCampaign(in: app)
        tapButton(identifier: "native-advance-3", in: app)
        XCTAssertTrue(firstElement("native-turn-report", in: app).waitForExistence(timeout: 12))
    }

    func testTurnReportDismissViaAcknowledgeButton() {
        let app = launchResetApp(fakeAI: true)
        startBrazilCampaign(in: app)
        tapButton(identifier: "native-advance-3", in: app)
        let tr = firstElement("native-turn-report", in: app)
        XCTAssertTrue(tr.waitForExistence(timeout: 12))
        app.buttons["ACKNOWLEDGE & CLOSE DOSSIER"].tap()
        XCTAssertFalse(tr.exists)
    }

    func testConsoleDrawerToggle() {
        let app = launchResetApp(fakeAI: true)
        startBrazilCampaign(in: app)
        app.buttons["native-console-toggle"].tap()
        XCTAssertTrue(firstElement("console-tab-orders", in: app).exists)
        app.buttons["native-console-toggle"].tap()
        XCTAssertFalse(firstElement("console-tab-orders", in: app).exists)
    }

    func testConsoleAllTabs() {
        let app = launchResetApp(fakeAI: true)
        startBrazilCampaign(in: app)
        tapButton(identifier: "native-console-toggle", in: app)
        for item in ["console-tab-orders", "console-tab-suggestions", "console-tab-advisor", "console-tab-diplomacy", "console-tab-events"] {
            firstElement(item, in: app).tap()
        }
    }

    func testOrdersAddAndDeleteOrder() {
        let app = launchResetApp(fakeAI: true)
        startBrazilCampaign(in: app)
        tapButton(identifier: "native-console-toggle", in: app)
        let editor = firstElement("native-action-editor", in: app)
        editor.tap()
        editor.typeText("UI test")
        dismissKeyboardIfPresent(in: app)
        tapButton(identifier: "native-add-order", in: app)
        // identifiers are native-delete-order-<uuid> so use BEGINSWITH
        let deleteButtons = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "native-delete-order-"))
        let ordersPanel = firstElement("native-orders-editor", in: app)
        for _ in 0 ..< 3 where !deleteButtons.firstMatch.exists {
            ordersPanel.swipeUp()
        }
        XCTAssertTrue(deleteButtons.firstMatch.waitForExistence(timeout: 4), "Delete order button should appear after adding an order")
        deleteButtons.firstMatch.tap()
        XCTAssertFalse(app.staticTexts["UI test"].exists)
    }

    func testOrdersAddButtonDisabledWhenEmpty() {
        let app = launchResetApp(fakeAI: true)
        startBrazilCampaign(in: app)
        tapButton(identifier: "native-console-toggle", in: app)
        XCTAssertFalse(firstElement("native-add-order", in: app).isEnabled)
    }

    func testSuggestedActionsRefreshButton() {
        let app = launchResetApp(fakeAI: true)
        startBrazilCampaign(in: app)
        tapButton(identifier: "native-map-command-orders", in: app)
        firstElement("native-refresh-suggestions", in: app).tap()
        XCTAssertTrue(firstElement("native-refresh-suggestions", in: app).exists)
    }

    func testApplySuggestionAddsToOrders() {
        let app = launchResetApp(fakeAI: true)
        startBrazilCampaign(in: app)
        tapButton(identifier: "native-map-command-orders", in: app)
        let matrix = firstElement("native-decision-matrix", in: app)
        XCTAssertTrue(matrix.waitForExistence(timeout: 8))
        let firstDecision = firstElement("native-decision-cell-0-0", in: app)
        XCTAssertTrue(firstDecision.waitForExistence(timeout: 4))
        firstDecision.tap()
        XCTAssertFalse(firstDecision.isEnabled, "Queued matrix cell should be disabled and visibly selected")
    }

    func testIntelSectionSelectorAllButtons() {
        let app = launchResetApp(fakeAI: true)
        startBrazilCampaign(in: app)
        tapButton(identifier: "native-map-command-advisor", in: app)
        for item in ["native-intel-section-advisor", "native-intel-section-diplomacy", "native-intel-section-events", "native-intel-section-worldEconomics", "native-intel-section-library", "native-intel-section-settings"] {
            tapIntelSection(identifier: item, in: app)
        }
    }

    func testAdvisorAskButtonDisabledWhenEmpty() {
        let app = launchResetApp(fakeAI: true)
        startBrazilCampaign(in: app)
        tapButton(identifier: "native-map-command-advisor", in: app)
        tapIntelSection(identifier: "native-intel-section-advisor", in: app)
        XCTAssertFalse(firstElement("native-ask-advisor", in: app).isEnabled)
    }

    func testAdvisorStarterFillsAReadyToSendQuestion() {
        let app = launchResetApp(fakeAI: true)
        startBrazilCampaign(in: app)
        tapButton(identifier: "native-map-command-advisor", in: app)
        tapIntelSection(identifier: "native-intel-section-advisor", in: app)

        let starter = app.buttons["native-advisor-starter-0"]
        XCTAssertTrue(starter.waitForExistence(timeout: 4))
        starter.tap()

        let question = firstElement("native-advisor-question", in: app)
        XCTAssertEqual(question.value as? String, "What is the most urgent risk this turn?")
        XCTAssertTrue(firstElement("native-ask-advisor", in: app).isEnabled)
    }

    func testDiplomacySendButtonDisabledWhenEmpty() {
        let app = launchResetApp(fakeAI: true)
        startBrazilCampaign(in: app)
        tapButton(identifier: "native-map-command-advisor", in: app)
        tapIntelSection(identifier: "native-intel-section-diplomacy", in: app)
        XCTAssertFalse(firstElement("native-send-diplomacy", in: app).isEnabled)
    }

    func testDiplomacyStarterFillsAReadyToSendProposal() {
        let app = launchResetApp(fakeAI: true)
        startBrazilCampaign(in: app)
        tapButton(identifier: "native-map-command-advisor", in: app)
        tapIntelSection(identifier: "native-intel-section-diplomacy", in: app)

        let starter = app.buttons["native-diplomacy-starter-0"]
        XCTAssertTrue(starter.waitForExistence(timeout: 4))
        starter.tap()

        let message = firstElement("native-diplomacy-message", in: app)
        XCTAssertEqual(message.value as? String, "Propose a trade resilience compact.")
        XCTAssertTrue(firstElement("native-send-diplomacy", in: app).isEnabled)
    }

    func testLibraryExportButtonExists() {
        let app = launchResetApp(fakeAI: true)
        startBrazilCampaign(in: app)
        tapButton(identifier: "native-map-command-advisor", in: app)
        tapIntelSection(identifier: "native-intel-section-library", in: app)
        XCTAssertTrue(firstElement("native-export-campaign", in: app).isEnabled)
    }

    func testLibraryImportButtonExists() {
        let app = launchResetApp(fakeAI: true)
        startBrazilCampaign(in: app)
        tapButton(identifier: "native-map-command-advisor", in: app)
        tapIntelSection(identifier: "native-intel-section-library", in: app)
        XCTAssertTrue(firstElement("native-import-campaign", in: app).isEnabled)
    }

    func testSettingsPollStatusButton() {
        let app = launchResetApp(fakeAI: true)
        startBrazilCampaign(in: app)
        tapButton(identifier: "native-map-command-advisor", in: app)
        tapIntelSection(identifier: "native-intel-section-settings", in: app)
        tapButton(identifier: "native-apple-status-check", in: app)
    }

    func testSettingsSaveCampaignButton() {
        let app = launchResetApp(fakeAI: true)
        startBrazilCampaign(in: app)
        tapButton(identifier: "native-map-command-advisor", in: app)
        tapIntelSection(identifier: "native-intel-section-settings", in: app)
        tapButton(identifier: "native-save-campaign", in: app)
    }

    func testSettingsSwitchesBetweenOnlyNVIDIAAndOpenRouterFree() {
        let app = launchResetApp(fakeAI: true)
        startBrazilCampaign(in: app)
        tapButton(identifier: "native-map-command-advisor", in: app)
        tapIntelSection(identifier: "native-intel-section-settings", in: app)

        let settings = firstElement("native-settings-panel", in: app)
        let section = firstElement("native-ai-connection-section", in: app)
        for _ in 0 ..< 8 where !section.isHittable {
            settings.swipeUp()
        }
        XCTAssertTrue(section.waitForExistence(timeout: 4))
        section.tap()

        let picker = firstElement("native-ai-provider-picker", in: app)
        XCTAssertTrue(picker.waitForExistence(timeout: 4))
        let openRouter = picker.buttons["OpenRouter Free"]
        let nvidia = picker.buttons["NVIDIA NIM"]
        XCTAssertTrue(openRouter.exists)
        XCTAssertTrue(nvidia.exists)
        XCTAssertEqual(picker.buttons.count, 2)
        openRouter.tap()
        XCTAssertTrue(openRouter.isSelected)
        nvidia.tap()
        XCTAssertTrue(nvidia.isSelected)
    }

    func testSettingsExitToMainMenuButton() {
        let app = launchResetApp(fakeAI: true)
        startBrazilCampaign(in: app)
        tapButton(identifier: "native-map-command-advisor", in: app)
        tapIntelSection(identifier: "native-intel-section-settings", in: app)
        openCampaignManagement(in: app)
        tapButton(identifier: "native-exit-to-menu", in: app)
        XCTAssertTrue(app.buttons["native-country-continue"].waitForExistence(timeout: 8))
    }

    func testSettingsResetAndDeleteButton() {
        let app = launchResetApp(fakeAI: true)
        startBrazilCampaign(in: app)
        tapButton(identifier: "native-map-command-advisor", in: app)
        tapIntelSection(identifier: "native-intel-section-settings", in: app)
        openCampaignManagement(in: app)
        tapButton(identifier: "native-change-country", in: app)
        XCTAssertTrue(app.buttons["native-country-continue"].waitForExistence(timeout: 8))
    }

    func testSettingsCanCreateDynamicCountry() {
        let app = launchResetApp(fakeAI: true)
        startBrazilCampaign(in: app)
        tapButton(identifier: "native-map-command-advisor", in: app)
        tapIntelSection(identifier: "native-intel-section-settings", in: app)
        openCampaignManagement(in: app)

        let settings = firstElement("native-settings-panel", in: app)
        let countryPanel = firstElement("native-new-country-panel", in: app)
        for _ in 0 ..< 10 where !countryPanel.isHittable {
            settings.swipeUp()
        }
        XCTAssertTrue(countryPanel.waitForExistence(timeout: 4))
        countryPanel.tap()

        let codeField = firstElement("native-new-country-code", in: app)
        let nameField = firstElement("native-new-country-name", in: app)
        XCTAssertTrue(codeField.waitForExistence(timeout: 4))
        codeField.tap()
        codeField.typeText("ATL")
        nameField.tap()
        nameField.typeText("Atlantic Federation")
        dismissKeyboardIfPresent(in: app)

        tapButton(identifier: "native-add-country-button", in: app)
        XCTAssertTrue(app.staticTexts["Atlantic Federation"].waitForExistence(timeout: 4))
    }

    func testWorldEconomicsExposesResearchAndStandingForces() {
        let app = launchResetApp(fakeAI: true)
        startBrazilCampaign(in: app)
        tapButton(identifier: "native-map-command-advisor", in: app)
        tapIntelSection(identifier: "native-intel-section-worldEconomics", in: app)

        let economics = firstElement("native-world-economics-screen", in: app)
        let readiness = firstElement("native-research-force-panel", in: app)
        for _ in 0 ..< 5 where !readiness.isHittable {
            economics.swipeUp()
        }

        XCTAssertTrue(readiness.waitForExistence(timeout: 4))
        XCTAssertTrue(firstElement("native-research-progress", in: app).exists)
        XCTAssertTrue(firstElement("native-research-budget-slider", in: app).exists)
        for identifier in ["native-force-infantry", "native-force-armor", "native-force-air", "native-force-naval"] {
            XCTAssertTrue(firstElement(identifier, in: app).exists, "Missing force disclosure \(identifier)")
        }
    }

    func testSettingsCanTransferPlayerControlWithConfirmation() {
        let app = launchResetApp(fakeAI: true)
        startBrazilCampaign(in: app)
        tapButton(identifier: "native-map-command-advisor", in: app)
        tapIntelSection(identifier: "native-intel-section-settings", in: app)
        openCampaignManagement(in: app)

        let settings = firstElement("native-settings-panel", in: app)
        let switchPanel = firstElement("native-country-switch-panel", in: app)
        for _ in 0 ..< 10 where !switchPanel.isHittable {
            settings.swipeUp()
        }
        XCTAssertTrue(switchPanel.waitForExistence(timeout: 4))
        switchPanel.tap()

        let picker = firstElement("native-country-switch-picker", in: app)
        XCTAssertTrue(picker.waitForExistence(timeout: 4))
        picker.tap()

        let china = app.buttons["China · CHN"]
        XCTAssertTrue(china.waitForExistence(timeout: 4))
        china.tap()

        let confirm = app.alerts.buttons["Switch country"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 4))
        confirm.tap()

        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "China · CHN · ROUND")).firstMatch.waitForExistence(timeout: 8))
    }

    // MARK: - Helper Methods

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

    private func tapIntelSection(identifier: String, in app: XCUIApplication) {
        let button = firstElement(identifier, in: app)
        XCTAssertTrue(button.waitForExistence(timeout: 4), "Missing intelligence section \(identifier):\n\(app.debugDescription)")
        let selector = firstElement("native-intel-section-selector", in: app)
        for _ in 0 ..< 6 where !button.isHittable {
            selector.swipeLeft()
        }
        XCTAssertTrue(button.isHittable, "Unhittable intelligence section \(identifier):\n\(app.debugDescription)")
        button.tap()
    }

    private func dismissOnboardingIfPresent(in app: XCUIApplication) {
        let skipButton = app.buttons["native-onboarding-skip"]
        if skipButton.waitForExistence(timeout: 2) {
            skipButton.tap()
            XCTAssertFalse(skipButton.waitForExistence(timeout: 2))
        }
    }

    private func openCampaignManagement(in app: XCUIApplication) {
        let section = firstElement("native-campaign-management-section", in: app)
        XCTAssertTrue(section.waitForExistence(timeout: 4))
        for _ in 0 ..< 8 where !section.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(section.isHittable, "Campaign management should be reachable in settings")
        section.tap()
    }

    private func dismissKeyboardIfPresent(in app: XCUIApplication) {
        guard app.keyboards.firstMatch.exists else { return }
        let doneButton = app.buttons["native-keyboard-done"]
        if doneButton.waitForExistence(timeout: 2) {
            doneButton.tap()
        } else {
            app.swipeDown()
        }

        if app.keyboards.firstMatch.waitForExistence(timeout: 1) {
            for identifier in ["native-console-content", "native-intel-screen"] where app.keyboards.firstMatch.exists {
                let scrollView = firstElement(identifier, in: app)
                if scrollView.exists {
                    scrollView.swipeDown()
                }
            }
        }

        XCTAssertFalse(app.keyboards.firstMatch.waitForExistence(timeout: 2), "Keyboard should dismiss before continuing the flow")
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

    private func dismissTurnReport(in app: XCUIApplication) {
        let acknowledgeButton = app.buttons["ACKNOWLEDGE & CLOSE DOSSIER"]
        if acknowledgeButton.waitForExistence(timeout: 4) {
            acknowledgeButton.tap()
            return
        }

        let closeButton = app.buttons["Close report"]
        XCTAssertTrue(closeButton.waitForExistence(timeout: 4), "Missing report dismiss button:\n\(app.debugDescription)")
        closeButton.tap()
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

        let nvidiaProvider = app.buttons["native-provider-nvidia"]
        XCTAssertTrue(nvidiaProvider.waitForExistence(timeout: 8))
        nvidiaProvider.tap()

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
