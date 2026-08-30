import Foundation
import OSLog

/// Player-selectable OpenRouter AI service using the unified free-model route.
/// Routing is strict: NVIDIA failures never enter this service automatically.
///
/// Inherits ALL prompt construction, JSON decoding, validation, and retry logic
/// from `NativeZAIService` — only the endpoint, API key, model list, and thinking
/// field differ. OpenRouter uses the same OpenAI-compatible chat completions API.
@MainActor
class NativeOpenRouterService: NativeZAIService {
    private let orLogger = Logger(subsystem: "com.gibavargas.SwiftHistoria", category: "NativeOpenRouterService")
    private var openRouterModelLanes: [ZAIModelLane] = [
        ZAIModelLane(name: "openrouter/free", displayName: "Free Models Router", maxConcurrent: 3)
    ]

    /// Unified free-model router exposed at https://openrouter.ai/openrouter/free.
    /// Use one lane so every OpenRouter call goes through the same provider-managed
    /// free route instead of hard-coding individual `:free` model slugs.
    override var modelLanes: [ZAIModelLane] {
        get {
            openRouterModelLanes
        }
        set {
            openRouterModelLanes = newValue
        }
    }

    override var apiKey: String {
        NativeSecretStore.string(forKey: "OPENROUTER_API_KEY", defaults: defaults) ?? ""
    }

    override var useCodingEndpoint: Bool {
        false
    }

    override var apiEndpoint: URL {
        URL(string: "https://openrouter.ai/api/v1/chat/completions")!
    }

    override var includesThinkingField: Bool {
        false
    }

    override var includesMaxTokensField: Bool {
        false
    }

    override var supportsStreaming: Bool {
        true
    }

    override var supportsReasoningStreaming: Bool {
        true
    }

    override var providerDisplayName: String {
        "OpenRouter"
    }

    override var routeDisplayName: String {
        "OpenRouter Free API"
    }

    override func checkReadiness() async -> NativeAIReadiness {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if key.isEmpty {
            return .unavailable("OpenRouter API Key not configured in System Settings.")
        }
        orLogger.info("OpenRouter readiness configured for openrouter/free without spending a free-router request")
        return .available(tokenBudget: "OpenRouter free router configured; live calls validate on use")
    }

    override func generateTurn(
        for state: NativeCampaignState,
        months: Int,
        progress: @escaping @MainActor (NativeTurnProgress) -> Void
    ) async throws -> NativeGeneratedTurn {
        let totalLanes = NativeStrategyContextDatabase.estimatedLaneCount(for: state)
        var reasoningStatus = NativeReasoningStatus.waiting
        var reasoningText = "Waiting for the selected free model to expose reasoning."
        var activeModelIdentifier = primaryModelIdentifier

        func publishProgress(completedLanes: Int, detail: String, phase: String) {
            progress(NativeTurnProgress(
                completedLanes: completedLanes,
                detail: detail,
                phase: phase,
                totalLanes: totalLanes,
                providerName: providerDisplayName,
                modelName: primaryModelDisplayName,
                modelIdentifier: activeModelIdentifier,
                reasoningStatus: reasoningStatus,
                reasoningText: reasoningText
            ))
        }

        func receiveReasoning(_ update: NativeReasoningStreamUpdate, completedLanes: Int, detail: String, phase: String) {
            reasoningStatus = update.status
            reasoningText = update.text
            if let modelIdentifier = update.modelIdentifier, !modelIdentifier.isEmpty {
                activeModelIdentifier = modelIdentifier
            }
            publishProgress(completedLanes: completedLanes, detail: detail, phase: phase)
        }

        progress(NativeTurnProgress(
            completedLanes: 0,
            detail: "Calling OpenRouter Free with split prompts (consequences + world events).",
            phase: "Consulting OpenRouter",
            totalLanes: totalLanes,
            providerName: providerDisplayName,
            modelName: primaryModelDisplayName,
            modelIdentifier: primaryModelIdentifier,
            reasoningStatus: reasoningStatus,
            reasoningText: reasoningText
        ))

        // ── D3: Try split prompts first ──────────────────────────
        do {
            // Call 1: Player action consequences
            let consequenceResponse = try await executeProviderRequest(
                prompt: makeConsequenceOnlyPrompt(for: state, months: months, repairInstruction: nil),
                maxTokens: 1800,
                temperature: NativeTemperaturePolicy.consequencePass,
                responseFormat: "json_object",
                thinkingEnabled: true,
                onReasoningProgress: { update in
                    receiveReasoning(
                        update,
                        completedLanes: 0,
                        detail: "Resolving queued orders and their immediate consequences.",
                        phase: "Reasoning about orders"
                    )
                }
            )
            let consequenceResult = try OpenRouterTurnParser.turn(from: consequenceResponse, state: state, months: months)

            // Call 2: World events (merge into consequence result)
            var mergedResult = consequenceResult
            do {
                reasoningStatus = .waiting
                reasoningText = "Starting a second reasoning pass for world events."
                activeModelIdentifier = primaryModelIdentifier
                publishProgress(
                    completedLanes: max(1, totalLanes / 2),
                    detail: "Player consequences resolved; consulting the world-event model pass.",
                    phase: "Reasoning about the world"
                )
                let worldResponse = try await executeProviderRequest(
                    prompt: makeWorldEventOnlyPrompt(for: state, months: months),
                    maxTokens: 1200,
                    temperature: NativeTemperaturePolicy.consequencePass,
                    responseFormat: "json_object",
                    thinkingEnabled: true,
                    onReasoningProgress: { update in
                        receiveReasoning(
                            update,
                            completedLanes: max(1, totalLanes / 2),
                            detail: "Simulating world events and external reactions.",
                            phase: "Reasoning about the world"
                        )
                    }
                )
                let parsed = try OpenRouterTurnParser.turn(from: worldResponse, state: state, months: months)
                mergedResult.events.append(contentsOf: parsed.events)
                mergedResult.stabilityDelta += parsed.stabilityDelta
                mergedResult.worldTensionDelta += parsed.worldTensionDelta
            } catch {
                orLogger.warning("OpenRouter world-event split call failed; continuing with consequence-only events: \(error.localizedDescription, privacy: .public)")
            }

            let validated = try NativeGameEngine.validated(mergedResult, state: state, months: months)
            progress(NativeTurnProgress(
                completedLanes: totalLanes,
                detail: "OpenRouter split turn validated (events=\(validated.events.count)).",
                phase: NativeFoundationTurnLane.summary.title,
                totalLanes: totalLanes,
                providerName: providerDisplayName,
                modelName: primaryModelDisplayName,
                modelIdentifier: activeModelIdentifier,
                reasoningStatus: reasoningStatus,
                reasoningText: reasoningText
            ))
            orLogger.info("OpenRouter split turn validated events=\(validated.events.count, privacy: .public)")
            return validated

        } catch is CancellationError {
            orLogger.warning("OpenRouter split turn cancelled.")
            throw CancellationError()
        } catch {
            if isRateLimitError(error) {
                orLogger.warning("OpenRouter split turn rate limited; not spending a repair retry.")
                throw error
            }
            orLogger.warning("OpenRouter split turn failed; falling back to unified prompt: \(error.localizedDescription, privacy: .public)")
        }

        // ── Fallback: unified prompt (existing logic preserved) ──
        reasoningStatus = .waiting
        reasoningText = "Restarting with a unified reasoning pass."
        activeModelIdentifier = primaryModelIdentifier
        publishProgress(
            completedLanes: 0,
            detail: "Falling back to OpenRouter unified prompt.",
            phase: "Consulting OpenRouter (unified)"
        )

        do {
            let turn = try await generateUnifiedTurn(
                for: state,
                months: months,
                repairInstruction: nil,
                onReasoningProgress: { update in
                    receiveReasoning(
                        update,
                        completedLanes: 0,
                        detail: "Resolving the complete turn in one model pass.",
                        phase: "Unified reasoning"
                    )
                }
            )
            let validated = try NativeGameEngine.validated(turn, state: state, months: months)
            progress(NativeTurnProgress(
                completedLanes: totalLanes,
                detail: "OpenRouter unified turn validated.",
                phase: NativeFoundationTurnLane.summary.title,
                totalLanes: totalLanes,
                providerName: providerDisplayName,
                modelName: primaryModelDisplayName,
                modelIdentifier: activeModelIdentifier,
                reasoningStatus: reasoningStatus,
                reasoningText: reasoningText
            ))
            orLogger.info("OpenRouter unified fallback validated events=\(validated.events.count, privacy: .public)")
            return validated
        } catch is CancellationError {
            orLogger.warning("OpenRouter unified turn cancelled; not retrying repair.")
            throw CancellationError()
        } catch {
            if isRateLimitError(error) {
                orLogger.warning("OpenRouter unified turn rate limited; not spending a repair retry.")
                throw error
            }
            orLogger.warning("OpenRouter unified turn failed; retrying once with repair instruction: \(error.localizedDescription, privacy: .public)")
            progress(NativeTurnProgress(
                completedLanes: max(0, totalLanes - 1),
                detail: "Repairing OpenRouter unified turn: \(error.localizedDescription)",
                phase: "Repairing turn",
                totalLanes: totalLanes,
                providerName: providerDisplayName,
                modelName: primaryModelDisplayName,
                modelIdentifier: activeModelIdentifier,
                reasoningStatus: reasoningStatus,
                reasoningText: reasoningText
            ))
            reasoningStatus = .waiting
            reasoningText = "The first unified response was invalid; reasoning through one repair pass."
            activeModelIdentifier = primaryModelIdentifier
            let repairedTurn = try await generateUnifiedTurn(
                for: state,
                months: months,
                repairInstruction: error.localizedDescription,
                onReasoningProgress: { update in
                    receiveReasoning(
                        update,
                        completedLanes: max(0, totalLanes - 1),
                        detail: "Repairing the response against the turn schema.",
                        phase: "Repair reasoning"
                    )
                }
            )
            let validated = try NativeGameEngine.validated(repairedTurn, state: state, months: months)
            progress(NativeTurnProgress(
                completedLanes: totalLanes,
                detail: "OpenRouter unified turn repair validated.",
                phase: NativeFoundationTurnLane.summary.title,
                totalLanes: totalLanes,
                providerName: providerDisplayName,
                modelName: primaryModelDisplayName,
                modelIdentifier: activeModelIdentifier,
                reasoningStatus: reasoningStatus,
                reasoningText: reasoningText
            ))
            orLogger.info("OpenRouter repaired unified turn validated events=\(validated.events.count, privacy: .public)")
            return validated
        }
    }

    private func isRateLimitError(_ error: Error) -> Bool {
        error.localizedDescription.localizedCaseInsensitiveContains("rate limited") ||
            error.localizedDescription.localizedCaseInsensitiveContains("429")
    }

    override func generateSuggestedActions(for state: NativeCampaignState) async throws -> [NativeSuggestedAction] {
        let prompt = NativeDecisionMatrixPrompt.makeOpenRouterSafe(for: state)
        var lastFailure = "No response was validated."
        var repairNote = ""
        for attempt in 1 ... 2 {
            let rawResponse = try await executeProviderRequest(
                prompt: prompt + repairNote,
                maxTokens: 8000,
                temperature: attempt == 1 ? NativeTemperaturePolicy.matrixFirst : NativeTemperaturePolicy.matrixRepair,
                responseFormat: "json_object",
                thinkingEnabled: false,
                requestTimeout: 45,
                retryLimit: 0
            )

            let suggestions = OpenRouterSuggestionParser.suggestions(from: rawResponse, state: state)
            do {
                let matrix = try NativeDecisionMatrixContract.validatedPlayerMatrix(suggestions, state: state)
                orLogger.info("OpenRouter decision matrix validated cells=\(matrix.count, privacy: .public)")
                return matrix
            } catch {
                lastFailure = error.localizedDescription
                orLogger.warning("OpenRouter decision matrix invalid count=\(suggestions.count, privacy: .public) attempt=\(attempt, privacy: .public): \(lastFailure, privacy: .public)")
                if let tailored = try? NativeDecisionMatrixContract.aiTailoredPlayerMatrix(from: suggestions, state: state) {
                    orLogger.info("OpenRouter tailored the engine-owned legal matrix cells=\(tailored.count, privacy: .public)")
                    return tailored
                }
                repairNote = """

                REPAIR: The previous board was rejected: \(lastFailure)
                Return a complete replacement object with exactly 25 eligible suggestions, every matrixRow/matrixColumn pair 0...4 exactly once. Do not return only repaired cells. Recheck each cost, target, political directive, region directive, and sovereignty precondition against the unchanged world snapshot.
                """
            }
        }

        throw NativeFoundationModelError.invalidSuggestedActions(
            "OpenRouter Free could not produce a legal 5 x 5 decision matrix after repair. \(lastFailure)"
        )
    }

    private func generateUnifiedTurn(
        for state: NativeCampaignState,
        months: Int,
        repairInstruction: String?,
        onReasoningProgress: (@MainActor (NativeReasoningStreamUpdate) -> Void)?
    ) async throws -> NativeGeneratedTurn {
        let rawResponse = try await executeProviderRequest(
            prompt: unifiedTurnPrompt(for: state, months: months, repairInstruction: repairInstruction),
            maxTokens: 2600,
            temperature: repairInstruction == nil ? NativeTemperaturePolicy.unifiedTurn : NativeTemperaturePolicy.unifiedRepair,
            responseFormat: "json_object",
            thinkingEnabled: true,
            onReasoningProgress: onReasoningProgress
        )
        return try OpenRouterTurnParser.turn(from: rawResponse, state: state, months: months)
    }

    private func unifiedTurnPrompt(
        for state: NativeCampaignState,
        months: Int,
        repairInstruction: String?
    ) -> String {
        let targetDate = NativeGameEngine.advance(date: state.gameDate, months: months)
        let plannedActions = Array(state.plannedActions.filter { $0.status == .planned }.prefix(NativeDecisionMatrixContract.maximumOrdersPerTurn))
        let actionLines = openRouterOrderLines(plannedActions)
        let objectives = NativeGameEngine.campaignObjectives(for: state)
        let objectiveLines = objectives.isEmpty
            ? "No explicit campaign objectives."
            : objectives.prefix(4).map { objective in
                "- \(objective.title): \(objective.currentValue) -> \(objective.targetValue) by \(objective.deadline). \(objective.detail)"
            }.joined(separator: "\n")
        let recentEvents = state.timeline.prefix(4).map { "- \($0.date): \($0.title)" }.joined(separator: "\n")
        let repairBlock = repairInstruction.map {
            """

            Repair instruction from validator:
            \($0)
            """
        } ?? ""

        return """
        Resolve one SwiftHistoria turn in a single OpenRouter Free response.
        Current campaign:
        - Country: \(state.country.name) (\(state.country.code))
        - Scenario: \(state.scenarioName)
        - Round: \(state.round)
        - Current date: \(state.gameDate)
        - Target date: \(targetDate)
        - Stability: \(state.stability)
        - World tension: \(state.worldTension)
        - Administrative capacity: \(state.administrativeCapacity)

        \(openRouterMechanicsContext(for: state))

        Campaign objectives:
        \(objectiveLines)

        Player orders to resolve:
        \(actionLines)

        Recent events to avoid repeating:
        \(recentEvents.isEmpty ? "No recent events." : recentEvents)
        \(repairBlock)

        Return one strict JSON object only. Do not include markdown fences, prose, comments, or schema labels.
        Required JSON schema:
        {
          "summary": "One concrete sentence summarizing the period.",
          "stabilityDelta": -3,
          "worldTensionDelta": 1,
          "events": [
            {
              "title": "Strict short news headline.",
              "description": "Concrete 1-2 sentence event description with agencies, dates, and measurable effect.",
              "kind": "action, economy, diplomacy, or world",
              "importance": "minor, major, or severe",
              "notable": true,
              "playerRelated": false,
              "linkedActionID": null,
              "effectTarget": "Country code like \(state.country.code) or GLOBAL",
              "effectTrack": "⟦ECO⟧|⟦MKT⟧|⟦STB⟧|⟦SEC⟧|⟦DIP⟧|⟦MIL⟧|⟦TNS⟧",
              "effectMagnitude": -3,
              "effectSummary": "One concise sentence describing the game mechanics effect.",
              "hexLeverCode": null,
              "sovereigntyChange": null
            }
          ]
        }

        Event requirements:
        - Return 4 to 6 events.
        - Include at least one playerRelated=false world event.
        - Include one playerRelated=true event for each queued order above, using its exact linkedActionID.
        - Dates are assigned by the game engine; do not include date fields.
        - Keep every event concrete and avoid placeholder words like Native, Generated, Draft, Schema, Placeholder.
        \(NativeStrategicTrack.mechanicCodebookPrompt)
        Valid "kind" values: action, diplomacy, economy, world. Valid "importance" values: minor, major, severe.
        Each linked action event must output the exact code corresponding to one of that order's listed mechanicTracks. Copy structured sovereigntyChange only from its linked order; otherwise use null.
        effectTarget must be GLOBAL, \(state.country.code), or a country/region identifier explicitly present in the mechanics context. Never invent a target.

        Example events:
        1. Player-related event resolving a logistics order:
           {"title":"Port Modernization Phase 1 Begins","description":"The National Infrastructure Authority commenced Phase 1 of the coastal port upgrade, deploying 2,400 workers to expand container capacity by 35%.","kind":"action","importance":"major","notable":true,"playerRelated":true,"linkedActionID":"action-3-1","effectTarget":"BRA","effectTrack":"⟦ECO⟧","effectMagnitude":3,"effectSummary":"Infrastructure investment boosts economic resilience by 3.","hexLeverCode":"0x4D21F4","sovereigntyChange":null}
        2. World event unrelated to the player:
           {"title":"OPEC Announces Supply Restructuring","description":"The Organization of Petroleum Exporting Countries agreed to reduce daily output by 2.1 million barrels, signaling tighter global energy markets.","kind":"world","importance":"major","notable":true,"playerRelated":false,"linkedActionID":null,"effectTarget":"GLOBAL","effectTrack":"⟦MKT⟧","effectMagnitude":-2,"effectSummary":"Energy supply tightening reduces global market confidence by 2.","hexLeverCode":"0xCD42D8","sovereigntyChange":null}
        """
    }

    // MARK: - D1: Compact context for free models

    /// Compact recent context for free models — strips canon and strategy database.
    private func compactRecentContext(for state: NativeCampaignState) -> String {
        let recent = state.timeline
            .prefix(2)
            .map { "- \(safeTitle($0.title)): \(safeTitle($0.description).prefix(80))" }
            .joined(separator: "\n")
        let objectives = NativeGameEngine.campaignObjectives(for: state)
            .prefix(2)
            .map { "- \($0.title): \($0.currentValue)/\($0.targetValue)" }
            .joined(separator: "\n")
        return """
        Round: \(state.round) | Date: \(state.gameDate)
        Stability: \(state.stability)/100 | Tension: \(state.worldTension)/100
        Capacity: \(state.administrativeCapacity)/120
        Objectives:
        \(objectives.isEmpty ? "None." : objectives)
        Recent events:
        \(recent.isEmpty ? "None." : recent)
        """
    }

    private func safeTitle(_ text: String) -> String {
        String(text.prefix(100)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - D3: Split prompts (consequences + world events)

    private func makeConsequenceOnlyPrompt(
        for state: NativeCampaignState,
        months: Int,
        repairInstruction: String?
    ) -> String {
        let targetDate = NativeGameEngine.advance(date: state.gameDate, months: months)
        let plannedActions = Array(state.plannedActions.filter { $0.status == .planned }.prefix(NativeDecisionMatrixContract.maximumOrdersPerTurn))
        let actionLines = openRouterOrderLines(plannedActions)
        let recentEvents = state.timeline.prefix(3).map { "- \($0.date): \($0.title)" }.joined(separator: "\n")
        let repairBlock = repairInstruction.map {
            "\nRepair instruction from validator:\n\($0)"
        } ?? ""

        return """
        Resolve player action consequences for one SwiftHistoria turn.
        Country: \(state.country.name) (\(state.country.code)) | Round: \(state.round) | Date: \(state.gameDate) → \(targetDate)
        \(openRouterMechanicsContext(for: state))
        Player orders to resolve:
        \(actionLines)
        Recent events: \(recentEvents.isEmpty ? "None." : recentEvents)
        \(repairBlock)
        Return one strict JSON object only. No markdown fences or prose.
        Required JSON schema:
        {
          "summary": "One concrete sentence.",
          "stabilityDelta": 0,
          "worldTensionDelta": 0,
          "events": [
            {
              "title": "Short news headline.",
              "description": "Concrete 1-2 sentence description.",
              "kind": "action, diplomacy, or economy",
              "importance": "minor, major, or severe",
              "notable": true,
              "playerRelated": true,
              "linkedActionID": "action-id-from-orders-above-or-null",
              "effectTarget": "\(state.country.code)",
              "effectTrack": "⟦ECO⟧|⟦MKT⟧|⟦STB⟧|⟦SEC⟧|⟦DIP⟧|⟦MIL⟧|⟦TNS⟧",
              "effectMagnitude": -3,
              "effectSummary": "Concise game mechanics effect.",
              "hexLeverCode": null,
              "sovereigntyChange": null
            }
          ]
        }
        Produce 1 event per queued player order. If no orders, produce 1 domestic planning event.
        If an order includes structured sovereignty metadata, copy it exactly into that order's event sovereigntyChange. Do not create sovereigntyChange for any other order.
        \(NativeStrategicTrack.mechanicCodebookPrompt)
        Valid "kind" values: action, diplomacy, economy. Valid "importance" values: minor, major, severe.
        Each event's effectTrack code must correspond to one of its linked order's mechanicTracks. Preserve exact linkedActionID, target, and structured sovereignty metadata from that order.
        """
    }

    private func makeWorldEventOnlyPrompt(
        for state: NativeCampaignState,
        months: Int
    ) -> String {
        let targetDate = NativeGameEngine.advance(date: state.gameDate, months: months)
        let recentEvents = state.timeline.prefix(3).map { "- \($0.date): \($0.title)" }.joined(separator: "\n")

        return """
        Generate world events for one SwiftHistoria turn.
        Country: \(state.country.name) (\(state.country.code)) | Round: \(state.round) | Period: \(state.gameDate) → \(targetDate)
        \(openRouterMechanicsContext(for: state))
        Recent events: \(recentEvents.isEmpty ? "None." : recentEvents)
        Already-used event titles: \(state.timeline.prefix(4).map(\.title).joined(separator: "; "))
        Return one strict JSON object only. No markdown fences or prose.
        Required JSON schema:
        {
          "summary": "One concrete sentence.",
          "stabilityDelta": 0,
          "worldTensionDelta": 0,
          "events": [
            {
              "title": "Short world news headline.",
              "description": "Concrete 1-2 sentence description.",
              "kind": "world or economy",
              "importance": "minor, major, or severe",
              "notable": true,
              "playerRelated": false,
              "linkedActionID": null,
              "effectTarget": "GLOBAL or country code",
              "effectTrack": "⟦ECO⟧|⟦MKT⟧|⟦STB⟧|⟦SEC⟧|⟦DIP⟧|⟦MIL⟧|⟦TNS⟧",
              "effectMagnitude": -2,
              "effectSummary": "Concise game mechanics effect.",
              "hexLeverCode": null,
              "sovereigntyChange": null
            }
          ]
        }
        Produce 1-2 world events unrelated to the player.
        \(NativeStrategicTrack.mechanicCodebookPrompt)
        Valid "kind" values: economy, world. Valid "importance" values: minor, major, severe.
        World events must have linkedActionID=null, playerRelated=false, and sovereigntyChange=null. effectTarget must be GLOBAL or an existing country code from the mechanics context.
        """
    }

    private func openRouterOrderLines(_ actions: [NativePlannedAction]) -> String {
        guard !actions.isEmpty else { return "No player orders queued." }
        return actions.enumerated().map { index, action in
            let sovereignty = action.sovereigntyChange.map {
                "{kind:\($0.kind.rawValue),name:\($0.name),regions:\($0.regionIDs),sources:\($0.sourceCodes),target:\($0.targetCode)}"
            } ?? "null"
            return "\(index + 1). id=\(action.id); kind=\(action.decisionKind); cost=\(action.administrativeCost); mechanicCodes=\(action.mechanicTracks.map(\.mechanicCode)); targetCountry=\(action.targetCountryCode ?? "none"); targetRegion=\(action.targetRegionID ?? "none"); sovereigntyChange=\(sovereignty); title=\(action.title); detail=\(action.detail)"
        }.joined(separator: "\n")
    }

    private func openRouterMechanicsContext(for state: NativeCampaignState) -> String {
        let ledger = state.economicLedger
        let conflicts = state.regionConflicts.values.sorted { $0.regionID < $1.regionID }.prefix(6).map {
            "\($0.regionID):owner=\($0.originalCountryCode),controller=\($0.controllerCode),mode=\($0.mode.rawValue),intensity=\($0.intensity)"
        }.joined(separator: "; ")
        let diplomacy = state.aiCountryStates.sorted { $0.key < $1.key }.prefix(12).map { code, ai in
            "\(code):relation=\(ai.relationshipScores[state.country.code] ?? 0),doctrine=\(ai.doctrine.rawValue),agenda=\(ai.agendaProgress)%"
        }.joined(separator: "; ")
        return """
        Mechanics snapshot (authoritative):
        capacity=\(state.administrativeCapacity)/120; queueLimit=\(NativeDecisionMatrixContract.maximumOrdersPerTurn); stability=\(state.stability)/100; worldTension=\(state.worldTension)/100
        government=\(ledger.governmentType); approval=\(String(format: "%.1f", ledger.publicApprovalPercent))%; nextElectionRound=\(ledger.nextElectionRound)
        GDP=\(ledger.nominalGDPTrillions)T; growth=\(ledger.realGrowthPercent)%; inflation=\(ledger.inflationPercent)%; budget=\(String(format: "%.1f", ledger.budgetBalancePercentGDP))%; debt=\(String(format: "%.1f", ledger.publicDebtPercentGDP))%; trade=\(String(format: "%.1f", ledger.tradeBalancePercentGDP))%; unemployment=\(String(format: "%.1f", ledger.unemploymentPercent))%; fiscalSpace=\(ledger.fiscalSpaceIndex)/100; security=\(String(format: "%.0f", ledger.securityIndex))/100; rebels=\(String(format: "%.1f", ledger.rebelControlPercent))%
        researchEra=\(state.techEra); researchPoints=\(state.researchPoints); units=\(state.militaryUnits.sorted { $0.key < $1.key })
        conflicts=\(conflicts.isEmpty ? "none" : conflicts)
        diplomacy=\(diplomacy.isEmpty ? "none" : diplomacy)
        existingCountryCodes=\(NativeStrategyContextDatabase.strategicCountryCodes(for: state).filter { $0 != "GLOBAL" }.joined(separator: ","))
        """
    }
}

enum OpenRouterSuggestionParser {
    static func suggestions(from rawResponse: String, state: NativeCampaignState) -> [NativeSuggestedAction] {
        for candidate in NativeJSONExtraction.candidates(from: rawResponse) {
            guard let data = candidate.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data)
            else {
                continue
            }

            let dictionaries = suggestionDictionaries(from: object)
            let suggestions = dictionaries.enumerated().compactMap { index, dictionary in
                nativeSuggestion(from: dictionary, state: state, index: index)
            }
            if !suggestions.isEmpty { return suggestions }
        }
        return []
    }

    private static func suggestionDictionaries(from object: Any) -> [[String: Any]] {
        if let array = object as? [[String: Any]] {
            return array
        }
        guard let dictionary = object as? [String: Any] else { return [] }
        for key in ["suggestions", "suggestedActions", "actions", "orders", "recommendations", "proposals"] {
            if let array = dictionary[key] as? [[String: Any]] {
                return array
            }
        }
        return []
    }

    private static func nativeSuggestion(
        from dictionary: [String: Any],
        state: NativeCampaignState,
        index: Int
    ) -> NativeSuggestedAction? {
        guard let title = firstString(dictionary, keys: ["title", "name", "order", "action", "proposal"]) else {
            return nil
        }

        let summary = firstString(dictionary, keys: ["detail", "details", "summary", "description", "expectedOutcome", "outcome"]) ?? ""
        let instrument = firstString(dictionary, keys: ["instrument", "policy", "measure", "category"]) ?? ""
        let risk = firstString(dictionary, keys: ["risk", "tradeoff", "tradeOff"]) ?? ""
        let rationale = firstString(dictionary, keys: ["rationale", "reason", "why", "justification"]) ?? summary
        let primaryMechanic = firstString(dictionary, keys: ["primaryMechanic", "primary_mechanic", "mechanic"]) ?? ""
        let secondaryMechanic = firstString(dictionary, keys: ["secondaryMechanic", "secondary_mechanic"]) ?? ""
        let actionKind = firstString(dictionary, keys: ["actionKind", "action_kind", "kind", "type"]) ?? "policy"
        let targetCountryCode = firstString(dictionary, keys: ["targetCountryCode", "target_country_code", "countryCode", "target"])
        let targetRegionID = firstString(dictionary, keys: ["targetRegionID", "target_region_id", "regionID", "regionId"])
        let matrixRow = intValue(dictionary["matrixRow"] ?? dictionary["row"]) ?? -1
        let matrixColumn = intValue(dictionary["matrixColumn"] ?? dictionary["column"]) ?? -1
        let administrativeCost = intValue(dictionary["administrativeCost"] ?? dictionary["cost"]) ?? 0
        let sovereigntyChange = parsedOpenRouterSovereignty(dictionary["sovereigntyChange"] ?? dictionary["sovereignty_change"])

        let detailParts = [
            summary,
            instrument.isEmpty ? "" : "Instrument: \(instrument).",
            risk.isEmpty ? "" : "Risk: \(risk)."
        ].filter { !$0.isEmpty }

        guard !detailParts.isEmpty else { return nil }

        let rationaleParts = [
            rationale,
            "It respects current campaign objectives and administrative capacity."
        ]

        return NativeSuggestedAction(
            detail: sanitizeFoundationModelText(detailParts.joined(separator: " ")),
            id: "suggestion-\(state.country.code.lowercased())-\(state.round)-openrouter-\(index + 1)",
            rationale: sanitizeFoundationModelText(rationaleParts.joined(separator: " ")),
            title: sanitizeFoundationModelText(title),
            urgency: normalizedFoundationUrgency(firstString(dictionary, keys: ["urgency", "priority", "timing"]) ?? "soon"),
            primaryMechanic: sanitizeFoundationModelText(primaryMechanic),
            secondaryMechanic: sanitizeFoundationModelText(secondaryMechanic),
            actionKind: sanitizeFoundationModelText(actionKind).lowercased(),
            administrativeCost: administrativeCost,
            matrixRow: matrixRow,
            matrixColumn: matrixColumn,
            targetCountryCode: targetCountryCode,
            targetRegionID: targetRegionID,
            sovereigntyChange: sovereigntyChange
        )
    }

    private static func firstString(_ dictionary: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if dictionary[key] is NSNull { continue }
            if let value = dictionary[key] as? String {
                let sanitized = sanitizeFoundationModelText(value)
                if !sanitized.isEmpty, !["null", "nil", "none"].contains(sanitized.lowercased()) {
                    return sanitized
                }
            }
            if let value = dictionary[key] {
                let text = sanitizeFoundationModelText("\(value)")
                if !text.isEmpty, !["null", "nil", "none", "<null>"].contains(text.lowercased()) {
                    return text
                }
            }
        }
        return nil
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? Double { return Int(value.rounded()) }
        if let value = value as? String { return Int(value.trimmingCharacters(in: .whitespacesAndNewlines)) }
        return nil
    }
}

private func parsedOpenRouterSovereignty(_ value: Any?) -> NativeSovereigntyChange? {
    guard let dictionary = value as? [String: Any],
          let rawKind = dictionary["kind"] as? String,
          let kind = NativeSovereigntyChangeKind(rawValue: rawKind.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    else { return nil }

    func strings(_ value: Any?) -> [String] {
        if let values = value as? [String] {
            return values.map(sanitizeFoundationModelText).filter { !$0.isEmpty }
        }
        if let value = value as? String {
            return value.split(separator: ",").map { sanitizeFoundationModelText(String($0)) }.filter { !$0.isEmpty }
        }
        return []
    }

    return NativeSovereigntyChange(
        kind: kind,
        name: sanitizeFoundationModelText(dictionary["name"] as? String ?? ""),
        regionIDs: strings(dictionary["regionIDs"] ?? dictionary["region_ids"]),
        sourceCodes: strings(dictionary["sourceCodes"] ?? dictionary["source_codes"]).map { $0.uppercased() },
        targetCode: sanitizeFoundationModelText(dictionary["targetCode"] as? String ?? dictionary["target_code"] as? String ?? "").uppercased()
    )
}

private enum OpenRouterTurnParser {
    static func turn(from rawResponse: String, state: NativeCampaignState, months: Int) throws -> NativeGeneratedTurn {
        for candidate in NativeJSONExtraction.candidates(from: rawResponse) {
            guard let data = candidate.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let eventDictionaries = object["events"] as? [[String: Any]]
            else {
                continue
            }

            let events = eventDictionaries.enumerated().compactMap { index, dictionary in
                nativeEvent(from: dictionary, state: state, months: months, index: index)
            }
            guard !events.isEmpty else { continue }

            let summary = firstString(object, keys: ["summary", "turnSummary", "periodSummary"]) ?? ""
            return NativeGeneratedTurn(
                events: events,
                stabilityDelta: intValue(object["stabilityDelta"]) ?? 0,
                summary: sanitizeFoundationModelText(summary),
                worldTensionDelta: intValue(object["worldTensionDelta"] ?? object["globalFrictionDelta"]) ?? 0
            )
        }

        throw NativeFoundationModelError.generationFailed("OpenRouter unified turn returned invalid strict JSON.")
    }

    private static func nativeEvent(
        from dictionary: [String: Any],
        state: NativeCampaignState,
        months: Int,
        index: Int
    ) -> NativeCampaignEvent? {
        guard let title = firstString(dictionary, keys: ["title", "headline"]),
              let description = firstString(dictionary, keys: ["description", "detail", "summary"]),
              let effectSummary = firstString(dictionary, keys: ["effectSummary", "mechanicEffect", "gameEffect"])
        else {
            return nil
        }

        let eventDate = NativeGameEngine.advance(date: state.gameDate, months: months)
        let eventID = "openrouter-unified-\(state.round)-\(index)"
        let kindText = (firstString(dictionary, keys: ["kind", "type"]) ?? "world").lowercased()
        let importanceText = (firstString(dictionary, keys: ["importance", "severity"]) ?? "minor").lowercased()
        let trackText = (firstString(dictionary, keys: ["effectTrack", "effectCode", "track", "mechanic"]) ?? "⟦ECO⟧")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: "-")
        let targetText = firstString(dictionary, keys: ["effectTarget", "target"]) ?? state.country.code
        let linkedActionID = firstString(dictionary, keys: ["linkedActionID", "linkedActionId", "actionID", "actionId"])
        let usableLinkedID = linkedActionID.flatMap { $0.lowercased() == "null" ? nil : $0 }
        let playerRelated = boolValue(dictionary["playerRelated"]) ?? (usableLinkedID != nil)

        let effect = NativeStrategicEffect(
            date: eventDate,
            eventId: eventID,
            id: "\(eventID)-effect",
            magnitude: max(-5, min(5, intValue(dictionary["effectMagnitude"] ?? dictionary["magnitude"]) ?? 0)),
            summary: sanitizeFoundationModelText(effectSummary),
            target: sanitizeFoundationModelText(targetText == "PLAYER" ? state.country.code : targetText),
            track: NativeStrategicTrack.decodeMechanicToken(trackText) ?? .economicResilience
        )

        return NativeCampaignEvent(
            date: eventDate,
            description: sanitizeFoundationModelText(description),
            id: eventID,
            importance: ["critical", "severe"].contains(importanceText) ? .severe : (importanceText == "major" ? .major : .minor),
            kind: eventKind(kindText),
            linkedActionIDs: usableLinkedID.map { [$0] } ?? [],
            notable: boolValue(dictionary["notable"]) ?? true,
            playerRelated: playerRelated,
            strategicEffects: [effect],
            title: sanitizeFoundationModelText(title),
            hexLeverCode: firstString(dictionary, keys: ["hexLeverCode", "hexLever"]),
            sovereigntyChange: parsedOpenRouterSovereignty(dictionary["sovereigntyChange"] ?? dictionary["sovereignty_change"])
        )
    }

    private static func eventKind(_ value: String) -> NativeEventKind {
        switch value {
        case "action", "domestic": .action
        case "diplomacy": .diplomacy
        case "economy": .economy
        default: .world
        }
    }

    private static func firstString(_ dictionary: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = dictionary[key] as? String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        return nil
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? Double { return Int(value.rounded()) }
        if let value = value as? String { return Int(value.trimmingCharacters(in: .whitespacesAndNewlines)) }
        return nil
    }

    private static func boolValue(_ value: Any?) -> Bool? {
        if let value = value as? Bool { return value }
        if let value = value as? String {
            switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "true", "yes", "1": return true
            case "false", "no", "0": return false
            default: return nil
            }
        }
        return nil
    }
}
