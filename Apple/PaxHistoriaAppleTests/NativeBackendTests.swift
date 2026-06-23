@testable import SwiftHistoria
import XCTest

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
                makeEvent(id: "player-only", playerRelated: true)
            ], stabilityDelta: 0, summary: summary, worldTensionDelta: 0),
            state: state,
            months: 1
        ))

        XCTAssertThrowsError(try NativeGameEngine.validated(
            NativeGeneratedTurn(events: [
                makeEvent(id: "placeholder", title: "AppleNativeGeneratedEventDraft", playerRelated: false),
                makeEvent(id: "player", playerRelated: true)
            ], stabilityDelta: 0, summary: summary, worldTensionDelta: 0),
            state: state,
            months: 1
        ))

        // Military tracks are now valid — the game is a geopolitical simulator
        // and all strategic tracks are accepted by the engine.
        XCTAssertNoThrow(try NativeGameEngine.validated(
            NativeGeneratedTurn(events: [
                makeEvent(id: "military-track", playerRelated: false, track: .militaryReadiness),
                makeEvent(id: "player", playerRelated: true)
            ], stabilityDelta: 0, summary: summary, worldTensionDelta: 0),
            state: state,
            months: 1
        ))

        XCTAssertThrowsError(try NativeGameEngine.validated(
            NativeGeneratedTurn(events: [
                makeEvent(id: "bad-date", date: "soon", playerRelated: false),
                makeEvent(id: "player", playerRelated: true)
            ], stabilityDelta: 0, summary: summary, worldTensionDelta: 0),
            state: state,
            months: 1
        ))

        XCTAssertThrowsError(try NativeGameEngine.validated(
            NativeGeneratedTurn(events: [
                makeEvent(id: "duplicate", playerRelated: false),
                makeEvent(id: "duplicate", playerRelated: true)
            ], stabilityDelta: 0, summary: summary, worldTensionDelta: 0),
            state: state,
            months: 1
        ))
    }

    func testGeneratedTurnValidationRejectsDatesOutsideTurnWindow() throws {
        let state = makeState()
        let summary = "Regional planning signals shift while external markets reassess delivery capacity."
        let targetDate = NativeGameEngine.advance(date: state.gameDate, months: 1)

        var futureEvent = makeEvent(id: "future-world", date: "2099-01-15", playerRelated: false)
        futureEvent.strategicEffects[0].date = "2099-01-15"
        XCTAssertThrowsError(try NativeGameEngine.validated(
            NativeGeneratedTurn(events: [
                futureEvent,
                makeEvent(id: "player", date: targetDate, playerRelated: true)
            ], stabilityDelta: 0, summary: summary, worldTensionDelta: 0),
            state: state,
            months: 1
        ))

        var mismatchedEffect = makeEvent(id: "mismatched-effect", date: targetDate, playerRelated: false)
        mismatchedEffect.strategicEffects[0].date = state.gameDate
        XCTAssertThrowsError(try NativeGameEngine.validated(
            NativeGeneratedTurn(events: [
                mismatchedEffect,
                makeEvent(id: "player-2", date: targetDate, playerRelated: true)
            ], stabilityDelta: 0, summary: summary, worldTensionDelta: 0),
            state: state,
            months: 1
        ))
    }

    func testResolvedActionMemoryDoesNotRewriteOldResolvedActions() throws {
        var state = makeState()
        let action = NativePlannedAction(
            createdAt: state.gameDate,
            detail: "Fund a public transit delivery audit.",
            id: "already-resolved",
            resolvedAt: state.gameDate,
            status: .resolved,
            title: "Transit audit"
        )
        state.plannedActions = [action]
        state.actionMemory = [
            NativeActionMemory(
                actionID: action.id,
                createdAt: action.createdAt,
                detail: action.detail,
                economicSummary: "Original resolved summary remains stable.",
                id: "memory-\(action.id)",
                resolvedAt: action.resolvedAt,
                ruleIDs: ["public-services"],
                source: "manual",
                status: .resolved,
                title: action.title
            )
        ]

        let applied = NativeGameEngine.apply(
            NativeGeneratedTurn(
                events: [makeEvent(id: "unrelated-world", playerRelated: false)],
                stabilityDelta: 0,
                summary: "No new action resolution occurs this turn.",
                worldTensionDelta: 0
            ),
            to: state,
            months: 1
        )

        let memory = try XCTUnwrap(applied.actionMemory.first { $0.actionID == action.id })
        XCTAssertEqual(memory.economicSummary, "Original resolved summary remains stable.")
        XCTAssertEqual(memory.source, "manual")
    }

    func testStabilizationConflictDoesNotEscalateWorldTension() throws {
        var state = makeState()
        state.worldTension = 40
        state.budgetMilitarySlider = 0.33
        let region = try XCTUnwrap(GeopoliticalMapData.regions.first { $0.countryCode == state.country.code })
        state.regionConflicts[region.id] = NativeRegionConflictState(
            controllerCode: state.country.code,
            intensity: 1,
            mode: .stabilization,
            originalCountryCode: region.countryCode,
            regionID: region.id,
            summary: "Stabilization work is active but no longer contested.",
            updatedAt: state.gameDate
        )

        let applied = NativeGameEngine.apply(
            NativeGeneratedTurn(
                events: [],
                stabilityDelta: 0,
                summary: "Stabilization work continues without new international friction.",
                worldTensionDelta: 0
            ),
            to: state,
            months: 1
        )

        XCTAssertEqual(applied.worldTension, 40)
    }

    func testStrategicDatabaseBatchesAndFetchesRegionalMapState() throws {
        let database = try NativeDatabaseContext(inMemory: true)
        let armies = (0 ..< 5000).map { index in
            NativeArmySnapshot(
                countryCode: index.isMultiple(of: 2) ? "USA" : "BRA",
                currentRegionID: index.isMultiple(of: 3) ? "USA" : "BRA",
                id: "army-\(index)",
                strength: 10 + index % 70,
                type: index.isMultiple(of: 5) ? .armor : .infantry
            )
        }
        let buildings = [
            NativeBuildingSnapshot(ownerCountryCode: "USA", regionID: "USA", type: .fortress),
            NativeBuildingSnapshot(ownerCountryCode: "BRA", regionID: "BRA", type: .market)
        ]

        try database.replaceStrategicMapState(armies: armies, buildings: buildings)

        XCTAssertEqual(try database.allArmies().count, 5000)
        XCTAssertEqual(try database.allBuildings().count, 2)
        XCTAssertEqual(try database.armies(in: "USA").count, 1667)
        XCTAssertEqual(try database.buildings(in: "BRA").first?.type, .market)
    }

    func testBackgroundSimulationCreatesVisibleStrategicMapActions() {
        var state = makeState()
        state.aiCountryStates = [
            "ARG": NativeAICountryState(
                countryCode: "ARG",
                doctrine: .expansionist,
                budgetPriority: .military,
                relationshipScores: [state.country.code: -70],
                multiTurnAgenda: "Probe border readiness.",
                agendaProgress: 40
            )
        ]
        state.economicLedgers["ARG"] = NativeStrategyContextDatabase.startingEconomicLedger(
            forCode: "ARG",
            scenario: NativeScenarioCatalog.defaultScenario
        )

        let simulated = BackgroundSimulationService.shared.simulatedTurn(state)

        XCTAssertFalse(simulated.mapArmies.isEmpty)
        XCTAssertTrue(simulated.mapArmies.allSatisfy { !$0.currentRegionID.isEmpty })
        XCTAssertEqual(simulated.timeline, state.timeline)
        XCTAssertEqual(simulated.worldEffects, state.worldEffects)
        XCTAssertTrue(simulated.lastSummary.contains("Background simulation added"))
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
                    makeEvent(id: "linked", playerRelated: true, linkedActionIDs: [firstAction.id], magnitude: -4)
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
        XCTAssertTrue(applied.timeline.contains { $0.id == "independent" })
        XCTAssertTrue(applied.timeline.contains { $0.id == "linked" })
        XCTAssertTrue(applied.worldEffects.contains { $0.eventId == "independent" })
        XCTAssertTrue(applied.worldEffects.contains { $0.eventId == "linked" })
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
                )
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
        state.timeline = (0 ..< 125).map { index in
            makeEvent(
                id: "archive-event-\(index)",
                date: state.gameDate,
                playerRelated: index.isMultiple(of: 2)
            )
        }
        state.worldEffects = (0 ..< 225).map { index in
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
                    makeEvent(id: "new-player", date: state.gameDate, playerRelated: true)
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
                    makeEvent(id: "linked-econ", playerRelated: true, linkedActionIDs: [action.id], track: .economicResilience, magnitude: 3)
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
        try legacyDefaults.set(JSONEncoder().encode(legacyState), forKey: "pax-historia.native.campaign-state.v1")

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

        let validButOversized = data + Data(repeating: 0x20, count: NativeCampaignStore.maximumCampaignImportBytes - data.count + 1)
        XCTAssertThrowsError(try imported.importCampaignData(validButOversized)) { error in
            XCTAssertTrue(error.localizedDescription.contains("too large"))
        }
    }

    func testCampaignStateDecodeKeepsGoodItemsWhenLegacyArrayContainsBadItem() throws {
        let state = makeState()
        let encoded = try JSONEncoder().encode(state)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let timeline = try XCTUnwrap(object["timeline"] as? [[String: Any]])
        object["timeline"] = timeline + [["id": 42, "date": ["bad": "shape"]]]
        let corrupted = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(NativeCampaignState.self, from: corrupted)

        XCTAssertEqual(decoded.timeline.map(\.id), state.timeline.map(\.id))
    }

    func testMapDataAliasesSelectableCountryCodesToGeometryCodes() {
        XCTAssertEqual(GeopoliticalMapData.canonicalCountryCode("PSE"), "PSX")
        XCTAssertEqual(GeopoliticalMapData.canonicalCountryCode("XXK"), "KOS")
        XCTAssertFalse(GeopoliticalMapData.regions(forCountryCode: "PSE").isEmpty)
        XCTAssertFalse(GeopoliticalMapData.regions(forCountryCode: "XXK").isEmpty)
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

        await store.performAdvance(months: 1)
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

    func testDefaultScenarioUsesReal2010HistoricalBaseline() {
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
        await store.performAdvance(months: 1)

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

        let task = Task { await store.performAdvance(months: 1) }
        await gate.waitUntilEntered()

        XCTAssertTrue(store.isAdvancing)
        XCTAssertNotNil(store.turnProgress)
        XCTAssertGreaterThan(store.turnProgress?.totalLanes ?? 0, 0)

        await gate.resume()
        await task.value
        XCTAssertFalse(store.isAdvancing)
        XCTAssertNil(store.turnProgress)
    }

    func testSuggestedActionsTimeoutClearsLoadingState() async throws {
        let service = FakeNativeAIService()
        service.suggestionHandler = { _ in
            try await Task.sleep(nanoseconds: 5_000_000_000)
            return []
        }
        let originalTimeout = NativeCampaignStore.suggestionRefreshTimeoutNanoseconds
        NativeCampaignStore.suggestionRefreshTimeoutNanoseconds = 1_000_000
        defer { NativeCampaignStore.suggestionRefreshTimeoutNanoseconds = originalTimeout }

        let store = try makeStore(aiService: service)
        store.state = makeState()
        await store.refreshSuggestedActions(force: true)

        XCTAssertFalse(store.isLoadingSuggestions)
        XCTAssertTrue(store.state?.suggestedActions.isEmpty ?? false)
        XCTAssertTrue(store.lastSuggestionError?.contains("too long") == true)
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

        let task = Task { await store.performAdvance(months: 1) }
        await gate.waitUntilEntered()
        store.setLanguage(.spanish)
        await gate.resume()
        await task.value

        XCTAssertEqual(store.state?.round, 1)
        XCTAssertEqual(store.state?.language, .spanish)
    }

    func testManualBudgetAndOfferChangesInvalidatePendingAdvance() async throws {
        let gate = AsyncGate()
        let service = FakeNativeAIService()
        service.turnHandler = { state, months in
            await gate.wait()
            return makeValidTurn(for: state, months: months)
        }

        let store = try makeStore(aiService: service)
        store.choose(testCountry)
        var state = try XCTUnwrap(store.state)
        state.activeOffers = [
            NativeDiplomaticOffer(
                id: "offer-arg-trade",
                proposerCode: "ARG",
                type: .tradeAgreement,
                description: "A narrow ports and customs agreement.",
                stabilityCost: 1,
                relationshipEffect: 4,
                growthDelta: 0.2,
                status: .pending,
                turnProposed: state.round
            )
        ]
        store.state = state

        let task = Task { await store.performAdvance(months: 1) }
        await gate.waitUntilEntered()
        store.updateBudgetSliders(military: 10, services: 0, diplomacy: 0)
        store.acceptDiplomaticOffer(id: "offer-arg-trade")
        await gate.resume()
        await task.value

        XCTAssertEqual(store.state?.round, 1)
        XCTAssertEqual(try XCTUnwrap(store.state?.budgetMilitarySlider), 1.0, accuracy: 0.0001)
        XCTAssertEqual(store.state?.activeOffers.first?.status, .accepted)
        XCTAssertTrue(store.state?.timeline.contains { $0.id.hasPrefix("offer-accept-event-offer-arg-trade") } == true)
    }

    func testTerminalCampaignDoesNotAdvanceOrCallAI() async throws {
        let service = FakeNativeAIService()
        service.turnHandler = { _, _ in
            XCTFail("Terminal campaigns must not request a new AI turn.")
            return NativeGeneratedTurn(events: [], stabilityDelta: 0, summary: "Should not run.", worldTensionDelta: 0)
        }

        let store = try makeStore(aiService: service)
        store.choose(testCountry)
        var state = try XCTUnwrap(store.state)
        state.victoryStatus = .won
        store.state = state

        await store.performAdvance(months: 1)

        XCTAssertEqual(store.state?.round, state.round)
        XCTAssertEqual(store.state?.gameDate, state.gameDate)
        XCTAssertTrue(store.lastError?.localizedCaseInsensitiveContains("ended") == true)
    }

    func testDeletingPlannedActionRefundsAdministrativeCapacityUpToTurnCap() throws {
        let store = try makeStore()
        store.choose(testCountry)
        var state = try XCTUnwrap(store.state)
        let action = try XCTUnwrap(NativeGameEngine.action(
            from: "Fund a public service delivery audit.",
            date: state.gameDate
        ))
        state.administrativeCapacity = 110
        state.plannedActions = [action]
        store.state = state

        store.deleteAction(id: action.id)

        XCTAssertEqual(store.state?.administrativeCapacity, 120)
        XCTAssertTrue(store.state?.plannedActions.isEmpty == true)
    }

    func testAIProviderPreferencePersistsInDefaults() {
        let defaults = makeDefaults()
        XCTAssertEqual(NativeAIProviderPreference.current(defaults: defaults), .openRouter)

        defaults.set(NativeAIProviderPreference.openRouter.rawValue, forKey: NativeAIProviderPreference.storageKey)
        XCTAssertEqual(NativeAIProviderPreference.current(defaults: defaults), .openRouter)

        defaults.set(NativeAIProviderPreference.zai.rawValue, forKey: NativeAIProviderPreference.storageKey)
        XCTAssertEqual(NativeAIProviderPreference.current(defaults: defaults), .zai)
    }

    func testAIProviderServicesReadInjectedDefaults() async throws {
        let defaults = makeDefaults()
        defaults.set("or-test-key", forKey: "OPENROUTER_API_KEY")
        defaults.set("zai-test-key", forKey: "ZAI_API_KEY")
        defaults.set(NativeAIProviderPreference.openRouter.rawValue, forKey: NativeAIProviderPreference.storageKey)

        let openRouter = NativeOpenRouterService(defaults: defaults)
        XCTAssertEqual(openRouter.apiKey, "or-test-key")
        XCTAssertEqual(openRouter.providerDisplayName, "OpenRouter")
        XCTAssertEqual(openRouter.modelLanes.map(\.name), ["openrouter/free"])
        XCTAssertEqual(openRouter.modelLanes.first?.displayName, "Free Models Router")
        XCTAssertEqual(openRouter.modelLanes.first?.maxConcurrent, 3)
        let firstOpenRouterLane = try XCTUnwrap(openRouter.modelLanes.first)
        let secondOpenRouterLane = try XCTUnwrap(openRouter.modelLanes.first)
        XCTAssertTrue(firstOpenRouterLane === secondOpenRouterLane)

        let progress = NativeTurnProgress(
            completedLanes: 0,
            detail: "Calling OpenRouter Free API with Free Models Router first.",
            phase: "Consulting OpenRouter",
            totalLanes: 4,
            providerName: openRouter.providerDisplayName,
            modelName: openRouter.primaryModelDisplayName,
            modelIdentifier: openRouter.primaryModelIdentifier
        )
        XCTAssertEqual(progress.providerSummary, "Calling OpenRouter · Free Models Router")
        XCTAssertFalse(progress.providerSummary?.localizedCaseInsensitiveContains("Apple") ?? true)

        let readiness = await openRouter.checkReadiness()
        XCTAssertTrue(readiness.ok)
        XCTAssertEqual(readiness.tokenBudget, "OpenRouter free router configured; live calls validate on use")

        let suggestionsProvider = CapturingOpenRouterGameService(defaults: defaults)
        let suggestions = try await suggestionsProvider.generateSuggestedActions(for: makeState())
        XCTAssertEqual(suggestions.count, 4)
        XCTAssertEqual(suggestionsProvider.modelLanes.map(\.name), ["openrouter/free"])
        XCTAssertEqual(suggestionsProvider.capturedRequests.count, 1)
        let firstPrompt = try XCTUnwrap(suggestionsProvider.capturedRequests.first?.prompt)
        XCTAssertTrue(firstPrompt.contains("Create exactly four concrete civic proposals"))
        XCTAssertTrue(firstPrompt.contains("accept-ready"))
        XCTAssertTrue(firstPrompt.contains("Respect current administrative capacity"))
        XCTAssertTrue(firstPrompt.contains("Campaign objectives"))
        XCTAssertTrue(firstPrompt.contains("Domestic legitimacy"))
        XCTAssertTrue(firstPrompt.contains("Current selected ledger"))
        XCTAssertTrue(firstPrompt.contains("Strategy database"))
        XCTAssertTrue(firstPrompt.contains("Required JSON schema"))
        XCTAssertTrue(firstPrompt.contains("\"suggestions\""))
        XCTAssertTrue(firstPrompt.contains("openrouter/free") == false)
        XCTAssertEqual(suggestionsProvider.capturedRequests.first?.maxTokens, 2600)

        let zai = NativeZAIService(defaults: defaults)
        XCTAssertEqual(zai.apiKey, "zai-test-key")
        XCTAssertEqual(zai.providerDisplayName, "Z.AI")

        let store = try makeStore(defaults: defaults)
        XCTAssertEqual(store.selectedAIProviderPreference, .openRouter)
    }

    func testDynamicAIServiceRoutesEveryGameAISurfaceThroughOpenRouterFree() async throws {
        let defaults = makeDefaults()
        defaults.set("or-test-key", forKey: "OPENROUTER_API_KEY")
        defaults.set(NativeAIProviderPreference.openRouter.rawValue, forKey: NativeAIProviderPreference.storageKey)
        let openRouter = CapturingOpenRouterGameService(defaults: defaults)
        let service = DynamicAIService(defaults: defaults, openRouterService: openRouter)
        let state = makeState()

        let readiness = await service.checkReadiness()
        XCTAssertTrue(readiness.ok)
        XCTAssertEqual(readiness.tokenBudget, "OpenRouter free router configured; live calls validate on use")
        XCTAssertEqual(service.lastProviderUsed, "OpenRouter")
        XCTAssertTrue(openRouter.capturedRequests.isEmpty)

        var progressEvents: [NativeTurnProgress] = []
        let generatedTurn = try await service.generateTurn(for: state, months: 1) { progress in
            progressEvents.append(progress)
        }
        XCTAssertEqual(service.lastProviderUsed, "OpenRouter")
        XCTAssertTrue(generatedTurn.events.contains { !$0.playerRelated })
        XCTAssertTrue(generatedTurn.events.contains { $0.playerRelated })
        XCTAssertFalse(progressEvents.isEmpty)
        XCTAssertTrue(progressEvents.allSatisfy { $0.providerName == "OpenRouter" })
        XCTAssertTrue(progressEvents.allSatisfy { $0.modelIdentifier == "openrouter/free" })
        XCTAssertTrue(progressEvents.contains { $0.providerSummary == "Calling OpenRouter · Free Models Router" })

        let suggestions = try await service.generateSuggestedActions(for: state)
        XCTAssertEqual(service.lastProviderUsed, "OpenRouter")
        XCTAssertEqual(suggestions.count, 4)

        let advisor = try await service.generateAdvisorBrief(
            for: state,
            question: "What should we do next without writing every order manually?"
        )
        XCTAssertEqual(service.lastProviderUsed, "OpenRouter")
        XCTAssertTrue(advisor.contains("OpenRouter advisor"))

        let thread = NativeDiplomaticThread(
            id: "thread-arg",
            lastUpdated: state.gameDate,
            messages: [
                NativeDiplomaticMessage(date: state.gameDate, id: "msg-1", speaker: "Argentina", text: "We need corridor guarantees.")
            ],
            participant: PlayerCountry(code: "ARG", name: "Argentina"),
            summary: "Argentina wants bounded logistics coordination."
        )
        let reply = try await service.generateDiplomaticReply(
            for: state,
            thread: thread,
            message: "Offer a narrow logistics channel."
        )
        XCTAssertEqual(service.lastProviderUsed, "OpenRouter")
        XCTAssertTrue(reply.contains("OpenRouter diplomacy"))

        XCTAssertEqual(openRouter.modelLanes.map(\.name), ["openrouter/free"])
        let unifiedTurnRequests = openRouter.capturedRequests.filter {
            $0.responseFormat == "json_object" &&
                $0.prompt.contains("Resolve one SwiftHistoria turn in a single OpenRouter Free response")
        }
        XCTAssertEqual(unifiedTurnRequests.count, 1)
        XCTAssertTrue(unifiedTurnRequests.allSatisfy { $0.prompt.contains("Required JSON schema") })
        XCTAssertTrue(unifiedTurnRequests.allSatisfy { $0.prompt.contains("\"events\"") })
        XCTAssertTrue(unifiedTurnRequests.allSatisfy { $0.prompt.contains("Campaign objectives") })
        XCTAssertTrue(openRouter.capturedRequests.contains { $0.prompt.contains("Create exactly four concrete civic proposals") && $0.prompt.contains("\"suggestions\"") })
        XCTAssertTrue(openRouter.capturedRequests.contains { $0.prompt.contains("SwiftHistoria strategic advisor") && $0.prompt.contains("Campaign objectives") })
        XCTAssertTrue(openRouter.capturedRequests.contains { $0.prompt.contains("diplomacy chat inside SwiftHistoria") && $0.prompt.contains("Recent campaign context") })
    }

    func testOpenRouterSuggestionsAcceptFreeModelSchemaVariants() async throws {
        let defaults = makeDefaults()
        defaults.set("or-test-key", forKey: "OPENROUTER_API_KEY")
        let openRouter = CapturingOpenRouterGameService(defaults: defaults)
        openRouter.suggestionResponse = """
        {
          "actions": [
            {
              "name": "Stage Export Credit Review",
              "summary": "Create a bounded treasury export-credit review next period for firms already near customs clearance.",
              "expectedOutcome": "Primary mechanic: trade balance; secondary mechanic: market confidence; capacity fit: within current administrative capacity.",
              "rationale": "This targets the external-balance objective without adding a broad subsidy program.",
              "priority": "soon"
            },
            {
              "action": "Open Corridor Security Audit",
              "description": "Assign a civilian audit team to logistics corridors where service disruption would raise local anxiety.",
              "effectTrack": "public security and insurgency pressure",
              "risk": "May expose procurement delays before mitigation funding is ready.",
              "why": "This protects territorial integrity while keeping the order narrow.",
              "timing": "immediate"
            },
            {
              "proposal": "Publish Grid Reserve Schedule",
              "detail": "Publish a regulator-led grid reserve schedule for peak months with measurable maintenance windows.",
              "primaryMechanic": "economic resilience and domestic legitimacy",
              "justification": "This supports domestic legitimacy by reducing visible service volatility.",
              "urgency": "opportunistic"
            }
          ]
        }
        """

        let suggestions = try await openRouter.generateSuggestedActions(for: makeState())

        XCTAssertEqual(suggestions.count, 3)
        XCTAssertTrue(suggestions.allSatisfy { openRouter.isValidNativeSuggestion($0) })
        XCTAssertEqual(suggestions.map(\.urgency), ["soon", "immediate", "opportunistic"])
    }

    func testOpenRouterLengthFinishReasonKeepsVisibleContentForRepairParsing() throws {
        let payload = """
        {
          "choices": [
            {
              "message": {
                "content": "{ \\"suggestions\\": [ { \\"title\\": \\"Fund Logistics Desk\\", \\"detail\\": \\"Create a bounded desk"
              },
              "finish_reason": "length"
            }
          ]
        }
        """

        let content = try NativeZAIService.decodeCompletionContent(
            from: XCTUnwrap(payload.data(using: .utf8)),
            providerDisplayName: "OpenRouter"
        )

        XCTAssertTrue(content.contains("\"suggestions\""))
        XCTAssertTrue(content.contains("Fund Logistics Desk"))
    }

    func testDynamicAIServiceKeepsSelectedOpenRouterFailuresOnOpenRouter() async throws {
        let defaults = makeDefaults()
        defaults.set("or-test-key", forKey: "OPENROUTER_API_KEY")
        defaults.set(NativeAIProviderPreference.openRouter.rawValue, forKey: NativeAIProviderPreference.storageKey)
        let service = DynamicAIService(defaults: defaults, openRouterService: FailingOpenRouterGameService(defaults: defaults))
        let state = makeState()

        do {
            _ = try await service.generateTurn(for: state, months: 1) { _ in }
            XCTFail("Expected OpenRouter turn failure to propagate.")
        } catch {
            XCTAssertEqual(service.lastProviderUsed, "OpenRouter")
            XCTAssertTrue(error.localizedDescription.contains("OpenRouter fixture failure"))
        }

        do {
            _ = try await service.generateSuggestedActions(for: state)
            XCTFail("Expected OpenRouter suggestion failure to propagate.")
        } catch {
            XCTAssertEqual(service.lastProviderUsed, "OpenRouter")
            XCTAssertTrue(error.localizedDescription.contains("OpenRouter fixture failure"))
        }

        do {
            _ = try await service.generateAdvisorBrief(for: state, question: "What now?")
            XCTFail("Expected OpenRouter advisor failure to propagate.")
        } catch {
            XCTAssertEqual(service.lastProviderUsed, "OpenRouter")
            XCTAssertTrue(error.localizedDescription.contains("OpenRouter fixture failure"))
        }

        let thread = NativeDiplomaticThread(
            id: "thread-arg",
            lastUpdated: state.gameDate,
            messages: [
                NativeDiplomaticMessage(date: state.gameDate, id: "msg-1", speaker: "Argentina", text: "We need corridor guarantees.")
            ],
            participant: PlayerCountry(code: "ARG", name: "Argentina"),
            summary: "Argentina wants bounded logistics coordination."
        )
        do {
            _ = try await service.generateDiplomaticReply(for: state, thread: thread, message: "Offer a narrow logistics channel.")
            XCTFail("Expected OpenRouter diplomacy failure to propagate.")
        } catch {
            XCTAssertEqual(service.lastProviderUsed, "OpenRouter")
            XCTAssertTrue(error.localizedDescription.contains("OpenRouter fixture failure"))
        }
    }

    func testDynamicAIServiceDoesNotFallbackWhenOpenRouterIsSelectedWithoutKey() async throws {
        let defaults = makeDefaults()
        defaults.set("zai-test-key", forKey: "ZAI_API_KEY")
        defaults.set(NativeAIProviderPreference.openRouter.rawValue, forKey: NativeAIProviderPreference.storageKey)
        let service = DynamicAIService(defaults: defaults)
        let state = makeState()

        let readiness = await service.checkReadiness()
        XCTAssertFalse(readiness.ok)
        XCTAssertEqual(service.lastProviderUsed, "OpenRouter")
        XCTAssertTrue(readiness.lastError.contains("OpenRouter is selected"))
        XCTAssertFalse(readiness.tokenBudget.localizedCaseInsensitiveContains("fallback"))

        do {
            _ = try await service.generateTurn(for: state, months: 1) { progress in
                XCTAssertEqual(progress.providerName, "OpenRouter")
                XCTAssertEqual(progress.modelIdentifier, "openrouter/free")
            }
            XCTFail("Expected missing OpenRouter key to fail instead of falling back.")
        } catch {
            XCTAssertEqual(service.lastProviderUsed, "OpenRouter")
            XCTAssertTrue(error.localizedDescription.contains("OpenRouter is selected"))
        }

        do {
            _ = try await service.generateSuggestedActions(for: state)
            XCTFail("Expected missing OpenRouter key to fail suggestions instead of falling back.")
        } catch {
            XCTAssertEqual(service.lastProviderUsed, "OpenRouter")
            XCTAssertTrue(error.localizedDescription.contains("OpenRouter is selected"))
        }
    }

    func testSaveSlotsResumeTheActiveCampaignAfterFreshLaunch() throws {
        let defaults = makeDefaults()
        let persistenceDirectory = try makePersistenceDirectory()
        let store = NativeCampaignStore(
            defaults: defaults,
            aiService: FakeNativeAIService(),
            persistenceDirectory: persistenceDirectory
        )

        store.choose(PlayerCountry(code: "BRA", name: "Brazil"))
        store.setLanguage(.portuguese)
        store.selectScenario(id: "resilience-decade")
        store.switchSlot(2)
        store.choose(PlayerCountry(code: "ARG", name: "Argentina"))
        store.setLanguage(.spanish)
        store.selectScenario(id: "solarpunk-dawn")
        XCTAssertEqual(store.saveSlot, 2)
        XCTAssertEqual(store.state?.country.code, "ARG")
        XCTAssertEqual(store.state?.language, .spanish)
        XCTAssertEqual(store.state?.scenarioID, "solarpunk-dawn")
        XCTAssertEqual(store.slotSummary(1)?.countryName, "Brazil")
        XCTAssertEqual(store.slotSummary(2)?.countryName, "Argentina")

        let relaunched = NativeCampaignStore(
            defaults: defaults,
            aiService: FakeNativeAIService(),
            persistenceDirectory: persistenceDirectory
        )

        XCTAssertEqual(relaunched.saveSlot, 2)
        XCTAssertEqual(relaunched.state?.country.code, "ARG")
        XCTAssertEqual(relaunched.selectedCountry?.code, "ARG")
        XCTAssertEqual(relaunched.state?.language, .spanish)
        XCTAssertEqual(relaunched.selectedLanguage, .spanish)
        XCTAssertEqual(relaunched.state?.scenarioID, "solarpunk-dawn")
        XCTAssertEqual(relaunched.selectedScenarioID, "solarpunk-dawn")

        relaunched.switchSlot(1)
        XCTAssertEqual(relaunched.state?.country.code, "BRA")
        XCTAssertEqual(relaunched.selectedCountry?.code, "BRA")
        XCTAssertEqual(relaunched.state?.language, .portuguese)
        XCTAssertEqual(relaunched.selectedScenarioID, "resilience-decade")
    }

    func testLiveOpenRouterFreeSuggestedActionsWhenEnabled() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["PAX_HISTORIA_RUN_LIVE_OPENROUTER"] == "1" else {
            throw XCTSkip("Set PAX_HISTORIA_RUN_LIVE_OPENROUTER=1 to exercise the real OpenRouter Free suggestion path.")
        }
        guard let key = environment["OPENROUTER_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else {
            throw XCTSkip("OPENROUTER_API_KEY is required for the live OpenRouter Free suggestion path.")
        }

        let defaults = makeDefaults()
        defaults.set(key, forKey: "OPENROUTER_API_KEY")
        let service = NativeOpenRouterService(defaults: defaults)

        let suggestions = try await service.generateSuggestedActions(for: makeState())

        XCTAssertGreaterThanOrEqual(suggestions.count, 3)
        XCTAssertLessThanOrEqual(suggestions.count, 4)
        for suggestion in suggestions {
            XCTAssertTrue(service.isValidNativeSuggestion(suggestion))
            let detailNamesGameSystem = suggestion.detail.localizedCaseInsensitiveContains("mechanic") ||
                suggestion.detail.localizedCaseInsensitiveContains("capacity")
            let rationaleNamesGameSystem = suggestion.rationale.localizedCaseInsensitiveContains("mechanic") ||
                suggestion.rationale.localizedCaseInsensitiveContains("objective")
            XCTAssertTrue(detailNamesGameSystem)
            XCTAssertTrue(rationaleNamesGameSystem)
        }
    }

    func testCampaignObjectivesExposeScenarioWinProgress() {
        var state = makeState()
        state.scenarioID = NativeScenarioCatalog.defaultScenario.id
        state.stability = 80
        state.economicLedger.tradeBalancePercentGDP = 0.5

        let objectives = NativeGameEngine.campaignObjectives(for: state)
        let expectedCoreRegions = max(1, GeopoliticalMapData.regions(forCountryCode: state.country.code).count)

        XCTAssertEqual(objectives.count, 3)
        XCTAssertTrue(objectives.contains { $0.id == "stability" && $0.isComplete })
        XCTAssertTrue(objectives.contains { $0.id == "trade" && $0.isComplete })
        XCTAssertTrue(objectives.contains { $0.id == "core" && $0.targetValue == "\(expectedCoreRegions) secure" })
        XCTAssertTrue(objectives.allSatisfy { !$0.title.isEmpty && !$0.deadline.isEmpty })
    }

    func testSolarpunkObjectiveAndVictoryTreatTinyInsurgencyAsZero() {
        var state = makeState()
        state.scenarioID = "solarpunk-dawn"
        state.gameDate = "2069-01-15"
        state.stability = 85
        state.economicLedger.rebelControlPercent = 0.05
        state.economicLedger.securityIndex = 80

        let objectives = NativeGameEngine.campaignObjectives(for: state)

        XCTAssertEqual(NativeGameEngine.evaluateVictoryStatus(for: state), .won)
        XCTAssertTrue(objectives.contains { $0.id == "rebel" && $0.isComplete })
    }

    func testDirectivePreviewUsesQuickActionAndRegionalCosts() throws {
        var state = makeState()
        state.administrativeCapacity = 45

        let tradePreview = NativeGameEngine.previewDirective("Propose a bilateral trade agreement to deepen ties.", in: state)
        XCTAssertEqual(tradePreview.cost, 15)
        XCTAssertEqual(tradePreview.capacityAfter, 30)
        XCTAssertTrue(tradePreview.expectedEffects.contains { $0.contains("Diplomatic") || $0.contains("Trade") })

        let region = try XCTUnwrap(GeopoliticalMapData.regions.first { $0.id == "ARG" })
        let invadePreview = NativeGameEngine.previewDirective("Invade \(region.name) (ID: \(region.id))", in: state)
        XCTAssertEqual(invadePreview.cost, 40)
        XCTAssertEqual(invadePreview.capacityAfter, 5)
        XCTAssertTrue(invadePreview.expectedEffects.contains { $0.localizedCaseInsensitiveContains("dice") })

        state.administrativeCapacity = 10
        let blockedPreview = NativeGameEngine.previewDirective("Fortify \(region.name) (ID: \(region.id))", in: state)
        XCTAssertEqual(blockedPreview.cost, 35)
        XCTAssertNotNil(blockedPreview.warning)
    }

    func testRegionalOrdersResolveDeterministicallyWithoutAI() throws {
        var state = makeState()
        let region = try XCTUnwrap(GeopoliticalMapData.regions.first { $0.countryCode == "BRA" })
        let action = NativePlannedAction(
            createdAt: state.gameDate,
            detail: "Stabilize \(region.name) (ID: \(region.id))",
            id: "action-stabilize-bra",
            resolvedAt: nil,
            status: .planned,
            title: "Stabilize \(region.name) (ID: \(region.id))"
        )
        state.plannedActions = [action]
        state.regionOccupations[region.id] = "REB"
        state.regionConflicts[region.id] = NativeRegionConflictState(
            controllerCode: "REB",
            intensity: 5,
            mode: .guerrillaControl,
            originalCountryCode: region.countryCode,
            regionID: region.id,
            summary: "Test insurgency pressure.",
            updatedAt: state.gameDate
        )

        let applied = NativeGameEngine.apply(
            NativeGeneratedTurn(events: [], stabilityDelta: 0, summary: "Regional order resolved.", worldTensionDelta: 0),
            to: state,
            months: 1
        )

        XCTAssertEqual(applied.plannedActions.first?.status, .resolved)
        XCTAssertNil(applied.regionOccupations[region.id])
        XCTAssertEqual(applied.regionConflicts[region.id]?.mode, .stabilization)
        XCTAssertTrue(applied.timeline.contains { $0.id.hasPrefix("regional-stabilize-\(region.id)-") })
    }

    func testMalformedRegionalOrderDoesNotRemainPlannedForever() {
        var state = makeState()
        let action = NativePlannedAction(
            createdAt: state.gameDate,
            detail: "Fortify imaginary province (ID: DOES_NOT_EXIST)",
            id: "action-invalid-regional",
            resolvedAt: nil,
            status: .planned,
            title: "Fortify imaginary province"
        )
        state.plannedActions = [action]

        let applied = NativeGameEngine.apply(
            NativeGeneratedTurn(events: [], stabilityDelta: 0, summary: "No external adjudication.", worldTensionDelta: 0),
            to: state,
            months: 1
        )

        XCTAssertEqual(applied.plannedActions.first?.status, .resolved)
        XCTAssertTrue(applied.timeline.contains { event in
            event.id.hasPrefix("regional-invalid-action-invalid-regional-") &&
                event.linkedActionIDs == ["action-invalid-regional"]
        })
    }

    func testAfterActionReportSummarizesResolvedOrders() {
        let state = makeState()
        let turn = NativeGeneratedTurn(
            events: [
                makeEvent(id: "reported-action", playerRelated: true, linkedActionIDs: ["action-1"], track: .economicResilience, magnitude: 2),
                makeEvent(id: "reported-world", playerRelated: false, track: .worldTension, magnitude: -1)
            ],
            stabilityDelta: 1,
            summary: "Cabinet after-action reporting links orders to visible effects.",
            worldTensionDelta: -2
        )

        let report = NativeGameEngine.afterActionReport(for: turn, state: state)

        XCTAssertEqual(report.resolvedOrderCount, 1)
        XCTAssertEqual(report.events.count, 2)
        XCTAssertTrue(report.metrics.contains { $0.id == "economy" && $0.delta == "+2" })
        XCTAssertTrue(report.summary.contains("after-action"))
    }

    func testDefaultAIProgressDoesNotPretendToBeApple() async throws {
        let service = FakeNativeAIService()
        let state = makeState()
        var progressEvents: [NativeTurnProgress] = []

        _ = try await service.generateTurn(for: state, months: 1) { progress in
            progressEvents.append(progress)
        }

        XCTAssertFalse(progressEvents.isEmpty)
        XCTAssertFalse(progressEvents.contains { event in
            event.detail.localizedCaseInsensitiveContains("Apple") ||
                event.phase.localizedCaseInsensitiveContains("Apple") ||
                (event.providerSummary?.localizedCaseInsensitiveContains("Apple") ?? false)
        })
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

    func testPrintPromptExamples() {
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
        XCTAssertTrue(suggestionPrompt.contains("accept-ready"))
        XCTAssertTrue(suggestionPrompt.contains("Respect current administrative capacity"))
        XCTAssertTrue(suggestionPrompt.contains("Campaign objectives"))
        XCTAssertTrue(suggestionPrompt.contains("Domestic legitimacy"))

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
            diplomacyPrompt
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

    func testPromptClampPreservesOpeningAndClosingConstraints() {
        let opening = "Create one selected-region economic assessment event."
        let middle = (0 ..< 260).map { "Long context row \($0): stored evidence for the model." }.joined(separator: "\n")
        let closing = "Return one strict JSON object only. Do not include markdown fences, prose, schema labels, or comments."

        let prompt = NativePromptHarness.clamped(
            """
            \(opening)
            \(middle)
            \(closing)
            """,
            characterLimit: 1200
        )

        XCTAssertLessThanOrEqual(prompt.count, 1200)
        XCTAssertTrue(prompt.hasPrefix(opening))
        XCTAssertTrue(prompt.contains(NativePromptHarness.trimMarker.trimmingCharacters(in: .whitespacesAndNewlines)))
        XCTAssertTrue(prompt.contains(closing))
    }

    func testMultiCountryEconSimulationAndNaming() {
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
        for i in 1 ... 50 {
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

    func testScenarioExpansionCatalog() {
        let all = NativeScenarioCatalog.all
        XCTAssertEqual(all.count, 8)
        let soviet = NativeScenarioCatalog.scenario(for: "soviet-triumph")
        XCTAssertEqual(soviet.id, "soviet-triumph")
        XCTAssertEqual(soviet.name, "Soviet Triumph")
    }

    func testSovietTriumphCustomizations() {
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
        let persistenceDirectory = try makePersistenceDirectory()
        let store = NativeCampaignStore(
            defaults: defaults,
            aiService: FakeNativeAIService(),
            persistenceDirectory: persistenceDirectory
        )
        let state = makeState()
        store.choose(state.country)

        store.setGameMode(.ironman)
        XCTAssertEqual(store.state?.gameMode, .ironman)

        let newStore = NativeCampaignStore(
            defaults: defaults,
            aiService: FakeNativeAIService(),
            persistenceDirectory: persistenceDirectory
        )
        XCTAssertEqual(newStore.state?.gameMode, .ironman)
    }

    func testCampaignStoreSlotHelpersUseStableSuffixes() {
        XCTAssertEqual(NativeCampaignStore.slotKey("pax-historia.native.campaign-state.v1", slot: 1), "pax-historia.native.campaign-state.v1")
        XCTAssertEqual(NativeCampaignStore.slotKey("pax-historia.native.campaign-state.v1", slot: 2), "pax-historia.native.campaign-state.v1.slot2")
        XCTAssertEqual(NativeCampaignStore.slotKey("pax-historia.native.campaign-state.v1", slot: 3), "pax-historia.native.campaign-state.v1.slot3")

        XCTAssertEqual(NativeCampaignStore.slotFileName("campaign-state-envelope-v2.json", slot: 1), "campaign-state-envelope-v2.json")
        XCTAssertEqual(NativeCampaignStore.slotFileName("campaign-state-envelope-v2.json", slot: 2), "campaign-state-envelope-v2-slot2.json")
        XCTAssertEqual(NativeCampaignStore.slotFileName("campaign-state-envelope-v2.json", slot: 3), "campaign-state-envelope-v2-slot3.json")
    }

    func testTursoConfigurationNormalizesLibSQLURLs() throws {
        let defaults = makeDefaults()
        defaults.set("libsql://swift-historia-test.turso.io", forKey: NativeCampaignStore.tursoDatabaseURLKey)
        defaults.set("test-token", forKey: NativeCampaignStore.tursoAuthTokenKey)

        let config = try XCTUnwrap(NativeTursoCampaignPersistence.configuration(defaults: defaults, environment: [:]))

        XCTAssertEqual(config.databaseURL.absoluteString, "https://swift-historia-test.turso.io")
        XCTAssertEqual(config.pipelineURL.absoluteString, "https://swift-historia-test.turso.io/v2/pipeline")
        XCTAssertEqual(config.authToken, "test-token")
    }

    func testTursoWritePipelineUsesBlobUpsertsAndBearerAuth() throws {
        let config = try NativeTursoCampaignPersistence.Configuration(
            databaseURL: XCTUnwrap(URL(string: "https://swift-historia-test.turso.io")),
            authToken: "test-token"
        )
        let record = NativeTursoCampaignPersistence.Record(
            kind: .envelope,
            data: Data("campaign-envelope".utf8),
            savedAt: "2026-06-21T00:00:00Z"
        )
        let request = NativeTursoCampaignPersistence.pipelineRequest(
            configuration: config,
            requests: NativeTursoCampaignPersistence.writeRequests(records: [record], slot: 2)
        )

        XCTAssertEqual(request.url?.absoluteString, "https://swift-historia-test.turso.io/v2/pipeline")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
        let body = try XCTUnwrap(request.httpBody)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let requests = try XCTUnwrap(object["requests"] as? [[String: Any]])
        XCTAssertEqual((requests.last?["type"] as? String), "close")

        let upsert = try XCTUnwrap(requests.dropFirst().first?["stmt"] as? [String: Any])
        XCTAssertTrue((upsert["sql"] as? String)?.contains("ON CONFLICT(slot, kind)") == true)
        let args = try XCTUnwrap(upsert["args"] as? [[String: String]])
        XCTAssertEqual(args[0]["value"], "2")
        XCTAssertEqual(args[1]["value"], "envelope")
        XCTAssertEqual(args[3]["type"], "blob")
        XCTAssertEqual(args[3]["base64"], Data("campaign-envelope".utf8).base64EncodedString())
    }

    func testTursoPipelineResponseDecodesBlobRows() {
        let base64 = Data("campaign-envelope".utf8).base64EncodedString()
        let response = """
        {
          "results": [
            {
              "cols": [{"name": "data", "decltype": "BLOB"}],
              "rows": [[{"type": "blob", "base64": "\(base64)"}]]
            }
          ]
        }
        """

        let decoded = NativeTursoCampaignPersistence.dataBlob(fromPipelineResponse: Data(response.utf8))

        XCTAssertEqual(decoded, Data("campaign-envelope".utf8))
    }

    func testFoundationTextHelpersCollapseDuplicatesAndNormalizeUrgency() {
        XCTAssertEqual(
            sanitizeFoundationModelText("Alpha sentence. Alpha sentence. Beta sentence."),
            "Alpha sentence. Beta sentence."
        )
        XCTAssertEqual(
            sanitizeFoundationModelText("Line one\nLine one\nLine two\nLine two"),
            "Line one\nLine two"
        )
        XCTAssertTrue(hasConcreteFoundationText("Deliver a clear public transit modernization plan.", minimumWords: 4))
        XCTAssertFalse(hasConcreteFoundationText("AppleNativeGeneratedEventDraft", minimumWords: 2))
        XCTAssertEqual(normalizedFoundationUrgency("  IMMEDIATE  "), "immediate")
        XCTAssertEqual(normalizedFoundationUrgency("unknown"), "soon")
    }

    func testLoadCampaignStatePrefersNewerUserDefaultsEnvelopeOverFileCopy() throws {
        let defaults = makeDefaults()
        let persistenceDirectory = try makePersistenceDirectory()
        let decoder = JSONDecoder()
        let encoder = JSONEncoder()

        var fileState = makeState()
        fileState.round = 3
        var defaultsState = makeState()
        defaultsState.round = 8

        let fileEnvelope = NativeCampaignStore.CampaignStateEnvelope(
            schemaVersion: 2,
            savedAt: "2026-06-20T00:00:00Z",
            state: fileState
        )
        let defaultsEnvelope = NativeCampaignStore.CampaignStateEnvelope(
            schemaVersion: 2,
            savedAt: "2026-06-21T00:00:00Z",
            state: defaultsState
        )

        let envelopeURL = NativeCampaignStore.persistenceURL(
            fileName: NativeCampaignStore.campaignStateEnvelopeFileName,
            directory: persistenceDirectory
        )
        try encoder.encode(fileEnvelope).write(to: envelopeURL)
        let encodedDefaultsEnvelope = try encoder.encode(defaultsEnvelope)
        defaults.set(
            encodedDefaultsEnvelope,
            forKey: NativeCampaignStore.campaignStateEnvelopeKey
        )

        let loaded = NativeCampaignStore.loadCampaignState(
            from: defaults,
            decoder: decoder,
            persistenceDirectory: persistenceDirectory
        )

        XCTAssertEqual(loaded.state?.round, defaultsState.round)
        XCTAssertEqual(loaded.notice, "Loaded the newest campaign save from user-defaults because it is newer than the file copy.")
    }

    func testLoadCampaignStateFallsBackToBackupWhenPrimarySaveIsMissing() throws {
        let defaults = makeDefaults()
        let persistenceDirectory = try makePersistenceDirectory()
        let decoder = JSONDecoder()
        let encoder = JSONEncoder()

        var backupState = makeState()
        backupState.round = 11

        let backupEnvelope = NativeCampaignStore.CampaignStateEnvelope(
            schemaVersion: 2,
            savedAt: "2026-06-21T00:00:00Z",
            state: backupState
        )

        let backupURL = NativeCampaignStore.persistenceURL(
            fileName: NativeCampaignStore.campaignStateBackupFileName,
            directory: persistenceDirectory
        )
        try encoder.encode(backupEnvelope).write(to: backupURL)

        let loaded = NativeCampaignStore.loadCampaignState(
            from: defaults,
            decoder: decoder,
            persistenceDirectory: persistenceDirectory
        )

        XCTAssertEqual(loaded.state?.round, backupState.round)
        XCTAssertTrue(loaded.notice?.contains("last-good campaign backup") == true)
        XCTAssertTrue(loaded.notice?.contains("Source: file.") == true)
    }

    func testLoadCampaignStateLoadsLegacySaveWhenVersionedCopiesAreUnavailable() throws {
        let defaults = makeDefaults()
        let persistenceDirectory = try makePersistenceDirectory()
        let decoder = JSONDecoder()
        let encoder = JSONEncoder()

        var legacyState = makeState()
        legacyState.round = 14

        let legacyURL = NativeCampaignStore.persistenceURL(
            fileName: NativeCampaignStore.campaignStateLegacyFileName,
            directory: persistenceDirectory
        )
        try encoder.encode(legacyState).write(to: legacyURL)

        let loaded = NativeCampaignStore.loadCampaignState(
            from: defaults,
            decoder: decoder,
            persistenceDirectory: persistenceDirectory
        )

        XCTAssertEqual(loaded.state?.round, legacyState.round)
        XCTAssertTrue(loaded.notice?.contains("legacy campaign save") == true)
        XCTAssertTrue(loaded.notice?.contains("Source: file.") == true)
    }

    func testHexLever8CharacterDecodingAndTacticalNudges() {
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

    func testConflictMapNudgesRecordConventionalAndGuerrillaStates() {
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

    func testSovereigntyChangeCreatesDynamicCountryActor() {
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

    func testEmptyDraftActionIsANoOpWithoutCapacityError() {
        let state = makeState()
        let store = NativeCampaignStore(aiService: FakeNativeAIService())
        store.state = state
        store.state?.administrativeCapacity = 5
        store.draftAction = "   "

        store.addDraftAction()

        XCTAssertNil(store.lastError)
        XCTAssertEqual(store.state?.administrativeCapacity, 5)
        XCTAssertEqual(store.state?.plannedActions.count, 0)
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

    func testTurnResolutionStabilityCrisisAndCollapse() {
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

    func testScenarioVictoryConditionEvaluation() {
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
        state.economicLedger = try XCTUnwrap(ledgers[state.country.code])

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
        boostState.economicLedger = try XCTUnwrap(boostLedgers[boostState.country.code])

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

    func testWorldTensionEscalationAndParanoia() {
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

    func testTerritorialAndRadiologicalPenalties() {
        var state = makeState()
        state.regionOccupations = ["BRA_Acre": "CHN"]
        state.nuclearFalloutRegions = ["BRA_Acre"]

        let generated = NativeGeneratedTurn(events: [], stabilityDelta: 0, summary: "Leap", worldTensionDelta: 0)
        let resolved = NativeGameEngine.apply(generated, to: state, months: 1)

        let penaltyEntry = resolved.economicLedger.entries.first { $0.ruleID == "territorial-crisis" }
        XCTAssertNotNil(penaltyEntry)
        XCTAssertEqual(penaltyEntry?.growthDelta ?? 0, -2.5, accuracy: 0.01)
        XCTAssertEqual(penaltyEntry?.inflationDelta ?? 0, 3.0, accuracy: 0.01)
        XCTAssertLessThan(resolved.economicLedger.realGrowthPercent, state.economicLedger.realGrowthPercent)
        XCTAssertEqual(resolved.economicLedger.inflationPercent, 8.0, accuracy: 0.1)
        XCTAssertEqual(resolved.stability, 67)
    }

    func test512DiceFrictionSystem() {
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
private struct CapturedProviderRequest {
    var prompt: String
    var maxTokens: Int
    var responseFormat: String?
}

@MainActor
private class CapturingOpenRouterGameService: NativeOpenRouterService {
    var capturedRequests: [CapturedProviderRequest] = []
    var suggestionResponse: String?
    private var eventIndex = 0

    override var apiKey: String {
        "test-openrouter-key"
    }

    override func executeProviderRequest(
        prompt: String,
        maxTokens: Int,
        temperature _: Double,
        responseFormat: String? = nil,
        thinkingEnabled _: Bool = true,
        onStreamProgress _: (@MainActor (String) -> Void)? = nil
    ) async throws -> String {
        capturedRequests.append(CapturedProviderRequest(prompt: prompt, maxTokens: maxTokens, responseFormat: responseFormat))
        if prompt.contains("Return exactly this JSON") {
            return "{\"ok\":true}"
        }
        if responseFormat == nil {
            if prompt.contains("diplomacy chat inside SwiftHistoria") {
                return "OpenRouter diplomacy reply keeps the logistics channel narrow and tied to the current corridor pressure."
            }
            return "OpenRouter advisor response reads the ledger, objectives, and current order load before recommending one bounded next move."
        }
        if prompt.contains("\"suggestions\"") {
            return suggestionResponse ?? suggestionBatchJSON
        }
        if prompt.contains("Resolve one SwiftHistoria turn in a single OpenRouter Free response") {
            return unifiedTurnJSON
        }
        if prompt.contains("\"stabilityDelta\""), prompt.contains("\"globalFrictionDelta\"") {
            return """
            {
              "summary": "OpenRouter Free synthesizes the validated lanes into a compact game-world turn.",
              "stabilityDelta": 1,
              "globalFrictionDelta": -1
            }
            """
        }

        eventIndex += 1
        return eventJSON(index: eventIndex)
    }

    private var unifiedTurnJSON: String {
        let linkedActionIDJSON = makeState().plannedActions.first.map { "\"\($0)\"" } ?? "null"
        return """
        {
          "summary": "OpenRouter Free resolves the period by balancing logistics reform, public security, and market confidence in one validated turn.",
          "stabilityDelta": 1,
          "worldTensionDelta": -1,
          "events": [
            {
              "title": "Regional Market Confidence Review",
              "description": "Regional planning ministries review corridor bottlenecks and publish measurable logistics milestones before the next monthly cabinet cycle.",
              "kind": "world",
              "importance": "major",
              "notable": true,
              "playerRelated": false,
              "linkedActionID": null,
              "effectTarget": "GLOBAL",
              "effectTrack": "market-confidence",
              "effectMagnitude": 1,
              "effectSummary": "The review improves market confidence while keeping world tension contained.",
              "hexLeverCode": null,
              "sovereigntyChange": null
            },
            {
              "title": "OpenRouter Order Implementation Review",
              "description": "Domestic agencies convert the queued order into bounded implementation milestones tied to fiscal space and service delivery capacity.",
              "kind": "domestic",
              "importance": "major",
              "notable": true,
              "playerRelated": true,
              "linkedActionID": \(linkedActionIDJSON),
              "effectTarget": "BRA",
              "effectTrack": "economic-resilience",
              "effectMagnitude": 1,
              "effectSummary": "The order strengthens economic resilience through measured administrative execution.",
              "hexLeverCode": null,
              "sovereigntyChange": null
            },
            {
              "title": "Security Capacity Audit",
              "description": "Civilian security planners audit high-pressure municipalities and report staffing needs without expanding the campaign beyond current capacity.",
              "kind": "domestic",
              "importance": "minor",
              "notable": true,
              "playerRelated": true,
              "linkedActionID": null,
              "effectTarget": "BRA",
              "effectTrack": "internal-stability",
              "effectMagnitude": 1,
              "effectSummary": "The audit improves internal stability by identifying pressure points before unrest grows.",
              "hexLeverCode": null,
              "sovereigntyChange": null
            },
            {
              "title": "Trade Desk Coordination",
              "description": "The treasury and foreign ministry align trade desk priorities with export bottlenecks and near-term diplomatic channels.",
              "kind": "economy",
              "importance": "minor",
              "notable": true,
              "playerRelated": true,
              "linkedActionID": null,
              "effectTarget": "BRA",
              "effectTrack": "diplomatic-leverage",
              "effectMagnitude": 1,
              "effectSummary": "The coordination improves diplomatic leverage while protecting the current trade balance objective.",
              "hexLeverCode": null,
              "sovereigntyChange": null
            }
          ]
        }
        """
    }

    private var suggestionBatchJSON: String {
        """
        {
          "suggestions": [
            {
              "title": "Fund Logistics Desk",
              "detail": "Create a bounded regional logistics desk next period through a transport agency; primary mechanic: trade balance; secondary mechanic: market confidence; capacity fit: within current administrative capacity; intended effect: reduce corridor pressure.",
              "rationale": "This fits the current campaign objectives by improving trade balance while protecting market confidence under the selected ledger constraints.",
              "urgency": "soon"
            },
            {
              "title": "Audit Security Corridors",
              "detail": "Assign a civilian security audit team next period to contested service corridors; primary mechanic: public security; secondary mechanic: insurgency pressure; capacity fit: within current administrative capacity; intended effect: expose stabilization gaps.",
              "rationale": "This fits the current campaign objectives by improving territorial integrity while reducing insurgency pressure in the current map context.",
              "urgency": "immediate"
            },
            {
              "title": "Open Trade Balance Desk",
              "detail": "Open a treasury trade desk next period for export bottleneck review; primary mechanic: trade balance; secondary mechanic: fiscal space; capacity fit: within current administrative capacity; intended effect: identify cheap external-balance gains.",
              "rationale": "This fits the current campaign objectives by targeting external balance while protecting fiscal space in the selected ledger.",
              "urgency": "soon"
            },
            {
              "title": "Publish Energy Resilience Plan",
              "detail": "Publish a bounded grid resilience plan through the energy regulator next period; primary mechanic: economic resilience; secondary mechanic: unemployment; capacity fit: within current administrative capacity; intended effect: reduce service volatility.",
              "rationale": "This fits the current campaign objectives by supporting domestic legitimacy while limiting employment and resilience pressure.",
              "urgency": "opportunistic"
            }
          ]
        }
        """
    }

    private func eventJSON(index: Int) -> String {
        """
        {
          "title": "OpenRouter Lane \(index) Review",
          "description": "Regional agencies review logistics corridors and service capacity using the current campaign ledger, objectives, and diplomatic pressure before publishing measurable planning milestones.",
          "kind": "economy",
          "importance": "major",
          "notable": true,
          "effectTarget": "BRA",
          "effectTrack": "market-confidence",
          "effectMagnitude": 1,
          "effectSummary": "OpenRouter Free links the generated lane to stored market-confidence and service-capacity mechanics.",
          "hexLeverCode": null,
          "sovereigntyChange": null
        }
        """
    }
}

@MainActor
private final class FailingOpenRouterGameService: NativeOpenRouterService {
    override var apiKey: String {
        "test-openrouter-key"
    }

    override func executeProviderRequest(
        prompt _: String,
        maxTokens _: Int,
        temperature _: Double,
        responseFormat _: String? = nil,
        thinkingEnabled _: Bool = true,
        onStreamProgress _: (@MainActor (String) -> Void)? = nil
    ) async throws -> String {
        throw NativeFoundationModelError.generationFailed("OpenRouter fixture failure")
    }
}

@MainActor
private final class FakeNativeAIService: NativeAIService {
    var turnHandler: ((NativeCampaignState, Int) async throws -> NativeGeneratedTurn)?
    var suggestionHandler: ((NativeCampaignState) async throws -> [NativeSuggestedAction])?

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
        if let suggestionHandler {
            return try await suggestionHandler(state)
        }
        return [
            NativeSuggestedAction(detail: "Fund a service access audit for district agencies.", id: "fake-1", rationale: "It fits current delivery constraints.", title: "Audit service access", urgency: "soon"),
            NativeSuggestedAction(detail: "Open a logistics desk for regional infrastructure permits.", id: "fake-2", rationale: "It supports market confidence.", title: "Coordinate logistics desk", urgency: "opportunistic"),
            NativeSuggestedAction(detail: "Publish a fiscal buffer plan for essential services.", id: "fake-3", rationale: "It protects stability during delays.", title: "Publish buffer plan", urgency: "immediate")
        ]
    }

    func generateAdvisorBrief(for _: NativeCampaignState, question _: String) async throws -> String {
        "Hold the line on concrete service delivery and avoid vague commitments."
    }

    func generateDiplomaticReply(for _: NativeCampaignState, thread _: NativeDiplomaticThread, message _: String) async throws -> String {
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
    try NativeCampaignStore(
        defaults: defaults,
        aiService: aiService,
        persistenceDirectory: makePersistenceDirectory()
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

private func makeValidTurn(for state: NativeCampaignState, months _: Int) -> NativeGeneratedTurn {
    NativeGeneratedTurn(
        events: [
            makeEvent(id: "independent-\(state.round)", playerRelated: false),
            makeEvent(id: "player-\(state.round)", playerRelated: true)
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
            )
        ],
        title: title
    )
}
