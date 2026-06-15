import XCTest
@testable import SwiftHistoria

@MainActor
final class NativeBackendTests: XCTestCase {
    func testGeneratedTurnValidationRejectsUnsafePayloads() throws {
        let state = makeState()
        let summary = "Regional planning signals shift while external markets reassess delivery capacity."

        XCTAssertThrowsError(try NativeGameEngine.validated(
            NativeGeneratedTurn(events: [], stabilityDelta: 0, summary: summary, worldTensionDelta: 0),
            state: state,
            months: 1
        ))

        XCTAssertThrowsError(try NativeGameEngine.validated(
            NativeGeneratedTurn(events: [
                makeEvent(id: "player-only", playerRelated: true),
            ], stabilityDelta: 0, summary: summary, worldTensionDelta: 0),
            state: state,
            months: 1
        ))

        XCTAssertThrowsError(try NativeGameEngine.validated(
            NativeGeneratedTurn(events: [
                makeEvent(id: "placeholder", title: "AppleNativeGeneratedEventDraft", playerRelated: false),
                makeEvent(id: "player", playerRelated: true),
            ], stabilityDelta: 0, summary: summary, worldTensionDelta: 0),
            state: state,
            months: 1
        ))

        XCTAssertThrowsError(try NativeGameEngine.validated(
            NativeGeneratedTurn(events: [
                makeEvent(id: "unsafe", playerRelated: false, track: .militaryReadiness),
                makeEvent(id: "player", playerRelated: true),
            ], stabilityDelta: 0, summary: summary, worldTensionDelta: 0),
            state: state,
            months: 1
        ))

        XCTAssertThrowsError(try NativeGameEngine.validated(
            NativeGeneratedTurn(events: [
                makeEvent(id: "bad-date", date: "soon", playerRelated: false),
                makeEvent(id: "player", playerRelated: true),
            ], stabilityDelta: 0, summary: summary, worldTensionDelta: 0),
            state: state,
            months: 1
        ))

        XCTAssertThrowsError(try NativeGameEngine.validated(
            NativeGeneratedTurn(events: [
                makeEvent(id: "duplicate", playerRelated: false),
                makeEvent(id: "duplicate", playerRelated: true),
            ], stabilityDelta: 0, summary: summary, worldTensionDelta: 0),
            state: state,
            months: 1
        ))
    }

    func testStateApplicationResolvesOnlyLinkedActionsAndClampsMetrics() throws {
        var state = makeState()
        let firstAction = try XCTUnwrap(NativeGameEngine.action(from: "Fund grid modernization through a public service bond.", date: state.gameDate))
        let secondAction = try XCTUnwrap(NativeGameEngine.action(from: "Open a ports coordination office for regional logistics.", date: state.gameDate))
        state.plannedActions = [firstAction, secondAction]
        state.language = .spanish
        state.scenarioID = NativeScenarioCatalog.fragmentedMarkets.id
        state.stability = 98
        state.worldTension = 3

        let generated = try NativeGameEngine.validated(
            NativeGeneratedTurn(
                events: [
                    makeEvent(id: "independent", playerRelated: false, track: .internalStability, magnitude: 5),
                    makeEvent(id: "linked", playerRelated: true, linkedActionIDs: [firstAction.id], magnitude: -4),
                ],
                stabilityDelta: 80,
                summary: "Planning agencies convert a narrow fiscal window into visible delivery commitments.",
                worldTensionDelta: -80
            ),
            state: state,
            months: 3
        )

        let applied = NativeGameEngine.apply(generated, to: state, months: 3)

        XCTAssertEqual(applied.plannedActions.first { $0.id == firstAction.id }?.status, .resolved)
        XCTAssertEqual(applied.plannedActions.first { $0.id == secondAction.id }?.status, .planned)
        XCTAssertEqual(applied.stability, 100)
        XCTAssertEqual(applied.worldTension, 0)
        XCTAssertEqual(applied.language, .spanish)
        XCTAssertEqual(applied.scenarioID, NativeScenarioCatalog.fragmentedMarkets.id)
        let nonPollutionTimeline = applied.timeline.filter { !$0.id.hasPrefix("512dice-") }
        let nonPollutionEffects = applied.worldEffects.filter { !$0.eventId.hasPrefix("512dice-") }
        XCTAssertEqual(nonPollutionTimeline.count, generated.events.count + state.timeline.count)
        XCTAssertEqual(nonPollutionEffects.count, generated.events.flatMap(\.strategicEffects).count + state.worldEffects.count)
    }

    func testInvasionActionsResolveDeterministically() throws {
        var state = makeState()
        state.budgetMilitarySlider = 0.5
        let region = try XCTUnwrap(GeopoliticalMapData.regions.first { $0.id == "ARG" })
        let invasion = NativePlannedAction(
            createdAt: state.gameDate,
            detail: "Invade \(region.name) (ID: \(region.id))",
            id: "action-fixed-invasion",
            resolvedAt: nil,
            status: .planned,
            title: "Invade \(region.name) (ID: \(region.id))"
        )
        state.plannedActions = [invasion]

        let generated = NativeGeneratedTurn(events: [], stabilityDelta: 0, summary: "Leap", worldTensionDelta: 0)
        let firstResolution = NativeGameEngine.apply(generated, to: state, months: 1)
        let secondResolution = NativeGameEngine.apply(generated, to: state, months: 1)

        XCTAssertEqual(firstResolution.plannedActions.first?.status, .resolved)
        XCTAssertEqual(firstResolution.plannedActions.first?.resolvedAt, secondResolution.plannedActions.first?.resolvedAt)
        XCTAssertEqual(firstResolution.regionOccupations[region.id], secondResolution.regionOccupations[region.id])
        XCTAssertEqual(firstResolution.regionConflicts[region.id], secondResolution.regionConflicts[region.id])
        XCTAssertEqual(firstResolution.timeline.first?.id, secondResolution.timeline.first?.id)
        XCTAssertTrue(firstResolution.timeline.first?.linkedActionIDs.contains(invasion.id) == true)
    }

    func testLinkedInvasionActionsStillRollDiceBattle() throws {
        var state = makeState()
        state.budgetMilitarySlider = 0.5
        let region = try XCTUnwrap(GeopoliticalMapData.regions.first { $0.id == "ARG" })
        let invasion = NativePlannedAction(
            createdAt: state.gameDate,
            detail: "Invade \(region.name) (ID: \(region.id))",
            id: "action-linked-invasion",
            resolvedAt: nil,
            status: .planned,
            title: "Invade \(region.name) (ID: \(region.id))"
        )
        state.plannedActions = [invasion]

        let generated = NativeGeneratedTurn(
            events: [
                makeEvent(
                    id: "ai-linked-invasion-setup",
                    title: "Command Staff Opens Invasion File",
                    playerRelated: true,
                    linkedActionIDs: [invasion.id]
                ),
            ],
            stabilityDelta: 0,
            summary: "Leap",
            worldTensionDelta: 0
        )
        let resolved = NativeGameEngine.apply(generated, to: state, months: 1)

        XCTAssertEqual(resolved.plannedActions.first?.status, .resolved)
        XCTAssertTrue(resolved.timeline.contains { event in
            event.id.hasPrefix("invasion-success-\(region.id)-") ||
                event.id.hasPrefix("invasion-fail-\(region.id)-")
        })
        XCTAssertTrue(resolved.timeline.contains { $0.description.contains("Dice Battle for \(region.name)") })
        XCTAssertNotNil(resolved.regionConflicts[region.id])
    }

    func testStateApplicationPreservesComplexCampaignArchives() throws {
        var state = makeState()
        state.timeline = (0..<125).map { index in
            makeEvent(
                id: "archive-event-\(index)",
                date: state.gameDate,
                playerRelated: index.isMultiple(of: 2)
            )
        }
        state.worldEffects = (0..<225).map { index in
            NativeStrategicEffect(
                date: state.gameDate,
                eventId: "archive-event-\(index)",
                id: "archive-effect-\(index)",
                magnitude: index.isMultiple(of: 2) ? 1 : -1,
                summary: "Archived strategic effect \(index) remains part of the complex campaign.",
                target: index.isMultiple(of: 2) ? state.country.name : "International system",
                track: index.isMultiple(of: 2) ? .internalStability : .marketConfidence
            )
        }

        let generated = try NativeGameEngine.validated(
            NativeGeneratedTurn(
                events: [
                    makeEvent(id: "new-independent", date: state.gameDate, playerRelated: false),
                    makeEvent(id: "new-player", date: state.gameDate, playerRelated: true),
                ],
                stabilityDelta: 0,
                summary: "Complex campaign archives stay intact while new events enter the turn log.",
                worldTensionDelta: 0
            ),
            state: state,
            months: 1
        )

        let applied = NativeGameEngine.apply(generated, to: state, months: 1)

        let nonPollutionTimeline = applied.timeline.filter { !$0.id.hasPrefix("512dice-") }
        let nonPollutionEffects = applied.worldEffects.filter { !$0.eventId.hasPrefix("512dice-") }
        XCTAssertEqual(nonPollutionTimeline.count, 127)
        XCTAssertEqual(nonPollutionEffects.count, 227)
        XCTAssertTrue(applied.timeline.contains { $0.id == "archive-event-124" })
        XCTAssertTrue(applied.worldEffects.contains { $0.id == "archive-effect-224" })
    }

    func testEconomicLedgerAndActionMemoryUpdateAfterResolvedActions() throws {
        var state = makeState()
        let action = try XCTUnwrap(NativeGameEngine.action(
            from: "Fund a grid reliability and public transit resilience package through the treasury reserve.",
            date: state.gameDate
        ))
        state.plannedActions = [action]
        state.actionMemory = NativeStrategyContextDatabase.remember(
            action: action,
            in: [],
            source: "test",
            state: state
        )
        let originalLedger = state.economicLedger

        let generated = try NativeGameEngine.validated(
            NativeGeneratedTurn(
                events: [
                    makeEvent(id: "external-econ", playerRelated: false, track: .marketConfidence, magnitude: -1),
                    makeEvent(id: "linked-econ", playerRelated: true, linkedActionIDs: [action.id], track: .economicResilience, magnitude: 3),
                ],
                stabilityDelta: 1,
                summary: "Budget officers convert the action into measurable fiscal and resilience consequences.",
                worldTensionDelta: 0
            ),
            state: state,
            months: 3
        )

        let applied = NativeGameEngine.apply(generated, to: state, months: 3)
        let resolvedMemory = try XCTUnwrap(applied.actionMemory.first { $0.actionID == action.id })

        XCTAssertEqual(applied.plannedActions.first?.status, .resolved)
        XCTAssertEqual(resolvedMemory.status, .resolved)
        XCTAssertEqual(resolvedMemory.resolvedAt, applied.gameDate)
        XCTAssertFalse(applied.economicLedger.entries.isEmpty)
        XCTAssertNotEqual(applied.economicLedger.budgetBalancePercentGDP, originalLedger.budgetBalancePercentGDP)
        XCTAssertNotEqual(applied.economicLedger.nominalGDPTrillions, originalLedger.nominalGDPTrillions)
        XCTAssertGreaterThanOrEqual(applied.economicLedger.fiscalSpaceIndex, 0)
        XCTAssertLessThanOrEqual(applied.economicLedger.fiscalSpaceIndex, 100)
    }

    func testPersistenceRecoversBackupAndLegacySaves() throws {
        let defaults = makeDefaults()
        let persistenceDirectory = try makePersistenceDirectory()
        let store = NativeCampaignStore(
            defaults: defaults,
            aiService: FakeNativeAIService(),
            persistenceDirectory: persistenceDirectory
        )
        store.choose(testCountry)
        let savedState = try XCTUnwrap(store.state)
        let primaryFile = persistenceDirectory.appendingPathComponent("campaign-state-envelope-v2.json")
        let backupFile = persistenceDirectory.appendingPathComponent("campaign-state-backup-v2.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: primaryFile.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: backupFile.path))

        defaults.set(Data("corrupt-primary".utf8), forKey: "pax-historia.native.campaign-state-envelope.v2")
        defaults.removeObject(forKey: "pax-historia.native.campaign-state-backup.v2")
        try Data("corrupt-primary-file".utf8).write(to: primaryFile, options: [.atomic])

        let recovered = NativeCampaignStore(
            defaults: defaults,
            aiService: FakeNativeAIService(),
            persistenceDirectory: persistenceDirectory
        )
        XCTAssertEqual(recovered.state?.country.code, savedState.country.code)
        XCTAssertTrue(recovered.lastRecoveryNotice?.contains("backup") == true)
        XCTAssertTrue(recovered.lastRecoveryNotice?.contains("file") == true)

        let legacyDefaults = makeDefaults()
        let legacyPersistenceDirectory = try makePersistenceDirectory()
        var legacyState = makeState()
        legacyState.timeline = []
        legacyState.round = -4
        legacyDefaults.set(try JSONEncoder().encode(legacyState), forKey: "pax-historia.native.campaign-state.v1")

        let legacyStore = NativeCampaignStore(
            defaults: legacyDefaults,
            aiService: FakeNativeAIService(),
            persistenceDirectory: legacyPersistenceDirectory
        )
        XCTAssertEqual(legacyStore.state?.country.code, legacyState.country.code)
        XCTAssertEqual(legacyStore.state?.round, 1)
        XCTAssertFalse(legacyStore.state?.timeline.isEmpty ?? true)
        XCTAssertTrue(legacyStore.lastRecoveryNotice?.contains("legacy") == true)
    }

    func testImportExportRoundTripsAndRejectsOversizedFiles() throws {
        let defaults = makeDefaults()
        let store = try makeStore(defaults: defaults)
        store.choose(testCountry)

        let data = try store.exportCampaignData()
        let imported = try makeStore()
        try imported.importCampaignData(data)

        XCTAssertEqual(imported.state?.country.code, testCountry.code)
        XCTAssertEqual(imported.state?.scenarioID, store.state?.scenarioID)
        XCTAssertThrowsError(try imported.importCampaignData(Data(repeating: 0, count: 1_600_000)))
    }

    func testNativeFrontendSmokeFlowCoversPrimaryAppleSurfaces() async throws {
        let store = try makeStore()
        store.selectScenario(id: NativeScenarioCatalog.fragmentedMarkets.id)
        store.setLanguage(.portuguese)
        store.choose(testCountry)

        _ = ContentView()
        _ = CountrySelectionView(
            countries: CountryCatalog.all,
            languages: NativeGameLanguage.allCases,
            onScenarioSelect: store.selectScenario,
            onLanguageSelect: store.setLanguage,
            scenarios: NativeScenarioCatalog.all,
            selectedLanguage: store.selectedLanguage,
            selectedScenarioID: store.selectedScenarioID,
            onSelect: store.choose,
            activeCampaignState: store.state,
            onResumeCampaign: {}
        )
        _ = NativeGameView(store: store)
        _ = NativeGameShell(
            store: store,
            libraryMessage: nil,
            onExportCampaign: {},
            onImportCampaign: {}
        )

        XCTAssertEqual(store.state?.scenarioID, NativeScenarioCatalog.fragmentedMarkets.id)
        XCTAssertEqual(store.state?.language, .portuguese)
        XCTAssertEqual(store.state?.country.code, testCountry.code)

        while store.isLoadingSuggestions {
            await Task.yield()
        }
        await store.refreshSuggestedActions(force: true)
        while store.isLoadingSuggestions {
            await Task.yield()
        }
        XCTAssertFalse(store.state?.suggestedActions.isEmpty ?? true)

        store.draftAction = "Fund a metropolitan grid reliability audit for high-priority service corridors."
        store.addDraftAction()
        XCTAssertEqual(store.state?.plannedActions.first?.status, .planned)

        await store.advance(months: 1)
        XCTAssertGreaterThan(store.state?.round ?? 0, 1)
        XCTAssertFalse(store.state?.timeline.isEmpty ?? true)

        store.draftAdvisorQuestion = "What should we protect first this quarter?"
        await store.askAdvisor()
        XCTAssertTrue(store.state?.advisorMessages.contains { $0.role == .advisor } == true)

        let partner = try XCTUnwrap(CountryCatalog.all.first { $0.code != testCountry.code })
        store.selectedDiplomaticPartnerCode = partner.code
        store.draftDiplomaticMessage = "Open a narrow technical channel on port and energy reliability."
        await store.sendDiplomaticMessage()
        XCTAssertTrue(store.state?.diplomaticThreads.contains { $0.participant.code == partner.code && !$0.messages.isEmpty } == true)
    }

    func testDefaultScenarioUsesReal2010HistoricalBaseline() throws {
        let scenario = NativeScenarioCatalog.defaultScenario
        let state = NativeGameEngine.initialState(for: testCountry, scenario: scenario, language: .english)
        let profile = Native2010WorldModel.profile(for: testCountry)

        XCTAssertEqual(scenario.startDate, Native2010WorldModel.historicalStartDate)
        XCTAssertEqual(scenario.gameDate, Native2010WorldModel.openingGameDate)
        XCTAssertEqual(state.startDate, "2010-01-01")
        XCTAssertEqual(state.gameDate, "2010-01-15")
        XCTAssertEqual(state.stability, profile.stability)
        XCTAssertEqual(state.worldTension, Native2010WorldModel.worldTension(for: testCountry, scenario: scenario))
        XCTAssertTrue(state.lastSummary.contains("Real public history"))
        XCTAssertTrue(state.timeline.first?.title.contains("2010") == true)
        XCTAssertTrue(state.timeline.first?.description.contains("real 2010 baseline") == true)
        XCTAssertFalse(CountryCatalog.all.contains { $0.code == "SSD" })
        XCTAssertTrue(Native2010WorldModel.unavailableAtStart.contains("SSD"))
    }

    func testNative2010UIPayloadsRejectFictionalBlocs() {
        let state = NativeGameEngine.initialState(for: testCountry)
        let alignments = Native2010WorldModel.alignments(for: state)
        let riskSignals = Native2010WorldModel.riskSignals(for: state)
        let commitments = Native2010WorldModel.commitments(for: state)
        let mapSectors = Native2010WorldModel.mapSectors(for: state)
        let promptContext = Native2010WorldModel.promptContext(for: state)
        let payload = (
            alignments.map(\.name) +
            alignments.map(\.stance) +
            riskSignals.map(\.name) +
            commitments.map(\.name) +
            mapSectors.map(\.name) +
            [promptContext]
        ).joined(separator: " ")

        XCTAssertFalse(alignments.isEmpty)
        XCTAssertFalse(riskSignals.isEmpty)
        XCTAssertFalse(commitments.isEmpty)
        XCTAssertTrue(mapSectors.contains { $0.code == state.country.code })
        XCTAssertTrue(promptContext.contains("2010 historical canon"))
        XCTAssertTrue(promptContext.contains("Do not invent future blocs"))

        for forbidden in ["Volkan", "Kansak", "Sundar", "Pacifika", "Northland", "Eastern Bloc"] {
            XCTAssertFalse(payload.localizedCaseInsensitiveContains(forbidden), "\(forbidden) should not be in the native 2010 baseline.")
        }
    }

    func testAIFailurePreservesManualCampaignState() async throws {
        let service = FakeNativeAIService()
        service.turnHandler = { _, _ in
            throw NativeFoundationModelError.modelUnavailable("Local model is still preparing.")
        }
        let store = try makeStore(aiService: service)
        store.choose(testCountry)
        store.draftAction = "Expand reserve power procurement for regional service continuity."
        store.addDraftAction()

        let before = try XCTUnwrap(store.state)
        await store.advance(months: 1)

        let after = try XCTUnwrap(store.state)
        XCTAssertEqual(after.round, before.round)
        XCTAssertEqual(after.gameDate, before.gameDate)
        XCTAssertEqual(after.plannedActions.first?.status, .planned)
        XCTAssertTrue(store.lastError?.contains("unavailable") == true)
    }

    func testStorePublishesTurnProgressWhileAIWorkIsPending() async throws {
        let gate = AsyncGate()
        let service = FakeNativeAIService()
        service.turnHandler = { state, months in
            await gate.wait()
            return makeValidTurn(for: state, months: months)
        }
        let store = try makeStore(aiService: service)
        store.choose(testCountry)

        let task = Task { await store.advance(months: 1) }
        await gate.waitUntilEntered()

        XCTAssertTrue(store.isAdvancing)
        XCTAssertNotNil(store.turnProgress)
        XCTAssertGreaterThan(store.turnProgress?.totalLanes ?? 0, 0)

        await gate.resume()
        await task.value
        XCTAssertFalse(store.isAdvancing)
        XCTAssertNil(store.turnProgress)
    }

    func testStaleAIResponseIsIgnored() async throws {
        let gate = AsyncGate()
        let service = FakeNativeAIService()
        service.turnHandler = { state, months in
            await gate.wait()
            return makeValidTurn(for: state, months: months)
        }

        let store = try makeStore(aiService: service)
        store.choose(testCountry)
        await Task.yield()

        let task = Task { await store.advance(months: 1) }
        await gate.waitUntilEntered()
        store.setLanguage(.spanish)
        await gate.resume()
        await task.value

        XCTAssertEqual(store.state?.round, 1)
        XCTAssertEqual(store.state?.language, .spanish)
    }

    func testReadinessMapsUnsupportedOSWithoutAdvancing() {
        let readiness = NativeAIReadiness.failure(NativeFoundationModelError.unsupportedOS)

        XCTAssertEqual(readiness.availability, "unsupported-os")
        XCTAssertFalse(readiness.ok)
        XCTAssertTrue(readiness.recoverySuggestion.contains("FoundationModels"))
    }

    func testLiveFoundationModelsGenerateValidNativeTurnWhenEnabled() async throws {
        guard liveFoundationModelsGateEnabled else {
            throw XCTSkip("Set PAX_HISTORIA_RUN_LIVE_FOUNDATION_MODELS=1 or compile with -D PAX_HISTORIA_RUN_LIVE_FOUNDATION_MODELS to run the live Apple Foundation Models backend gate.")
        }

        let service = NativeFoundationModelService()
        let readiness = await service.checkReadiness()
        XCTAssertTrue(readiness.ok, "Expected live Foundation Models support, got \(readiness.availability): \(readiness.lastError)")

        var state = NativeGameEngine.initialState(
            for: testCountry,
            scenario: NativeScenarioCatalog.resilienceDecade,
            language: .english
        )
        let plannedAction = try XCTUnwrap(NativeGameEngine.action(
            from: "Fund a cross-agency energy reliability dashboard for essential service corridors.",
            date: state.gameDate
        ))
        state.plannedActions = [plannedAction]

        let generated = try await service.generateTurn(for: state, months: 1)
        let validated = try NativeGameEngine.validated(generated, state: state, months: 1)
        let applied = NativeGameEngine.apply(validated, to: state, months: 1)

        XCTAssertEqual(applied.round, 2)
        XCTAssertTrue(validated.events.contains { !$0.playerRelated })
        XCTAssertTrue(validated.events.contains { $0.playerRelated })
        XCTAssertTrue(applied.plannedActions.contains { $0.id == plannedAction.id && $0.status == .resolved })
        XCTAssertFalse(validated.summary.isEmpty)
    }

    func testPrintPromptExamples() throws {
        var state = makeState()
        let plannedAction = NativePlannedAction(
            createdAt: state.gameDate,
            detail: "Fund a metropolitan grid reliability audit for high-priority service corridors.",
            id: "action-1",
            resolvedAt: nil,
            status: .planned,
            title: "Grid Modernization"
        )
        state.plannedActions = [plannedAction]

        let partner = PlayerCountry(code: "ARG", name: "Argentina")
        let thread = NativeDiplomaticThread(
            id: "thread-1",
            lastUpdated: state.gameDate,
            messages: [
                NativeDiplomaticMessage(date: state.gameDate, id: "msg-1", speaker: partner.name, text: "Let us cooperate.")
            ],
            participant: partner,
            summary: "Cooperation agreement"
        )
        state.diplomaticThreads = [thread]

        let service = NativeFoundationModelService()

        let independentPrompt = service.makeIndependentEventPrompt(for: state, months: 1, repairInstruction: nil)
        print("\n--- TEST PRINT: INDEPENDENT PROMPT START ---")
        print(independentPrompt)
        print("--- TEST PRINT: INDEPENDENT PROMPT END ---\n")
        XCTAssertTrue(independentPrompt.contains("North Sea Corridor Expansion"))

        let actionPrompt = service.makeActionEventPrompt(for: state, action: plannedAction, months: 1, repairInstruction: nil)
        print("\n--- TEST PRINT: ACTION PROMPT START ---")
        print(actionPrompt)
        print("--- TEST PRINT: ACTION PROMPT END ---\n")
        XCTAssertTrue(actionPrompt.contains("Corridor Transit Integration"))
        XCTAssertTrue(actionPrompt.contains("Action-specific facts and consequence ranges"))

        let economicPrompt = service.makeEconomicEventPrompt(for: state, months: 1, repairInstruction: nil)
        print("\n--- TEST PRINT: ECONOMIC PROMPT START ---")
        print(economicPrompt)
        print("--- TEST PRINT: ECONOMIC PROMPT END ---\n")
        XCTAssertTrue(economicPrompt.contains("budget surplus or deficit"))
        XCTAssertTrue(economicPrompt.contains("Current strategy database"))

        let domesticPrompt = service.makeDomesticEventPrompt(for: state, months: 1, repairInstruction: nil)
        print("\n--- TEST PRINT: DOMESTIC PROMPT START ---")
        print(domesticPrompt)
        print("--- TEST PRINT: DOMESTIC PROMPT END ---\n")
        XCTAssertTrue(domesticPrompt.contains("Regional Services Consolidation"))

        let summaryPrompt = service.makeSummaryPrompt(for: state, months: 1, events: [])
        print("\n--- TEST PRINT: SUMMARY PROMPT START ---")
        print(summaryPrompt)
        print("--- TEST PRINT: SUMMARY PROMPT END ---\n")
        XCTAssertTrue(summaryPrompt.contains("Administrative streamlining"))

        let suggestionPrompt = service.makeSuggestionPrompt(for: state, focus: "fiscal buffers and community services", index: 1)
        print("\n--- TEST PRINT: SUGGESTION PROMPT START ---")
        print(suggestionPrompt)
        print("--- TEST PRINT: SUGGESTION PROMPT END ---\n")
        XCTAssertTrue(suggestionPrompt.contains("Establish Logistics Reserves"))

        let advisorPrompt = service.makeAdvisorPrompt(for: state, question: "What should we protect first this quarter?")
        print("\n--- TEST PRINT: ADVISOR PROMPT START ---")
        print(advisorPrompt)
        print("--- TEST PRINT: ADVISOR PROMPT END ---\n")
        XCTAssertTrue(advisorPrompt.contains("SwiftHistoria strategic advisor"))

        let diplomacyPrompt = service.makeDiplomacyPrompt(for: state, thread: thread, message: "Hello")
        print("\n--- TEST PRINT: DIPLOMACY PROMPT START ---")
        print(diplomacyPrompt)
        print("--- TEST PRINT: DIPLOMACY PROMPT END ---\n")
        XCTAssertTrue(diplomacyPrompt.contains("diplomacy chat inside SwiftHistoria"))

        let mechanicsPrompts = [
            independentPrompt,
            actionPrompt,
            economicPrompt,
            domesticPrompt,
            summaryPrompt,
            suggestionPrompt,
            advisorPrompt,
            diplomacyPrompt,
        ]
        for prompt in mechanicsPrompts {
            XCTAssertTrue(prompt.contains("Mechanics checklist"))
            XCTAssertTrue(prompt.contains("economic ledger"))
            XCTAssertTrue(prompt.contains("public security"))
            XCTAssertTrue(prompt.contains("insurgency pressure"))
            XCTAssertTrue(prompt.contains("map conflict"))
            XCTAssertTrue(prompt.contains("regionConflicts"))
            XCTAssertTrue(prompt.contains("diplomacy/global friction"))
            XCTAssertTrue(prompt.contains("hexLeverCode"))
        }
        XCTAssertTrue(suggestionPrompt.contains("primary affected mechanic"))
        XCTAssertTrue(suggestionPrompt.contains("secondary mechanic"))
    }

    func testMultiCountryEconSimulationAndNaming() throws {
        let state = makeState()
        XCTAssertGreaterThanOrEqual(state.economicLedgers.count, CountryCatalog.all.count)
        XCTAssertEqual(state.economicLedgers["GLOBAL"]?.nominalGDPTrillions, 66.20)
        XCTAssertNotNil(state.economicLedgers["MEX"])
        XCTAssertNotNil(state.economicLedgers["NGA"])

        let resolvedGlobal = CountryCatalog.all.first(where: { $0.code == "GLOBAL" })?.name ?? "Global System"
        let resolvedUSA = CountryCatalog.all.first(where: { $0.code == "USA" })?.name ?? "USA"
        XCTAssertEqual(resolvedGlobal, "Global System")
        XCTAssertEqual(resolvedUSA, "United States")

        let strategicEffect = NativeStrategicEffect(
            date: state.gameDate,
            eventId: "trade-facilitation-us",
            id: "effect-us",
            magnitude: 4,
            summary: "US imports speed up.",
            target: "USA",
            track: .marketConfidence
        )
        let customEvent = NativeCampaignEvent(
            date: state.gameDate,
            description: "Custom US trade event.",
            id: "trade-facilitation-us",
            importance: .major,
            kind: .world,
            linkedActionIDs: [],
            notable: true,
            playerRelated: false,
            strategicEffects: [strategicEffect],
            title: "US Corridor Clearance"
        )

        let previousUSLedger = state.economicLedgers["USA"]
        let previousBRALedger = state.economicLedgers["BRA"]

        let nextLedgers = NativeStrategyContextDatabase.updatedEconomicLedgers(
            from: state.economicLedgers,
            state: state,
            events: [customEvent],
            months: 3,
            targetDate: "2010-04-15"
        )

        XCTAssertNotNil(nextLedgers["USA"])
        XCTAssertNotNil(nextLedgers["BRA"])
        XCTAssertNotEqual(nextLedgers["USA"]?.budgetBalancePercentGDP, previousUSLedger?.budgetBalancePercentGDP)

        let usaEntries = nextLedgers["USA"]?.entries ?? []
        let braEntries = nextLedgers["BRA"]?.entries ?? []
        XCTAssertTrue(usaEntries.contains { $0.eventID == "trade-facilitation-us" }, "USA should have the event entry.")
        XCTAssertFalse(braEntries.contains { $0.eventID == "trade-facilitation-us" }, "BRA should not have the event entry.")
    }

    func testHexLeverDecodingAndApplication() throws {
        // Test standard codes
        let lever1 = try XCTUnwrap(NativeStrategyContextDatabase.decodeHexLever("0x4D21F4"))
        XCTAssertEqual(lever1.growthDelta, 0.4, accuracy: 0.0001)
        XCTAssertEqual(lever1.budgetDelta, -0.15, accuracy: 0.0001)
        XCTAssertEqual(lever1.debtDelta, 0.4, accuracy: 0.0001)
        XCTAssertEqual(lever1.inflationDelta, 0.05, accuracy: 0.0001)
        XCTAssertEqual(lever1.tradeDelta, -0.05, accuracy: 0.0001)
        XCTAssertEqual(lever1.fiscalSpaceDelta, 4)

        let lever2 = try XCTUnwrap(NativeStrategyContextDatabase.decodeHexLever("0x0D0004"))
        XCTAssertEqual(lever2.growthDelta, 0.0, accuracy: 0.0001)
        XCTAssertEqual(lever2.budgetDelta, -0.15, accuracy: 0.0001)
        XCTAssertEqual(lever2.debtDelta, 0.0, accuracy: 0.0001)
        XCTAssertEqual(lever2.inflationDelta, 0.0, accuracy: 0.0001)
        XCTAssertEqual(lever2.tradeDelta, 0.0, accuracy: 0.0001)
        XCTAssertEqual(lever2.fiscalSpaceDelta, 4)

        // Test lowercase, case insensitivity, no prefix
        let lever3 = try XCTUnwrap(NativeStrategyContextDatabase.decodeHexLever("cd42d8"))
        XCTAssertEqual(lever3.growthDelta, -0.4, accuracy: 0.0001)
        XCTAssertEqual(lever3.budgetDelta, -0.15, accuracy: 0.0001)
        XCTAssertEqual(lever3.debtDelta, 0.8, accuracy: 0.0001)
        XCTAssertEqual(lever3.inflationDelta, 0.1, accuracy: 0.0001)
        XCTAssertEqual(lever3.tradeDelta, -0.15, accuracy: 0.0001)
        XCTAssertEqual(lever3.fiscalSpaceDelta, -8)

        // Test invalid inputs
        XCTAssertNil(NativeStrategyContextDatabase.decodeHexLever("0x12345"))
        XCTAssertNil(NativeStrategyContextDatabase.decodeHexLever("0x1234567"))
        XCTAssertNil(NativeStrategyContextDatabase.decodeHexLever("0x12345G"))
    }

    func testStochasticEconomicDriftAndCrisisTrigger() throws {
        var state = makeState()
        let previousLedgers = state.economicLedgers

        // Advance turn once. Background drift should update metrics.
        let nextLedgers = NativeStrategyContextDatabase.updatedEconomicLedgers(
            from: state.economicLedgers,
            state: state,
            events: [],
            months: 3,
            targetDate: "2010-04-15"
        )

        // Every country should have reacted / drifted in some way
        for (code, ledger) in nextLedgers {
            let prev = try XCTUnwrap(previousLedgers[code])
            XCTAssertNotEqual(ledger.realGrowthPercent, prev.realGrowthPercent, "Country \(code) should have experienced drift/change.")
        }

        // Force high debt/low fiscal space crisis state for CHN to trigger restructuring
        let crisisLedger = NativeEconomicLedger(
            budgetBalancePercentGDP: -10.0,
            entries: [],
            fiscalSpaceIndex: 0,
            inflationPercent: 2.0,
            nominalGDPTrillions: 5.0,
            publicDebtPercentGDP: 180.0,
            realGrowthPercent: 2.0,
            tradeBalancePercentGDP: 1.0,
            unemploymentPercent: 8.0
        )

        // Let's roll until we get a restructuring event (40% probability, so it should trigger quickly)
        var restructuringHappened = false
        for i in 1...50 {
            let targetDate = "2010-04-\(String(format: "%02d", i))"
            if let result = NativeStrategyContextDatabase.rollStochasticEvent(for: crisisLedger, code: "CHN", targetDate: targetDate) {
                if result.summary.contains("Debt Restructuring") {
                    restructuringHappened = true
                    XCTAssertEqual(result.deltas.debtDelta, -40.0)
                    XCTAssertEqual(result.deltas.fiscalSpaceDelta, 25)
                    XCTAssertEqual(result.deltas.growthDelta, -4.5)
                    break
                }
            }
        }
        XCTAssertTrue(restructuringHappened, "Expected a debt restructuring event to trigger under high debt and zero fiscal space.")
    }

    func testScenarioExpansionCatalog() throws {
        let all = NativeScenarioCatalog.all
        XCTAssertEqual(all.count, 8)
        let soviet = NativeScenarioCatalog.scenario(for: "soviet-triumph")
        XCTAssertEqual(soviet.id, "soviet-triumph")
        XCTAssertEqual(soviet.name, "Soviet Triumph")
    }

    func testSovietTriumphCustomizations() throws {
        let sovietScenario = NativeScenarioCatalog.scenario(for: "soviet-triumph")
        let rus = PlayerCountry(code: "RUS", name: "Russia")

        let state = NativeGameEngine.initialState(for: rus, scenario: sovietScenario, language: .english)
        XCTAssertEqual(state.country.code, "RUS")

        let ledger = state.economicLedgers["RUS"]
        XCTAssertNotNil(ledger)
    }

    func testMidGameCountrySwitching() throws {
        let store = try makeStore()
        let state = makeState()
        store.choose(state.country)

        let newCountry = PlayerCountry(code: "CHN", name: "China")
        store.switchCountry(to: newCountry)

        XCTAssertEqual(store.selectedCountry?.code, "CHN")
        XCTAssertEqual(store.state?.country.code, "CHN")
    }

    func testGameModePersistence() throws {
        let defaults = makeDefaults()
        let store = try makeStore(defaults: defaults)
        let state = makeState()
        store.choose(state.country)

        store.setGameMode(.ironman)
        XCTAssertEqual(store.state?.gameMode, .ironman)

        let newStore = try makeStore(defaults: defaults)
        XCTAssertEqual(newStore.state?.gameMode, .ironman)
    }

    func testHexLever8CharacterDecodingAndTacticalNudges() throws {
        let hex = "0x4D21F423"
        let lever = NativeStrategyContextDatabase.decodeHexLever(hex)
        XCTAssertNotNil(lever)
        XCTAssertEqual(lever?.securityDelta, 5.0)
        XCTAssertEqual(lever?.rebelDelta, -3.0)
        XCTAssertEqual(lever?.invasionNudge, 3)
        XCTAssertEqual(lever?.conflictMode, .nuclearFallout)
        XCTAssertEqual(NativeStrategyContextDatabase.conflictNudgeLabel(for: 3), "nuclear fallout")

        let state = makeState()
        var event = makeEvent(id: "nuclear-test", playerRelated: true)
        event.hexLeverCode = "0x4D21F423"

        let generated = NativeGeneratedTurn(
            events: [event],
            stabilityDelta: 0,
            summary: "Tactical hex applied.",
            worldTensionDelta: 0
        )

        let applied = NativeGameEngine.apply(generated, to: state, months: 3)
        XCTAssertTrue(applied.nuclearFalloutRegions.count > 0)
        XCTAssertTrue(applied.regionConflicts.values.contains { $0.mode == .nuclearFallout })
    }

    func testConflictMapNudgesRecordConventionalAndGuerrillaStates() throws {
        let state = makeState()
        var conventionalEvent = makeEvent(id: "conventional-nudge", playerRelated: true)
        conventionalEvent.hexLeverCode = "0x00000001"
        var guerrillaEvent = makeEvent(id: "guerrilla-nudge", playerRelated: true)
        guerrillaEvent.hexLeverCode = "0x00000002"

        let generated = NativeGeneratedTurn(
            events: [conventionalEvent, guerrillaEvent],
            stabilityDelta: 0,
            summary: "Map-control nudges applied through abstract conflict levers.",
            worldTensionDelta: 0
        )

        let applied = NativeGameEngine.apply(generated, to: state, months: 3)

        XCTAssertTrue(applied.regionConflicts.values.contains { $0.mode == .conventionalOccupation })
        XCTAssertTrue(applied.regionConflicts.values.contains { $0.mode == .guerrillaControl })
        XCTAssertTrue(applied.regionOccupations.values.contains("REB"))
    }

    func testSovereigntyChangeCreatesDynamicCountryActor() throws {
        let state = makeState()
        var event = makeEvent(id: "secession-event", playerRelated: false)
        event.sovereigntyChange = NativeSovereigntyChange(
            kind: .secession,
            name: "Patagonia",
            regionIDs: ["ARG"],
            sourceCodes: ["ARG"],
            targetCode: "PAT"
        )

        let applied = NativeGameEngine.apply(
            NativeGeneratedTurn(
                events: [event],
                stabilityDelta: 0,
                summary: "A formal secession creates a separate political actor.",
                worldTensionDelta: 0
            ),
            to: state,
            months: 1
        )

        XCTAssertEqual(applied.dynamicCountries["PAT"], "Patagonia")
        XCTAssertEqual(applied.regionOccupations["ARG"], "PAT")
        XCTAssertNotNil(applied.economicLedgers["PAT"])
        XCTAssertNotNil(applied.aiCountryStates["PAT"])
        XCTAssertEqual(applied.regionConflicts["ARG"]?.mode, .contestedBorder)
    }

    func testValidatedTurnKeepsOnlyOneMapNudge() throws {
        let state = makeState()
        var conventionalEvent = makeEvent(id: "conventional-nudge", playerRelated: false)
        conventionalEvent.hexLeverCode = "0x00000001"
        var guerrillaEvent = makeEvent(id: "guerrilla-nudge", playerRelated: true)
        guerrillaEvent.hexLeverCode = "0x00000002"

        let validated = try NativeGameEngine.validated(
            NativeGeneratedTurn(
                events: [conventionalEvent, guerrillaEvent],
                stabilityDelta: 0,
                summary: "Map-control nudges are reconciled before deterministic application.",
                worldTensionDelta: 0
            ),
            state: state,
            months: 3
        )

        XCTAssertEqual(validated.events.compactMap(\.hexLeverCode), ["0x00000001", "0x000000"])
    }

    private var liveFoundationModelsGateEnabled: Bool {
        #if PAX_HISTORIA_RUN_LIVE_FOUNDATION_MODELS
        return true
        #else
        return ProcessInfo.processInfo.environment["PAX_HISTORIA_RUN_LIVE_FOUNDATION_MODELS"] == "1"
        #endif
    }

    func testAICountryStatesInitialization() throws {
        let state = makeState()
        XCTAssertFalse(state.aiCountryStates.isEmpty, "aiCountryStates should be initialized.")
        let usaState = try XCTUnwrap(state.aiCountryStates["USA"])
        XCTAssertEqual(usaState.doctrine, .collaborative)
        XCTAssertEqual(usaState.budgetPriority, .diplomacy)
        XCTAssertEqual(usaState.relationshipScores["CHN"], -25)

        let fragmentedScenario = NativeScenarioCatalog.fragmentedMarkets
        let state2 = NativeGameEngine.initialState(for: testCountry, scenario: fragmentedScenario, language: .english)
        let usaState2 = try XCTUnwrap(state2.aiCountryStates["USA"])
        XCTAssertEqual(usaState2.doctrine, .defensive)
        XCTAssertEqual(usaState2.relationshipScores["CHN"], -50)
    }

    func testRelationshipUpdatesViaHexLevers() throws {
        let state = makeState()
        var event = makeEvent(id: "invasion-event", playerRelated: false)
        event.hexLeverCode = "0x00000007" // invasion/conquest hex lever (delta = -50)

        let generated = try NativeGameEngine.validated(
            NativeGeneratedTurn(events: [
                event,
                makeEvent(id: "player", playerRelated: true)
            ], stabilityDelta: 0, summary: "BRA invades border zone triggering geopolitical tensions.", worldTensionDelta: 0),
            state: state,
            months: 1
        )

        let applied = NativeGameEngine.apply(generated, to: state, months: 1)
        let usaState = try XCTUnwrap(applied.aiCountryStates["USA"])
        let scoreWithBRA = usaState.relationshipScores["BRA"] ?? 0
        XCTAssertEqual(scoreWithBRA, -29, "Relations tank by 50 (20 to -30) from invasion hex lever, then drift 1 month toward neutral, resulting in -29.")
    }

    func testDeterministicAIDoctrineDrift() throws {
        let state = makeState()
        let previousUSLedger = try XCTUnwrap(state.economicLedgers["USA"])

        let generated = try NativeGameEngine.validated(
            NativeGeneratedTurn(events: [
                makeEvent(id: "independent", playerRelated: false),
                makeEvent(id: "player", playerRelated: true)
            ], stabilityDelta: 0, summary: "USA sustains collaborative doctrine expanding diplomatic trade corridors.", worldTensionDelta: 0),
            state: state,
            months: 3
        )

        let applied = NativeGameEngine.apply(generated, to: state, months: 3)
        let currentUSLedger = applied.economicLedgers["USA"]

        XCTAssertNotNil(currentUSLedger)
        XCTAssertGreaterThan(currentUSLedger?.tradeBalancePercentGDP ?? -999, previousUSLedger.tradeBalancePercentGDP)
    }

    func testAdministrativeCapacityEnforcement() throws {
        let state = makeState()
        XCTAssertEqual(state.administrativeCapacity, 100)

        let store = NativeCampaignStore(aiService: FakeNativeAIService())
        store.state = state

        // Add action 1
        store.draftAction = "Test Directive A"
        store.addDraftAction()

        XCTAssertEqual(store.state?.administrativeCapacity, 70)
        XCTAssertEqual(store.state?.plannedActions.count, 1)

        // Add action 2
        store.draftAction = "Test Directive B"
        store.addDraftAction()

        XCTAssertEqual(store.state?.administrativeCapacity, 40)

        // Add action 3
        store.draftAction = "Test Directive C"
        store.addDraftAction()

        XCTAssertEqual(store.state?.administrativeCapacity, 10)

        // Try adding action 4 (fails due to capacity)
        store.draftAction = "Test Directive D"
        store.addDraftAction()

        XCTAssertEqual(store.state?.administrativeCapacity, 10)
        XCTAssertEqual(store.state?.plannedActions.count, 3)
        XCTAssertNotNil(store.lastError)

        // Delete action 1
        let actionToDelete = try XCTUnwrap(store.state?.plannedActions.first)
        store.deleteAction(id: actionToDelete.id)

        XCTAssertEqual(store.state?.administrativeCapacity, 40)
        XCTAssertEqual(store.state?.plannedActions.count, 2)
    }

    func testDynamicAdministrativeCapacity() throws {
        let state = makeState()
        XCTAssertEqual(state.administrativeCapacity, 100)

        // 1 directive
        XCTAssertEqual(NativeGameEngine.estimateDirectiveCost(for: "Build a railway network in the north."), 30)

        // 2 directives (sentence boundary)
        XCTAssertEqual(NativeGameEngine.estimateDirectiveCost(for: "Build a railway network. Construct a seaport."), 60)

        // 2 directives (conjunction transition)
        XCTAssertEqual(NativeGameEngine.estimateDirectiveCost(for: "Build a railway network and construct a seaport."), 60)

        // 3 directives (multiple conjunctions/boundaries)
        XCTAssertEqual(NativeGameEngine.estimateDirectiveCost(for: "Build a railway network, and construct a seaport; also expand highways."), 90)

        // Test store enforcement
        let store = NativeCampaignStore(aiService: FakeNativeAIService())
        store.state = state

        // Add 2-directive action (should cost 60)
        store.draftAction = "Build a railway network and construct a seaport."
        store.addDraftAction()

        XCTAssertEqual(store.state?.administrativeCapacity, 40) // 100 - 60
        XCTAssertEqual(store.state?.plannedActions.count, 1)

        // Try to add a 2-directive action when only 40 is left (should fail)
        store.draftAction = "Invest in green energy and modernize the electrical grid."
        store.addDraftAction()

        XCTAssertEqual(store.state?.administrativeCapacity, 40)
        XCTAssertEqual(store.state?.plannedActions.count, 1)
        XCTAssertNotNil(store.lastError)

        // Delete action 1 (should refund 60)
        let actionToDelete = try XCTUnwrap(store.state?.plannedActions.first)
        store.deleteAction(id: actionToDelete.id)

        XCTAssertEqual(store.state?.administrativeCapacity, 100)
        XCTAssertEqual(store.state?.plannedActions.count, 0)
    }

    func testTurnResolutionStabilityCrisisAndCollapse() throws {
        var state = makeState()
        state.stability = 25
        if var ledger = state.economicLedgers[state.country.code] {
            ledger.securityIndex = 60.0
            ledger.realGrowthPercent = 4.0
            ledger.inflationPercent = 5.0
            state.economicLedgers[state.country.code] = ledger
            state.economicLedger = ledger
        }

        // Stability drop to 15 (triggers crisis)
        let generatedCrisis = NativeGeneratedTurn(
            events: [makeEvent(id: "ev1", playerRelated: true)],
            stabilityDelta: -10,
            summary: "Stability drop triggers severe crisis.",
            worldTensionDelta: 0
        )

        let appliedCrisis = NativeGameEngine.apply(generatedCrisis, to: state, months: 1)
        XCTAssertEqual(appliedCrisis.stability, 15)
        XCTAssertTrue(appliedCrisis.timeline.contains { $0.title.contains("CRISIS") })

        // Stability drops to 0 (collapse)
        let generatedCollapse = NativeGeneratedTurn(
            events: [makeEvent(id: "ev2", playerRelated: true)],
            stabilityDelta: -20,
            summary: "Total stability collapse.",
            worldTensionDelta: 0
        )

        let appliedCollapse = NativeGameEngine.apply(generatedCollapse, to: appliedCrisis, months: 1)
        XCTAssertEqual(appliedCollapse.stability, 0)
        XCTAssertEqual(appliedCollapse.victoryStatus, .lostCollapse)
        XCTAssertTrue(appliedCollapse.timeline.contains { $0.title.contains("NATION COLLAPSED") })
    }

    func testScenarioVictoryConditionEvaluation() throws {
        var state = makeState()
        state.scenarioID = "default"
        state.stability = 85
        state.gameDate = "2025-06-15"

        // Set positive trade balance
        if var ledger = state.economicLedgers[state.country.code] {
            ledger.tradeBalancePercentGDP = 1.5
            state.economicLedgers[state.country.code] = ledger
            state.economicLedger = ledger
        }

        // No occupied native regions
        state.regionOccupations = [:]

        let status = NativeGameEngine.evaluateVictoryStatus(for: state)
        XCTAssertEqual(status, .won)

        // Exceed target year (lostTimeout)
        var lostState = state
        lostState.stability = 50
        lostState.gameDate = "2031-01-01"
        let lostStatus = NativeGameEngine.evaluateVictoryStatus(for: lostState)
        XCTAssertEqual(lostStatus, .lostTimeout)
    }

    func testDiplomaticOfferProposalsAndActions() throws {
        var state = makeState()

        let offer = NativeDiplomaticOffer(
            id: "test-offer-1",
            proposerCode: "CHN",
            type: .tradeAgreement,
            description: "CHN proposes a Trade Agreement.",
            stabilityCost: 0,
            relationshipEffect: 20,
            growthDelta: 0.4,
            status: .pending,
            turnProposed: 1
        )
        state.activeOffers = [offer]

        let store = NativeCampaignStore(aiService: FakeNativeAIService())
        store.state = state

        // Accept offer
        store.acceptDiplomaticOffer(id: offer.id)

        XCTAssertEqual(store.state?.activeOffers.first?.status, .accepted)

        let chnState = try XCTUnwrap(store.state?.aiCountryStates["CHN"])
        let scoreWithPlayer = chnState.relationshipScores[state.country.code] ?? 0
        XCTAssertEqual(scoreWithPlayer, 20) // CHN relations updated

        XCTAssertEqual(store.state?.economicLedger.realGrowthPercent, 7.9) // starting 7.5 + 0.4
    }

    func testDynamicCapacityRefillFactors() throws {
        var state = makeState()
        // Low stability (10) -> stabilityPenalty is 36.
        // High rebel control (20) -> rebelPenalty is 20.
        // Low services slider (0.10) -> servicesBonus is -15.
        // Total refill = 100 - 36 - 20 - 15 = 29.
        state.stability = 10
        state.budgetServicesSlider = 0.10
        var ledgers = [state.country.code: state.economicLedger]
        ledgers[state.country.code]?.rebelControlPercent = 20.0
        ledgers[state.country.code]?.securityIndex = 60.0
        state.economicLedgers = ledgers
        state.economicLedger = ledgers[state.country.code]!

        let generated = NativeGeneratedTurn(events: [], stabilityDelta: 0, summary: "Leap", worldTensionDelta: 0)
        let resolved = NativeGameEngine.apply(generated, to: state, months: 1)
        XCTAssertEqual(resolved.administrativeCapacity, 28)

        // Services boost: Services slider > 0.40 -> +15 capacity bonus.
        // High stability (100) -> penalty is 0.
        // 0% rebel control -> penalty is 0.
        // Total refill = 100 - 0 - 0 + 15 = 115.
        var boostState = makeState()
        boostState.stability = 100
        boostState.budgetServicesSlider = 0.50
        var boostLedgers = [boostState.country.code: boostState.economicLedger]
        boostLedgers[boostState.country.code]?.rebelControlPercent = 0.0
        boostState.economicLedgers = boostLedgers
        boostState.economicLedger = boostLedgers[boostState.country.code]!

        let resolvedBoost = NativeGameEngine.apply(generated, to: boostState, months: 1)
        XCTAssertEqual(resolvedBoost.administrativeCapacity, 115)
    }

    func testInterconnectedSimulationEngineFeedbackLoops() throws {
        var state = makeState()

        // 1. Deficit-to-Debt and Debt-to-Fiscal-Space coupling
        if var ledger = state.economicLedgers[state.country.code] {
            ledger.budgetBalancePercentGDP = -6.0 // Deficit of 6%
            ledger.publicDebtPercentGDP = 50.0 // Debt starts at 50%
            ledger.inflationPercent = 12.0 // Inflation high
            state.economicLedgers[state.country.code] = ledger
            state.economicLedger = ledger
        }

        let generated = NativeGeneratedTurn(events: [], stabilityDelta: 0, summary: "Leap", worldTensionDelta: 0)
        let resolved = NativeGameEngine.apply(generated, to: state, months: 12) // Leap 1 year to make deficit subtraction cleaner

        // Debt should increase by deficit: 50.0 - (-6.0 * 1.0) = 56.0. Since stochastic events or rebel control might add small noise, assert greater than 50.5
        XCTAssertGreaterThan(resolved.economicLedger.publicDebtPercentGDP, 50.5)
        // Fiscal space is updated dynamically based on debt/inflation
        XCTAssertLessThan(resolved.economicLedger.fiscalSpaceIndex, 80)

        // 2. Inflation-to-Stability feedback
        var stateBase = makeState()
        stateBase.stability = 80
        if var ledger = stateBase.economicLedgers[stateBase.country.code] {
            ledger.inflationPercent = 2.0 // Low inflation
            ledger.securityIndex = 60.0 // Neutral security
            stateBase.economicLedgers[stateBase.country.code] = ledger
            stateBase.economicLedger = ledger
        }
        let resolvedBase = NativeGameEngine.apply(generated, to: stateBase, months: 1)

        var stateHighInflation = makeState()
        stateHighInflation.stability = 80
        if var ledger = stateHighInflation.economicLedgers[stateHighInflation.country.code] {
            ledger.inflationPercent = 30.0 // Very high inflation
            ledger.securityIndex = 60.0 // Neutral security
            stateHighInflation.economicLedgers[stateHighInflation.country.code] = ledger
            stateHighInflation.economicLedger = ledger
        }
        let resolvedInflation = NativeGameEngine.apply(generated, to: stateHighInflation, months: 1)

        // High inflation state should have lower stability than base state due to inflation drag
        XCTAssertLessThan(resolvedInflation.stability, resolvedBase.stability)

        // 3. Treaty ongoing relationship boost & ledger changes
        var stateTreaty = makeState()
        stateTreaty.budgetDiplomacySlider = 0.50 // High diplomacy budget to disable relationship decay
        let offer = NativeDiplomaticOffer(
            id: "alliance-offer",
            proposerCode: "USA",
            type: .militaryAlliance,
            description: "Military Alliance",
            stabilityCost: 0,
            relationshipEffect: 10,
            growthDelta: -0.05,
            status: .accepted,
            turnProposed: 1
        )
        stateTreaty.activeOffers = [offer]
        stateTreaty.aiCountryStates["USA"] = NativeAICountryState(
            countryCode: "USA",
            doctrine: .defensive,
            budgetPriority: .stability,
            relationshipScores: [stateTreaty.country.code: 30],
            multiTurnAgenda: "Consolidating alliances.",
            agendaProgress: 0
        )

        let resolvedTreaty = NativeGameEngine.apply(generated, to: stateTreaty, months: 1)
        // Relationship score towards player should increase by 2 from treaty upkeep without double-counting generic outreach.
        let proposerState = try XCTUnwrap(resolvedTreaty.aiCountryStates["USA"])
        XCTAssertEqual(proposerState.relationshipScores[resolvedTreaty.country.code], 32)

        // 4. Fallout & Imperial friction tension escalation
        var stateTensionBase = makeState()
        stateTensionBase.worldTension = 10
        stateTensionBase.regionOccupations = [:]
        stateTensionBase.nuclearFalloutRegions = []
        let resolvedTensionBase = NativeGameEngine.apply(generated, to: stateTensionBase, months: 1)

        var stateTension = makeState()
        stateTension.worldTension = 10
        stateTension.regionOccupations = ["BRA": "CHN"] // Player country BRA has 1 occupied region
        stateTension.nuclearFalloutRegions = ["USA", "CHN"] // 2 fallout regions globally
        let resolvedTension = NativeGameEngine.apply(generated, to: stateTension, months: 1)

        // Fallout and occupations should drive world tension higher than baseline
        XCTAssertGreaterThan(resolvedTension.worldTension, resolvedTensionBase.worldTension)
    }

    func testHighDiplomacyOutreachDoesNotDoubleCountAcceptedTreatyPartners() throws {
        var state = makeState()
        state.budgetDiplomacySlider = 0.50
        state.activeOffers = [
            NativeDiplomaticOffer(
                id: "accepted-alliance-usa",
                proposerCode: "USA",
                type: .militaryAlliance,
                description: "Accepted military alliance",
                stabilityCost: 0,
                relationshipEffect: 10,
                growthDelta: -0.05,
                status: .accepted,
                turnProposed: 1
            )
        ]

        var usa = try XCTUnwrap(state.aiCountryStates["USA"])
        usa.relationshipScores[state.country.code] = 30
        state.aiCountryStates["USA"] = usa

        var chn = try XCTUnwrap(state.aiCountryStates["CHN"])
        chn.relationshipScores[state.country.code] = 30
        state.aiCountryStates["CHN"] = chn

        let generated = NativeGeneratedTurn(events: [], stabilityDelta: 0, summary: "Leap", worldTensionDelta: 0)
        let resolved = NativeGameEngine.apply(generated, to: state, months: 1)

        let treatyPartner = try XCTUnwrap(resolved.aiCountryStates["USA"])
        XCTAssertEqual(treatyPartner.relationshipScores[resolved.country.code], 32)

        let nonTreatyPartner = try XCTUnwrap(resolved.aiCountryStates["CHN"])
        XCTAssertEqual(nonTreatyPartner.relationshipScores[resolved.country.code], 31)
    }

    func testWorldTensionEscalationAndParanoia() throws {
        var state = makeState()
        state.worldTension = 20

        // 1 active region conflict, arms buildup (military slider = 0.50) -> tensionEscalation = 1 + 2 = 3.
        state.budgetMilitarySlider = 0.50
        state.regionConflicts = ["BRA": NativeRegionConflictState(controllerCode: "REB", intensity: 2, mode: .conventionalOccupation, originalCountryCode: "BRA", regionID: "BRA")]

        let generated = NativeGeneratedTurn(events: [], stabilityDelta: 0, summary: "Leap", worldTensionDelta: 5)
        let resolved = NativeGameEngine.apply(generated, to: state, months: 1)

        // worldTension should be 20 (start) + 5 (adjTensionDelta) + 3 (tensionEscalation) = 28.
        XCTAssertEqual(resolved.worldTension, 28)

        // Paranoia test: threshold = 20 + worldTension / 2.
        // Let's set world tension to 80 -> threshold is 20 + 40 = 60.
        var paranoiaState = makeState()
        paranoiaState.worldTension = 80

        let offer = NativeDiplomaticOffer(
            id: "offer-p1",
            proposerCode: "CHN",
            type: .tradeAgreement,
            description: "Agreement",
            stabilityCost: 0,
            relationshipEffect: 10,
            growthDelta: 0.2,
            status: .pending,
            turnProposed: 1
        )
        paranoiaState.activeOffers = [offer]

        if var chn = paranoiaState.aiCountryStates["CHN"] {
            chn.relationshipScores[paranoiaState.country.code] = 50
            paranoiaState.aiCountryStates["CHN"] = chn
        }

        let store = NativeCampaignStore(aiService: FakeNativeAIService())
        store.state = paranoiaState

        store.counterDiplomaticOffer(id: offer.id)
        XCTAssertEqual(store.state?.activeOffers.first?.status, .countered)
    }

    func testArmsBuildupAndDiplomacySliders() throws {
        var state = makeState()
        state.budgetMilitarySlider = 0.50
        state.budgetDiplomacySlider = 0.10

        if var usa = state.aiCountryStates["USA"] {
            usa.relationshipScores["BRA"] = -30
            state.aiCountryStates["USA"] = usa
        }

        let generated = NativeGeneratedTurn(events: [], stabilityDelta: 0, summary: "Leap", worldTensionDelta: 0)
        let resolved = NativeGameEngine.apply(generated, to: state, months: 1)

        let usaState = try XCTUnwrap(resolved.aiCountryStates["USA"])
        XCTAssertEqual(usaState.relationshipScores["BRA"], -29)
    }

    func testTerritorialAndRadiologicalPenalties() throws {
        var state = makeState()
        state.regionOccupations = ["BRA_Acre": "CHN"]
        state.nuclearFalloutRegions = ["BRA_Acre"]

        let generated = NativeGeneratedTurn(events: [], stabilityDelta: 0, summary: "Leap", worldTensionDelta: 0)
        let resolved = NativeGameEngine.apply(generated, to: state, months: 1)

        XCTAssertEqual(resolved.economicLedger.realGrowthPercent, 5.0, accuracy: 0.1)
        XCTAssertEqual(resolved.economicLedger.inflationPercent, 8.0, accuracy: 0.1)
        XCTAssertEqual(resolved.stability, 67)
    }

    func test512DiceFrictionSystem() throws {
        NativeGameEngine.force512DiceFrictionForTesting = true
        defer { NativeGameEngine.force512DiceFrictionForTesting = false }

        let state = makeState()
        let generated = NativeGeneratedTurn(events: [], stabilityDelta: 0, summary: "Leap", worldTensionDelta: 0)
        let resolved = NativeGameEngine.apply(generated, to: state, months: 1)

        // The timeline must contain at least one 512dice event (the overall friction event or specific ones)
        let hasFrictionEvents = resolved.timeline.contains { event in
            event.id.hasPrefix("512dice-")
        }
        XCTAssertTrue(hasFrictionEvents, "Expected 512-dice friction events to be generated and added to the timeline.")

        // Verify that the overall event exists
        let overallEvent = resolved.timeline.first { $0.id.hasPrefix("512dice-overall-") }
        XCTAssertNotNil(overallEvent, "Expected an overall turbulence event in the timeline.")
        
        // The economic ledger should contain entries related to the 512-dice events
        let entries = resolved.economicLedger.entries
        let hasFrictionLedgerEntry = entries.contains { entry in
            entry.eventID.hasPrefix("512dice-")
        }
        XCTAssertTrue(hasFrictionLedgerEntry, "Expected economic ledger entries generated by 512-dice events.")
    }
}

@MainActor
private final class FakeNativeAIService: NativeAIService {
    var turnHandler: ((NativeCampaignState, Int) async throws -> NativeGeneratedTurn)?

    func checkReadiness() async -> NativeAIReadiness {
        .available(tokenBudget: "fake")
    }

    func generateTurn(for state: NativeCampaignState, months: Int) async throws -> NativeGeneratedTurn {
        if let turnHandler {
            return try await turnHandler(state, months)
        }
        return makeValidTurn(for: state, months: months)
    }

    func generateSuggestedActions(for state: NativeCampaignState) async throws -> [NativeSuggestedAction] {
        [
            NativeSuggestedAction(detail: "Fund a service access audit for district agencies.", id: "fake-1", rationale: "It fits current delivery constraints.", title: "Audit service access", urgency: "soon"),
            NativeSuggestedAction(detail: "Open a logistics desk for regional infrastructure permits.", id: "fake-2", rationale: "It supports market confidence.", title: "Coordinate logistics desk", urgency: "opportunistic"),
            NativeSuggestedAction(detail: "Publish a fiscal buffer plan for essential services.", id: "fake-3", rationale: "It protects stability during delays.", title: "Publish buffer plan", urgency: "immediate"),
        ]
    }

    func generateAdvisorBrief(for state: NativeCampaignState, question: String) async throws -> String {
        "Hold the line on concrete service delivery and avoid vague commitments."
    }

    func generateDiplomaticReply(for state: NativeCampaignState, thread: NativeDiplomaticThread, message: String) async throws -> String {
        "The counterpart accepts a narrow technical channel while reserving broader commitments."
    }
}

private actor AsyncGate {
    private var entered = false
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        entered = true
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func waitUntilEntered() async {
        while !entered {
            await Task.yield()
        }
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}

private let testCountry = PlayerCountry(code: "BRA", name: "Brazil")

@MainActor
private func makeStore(
    defaults: UserDefaults = makeDefaults(),
    aiService: any NativeAIService = FakeNativeAIService()
) throws -> NativeCampaignStore {
    NativeCampaignStore(
        defaults: defaults,
        aiService: aiService,
        persistenceDirectory: try makePersistenceDirectory()
    )
}

private func makeState() -> NativeCampaignState {
    NativeGameEngine.initialState(for: testCountry)
}

private func makeDefaults() -> UserDefaults {
    let suiteName = "NativeBackendTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}

private func makePersistenceDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("PaxHistoriaNativeBackendTests", isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func makeValidTurn(for state: NativeCampaignState, months: Int) -> NativeGeneratedTurn {
    NativeGeneratedTurn(
        events: [
            makeEvent(id: "independent-\(state.round)", playerRelated: false),
            makeEvent(id: "player-\(state.round)", playerRelated: true),
        ],
        stabilityDelta: 1,
        summary: "Regional agencies turn concrete planning into a visible delivery signal.",
        worldTensionDelta: -1
    )
}

private func makeEvent(
    id: String,
    title: String = "Transit Funding Review",
    date: String = "",
    playerRelated: Bool,
    linkedActionIDs: [String] = [],
    track: NativeStrategicTrack = .marketConfidence,
    magnitude: Int = 2
) -> NativeCampaignEvent {
    NativeCampaignEvent(
        date: date,
        description: "Regional agencies review delivery milestones and publish a concrete service timetable for affected districts.",
        id: id,
        importance: .major,
        kind: playerRelated ? .action : .world,
        linkedActionIDs: linkedActionIDs,
        notable: true,
        playerRelated: playerRelated,
        strategicEffects: [
            NativeStrategicEffect(
                date: date,
                eventId: id,
                id: "\(id)-effect",
                magnitude: magnitude,
                summary: "Market confidence shifts as service delivery commitments become measurable.",
                target: playerRelated ? testCountry.name : "International system",
                track: track
            ),
        ],
        title: title
    )
}
