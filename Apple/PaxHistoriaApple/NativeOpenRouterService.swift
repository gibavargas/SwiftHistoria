import Foundation
import OSLog

/// OpenRouter-based AI service using free models. Falls back before Z.AI.
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
        defaults.string(forKey: "OPENROUTER_API_KEY") ?? ""
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

    override var supportsStreaming: Bool {
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
        progress(NativeTurnProgress(
            completedLanes: 0,
            detail: "Calling OpenRouter Free once for the whole turn to reduce free-router rate pressure.",
            phase: "Consulting OpenRouter",
            totalLanes: totalLanes,
            providerName: providerDisplayName,
            modelName: primaryModelDisplayName,
            modelIdentifier: primaryModelIdentifier
        ))

        do {
            let turn = try await generateUnifiedTurn(for: state, months: months, repairInstruction: nil)
            let validated = try NativeGameEngine.validated(turn, state: state, months: months)
            progress(NativeTurnProgress(
                completedLanes: totalLanes,
                detail: "OpenRouter unified turn validated.",
                phase: NativeFoundationTurnLane.summary.title,
                totalLanes: totalLanes,
                providerName: providerDisplayName,
                modelName: primaryModelDisplayName,
                modelIdentifier: primaryModelIdentifier
            ))
            orLogger.info("OpenRouter unified turn validated events=\(validated.events.count, privacy: .public)")
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
                modelIdentifier: primaryModelIdentifier
            ))
            let repairedTurn = try await generateUnifiedTurn(for: state, months: months, repairInstruction: error.localizedDescription)
            let validated = try NativeGameEngine.validated(repairedTurn, state: state, months: months)
            progress(NativeTurnProgress(
                completedLanes: totalLanes,
                detail: "OpenRouter unified turn repair validated.",
                phase: NativeFoundationTurnLane.summary.title,
                totalLanes: totalLanes,
                providerName: providerDisplayName,
                modelName: primaryModelDisplayName,
                modelIdentifier: primaryModelIdentifier
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
        let focusAreas = [
            "fiscal ledger, budget balance, debt, and market confidence",
            "public security, insurgency pressure, and stabilization capacity",
            "diplomacy, trade balance, global friction, and regional relations",
            "infrastructure, energy, climate resilience, unemployment, and service access"
        ]
        let prompt = """
        \(promptHarness.makeSuggestionBatchPrompt(for: state, focusAreas: focusAreas))

        Required JSON schema:
        {
          "suggestions": [
            {
              "title": "Short imperative title for the civic proposal.",
              "detail": "Accept-ready board-game order with bounded instrument, generic agency or sector, timing, primary mechanic, secondary mechanic, capacity fit, and intended game effect.",
              "rationale": "Why this proposal fits the current campaign state and objectives, explicitly naming the primary affected mechanic and one connected secondary mechanic.",
              "urgency": "immediate, soon, or opportunistic"
            }
          ]
        }

        Return one strict JSON object only. Do not include markdown fences, prose, schema labels, or comments.
        """

        var lastValidCount = 0
        var repairNote = ""
        for attempt in 1 ... 2 {
            let rawResponse = try await executeProviderRequest(
                prompt: prompt + repairNote,
                maxTokens: 1400,
                temperature: attempt == 1 ? 0.1 : 0.0,
                responseFormat: "json_object",
                thinkingEnabled: false
            )

            let suggestions = OpenRouterSuggestionParser
                .suggestions(from: rawResponse, state: state)
                .filter { isValidNativeSuggestion($0) }
            lastValidCount = max(lastValidCount, suggestions.count)
            guard suggestions.count >= 3 else {
                orLogger.warning("OpenRouter batched suggestions invalid count=\(suggestions.count, privacy: .public) attempt=\(attempt, privacy: .public)")
                repairNote = """

                Repair note: the previous JSON did not decode into at least three valid suggestions. Return exactly one JSON object with key "suggestions". Each item must include non-empty string keys "title", "detail", "rationale", and "urgency"; urgency must be "immediate", "soon", or "opportunistic".
                """
                continue
            }
            orLogger.info("OpenRouter batched suggestions validated count=\(suggestions.count, privacy: .public)")
            return Array(suggestions.prefix(4))
        }

        throw NativeFoundationModelError.invalidSuggestedActions("OpenRouter Free returned \(lastValidCount) valid suggestions; expected at least 3.")
    }

    private func generateUnifiedTurn(
        for state: NativeCampaignState,
        months: Int,
        repairInstruction: String?
    ) async throws -> NativeGeneratedTurn {
        let rawResponse = try await executeProviderRequest(
            prompt: unifiedTurnPrompt(for: state, months: months, repairInstruction: repairInstruction),
            maxTokens: 2600,
            temperature: repairInstruction == nil ? 0.1 : 0.0,
            responseFormat: "json_object",
            thinkingEnabled: false
        )
        return try OpenRouterTurnParser.turn(from: rawResponse, state: state, months: months)
    }

    private func unifiedTurnPrompt(
        for state: NativeCampaignState,
        months: Int,
        repairInstruction: String?
    ) -> String {
        let targetDate = NativeGameEngine.advance(date: state.gameDate, months: months)
        let plannedActions = Array(state.plannedActions.filter { $0.status == .planned }.prefix(3))
        let actionLines = plannedActions.isEmpty
            ? "No player orders are queued."
            : plannedActions.enumerated().map { index, action in
                "\(index + 1). id=\(action.id); title=\(action.title); detail=\(action.detail)"
            }.joined(separator: "\n")
        let objectives = NativeGameEngine.campaignObjectives(for: state)
        let objectiveLines = objectives.isEmpty
            ? "No explicit campaign objectives."
            : objectives.prefix(4).map { objective in
                "- \(objective.title): \(objective.currentValue) -> \(objective.targetValue) by \(objective.deadline). \(objective.detail)"
            }.joined(separator: "\n")
        let ledger = state.economicLedger
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

        Current selected ledger:
        - Real growth: \(ledger.realGrowthPercent)%
        - Inflation: \(ledger.inflationPercent)%
        - Budget balance: \(ledger.budgetBalancePercentGDP)% GDP
        - Public debt: \(ledger.publicDebtPercentGDP)% GDP
        - Trade balance: \(ledger.tradeBalancePercentGDP)% GDP
        - Unemployment: \(ledger.unemploymentPercent)%
        - Public security: \(ledger.securityIndex)/100
        - Insurgency pressure: \(ledger.rebelControlPercent)%
        - Fiscal space: \(ledger.fiscalSpaceIndex)/100

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
              "kind": "economy, domestic, or world",
              "importance": "minor, major, or critical",
              "notable": true,
              "playerRelated": false,
              "linkedActionID": null,
              "effectTarget": "Country code like \(state.country.code) or GLOBAL",
              "effectTrack": "economic-resilience, market-confidence, diplomatic-leverage, internal-stability, world-tension, or security-anxiety",
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
        """
    }
}

private enum OpenRouterSuggestionParser {
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
        let mechanics = firstString(dictionary, keys: ["mechanic", "mechanics", "effectTrack", "effectTarget", "primaryMechanic"]) ?? ""
        let rationale = firstString(dictionary, keys: ["rationale", "reason", "why", "justification"]) ?? summary

        let detailParts = [
            summary,
            instrument.isEmpty ? "" : "Instrument: \(instrument).",
            mechanics.isEmpty ? "" : "Mechanic link: \(mechanics).",
            risk.isEmpty ? "" : "Risk: \(risk)."
        ].filter { !$0.isEmpty }

        guard !detailParts.isEmpty else { return nil }

        let rationaleParts = [
            rationale,
            mechanics.isEmpty ? "This proposal is tied to current campaign objectives and administrative capacity." : "It affects \(mechanics) while respecting current campaign objectives and administrative capacity."
        ]

        return NativeSuggestedAction(
            detail: sanitizeFoundationModelText(detailParts.joined(separator: " ")),
            id: "suggestion-\(state.country.code.lowercased())-\(state.round)-openrouter-\(index + 1)",
            rationale: sanitizeFoundationModelText(rationaleParts.joined(separator: " ")),
            title: sanitizeFoundationModelText(title),
            urgency: normalizedFoundationUrgency(firstString(dictionary, keys: ["urgency", "priority", "timing"]) ?? "soon")
        )
    }

    private static func firstString(_ dictionary: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = dictionary[key] as? String {
                let sanitized = sanitizeFoundationModelText(value)
                if !sanitized.isEmpty { return sanitized }
            }
            if let value = dictionary[key] {
                let text = sanitizeFoundationModelText("\(value)")
                if !text.isEmpty { return text }
            }
        }
        return nil
    }
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
        let trackText = (firstString(dictionary, keys: ["effectTrack", "track", "mechanic"]) ?? "economic-resilience")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
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
            track: NativeStrategicTrack(rawValue: trackText) ?? .economicResilience
        )

        return NativeCampaignEvent(
            date: eventDate,
            description: sanitizeFoundationModelText(description),
            id: eventID,
            importance: importanceText == "critical" ? .severe : (importanceText == "major" ? .major : .minor),
            kind: kindText == "economy" ? .economy : (kindText == "domestic" ? .action : .world),
            linkedActionIDs: usableLinkedID.map { [$0] } ?? [],
            notable: boolValue(dictionary["notable"]) ?? true,
            playerRelated: playerRelated,
            strategicEffects: [effect],
            title: sanitizeFoundationModelText(title),
            hexLeverCode: firstString(dictionary, keys: ["hexLeverCode", "hexLever"]),
            sovereigntyChange: nil
        )
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
