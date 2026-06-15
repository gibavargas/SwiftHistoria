import XCTest
@testable import SwiftHistoria

@MainActor
final class NativeE2ETests: XCTestCase {

    private let testCountry = PlayerCountry(code: "USA", name: "United States")

    func testEndToEndGameSessionFlow() async throws {
        // 1. Initialize clean campaign store with temp directory
        let defaults = makeCleanDefaults()
        let persistenceDir = try makeTempPersistenceDir()
        let fakeAI = FakeE2EAIService()

        let store = NativeCampaignStore(
            defaults: defaults,
            aiService: fakeAI,
            persistenceDirectory: persistenceDir
        )

        // 2. Select scenario and verify initial setup
        store.selectScenario(id: NativeScenarioCatalog.defaultScenario.id)
        XCTAssertEqual(store.selectedScenarioID, NativeScenarioCatalog.defaultScenario.id)

        // Choose country and wait for suggestions to prevent race conditions on stateVersion
        store.choose(testCountry)
        while store.isLoadingSuggestions {
            await Task.yield()
        }

        XCTAssertNotNil(store.state)
        guard let initialState = store.state else {
            XCTFail("Store failed to initialize campaign state")
            return
        }

        // 3. Assert Turn 1 State initialization
        XCTAssertEqual(initialState.round, 1)
        XCTAssertEqual(initialState.country.code, "USA")
        XCTAssertEqual(initialState.economicLedgers.count, 245)

        let expectedStability = Native2010WorldModel.stability(for: testCountry, scenario: NativeScenarioCatalog.defaultScenario)
        let expectedWorldTension = Native2010WorldModel.worldTension(for: testCountry, scenario: NativeScenarioCatalog.defaultScenario)

        XCTAssertEqual(initialState.stability, expectedStability)
        XCTAssertEqual(initialState.worldTension, expectedWorldTension)

        // Verify ledger properties exist
        let initialUSALedger = try XCTUnwrap(initialState.economicLedgers["USA"])
        XCTAssertEqual(initialUSALedger.nominalGDPTrillions, 14.99, accuracy: 0.1)

        // 4. Create and queue a planned civic proposal
        store.draftAction = "Launch regional energy and transport corridor optimization project."
        store.addDraftAction()

        let stateWithAction = try XCTUnwrap(store.state)
        XCTAssertEqual(stateWithAction.plannedActions.count, 1)
        let plannedAction = try XCTUnwrap(stateWithAction.plannedActions.first)
        XCTAssertEqual(plannedAction.status, .planned)

        // Set up fake AI to generate a turn resolving this action and including a hex lever code
        fakeAI.nextTurnEvents = [
            NativeCampaignEvent(
                date: stateWithAction.gameDate,
                description: "The transport corridor project resolves successfully with infrastructure optimization across the state.",
                id: "event-corridor",
                importance: .major,
                kind: .action,
                linkedActionIDs: [plannedAction.id],
                notable: true,
                playerRelated: true,
                strategicEffects: [
                    NativeStrategicEffect(
                        date: stateWithAction.gameDate,
                        eventId: "event-corridor",
                        id: "effect-corridor-1",
                        magnitude: 2,
                        summary: "Infrastructure corridor optimization directly boosts GDP growth.",
                        target: "USA",
                        track: .economicResilience
                    )
                ],
                title: "Corridor Optimization Complete",
                hexLeverCode: "0x4D21F4" // Growth +0.4%, Budget -0.15%, Debt +0.4%, Inflation +0.05%, Trade -0.05%, Fiscal Space +4
            ),
            NativeCampaignEvent(
                date: stateWithAction.gameDate,
                description: "Global shipping volumes stabilize as cargo backlogs clear completely around the major ports.",
                id: "event-global-independent",
                importance: .minor,
                kind: .world,
                linkedActionIDs: [],
                notable: false,
                playerRelated: false,
                strategicEffects: [
                    NativeStrategicEffect(
                        date: stateWithAction.gameDate,
                        eventId: "event-global-independent",
                        id: "effect-global-independent-1",
                        magnitude: 1,
                        summary: "Global trade market conditions stabilize slightly.",
                        target: "International system",
                        track: .marketConfidence
                    )
                ],
                title: "Global Supply Chain Stability"
            )
        ]

        // 5. Advance turn (simulating turn advance)
        await store.advance(months: 3)

        if let lastError = store.lastError {
            print("E2E Test Advance Failed Error: \(lastError)")
        }

        let stateTurn2 = try XCTUnwrap(store.state)
        XCTAssertEqual(stateTurn2.round, 2)
        XCTAssertEqual(stateTurn2.gameDate, "2010-04-15") // advanced 3 months from 2010-01-15

        // Verify action is resolved
        let resolvedAction = try XCTUnwrap(stateTurn2.plannedActions.first { $0.id == plannedAction.id })
        XCTAssertEqual(resolvedAction.status, .resolved)
        XCTAssertEqual(resolvedAction.resolvedAt, "2010-04-15")

        // Verify action memory is updated
        XCTAssertTrue(stateTurn2.actionMemory.contains { $0.actionID == plannedAction.id && $0.status == .resolved })

        // Verify hex lever and background stochastic drift applied to USA ledger
        let usaLedgerTurn2 = try XCTUnwrap(stateTurn2.economicLedgers["USA"])
        XCTAssertFalse(usaLedgerTurn2.entries.isEmpty, "USA ledger should contain entries")

        // Verify that background stochastic drift also updated non-targeted polities (e.g. Brazil)
        let braLedgerTurn2 = try XCTUnwrap(stateTurn2.economicLedgers["BRA"])
        XCTAssertNotEqual(braLedgerTurn2.realGrowthPercent, initialState.economicLedgers["BRA"]?.realGrowthPercent)

        // 6. Test Advisor Brief generation
        store.draftAdvisorQuestion = "Should we prioritize trade or domestic stability?"
        await store.askAdvisor()

        let stateAdvisor = try XCTUnwrap(store.state)
        XCTAssertTrue(stateAdvisor.advisorMessages.contains { $0.role == .advisor && $0.text.contains("E2E Advisor Advice") })

        // 7. Test Diplomatic Chat flow
        let partner = try XCTUnwrap(CountryCatalog.all.first { $0.code == "CHN" })
        store.selectedDiplomaticPartnerCode = partner.code
        store.draftDiplomaticMessage = "Initiate transport coordination discussions."
        await store.sendDiplomaticMessage()

        let stateDiplomacy = try XCTUnwrap(store.state)
        let chnThread = try XCTUnwrap(stateDiplomacy.diplomaticThreads.first { $0.participant.code == "CHN" })
        XCTAssertTrue(chnThread.messages.contains { $0.speaker == partner.name && $0.text.contains("E2E Diplomatic Response") })

        // 8. Test Export, Clean Reset, and Import (Persistence Recovery)
        let exportedData = try store.exportCampaignData()
        XCTAssertFalse(exportedData.isEmpty)

        // Initialize an entirely new store with a different clean folder
        let otherDefaults = makeCleanDefaults()
        let otherPersistenceDir = try makeTempPersistenceDir()
        let otherStore = NativeCampaignStore(
            defaults: otherDefaults,
            aiService: fakeAI,
            persistenceDirectory: otherPersistenceDir
        )

        // Import campaign data
        try otherStore.importCampaignData(exportedData)

        // Assert that the state matches the exported store state exactly
        let importedState = try XCTUnwrap(otherStore.state)
        XCTAssertEqual(importedState.round, stateDiplomacy.round)
        XCTAssertEqual(importedState.gameDate, stateDiplomacy.gameDate)
        XCTAssertEqual(importedState.country.code, stateDiplomacy.country.code)
        XCTAssertEqual(importedState.stability, stateDiplomacy.stability)
        XCTAssertEqual(importedState.worldTension, stateDiplomacy.worldTension)
        XCTAssertEqual(importedState.plannedActions.count, stateDiplomacy.plannedActions.count)
        XCTAssertEqual(importedState.actionMemory.count, stateDiplomacy.actionMemory.count)
        XCTAssertEqual(importedState.advisorMessages.count, stateDiplomacy.advisorMessages.count)
        XCTAssertEqual(importedState.diplomaticThreads.count, stateDiplomacy.diplomaticThreads.count)

        // Verify ledger matches exactly
        let importedUSALedger = try XCTUnwrap(importedState.economicLedgers["USA"])
        XCTAssertEqual(importedUSALedger.nominalGDPTrillions, usaLedgerTurn2.nominalGDPTrillions, accuracy: 0.0001)
        XCTAssertEqual(importedUSALedger.realGrowthPercent, usaLedgerTurn2.realGrowthPercent, accuracy: 0.0001)

        // 9. Advance another turn in the imported store to ensure operational continuity
        fakeAI.nextTurnEvents = [
            NativeCampaignEvent(
                date: importedState.gameDate,
                description: "Subsequent external market developments stabilize trade corridors and shipping routes.",
                id: "event-external-2",
                importance: .minor,
                kind: .world,
                linkedActionIDs: [],
                notable: true,
                playerRelated: false,
                strategicEffects: [
                    NativeStrategicEffect(
                        date: importedState.gameDate,
                        eventId: "event-external-2",
                        id: "effect-external-2-1",
                        magnitude: 1,
                        summary: "Global trade markets stabilize significantly.",
                        target: "International system",
                        track: .marketConfidence
                    )
                ],
                title: "External Market Stabilization"
            )
        ]

        await otherStore.advance(months: 1)

        let finalState = try XCTUnwrap(otherStore.state)
        XCTAssertEqual(finalState.round, 3)
        XCTAssertEqual(finalState.gameDate, "2010-05-15") // advanced 1 month
        XCTAssertTrue(finalState.timeline.contains { $0.id == "event-external-2" })
    }

    // Helpers
    private func makeCleanDefaults() -> UserDefaults {
        let suiteName = "NativeE2ETests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func makeTempPersistenceDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("PaxHistoriaNativeE2ETests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

@MainActor
private final class FakeE2EAIService: NativeAIService {
    var nextTurnEvents: [NativeCampaignEvent] = []

    func checkReadiness() async -> NativeAIReadiness {
        .available(tokenBudget: "fake-e2e")
    }

    func generateTurn(for state: NativeCampaignState, months: Int) async throws -> NativeGeneratedTurn {
        NativeGeneratedTurn(
            events: nextTurnEvents.isEmpty ? [
                NativeCampaignEvent(
                    date: state.gameDate,
                    description: "Standard player-related domestic e2e background updates have been successfully processed for this turn.",
                    id: "default-player-e2e-\(state.round)",
                    importance: .minor,
                    kind: .action,
                    linkedActionIDs: [],
                    notable: false,
                    playerRelated: true,
                    strategicEffects: [
                        NativeStrategicEffect(
                            date: state.gameDate,
                            eventId: "default-player-e2e-\(state.round)",
                            id: "default-player-e2e-effect-\(state.round)",
                            magnitude: 1,
                            summary: "A minor domestic stability shift occurs during this turn.",
                            target: state.country.name,
                            track: .internalStability
                        )
                    ],
                    title: "Standard Domestic E2E Update"
                ),
                NativeCampaignEvent(
                    date: state.gameDate,
                    description: "Standard external market e2e background updates have been successfully processed for this turn.",
                    id: "default-e2e-\(state.round)",
                    importance: .minor,
                    kind: .world,
                    linkedActionIDs: [],
                    notable: false,
                    playerRelated: false,
                    strategicEffects: [
                        NativeStrategicEffect(
                            date: state.gameDate,
                            eventId: "default-e2e-\(state.round)",
                            id: "default-e2e-effect-\(state.round)",
                            magnitude: 1,
                            summary: "A minor market confidence shift occurs during this turn.",
                            target: "International system",
                            track: .marketConfidence
                        )
                    ],
                    title: "Standard E2E Market Readjustment"
                )
            ] : nextTurnEvents,
            stabilityDelta: 2,
            summary: "The E2E turn simulation has completed successfully.",
            worldTensionDelta: -1
        )
    }

    func generateSuggestedActions(for state: NativeCampaignState) async throws -> [NativeSuggestedAction] {
        [
            NativeSuggestedAction(detail: "E2E suggested action detail.", id: "sug-e2e-1", rationale: "E2E suggestion rationale.", title: "E2E Suggested Action", urgency: "soon")
        ]
    }

    func generateAdvisorBrief(for state: NativeCampaignState, question: String) async throws -> String {
        "E2E Advisor Advice: Prioritize transport corridors to bolster growth."
    }

    func generateDiplomaticReply(for state: NativeCampaignState, thread: NativeDiplomaticThread, message: String) async throws -> String {
        "E2E Diplomatic Response: China welcomes corridor integration discussions."
    }
}
