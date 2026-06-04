import XCTest
@testable import Pax_Historia

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
        XCTAssertLessThanOrEqual(applied.timeline.count, 80)
        XCTAssertLessThanOrEqual(applied.worldEffects.count, 160)
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
            onSelect: store.choose
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
    }

    private var liveFoundationModelsGateEnabled: Bool {
        #if PAX_HISTORIA_RUN_LIVE_FOUNDATION_MODELS
        return true
        #else
        return ProcessInfo.processInfo.environment["PAX_HISTORIA_RUN_LIVE_FOUNDATION_MODELS"] == "1"
        #endif
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
