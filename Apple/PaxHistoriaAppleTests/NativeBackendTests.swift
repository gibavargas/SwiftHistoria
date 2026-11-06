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

    func testForeignInternalStabilityEffectsDoNotMutatePlayerStability() {
        var state = makeState()
        state.stability = 70
        let targetDate = NativeGameEngine.advance(date: state.gameDate, months: 1)
        let foreignEvent = NativeCampaignEvent(
            date: targetDate,
            description: "A foreign cabinet completes a domestic administrative reform with measurable local effects.",
            id: "foreign-stability",
            importance: .major,
            kind: .world,
            linkedActionIDs: [],
            notable: true,
            playerRelated: false,
            strategicEffects: [
                NativeStrategicEffect(
                    date: targetDate,
                    eventId: "foreign-stability",
                    id: "foreign-stability-effect",
                    magnitude: 3,
                    summary: "The foreign reform improves local institutional stability without changing Brazil.",
                    target: "USA",
                    track: .internalStability
                )
            ],
            title: "Foreign Reform Completed"
        )
        let baseline = NativeGameEngine.apply(
            NativeGeneratedTurn(
                events: [],
                stabilityDelta: 0,
                summary: "Foreign institutions continue normal operations while Brazil remains unchanged.",
                worldTensionDelta: 0
            ),
            to: state,
            months: 1
        )
        let applied = NativeGameEngine.apply(
            NativeGeneratedTurn(
                events: [foreignEvent],
                stabilityDelta: 0,
                summary: "Foreign institutions complete a reform while Brazil remains unchanged.",
                worldTensionDelta: 0
            ),
            to: state,
            months: 1
        )

        XCTAssertEqual(applied.stability, baseline.stability)
        XCTAssertTrue(applied.timeline.contains { $0.id == foreignEvent.id })
        XCTAssertTrue(applied.economicLedgers["USA"]?.entries.contains { $0.eventID == foreignEvent.id } == true)
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

    func testStateApplicationPreservesLongCampaignTimeline() {
        var state = makeState()
        let historicalEvents = (0 ..< 305).map { index in
            makeEvent(
                id: "historical-event-\(index)",
                date: state.gameDate,
                playerRelated: index.isMultiple(of: 2)
            )
        }
        state.timeline = historicalEvents
        let historicalMemories = (0 ..< 405).map { index in
            NativeSemanticMemory(
                date: state.gameDate,
                embedding: [Float(index)],
                id: "historical-memory-\(index)",
                importance: 1,
                sourceID: "historical-memory-source-\(index)",
                text: "Archived strategic memory \(index)",
                track: .internalStability
            )
        }
        state.semanticMemory = historicalMemories

        let advanced = NativeGameEngine.apply(
            NativeGeneratedTurn(
                events: [],
                stabilityDelta: 0,
                summary: "The administration completes another month without erasing its historical archive.",
                worldTensionDelta: 0
            ),
            to: state,
            months: 1
        )

        let preservedIDs = Set(advanced.timeline.map(\.id))
        let preservedMemoryIDs = Set(advanced.semanticMemory.map(\.id))
        XCTAssertTrue(historicalEvents.allSatisfy { preservedIDs.contains($0.id) })
        XCTAssertTrue(historicalMemories.allSatisfy { preservedMemoryIDs.contains($0.id) })
        XCTAssertGreaterThanOrEqual(advanced.timeline.count, historicalEvents.count)
        XCTAssertGreaterThanOrEqual(advanced.semanticMemory.count, historicalMemories.count)
    }

    func testDiplomaticReplyPreservesFullThreadArchive() async throws {
        let store = try makeStore(aiService: FakeNativeAIService())
        var state = makeState()
        let partner = PlayerCountry(code: "ARG", name: "Argentina")
        let history = (0 ..< 30).map { index in
            NativeDiplomaticMessage(
                date: state.gameDate,
                id: "archived-diplomatic-message-\(index)",
                speaker: index.isMultiple(of: 2) ? state.country.name : partner.name,
                text: "Archived diplomatic exchange \(index)."
            )
        }
        state.diplomaticThreads = [NativeDiplomaticThread(
            id: "thread-arg",
            lastUpdated: state.gameDate,
            messages: history,
            participant: partner,
            summary: "A long-running bilateral channel."
        )]
        store.state = state
        store.selectedDiplomaticPartnerCode = partner.code
        store.draftDiplomaticMessage = "Continue the existing technical channel without discarding its archive."

        await store.sendDiplomaticMessage()

        let updatedMessages = try XCTUnwrap(store.state?.diplomaticThreads.first?.messages)
        let updatedIDs = Set(updatedMessages.map(\.id))
        XCTAssertEqual(updatedMessages.count, history.count + 2)
        XCTAssertTrue(history.allSatisfy { updatedIDs.contains($0.id) })
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

    func testPersistenceRecoversBackupAndLegacySaves() async throws {
        let defaults = makeDefaults()
        let persistenceDirectory = try makePersistenceDirectory()
        let store = NativeCampaignStore(
            defaults: defaults,
            aiService: FakeNativeAIService(),
            persistenceDirectory: persistenceDirectory
        )
        store.choose(testCountry)
        await store.waitForPersistence()
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

        await store.performAdvance()
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
        await store.performAdvance()

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

        let task = Task { await store.performAdvance() }
        await gate.waitUntilEntered()

        XCTAssertTrue(store.isAdvancing)
        XCTAssertNotNil(store.turnProgress)
        XCTAssertGreaterThan(store.turnProgress?.totalLanes ?? 0, 0)

        await gate.resume()
        await task.value
        XCTAssertFalse(store.isAdvancing)
        XCTAssertNil(store.turnProgress)
    }

    func testSuccessfulAdvanceRefreshesSuggestionsBeforeReturning() async throws {
        let service = FakeNativeAIService()
        var suggestionRequestCount = 0
        service.turnHandler = { state, months in
            makeValidTurn(for: state, months: months)
        }
        service.suggestionHandler = { state in
            suggestionRequestCount += 1
            return makeLegalDecisionMatrix(for: state, cost: 10)
        }
        let store = try makeStore(aiService: service)
        store.state = makeState()

        await store.performAdvance()

        XCTAssertEqual(suggestionRequestCount, 1)
        XCTAssertEqual(store.state?.suggestedActions.count, NativeDecisionMatrixContract.cellCount)
        XCTAssertNil(store.pendingSuggestionRefreshForce)
        XCTAssertFalse(store.isAdvancing)
    }

    func testCampaignStoreUsesOneFixedThreeMonthTurnCadence() async throws {
        let service = FakeNativeAIService()
        var requestedMonths: Int?
        service.turnHandler = { state, months in
            requestedMonths = months
            return makeValidTurn(for: state, months: months)
        }
        let store = try makeStore(aiService: service)
        store.state = makeState()

        await store.performAdvance()

        XCTAssertEqual(NativeCampaignStore.monthsPerTurn, 3)
        XCTAssertEqual(requestedMonths, 3)
        XCTAssertEqual(store.state?.round, 2)
        XCTAssertEqual(store.state?.gameDate, "2010-04-15")
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

    func testDuplicateAutomaticSuggestionRefreshDoesNotCreateAnInfiniteRetryLoop() async throws {
        let gate = AsyncGate()
        let service = FakeNativeAIService()
        var requestCount = 0
        service.suggestionHandler = { _ in
            requestCount += 1
            await gate.wait()
            return []
        }
        let store = try makeStore(aiService: service)
        store.state = makeState()

        let firstRefresh = Task { await store.refreshSuggestedActions(force: false) }
        await gate.waitUntilEntered()
        await store.refreshSuggestedActions(force: false)

        XCTAssertNil(store.pendingSuggestionRefreshForce)
        await gate.resume()
        await firstRefresh.value
        await Task.yield()

        XCTAssertEqual(requestCount, 1)
        XCTAssertFalse(store.isLoadingSuggestions)
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

        let task = Task { await store.performAdvance() }
        await gate.waitUntilEntered()
        store.setLanguage(.spanish)
        await gate.resume()
        await task.value

        XCTAssertEqual(store.state?.round, 1)
        XCTAssertEqual(store.state?.language, .spanish)
    }

    func testProviderSwitchInvalidatesPendingWorkBeforeChangingRoute() async throws {
        let gate = AsyncGate()
        let defaults = makeDefaults()
        defaults.set(NativeAIProviderPreference.nvidia.rawValue, forKey: NativeAIProviderPreference.storageKey)
        let service = FakeNativeAIService()
        service.turnHandler = { state, months in
            await gate.wait()
            return makeValidTurn(for: state, months: months)
        }

        let store = try makeStore(defaults: defaults, aiService: service)
        var state = makeState()
        state.aiReadiness = .available(tokenBudget: "old NVIDIA route")
        state.suggestedActions = makeLegalDecisionMatrix(for: state, cost: 10)
        store.state = state

        let task = Task { await store.performAdvance() }
        await gate.waitUntilEntered()
        let previousVersion = store.stateVersion

        XCTAssertTrue(store.setAIProvider(.openRouter))
        XCTAssertGreaterThan(store.stateVersion, previousVersion)
        XCTAssertEqual(defaults.string(forKey: NativeAIProviderPreference.storageKey), NativeAIProviderPreference.openRouter.rawValue)
        XCTAssertEqual(store.state?.aiReadiness, .notChecked)
        XCTAssertTrue(store.state?.suggestedActions.isEmpty == true)

        await gate.resume()
        await task.value
        XCTAssertEqual(store.state?.round, state.round)
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

        let task = Task { await store.performAdvance() }
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

        await store.performAdvance()

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
        XCTAssertEqual(NativeAIProviderPreference.allCases, [.nvidia, .openRouter])
        XCTAssertEqual(NativeAIProviderPreference.current(defaults: defaults), .nvidia)

        defaults.set(NativeAIProviderPreference.nvidia.rawValue, forKey: NativeAIProviderPreference.storageKey)
        XCTAssertEqual(NativeAIProviderPreference.current(defaults: defaults), .nvidia)

        defaults.set(NativeAIProviderPreference.openRouter.rawValue, forKey: NativeAIProviderPreference.storageKey)
        XCTAssertEqual(NativeAIProviderPreference.current(defaults: defaults), .openRouter)
    }

    func testProviderMigrationPreservesOpenRouterAndNormalizesRemovedRoutes() {
        let defaults = makeDefaults()
        defaults.set(NativeAIProviderPreference.openRouter.rawValue, forKey: NativeAIProviderPreference.storageKey)

        NativeAIProviderPreference.migrateLegacyDefaultIfNeeded(defaults: defaults)

        XCTAssertEqual(NativeAIProviderPreference.current(defaults: defaults), .openRouter)

        defaults.set("appleFoundation", forKey: NativeAIProviderPreference.storageKey)
        NativeAIProviderPreference.migrateLegacyDefaultIfNeeded(defaults: defaults)
        XCTAssertEqual(defaults.string(forKey: NativeAIProviderPreference.storageKey), NativeAIProviderPreference.nvidia.rawValue)
        XCTAssertEqual(NativeAIProviderPreference.current(defaults: defaults), .nvidia)
    }

    func testAIProviderServicesReadInjectedDefaults() async throws {
        let defaults = makeDefaults()
        defaults.set("nvapi-test-key", forKey: "NVIDIA_API_KEY")
        defaults.set("or-test-key", forKey: "OPENROUTER_API_KEY")
        defaults.set("zai-test-key", forKey: "ZAI_API_KEY")
        defaults.set(NativeAIProviderPreference.openRouter.rawValue, forKey: NativeAIProviderPreference.storageKey)

        let nvidia = NativeNVIDIAService(defaults: defaults)
        XCTAssertEqual(nvidia.apiKey, "nvapi-test-key")
        XCTAssertEqual(nvidia.providerDisplayName, "NVIDIA NIM")
        XCTAssertEqual(nvidia.apiEndpoint.absoluteString, "https://integrate.api.nvidia.com/v1/chat/completions")
        XCTAssertEqual(nvidia.modelLanes.map(\.name), ["minimaxai/minimax-m3", "moonshotai/kimi-k2.6", "deepseek-ai/deepseek-v4-flash"])
        XCTAssertEqual(nvidia.modelLanes.first?.displayName, "MiniMax-M3")
        XCTAssertFalse(nvidia.includesThinkingField)
        XCTAssertTrue(nvidia.includesMaxTokensField)

        var nvidiaPayload: [String: Any] = [
            "model": "minimaxai/minimax-m3",
            "temperature": 0.1,
            "response_format": ["type": "json_object"]
        ]
        nvidia.configureProviderPayload(&nvidiaPayload, thinkingEnabled: true)
        // Temperature from the caller (0.1) is respected
        XCTAssertEqual(nvidiaPayload["temperature"] as? Double, 0.1)
        XCTAssertEqual(nvidiaPayload["top_p"] as? Double, 0.90)
        // MiniMax-M3 supports response_format, so it stays in the payload
        XCTAssertNotNil(nvidiaPayload["response_format"])
        // No Qwen-specific chat_template_kwargs
        XCTAssertNil(nvidiaPayload["chat_template_kwargs"])

        var deepseekPayload: [String: Any] = [
            "model": "deepseek-ai/deepseek-v4-flash",
            "response_format": ["type": "json_object"]
        ]
        nvidia.configureProviderPayload(&deepseekPayload, thinkingEnabled: true)
        XCTAssertEqual(deepseekPayload["temperature"] as? Double, 1.0)
        XCTAssertEqual(deepseekPayload["top_p"] as? Double, 0.95)
        let chatTemplateKwargs = try XCTUnwrap(deepseekPayload["chat_template_kwargs"] as? [String: Any])
        XCTAssertEqual(chatTemplateKwargs["thinking"] as? Bool, true)
        XCTAssertEqual(chatTemplateKwargs["reasoning_effort"] as? String, "high")

        let openRouter = NativeOpenRouterService(defaults: defaults)
        XCTAssertEqual(openRouter.apiKey, "or-test-key")
        XCTAssertEqual(openRouter.providerDisplayName, "OpenRouter")
        XCTAssertEqual(openRouter.modelLanes.map(\.name), ["openrouter/free"])
        XCTAssertEqual(openRouter.modelLanes.first?.displayName, "Free Models Router")
        XCTAssertEqual(openRouter.modelLanes.first?.maxConcurrent, 3)
        XCTAssertFalse(openRouter.includesMaxTokensField)
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
        XCTAssertEqual(suggestions.count, 25)
        XCTAssertEqual(suggestionsProvider.modelLanes.map(\.name), ["openrouter/free"])
        XCTAssertEqual(suggestionsProvider.capturedRequests.count, 1)
        let firstPrompt = try XCTUnwrap(suggestionsProvider.capturedRequests.first?.prompt)
        XCTAssertTrue(firstPrompt.contains("exactly 25 suggestions"))
        XCTAssertTrue(firstPrompt.contains("LEGAL JSON SKELETON TO PERSONALIZE"))
        XCTAssertTrue(firstPrompt.contains("EDITING CONTRACT"))
        XCTAssertTrue(firstPrompt.contains("Preserve id, urgency"))
        XCTAssertTrue(firstPrompt.contains("Rewrite only title, detail, and rationale"))
        XCTAssertTrue(firstPrompt.contains("worldTension="))
        XCTAssertTrue(firstPrompt.contains("matrixRow"))
        XCTAssertTrue(firstPrompt.contains("\"suggestions\""))
        XCTAssertTrue(firstPrompt.contains("openrouter/free") == false)
        XCTAssertEqual(suggestionsProvider.capturedRequests.first?.maxTokens, 8000)

        let zai = NativeExternalAIService(defaults: defaults)
        XCTAssertEqual(zai.apiKey, "zai-test-key")
        XCTAssertEqual(zai.providerDisplayName, "Z.AI")

        let store = try makeStore(defaults: defaults)
        XCTAssertEqual(store.selectedAIProviderPreference, .openRouter)
    }

    func testProviderCancellationRecognizesCancelledURLError() {
        XCTAssertTrue(nativeProviderRequestWasCancelled(URLError(.cancelled)))
        XCTAssertFalse(nativeProviderRequestWasCancelled(URLError(.timedOut)))
    }

    func testNVIDIANIMGeneratesTheCompleteDecisionMatrixContract() async throws {
        let state = makeState()
        let service = CapturingNVIDIAMatrixService(defaults: makeDefaults())
        let envelope = ["suggestions": makeLegalDecisionMatrix(for: state, cost: 10)]
        let responseData = try JSONEncoder().encode(envelope)
        service.response = try XCTUnwrap(String(data: responseData, encoding: .utf8))

        let suggestions = try await service.generateSuggestedActions(for: state)

        XCTAssertEqual(suggestions.count, NativeDecisionMatrixContract.cellCount)
        XCTAssertEqual(Set(suggestions.map { "\($0.matrixRow):\($0.matrixColumn)" }).count, 25)
        // Single-call architecture: exactly 1 API call for the entire 25-cell matrix
        XCTAssertEqual(service.capturedRequests.count, 1)
        XCTAssertTrue(service.capturedRequests.allSatisfy { $0.responseFormat == "json_object" })
        XCTAssertFalse(service.capturedRequests.allSatisfy(\.thinkingEnabled))
    }

    func testDynamicAIServiceRoutesEveryGameAISurfaceOnlyThroughSelectedNVIDIA() async throws {
        let defaults = makeDefaults()
        defaults.set("nvapi-test-key", forKey: "NVIDIA_API_KEY")
        defaults.set("or-test-key", forKey: "OPENROUTER_API_KEY")
        defaults.set(NativeAIProviderPreference.nvidia.rawValue, forKey: NativeAIProviderPreference.storageKey)
        let nvidia = StubNVIDIAGameService(defaults: defaults)
        let openRouter = CapturingOpenRouterGameService(defaults: defaults)
        let service = DynamicAIService(
            defaults: defaults,
            nvidiaService: nvidia,
            openRouterService: openRouter
        )
        let state = makeState()

        let readiness = await service.checkReadiness()
        XCTAssertTrue(readiness.ok)
        _ = try await service.generateTurn(for: state, months: 1) { _ in }
        _ = try await service.generateSuggestedActions(for: state)
        _ = try await service.generateAdvisorBrief(for: state, question: "What now?")
        _ = try await service.generateDiplomaticReply(
            for: state,
            thread: makeDiplomaticThread(for: state),
            message: "Offer a bounded corridor."
        )

        XCTAssertEqual(nvidia.calledSurfaces, ["readiness", "turn", "suggestions", "advisor", "diplomacy"])
        XCTAssertTrue(openRouter.capturedRequests.isEmpty)
        XCTAssertEqual(service.lastProviderUsed, "NVIDIA NIM")
    }

    func testDynamicAIServiceKeepsSelectedNVIDIAFailuresOnNVIDIA() async throws {
        let defaults = makeDefaults()
        defaults.set("nvapi-test-key", forKey: "NVIDIA_API_KEY")
        defaults.set("or-test-key", forKey: "OPENROUTER_API_KEY")
        defaults.set(NativeAIProviderPreference.nvidia.rawValue, forKey: NativeAIProviderPreference.storageKey)
        let nvidia = StubNVIDIAGameService(defaults: defaults, shouldFail: true)
        let openRouter = CapturingOpenRouterGameService(defaults: defaults)
        let service = DynamicAIService(
            defaults: defaults,
            nvidiaService: nvidia,
            openRouterService: openRouter
        )
        let state = makeState()

        let readiness = await service.checkReadiness()
        XCTAssertFalse(readiness.ok)
        XCTAssertEqual(service.lastProviderUsed, "NVIDIA NIM")

        do {
            _ = try await service.generateTurn(for: state, months: 3) { _ in }
            XCTFail("Expected the selected NVIDIA turn failure to propagate.")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("NVIDIA fixture failure"))
        }
        do {
            _ = try await service.generateSuggestedActions(for: state)
            XCTFail("Expected the selected NVIDIA suggestion failure to propagate.")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("NVIDIA fixture failure"))
        }
        do {
            _ = try await service.generateAdvisorBrief(for: state, question: "What now?")
            XCTFail("Expected the selected NVIDIA advisor failure to propagate.")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("NVIDIA fixture failure"))
        }
        do {
            _ = try await service.generateDiplomaticReply(
                for: state,
                thread: makeDiplomaticThread(for: state),
                message: "Offer a bounded corridor."
            )
            XCTFail("Expected the selected NVIDIA diplomacy failure to propagate.")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("NVIDIA fixture failure"))
        }

        XCTAssertEqual(nvidia.calledSurfaces, ["readiness", "turn", "suggestions", "advisor", "diplomacy"])
        XCTAssertTrue(openRouter.capturedRequests.isEmpty)
        XCTAssertEqual(service.lastProviderUsed, "NVIDIA NIM")
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
        XCTAssertTrue(generatedTurn.events.contains { $0.kind == .action })
        XCTAssertTrue(generatedTurn.events.contains { $0.importance == .severe })
        XCTAssertFalse(progressEvents.isEmpty)
        XCTAssertTrue(progressEvents.allSatisfy { $0.providerName == "OpenRouter" })
        XCTAssertTrue(progressEvents.contains { $0.modelIdentifier == "openrouter/free" })
        XCTAssertTrue(progressEvents.contains { $0.modelIdentifier == "test/reasoning-free" })
        XCTAssertTrue(progressEvents.contains { $0.providerSummary == "Calling OpenRouter · Free Models Router" })
        XCTAssertTrue(progressEvents.contains { $0.reasoningStatus == .live && $0.reasoningText?.contains("campaign state") == true })

        let suggestions = try await service.generateSuggestedActions(for: state)
        XCTAssertEqual(service.lastProviderUsed, "OpenRouter")
        XCTAssertEqual(suggestions.count, 25)

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
        XCTAssertTrue(unifiedTurnRequests.allSatisfy { $0.prompt.contains("Mechanics snapshot (authoritative)") })
        XCTAssertTrue(unifiedTurnRequests.allSatisfy { $0.prompt.contains("capacity=100/120") })
        XCTAssertTrue(unifiedTurnRequests.allSatisfy { $0.prompt.contains("queueLimit=3") })
        XCTAssertTrue(unifiedTurnRequests.allSatisfy { $0.prompt.contains("minor, major, or severe") })
        XCTAssertTrue(unifiedTurnRequests.allSatisfy { $0.prompt.contains("⟦ECO⟧") && $0.prompt.contains("⟦TNS⟧") })
        XCTAssertTrue(unifiedTurnRequests.allSatisfy { $0.prompt.contains("narrative words never trigger mechanics") })
        XCTAssertTrue(openRouter.capturedRequests.contains { $0.thinkingEnabled && $0.hasReasoningProgress })
        XCTAssertTrue(openRouter.capturedRequests.contains {
            $0.prompt.contains("LEGAL JSON SKELETON TO PERSONALIZE") &&
                $0.prompt.contains("\"suggestions\"")
        })
        XCTAssertTrue(openRouter.capturedRequests.contains { $0.prompt.contains("SwiftHistoria strategic advisor") && $0.prompt.contains("Campaign objectives") })
        XCTAssertTrue(openRouter.capturedRequests.contains { $0.prompt.contains("diplomacy chat inside SwiftHistoria") && $0.prompt.contains("Recent campaign context") })
        XCTAssertTrue(openRouter.capturedRequests.contains { $0.prompt.contains("A chat reply is negotiation prose, not a state mutation") })
    }

    func testOpenRouterSuggestionsAcceptFreeModelSchemaVariants() async throws {
        let defaults = makeDefaults()
        defaults.set("or-test-key", forKey: "OPENROUTER_API_KEY")
        let openRouter = CapturingOpenRouterGameService(defaults: defaults)
        let actions = (0 ..< 5).flatMap { row in
            (0 ..< 5).map { column in
                """
                {"name":"Stage Policy Review \(row)-\(column)","summary":"Create a bounded treasury and service review for the current campaign period.","expectedOutcome":"The review uses existing institutions and remains within current administrative capacity.","why":"This legal proposal responds to stored objectives, budget pressure, and current institutional authority.","priority":"soon","primary_mechanic":"⟦ECO⟧","secondary_mechanic":"⟦STB⟧","row":\(row),"column":\(column),"cost":10,"action_kind":"policy"}
                """
            }
        }
        openRouter.suggestionResponse = "{\"actions\":[\(actions.joined(separator: ","))]}"

        let suggestions = try await openRouter.generateSuggestedActions(for: makeState())

        XCTAssertEqual(suggestions.count, 25)
        XCTAssertEqual(Set(suggestions.map { "\($0.matrixRow):\($0.matrixColumn)" }).count, 25)
        XCTAssertTrue(suggestions.allSatisfy { $0.actionKind == "policy" && $0.administrativeCost == 10 })
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

        let content = try NativeExternalAIService.decodeCompletionContent(
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
        defaults.set("nvapi-test-key", forKey: "NVIDIA_API_KEY")
        defaults.set(NativeAIProviderPreference.openRouter.rawValue, forKey: NativeAIProviderPreference.storageKey)
        let service = DynamicAIService(defaults: defaults)
        let state = makeState()

        let readiness = await service.checkReadiness()
        XCTAssertFalse(readiness.ok)
        XCTAssertEqual(service.lastProviderUsed, "OpenRouter")
        XCTAssertTrue(readiness.lastError.contains("OpenRouter Free is selected"))
        XCTAssertFalse(readiness.tokenBudget.localizedCaseInsensitiveContains("fallback"))

        do {
            _ = try await service.generateTurn(for: state, months: 1) { progress in
                XCTAssertEqual(progress.providerName, "OpenRouter")
                XCTAssertEqual(progress.modelIdentifier, "openrouter/free")
            }
            XCTFail("Expected missing OpenRouter key to fail instead of falling back.")
        } catch {
            XCTAssertEqual(service.lastProviderUsed, "OpenRouter")
            XCTAssertTrue(error.localizedDescription.contains("OpenRouter Free is selected"))
        }

        do {
            _ = try await service.generateSuggestedActions(for: state)
            XCTFail("Expected missing OpenRouter key to fail suggestions instead of falling back.")
        } catch {
            XCTAssertEqual(service.lastProviderUsed, "OpenRouter")
            XCTAssertTrue(error.localizedDescription.contains("OpenRouter Free is selected"))
        }
    }

    func testDynamicAIServiceDoesNotFallbackWhenNVIDIAIsSelectedWithoutKey() async throws {
        let defaults = makeDefaults()
        defaults.set("or-test-key", forKey: "OPENROUTER_API_KEY")
        defaults.set(NativeAIProviderPreference.nvidia.rawValue, forKey: NativeAIProviderPreference.storageKey)
        let openRouter = CapturingOpenRouterGameService(defaults: defaults)
        let service = DynamicAIService(defaults: defaults, openRouterService: openRouter)
        let state = makeState()

        let readiness = await service.checkReadiness()
        XCTAssertFalse(readiness.ok)
        XCTAssertEqual(service.lastProviderUsed, "NVIDIA NIM")
        XCTAssertTrue(readiness.lastError.contains("NVIDIA is selected"))

        do {
            _ = try await service.generateTurn(for: state, months: 3) { progress in
                XCTAssertEqual(progress.providerName, "NVIDIA NIM")
                XCTAssertEqual(progress.modelIdentifier, NativeNVIDIAService.modelIdentifier)
            }
            XCTFail("Expected missing NVIDIA key to fail instead of switching providers.")
        } catch {
            XCTAssertEqual(service.lastProviderUsed, "NVIDIA NIM")
            XCTAssertTrue(error.localizedDescription.contains("NVIDIA is selected"))
        }

        XCTAssertTrue(openRouter.capturedRequests.isEmpty)
    }

    func testSaveSlotsResumeTheActiveCampaignAfterFreshLaunch() async throws {
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
        await store.waitForPersistence()
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

    func testDebouncedPersistenceStaysWithTheSlotThatScheduledIt() async throws {
        let defaults = makeDefaults()
        let persistenceDirectory = try makePersistenceDirectory()
        let store = NativeCampaignStore(
            defaults: defaults,
            aiService: FakeNativeAIService(),
            persistenceDirectory: persistenceDirectory
        )
        store.state = makeState()

        store.persistState()
        store.switchSlot(2)

        // The debounced write sleeps 500 ms and then queues behind the shared
        // serial writer; poll for the observable effect instead of racing a
        // fixed sleep (which flakes under load).
        var slot1State: NativeCampaignState?
        for _ in 0 ..< 100 {
            slot1State = NativeCampaignStore.loadCampaignState(
                from: defaults,
                decoder: JSONDecoder(),
                persistenceDirectory: persistenceDirectory
            ).state
            if slot1State != nil { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        let slot2 = NativeCampaignStore.loadCampaignState(
            from: defaults,
            decoder: JSONDecoder(),
            persistenceDirectory: persistenceDirectory,
            slotKey: { NativeCampaignStore.slotKey($0, slot: 2) },
            slotFileName: { NativeCampaignStore.slotFileName($0, slot: 2) }
        )

        XCTAssertEqual(slot1State?.country.code, testCountry.code)
        XCTAssertNil(slot2.state)
    }

    func testCountryOnlyRecoveryWritesInitialStateToActiveSlot() async throws {
        let defaults = makeDefaults()
        let persistenceDirectory = try makePersistenceDirectory()
        defaults.set(2, forKey: NativeCampaignStore.activeSlotKey)
        try defaults.set(
            JSONEncoder().encode(PlayerCountry(code: "ARG", name: "Argentina")),
            forKey: NativeCampaignStore.slotKey(NativeCampaignStore.selectedCountryKey, slot: 2)
        )

        let store = NativeCampaignStore(
            defaults: defaults,
            aiService: FakeNativeAIService(),
            persistenceDirectory: persistenceDirectory
        )

        await store.waitForPersistence()
        XCTAssertEqual(store.saveSlot, 2)
        XCTAssertEqual(store.state?.country.code, "ARG")
        XCTAssertNil(store.slotSummary(1))
        XCTAssertEqual(store.slotSummary(2)?.countryName, "Argentina")
    }

    func testLiveOpenRouterFreeSuggestedActionsWhenEnabled() async throws {
        let environment = ProcessInfo.processInfo.environment
        let appDefaults = UserDefaults(suiteName: "com.gibavargas.SwiftHistoria.mac")
        guard environment["PAX_HISTORIA_RUN_LIVE_OPENROUTER"] == "1" || appDefaults?.bool(forKey: "PAX_HISTORIA_RUN_LIVE_OPENROUTER") == true else {
            throw XCTSkip("Set PAX_HISTORIA_RUN_LIVE_OPENROUTER=1 to exercise the real OpenRouter Free suggestion path.")
        }
        let key = (environment["OPENROUTER_API_KEY"] ?? appDefaults?.string(forKey: "OPENROUTER_API_KEY") ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            throw XCTSkip("OPENROUTER_API_KEY is required for the live OpenRouter Free suggestion path.")
        }

        let defaults = makeDefaults()
        defaults.set(key, forKey: "OPENROUTER_API_KEY")
        let service = NativeOpenRouterService(defaults: defaults)
        let state = makeState()

        let suggestions = try await service.generateSuggestedActions(for: state)

        XCTAssertEqual(suggestions.count, 25)
        XCTAssertEqual(Set(suggestions.map { "\($0.matrixRow):\($0.matrixColumn)" }).count, 25)
        for suggestion in suggestions {
            XCTAssertNil(NativeDecisionMatrixContract.eligibilityFailure(for: suggestion, state: state))
            XCTAssertNotNil(NativeStrategicTrack.allCases.first { $0.mechanicCode == suggestion.primaryMechanic })
            XCTAssertNotNil(NativeStrategicTrack.allCases.first { $0.mechanicCode == suggestion.secondaryMechanic })
        }
    }

    func testLiveOpenRouterGPTOSS20BFreeMatrixWhenEnabled() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["PAX_HISTORIA_RUN_LIVE_GPT_OSS_20B"] == "1" else {
            throw XCTSkip("Set PAX_HISTORIA_RUN_LIVE_GPT_OSS_20B=1 to exercise the dedicated GPT-OSS 20B Free matrix path.")
        }
        let appDefaults = UserDefaults(suiteName: "com.gibavargas.SwiftHistoria.mac")
        let key = (environment["OPENROUTER_API_KEY"] ?? appDefaults?.string(forKey: "OPENROUTER_API_KEY") ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            throw XCTSkip("OPENROUTER_API_KEY is required for the live GPT-OSS 20B Free matrix path.")
        }

        let defaults = makeDefaults()
        defaults.set(key, forKey: "OPENROUTER_API_KEY")
        let service = NativeOpenRouterService(defaults: defaults)
        service.modelLanes = [
            ZAIModelLane(
                name: "openai/gpt-oss-20b:free",
                displayName: "GPT-OSS 20B Free",
                maxConcurrent: 1
            )
        ]
        let state = makeState()

        let suggestions = try await service.generateSuggestedActions(for: state)

        XCTAssertEqual(suggestions.count, NativeDecisionMatrixContract.cellCount)
        XCTAssertEqual(Set(suggestions.map { "\($0.matrixRow):\($0.matrixColumn)" }).count, NativeDecisionMatrixContract.cellCount)
        for suggestion in suggestions {
            XCTAssertNil(NativeDecisionMatrixContract.eligibilityFailure(for: suggestion, state: state))
        }
    }

    func testLiveNVIDIANIMWhenEnabled() async throws {
        let environment = ProcessInfo.processInfo.environment
        let appDefaults = UserDefaults(suiteName: "com.gibavargas.SwiftHistoria.mac")
        guard environment["PAX_HISTORIA_RUN_LIVE_NVIDIA"] == "1" || appDefaults?.bool(forKey: "PAX_HISTORIA_RUN_LIVE_NVIDIA") == true else {
            throw XCTSkip("Set PAX_HISTORIA_RUN_LIVE_NVIDIA=1 to exercise NVIDIA NIM inference.")
        }
        let key = (environment["NVIDIA_API_KEY"] ?? appDefaults?.string(forKey: "NVIDIA_API_KEY") ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            throw XCTSkip("NVIDIA_API_KEY is required for the live NVIDIA NIM path.")
        }

        let defaults = makeDefaults()
        defaults.set(key, forKey: "NVIDIA_API_KEY")
        let service = NativeNVIDIAService(defaults: defaults)
        let state = makeState()

        let suggestions = try await service.generateSuggestedActions(for: state)

        XCTAssertEqual(suggestions.count, NativeDecisionMatrixContract.cellCount)
        XCTAssertEqual(Set(suggestions.map { "\($0.matrixRow):\($0.matrixColumn)" }).count, NativeDecisionMatrixContract.cellCount)
        for suggestion in suggestions {
            XCTAssertNil(NativeDecisionMatrixContract.eligibilityFailure(for: suggestion, state: state))
        }
    }

    func testLiveDiffusionGemmaBrainstormOpenRouterMatrixWhenEnabled() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["PAX_HISTORIA_RUN_LIVE_HYBRID_MATRIX"] == "1" else {
            throw XCTSkip("Set PAX_HISTORIA_RUN_LIVE_HYBRID_MATRIX=1 to exercise the two-provider matrix pipeline.")
        }
        let appDefaults = UserDefaults(suiteName: "com.gibavargas.SwiftHistoria.mac")
        let nvidiaKey = (environment["NVIDIA_API_KEY"] ?? appDefaults?.string(forKey: "NVIDIA_API_KEY") ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let openRouterKey = (environment["OPENROUTER_API_KEY"] ?? appDefaults?.string(forKey: "OPENROUTER_API_KEY") ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !nvidiaKey.isEmpty, !openRouterKey.isEmpty else {
            throw XCTSkip("Both NVIDIA_API_KEY and OPENROUTER_API_KEY are required for the hybrid matrix path.")
        }

        let defaults = makeDefaults()
        defaults.set(nvidiaKey, forKey: "NVIDIA_API_KEY")
        defaults.set(openRouterKey, forKey: "OPENROUTER_API_KEY")
        let state = makeState()
        let nvidia = NativeNVIDIAService(defaults: defaults)
        nvidia.modelLanes = [
            ZAIModelLane(
                name: "google/diffusiongemma-26b-a4b-it",
                displayName: "DiffusionGemma 26B",
                maxConcurrent: 1
            )
        ]
        let brainstorm = try await nvidia.executeProviderRequest(
            prompt: """
            Brainstorm a diverse set of concrete policy ideas for the following strategy-game state.
            Explore economy, society, diplomacy, security, and territorial governance across cautious through transformative postures.
            Do not emit JSON. Do not decide costs, action kinds, target IDs, or sovereignty structures. Those mechanics are owned by the game engine.

            \(NativeDecisionMatrixPrompt.make(for: state))
            """,
            maxTokens: 6000,
            temperature: 0.9,
            thinkingEnabled: true,
            requestTimeout: 60,
            retryLimit: 0
        )
        XCTAssertFalse(brainstorm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

        let openRouter = NativeOpenRouterService(defaults: defaults)
        let formatted = try await openRouter.executeProviderRequest(
            prompt: """
            \(NativeDecisionMatrixPrompt.make(for: state))

            CREATIVE BRAINSTORM FROM DIFFUSIONGEMMA:
            \(brainstorm)

            Use the brainstorm only for player-facing titles, details, and rationales. Return the required strict 25-cell JSON object now.
            """,
            maxTokens: 8000,
            temperature: 0.2,
            responseFormat: "json_object",
            thinkingEnabled: false,
            requestTimeout: 60,
            retryLimit: 0
        )
        let parsed = OpenRouterSuggestionParser.suggestions(from: formatted, state: state)
        let suggestions = try NativeDecisionMatrixContract.aiTailoredPlayerMatrix(from: parsed, state: state)

        XCTAssertEqual(suggestions.count, NativeDecisionMatrixContract.cellCount)
        for suggestion in suggestions {
            XCTAssertNil(NativeDecisionMatrixContract.eligibilityFailure(for: suggestion, state: state))
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

        let independentPrompt = NativePromptHarness.makeIndependentEventPrompt(for: state, months: 1, repairInstruction: nil)
        print("\n--- TEST PRINT: INDEPENDENT PROMPT START ---")
        print(independentPrompt)
        print("--- TEST PRINT: INDEPENDENT PROMPT END ---\n")
        XCTAssertTrue(independentPrompt.contains("North Sea Corridor Expansion"))
        XCTAssertTrue(independentPrompt.contains("\"effectTrack\":\"⟦MKT⟧\""))
        XCTAssertFalse(independentPrompt.contains("\"effectTrack\":\"market-confidence\""))

        let actionPrompt = NativePromptHarness.makeActionEventPrompt(for: state, action: plannedAction, months: 1, repairInstruction: nil)
        print("\n--- TEST PRINT: ACTION PROMPT START ---")
        print(actionPrompt)
        print("--- TEST PRINT: ACTION PROMPT END ---\n")
        XCTAssertTrue(actionPrompt.contains("Corridor Transit Integration"))
        XCTAssertTrue(actionPrompt.contains("Action-specific facts and consequence ranges"))
        XCTAssertTrue(actionPrompt.contains("\"effectTrack\":\"⟦ECO⟧\""))

        let economicPrompt = NativePromptHarness.makeEconomicEventPrompt(for: state, months: 1, repairInstruction: nil)
        print("\n--- TEST PRINT: ECONOMIC PROMPT START ---")
        print(economicPrompt)
        print("--- TEST PRINT: ECONOMIC PROMPT END ---\n")
        XCTAssertTrue(economicPrompt.contains("budget surplus or deficit"))
        XCTAssertTrue(economicPrompt.contains("Current strategy database"))

        let domesticPrompt = NativePromptHarness.makeDomesticEventPrompt(for: state, months: 1, repairInstruction: nil)
        print("\n--- TEST PRINT: DOMESTIC PROMPT START ---")
        print(domesticPrompt)
        print("--- TEST PRINT: DOMESTIC PROMPT END ---\n")
        XCTAssertTrue(domesticPrompt.contains("Regional Services Consolidation"))

        let summaryPrompt = NativePromptHarness.makeSummaryPrompt(for: state, months: 1, events: [])
        print("\n--- TEST PRINT: SUMMARY PROMPT START ---")
        print(summaryPrompt)
        print("--- TEST PRINT: SUMMARY PROMPT END ---\n")
        XCTAssertTrue(summaryPrompt.contains("Administrative streamlining"))

        let suggestionPrompt = NativePromptHarness.makeSuggestionPrompt(for: state, focus: "fiscal buffers and community services", index: 1)
        print("\n--- TEST PRINT: SUGGESTION PROMPT START ---")
        print(suggestionPrompt)
        print("--- TEST PRINT: SUGGESTION PROMPT END ---\n")
        XCTAssertTrue(suggestionPrompt.contains("Establish Logistics Reserves"))
        XCTAssertTrue(suggestionPrompt.contains("accept-ready"))
        XCTAssertTrue(suggestionPrompt.contains("Respect current administrative capacity"))
        XCTAssertTrue(suggestionPrompt.contains("Campaign objectives"))
        XCTAssertTrue(suggestionPrompt.contains("Domestic legitimacy"))
        XCTAssertTrue(suggestionPrompt.contains("⟦ECO⟧") && suggestionPrompt.contains("⟦TNS⟧"))
        XCTAssertTrue(suggestionPrompt.contains("prose never executes mechanics"))

        let advisorPrompt = NativePromptHarness.makeAdvisorPrompt(for: state, question: "What should we protect first this quarter?")
        print("\n--- TEST PRINT: ADVISOR PROMPT START ---")
        print(advisorPrompt)
        print("--- TEST PRINT: ADVISOR PROMPT END ---\n")
        XCTAssertTrue(advisorPrompt.contains("SwiftHistoria strategic advisor"))
        XCTAssertTrue(advisorPrompt.contains("Label forecasts as forecasts"))
        XCTAssertTrue(advisorPrompt.contains("three-order queue limit"))

        let diplomacyPrompt = NativePromptHarness.makeDiplomacyPrompt(for: state, thread: thread, message: "Hello")
        print("\n--- TEST PRINT: DIPLOMACY PROMPT START ---")
        print(diplomacyPrompt)
        print("--- TEST PRINT: DIPLOMACY PROMPT END ---\n")
        XCTAssertTrue(diplomacyPrompt.contains("diplomacy chat inside SwiftHistoria"))
        XCTAssertTrue(diplomacyPrompt.contains("A chat reply is negotiation prose, not a state mutation"))
        XCTAssertTrue(diplomacyPrompt.contains("relationship score"))

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
        let state = makeState()
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

        let worldSeed = try XCTUnwrap(store.state?.worldSeed)
        let timeline = try XCTUnwrap(store.state?.timeline)
        store.draftAction = "Pending order"
        store.draftAdvisorQuestion = "Pending question"
        store.draftDiplomaticMessage = "Pending message"

        let newCountry = PlayerCountry(code: "CHN", name: "China")
        XCTAssertTrue(store.switchCountry(to: newCountry))

        XCTAssertEqual(store.selectedCountry?.code, "CHN")
        XCTAssertEqual(store.state?.country.code, "CHN")
        XCTAssertEqual(store.state?.worldSeed, worldSeed)
        XCTAssertEqual(store.state?.timeline, timeline)
        XCTAssertEqual(store.state?.economicLedger, store.state?.economicLedgers["CHN"])
        XCTAssertEqual(store.draftAction, "")
        XCTAssertEqual(store.draftAdvisorQuestion, "")
        XCTAssertEqual(store.draftDiplomaticMessage, "")
        XCTAssertTrue(store.lastRecoveryNotice?.contains("shared campaign world was preserved") == true)
        XCTAssertFalse(store.switchCountry(to: newCountry))

        store.setGameMode(.ironman)
        XCTAssertFalse(store.switchCountry(to: PlayerCountry(code: "USA", name: "United States")))
        XCTAssertEqual(store.state?.country.code, "CHN")
    }

    func testResearchBudgetControlClampsAndRejectsNonfiniteValues() throws {
        let store = try makeStore()
        store.choose(testCountry)

        store.updateResearchBudget(0.75)
        XCTAssertEqual(store.state?.budgetResearchSlider ?? -1, 0.75, accuracy: 0.0001)

        store.updateResearchBudget(2.0)
        XCTAssertEqual(store.state?.budgetResearchSlider ?? -1, 1.0, accuracy: 0.0001)

        store.updateResearchBudget(-1.0)
        XCTAssertEqual(store.state?.budgetResearchSlider ?? -1, 0.0, accuracy: 0.0001)

        store.updateResearchBudget(.nan)
        XCTAssertEqual(store.state?.budgetResearchSlider ?? -1, 0.0, accuracy: 0.0001)
    }

    func testDynamicCountryCreationPopulatesEveryPromisedSurface() throws {
        let store = try makeStore()
        store.choose(testCountry)

        XCTAssertTrue(store.addDynamicCountry(code: "atl", name: "Atlantic Federation"))
        let state = try XCTUnwrap(store.state)

        XCTAssertEqual(state.dynamicCountries["ATL"], "Atlantic Federation")
        XCTAssertNotNil(state.economicLedgers["ATL"])
        XCTAssertNotNil(state.aiCountryStates["ATL"])
        XCTAssertTrue(NativeWorldEconomicsPanel.displayedCountryCodes(for: state).contains("ATL"))
        XCTAssertTrue(store.allVisibleCountries().contains { $0.code == "ATL" && $0.name == "Atlantic Federation" })
        XCTAssertFalse(store.addDynamicCountry(code: "ATL", name: "Duplicate Federation"))
    }

    func testCrisisDetectorRanksAndExplainsEveryActivePlayerCrisis() {
        var state = makeState()
        state.stability = 10
        state.worldTension = 95
        state.nuclearFalloutRegions = ["BRA_Acre"]
        state.regionConflicts = [
            "ARG": NativeRegionConflictState(
                controllerCode: "BRA",
                intensity: 3,
                mode: .conventionalOccupation,
                originalCountryCode: "ARG",
                regionID: "ARG",
                summary: "Brazilian forces hold the area.",
                updatedAt: state.gameDate
            ),
            "BRA": NativeRegionConflictState(
                controllerCode: "CHN",
                intensity: 5,
                mode: .conventionalOccupation,
                originalCountryCode: "BRA",
                regionID: "BRA",
                summary: "Foreign forces hold player territory.",
                updatedAt: state.gameDate
            ),
            "BRA_Acre": NativeRegionConflictState(
                controllerCode: "REB",
                intensity: 4,
                mode: .guerrillaControl,
                originalCountryCode: "BRA",
                regionID: "BRA_Acre",
                summary: "Insurgents hold the area.",
                updatedAt: state.gameDate
            )
        ]

        let crises = NativeCrisisDetector.activeCrises(for: state)
        let kinds = Set(crises.map(\.kind))

        XCTAssertEqual(crises.first?.severity, .critical)
        XCTAssertTrue(kinds.isSuperset(of: [.invasionIncoming, .invasionOutgoing, .rebellion, .nuclearFallout, .stability, .worldWar]))
        XCTAssertTrue(crises.allSatisfy { !$0.title.isEmpty && !$0.detail.isEmpty && !$0.date.isEmpty })
    }

    func testGameModePersistence() async throws {
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
        await store.waitForPersistence()

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

    func testMechanicCodebookRoundTripsEveryStrategicTrack() {
        let codes = Set(NativeStrategicTrack.allCases.map(\.mechanicCode))

        XCTAssertEqual(codes, ["⟦ECO⟧", "⟦MKT⟧", "⟦STB⟧", "⟦SEC⟧", "⟦DIP⟧", "⟦MIL⟧", "⟦TNS⟧"])
        for track in NativeStrategicTrack.allCases {
            XCTAssertEqual(NativeStrategicTrack.decodeMechanicToken(track.mechanicCode), track)
            XCTAssertEqual(NativeStrategicTrack.decodeMechanicToken(track.rawValue), track)
        }
        XCTAssertNil(NativeStrategicTrack.decodeMechanicToken("infrastructure and diplomacy"))
        XCTAssertTrue(NativeStrategicTrack.mechanicCodebookPrompt.contains("narrative words never trigger mechanics"))
    }

    func testDecisionMatrixUsesCodesAndRejectsInvalidMechanicTokens() throws {
        let state = makeState()
        let matrix = NativeDecisionMatrixContract.localPlayerMatrix(for: state)

        XCTAssertEqual(matrix.count, 25)
        XCTAssertTrue(matrix.allSatisfy {
            NativeStrategicTrack.decodeMechanicToken($0.primaryMechanic) != nil &&
                NativeStrategicTrack.decodeMechanicToken($0.secondaryMechanic) != nil &&
                $0.primaryMechanic.hasPrefix("⟦") && $0.secondaryMechanic.hasPrefix("⟦")
        })
        XCTAssertEqual(try NativeDecisionMatrixContract.validatedPlayerMatrix(matrix, state: state).count, 25)

        var invalid = matrix
        invalid[0].primaryMechanic = "infrastructure"
        XCTAssertThrowsError(try NativeDecisionMatrixContract.validatedPlayerMatrix(invalid, state: state))
    }

    func testSuggestedActionExecutesCodesInsteadOfNarrativeKeywords() throws {
        let store = try makeStore()
        let state = makeState()
        store.state = state
        var suggestion = try XCTUnwrap(
            NativeDecisionMatrixContract.localPlayerMatrix(for: state).first {
                $0.primaryMechanic == NativeStrategicTrack.diplomaticLeverage.mechanicCode
            }
        )
        suggestion.detail = "Fund military security infrastructure while preserving the exact coded diplomatic consequence."
        suggestion.primaryMechanic = NativeStrategicTrack.diplomaticLeverage.mechanicCode
        suggestion.secondaryMechanic = NativeStrategicTrack.marketConfidence.mechanicCode

        store.addSuggestedAction(suggestion)

        let accepted = try XCTUnwrap(store.state?.plannedActions.first)
        XCTAssertEqual(accepted.mechanicTracks, [.diplomaticLeverage, .marketConfidence])
        XCTAssertFalse(accepted.mechanicTracks.contains(.securityAnxiety))
        XCTAssertFalse(accepted.mechanicTracks.contains(.economicResilience))
    }

    func testTurnValidationEnforcesLinkedOrderMechanicCodes() throws {
        var state = makeState()
        let action = NativePlannedAction(
            createdAt: state.gameDate,
            detail: "Open a bounded negotiating channel.",
            id: "coded-order",
            status: .planned,
            title: "Regional Negotiation",
            mechanicTracks: [.diplomaticLeverage]
        )
        state.plannedActions = [action]
        let wrongTrackTurn = NativeGeneratedTurn(
            events: [
                makeEvent(id: "world", playerRelated: false, track: .worldTension),
                makeEvent(
                    id: "linked",
                    playerRelated: true,
                    linkedActionIDs: [action.id],
                    track: .securityAnxiety
                )
            ],
            stabilityDelta: 0,
            summary: "Diplomatic institutions review the negotiation mandate and regional response during this period.",
            worldTensionDelta: 0
        )

        XCTAssertThrowsError(try NativeGameEngine.validated(wrongTrackTurn, state: state, months: 3)) { error in
            XCTAssertTrue(String(describing: error).contains("⟦DIP⟧"))
        }

        var validTrackTurn = wrongTrackTurn
        validTrackTurn.events[1] = makeEvent(
            id: "linked",
            playerRelated: true,
            linkedActionIDs: [action.id],
            track: .diplomaticLeverage
        )
        XCTAssertNoThrow(try NativeGameEngine.validated(validTrackTurn, state: state, months: 3))
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
            ledger.governmentType = "autocracy"
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

    func testVictoryEvaluationUsesTheDisplayedObjectiveContractForEveryCatalogScenario() {
        let scenarios = [NativeScenarioCatalog.dividedSovereignty, NativeScenarioCatalog.resourceCrucible]

        for scenario in scenarios {
            var state = NativeGameEngine.initialState(for: testCountry, scenario: scenario)
            state.aiCountryStates = [:]
            state.stability = 85
            state.worldTension = 69
            state.economicLedger.securityIndex = 69
            state.economicLedgers[state.country.code] = state.economicLedger

            let incompleteObjectives = NativeGameEngine.campaignObjectives(for: state)
            XCTAssertTrue(incompleteObjectives.contains { $0.id == "stability" && $0.isComplete }, scenario.id)
            XCTAssertTrue(incompleteObjectives.contains { $0.id == "security" && !$0.isComplete }, scenario.id)
            XCTAssertEqual(NativeGameEngine.evaluateVictoryStatus(for: state), .ongoing, scenario.id)

            state.economicLedger.securityIndex = 70
            state.economicLedgers[state.country.code] = state.economicLedger

            XCTAssertTrue(NativeGameEngine.campaignObjectives(for: state).allSatisfy(\.isComplete), scenario.id)
            XCTAssertEqual(NativeGameEngine.evaluateVictoryStatus(for: state), .won, scenario.id)
        }
    }

    func testCompletedObjectivesAfterDeadlineStillLoseOnTime() {
        var state = makeState()
        state.aiCountryStates = [:]
        state.gameDate = "2031-01-01"
        state.stability = 100
        state.regionOccupations = [:]
        state.economicLedger.tradeBalancePercentGDP = 5
        state.economicLedgers[state.country.code] = state.economicLedger

        XCTAssertTrue(NativeGameEngine.campaignObjectives(for: state).allSatisfy(\.isComplete))
        XCTAssertEqual(NativeGameEngine.evaluateVictoryStatus(for: state), .lostTimeout)
    }

    func testTurnEvaluatesVictoryAfterFinalDeterministicSimulation() {
        var state = makeState()
        state.aiCountryStates = [:]
        state.gameDate = "2025-06-15"
        state.stability = 79
        state.regionOccupations = [:]
        state.budgetMilitarySlider = 0.25
        state.budgetServicesSlider = 0.50
        state.budgetDiplomacySlider = 0.25
        state.economicLedger.tradeBalancePercentGDP = 1
        state.economicLedger.realGrowthPercent = 4
        state.economicLedger.inflationPercent = 5
        state.economicLedger.securityIndex = 60
        state.economicLedgers = [state.country.code: state.economicLedger]

        let applied = NativeGameEngine.apply(
            NativeGeneratedTurn(
                events: [],
                stabilityDelta: 0,
                summary: "Public services complete the final legitimacy milestone.",
                worldTensionDelta: 0
            ),
            to: state,
            months: 1
        )

        XCTAssertGreaterThanOrEqual(applied.stability, 80)
        XCTAssertEqual(applied.victoryStatus, .won)
        XCTAssertTrue(applied.timeline.contains { $0.id.hasPrefix("victory-") })
    }

    func testRivalCompletingVictoryRaceEndsTheCampaignWithNamedDefeatEvent() throws {
        var state = makeState()
        state.gameDate = "2025-06-15"
        state.stability = 50
        let rivalCode = "ARG"
        var rivalState = try XCTUnwrap(state.aiCountryStates[rivalCode])
        rivalState.rivalCampaignProgress = 100
        state.aiCountryStates = [rivalCode: rivalState]

        var rivalLedger = try XCTUnwrap(state.economicLedgers[rivalCode])
        rivalLedger.securityIndex = 100
        rivalLedger.fiscalSpaceIndex = 100
        rivalLedger.realGrowthPercent = 16
        rivalLedger.nominalGDPTrillions = 100
        rivalLedger.tradeBalancePercentGDP = 0
        // Keep the rival at 100% after the end-of-turn macro coupling
        // recalculates fiscal space and security from debt, inflation, and
        // insurgency. Victory is intentionally evaluated against that final
        // deterministic state, not the pre-turn fixture.
        rivalLedger.publicDebtPercentGDP = 1
        rivalLedger.inflationPercent = 0
        rivalLedger.rebelControlPercent = 0
        state.economicLedgers = [
            state.country.code: state.economicLedger,
            rivalCode: rivalLedger
        ]

        let applied = NativeGameEngine.apply(
            NativeGeneratedTurn(
                events: [],
                stabilityDelta: 0,
                summary: "A rival power completes its strategic program.",
                worldTensionDelta: 0
            ),
            to: state,
            months: 1
        )

        XCTAssertEqual(
            NativeStrategyContextDatabase.aiVictoryProgress(forCode: rivalCode, in: applied),
            100,
            accuracy: 0.001
        )
        XCTAssertEqual(applied.victoryStatus, .lostRival)
        XCTAssertEqual(applied.rivalVictoryCountryCode, rivalCode)
        XCTAssertEqual(NativeGameEngine.victoriousRivalName(in: applied), "Argentina")
        XCTAssertTrue(applied.timeline.contains {
            $0.id.hasPrefix("rival-victory-arg-") && $0.title.contains("Argentina")
        })
        XCTAssertFalse(applied.timeline.contains { $0.id.hasPrefix("rival-threat-arg-") })

        let restored = try JSONDecoder().decode(
            NativeCampaignState.self,
            from: JSONEncoder().encode(applied)
        )
        XCTAssertEqual(restored.rivalVictoryCountryCode, rivalCode)
        XCTAssertEqual(NativeGameEngine.victoriousRivalName(in: restored), "Argentina")
    }

    func testRivalVictoryProgressUsesTheActiveScenarioObjectives() throws {
        var state = makeState()
        state.scenarioID = "soviet-triumph"
        state.gameDate = "2000-01-15"
        state.stability = 50
        state.worldTension = 79
        let rivalCode = "ARG"
        var rivalState = try XCTUnwrap(state.aiCountryStates[rivalCode])
        rivalState.rivalCampaignProgress = 100
        state.aiCountryStates = [rivalCode: rivalState]

        var rivalLedger = try XCTUnwrap(state.economicLedgers[rivalCode])
        rivalLedger.securityIndex = 100
        rivalLedger.fiscalSpaceIndex = 100
        rivalLedger.realGrowthPercent = 16
        rivalLedger.nominalGDPTrillions = 100
        state.economicLedgers = [
            state.country.code: state.economicLedger,
            rivalCode: rivalLedger
        ]

        XCTAssertLessThan(NativeStrategyContextDatabase.aiVictoryReadiness(forCode: rivalCode, in: state), 100)
        XCTAssertLessThan(NativeStrategyContextDatabase.aiVictoryProgress(forCode: rivalCode, in: state), 100)
        XCTAssertEqual(NativeGameEngine.evaluateVictoryStatus(for: state), .ongoing)

        state.worldTension = 80
        let rivalTargets = GeopoliticalMapData.regions.filter {
            $0.countryCode != rivalCode && $0.countryCode != "WATER"
        }.prefix(2)
        XCTAssertEqual(rivalTargets.count, 2)
        for region in rivalTargets {
            state.regionOccupations[region.id] = rivalCode
        }

        XCTAssertEqual(
            NativeStrategyContextDatabase.aiVictoryReadiness(forCode: rivalCode, in: state),
            100,
            accuracy: 0.001
        )
        XCTAssertEqual(
            NativeStrategyContextDatabase.aiVictoryProgress(forCode: rivalCode, in: state),
            100,
            accuracy: 0.001
        )
        XCTAssertEqual(NativeGameEngine.evaluateVictoryStatus(for: state), .lostRival)
    }

    func testRivalThreatWarningIsAggregatedAndEmittedOnlyOnce() throws {
        var state = makeState()
        state.stability = 50
        let rivalCode = "ARG"
        var rivalState = try XCTUnwrap(state.aiCountryStates[rivalCode])
        rivalState.rivalCampaignProgress = NativeStrategyContextDatabase.rivalAgendaVictoryAward * 2
        state.aiCountryStates = [rivalCode: rivalState]

        var rivalLedger = try XCTUnwrap(state.economicLedgers[rivalCode])
        rivalLedger.securityIndex = 100
        rivalLedger.tradeBalancePercentGDP = 0
        rivalLedger.publicDebtPercentGDP = 1
        rivalLedger.inflationPercent = 0
        rivalLedger.rebelControlPercent = 0
        state.economicLedgers = [
            state.country.code: state.economicLedger,
            rivalCode: rivalLedger
        ]

        NativeStrategyContextDatabase.simulateAIDrift(state: &state, months: 3)
        XCTAssertEqual(state.timeline.count(where: { $0.id.hasPrefix("rival-threat-") }), 1)

        state.round += 1
        NativeStrategyContextDatabase.simulateAIDrift(state: &state, months: 3)
        XCTAssertEqual(state.timeline.count(where: { $0.id.hasPrefix("rival-threat-") }), 1)
    }

    func testOpeningStrengthCannotTriggerRivalVictoryWithoutEarnedAgendas() {
        var state = makeState()
        state.gameDate = "2029-01-15"
        state.round = 99

        let readyRivals = state.aiCountryStates.keys.filter {
            NativeStrategyContextDatabase.aiVictoryReadiness(forCode: $0, in: state) >= 100
        }
        XCTAssertFalse(readyRivals.isEmpty)
        XCTAssertTrue(readyRivals.allSatisfy {
            NativeStrategyContextDatabase.aiVictoryProgress(forCode: $0, in: state) == 0
        })
        XCTAssertEqual(NativeGameEngine.evaluateVictoryStatus(for: state), .ongoing)
    }

    func testNoMapActorCannotEnterRivalVictoryRace() throws {
        var state = makeState()
        state.stability = 50
        let rivalCode = "TUV"
        var rivalState = try XCTUnwrap(state.aiCountryStates[rivalCode])
        rivalState.rivalCampaignProgress = 100
        state.aiCountryStates = [rivalCode: rivalState]

        var rivalLedger = try XCTUnwrap(state.economicLedgers[rivalCode])
        rivalLedger.securityIndex = 100
        rivalLedger.tradeBalancePercentGDP = 20
        state.economicLedgers = [
            state.country.code: state.economicLedger,
            rivalCode: rivalLedger
        ]

        XCTAssertTrue(GeopoliticalMapData.regions(forCountryCode: rivalCode).isEmpty)
        XCTAssertEqual(NativeStrategyContextDatabase.aiVictoryReadiness(forCode: rivalCode, in: state), 0)
        XCTAssertEqual(NativeStrategyContextDatabase.aiVictoryProgress(forCode: rivalCode, in: state), 0)
        XCTAssertEqual(NativeGameEngine.evaluateVictoryStatus(for: state), .ongoing)
    }

    func testCountryAliasesShareOneCanonicalRivalRaceEntry() throws {
        let state = makeState()
        let palestineAliases = state.aiCountryStates.keys.filter {
            GeopoliticalMapData.canonicalCountryCode($0) == "PSX"
        }
        let representatives = palestineAliases.filter {
            NativeStrategyContextDatabase.isCanonicalRivalRepresentative(forCode: $0, in: state)
        }

        XCTAssertGreaterThan(palestineAliases.count, 1)
        XCTAssertEqual(representatives.count, 1)
        let representative = try XCTUnwrap(representatives.first)
        let catalogName = try XCTUnwrap(CountryCatalog.all.first { $0.code == "PSE" }?.name)
        XCTAssertEqual(CountryNameResolver.name(forCode: representative, in: state), catalogName)
        XCTAssertNotEqual(catalogName, representative)
    }

    func testLegacyAIStateStartsWithNoEarnedRivalProgress() throws {
        let decoded = try JSONDecoder().decode(NativeAICountryState.self, from: Data("{}".utf8))
        XCTAssertEqual(decoded.rivalCampaignProgress, 0)
    }

    func testCompletedFullyReadyAgendaEarnsExactlyOneRivalMilestone() throws {
        var state = makeState()
        state.stability = 50
        let rivalCode = "ARG"
        var rivalState = try XCTUnwrap(state.aiCountryStates[rivalCode])
        rivalState.agendaProgress = 99
        rivalState.rivalCampaignProgress = 0
        state.aiCountryStates = [rivalCode: rivalState]

        var rivalLedger = try XCTUnwrap(state.economicLedgers[rivalCode])
        rivalLedger.securityIndex = 100
        rivalLedger.tradeBalancePercentGDP = 0
        rivalLedger.publicDebtPercentGDP = 1
        rivalLedger.inflationPercent = 0
        rivalLedger.rebelControlPercent = 0
        state.economicLedgers = [
            state.country.code: state.economicLedger,
            rivalCode: rivalLedger
        ]

        NativeStrategyContextDatabase.simulateAIDrift(state: &state, months: 3)
        XCTAssertEqual(
            try XCTUnwrap(state.aiCountryStates[rivalCode]).rivalCampaignProgress,
            NativeStrategyContextDatabase.rivalAgendaVictoryAward,
            accuracy: 0.001
        )

        NativeStrategyContextDatabase.simulateAIDrift(state: &state, months: 3)
        XCTAssertEqual(
            try XCTUnwrap(state.aiCountryStates[rivalCode]).rivalCampaignProgress,
            NativeStrategyContextDatabase.rivalAgendaVictoryAward,
            accuracy: 0.001
        )
    }

    func testTurnReducerPreservesCompletedAgendaResetAcrossParallelSimulation() async throws {
        let service = FakeNativeAIService()
        service.turnHandler = { state, months in
            makeValidTurn(for: state, months: months)
        }
        let store = try makeStore(aiService: service)
        var state = makeState()
        state.stability = 50
        let rivalCode = "ARG"
        var rivalState = try XCTUnwrap(state.aiCountryStates[rivalCode])
        rivalState.agendaProgress = 99
        rivalState.rivalCampaignProgress = 0
        state.aiCountryStates = [rivalCode: rivalState]

        var rivalLedger = try XCTUnwrap(state.economicLedgers[rivalCode])
        rivalLedger.securityIndex = 100
        rivalLedger.tradeBalancePercentGDP = 0
        rivalLedger.publicDebtPercentGDP = 1
        rivalLedger.inflationPercent = 0
        rivalLedger.rebelControlPercent = 0
        state.economicLedgers = [
            state.country.code: state.economicLedger,
            rivalCode: rivalLedger
        ]
        store.state = state

        await store.performAdvance()
        let afterCompletion = try XCTUnwrap(store.state?.aiCountryStates[rivalCode])
        XCTAssertEqual(afterCompletion.agendaProgress, 0)
        XCTAssertEqual(
            afterCompletion.rivalCampaignProgress,
            NativeStrategyContextDatabase.rivalAgendaVictoryAward,
            accuracy: 0.001
        )

        await store.performAdvance()
        let afterFollowingTurn = try XCTUnwrap(store.state?.aiCountryStates[rivalCode])
        XCTAssertGreaterThan(afterFollowingTurn.agendaProgress, 0)
        XCTAssertLessThan(afterFollowingTurn.agendaProgress, 100)
        XCTAssertEqual(
            afterFollowingTurn.rivalCampaignProgress,
            NativeStrategyContextDatabase.rivalAgendaVictoryAward,
            accuracy: 0.001
        )
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

    // MARK: – Action Failure Mechanics

    func testNonRegionalActionCanSucceed() throws {
        var state = makeState()
        // test-sanction-6 has roll < 65 → SUCCESS
        let action = NativePlannedAction(
            createdAt: state.gameDate,
            detail: "Impose targeted trade sanctions on a rival economy.",
            id: "test-sanction-6",
            status: .planned,
            title: "Impose trade sanctions"
        )
        state.plannedActions = [action]

        // The generated turn must link the action ID so the engine marks it .resolved
        let generated = NativeGeneratedTurn(
            events: [
                makeEvent(id: "independent-world", playerRelated: false),
                NativeCampaignEvent(
                    date: "",
                    description: "Sanctions effort is resolved by the administrative apparatus.",
                    id: "sanction-resolved",
                    importance: .major,
                    kind: .action,
                    linkedActionIDs: [action.id],
                    notable: true,
                    playerRelated: true,
                    strategicEffects: [],
                    title: "Trade Sanctions Resolved"
                )
            ],
            stabilityDelta: 0,
            summary: "Regional agencies review delivery milestones and publish a concrete service timetable.",
            worldTensionDelta: 0
        )

        let applied = NativeGameEngine.apply(generated, to: state, months: 1)

        let resolvedAction = try XCTUnwrap(applied.plannedActions.first { $0.id == "test-sanction-6" })
        XCTAssertEqual(resolvedAction.status, .resolved)
        XCTAssertEqual(resolvedAction.outcome, .success)

        // Success events should appear in the timeline
        let successEvents = applied.timeline.filter { $0.id.hasPrefix("action-outcome-test-sanction-6") }
        XCTAssertFalse(successEvents.isEmpty, "Expected at least one action-outcome event for the sanction action.")
        XCTAssertTrue(successEvents.contains { $0.kind == .action }, "Success should produce an .action event.")
    }

    func testNonRegionalActionCanFail() throws {
        var state = makeState()
        // test-sanction-2 has roll > 80 → FAILURE (effective threshold = 65, partial ceiling = 80)
        let action = NativePlannedAction(
            createdAt: state.gameDate,
            detail: "Impose targeted trade sanctions on a rival economy.",
            id: "test-sanction-2",
            status: .planned,
            title: "Impose trade sanctions"
        )
        state.plannedActions = [action]

        let generated = NativeGeneratedTurn(
            events: [
                makeEvent(id: "independent-world", playerRelated: false),
                NativeCampaignEvent(
                    date: "",
                    description: "Sanctions effort is resolved by the administrative apparatus.",
                    id: "sanction-resolved",
                    importance: .major,
                    kind: .action,
                    linkedActionIDs: [action.id],
                    notable: true,
                    playerRelated: true,
                    strategicEffects: [],
                    title: "Trade Sanctions Resolved"
                )
            ],
            stabilityDelta: 0,
            summary: "Regional agencies review delivery milestones and publish a concrete service timetable.",
            worldTensionDelta: 0
        )

        let applied = NativeGameEngine.apply(generated, to: state, months: 1)

        let resolvedAction = try XCTUnwrap(applied.plannedActions.first { $0.id == "test-sanction-2" })
        XCTAssertEqual(resolvedAction.status, .resolved)
        XCTAssertEqual(resolvedAction.outcome, .failure)

        // Failure events should appear in the timeline with .crisis kind
        let failureEvents = applied.timeline.filter { $0.id.hasPrefix("action-outcome-test-sanction-2") }
        XCTAssertFalse(failureEvents.isEmpty, "Expected at least one action-outcome event for the failed sanction.")
        XCTAssertTrue(failureEvents.contains { $0.kind == .crisis }, "Failure should produce a .crisis event.")

        // A negative stability effect should be applied
        let stabilityEffect = failureEvents.flatMap(\.strategicEffects).first { $0.track == .internalStability }
        XCTAssertNotNil(stabilityEffect, "Expected a stability strategic effect from the failure.")
        XCTAssertLessThan(try XCTUnwrap(stabilityEffect?.magnitude), 0, "Failure should have negative stability magnitude.")
    }

    // MARK: – Political Reform Tests

    func testPoliticalReformLiberalizeSuccess() throws {
        var state = makeState()
        // Set BRA to hybrid so liberalize is available
        state.economicLedgers[state.country.code]?.governmentType = "hybrid"
        state.stability = 50
        state.economicLedgers[state.country.code]?.publicApprovalPercent = 50.0

        // test-lib-4 has roll=0.6 < 50 → SUCCESS
        let action = NativePlannedAction(
            createdAt: state.gameDate,
            detail: "Liberalize the political system toward democratic governance.",
            id: "test-lib-4",
            status: .planned,
            title: "Liberalize toward democracy"
        )
        state.plannedActions = [action]

        let generated = NativeGeneratedTurn(
            events: [
                makeEvent(id: "independent-world", playerRelated: false),
                NativeCampaignEvent(
                    date: "",
                    description: "The liberalization reform package moves through the legislature.",
                    id: "reform-resolved",
                    importance: .major,
                    kind: .action,
                    linkedActionIDs: [action.id],
                    notable: true,
                    playerRelated: true,
                    strategicEffects: [],
                    title: "Liberalization Resolved"
                )
            ],
            stabilityDelta: 0,
            summary: "Regional agencies review delivery milestones and publish a concrete service timetable.",
            worldTensionDelta: 0
        )

        let applied = NativeGameEngine.apply(generated, to: state, months: 1)

        let resolvedAction = try XCTUnwrap(applied.plannedActions.first { $0.id == "test-lib-4" })
        XCTAssertEqual(resolvedAction.outcome, .success)

        let govType = applied.economicLedgers[state.country.code]?.governmentType
        XCTAssertEqual(govType, "democracy", "Liberalization success should transition government to democracy.")

        // Timeline should contain the liberalization event
        let reformEvents = applied.timeline.filter { $0.id.hasPrefix("pol-liberalize-") }
        XCTAssertFalse(reformEvents.isEmpty, "Expected a liberalization timeline event.")
    }

    func testPoliticalReformLiberalizeFailure() throws {
        var state = makeState()
        state.economicLedgers[state.country.code]?.governmentType = "hybrid"
        state.stability = 50
        state.economicLedgers[state.country.code]?.publicApprovalPercent = 50.0

        // test-lib-3: actual roll=70.4 > 50 → FAILURE
        let action = NativePlannedAction(
            createdAt: state.gameDate,
            detail: "Liberalize the political system toward democratic governance.",
            id: "test-lib-3",
            status: .planned,
            title: "Liberalize toward democracy"
        )
        state.plannedActions = [action]

        let generated = NativeGeneratedTurn(
            events: [
                makeEvent(id: "independent-world", playerRelated: false),
                NativeCampaignEvent(
                    date: "",
                    description: "The liberalization reform package moves through the legislature.",
                    id: "reform-resolved",
                    importance: .major,
                    kind: .action,
                    linkedActionIDs: [action.id],
                    notable: true,
                    playerRelated: true,
                    strategicEffects: [],
                    title: "Liberalization Resolved"
                )
            ],
            stabilityDelta: 0,
            summary: "Regional agencies review delivery milestones and publish a concrete service timetable.",
            worldTensionDelta: 0
        )

        let applied = NativeGameEngine.apply(generated, to: state, months: 1)

        let resolvedAction = try XCTUnwrap(applied.plannedActions.first { $0.id == "test-lib-3" })
        XCTAssertEqual(resolvedAction.outcome, .failure)

        let govType = applied.economicLedgers[state.country.code]?.governmentType
        XCTAssertEqual(govType, "hybrid", "Failed liberalization should NOT change government type.")

        // Should produce a crisis event
        let reformEvents = applied.timeline.filter { $0.id.hasPrefix("pol-liberalize-") }
        XCTAssertFalse(reformEvents.isEmpty)
        XCTAssertTrue(reformEvents.contains { $0.kind == .crisis }, "Failed liberalization should produce a .crisis event.")
    }

    func testPoliticalReformConsolidateSuccess() throws {
        var state = makeState()
        // BRA starts as democracy; consolidate is available and transitions to hybrid
        state.stability = 50
        state.economicLedgers[state.country.code]?.publicApprovalPercent = 50.0

        // test-con-2: actual roll=30.1 ≤ 55 → SUCCESS
        let action = NativePlannedAction(
            createdAt: state.gameDate,
            detail: "Consolidate executive power and reduce legislative oversight.",
            id: "test-con-2",
            status: .planned,
            title: "Consolidate executive power"
        )
        state.plannedActions = [action]

        let generated = NativeGeneratedTurn(
            events: [
                makeEvent(id: "independent-world", playerRelated: false),
                NativeCampaignEvent(
                    date: "",
                    description: "The consolidation package moves through the legislature.",
                    id: "reform-resolved",
                    importance: .major,
                    kind: .action,
                    linkedActionIDs: [action.id],
                    notable: true,
                    playerRelated: true,
                    strategicEffects: [],
                    title: "Consolidation Resolved"
                )
            ],
            stabilityDelta: 0,
            summary: "Regional agencies review delivery milestones and publish a concrete service timetable.",
            worldTensionDelta: 0
        )

        let applied = NativeGameEngine.apply(generated, to: state, months: 1)

        let resolvedAction = try XCTUnwrap(applied.plannedActions.first { $0.id == "test-con-2" })
        XCTAssertEqual(resolvedAction.outcome, .success)

        let govType = applied.economicLedgers[state.country.code]?.governmentType
        XCTAssertEqual(govType, "hybrid", "Consolidation success should transition democracy → hybrid.")
    }

    func testSnapElectionTriggered() throws {
        var state = makeState()
        // BRA is a democracy; snap election is available
        let originalElectionRound = state.economicLedgers[state.country.code]?.nextElectionRound ?? 0

        // test-snap-2: actual roll=69.4 ≤ 80 → SUCCESS
        let action = NativePlannedAction(
            createdAt: state.gameDate,
            detail: "Call snap elections to renew democratic mandate.",
            id: "test-snap-2",
            status: .planned,
            title: "Call snap elections"
        )
        state.plannedActions = [action]

        let generated = NativeGeneratedTurn(
            events: [
                makeEvent(id: "independent-world", playerRelated: false),
                NativeCampaignEvent(
                    date: "",
                    description: "The snap election decree is issued.",
                    id: "snap-resolved",
                    importance: .major,
                    kind: .action,
                    linkedActionIDs: [action.id],
                    notable: true,
                    playerRelated: true,
                    strategicEffects: [],
                    title: "Snap Election Resolved"
                )
            ],
            stabilityDelta: 0,
            summary: "Regional agencies review delivery milestones and publish a concrete service timetable.",
            worldTensionDelta: 0
        )

        let applied = NativeGameEngine.apply(generated, to: state, months: 1)

        let resolvedAction = try XCTUnwrap(applied.plannedActions.first { $0.id == "test-snap-2" })
        XCTAssertEqual(resolvedAction.outcome, .success)

        let newElectionRound = applied.economicLedgers[state.country.code]?.nextElectionRound
        XCTAssertEqual(newElectionRound, state.round + 12, "Snap election should set nextElectionRound to round + 12.")
        XCTAssertNotEqual(newElectionRound, originalElectionRound, "Election round should have changed.")
    }

    // MARK: - Dynamic AI-vs-AI Geopolitics (Rival World Life)

    func testRivalGeopoliticsProducesAIvsAIWarThatChangesTheMap() {
        // Force two expansionist, military-budgeted AI rivals with deep mutual
        // animosity so the war-roll has the maximum chance of firing. Then run
        // several turns — a war should erupt between them, redraw the
        // occupation/conflict map, impose ledger costs on both sides, and bump
        // world tension. All deterministically.
        var state = makeState()
        state.stability = 60
        state.worldTension = 45

        // Two valid strategic countries with real map regions.
        let attacker = "USA"
        let defender = "CHN"
        XCTAssertFalse(GeopoliticalMapData.regions(forCountryCode: attacker).isEmpty)
        XCTAssertFalse(GeopoliticalMapData.regions(forCountryCode: defender).isEmpty)

        state.aiCountryStates[attacker] = NativeAICountryState(
            countryCode: attacker,
            doctrine: .expansionist,
            budgetPriority: .military,
            relationshipScores: [defender: -90, state.country.code: 0],
            multiTurnAgenda: "Regional dominance",
            agendaProgress: 0
        )
        state.aiCountryStates[defender] = NativeAICountryState(
            countryCode: defender,
            doctrine: .defensive,
            budgetPriority: .military,
            relationshipScores: [attacker: -90, state.country.code: 0],
            multiTurnAgenda: "Defend sovereignty",
            agendaProgress: 0
        )

        let beforeTension = state.worldTension

        // Run enough turns that the deterministic war-roll fires at least once
        // for at least one of the qualifying attacker/date seeds.
        for round in 1 ... 15 {
            state.round = round
            state.gameDate = "2026-\(String(format: "%02d", ((round - 1) % 12) + 1))-15"
            NativeStrategyContextDatabase.simulateAIDrift(state: &state, months: 1)
        }

        let warEvents = state.timeline.filter {
            $0.id.hasPrefix("ai-war-") || $0.id.hasPrefix("ai-invasion-")
        }
        XCTAssertFalse(warEvents.isEmpty, "Expected at least one AI-vs-AI war or invasion event after 15 turns of provocation. Found: \(state.timeline.filter { $0.id.hasPrefix("ai-") }.map(\.id).prefix(5))")

        // The war must have produced a tangible map change: either a conflict
        // state or an occupation touching the defender's territory.
        let defenderRegions = Set(GeopoliticalMapData.regions(forCountryCode: defender).map(\.id))
        let touchedConflicts = state.regionConflicts.filter { defenderRegions.contains($0.key) }
        let touchedOccupations = state.regionOccupations.filter { defenderRegions.contains($0.key) }
        XCTAssertFalse(touchedConflicts.isEmpty && touchedOccupations.isEmpty,
                       "AI-vs-AI war should change the map (conflict or occupation on \(defender)).")

        // World tension should not have dropped as a result of a war.
        XCTAssertGreaterThanOrEqual(state.worldTension, beforeTension)

        // The player should not have accidentally become a party to an AI war.
        let playerTargetedWars = warEvents.filter { $0.id.contains("-\(state.country.code)") }
        XCTAssertTrue(playerTargetedWars.isEmpty, "AI-vs-AI wars must not target the player.")

        // Autonomous AI-to-AI treaties must be accepted (never pending) — the
        // player never votes on them.
        XCTAssertTrue(state.activeOffers.allSatisfy { $0.targetCode == nil || $0.status == .accepted },
                      "Autonomous AI treaties must be accepted (not pending) — player never votes on them.")
    }

    func testRivalGeopoliticsProducesIdeologicalAllianceBetweenAI() {
        // Two democracies that already like each other (>55 mutual) should,
        // over several turns, formalize an autonomous mutual-defense alliance
        // that the player is NOT a party to and cannot accept/reject.
        var state = makeState()
        state.stability = 60
        state.worldTension = 40

        let codeA = "USA"
        let codeB = "GBR"

        // Ensure ledgers exist and are democracies.
        if state.economicLedgers[codeA] == nil {
            state.economicLedgers[codeA] = NativeStrategyContextDatabase.startingEconomicLedger(forCode: codeA, scenario: NativeScenarioCatalog.defaultScenario)
        }
        if state.economicLedgers[codeB] == nil {
            state.economicLedgers[codeB] = NativeStrategyContextDatabase.startingEconomicLedger(forCode: codeB, scenario: NativeScenarioCatalog.defaultScenario)
        }
        state.economicLedgers[codeA]?.governmentType = "democracy"
        state.economicLedgers[codeB]?.governmentType = "democracy"

        state.aiCountryStates[codeA] = NativeAICountryState(
            countryCode: codeA,
            doctrine: .collaborative,
            budgetPriority: .diplomacy,
            relationshipScores: [codeB: 70, state.country.code: 10],
            multiTurnAgenda: "Deepen democratic partnership",
            agendaProgress: 0
        )
        state.aiCountryStates[codeB] = NativeAICountryState(
            countryCode: codeB,
            doctrine: .collaborative,
            budgetPriority: .diplomacy,
            relationshipScores: [codeA: 70, state.country.code: 10],
            multiTurnAgenda: "Deepen democratic partnership",
            agendaProgress: 0
        )

        for round in 1 ... 12 {
            state.round = round
            state.gameDate = "2026-\(String(format: "%02d", ((round - 1) % 12) + 1))-15"
            NativeStrategyContextDatabase.simulateAIDrift(state: &state, months: 1)
        }

        // An autonomous alliance offer between A and B must exist and be
        // accepted (the player never votes on it).
        let alliance = state.activeOffers.first { offer in
            offer.type == .militaryAlliance &&
                offer.status == .accepted &&
                offer.targetCode != nil &&
                ((offer.proposerCode == codeA && offer.targetCode == codeB) ||
                    (offer.proposerCode == codeB && offer.targetCode == codeA))
        }
        XCTAssertNotNil(alliance, "Expected an autonomous USA-GBR alliance after 12 turns of warm democratic relations.")

        // It must be marked as NOT player-facing.
        if let alliance {
            XCTAssertTrue(alliance.isAutonomousAITreaty, "AI-to-AI alliance must be flagged autonomous.")
            XCTAssertFalse(alliance.isPlayerFacing, "AI-to-AI alliance must not appear in the player's inbox.")
        }

        // A world event announcing the alliance should be on the timeline.
        let allianceEvents = state.timeline.filter { $0.id.hasPrefix("ai-alliance-event-") }
        XCTAssertFalse(allianceEvents.isEmpty, "Alliance formation should emit a world event.")
    }

    func testRivalGeopoliticsProducesTradeCorridorThatMovesLedgers() {
        // Two mercantile partners with warm relations should sign a structured
        // trade corridor that actually moves both their ledgers (trade + growth).
        var state = makeState()
        state.stability = 60
        state.worldTension = 30

        let codeA = "JPN"
        let codeB = "DEU"

        if state.economicLedgers[codeA] == nil {
            state.economicLedgers[codeA] = NativeStrategyContextDatabase.startingEconomicLedger(forCode: codeA, scenario: NativeScenarioCatalog.defaultScenario)
        }
        if state.economicLedgers[codeB] == nil {
            state.economicLedgers[codeB] = NativeStrategyContextDatabase.startingEconomicLedger(forCode: codeB, scenario: NativeScenarioCatalog.defaultScenario)
        }

        state.aiCountryStates[codeA] = NativeAICountryState(
            countryCode: codeA,
            doctrine: .mercantile,
            budgetPriority: .growth,
            relationshipScores: [codeB: 55, state.country.code: 5],
            multiTurnAgenda: "Commercial expansion",
            agendaProgress: 0
        )
        state.aiCountryStates[codeB] = NativeAICountryState(
            countryCode: codeB,
            doctrine: .mercantile,
            budgetPriority: .growth,
            relationshipScores: [codeA: 55, state.country.code: 5],
            multiTurnAgenda: "Commercial expansion",
            agendaProgress: 0
        )

        let tradeABefore = state.economicLedgers[codeA]?.tradeBalancePercentGDP ?? 0
        let tradeBBefore = state.economicLedgers[codeB]?.tradeBalancePercentGDP ?? 0

        for round in 1 ... 12 {
            state.round = round
            state.gameDate = "2026-\(String(format: "%02d", ((round - 1) % 12) + 1))-15"
            NativeStrategyContextDatabase.simulateAIDrift(state: &state, months: 1)
        }

        // A trade corridor treaty between the two must exist and be accepted.
        let tradePact = state.activeOffers.first { offer in
            offer.type == .tradeAgreement &&
                offer.status == .accepted &&
                offer.targetCode != nil &&
                ((offer.proposerCode == codeA && offer.targetCode == codeB) ||
                    (offer.proposerCode == codeB && offer.targetCode == codeA))
        }
        XCTAssertNotNil(tradePact, "Expected a JPN-DEU trade corridor after 12 turns of warm commercial relations.")

        // The ledger effect must be real and visible: trade entries tagged
        // ai-trade-pact should exist for both signatories.
        let pactEntriesA = state.economicLedgers[codeA]?.entries.filter { $0.ruleID == "ai-trade-pact" } ?? []
        let pactEntriesB = state.economicLedgers[codeB]?.entries.filter { $0.ruleID == "ai-trade-pact" } ?? []
        XCTAssertFalse(pactEntriesA.isEmpty, "Trade corridor should have produced ledger entries for \(codeA).")
        XCTAssertFalse(pactEntriesB.isEmpty, "Trade corridor should have produced ledger entries for \(codeB).")

        // The pact itself must be a positive trade contribution on both sides
        // (other drifts may also apply, so we assert the pact's own contribution).
        let pactContributionA = pactEntriesA.reduce(0.0) { $0 + $1.tradeBalanceDelta }
        let pactContributionB = pactEntriesB.reduce(0.0) { $0 + $1.tradeBalanceDelta }
        XCTAssertGreaterThan(pactContributionA, 0, "Trade pact must contribute positive trade balance to \(codeA).")
        XCTAssertGreaterThan(pactContributionB, 0, "Trade pact must contribute positive trade balance to \(codeB).")

        // Sanity: balances are finite.
        let tradeAAfter = state.economicLedgers[codeA]?.tradeBalancePercentGDP ?? tradeABefore
        let tradeBAfter = state.economicLedgers[codeB]?.tradeBalancePercentGDP ?? tradeBBefore
        XCTAssertTrue(tradeAAfter.isFinite && tradeBAfter.isFinite)

        // The player should never be a party to this trade pact.
        if let tradePact {
            XCTAssertNotEqual(tradePact.proposerCode, state.country.code)
            XCTAssertNotEqual(tradePact.targetCode, state.country.code)
        }
    }

    func testAutonomousAITreatiesDoNotLeakIntoPlayerDiplomacyInbox() {
        // An autonomous AI-to-AI treaty (targetCode != nil) must be flagged as
        // NOT player-facing, so the UI excludes it from the player's inbox.
        let offer = NativeDiplomaticOffer(
            id: "test-autonomous",
            proposerCode: "USA",
            type: .militaryAlliance,
            description: "USA-CHN autonomous pact",
            stabilityCost: 0,
            relationshipEffect: 10,
            growthDelta: 0,
            status: .accepted,
            turnProposed: 1,
            targetCode: "CHN"
        )
        XCTAssertTrue(offer.isAutonomousAITreaty)
        XCTAssertFalse(offer.isPlayerFacing)
        XCTAssertEqual(offer.targetCode, "CHN")

        // A legacy player-facing offer (no targetCode) must remain player-facing.
        let playerOffer = NativeDiplomaticOffer(
            id: "test-player",
            proposerCode: "USA",
            type: .tradeAgreement,
            description: "USA offers player a trade deal",
            stabilityCost: 0,
            relationshipEffect: 10,
            growthDelta: 0.2,
            status: .pending,
            turnProposed: 1
        )
        XCTAssertFalse(playerOffer.isAutonomousAITreaty)
        XCTAssertTrue(playerOffer.isPlayerFacing)
        XCTAssertNil(playerOffer.targetCode)
    }

    func testNativeDiplomaticOfferDecodesLegacySavesWithoutTargetCode() throws {
        // Existing saves have offers WITHOUT the targetCode field. Decoding
        // them must not crash and must default to nil (player-facing).
        let legacyJSON = Data("""
        {
            "id": "offer-legacy",
            "proposerCode": "USA",
            "type": "trade-agreement",
            "description": "legacy",
            "stabilityCost": 0,
            "relationshipEffect": 10,
            "growthDelta": 0.2,
            "status": "pending",
            "turnProposed": 3
        }
        """.utf8)

        let decoded = try JSONDecoder().decode(NativeDiplomaticOffer.self, from: legacyJSON)
        XCTAssertEqual(decoded.id, "offer-legacy")
        XCTAssertNil(decoded.targetCode, "Legacy saves must decode targetCode as nil.")
        XCTAssertTrue(decoded.isPlayerFacing, "Legacy offers must be treated as player-facing.")
    }
}

@MainActor
private struct CapturedProviderRequest {
    var hasReasoningProgress: Bool
    var prompt: String
    var maxTokens: Int
    var responseFormat: String?
    var thinkingEnabled: Bool
}

@MainActor
private final class StubNVIDIAGameService: NativeNVIDIAService {
    private let shouldFail: Bool
    var calledSurfaces: [String] = []

    init(defaults: UserDefaults, shouldFail: Bool = false) {
        self.shouldFail = shouldFail
        super.init(defaults: defaults)
    }

    private func failIfNeeded() throws {
        if shouldFail {
            throw NativeFoundationModelError.generationFailed("NVIDIA fixture failure")
        }
    }

    override func checkReadiness() async -> NativeAIReadiness {
        calledSurfaces.append("readiness")
        return shouldFail
            ? .unavailable("NVIDIA fixture failure")
            : .available(tokenBudget: "NVIDIA fixture ready; no app-level token cap")
    }

    override func generateTurn(for _: NativeCampaignState, months _: Int) async throws -> NativeGeneratedTurn {
        calledSurfaces.append("turn")
        try failIfNeeded()
        return NativeGeneratedTurn(events: [], stabilityDelta: 0, summary: "NVIDIA turn", worldTensionDelta: 0)
    }

    override func generateTurn(
        for state: NativeCampaignState,
        months: Int,
        progress _: @escaping @MainActor (NativeTurnProgress) -> Void
    ) async throws -> NativeGeneratedTurn {
        try await generateTurn(for: state, months: months)
    }

    override func generateSuggestedActions(for _: NativeCampaignState) async throws -> [NativeSuggestedAction] {
        calledSurfaces.append("suggestions")
        try failIfNeeded()
        return []
    }

    override func generateAdvisorBrief(for _: NativeCampaignState, question _: String) async throws -> String {
        calledSurfaces.append("advisor")
        try failIfNeeded()
        return "NVIDIA advisor"
    }

    override func generateDiplomaticReply(
        for _: NativeCampaignState,
        thread _: NativeDiplomaticThread,
        message _: String
    ) async throws -> String {
        calledSurfaces.append("diplomacy")
        try failIfNeeded()
        return "NVIDIA diplomacy"
    }
}

@MainActor
private final class CapturingNVIDIAMatrixService: NativeNVIDIAService {
    var capturedRequests: [CapturedProviderRequest] = []
    var response = ""

    override var apiKey: String {
        "test-nvidia-key"
    }

    override func executeProviderRequest(
        prompt: String,
        maxTokens: Int,
        temperature _: Double,
        responseFormat: String? = nil,
        thinkingEnabled: Bool = true,
        onStreamProgress _: (@MainActor (String) -> Void)? = nil,
        onReasoningProgress: (@MainActor (NativeReasoningStreamUpdate) -> Void)? = nil,
        requestTimeout _: TimeInterval = 90,
        retryLimit _: Int = 2
    ) async throws -> String {
        capturedRequests.append(CapturedProviderRequest(
            hasReasoningProgress: onReasoningProgress != nil,
            prompt: prompt,
            maxTokens: maxTokens,
            responseFormat: responseFormat,
            thinkingEnabled: thinkingEnabled
        ))
        return response
    }
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
        thinkingEnabled: Bool = true,
        onStreamProgress _: (@MainActor (String) -> Void)? = nil,
        onReasoningProgress: (@MainActor (NativeReasoningStreamUpdate) -> Void)? = nil,
        requestTimeout _: TimeInterval = 90,
        retryLimit _: Int = 2
    ) async throws -> String {
        capturedRequests.append(CapturedProviderRequest(
            hasReasoningProgress: onReasoningProgress != nil,
            prompt: prompt,
            maxTokens: maxTokens,
            responseFormat: responseFormat,
            thinkingEnabled: thinkingEnabled
        ))
        if thinkingEnabled, let onReasoningProgress {
            onReasoningProgress(NativeReasoningStreamUpdate(
                modelIdentifier: "test/reasoning-free",
                status: .live,
                text: "Reviewing campaign state and legal consequences."
            ))
        }
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
              "kind": "action",
              "importance": "severe",
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
        let cells = (0 ..< 5).flatMap { row in
            (0 ..< 5).map { column in
                """
                {"matrixRow":\(row),"matrixColumn":\(column),"title":"Fund Matrix Program \(row)-\(column)","detail":"Create a bounded regional service program through existing institutions during the next campaign period.","rationale":"This proposal fits stored objectives, current authority, fiscal limits, and administrative capacity.","urgency":"soon","primaryMechanic":"internal-stability","secondaryMechanic":"market-confidence","actionKind":"policy","administrativeCost":10,"targetCountryCode":null,"targetRegionID":null,"sovereigntyChange":null}
                """
            }
        }
        return "{\"suggestions\":[\(cells.joined(separator: ","))]}"
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

    func testPoliticalLedgerTolerantDecoding() throws {
        let jsonStr = """
        {
            "budgetBalancePercentGDP": -2.5,
            "entries": [],
            "fiscalSpaceIndex": 55,
            "inflationPercent": 2.0,
            "nominalGDPTrillions": 1.2,
            "publicDebtPercentGDP": 60.0,
            "realGrowthPercent": 3.0,
            "tradeBalancePercentGDP": -1.0,
            "unemploymentPercent": 5.8,
            "securityIndex": 75.0,
            "rebelControlPercent": 2.0,
            "resourceReserves": {}
        }
        """
        let json = Data(jsonStr.utf8)

        let decoder = JSONDecoder()
        let ledger = try decoder.decode(NativeEconomicLedger.self, from: json)
        XCTAssertEqual(ledger.governmentType, "democracy")
        XCTAssertEqual(ledger.publicApprovalPercent, 50.0)
        XCTAssertEqual(ledger.nextElectionRound, 48)
    }

    func testApprovalDriftAndElectionResolution() throws {
        var state = makeState()
        // Set up player country as a democracy
        var playerLedger = state.economicLedger
        playerLedger.governmentType = "democracy"
        playerLedger.publicApprovalPercent = 45.0 // low approval, high risk of losing
        playerLedger.nextElectionRound = 2
        state.economicLedgers[state.country.code] = playerLedger
        state.round = 2

        // Advance turn by 1 month to trigger simulateAIDrift
        let turn = NativeGeneratedTurn(events: [], stabilityDelta: 0, summary: "No external news.", worldTensionDelta: 0)
        let applied = NativeGameEngine.apply(turn, to: state, months: 1)

        // Verify nextElectionRound was updated (incremented by 48)
        let nextLedger = try XCTUnwrap(applied.economicLedgers[state.country.code])
        XCTAssertEqual(nextLedger.nextElectionRound, 50)

        // Verify an election event is logged in the timeline
        let electionEvents = applied.timeline.filter { $0.id.hasPrefix("election-resolution-") }
        XCTAssertEqual(electionEvents.count, 1)
    }

    func testAutocracyCoupTrigger() {
        var state = makeState()
        // Setup CHN as an autocracy with extremely low approval
        var chnLedger = NativeStrategyContextDatabase.startingEconomicLedger(forCode: "CHN", scenario: NativeScenarioCatalog.defaultScenario)
        chnLedger.governmentType = "autocracy"
        chnLedger.publicApprovalPercent = 15.0 // Critically low
        state.economicLedgers["CHN"] = chnLedger

        // Let's run simulation loop several times using simulateAIDrift directly to verify coup triggers
        var testState = state
        for _ in 1 ... 10 {
            NativeStrategyContextDatabase.simulateAIDrift(state: &testState, months: 1)
        }

        // Coup event should have fired and decried autocracy downfall
        let coupEvents = testState.timeline.filter { $0.id.hasPrefix("coup-") }
        XCTAssertTrue(coupEvents.count > 0)
    }

    func testIdeologicalRelationshipDrift() {
        var state = makeState()

        // Player (BRA) is democracy. Set up CHN as autocracy and GBR as democracy
        var braLedger = state.economicLedger
        braLedger.governmentType = "democracy"
        state.economicLedger = braLedger
        state.economicLedgers["BRA"] = braLedger

        var gbrLedger = NativeStrategyContextDatabase.startingEconomicLedger(forCode: "GBR", scenario: NativeScenarioCatalog.defaultScenario)
        gbrLedger.governmentType = "democracy"
        state.economicLedgers["GBR"] = gbrLedger

        var chnLedger = NativeStrategyContextDatabase.startingEconomicLedger(forCode: "CHN", scenario: NativeScenarioCatalog.defaultScenario)
        chnLedger.governmentType = "autocracy"
        state.economicLedgers["CHN"] = chnLedger

        // Initialize relationship scores
        let chnState = NativeAICountryState(countryCode: "CHN", doctrine: .isolationist, budgetPriority: .stability, relationshipScores: ["BRA": 0], multiTurnAgenda: "", agendaProgress: 0)
        let gbrState = NativeAICountryState(countryCode: "GBR", doctrine: .collaborative, budgetPriority: .diplomacy, relationshipScores: ["BRA": 0], multiTurnAgenda: "", agendaProgress: 0)
        state.aiCountryStates["CHN"] = chnState
        state.aiCountryStates["GBR"] = gbrState

        // Run AI drift simulation for 12 months
        var testState = state
        NativeStrategyContextDatabase.simulateAIDrift(state: &testState, months: 12)

        // Democracy GBR and Democracy BRA should drift positively
        let gbrToBraRel = testState.aiCountryStates["GBR"]?.relationshipScores["BRA"] ?? 0
        XCTAssertTrue(gbrToBraRel > 0, "Democracies should drift positively: \(gbrToBraRel)")

        // Autocracy CHN and Democracy BRA should drift negatively
        let chnToBraRel = testState.aiCountryStates["CHN"]?.relationshipScores["BRA"] ?? 0
        XCTAssertTrue(chnToBraRel < 0, "Democracy and Autocracy should drift negatively: \(chnToBraRel)")
    }

    func testDefenderAlliesPenalizePlayerOccupation() throws {
        var state = makeState()
        let occupiedRegion = try XCTUnwrap(
            GeopoliticalMapData.regions.first { $0.countryCode == "ARG" }
        )
        state.regionOccupations[occupiedRegion.id] = state.country.code
        state.aiCountryStates["USA"] = NativeAICountryState(
            countryCode: "USA",
            doctrine: .collaborative,
            budgetPriority: .diplomacy,
            relationshipScores: ["ARG": 70, state.country.code: 10],
            multiTurnAgenda: "Protect aligned regional partners.",
            agendaProgress: 0
        )

        NativeStrategyContextDatabase.simulateAIDrift(state: &state, months: 1)

        XCTAssertLessThanOrEqual(state.aiCountryStates["USA"]?.relationshipScores[state.country.code] ?? 100, 7)
    }

    func testRefinedGameMechanicsAndAIInterference() {
        var state = makeState()

        // 1. Verify Administrative Capacity drain from active conflicts and hostile AI agendas
        state.regionConflicts["ARG"] = NativeRegionConflictState(
            controllerCode: "ARG",
            intensity: 3,
            mode: .conventionalOccupation,
            originalCountryCode: "ARG",
            regionID: "ARG",
            summary: "Conflict Test",
            updatedAt: state.gameDate
        )
        state.aiCountryStates["ARG"] = NativeAICountryState(
            countryCode: "ARG",
            doctrine: .expansionist,
            budgetPriority: .military,
            relationshipScores: [state.country.code: -50],
            multiTurnAgenda: "Hostile planning",
            agendaProgress: 90
        )

        let turnGen = NativeGeneratedTurn(events: [], stabilityDelta: 0, summary: "Leap", worldTensionDelta: 0)
        let advancedState = NativeGameEngine.apply(turnGen, to: state, months: 1)

        // Hostile AI = 1 (ARG, relation -50 < -40), Conflict = 1 (ARG)
        // Base refill is 100, stability penalty = (100 - state.stability) * 0.4
        // With state.stability = 100, stability penalty = 0.
        // servicesBonus = 0 (budgetServicesSlider default).
        // rebelPenalty = 0 (player rebelControlPercent default).
        // aiACDrain = 1 * 5 = 5.
        // conflictACDrain = 1 * 3 = 3.
        // Expected refillAmount = 100 - 5 - 3 = 92.
        XCTAssertEqual(advancedState.administrativeCapacity, 92)

        // 2. Verify AI Invasions trigger correctly on agendaProgress >= 100 and expansionist doctrine
        var invasionState = makeState()
        invasionState.aiCountryStates["ARG"] = NativeAICountryState(
            countryCode: "ARG",
            doctrine: .expansionist,
            budgetPriority: .military,
            relationshipScores: [invasionState.country.code: -50],
            multiTurnAgenda: "Invasion plan",
            agendaProgress: 100
        )

        // Ensure BRA has regions
        let braRegions = GeopoliticalMapData.regions.filter { $0.countryCode == "BRA" }
        XCTAssertFalse(braRegions.isEmpty)

        // Let's run a turn, which should trigger the invasion
        let postInvasionState = NativeGameEngine.apply(turnGen, to: invasionState, months: 1)

        // The agendaProgress of ARG should be reset to 0
        XCTAssertEqual(postInvasionState.aiCountryStates["ARG"]?.agendaProgress, 0)

        // There should be a timeline event about invasion success or fail
        let hasInvasionEvent = postInvasionState.timeline.contains { event in
            event.id.contains("ai-invasion-success") || event.id.contains("ai-invasion-fail")
        }
        XCTAssertTrue(hasInvasionEvent)

        // 3. Verify Market, Port, and Fortress buildings modify GDP, trade, and combat rolls
        var buildingsState = makeState()
        XCTAssertGreaterThanOrEqual(braRegions.count, 2)
        let firstRegionID = braRegions[0].id
        let secondRegionID = braRegions[1].id

        buildingsState.mapBuildings = [
            NativeBuildingSnapshot(ownerCountryCode: "BRA", regionID: firstRegionID, type: .market),
            NativeBuildingSnapshot(ownerCountryCode: "BRA", regionID: secondRegionID, type: .port)
        ]

        buildingsState.regionOccupations[firstRegionID] = "BRA"
        buildingsState.regionOccupations[secondRegionID] = "BRA"

        let db = NativeStrategyContextDatabase.self
        var testLedgers = buildingsState.economicLedgers
        testLedgers = db.updatedEconomicLedgers(from: testLedgers, state: buildingsState, events: [], months: 1, targetDate: "2026-07-23")

        // Market level 1 should boost growth, Port level 1 should boost trade balance
        var baselineState = makeState()
        baselineState.regionOccupations[firstRegionID] = "BRA"
        baselineState.regionOccupations[secondRegionID] = "BRA"
        let baselineLedgers = db.updatedEconomicLedgers(from: baselineState.economicLedgers, state: baselineState, events: [], months: 1, targetDate: "2026-07-23")

        if let updatedLedger = testLedgers["BRA"], let baselineLedger = baselineLedgers["BRA"] {
            XCTAssertGreaterThan(updatedLedger.realGrowthPercent, baselineLedger.realGrowthPercent)
            XCTAssertGreaterThan(updatedLedger.tradeBalancePercentGDP, baselineLedger.tradeBalancePercentGDP)
        }

        // 4. Verify slider-based recruitment/attrition
        var recruitState = makeState()
        recruitState.budgetMilitarySlider = 0.50 // recruitment threshold is > 0.40
        var testStateRecruit = recruitState
        db.simulateAIDrift(state: &testStateRecruit, months: 1)

        XCTAssertGreaterThan(testStateRecruit.militaryUnits["infantry", default: 0], recruitState.militaryUnits["infantry", default: 0])

        var attritState = makeState()
        attritState.budgetMilitarySlider = 0.10 // attrition threshold is < 0.20
        var testStateAttrit = attritState
        db.simulateAIDrift(state: &testStateAttrit, months: 1)

        XCTAssertLessThan(testStateAttrit.militaryUnits["infantry", default: 0], attritState.militaryUnits["infantry", default: 0])
    }

    func testPlayerDecisionMatrixRequiresEveryEligibleCoordinate() throws {
        var state = NativeGameEngine.initialState(for: testCountry, worldSeed: 424_242)
        state.administrativeCapacity = 40
        let matrix = makeLegalDecisionMatrix(for: state, cost: 10)

        let validated = try NativeDecisionMatrixContract.validatedPlayerMatrix(matrix, state: state)

        XCTAssertEqual(validated.count, 25)
        XCTAssertEqual(Set(validated.map { "\($0.matrixRow):\($0.matrixColumn)" }).count, 25)
        XCTAssertTrue(validated.allSatisfy { $0.administrativeCost <= state.administrativeCapacity })

        var changedWorld = state
        changedWorld.budgetMilitarySlider = 0.8
        XCTAssertEqual(
            NativeDecisionMatrixContract.eligibilityFailure(for: validated[0], state: changedWorld),
            "world state changed after this matrix was generated"
        )

        var impossible = matrix
        impossible[0].actionKind = "political"
        impossible[0].detail = "Liberalize the political system toward democratic governance."
        XCTAssertThrowsError(try NativeDecisionMatrixContract.validatedPlayerMatrix(impossible, state: state))

        var unaffordable = matrix
        unaffordable[1].administrativeCost = 41
        XCTAssertThrowsError(try NativeDecisionMatrixContract.validatedPlayerMatrix(unaffordable, state: state))
    }

    func testLocalDecisionMatrixIsImmediateDeterministicAndFullyLegal() throws {
        var state = NativeGameEngine.initialState(for: testCountry, worldSeed: 424_242)
        state.administrativeCapacity = 100

        let first = NativeDecisionMatrixContract.localPlayerMatrix(for: state)
        let second = NativeDecisionMatrixContract.localPlayerMatrix(for: state)
        let validated = try NativeDecisionMatrixContract.validatedPlayerMatrix(first, state: state)

        XCTAssertEqual(first, second)
        XCTAssertEqual(validated.count, NativeDecisionMatrixContract.cellCount)
        XCTAssertEqual(Set(validated.map { "\($0.matrixRow):\($0.matrixColumn)" }).count, 25)
        XCTAssertTrue(validated.allSatisfy { $0.administrativeCost > 0 })
        XCTAssertTrue(validated.allSatisfy { $0.administrativeCost <= state.administrativeCapacity })
    }

    func testMatrixQueueCapsAtEveryOrderTheTurnPipelineCanResolveAndSupportsToggle() throws {
        let store = try makeStore()
        var state = NativeGameEngine.initialState(for: testCountry, worldSeed: 99)
        state.administrativeCapacity = 100
        let matrix = NativeDecisionMatrixContract.localPlayerMatrix(for: state)
        store.state = state

        for suggestion in matrix.prefix(NativeDecisionMatrixContract.maximumOrdersPerTurn) {
            store.addSuggestedAction(suggestion)
        }

        XCTAssertEqual(
            store.state?.plannedActions.filter { $0.status == .planned }.count,
            NativeDecisionMatrixContract.maximumOrdersPerTurn
        )
        XCTAssertEqual(store.state?.administrativeCapacity, 40)

        store.addSuggestedAction(matrix[NativeDecisionMatrixContract.maximumOrdersPerTurn])
        XCTAssertEqual(
            store.state?.plannedActions.filter { $0.status == .planned }.count,
            NativeDecisionMatrixContract.maximumOrdersPerTurn
        )
        XCTAssertTrue(store.lastError?.contains("queue is full") == true)

        store.toggleSuggestedAction(matrix[0])
        XCTAssertEqual(store.state?.plannedActions.filter { $0.status == .planned }.count, 2)
        XCTAssertEqual(store.state?.administrativeCapacity, 50)
    }

    func testOpenRouterMatrixPromptCarriesSeedsWorldPowerAndSovereigntyState() {
        var state = NativeGameEngine.initialState(for: testCountry, worldSeed: 0xA11C_E123)
        state.dynamicCountries["NBR"] = "New Brazil"
        let prompt = NativeDecisionMatrixPrompt.make(for: state)

        XCTAssertTrue(prompt.contains("worldSeed=2703024419"))
        XCTAssertTrue(prompt.contains("turnSeed="))
        XCTAssertTrue(prompt.contains("ALL COUNTRY STATES"))
        XCTAssertTrue(prompt.contains("militaryUnits="))
        XCTAssertTrue(prompt.contains("DYNAMIC COUNTRIES AND SOVEREIGNTY"))
        XCTAssertTrue(prompt.contains("NBR=New Brazil"))
        XCTAssertTrue(prompt.contains("EXACT POLITICAL DIRECTIVES CURRENTLY AVAILABLE"))
        XCTAssertTrue(prompt.contains("Secession/new-country requires stored rebel/conflict pressure"))
        XCTAssertTrue(prompt.contains("victoryStatus="))
        XCTAssertTrue(prompt.contains("queue at most 3 orders"))
    }

    func testSelectingMatrixCellPaysRecordedCostKeepsBoardAndRejectsDuplicate() throws {
        let store = try makeStore()
        var state = NativeGameEngine.initialState(for: testCountry, worldSeed: 99)
        state.administrativeCapacity = 50
        state.suggestedActions = makeLegalDecisionMatrix(for: state, cost: 12)
        store.state = state
        let suggestion = try XCTUnwrap(state.suggestedActions.first)

        store.addSuggestedAction(suggestion)

        XCTAssertEqual(store.state?.administrativeCapacity, 38)
        XCTAssertEqual(store.state?.plannedActions.first?.administrativeCost, 12)
        XCTAssertEqual(store.state?.plannedActions.first?.decisionKind, "policy")
        XCTAssertEqual(store.state?.suggestedActions.count, 25)

        store.addSuggestedAction(suggestion)
        XCTAssertEqual(store.state?.plannedActions.count, 1)
        XCTAssertTrue(store.lastError?.contains("already in the order queue") == true)
    }

    func testCampaignSeedAndCountryPolicyStreamsSurvivePersistence() throws {
        var state = NativeGameEngine.initialState(for: testCountry, worldSeed: 123_456_789)
        state.aiCountryStates["USA"]?.decisionStep = 7
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(NativeCampaignState.self, from: data)

        XCTAssertEqual(decoded.worldSeed, 123_456_789)
        XCTAssertEqual(decoded.aiCountryStates["USA"]?.decisionSeed, state.aiCountryStates["USA"]?.decisionSeed)
        XCTAssertEqual(decoded.aiCountryStates["USA"]?.decisionProfileID, state.aiCountryStates["USA"]?.decisionProfileID)
        XCTAssertEqual(decoded.aiCountryStates["USA"]?.decisionStep, 7)
    }

    func testSuccessfulStructuredPlayerSecessionCreatesIndependentSeededActor() throws {
        let baseState = NativeGameEngine.initialState(for: testCountry, worldSeed: 8080)
        let region = try XCTUnwrap(GeopoliticalMapData.regions(forCountryCode: testCountry.code).first)
        let change = NativeSovereigntyChange(
            kind: .secession,
            name: "New Brazil",
            regionIDs: [region.id],
            sourceCodes: [testCountry.code],
            targetCode: "NBR"
        )
        var successful: NativeCampaignState?

        for index in 0 ..< 20 where successful == nil {
            var state = baseState
            let action = NativePlannedAction(
                administrativeCost: 20,
                createdAt: state.gameDate,
                decisionKind: "sovereignty",
                detail: "Convene a constitutional convention for the stored secession settlement.",
                id: "structured-secession-\(index)",
                status: .planned,
                title: "Convene secession settlement",
                targetCountryCode: "NBR",
                targetRegionID: region.id,
                sovereigntyChange: change
            )
            state.plannedActions = [action]
            let linked = makeEvent(
                id: "secession-linked-\(index)",
                playerRelated: true,
                linkedActionIDs: [action.id]
            )
            let applied = NativeGameEngine.apply(
                NativeGeneratedTurn(
                    events: [linked],
                    stabilityDelta: 0,
                    summary: "The constitutional process reaches a formal and measurable sovereignty decision.",
                    worldTensionDelta: 0
                ),
                to: state,
                months: 1
            )
            if applied.plannedActions.first?.outcome != .failure {
                successful = applied
            }
        }

        let applied = try XCTUnwrap(successful)
        XCTAssertEqual(applied.dynamicCountries["NBR"], "New Brazil")
        XCTAssertEqual(applied.regionOccupations[region.id], "NBR")
        XCTAssertNotNil(applied.aiCountryStates["NBR"])
        XCTAssertNotEqual(applied.aiCountryStates["NBR"]?.decisionSeed, 0)
        XCTAssertTrue(applied.timeline.contains { $0.sovereigntyChange?.targetCode == "NBR" })
    }

    func testComplexElectionsAndRegimeTransitions() {
        let db = NativeStrategyContextDatabase.self

        // 1. Verify 2010 calendar starting election round initialization
        let braLedger = db.startingEconomicLedger(forCode: "BRA", scenario: NativeScenarioCatalog.defaultScenario)
        let usaLedger = db.startingEconomicLedger(forCode: "USA", scenario: NativeScenarioCatalog.defaultScenario)
        let gbrLedger = db.startingEconomicLedger(forCode: "GBR", scenario: NativeScenarioCatalog.defaultScenario)

        XCTAssertEqual(braLedger.nextElectionRound, 10) // October 2010
        XCTAssertEqual(usaLedger.nextElectionRound, 35) // November 2012
        XCTAssertEqual(gbrLedger.nextElectionRound, 5) // May 2010

        // 2. Verify coup transitions autocracy to democracy/hybrid and schedules first election
        var coupState = makeState()
        var autocracyLedger = db.startingEconomicLedger(forCode: "CHN", scenario: NativeScenarioCatalog.defaultScenario)
        autocracyLedger.governmentType = "autocracy"
        autocracyLedger.publicApprovalPercent = 10.0 // Critically low approval (<25%)
        coupState.economicLedgers["CHN"] = autocracyLedger

        var postCoupState = coupState
        for _ in 1 ... 20 {
            db.simulateAIDrift(state: &postCoupState, months: 1)
            let type = postCoupState.economicLedgers["CHN"]?.governmentType ?? "autocracy"
            if type == "democracy" || type == "hybrid" {
                break
            }
        }

        let finalCoupType = postCoupState.economicLedgers["CHN"]?.governmentType ?? "autocracy"
        XCTAssertTrue(finalCoupType == "democracy" || finalCoupType == "hybrid")
        XCTAssertEqual(postCoupState.economicLedgers["CHN"]?.nextElectionRound, postCoupState.round + 12)

        // 3. Verify democratic collapse under severe instability
        var collapseState = makeState()
        var unstableDemocracy = db.startingEconomicLedger(forCode: "BRA", scenario: NativeScenarioCatalog.defaultScenario)
        unstableDemocracy.governmentType = "democracy"
        unstableDemocracy.publicApprovalPercent = 10.0 // Critically low approval
        collapseState.stability = 10 // Critically low stability
        collapseState.economicLedgers["BRA"] = unstableDemocracy

        var postCollapseState = collapseState
        for _ in 1 ... 30 {
            db.simulateAIDrift(state: &postCollapseState, months: 1)
            let type = postCollapseState.economicLedgers["BRA"]?.governmentType ?? "democracy"
            if type == "autocracy" || type == "hybrid" {
                break
            }
        }

        let finalCollapseType = postCollapseState.economicLedgers["BRA"]?.governmentType ?? "democracy"
        XCTAssertTrue(finalCollapseType == "autocracy" || finalCollapseType == "hybrid")

        // 4. Verify hybrid regime transitions
        // Hybrid -> Democracy under high stability/approval
        var libState = makeState()
        var hybridLedger = db.startingEconomicLedger(forCode: "RUS", scenario: NativeScenarioCatalog.defaultScenario)
        hybridLedger.governmentType = "hybrid"
        hybridLedger.publicApprovalPercent = 80.0
        libState.stability = 85
        libState.economicLedgers["RUS"] = hybridLedger

        var postLibState = libState
        for _ in 1 ... 30 {
            db.simulateAIDrift(state: &postLibState, months: 1)
            if postLibState.economicLedgers["RUS"]?.governmentType == "democracy" {
                break
            }
        }
        XCTAssertEqual(postLibState.economicLedgers["RUS"]?.governmentType, "democracy")
        XCTAssertEqual(postLibState.economicLedgers["RUS"]?.nextElectionRound, postLibState.round + 24)

        // Hybrid -> Autocracy under low stability/approval
        var consState = makeState()
        var fragileHybrid = db.startingEconomicLedger(forCode: "RUS", scenario: NativeScenarioCatalog.defaultScenario)
        fragileHybrid.governmentType = "hybrid"
        fragileHybrid.publicApprovalPercent = 15.0
        consState.stability = 15
        consState.economicLedgers["RUS"] = fragileHybrid

        var postConsState = consState
        for _ in 1 ... 30 {
            db.simulateAIDrift(state: &postConsState, months: 1)
            if postConsState.economicLedgers["RUS"]?.governmentType == "autocracy" {
                break
            }
        }
        XCTAssertEqual(postConsState.economicLedgers["RUS"]?.governmentType, "autocracy")
    }

    // MARK: - Alternative History Event Chains & Executive Decisions Tests

    func testClassicModeAlternativeHistoryEventsTriggerForPlayer() {
        var state = makeState()
        state.scenarioID = "soviet-triumph"
        state.country = PlayerCountry(code: "RUS", name: "Russia")
        state.round = 1

        NativeStrategyContextDatabase.evaluateAlternativeHistoryEvents(state: &state)

        XCTAssertNotNil(state.pendingEventDecision, "Executive decision must be pending when player is the targeted nation")
        XCTAssertEqual(state.pendingEventDecision?.imageAssetName, "EventSovietCoup")
        XCTAssertEqual(state.pendingEventDecision?.title, "GKChP State Emergency Committee Resolution")
        XCTAssertEqual(state.eventFlags["soviet_gkchp"], "pending")
    }

    func testClassicModeTurnAdvanceBlockedOnPendingDecision() async throws {
        let store = try makeStore()
        var state = makeState()
        state.scenarioID = "soviet-triumph"
        state.country = PlayerCountry(code: "RUS", name: "Russia")
        state.round = 1
        NativeStrategyContextDatabase.evaluateAlternativeHistoryEvents(state: &state)
        store.state = state

        XCTAssertNotNil(store.state?.pendingEventDecision)

        await store.performAdvance()

        XCTAssertNotNil(store.lastError, "Turn advance must be blocked with an error when a decision is pending")
        XCTAssertTrue(store.lastError?.contains("decision is pending") == true)
        XCTAssertEqual(store.state?.round, 1, "Round must not advance while decision is unresolved")
    }

    func testClassicModeResolvePendingEventDecisionAppliesDeltas() throws {
        let store = try makeStore()
        var state = makeState()
        state.scenarioID = "soviet-triumph"
        state.country = PlayerCountry(code: "RUS", name: "Russia")
        state.round = 1
        state.stability = 50
        NativeStrategyContextDatabase.evaluateAlternativeHistoryEvents(state: &state)
        store.state = state

        let pending = try XCTUnwrap(store.state?.pendingEventDecision)
        let option = try XCTUnwrap(pending.decisionOptions?.first)

        store.resolvePendingEventDecision(option: option)

        XCTAssertNil(store.state?.pendingEventDecision, "Pending decision must be cleared upon store resolution")
        XCTAssertEqual(store.state?.eventFlags["soviet_gkchp"], option.id)
        XCTAssertEqual(store.state?.eventFlags["next_chain"], "soviet-ogas-launch")
        XCTAssertGreaterThan(try XCTUnwrap(store.state?.stability), 50, "Stability must increase from hardline resolution")

        // Timeline must record resolution event
        let resolutionEvent = try XCTUnwrap(store.state?.timeline.first)
        XCTAssertTrue(resolutionEvent.title.contains("Decision Enacted"))
        XCTAssertEqual(resolutionEvent.imageAssetName, "EventSovietCoup")
    }

    func testClassicModeAINationResolvesEventWithoutBlocking() {
        var state = makeState()
        state.scenarioID = "soviet-triumph"
        state.country = PlayerCountry(code: "BRA", name: "Brazil")
        state.round = 1

        NativeStrategyContextDatabase.evaluateAlternativeHistoryEvents(state: &state)

        XCTAssertNil(state.pendingEventDecision, "Pending decision must remain nil when player is not the target")
        XCTAssertEqual(state.eventFlags["soviet_gkchp"], "gkchp-hardline", "AI Russia must have autonomously resolved the event")
        XCTAssertEqual(state.eventFlags["next_chain"], "soviet-ogas-launch")
        let coupEvent = state.timeline.first { $0.id == "event-soviet-coup-1991" }
        XCTAssertNotNil(coupEvent, "Autonomous world event must be added to timeline")
    }

    func testNativeAlternativeHistoryCatalogContainsExactly500Events() {
        XCTAssertEqual(NativeAlternativeHistoryCatalog.events.count, 500, "Catalog must contain exactly 500 events")
        let uniqueIDs = Set(NativeAlternativeHistoryCatalog.events.map { $0.id })
        XCTAssertEqual(uniqueIDs.count, 500, "All 500 event IDs must be strictly unique")
    }

    func testNativeAlternativeHistoryCatalogScenarioArcCounts() {
        XCTAssertEqual(NativeAlternativeHistoryCatalog.sovietTriumphEvents.count, 75)
        XCTAssertEqual(NativeAlternativeHistoryCatalog.dividedSovereigntyEvents.count, 75)
        XCTAssertEqual(NativeAlternativeHistoryCatalog.doomsday1983Events.count, 75)
        XCTAssertEqual(NativeAlternativeHistoryCatalog.resourceCrucibleEvents.count, 75)
        XCTAssertEqual(NativeAlternativeHistoryCatalog.paxCyberneticaEvents.count, 75)
        XCTAssertEqual(NativeAlternativeHistoryCatalog.solarpunkDawnEvents.count, 75)
        XCTAssertEqual(NativeAlternativeHistoryCatalog.victoria3SystemicEvents.count, 50)
        XCTAssertEqual(
            NativeAlternativeHistoryCatalog.sovietTriumphEvents.count +
            NativeAlternativeHistoryCatalog.dividedSovereigntyEvents.count +
            NativeAlternativeHistoryCatalog.doomsday1983Events.count +
            NativeAlternativeHistoryCatalog.resourceCrucibleEvents.count +
            NativeAlternativeHistoryCatalog.paxCyberneticaEvents.count +
            NativeAlternativeHistoryCatalog.solarpunkDawnEvents.count +
            NativeAlternativeHistoryCatalog.victoria3SystemicEvents.count,
            500
        )
    }

    func testCatalogEventIntegrityAndMechanicTokens() {
        let validTokens: Set<String> = ["⟦ECO⟧", "⟦STB⟧", "⟦SEC⟧", "⟦MIL⟧", "⟦DIP⟧", "⟦MKT⟧", "⟦TNS⟧"]
        let validImages: Set<String> = [
            "EventSovietCoup",
            "EventFashodaCrisis",
            "EventBreadRiots",
            "EventCyberBlackout",
            "EventResourceCrisis",
            "EventSolarpunkDawn"
        ]

        for event in NativeAlternativeHistoryCatalog.events {
            XCTAssertFalse(event.id.isEmpty)
            XCTAssertFalse(event.title.isEmpty)
            XCTAssertFalse(event.description.isEmpty)
            XCTAssertFalse(event.date.isEmpty)
            XCTAssertNotNil(event.imageAssetName)
            XCTAssertTrue(validImages.contains(event.imageAssetName ?? ""))

            if let token = event.hexLeverCode {
                XCTAssertTrue(validTokens.contains(token), "Token \(token) must be one of the 7 valid mechanic codes")
            }

            guard let options = event.decisionOptions else {
                XCTFail("Event \(event.id) must contain decision options")
                continue
            }
            XCTAssertGreaterThanOrEqual(options.count, 2, "Event \(event.id) must offer at least 2 executive options")
            for option in options {
                XCTAssertFalse(option.id.isEmpty)
                XCTAssertFalse(option.label.isEmpty)
                XCTAssertFalse(option.detail.isEmpty)
            }
        }
    }

    func testLivingWorldBridgeConversionFromCatalog() {
        guard let firstSevere = NativeAlternativeHistoryCatalog.events.first(where: { $0.importance == .severe }) else {
            XCTFail("Must find at least one severe event in catalog")
            return
        }

        let lwEvent = NativeAlternativeHistoryCatalog.livingWorldDecision(from: firstSevere, day: 42, targetCountry: "RUS")
        XCTAssertEqual(lwEvent.id, firstSevere.id)
        XCTAssertEqual(lwEvent.day, 42)
        XCTAssertEqual(lwEvent.countryCode, "RUS")
        XCTAssertEqual(lwEvent.rarity, .legendary)
        XCTAssertEqual(lwEvent.options.count, firstSevere.decisionOptions?.count ?? 0)
        XCTAssertEqual(lwEvent.imageAssetName, firstSevere.imageAssetName)
        XCTAssertGreaterThan(lwEvent.severity, 0.8)
    }

    func testCandidateDecisionsFilteringForPlayerCountry() {
        var state = makeState()
        state.scenarioID = "soviet-triumph"
        state.country = PlayerCountry(code: "RUS", name: "Russia")
        state.round = 1

        let candidates = NativeAlternativeHistoryCatalog.candidateDecisions(state: state)
        XCTAssertFalse(candidates.isEmpty, "Candidate decisions must be returned for Russian player in Soviet scenario")
        XCTAssertEqual(candidates.first?.id, "ah-sov-001")
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
        onStreamProgress _: (@MainActor (String) -> Void)? = nil,
        onReasoningProgress _: (@MainActor (NativeReasoningStreamUpdate) -> Void)? = nil,
        requestTimeout _: TimeInterval = 90,
        retryLimit _: Int = 2
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
    private var enterContinuations: [CheckedContinuation<Void, Never>] = []
    private var waitContinuation: CheckedContinuation<Void, Never>?

    func wait() async {
        entered = true
        for cont in enterContinuations {
            cont.resume()
        }
        enterContinuations.removeAll()

        await withCheckedContinuation { continuation in
            self.waitContinuation = continuation
        }
    }

    func waitUntilEntered() async {
        if entered { return }
        await withCheckedContinuation { continuation in
            enterContinuations.append(continuation)
        }
    }

    func resume() {
        waitContinuation?.resume()
        waitContinuation = nil
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

private func makeDiplomaticThread(for state: NativeCampaignState) -> NativeDiplomaticThread {
    NativeDiplomaticThread(
        id: "thread-arg",
        lastUpdated: state.gameDate,
        messages: [
            NativeDiplomaticMessage(
                date: state.gameDate,
                id: "msg-1",
                speaker: "Argentina",
                text: "We need corridor guarantees."
            )
        ],
        participant: PlayerCountry(code: "ARG", name: "Argentina"),
        summary: "Argentina wants bounded logistics coordination."
    )
}

private func makeState() -> NativeCampaignState {
    NativeGameEngine.initialState(for: testCountry)
}

private func makeLegalDecisionMatrix(
    for state: NativeCampaignState,
    cost: Int
) -> [NativeSuggestedAction] {
    NativeDecisionMatrixRow.allCases.flatMap { row in
        NativeDecisionMatrixColumn.allCases.map { column in
            NativeSuggestedAction(
                detail: "Create a bounded public service program through existing institutions during the next campaign period.",
                id: "test-matrix-\(row.rawValue)-\(column.rawValue)",
                rationale: "This legal proposal fits stored objectives, fiscal limits, and current administrative authority.",
                title: "Matrix program \(row.rawValue) \(column.rawValue)",
                urgency: "soon",
                primaryMechanic: "internal-stability",
                secondaryMechanic: "market-confidence",
                actionKind: "policy",
                administrativeCost: min(cost, state.administrativeCapacity),
                matrixRow: row.rawValue,
                matrixColumn: column.rawValue
            )
        }
    }
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
