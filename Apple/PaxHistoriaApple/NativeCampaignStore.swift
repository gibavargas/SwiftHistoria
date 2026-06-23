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

    let defaults: UserDefaults
    let encoder: JSONEncoder
    let decoder: JSONDecoder
    private let aiService: any NativeAIService

    /// Provider name for the last advisor/diplomacy response (for UI labels).
    var lastAIProviderUsed: String {
        (aiService as? DynamicAIService)?.lastProviderUsed ?? "Unknown"
    }

    /// Session token usage for cost telemetry display.
    var sessionTokenUsage: (prompt: Int, completion: Int, total: Int) {
        guard let dyn = aiService as? DynamicAIService else { return (0, 0, 0) }
        return (dyn.sessionPromptTokens, dyn.sessionCompletionTokens, dyn.sessionTotalTokens)
    }

    var tokenBudgetWarning: Bool {
        (aiService as? DynamicAIService)?.tokenBudgetWarning ?? false
    }

    let persistenceDirectory: URL
    let logger = Logger(subsystem: "com.gibavargas.SwiftHistoria", category: "NativeCampaignStore")
    /// **Concurrency & Asynchrony Mechanic**:
    /// `stateVersion` prevents async race conditions (stale-response rejection).
    /// Incremented (`invalidateInFlightWork()`) whenever local state changes in a way that makes in-flight AI work obsolete.
    /// Async methods (like `advance(months:)` or `askAdvisor()`) capture this value before awaiting the AI service.
    /// After the await resumes, they check if `stateVersion` is still the same. If it changed (e.g. the user clicked "Reset" or advanced again),
    /// the stale result is dropped and not applied to the state, preventing ghost mutations.
    var stateVersion = 0
    var pendingSuggestionRefreshForce: Bool?

    static let maximumCampaignImportBytes = 5_000_000
    static let selectedCountryKey = "pax-historia.native.selected-country.v1"
    static let selectedLanguageKey = "pax-historia.native.selected-language.v1"
    static let selectedScenarioKey = "pax-historia.native.selected-scenario.v1"
    static let campaignStateKey = "pax-historia.native.campaign-state.v1"
    static let campaignStateEnvelopeKey = "pax-historia.native.campaign-state-envelope.v2"
    static let campaignStateBackupKey = "pax-historia.native.campaign-state-backup.v2"
    static let campaignStateEnvelopeFileName = "campaign-state-envelope-v2.json"
    static let campaignStateBackupFileName = "campaign-state-backup-v2.json"
    static let campaignStateLegacyFileName = "campaign-state-legacy-v1.json"
    static let maximumUserDefaultsCampaignBlobBytes = 512_000
    nonisolated static let tursoDatabaseURLKey = "TURSO_DATABASE_URL"
    nonisolated static let tursoAuthTokenKey = "TURSO_AUTH_TOKEN"

    // MARK: - Save Slots (#15)

    /// Active save slot (1, 2, or 3). Slot 1 uses the original unsuffixed keys for backward compat.
    static let activeSlotKey = "pax-historia.native.active-slot.v1"
    @Published var saveSlot: Int = 1 {
        didSet {
            defaults.set(saveSlot, forKey: Self.activeSlotKey)
        }
    }

    /// Returns slot-suffixed UserDefaults key. Slot 1 → original key (backward compatible).
    func slotKey(_ baseKey: String) -> String {
        Self.slotKey(baseKey, slot: saveSlot)
    }

    /// Returns slot-suffixed filename. Slot 1 → original filename.
    func slotFileName(_ baseName: String) -> String {
        Self.slotFileName(baseName, slot: saveSlot)
    }

    static func slotKey(_ baseKey: String, slot: Int) -> String {
        slot == 1 ? baseKey : "\(baseKey).slot\(slot)"
    }

    static func slotFileName(_ baseName: String, slot: Int) -> String {
        slot == 1 ? baseName : baseName.replacingOccurrences(of: ".json", with: "-slot\(slot).json")
    }

    /// Checks if a slot has a saved campaign.
    func slotHasCampaign(_ slot: Int) -> Bool {
        slotSummary(slot) != nil
    }

    /// Gets a summary of a save slot for UI display.
    func slotSummary(_ slot: Int) -> (countryName: String, round: Int, scenarioName: String)? {
        let loadResult = Self.loadCampaignState(
            from: defaults,
            decoder: decoder,
            persistenceDirectory: persistenceDirectory,
            slotKey: { key in Self.slotKey(key, slot: slot) },
            slotFileName: { name in Self.slotFileName(name, slot: slot) }
        )
        guard let state = loadResult.state.map(Self.normalizedLoadedState) else {
            return nil
        }
        return (state.country.name, state.round, state.scenarioName)
    }

    /// Switches to a different save slot and loads its campaign (if any).
    func switchSlot(_ slot: Int) {
        precondition(slot >= 1 && slot <= 3, "Save slot must be 1, 2, or 3")
        cancelInFlightTurn()
        saveSlot = slot
        // Reload state from the new slot
        let loadResult = Self.loadCampaignState(
            from: defaults,
            decoder: decoder,
            persistenceDirectory: persistenceDirectory,
            slotKey: { key in Self.slotKey(key, slot: slot) },
            slotFileName: { name in Self.slotFileName(name, slot: slot) }
        )
        state = loadResult.state.map(Self.normalizedLoadedState)
        lastRecoveryNotice = loadResult.notice
        selectedCountry = Self.loadSelectedCountry(from: defaults, decoder: decoder, key: slotKey(Self.selectedCountryKey))
        let loadedState = state
        selectedLanguage = NativeGameLanguage.normalized(defaults.string(forKey: slotKey(Self.selectedLanguageKey)) ?? loadedState?.language.rawValue)
        selectedScenarioID = Self.normalizedScenarioID(defaults.string(forKey: slotKey(Self.selectedScenarioKey)) ?? loadedState?.scenarioID)
        if selectedCountry == nil, let loadedState {
            selectedCountry = loadedState.country
        }
        selectedDiplomaticPartnerCode = Self.defaultDiplomaticPartnerCode(for: state)
    }

    static var suggestionRefreshTimeoutNanoseconds: UInt64 = 30_000_000_000
    private static let maximumAdministrativeCapacity = 120

    static var uiTestResetRequested: Bool {
        #if DEBUG
            let environment = ProcessInfo.processInfo.environment
            let arguments = ProcessInfo.processInfo.arguments
            return environment["PAX_HISTORIA_UI_TEST_RESET"] == "1" || arguments.contains("--pax-historia-ui-test-reset")
        #else
            return false
        #endif
    }

    private static func currentAIProviderRoute(defaults: UserDefaults) -> (provider: String, model: String, identifier: String, detail: String) {
        let preference = NativeAIProviderPreference.current(defaults: defaults)
        let openRouterKey = defaults.string(forKey: "OPENROUTER_API_KEY") ?? ""
        let hasOpenRouterKey = !openRouterKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let zaiKey = defaults.string(forKey: "ZAI_API_KEY") ?? ""
        let hasZAIKey = !zaiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        switch preference {
        case .appleFoundation:
            return (
                "Apple Foundation Models",
                "System Language Model",
                "SystemLanguageModel.default",
                "Player selected Apple Foundation Models. Calling the on-device System Language Model."
            )
        case .openRouter:
            if hasOpenRouterKey {
                return (
                    "OpenRouter",
                    "Free Models Router",
                    "openrouter/free",
                    "Player selected OpenRouter. Calling OpenRouter Free API; failures stay on OpenRouter and are shown to the player."
                )
            }
            return (
                "OpenRouter",
                "Free Models Router",
                "openrouter/free",
                "OpenRouter is selected, but no OpenRouter API key is saved. Add the key in Settings and retry."
            )
        case .zai:
            if hasZAIKey {
                let route = defaults.bool(forKey: "ZAI_USE_CODING_ENDPOINT") ? "Z.AI Coding Endpoint" : "Z.AI API"
                return (
                    "Z.AI",
                    "GLM-5",
                    "glm-5",
                    "Player selected Z.AI. Calling \(route); fallback is Apple Foundation Models."
                )
            }
            return (
                "Apple Foundation Models",
                "System Language Model",
                "SystemLanguageModel.default",
                "Z.AI is selected, but no Z.AI API key is saved. Starting with Apple Foundation Models."
            )
        }
    }

    struct CampaignLoadResult {
        let state: NativeCampaignState?
        let notice: String?
    }

    /// Versioned save wrapper. The raw `NativeCampaignState` is still mirrored
    /// as a legacy fallback, but the envelope is the primary format because it
    /// gives future migrations an explicit schema boundary.
    struct CampaignStateEnvelope: Codable {
        let schemaVersion: Int
        let savedAt: String
        let state: NativeCampaignState
    }

    struct PersistenceDataSource {
        let data: Data
        let label: String
    }

    init(
        defaults: UserDefaults = .standard,
        aiService: (any NativeAIService)? = nil,
        persistenceDirectory: URL? = nil
    ) {
        let decoder = JSONDecoder()
        self.defaults = defaults
        encoder = JSONEncoder()
        self.decoder = decoder
        self.aiService = aiService ?? DynamicAIService(defaults: defaults)
        self.persistenceDirectory = persistenceDirectory ?? Self.defaultPersistenceDirectory()
        #if DEBUG
            if Self.uiTestResetRequested {
                Self.removePersistedCampaignState(defaults: defaults, persistenceDirectory: self.persistenceDirectory)
            }
        #endif
        // Restore active save slot (#15)
        let savedSlot = defaults.integer(forKey: Self.activeSlotKey)
        let activeSlot = (savedSlot >= 1 && savedSlot <= 3) ? savedSlot : 1
        selectedCountry = Self.loadSelectedCountry(
            from: defaults,
            decoder: decoder,
            key: Self.slotKey(Self.selectedCountryKey, slot: activeSlot)
        )
        let loadResult = Self.loadCampaignState(
            from: defaults,
            decoder: decoder,
            persistenceDirectory: self.persistenceDirectory,
            slotKey: { key in Self.slotKey(key, slot: activeSlot) },
            slotFileName: { name in Self.slotFileName(name, slot: activeSlot) }
        )
        let loadedState = loadResult.state.map(Self.normalizedLoadedState)
        state = loadedState
        lastRecoveryNotice = loadResult.notice
        let languageKey = Self.slotKey(Self.selectedLanguageKey, slot: activeSlot)
        let resolvedLanguage = NativeGameLanguage.normalized(defaults.string(forKey: languageKey) ?? loadedState?.language.rawValue)
        selectedLanguage = resolvedLanguage

        // Ensure AppleLanguages matches the saved game language on launch.
        if defaults.string(forKey: languageKey) != nil {
            let localeCode = switch resolvedLanguage {
            case .english: "en"
            case .portuguese: "pt-BR"
            case .spanish: "es"
            }
            defaults.set([localeCode], forKey: "AppleLanguages")
        }

        selectedScenarioID = Self.normalizedScenarioID(defaults.string(forKey: Self.slotKey(Self.selectedScenarioKey, slot: activeSlot)) ?? loadedState?.scenarioID)

        if let selectedCountry, state == nil {
            state = NativeGameEngine.initialState(for: selectedCountry, scenario: selectedScenario, language: selectedLanguage)
            persistState()
        } else if selectedCountry == nil, let state {
            selectedCountry = state.country
            selectedLanguage = state.language
            selectedScenarioID = Self.normalizedScenarioID(state.scenarioID)
        }
        selectedDiplomaticPartnerCode = Self.defaultDiplomaticPartnerCode(for: state)
        // Set saveSlot after all stored properties are initialized
        saveSlot = activeSlot
        logger.info("Native campaign store initialized hasState=\(self.state != nil, privacy: .public)")
    }

    var selectedScenario: NativeScenario {
        NativeScenarioCatalog.scenario(for: selectedScenarioID)
    }

    var selectedAIProviderPreference: NativeAIProviderPreference {
        NativeAIProviderPreference.current(defaults: defaults)
    }

    func setLanguage(_ language: NativeGameLanguage) {
        guard selectedLanguage != language || state?.language != language else { return }
        invalidateInFlightWork()
        selectedLanguage = language
        defaults.set(language.rawValue, forKey: slotKey(Self.selectedLanguageKey))

        // Update the system locale so SwiftUI picks up the correct Localizable.xcstrings
        // translations on the next app launch.
        let localeCode = switch language {
        case .english: "en"
        case .portuguese: "pt-BR"
        case .spanish: "es"
        }
        defaults.set([localeCode], forKey: "AppleLanguages")

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
        defaults.set(scenario.id, forKey: slotKey(Self.selectedScenarioKey))
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
        defaults.set(selectedLanguage.rawValue, forKey: slotKey(Self.selectedLanguageKey))
        defaults.set(selectedScenarioID, forKey: slotKey(Self.selectedScenarioKey))
        if let data = try? encoder.encode(country) {
            defaults.set(data, forKey: slotKey(Self.selectedCountryKey))
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
        defaults.removeObject(forKey: slotKey(Self.selectedCountryKey))
        defaults.removeObject(forKey: slotKey(Self.campaignStateKey))
        defaults.removeObject(forKey: slotKey(Self.campaignStateEnvelopeKey))
        defaults.removeObject(forKey: slotKey(Self.campaignStateBackupKey))
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

        state = currentState

        if let data = try? encoder.encode(newCountry) {
            defaults.set(data, forKey: slotKey(Self.selectedCountryKey))
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
        defaults.removeObject(forKey: slotKey(Self.selectedCountryKey))
        logger.info("Exited to main menu (campaign state retained for resume)")
    }

    func resumeActiveCampaign() {
        guard let state else { return }
        invalidateInFlightWork()
        selectedCountry = state.country
        selectedScenarioID = state.scenarioID
        selectedLanguage = state.language
        selectedDiplomaticPartnerCode = Self.defaultDiplomaticPartnerCode(for: state)
        if let data = try? encoder.encode(state.country) {
            defaults.set(data, forKey: slotKey(Self.selectedCountryKey))
        }
        defaults.set(state.scenarioID, forKey: slotKey(Self.selectedScenarioKey))
        defaults.set(state.language.rawValue, forKey: slotKey(Self.selectedLanguageKey))
        logger.info("Resumed active campaign as \(state.country.code)")
    }

    func setGameMode(_ mode: NativeGameMode) {
        guard var currentState = state else { return }
        invalidateInFlightWork()
        currentState.gameMode = mode
        state = currentState
        persistState()
        logger.info("Game mode changed to \(mode.rawValue)")
    }

    var campaignExportFilename: String {
        let slug = [
            state?.scenarioID ?? selectedScenarioID,
            state?.country.code ?? "campaign",
            state?.gameDate ?? NativeGameEngine.todayStamp()
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
        guard data.count <= Self.maximumCampaignImportBytes else {
            throw NativeCampaignStoreError.campaignImportTooLarge(
                actualBytes: data.count,
                maximumBytes: Self.maximumCampaignImportBytes
            )
        }
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
            defaults.set(data, forKey: slotKey(Self.selectedCountryKey))
        }
        defaults.set(selectedScenarioID, forKey: slotKey(Self.selectedScenarioKey))
        defaults.set(selectedLanguage.rawValue, forKey: slotKey(Self.selectedLanguageKey))
        persistState()
        logger.info("Native campaign imported bytes=\(data.count, privacy: .public) scenario=\(self.selectedScenarioID, privacy: .public)")
    }

    func addDraftAction() {
        guard var state else { return }
        let action = NativeGameEngine.action(from: draftAction, date: state.gameDate)
        guard let action else {
            lastError = nil
            return
        }
        let cost = NativeGameEngine.estimateDirectiveCost(for: action.detail)
        if state.administrativeCapacity < cost {
            lastError = "Insufficient administrative capacity. This directive requires \(cost) capacity."
            return
        }

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
            id: "action-\(state.round)-\(state.plannedActions.count + 1)",
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
            source: "ai-suggestion",
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
                state.administrativeCapacity = min(Self.maximumAdministrativeCapacity, state.administrativeCapacity + cost)
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
                state.administrativeCapacity = min(Self.maximumAdministrativeCapacity, state.administrativeCapacity + cost)
            }
            state.plannedActions.remove(at: index)
        }
        state.actionMemory.removeAll { removedIDs.contains($0.actionID) && $0.status == .planned }
        self.state = state
        persistState()
        logger.info("Native actions deleted count=\(offsets.count, privacy: .public)")
    }

    func checkAIStatus() async {
        guard var state else { return }
        let requestVersion = stateVersion
        let readiness = await aiService.checkReadiness()
        guard isCurrentStateVersion(requestVersion) else { return }
        invalidateInFlightWork()
        state.aiReadiness = readiness
        self.state = state
        persistState()
        logger.info("Native AI readiness checked availability=\(readiness.availability, privacy: .public)")
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
            id: "advisor-leader-\(currentState.round)-\(currentState.advisorMessages.count + 1)",
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
                    id: "advisor-ai-\(currentState.round)-\(currentState.advisorMessages.count + 2)",
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
            lastAdvisorError = "\(error.localizedDescription) The advisor transcript was preserved; verify the selected AI provider and retry."
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
            id: "diplomacy-leader-\(currentState.round)-\(currentState.diplomaticThreads.count + 1)",
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
                    id: "diplomacy-\(partner.code.lowercased())-\(currentState.round)",
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

    // MARK: - Turn advancement with cancellation support

    private var advanceTask: Task<Void, Never>?

    /// Public entry point — creates and stores a cancellable Task.
    func advance(months: Int) {
        guard !isAdvancing else { return }
        advanceTask?.cancel()
        advanceTask = Task { [weak self] in
            await self?.performAdvance(months: months)
        }
    }

    /// Cancels any in-flight turn generation (e.g. on reset/import).
    func cancelInFlightTurn() {
        advanceTask?.cancel()
        advanceTask = nil
        invalidateInFlightWork()
    }

    func performAdvance(months: Int) async {
        guard var currentState = state, !isAdvancing else { return }
        guard currentState.victoryStatus == .ongoing else {
            lastError = "This campaign has already ended. Start or import a new campaign to continue playing."
            return
        }
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
        let providerRoute = Self.currentAIProviderRoute(defaults: defaults)
        turnProgress = NativeTurnProgress(
            completedLanes: 0,
            detail: providerRoute.detail,
            phase: "Preparing turn",
            totalLanes: laneCount,
            providerName: providerRoute.provider,
            modelName: providerRoute.model,
            modelIdentifier: providerRoute.identifier
        )
        var shouldRefreshSuggestions = false

        do {
            let generated = try await aiService.generateTurn(for: currentState, months: months) { [weak self] progress in
                guard let self, isCurrentStateVersion(requestVersion) else { return }
                turnProgress = progress
            }
            guard isCurrentStateVersion(requestVersion) else { return }
            let activeRoute = turnProgress.map { ($0.providerName, $0.modelName, $0.modelIdentifier) }
            turnProgress = NativeTurnProgress(
                completedLanes: max(0, laneCount - 1),
                detail: "Checking dates, linked actions, and visible consequences.",
                phase: "Validating turn",
                totalLanes: laneCount,
                providerName: activeRoute?.0,
                modelName: activeRoute?.1,
                modelIdentifier: activeRoute?.2
            )
            let validated = try NativeGameEngine.validated(generated, state: currentState, months: months)
            turnProgress = NativeTurnProgress(
                completedLanes: laneCount,
                detail: "Updating budgets, fiscal space, action memory, and campaign effects.",
                phase: "Applying economics",
                totalLanes: laneCount,
                providerName: activeRoute?.0,
                modelName: activeRoute?.1,
                modelIdentifier: activeRoute?.2
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
        guard !isAdvancing else { return }
        guard let state, state.suggestedActions.isEmpty else { return }
        await refreshSuggestedActions(force: false)
    }

    func refreshSuggestedActions(force: Bool) async {
        guard var currentState = state else { return }
        guard !isAdvancing else {
            pendingSuggestionRefreshForce = (pendingSuggestionRefreshForce ?? false) || force
            return
        }
        guard !isLoadingSuggestions else {
            pendingSuggestionRefreshForce = (pendingSuggestionRefreshForce ?? false) || force
            return
        }
        guard force || currentState.suggestedActions.isEmpty else { return }

        isLoadingSuggestions = true
        lastSuggestionError = nil
        let requestVersion = stateVersion
        defer {
            isLoadingSuggestions = false
            if let pendingForce = pendingSuggestionRefreshForce {
                pendingSuggestionRefreshForce = nil
                Task { await refreshSuggestedActions(force: pendingForce) }
            }
        }

        do {
            let suggestions = try await suggestionsWithTimeout(for: currentState)
            guard isCurrentStateVersion(requestVersion) else { return }
            currentState.suggestedActions = suggestions
            currentState.aiReadiness = .available(tokenBudget: "sliced-guided-generation context=4096, suggestions=4x180")
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
            state = currentState
            lastSuggestionError = error.localizedDescription
            persistState()
            logger.error("Native suggested actions refresh failed")
        }
    }

    private func suggestionsWithTimeout(for state: NativeCampaignState) async throws -> [NativeSuggestedAction] {
        let suggestionTask = Task { @MainActor [aiService] in
            try await aiService.generateSuggestedActions(for: state)
        }
        let timeoutTask = Task<[NativeSuggestedAction], Error> {
            try await Task.sleep(nanoseconds: Self.suggestionRefreshTimeoutNanoseconds)
            throw NativeCampaignStoreError.suggestionRefreshTimedOut
        }

        return try await withThrowingTaskGroup(of: [NativeSuggestedAction].self) { group in
            group.addTask { try await suggestionTask.value }
            group.addTask { try await timeoutTask.value }
            defer {
                group.cancelAll()
                suggestionTask.cancel()
                timeoutTask.cancel()
            }

            return try await group.next() ?? []
        }
    }

    func invalidateInFlightWork() {
        advanceTask?.cancel()
        advanceTask = nil
        stateVersion += 1
    }

    func isCurrentStateVersion(_ version: Int) -> Bool {
        stateVersion == version
    }

    private static func normalizedScenarioID(_ value: String?) -> String {
        let rawID = sanitizeFoundationModelText(value ?? "")
        return NativeScenarioCatalog.scenario(for: rawID).id
    }

    private static func normalizedBudgetSliders(
        military: Double,
        services: Double,
        diplomacy: Double
    ) -> (military: Double, services: Double, diplomacy: Double) {
        var values = [military, services, diplomacy].map { value in
            value.isFinite ? Swift.max(0.0, Swift.min(1.0, value)) : 0.0
        }
        let total = values.reduce(0.0, +)
        if total > 0 {
            values = values.map { $0 / total }
        } else {
            values = [0.33, 0.34, 0.33]
        }
        return (values[0], values[1], values[2])
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
        state.administrativeCapacity = Swift.max(0, Swift.min(maximumAdministrativeCapacity, state.administrativeCapacity))
        let sliders = normalizedBudgetSliders(
            military: state.budgetMilitarySlider,
            services: state.budgetServicesSlider,
            diplomacy: state.budgetDiplomacySlider
        )
        state.budgetMilitarySlider = sliders.military
        state.budgetServicesSlider = sliders.services
        state.budgetDiplomacySlider = sliders.diplomacy
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
            "\(action.title) has been placed before the cabinet. Its concrete consequences will be resolved on the next time jump."
        case .portuguese:
            "\(action.title) foi colocado diante do gabinete. Suas consequências concretas serão resolvidas no próximo salto de tempo."
        case .spanish:
            "\(action.title) fue puesto ante el gabinete. Sus consecuencias concretas se resolverán en el próximo salto temporal."
        }
    }

    private static func acceptedSuggestionSummary(for action: NativePlannedAction, language: NativeGameLanguage) -> String {
        switch language {
        case .english:
            "\(action.title) has been accepted as a planned order. The selected AI provider will resolve its impact on the next time jump."
        case .portuguese:
            "\(action.title) foi aceito como ordem planejada. O provedor de IA selecionado resolverá seu impacto no próximo salto de tempo."
        case .spanish:
            "\(action.title) fue aceptado como orden planificada. El proveedor de IA seleccionado resolverá su impacto en el próximo salto temporal."
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
        guard var state else { return }
        invalidateInFlightWork()
        let normalized = Self.normalizedBudgetSliders(
            military: military,
            services: services,
            diplomacy: diplomacy
        )
        state.budgetMilitarySlider = normalized.military
        state.budgetServicesSlider = normalized.services
        state.budgetDiplomacySlider = normalized.diplomacy
        self.state = state
        persistState()
    }

    func acceptDiplomaticOffer(id: String) {
        guard var state else { return }
        guard let idx = state.activeOffers.firstIndex(where: { $0.id == id && $0.status == .pending }) else { return }
        invalidateInFlightWork()
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
                id: "ledger-entry-offer-accept-\(id)",
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
            id: "offer-accept-event-\(id)",
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
        guard var state else { return }
        guard let idx = state.activeOffers.firstIndex(where: { $0.id == id && $0.status == .pending }) else { return }
        invalidateInFlightWork()
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
            id: "offer-reject-event-\(id)",
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
        guard var state else { return }
        guard let idx = state.activeOffers.firstIndex(where: { $0.id == id && $0.status == .pending }) else { return }
        invalidateInFlightWork()
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
                    id: "ledger-entry-offer-counter-accept-\(id)",
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
                id: "offer-counter-accept-event-\(id)",
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
                id: "offer-counter-reject-event-\(id)",
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
    case campaignImportTooLarge(actualBytes: Int, maximumBytes: Int)
    case noCampaignToExport
    case suggestionRefreshTimedOut

    var errorDescription: String? {
        switch self {
        case let .campaignImportTooLarge(actualBytes, maximumBytes):
            let actualMB = Double(actualBytes) / 1_000_000.0
            let maximumMB = Double(maximumBytes) / 1_000_000.0
            return String(format: "Campaign import is too large (%.1f MB). Maximum supported size is %.1f MB.", actualMB, maximumMB)
        case .noCampaignToExport:
            return "There is no native campaign to export yet."
        case .suggestionRefreshTimedOut:
            return "Suggested actions took too long to refresh. Keep drafting manual orders or retry from Settings after checking the selected AI provider."
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
