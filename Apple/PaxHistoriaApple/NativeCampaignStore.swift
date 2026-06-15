import Foundation
import OSLog

/// Main actor owner for native campaign state.
///
/// **State Flow Mechanic**: 
/// SwiftUI views MUST NOT mutate `NativeCampaignState` directly. Instead, views call methods on this store.
/// The store centralizes all business logic and state transitions:
/// View Action -> Store Method -> (Optional Async AI Call) -> Engine Validation -> State Mutation -> `persistState()` -> @Published UI Update.
/// This single-directional data flow ensures that every user-visible mutation is validated, persisted, and safely synchronized with the UI.
@MainActor
final class NativeCampaignStore: ObservableObject {
    @Published private(set) var selectedCountry: PlayerCountry?
    @Published private(set) var selectedLanguage: NativeGameLanguage
    @Published private(set) var selectedScenarioID: String
    @Published var state: NativeCampaignState?
    @Published var draftAction = ""
    @Published var draftAdvisorQuestion = ""
    @Published var draftDiplomaticMessage = ""
    @Published var selectedDiplomaticPartnerCode = ""
    @Published private(set) var isAdvancing = false
    @Published private(set) var isLoadingAdvisor = false
    @Published private(set) var isLoadingDiplomacy = false
    @Published private(set) var isLoadingSuggestions = false
    @Published private(set) var lastAdvisorError: String?
    @Published private(set) var lastDiplomacyError: String?
    @Published private(set) var lastError: String?
    @Published private(set) var lastRecoveryNotice: String?
    @Published private(set) var lastSuggestionError: String?
    @Published private(set) var turnProgress: NativeTurnProgress?
    @Published var lastTurnReport: NativeGeneratedTurn? = nil

    private let defaults: UserDefaults
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let aiService: any NativeAIService
    private let persistenceDirectory: URL
    private let logger = Logger(subsystem: "com.gibavargas.SwiftHistoria", category: "NativeCampaignStore")
    // **Concurrency & Asynchrony Mechanic**:
    // `stateVersion` prevents async race conditions (stale-response rejection).
    // Incremented (`invalidateInFlightWork()`) whenever local state changes in a way that makes in-flight AI work obsolete.
    // Async methods (like `advance(months:)` or `askAdvisor()`) capture this value before awaiting the AI service.
    // After the await resumes, they check if `stateVersion` is still the same. If it changed (e.g. the user clicked "Reset" or advanced again),
    // the stale result is dropped and not applied to the state, preventing ghost mutations.
    private var stateVersion = 0

    private static let selectedCountryKey = "pax-historia.native.selected-country.v1"
    private static let selectedLanguageKey = "pax-historia.native.selected-language.v1"
    private static let selectedScenarioKey = "pax-historia.native.selected-scenario.v1"
    private static let campaignStateKey = "pax-historia.native.campaign-state.v1"
    private static let campaignStateEnvelopeKey = "pax-historia.native.campaign-state-envelope.v2"
    private static let campaignStateBackupKey = "pax-historia.native.campaign-state-backup.v2"
    private static let campaignStateEnvelopeFileName = "campaign-state-envelope-v2.json"
    private static let campaignStateBackupFileName = "campaign-state-backup-v2.json"
    private static let campaignStateLegacyFileName = "campaign-state-legacy-v1.json"

    private static var uiTestResetRequested: Bool {
        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        let arguments = ProcessInfo.processInfo.arguments
        return environment["PAX_HISTORIA_UI_TEST_RESET"] == "1" || arguments.contains("--pax-historia-ui-test-reset")
        #else
        return false
        #endif
    }

    private static func removePersistedCampaignState(defaults: UserDefaults, persistenceDirectory: URL) {
        defaults.removeObject(forKey: selectedCountryKey)
        defaults.removeObject(forKey: selectedLanguageKey)
        defaults.removeObject(forKey: selectedScenarioKey)
        defaults.removeObject(forKey: campaignStateKey)
        defaults.removeObject(forKey: campaignStateEnvelopeKey)
        defaults.removeObject(forKey: campaignStateBackupKey)

        for fileName in [campaignStateEnvelopeFileName, campaignStateBackupFileName, campaignStateLegacyFileName] {
            try? FileManager.default.removeItem(at: persistenceDirectory.appendingPathComponent(fileName))
        }
    }

    private struct CampaignLoadResult {
        let state: NativeCampaignState?
        let notice: String?
    }

    /// Versioned save wrapper. The raw `NativeCampaignState` is still mirrored
    /// as a legacy fallback, but the envelope is the primary format because it
    /// gives future migrations an explicit schema boundary.
    private struct CampaignStateEnvelope: Codable {
        let schemaVersion: Int
        let savedAt: String
        let state: NativeCampaignState
    }

    private struct PersistenceDataSource {
        let data: Data
        let label: String
    }

    init(
        defaults: UserDefaults = .standard,
        aiService: any NativeAIService = DynamicAIService(),
        persistenceDirectory: URL? = nil
    ) {
        let decoder = JSONDecoder()
        self.defaults = defaults
        self.encoder = JSONEncoder()
        self.decoder = decoder
        self.aiService = aiService
        self.persistenceDirectory = persistenceDirectory ?? Self.defaultPersistenceDirectory()
        #if DEBUG
        if Self.uiTestResetRequested {
            Self.removePersistedCampaignState(defaults: defaults, persistenceDirectory: self.persistenceDirectory)
        }
        #endif
        selectedCountry = Self.loadSelectedCountry(from: defaults, decoder: decoder)
        let loadResult = Self.loadCampaignState(
            from: defaults,
            decoder: decoder,
            persistenceDirectory: self.persistenceDirectory
        )
        let loadedState = loadResult.state.map(Self.normalizedLoadedState)
        state = loadedState
        lastRecoveryNotice = loadResult.notice
        selectedLanguage = NativeGameLanguage.normalized(defaults.string(forKey: Self.selectedLanguageKey) ?? loadedState?.language.rawValue)
        selectedScenarioID = Self.normalizedScenarioID(defaults.string(forKey: Self.selectedScenarioKey) ?? loadedState?.scenarioID)

        if let selectedCountry, state == nil {
            state = NativeGameEngine.initialState(for: selectedCountry, scenario: selectedScenario, language: selectedLanguage)
            persistState()
        } else if selectedCountry == nil, let state {
            selectedCountry = state.country
            selectedLanguage = state.language
            selectedScenarioID = Self.normalizedScenarioID(state.scenarioID)
        }
        selectedDiplomaticPartnerCode = Self.defaultDiplomaticPartnerCode(for: state)
        logger.info("Native campaign store initialized hasState=\(self.state != nil, privacy: .public)")
    }

    var selectedScenario: NativeScenario {
        NativeScenarioCatalog.scenario(for: selectedScenarioID)
    }

    func setLanguage(_ language: NativeGameLanguage) {
        guard selectedLanguage != language || state?.language != language else { return }
        invalidateInFlightWork()
        selectedLanguage = language
        defaults.set(language.rawValue, forKey: Self.selectedLanguageKey)
        logger.info("Native campaign language changed language=\(language.rawValue, privacy: .public)")
        lastAdvisorError = nil
        lastDiplomacyError = nil
        lastError = nil
        lastSuggestionError = nil

        guard var state else { return }
        state.language = language
        state.suggestedActions = []
        self.state = state
        persistState()
        Task { await refreshSuggestedActions(force: true) }
    }

    func selectScenario(id: String) {
        let scenario = NativeScenarioCatalog.scenario(for: id)
        invalidateInFlightWork()
        selectedScenarioID = scenario.id
        defaults.set(scenario.id, forKey: Self.selectedScenarioKey)
        logger.info("Native campaign scenario selected scenario=\(scenario.id, privacy: .public)")
        lastAdvisorError = nil
        lastDiplomacyError = nil
        lastError = nil
        lastRecoveryNotice = nil
        lastSuggestionError = nil
        lastTurnReport = nil
        turnProgress = nil

        if let selectedCountry {
            state = NativeGameEngine.initialState(for: selectedCountry, scenario: scenario, language: selectedLanguage)
            selectedDiplomaticPartnerCode = Self.defaultDiplomaticPartnerCode(for: state)
            persistState()
            Task { await refreshSuggestedActions(force: true) }
        }
    }

    func choose(_ country: PlayerCountry) {
        invalidateInFlightWork()
        selectedCountry = country
        state = NativeGameEngine.initialState(for: country, scenario: selectedScenario, language: selectedLanguage)
        logger.info("Native campaign country selected country=\(country.code, privacy: .public) scenario=\(self.selectedScenarioID, privacy: .public)")
        lastError = nil
        lastAdvisorError = nil
        lastDiplomacyError = nil
        lastRecoveryNotice = nil
        lastSuggestionError = nil
        lastTurnReport = nil
        turnProgress = nil
        selectedDiplomaticPartnerCode = Self.defaultDiplomaticPartnerCode(for: state)
        defaults.set(selectedLanguage.rawValue, forKey: Self.selectedLanguageKey)
        defaults.set(selectedScenarioID, forKey: Self.selectedScenarioKey)
        if let data = try? encoder.encode(country) {
            defaults.set(data, forKey: Self.selectedCountryKey)
        }
        persistState()
        Task { await refreshSuggestedActions(force: true) }
    }

    func resetSelection() {
        invalidateInFlightWork()
        selectedCountry = nil
        state = nil
        draftAction = ""
        draftAdvisorQuestion = ""
        draftDiplomaticMessage = ""
        selectedDiplomaticPartnerCode = ""
        lastAdvisorError = nil
        lastDiplomacyError = nil
        lastError = nil
        lastRecoveryNotice = nil
        lastSuggestionError = nil
        lastTurnReport = nil
        turnProgress = nil
        defaults.removeObject(forKey: Self.selectedCountryKey)
        defaults.removeObject(forKey: Self.campaignStateKey)
        defaults.removeObject(forKey: Self.campaignStateEnvelopeKey)
        defaults.removeObject(forKey: Self.campaignStateBackupKey)
        removePersistedCampaignFiles()
        logger.info("Native campaign selection reset")
    }

    func switchCountry(to newCountry: PlayerCountry) {
        guard var currentState = state else { return }
        invalidateInFlightWork()

        selectedCountry = newCountry
        currentState.country = newCountry

        if let existingLedger = currentState.economicLedgers[newCountry.code] {
            currentState.economicLedger = existingLedger
        } else {
            let scenario = NativeScenarioCatalog.scenario(for: currentState.scenarioID)
            let newLedger = NativeStrategyContextDatabase.startingEconomicLedger(for: newCountry, scenario: scenario)
            currentState.economicLedger = newLedger
            currentState.economicLedgers[newCountry.code] = newLedger
        }

        selectedDiplomaticPartnerCode = Self.defaultDiplomaticPartnerCode(for: currentState)
        currentState.lastSummary = "\(newCountry.name) leadership assumed. Turn intent into concrete plans."

        draftAction = ""
        draftAdvisorQuestion = ""
        draftDiplomaticMessage = ""

        self.state = currentState

        if let data = try? encoder.encode(newCountry) {
            defaults.set(data, forKey: Self.selectedCountryKey)
        }

        persistState()
        logger.info("Switched country to \(newCountry.code)")

        Task { await refreshSuggestedActions(force: true) }
    }

    func manualSaveCampaign() {
        persistState()
        lastRecoveryNotice = "Campaign manually saved successfully."
        logger.info("Campaign manually saved")
    }

    func exitToMainMenu() {
        invalidateInFlightWork()
        selectedCountry = nil
        defaults.removeObject(forKey: Self.selectedCountryKey)
        logger.info("Exited to main menu (campaign state retained for resume)")
    }

    func resumeActiveCampaign() {
        guard let state = state else { return }
        invalidateInFlightWork()
        selectedCountry = state.country
        selectedScenarioID = state.scenarioID
        selectedLanguage = state.language
        selectedDiplomaticPartnerCode = Self.defaultDiplomaticPartnerCode(for: state)
        if let data = try? encoder.encode(state.country) {
            defaults.set(data, forKey: Self.selectedCountryKey)
        }
        defaults.set(state.scenarioID, forKey: Self.selectedScenarioKey)
        defaults.set(state.language.rawValue, forKey: Self.selectedLanguageKey)
        logger.info("Resumed active campaign as \(state.country.code)")
    }

    func setGameMode(_ mode: NativeGameMode) {
        guard var currentState = state else { return }
        invalidateInFlightWork()
        currentState.gameMode = mode
        self.state = currentState
        persistState()
        logger.info("Game mode changed to \(mode.rawValue)")
    }

    var campaignExportFilename: String {
        let slug = [
            state?.scenarioID ?? selectedScenarioID,
            state?.country.code ?? "campaign",
            state?.gameDate ?? NativeGameEngine.todayStamp(),
        ]
            .map { $0.lowercased().replacingOccurrences(of: ":", with: "-") }
            .joined(separator: "-")
        return "pax-historia-\(slug).json"
    }

    func exportCampaignData() throws -> Data {
        guard let state else {
            throw NativeCampaignStoreError.noCampaignToExport
        }

        let exportEncoder = JSONEncoder()
        exportEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try exportEncoder.encode(state)
    }

    func importCampaignData(_ data: Data) throws {
        let imported = try decoder.decode(NativeCampaignState.self, from: data)
        let normalized = Self.normalizedLoadedState(imported)
        invalidateInFlightWork()
        selectedCountry = normalized.country
        selectedLanguage = normalized.language
        selectedScenarioID = Self.normalizedScenarioID(normalized.scenarioID)
        state = normalized
        draftAction = ""
        draftAdvisorQuestion = ""
        draftDiplomaticMessage = ""
        selectedDiplomaticPartnerCode = Self.defaultDiplomaticPartnerCode(for: state)
        lastAdvisorError = nil
        lastDiplomacyError = nil
        lastError = nil
        lastRecoveryNotice = nil
        lastSuggestionError = nil
        lastTurnReport = nil
        turnProgress = nil

        if let data = try? encoder.encode(normalized.country) {
            defaults.set(data, forKey: Self.selectedCountryKey)
        }
        defaults.set(selectedScenarioID, forKey: Self.selectedScenarioKey)
        defaults.set(selectedLanguage.rawValue, forKey: Self.selectedLanguageKey)
        persistState()
        logger.info("Native campaign imported bytes=\(data.count, privacy: .public) scenario=\(self.selectedScenarioID, privacy: .public)")
    }

    func addDraftAction() {
        guard var state else { return }
        let cost = NativeGameEngine.estimateDirectiveCost(for: draftAction)
        if state.administrativeCapacity < cost {
            lastError = "Insufficient administrative capacity. This directive requires \(cost) capacity."
            return
        }
        let action = NativeGameEngine.action(from: draftAction, date: state.gameDate)
        guard let action else { return }

        invalidateInFlightWork()
        state.administrativeCapacity -= cost
        state.plannedActions.insert(action, at: 0)
        state.actionMemory = NativeStrategyContextDatabase.remember(
            action: action,
            in: state.actionMemory,
            source: "manual",
            state: state
        )
        state.lastSummary = Self.plannedOrderSummary(for: action, language: state.language)
        self.state = state
        draftAction = ""
        persistState()
        logger.info("Native manual action added round=\(state.round, privacy: .public)")
    }

    func addSuggestedAction(_ suggestion: NativeSuggestedAction) {
        guard var state else { return }
        let cost = NativeGameEngine.estimateDirectiveCost(for: suggestion.detail)
        if state.administrativeCapacity < cost {
            lastError = "Insufficient administrative capacity. This suggestion requires \(cost) capacity."
            return
        }
        let detail = sanitizeFoundationModelText(suggestion.detail)
        guard !detail.isEmpty else { return }
        let title = sanitizeFoundationModelText(suggestion.title)
        guard !title.isEmpty, !containsFoundationPlaceholderText(title) else { return }

        let action = NativePlannedAction(
            createdAt: state.gameDate,
            detail: detail,
            id: "action-\(UUID().uuidString.lowercased())",
            resolvedAt: nil,
            status: .planned,
            title: title
        )
        invalidateInFlightWork()
        state.administrativeCapacity -= cost
        state.plannedActions.insert(action, at: 0)
        state.actionMemory = NativeStrategyContextDatabase.remember(
            action: action,
            in: state.actionMemory,
            source: "apple-suggestion",
            state: state
        )
        state.suggestedActions.removeAll { $0.id == suggestion.id }
        state.lastSummary = Self.acceptedSuggestionSummary(for: action, language: state.language)
        self.state = state
        persistState()
        logger.info("Native suggested action accepted round=\(state.round, privacy: .public)")
    }

    func deleteAction(id: String) {
        guard var state else { return }
        invalidateInFlightWork()
        if let idx = state.plannedActions.firstIndex(where: { $0.id == id }) {
            let action = state.plannedActions[idx]
            if action.status == .planned {
                let cost = NativeGameEngine.estimateDirectiveCost(for: action.detail)
                state.administrativeCapacity = min(100, state.administrativeCapacity + cost)
            }
            state.plannedActions.remove(at: idx)
        }
        state.actionMemory.removeAll { $0.actionID == id && $0.status == .planned }
        self.state = state
        persistState()
        logger.info("Native action deleted")
    }

    func deleteActions(at offsets: IndexSet) {
        guard var state else { return }
        invalidateInFlightWork()
        let removedIDs = offsets.compactMap { index in
            state.plannedActions.indices.contains(index) ? state.plannedActions[index].id : nil
        }
        for index in offsets.sorted(by: >) where state.plannedActions.indices.contains(index) {
            let action = state.plannedActions[index]
            if action.status == .planned {
                let cost = NativeGameEngine.estimateDirectiveCost(for: action.detail)
                state.administrativeCapacity = min(100, state.administrativeCapacity + cost)
            }
            state.plannedActions.remove(at: index)
        }
        state.actionMemory.removeAll { removedIDs.contains($0.actionID) && $0.status == .planned }
        self.state = state
        persistState()
        logger.info("Native actions deleted count=\(offsets.count, privacy: .public)")
    }

    func checkAppleStatus() async {
        guard var state else { return }
        let requestVersion = stateVersion
        let readiness = await aiService.checkReadiness()
        guard isCurrentStateVersion(requestVersion) else { return }
        invalidateInFlightWork()
        state.aiReadiness = readiness
        self.state = state
        persistState()
        logger.info("Native Apple readiness checked availability=\(readiness.availability, privacy: .public)")
    }

    func askAdvisor() async {
        guard var currentState = state, !isLoadingAdvisor else { return }
        let question = sanitizeFoundationModelText(draftAdvisorQuestion)
        guard hasConcreteFoundationText(question, minimumWords: 2) else { return }

        isLoadingAdvisor = true
        defer { isLoadingAdvisor = false }
        lastAdvisorError = nil
        let userMessage = NativeAdvisorMessage(
            date: currentState.gameDate,
            id: "advisor-leader-\(UUID().uuidString.lowercased())",
            role: .leader,
            text: question
        )
        currentState.advisorMessages.insert(userMessage, at: 0)
        invalidateInFlightWork()
        let requestVersion = stateVersion
        state = currentState
        draftAdvisorQuestion = ""
        persistState()

        do {
            let answer = try await aiService.generateAdvisorBrief(for: currentState, question: question)
            guard isCurrentStateVersion(requestVersion) else { return }
            guard var nextState = state else { return }
            nextState.advisorMessages.insert(
                NativeAdvisorMessage(
                    date: nextState.gameDate,
                    id: "advisor-apple-\(UUID().uuidString.lowercased())",
                    role: .advisor,
                    text: answer
                ),
                at: 0
            )
            nextState.aiReadiness = .available(tokenBudget: "advisor context=4096, maxResponse=220")
            invalidateInFlightWork()
            state = nextState
            persistState()
            logger.info("Native advisor response stored round=\(nextState.round, privacy: .public)")
        } catch {
            guard isCurrentStateVersion(requestVersion) else { return }
            guard var nextState = state else { return }
            nextState.aiReadiness = .failure(error)
            invalidateInFlightWork()
            state = nextState
            lastAdvisorError = "\(error.localizedDescription) The advisor transcript was preserved; retry when Apple Foundation Models are ready."
            persistState()
            logger.error("Native advisor response failed round=\(nextState.round, privacy: .public)")
        }
    }

    func sendDiplomaticMessage() async {
        guard var currentState = state, !isLoadingDiplomacy else { return }
        let message = sanitizeFoundationModelText(draftDiplomaticMessage)
        guard hasConcreteFoundationText(message, minimumWords: 1) else { return }
        let partner = selectedDiplomaticPartner(in: currentState)

        isLoadingDiplomacy = true
        defer { isLoadingDiplomacy = false }
        lastDiplomacyError = nil
        let leaderMessage = NativeDiplomaticMessage(
            date: currentState.gameDate,
            id: "diplomacy-leader-\(UUID().uuidString.lowercased())",
            speaker: currentState.country.name,
            text: message
        )
        var thread = currentState.thread(for: partner)
        thread.messages.append(leaderMessage)
        thread.lastUpdated = currentState.gameDate
        currentState.upsertDiplomaticThread(thread)
        invalidateInFlightWork()
        let requestVersion = stateVersion
        state = currentState
        draftDiplomaticMessage = ""
        persistState()

        do {
            let reply = try await aiService.generateDiplomaticReply(
                for: currentState,
                thread: thread,
                message: message
            )
            guard isCurrentStateVersion(requestVersion) else { return }
            guard var nextState = state else { return }
            var nextThread = nextState.thread(for: partner)
            nextThread.messages.append(
                NativeDiplomaticMessage(
                    date: nextState.gameDate,
                    id: "diplomacy-\(partner.code.lowercased())-\(UUID().uuidString.lowercased())",
                    speaker: partner.name,
                    text: reply
                )
            )
            nextThread.messages = Array(nextThread.messages.suffix(30))
            nextThread.lastUpdated = nextState.gameDate
            nextThread.summary = sanitizeFoundationModelText(reply).prefixText(140)
            nextState.upsertDiplomaticThread(nextThread)
            nextState.aiReadiness = .available(tokenBudget: "diplomacy context=4096, maxResponse=180")
            invalidateInFlightWork()
            state = nextState
            persistState()
            logger.info("Native diplomatic response stored partner=\(partner.code, privacy: .public)")
        } catch {
            guard isCurrentStateVersion(requestVersion) else { return }
            guard var nextState = state else { return }
            nextState.aiReadiness = .failure(error)
            invalidateInFlightWork()
            state = nextState
            lastDiplomacyError = "\(error.localizedDescription) The channel stayed open and no fake diplomatic response was inserted."
            persistState()
            logger.error("Native diplomatic response failed partner=\(partner.code, privacy: .public)")
        }
    }

    func advance(months: Int) async {
        guard var currentState = state, !isAdvancing else { return }
        guard months > 0 else {
            lastError = "Choose a positive time jump."
            return
        }

        isAdvancing = true
        defer {
            isAdvancing = false
            turnProgress = nil
        }
        lastError = nil
        // `currentState` is the input snapshot for generation. If the player
        // imports, resets, changes language, or edits actions while the model is
        // running, `requestVersion` prevents this older result from overwriting
        // the newer campaign.
        let requestVersion = stateVersion
        let laneCount = NativeStrategyContextDatabase.estimatedLaneCount(for: currentState)
        turnProgress = NativeTurnProgress(
            completedLanes: 0,
            detail: "Preparing local facts, action memory, and economic ledger.",
            phase: "Preparing turn",
            totalLanes: laneCount
        )
        var shouldRefreshSuggestions = false

        do {
            let generated = try await aiService.generateTurn(for: currentState, months: months) { [weak self] progress in
                guard let self, self.isCurrentStateVersion(requestVersion) else { return }
                self.turnProgress = progress
            }
            guard isCurrentStateVersion(requestVersion) else { return }
            turnProgress = NativeTurnProgress(
                completedLanes: max(0, laneCount - 1),
                detail: "Checking dates, linked actions, and visible consequences.",
                phase: "Validating turn",
                totalLanes: laneCount
            )
            let validated = try NativeGameEngine.validated(generated, state: currentState, months: months)
            turnProgress = NativeTurnProgress(
                completedLanes: laneCount,
                detail: "Updating budgets, fiscal space, action memory, and campaign effects.",
                phase: "Applying economics",
                totalLanes: laneCount
            )
            currentState = NativeGameEngine.apply(
                validated,
                to: currentState,
                months: months
            )

            invalidateInFlightWork()
            state = currentState
            lastTurnReport = validated
            lastError = nil
            persistState()
            shouldRefreshSuggestions = true
            logger.info("Native campaign advanced round=\(currentState.round, privacy: .public) months=\(months, privacy: .public)")
        } catch {
            guard isCurrentStateVersion(requestVersion) else { return }
            currentState.aiReadiness = .failure(error)
            invalidateInFlightWork()
            state = currentState
            lastError = error.localizedDescription
            persistState()
            logger.error("Native campaign advance failed round=\(currentState.round, privacy: .public) months=\(months, privacy: .public)")
        }

        if shouldRefreshSuggestions {
            await refreshSuggestedActions(force: true)
        }
    }

    func refreshSuggestedActionsIfNeeded() async {
        guard let state, state.suggestedActions.isEmpty else { return }
        await refreshSuggestedActions(force: false)
    }

    func refreshSuggestedActions(force: Bool) async {
        guard var currentState = state, !isLoadingSuggestions else { return }
        guard force || currentState.suggestedActions.isEmpty else { return }

        isLoadingSuggestions = true
        lastSuggestionError = nil
        let requestVersion = stateVersion
        defer { isLoadingSuggestions = false }

        do {
            let suggestions = try await aiService.generateSuggestedActions(for: currentState)
            guard isCurrentStateVersion(requestVersion) else { return }
            currentState.suggestedActions = suggestions
            currentState.aiReadiness = .available(tokenBudget: "sliced-guided-generation context=4096, suggestions=4x180")
            invalidateInFlightWork()
            state = currentState
            lastSuggestionError = nil
            persistState()
            logger.info("Native suggested actions refreshed count=\(suggestions.count, privacy: .public)")
        } catch {
            guard isCurrentStateVersion(requestVersion) else { return }
            currentState.aiReadiness = .suggestionFailure(error)
            if force {
                currentState.suggestedActions = []
            }
            invalidateInFlightWork()
            state = currentState
            lastSuggestionError = error.localizedDescription
            persistState()
            logger.error("Native suggested actions refresh failed")
        }
    }

    private func persistState() {
        guard let state else {
            defaults.removeObject(forKey: Self.campaignStateKey)
            defaults.removeObject(forKey: Self.campaignStateEnvelopeKey)
            defaults.removeObject(forKey: Self.campaignStateBackupKey)
            removePersistedCampaignFiles()
            return
        }

        // Persistence is deliberately redundant: primary versioned envelope,
        // last-good envelope backup, and a direct legacy state blob. The read
        // path tries them in that order so corrupt primary data can be recovered
        // without losing old-save compatibility.
        let envelope = CampaignStateEnvelope(
            schemaVersion: 2,
            savedAt: NativeGameEngine.todayStamp(),
            state: state
        )
        let envelopeData: Data
        let legacyData: Data
        do {
            envelopeData = try encoder.encode(envelope)
            legacyData = try encoder.encode(state)
        } catch {
            logger.error("Native campaign encode failed")
            return
        }

        if let previousPrimary = Self.primaryPersistenceData(
            from: defaults,
            persistenceDirectory: persistenceDirectory
        ),
           let previousEnvelope = try? decoder.decode(CampaignStateEnvelope.self, from: previousPrimary),
           previousEnvelope.schemaVersion == 2 {
            defaults.set(previousPrimary, forKey: Self.campaignStateBackupKey)
            do {
                try Self.writePersistenceData(
                    previousPrimary,
                    fileName: Self.campaignStateBackupFileName,
                    directory: persistenceDirectory
                )
            } catch {
                logger.error("Native campaign backup file write failed")
            }
        } else {
            defaults.set(envelopeData, forKey: Self.campaignStateBackupKey)
            do {
                try Self.writePersistenceData(
                    envelopeData,
                    fileName: Self.campaignStateBackupFileName,
                    directory: persistenceDirectory
                )
            } catch {
                logger.error("Native campaign backup file seed failed")
            }
        }
        defaults.set(envelopeData, forKey: Self.campaignStateEnvelopeKey)
        defaults.set(legacyData, forKey: Self.campaignStateKey)
        do {
            try Self.writePersistenceData(
                envelopeData,
                fileName: Self.campaignStateEnvelopeFileName,
                directory: persistenceDirectory
            )
            try Self.writePersistenceData(
                legacyData,
                fileName: Self.campaignStateLegacyFileName,
                directory: persistenceDirectory
            )
            logger.info("Native campaign persisted round=\(state.round, privacy: .public) timeline=\(state.timeline.count, privacy: .public)")
        } catch {
            logger.error("Native campaign file persistence failed")
        }
    }

    private func invalidateInFlightWork() {
        stateVersion += 1
    }

    private func isCurrentStateVersion(_ version: Int) -> Bool {
        stateVersion == version
    }

    private static func loadSelectedCountry(from defaults: UserDefaults, decoder: JSONDecoder) -> PlayerCountry? {
        guard let data = defaults.data(forKey: selectedCountryKey) else {
            return nil
        }

        return try? decoder.decode(PlayerCountry.self, from: data)
    }

    private func removePersistedCampaignFiles() {
        for fileName in [
            Self.campaignStateEnvelopeFileName,
            Self.campaignStateBackupFileName,
            Self.campaignStateLegacyFileName,
        ] {
            do {
                try Self.removePersistenceData(fileName: fileName, directory: persistenceDirectory)
            } catch {
                logger.error("Native campaign persistence cleanup failed")
            }
        }
    }

    private static func loadCampaignState(
        from defaults: UserDefaults,
        decoder: JSONDecoder,
        persistenceDirectory: URL
    ) -> CampaignLoadResult {
        let primarySources = persistenceSources(
            defaults: defaults,
            key: campaignStateEnvelopeKey,
            fileName: campaignStateEnvelopeFileName,
            directory: persistenceDirectory
        )
        for source in primarySources {
            if let envelope = try? decoder.decode(CampaignStateEnvelope.self, from: source.data), envelope.schemaVersion == 2 {
                return CampaignLoadResult(state: envelope.state, notice: nil)
            }
        }

        let backupSources = persistenceSources(
            defaults: defaults,
            key: campaignStateBackupKey,
            fileName: campaignStateBackupFileName,
            directory: persistenceDirectory
        )
        for source in backupSources {
            if let envelope = try? decoder.decode(CampaignStateEnvelope.self, from: source.data),
               envelope.schemaVersion == 2 {
                let notice = primarySources.isEmpty
                ? "Loaded the last-good campaign backup because the primary save was missing."
                : "Recovered the campaign from the last-good backup because the primary save was corrupt."
                return CampaignLoadResult(state: envelope.state, notice: "\(notice) Source: \(source.label).")
            }
        }

        let legacySources = persistenceSources(
            defaults: defaults,
            key: campaignStateKey,
            fileName: campaignStateLegacyFileName,
            directory: persistenceDirectory
        )
        for source in legacySources {
            if let state = try? decoder.decode(NativeCampaignState.self, from: source.data) {
                let notice = primarySources.isEmpty
                ? "Loaded a legacy campaign save and will upgrade it on the next save."
                : "Loaded a legacy campaign save because the versioned save could not be read."
                return CampaignLoadResult(state: state, notice: "\(notice) Source: \(source.label).")
            }
        }

        if !primarySources.isEmpty || !backupSources.isEmpty || !legacySources.isEmpty {
            return CampaignLoadResult(
                state: nil,
                notice: "Saved campaign data could not be read. A new campaign was not created until you choose a country."
            )
        }

        return CampaignLoadResult(state: nil, notice: nil)
    }

    private static func defaultPersistenceDirectory(fileManager: FileManager = .default) -> URL {
        let baseDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ??
            URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return baseDirectory
            .appendingPathComponent("SwiftHistoria", isDirectory: true)
            .appendingPathComponent("NativeCampaigns", isDirectory: true)
    }

    private static func primaryPersistenceData(
        from defaults: UserDefaults,
        persistenceDirectory: URL
    ) -> Data? {
        persistenceSources(
            defaults: defaults,
            key: campaignStateEnvelopeKey,
            fileName: campaignStateEnvelopeFileName,
            directory: persistenceDirectory
        ).first?.data
    }

    private static func persistenceSources(
        defaults: UserDefaults,
        key: String,
        fileName: String,
        directory: URL
    ) -> [PersistenceDataSource] {
        var sources: [PersistenceDataSource] = []
        if let data = readPersistenceData(fileName: fileName, directory: directory) {
            sources.append(PersistenceDataSource(data: data, label: "file"))
        }
        if let data = defaults.data(forKey: key) {
            sources.append(PersistenceDataSource(data: data, label: "user-defaults"))
        }
        return sources
    }

    private static func persistenceURL(fileName: String, directory: URL) -> URL {
        directory.appendingPathComponent(fileName, isDirectory: false)
    }

    private static func readPersistenceData(fileName: String, directory: URL) -> Data? {
        try? Data(contentsOf: persistenceURL(fileName: fileName, directory: directory))
    }

    private static func writePersistenceData(_ data: Data, fileName: String, directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: persistenceURL(fileName: fileName, directory: directory), options: [.atomic])
    }

    private static func removePersistenceData(fileName: String, directory: URL) throws {
        let url = persistenceURL(fileName: fileName, directory: directory)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    private static func normalizedScenarioID(_ value: String?) -> String {
        let rawID = sanitizeFoundationModelText(value ?? "")
        return NativeScenarioCatalog.scenario(for: rawID).id
    }

    private static func normalizedLoadedState(_ loaded: NativeCampaignState) -> NativeCampaignState {
        var state = loaded
        let scenario = NativeScenarioCatalog.scenario(for: state.scenarioID)
        state.language = NativeGameLanguage.normalized(state.language.rawValue)
        state.scenarioID = scenario.id
        state.scenarioName = sanitizeFoundationModelText(state.scenarioName)
        if state.scenarioName.isEmpty || containsFoundationPlaceholderText(state.scenarioName) {
            state.scenarioName = scenario.name
        }
        state.scenarioDescription = sanitizeFoundationModelText(state.scenarioDescription)
        if state.scenarioDescription.isEmpty || containsFoundationPlaceholderText(state.scenarioDescription) {
            state.scenarioDescription = scenario.heroSubtitle
        }
        if state.aiReadiness.availability == "apple-foundation-error" {
            state.aiReadiness = .notChecked
        }
        if !NativeGameEngine.isValidDate(state.gameDate) {
            state.gameDate = NativeGameEngine.initialState(for: state.country, scenario: scenario, language: state.language).gameDate
        }
        if !NativeGameEngine.isValidDate(state.startDate) {
            state.startDate = NativeGameEngine.initialState(for: state.country, scenario: scenario, language: state.language).startDate
        }
        state.round = Swift.max(1, state.round)
        state.stability = NativeGameEngine.clampedMetric(state.stability)
        state.worldTension = NativeGameEngine.clampedMetric(state.worldTension)
        state.suggestedActions = []
        state.lastSummary = sanitizeFoundationModelText(state.lastSummary)
        let initialState = NativeGameEngine.initialState(for: state.country, scenario: scenario, language: state.language)
        if state.lastSummary.isEmpty || containsFoundationPlaceholderText(state.lastSummary) {
            state.lastSummary = initialState.lastSummary
        }
        state.advisorMessages = deduped(state.advisorMessages, fallbackPrefix: "advisor-message") { message in
            message.id
        } transform: { message, id in
            var message = message
            message.id = id
            message.text = sanitizeFoundationModelText(message.text)
            if message.text.isEmpty || containsFoundationPlaceholderText(message.text) {
                return nil
            }
            if message.date.isEmpty || !NativeGameEngine.isValidDate(message.date) {
                message.date = state.gameDate
            }
            return message
        }
        state.diplomaticThreads = deduped(state.diplomaticThreads, fallbackPrefix: "diplomacy-thread") { thread in
            thread.id
        } transform: { thread, id in
            var thread = thread
            thread.id = id
            thread.summary = sanitizeFoundationModelText(thread.summary)
            if thread.lastUpdated.isEmpty || !NativeGameEngine.isValidDate(thread.lastUpdated) {
                thread.lastUpdated = state.gameDate
            }
            thread.messages = deduped(thread.messages, fallbackPrefix: "\(id)-message") { message in
                message.id
            } transform: { message, messageID in
                var message = message
                message.id = messageID
                message.speaker = sanitizeFoundationModelText(message.speaker)
                message.text = sanitizeFoundationModelText(message.text)
                if message.text.isEmpty || containsFoundationPlaceholderText(message.text) {
                    return nil
                }
                if message.speaker.isEmpty {
                    message.speaker = thread.participant.name
                }
                if message.date.isEmpty || !NativeGameEngine.isValidDate(message.date) {
                    message.date = thread.lastUpdated
                }
                return message
            }
            return thread.messages.isEmpty ? nil : thread
        }
        state.plannedActions = deduped(state.plannedActions, fallbackPrefix: "action") { action in
            action.id
        } transform: { action, id in
            var action = action
            action.id = id
            action.title = sanitizeFoundationModelText(action.title)
            action.detail = sanitizeFoundationModelText(action.detail)
            if action.title.isEmpty {
                action.title = "Untitled order"
            }
            if action.createdAt.isEmpty || !NativeGameEngine.isValidDate(action.createdAt) {
                action.createdAt = state.gameDate
            }
            if let resolvedAt = action.resolvedAt, !NativeGameEngine.isValidDate(resolvedAt) {
                action.resolvedAt = nil
                action.status = .planned
            }
            return action
        }
        state.actionMemory = deduped(state.actionMemory, fallbackPrefix: "action-memory") { memory in
            memory.id
        } transform: { memory, id in
            var memory = memory
            memory.id = id
            memory.actionID = sanitizeFoundationModelText(memory.actionID)
            memory.title = sanitizeFoundationModelText(memory.title)
            memory.detail = sanitizeFoundationModelText(memory.detail)
            memory.economicSummary = sanitizeFoundationModelText(memory.economicSummary)
            memory.source = sanitizeFoundationModelText(memory.source)
            memory.ruleIDs = Array(Set(memory.ruleIDs.map(sanitizeFoundationModelText).filter { !$0.isEmpty })).sorted()
            guard !memory.actionID.isEmpty else { return nil }
            if memory.title.isEmpty {
                memory.title = state.plannedActions.first { $0.id == memory.actionID }?.title ?? "Recorded order"
            }
            if memory.createdAt.isEmpty || !NativeGameEngine.isValidDate(memory.createdAt) {
                memory.createdAt = state.gameDate
            }
            if let resolvedAt = memory.resolvedAt, !NativeGameEngine.isValidDate(resolvedAt) {
                memory.resolvedAt = nil
                memory.status = .planned
            }
            if memory.economicSummary.isEmpty || containsFoundationPlaceholderText(memory.economicSummary) {
                memory.economicSummary = "Awaiting economic assessment."
            }
            if memory.source.isEmpty {
                memory.source = "loaded"
            }
            return memory
        }
        if state.actionMemory.isEmpty {
            for action in state.plannedActions.reversed() {
                state.actionMemory = NativeStrategyContextDatabase.remember(
                    action: action,
                    in: state.actionMemory,
                    source: "loaded",
                    state: state
                )
            }
        }
        state.economicLedger = NativeStrategyContextDatabase.normalizedEconomicLedger(
            state.economicLedger,
            for: state.country,
            scenario: scenario
        )
        state.dynamicCountries = Dictionary(uniqueKeysWithValues: state.dynamicCountries.compactMap { code, name in
            let cleanCode = code.uppercased().filter { $0 >= "A" && $0 <= "Z" }
            let cleanName = sanitizeFoundationModelText(name)
            guard cleanCode.count >= 2, !cleanName.isEmpty else { return nil }
            return (String(cleanCode.prefix(6)), cleanName)
        })
        var normalizedLedgers: [String: NativeEconomicLedger] = [:]
        for (code, ledger) in state.economicLedgers {
            let dummyCountry = PlayerCountry(code: code, name: code)
            normalizedLedgers[code] = NativeStrategyContextDatabase.normalizedEconomicLedger(
                ledger,
                for: dummyCountry,
                scenario: scenario
            )
        }
        for code in NativeStrategyContextDatabase.strategicCountryCodes(for: state) {
            if normalizedLedgers[code] == nil {
                let dummyCountry = PlayerCountry(code: code, name: code)
                normalizedLedgers[code] = NativeStrategyContextDatabase.startingEconomicLedger(for: dummyCountry, scenario: scenario)
            }
        }
        normalizedLedgers[state.country.code] = state.economicLedger
        state.economicLedgers = normalizedLedgers
        state.regionConflicts = normalizedRegionConflicts(
            state.regionConflicts,
            occupations: state.regionOccupations,
            falloutRegions: state.nuclearFalloutRegions,
            gameDate: state.gameDate
        )
        state.timeline = deduped(state.timeline, fallbackPrefix: "event") { event in
            event.id
        } transform: { event, id in
            var event = event
            event.id = id
            event.title = sanitizeFoundationModelText(event.title)
            event.description = sanitizeFoundationModelText(event.description)
            if var sovereignty = event.sovereigntyChange {
                sovereignty.targetCode = sovereignty.targetCode.uppercased().filter { $0 >= "A" && $0 <= "Z" }
                sovereignty.targetCode = String(sovereignty.targetCode.prefix(6))
                sovereignty.name = sanitizeFoundationModelText(sovereignty.name)
                sovereignty.sourceCodes = sovereignty.sourceCodes.map { $0.uppercased().filter { $0 >= "A" && $0 <= "Z" } }.filter { !$0.isEmpty }
                sovereignty.regionIDs = sovereignty.regionIDs.map(sanitizeFoundationModelText).filter { !$0.isEmpty }
                event.sovereigntyChange = sovereignty.targetCode.isEmpty && sovereignty.name.isEmpty ? nil : sovereignty
            }
            guard !containsFoundationPlaceholderText(event.title), !containsFoundationPlaceholderText(event.description) else {
                return nil
            }
            if event.title.isEmpty {
                event.title = event.playerRelated ? "\(state.country.name) faces a decision point" : "The international system shifts"
            }
            if event.description.isEmpty {
                event.description = "The campaign records a strategic development with consequences still being assessed."
            }
            if event.date.isEmpty || !NativeGameEngine.isValidDate(event.date) {
                event.date = state.gameDate
            }
            event.linkedActionIDs = Array(Set(event.linkedActionIDs)).sorted()
            if event.kind == .crisis {
                event.kind = event.playerRelated ? .action : .world
            }
            event.strategicEffects = deduped(event.strategicEffects, fallbackPrefix: "\(event.id)-effect") { effect in
                effect.id
            } transform: { effect, id in
                var effect = effect
                effect.id = id
                if effect.eventId.isEmpty {
                    effect.eventId = event.id
                }
                if effect.date.isEmpty || !NativeGameEngine.isValidDate(effect.date) {
                    effect.date = event.date
                }
                effect.summary = sanitizeFoundationModelText(effect.summary)
                effect.target = sanitizeFoundationModelText(effect.target)
                effect.track = foundationVisibleTrack(effect.track)
                effect.magnitude = Swift.max(-5, Swift.min(5, effect.magnitude))
                guard !containsFoundationPlaceholderText(effect.summary), !containsFoundationPlaceholderText(effect.target) else {
                    return nil
                }
                if effect.summary.isEmpty {
                    effect.summary = "Strategic consequences remain under review."
                }
                if effect.target.isEmpty {
                    effect.target = event.playerRelated ? state.country.name : "International system"
                }
                return effect
            }
            return event
        }
        if state.timeline.isEmpty {
            state.timeline = initialState.timeline
        }
        state.semanticMemory = deduped(state.semanticMemory, fallbackPrefix: "semantic-memory") { memory in
            memory.id
        } transform: { memory, id in
            var memory = memory
            memory.id = id
            memory.sourceID = sanitizeFoundationModelText(memory.sourceID)
            memory.text = sanitizeFoundationModelText(memory.text)
            guard !memory.sourceID.isEmpty, !memory.text.isEmpty, memory.embedding.count == 64 else { return nil }
            if memory.date.isEmpty || !NativeGameEngine.isValidDate(memory.date) {
                memory.date = state.gameDate
            }
            memory.importance = Swift.max(1, Swift.min(5, memory.importance))
            memory.track = foundationVisibleTrack(memory.track)
            return memory
        }
        if state.semanticMemory.isEmpty {
            state.semanticMemory = NativeStrategyContextDatabase.updatedSemanticMemory(
                state: state,
                events: Array(state.timeline.prefix(12))
            )
        }
        state.worldEffects = deduped(state.worldEffects, fallbackPrefix: "world-effect") { effect in
            effect.id
        } transform: { effect, id in
            var effect = effect
            effect.id = id
            if effect.date.isEmpty || !NativeGameEngine.isValidDate(effect.date) {
                effect.date = state.gameDate
            }
            effect.summary = sanitizeFoundationModelText(effect.summary)
            effect.target = sanitizeFoundationModelText(effect.target)
            effect.track = foundationVisibleTrack(effect.track)
            effect.magnitude = Swift.max(-5, Swift.min(5, effect.magnitude))
            guard !containsFoundationPlaceholderText(effect.summary), !containsFoundationPlaceholderText(effect.target) else {
                return nil
            }
            if effect.summary.isEmpty {
                effect.summary = "Strategic consequences remain under review."
            }
            if effect.target.isEmpty {
                effect.target = "International system"
            }
            return effect
        }
        if state.aiCountryStates.isEmpty {
            state.aiCountryStates = NativeStrategyContextDatabase.initialAICountryStates(for: state.scenarioID)
        }
        return state
    }

    private static func normalizedRegionConflicts(
        _ conflicts: [String: NativeRegionConflictState],
        occupations: [String: String],
        falloutRegions: [String],
        gameDate: String
    ) -> [String: NativeRegionConflictState] {
        var next = conflicts
        for (regionID, controllerCode) in occupations where next[regionID] == nil {
            let originalCode = NativeRegionConflictState.countryCode(fromLegacyRegionID: regionID)
            let mode: NativeRegionConflictMode = controllerCode == "REB" ? .guerrillaControl : .conventionalOccupation
            next[regionID] = NativeRegionConflictState(
                controllerCode: controllerCode,
                intensity: controllerCode == "REB" ? 4 : 3,
                mode: mode,
                originalCountryCode: originalCode,
                regionID: regionID,
                summary: "Recovered from legacy occupation map state.",
                updatedAt: gameDate
            )
        }
        for regionID in falloutRegions {
            let originalCode = NativeRegionConflictState.countryCode(fromLegacyRegionID: regionID)
            let existingUpdatedAt = next[regionID]?.updatedAt ?? ""
            let recoveredUpdatedAt = existingUpdatedAt.isEmpty ? gameDate : existingUpdatedAt
            next[regionID] = NativeRegionConflictState(
                controllerCode: occupations[regionID] ?? next[regionID]?.controllerCode ?? originalCode,
                intensity: 5,
                mode: .nuclearFallout,
                originalCountryCode: originalCode,
                regionID: regionID,
                summary: next[regionID]?.summary ?? "Recovered from legacy nuclear fallout map state.",
                updatedAt: recoveredUpdatedAt
            )
        }
        return next.compactMapValues { conflict in
            var conflict = conflict
            conflict.regionID = sanitizeFoundationModelText(conflict.regionID)
            conflict.controllerCode = sanitizeFoundationModelText(conflict.controllerCode)
            conflict.originalCountryCode = sanitizeFoundationModelText(conflict.originalCountryCode)
            conflict.sourceEventID = sanitizeFoundationModelText(conflict.sourceEventID)
            conflict.summary = sanitizeFoundationModelText(conflict.summary)
            conflict.intensity = Swift.max(1, Swift.min(5, conflict.intensity))
            if conflict.regionID.isEmpty || conflict.controllerCode.isEmpty {
                return nil
            }
            if conflict.originalCountryCode.isEmpty {
                conflict.originalCountryCode = NativeRegionConflictState.countryCode(fromLegacyRegionID: conflict.regionID)
            }
            if conflict.updatedAt.isEmpty || !NativeGameEngine.isValidDate(conflict.updatedAt) {
                conflict.updatedAt = gameDate
            }
            return conflict
        }
    }

    private static func plannedOrderSummary(for action: NativePlannedAction, language: NativeGameLanguage) -> String {
        switch language {
        case .english:
            return "\(action.title) has been placed before the cabinet. Its concrete consequences will be resolved on the next time jump."
        case .portuguese:
            return "\(action.title) foi colocado diante do gabinete. Suas consequências concretas serão resolvidas no próximo salto de tempo."
        case .spanish:
            return "\(action.title) fue puesto ante el gabinete. Sus consecuencias concretas se resolverán en el próximo salto temporal."
        }
    }

    private static func acceptedSuggestionSummary(for action: NativePlannedAction, language: NativeGameLanguage) -> String {
        switch language {
        case .english:
            return "\(action.title) has been accepted as a planned order. Apple Foundation Models will resolve its impact on the next time jump."
        case .portuguese:
            return "\(action.title) foi aceito como ordem planejada. O Apple Foundation Models resolverá seu impacto no próximo salto de tempo."
        case .spanish:
            return "\(action.title) fue aceptado como orden planificada. Apple Foundation Models resolverá su impacto en el próximo salto temporal."
        }
    }

    private static func deduped<Element>(
        _ values: [Element],
        fallbackPrefix: String,
        id: (Element) -> String,
        transform: (Element, String) -> Element?
    ) -> [Element] {
        var seen = Set<String>()
        return values.enumerated().compactMap { index, value in
            let rawID = sanitizeFoundationModelText(id(value))
            let candidate = rawID.isEmpty ? "\(fallbackPrefix)-\(index)" : rawID
            let uniqueID = seen.insert(candidate).inserted ? candidate : "\(candidate)-\(index)"
            return transform(value, uniqueID)
        }
    }

    private static func defaultDiplomaticPartnerCode(for state: NativeCampaignState?) -> String {
        guard let state else { return "" }
        return CountryCatalog.all.first { $0.code != state.country.code }?.code ?? ""
    }

    private func selectedDiplomaticPartner(in state: NativeCampaignState) -> PlayerCountry {
        if let selected = CountryCatalog.all.first(where: { $0.code == selectedDiplomaticPartnerCode && $0.code != state.country.code }) {
            return selected
        }
        let fallback = CountryCatalog.all.first { $0.code != state.country.code } ?? PlayerCountry(code: "INT", name: "International Forum")
        selectedDiplomaticPartnerCode = fallback.code
        return fallback
    }

    func updateBudgetSliders(military: Double, services: Double, diplomacy: Double) {
        guard var state = self.state else { return }
        state.budgetMilitarySlider = military
        state.budgetServicesSlider = services
        state.budgetDiplomacySlider = diplomacy
        self.state = state
        persistState()
    }

    func acceptDiplomaticOffer(id: String) {
        guard var state = self.state else { return }
        guard let idx = state.activeOffers.firstIndex(where: { $0.id == id && $0.status == .pending }) else { return }
        var offer = state.activeOffers[idx]
        offer.status = .accepted
        state.activeOffers[idx] = offer

        state.stability = max(0, min(100, state.stability - offer.stabilityCost))

        if var proposerState = state.aiCountryStates[offer.proposerCode] {
            let currentVal = proposerState.relationshipScores[state.country.code] ?? 0
            proposerState.relationshipScores[state.country.code] = max(-100, min(100, currentVal + offer.relationshipEffect))
            state.aiCountryStates[offer.proposerCode] = proposerState
        }

        if var pLedger = state.economicLedgers[state.country.code] {
            pLedger.realGrowthPercent = max(-12.0, min(16.0, pLedger.realGrowthPercent + offer.growthDelta))

            var secDelta = 0.0
            var tradeDelta = 0.0
            if offer.type == .militaryAlliance {
                secDelta = 5.0
                pLedger.securityIndex = max(0.0, min(100.0, pLedger.securityIndex + secDelta))
            } else if offer.type == .nonAggressionPact {
                secDelta = 1.0
                pLedger.securityIndex = max(0.0, min(100.0, pLedger.securityIndex + secDelta))
            } else if offer.type == .tradeAgreement {
                tradeDelta = 1.2
                pLedger.tradeBalancePercentGDP = max(-20.0, min(20.0, pLedger.tradeBalancePercentGDP + tradeDelta))
            }

            let acceptEntry = NativeEconomicLedgerEntry(
                budgetBalanceDelta: 0.0,
                debtDelta: 0.0,
                eventID: "offer-accept-\(id)",
                fiscalSpaceDelta: 0,
                growthDelta: offer.growthDelta,
                id: "ledger-entry-offer-accept-\(UUID().uuidString.lowercased())",
                inflationDelta: 0.0,
                ruleID: "diplomatic-treaty",
                summary: "Accepted offer: \(offer.type.displayName) with \(offer.proposerCode)",
                tradeBalanceDelta: tradeDelta,
                turnDate: state.gameDate,
                securityDelta: secDelta,
                rebelDelta: 0.0
            )
            pLedger.entries.insert(acceptEntry, at: 0)
            state.economicLedgers[state.country.code] = pLedger
            state.economicLedger = pLedger
        }

        let acceptEvent = NativeCampaignEvent(
            date: state.gameDate,
            description: "TREATY SIGNED: We have accepted the \(offer.type.displayName) proposal from \(offer.proposerCode). Effects: \(offer.description)",
            id: "offer-accept-event-\(id)-\(UUID().uuidString.lowercased())",
            importance: .major,
            kind: .diplomacy,
            linkedActionIDs: [],
            notable: true,
            playerRelated: true,
            strategicEffects: [],
            title: "Treaty Signed with \(offer.proposerCode)"
        )
        state.timeline.insert(acceptEvent, at: 0)
        self.state = state
        persistState()
    }

    func rejectDiplomaticOffer(id: String) {
        guard var state = self.state else { return }
        guard let idx = state.activeOffers.firstIndex(where: { $0.id == id && $0.status == .pending }) else { return }
        var offer = state.activeOffers[idx]
        offer.status = .rejected
        state.activeOffers[idx] = offer

        if var proposerState = state.aiCountryStates[offer.proposerCode] {
            let currentVal = proposerState.relationshipScores[state.country.code] ?? 0
            proposerState.relationshipScores[state.country.code] = max(-100, min(100, currentVal - 5))
            state.aiCountryStates[offer.proposerCode] = proposerState
        }

        let rejectEvent = NativeCampaignEvent(
            date: state.gameDate,
            description: "PROPOSAL REJECTED: We declined the \(offer.type.displayName) proposal from \(offer.proposerCode). Relations deteriorated slightly.",
            id: "offer-reject-event-\(id)-\(UUID().uuidString.lowercased())",
            importance: .minor,
            kind: .diplomacy,
            linkedActionIDs: [],
            notable: false,
            playerRelated: true,
            strategicEffects: [],
            title: "Declined Proposal from \(offer.proposerCode)"
        )
        state.timeline.insert(rejectEvent, at: 0)
        self.state = state
        persistState()
    }

    func counterDiplomaticOffer(id: String) {
        guard var state = self.state else { return }
        guard let idx = state.activeOffers.firstIndex(where: { $0.id == id && $0.status == .pending }) else { return }
        var offer = state.activeOffers[idx]

        let proposerCode = offer.proposerCode
        let relations = state.aiCountryStates[proposerCode]?.relationshipScores[state.country.code] ?? 0
        let threshold = 20 + (state.worldTension / 2)
        if relations >= threshold {
            offer.status = .accepted
            offer.growthDelta *= 1.25
            offer.relationshipEffect = Int(Double(offer.relationshipEffect) * 1.25)
            state.activeOffers[idx] = offer

            state.stability = max(0, min(100, state.stability - offer.stabilityCost))

            if var proposerState = state.aiCountryStates[proposerCode] {
                let currentVal = proposerState.relationshipScores[state.country.code] ?? 0
                proposerState.relationshipScores[state.country.code] = max(-100, min(100, currentVal + offer.relationshipEffect))
                state.aiCountryStates[proposerCode] = proposerState
            }

            if var pLedger = state.economicLedgers[state.country.code] {
                pLedger.realGrowthPercent = max(-12.0, min(16.0, pLedger.realGrowthPercent + offer.growthDelta))

                var secDelta = 0.0
                var tradeDelta = 0.0
                if offer.type == .militaryAlliance {
                    secDelta = 6.25
                    pLedger.securityIndex = max(0.0, min(100.0, pLedger.securityIndex + secDelta))
                } else if offer.type == .nonAggressionPact {
                    secDelta = 1.25
                    pLedger.securityIndex = max(0.0, min(100.0, pLedger.securityIndex + secDelta))
                } else if offer.type == .tradeAgreement {
                    tradeDelta = 1.5
                    pLedger.tradeBalancePercentGDP = max(-20.0, min(20.0, pLedger.tradeBalancePercentGDP + tradeDelta))
                }

                let acceptEntry = NativeEconomicLedgerEntry(
                    budgetBalanceDelta: 0.0,
                    debtDelta: 0.0,
                    eventID: "offer-counter-accept-\(id)",
                    fiscalSpaceDelta: 0,
                    growthDelta: offer.growthDelta,
                    id: "ledger-entry-offer-counter-accept-\(UUID().uuidString.lowercased())",
                    inflationDelta: 0.0,
                    ruleID: "diplomatic-treaty",
                    summary: "Accepted counter-offer: \(offer.type.displayName) with \(offer.proposerCode)",
                    tradeBalanceDelta: tradeDelta,
                    turnDate: state.gameDate,
                    securityDelta: secDelta,
                    rebelDelta: 0.0
                )
                pLedger.entries.insert(acceptEntry, at: 0)
                state.economicLedgers[state.country.code] = pLedger
                state.economicLedger = pLedger
            }

            let acceptEvent = NativeCampaignEvent(
                date: state.gameDate,
                description: "COUNTER-PROPOSAL ACCEPTED: \(proposerCode) accepted our counter-terms for the \(offer.type.displayName). Benefits improved by 25%!",
                id: "offer-counter-accept-event-\(id)-\(UUID().uuidString.lowercased())",
                importance: .major,
                kind: .diplomacy,
                linkedActionIDs: [],
                notable: true,
                playerRelated: true,
                strategicEffects: [],
                title: "Counter-Proposal Accepted by \(proposerCode)"
            )
            state.timeline.insert(acceptEvent, at: 0)
        } else {
            offer.status = .countered
            state.activeOffers[idx] = offer

            let rejectEvent = NativeCampaignEvent(
                date: state.gameDate,
                description: "COUNTER-PROPOSAL REJECTED: \(proposerCode) declined our counter-terms for the \(offer.type.displayName). Negotiations broke down and the proposal was cancelled.",
                id: "offer-counter-reject-event-\(id)-\(UUID().uuidString.lowercased())",
                importance: .major,
                kind: .diplomacy,
                linkedActionIDs: [],
                notable: true,
                playerRelated: true,
                strategicEffects: [],
                title: "Counter-Proposal Declined by \(proposerCode)"
            )
            state.timeline.insert(rejectEvent, at: 0)
        }

        self.state = state
        persistState()
    }
}

enum NativeCampaignStoreError: LocalizedError {
    case noCampaignToExport

    var errorDescription: String? {
        switch self {
        case .noCampaignToExport:
            return "There is no native campaign to export yet."
        }
    }
}

private extension NativeCampaignState {
    func thread(for participant: PlayerCountry) -> NativeDiplomaticThread {
        diplomaticThreads.first { $0.participant.code == participant.code } ??
            NativeDiplomaticThread(
                id: "diplomacy-\(participant.code.lowercased())",
                lastUpdated: gameDate,
                messages: [],
                participant: participant,
                summary: "No messages yet."
            )
    }

    mutating func upsertDiplomaticThread(_ thread: NativeDiplomaticThread) {
        if let index = diplomaticThreads.firstIndex(where: { $0.participant.code == thread.participant.code }) {
            diplomaticThreads[index] = thread
        } else {
            diplomaticThreads.insert(thread, at: 0)
        }
    }
}

private extension String {
    func prefixText(_ maxLength: Int) -> String {
        guard maxLength > 0 else { return "" }
        guard count > maxLength else { return self }
        let end = index(startIndex, offsetBy: maxLength)
        return String(self[..<end])
    }
}
