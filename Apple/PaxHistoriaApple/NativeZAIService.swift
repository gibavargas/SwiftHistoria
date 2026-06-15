import Foundation
import OSLog

@MainActor
class NativeZAIService: NativeAIService {
    private let logger = Logger(subsystem: "com.gibavargas.SwiftHistoria", category: "NativeZAIService")
    private let modelLanes: [ZAIModelLane] = [
        ZAIModelLane(name: "glm-5", displayName: "GLM-5", maxConcurrent: 2),
        ZAIModelLane(name: "glm-4.7-flashx", displayName: "GLM-4.7-FlashX", maxConcurrent: 3),
        ZAIModelLane(name: "glm-4.7-flash", displayName: "GLM-4.7-Flash", maxConcurrent: 1),
    ]
    private var nextModelLaneStartIndex = 0
    
    private var apiKey: String {
        UserDefaults.standard.string(forKey: "ZAI_API_KEY") ?? ""
    }
    
    private var useCodingEndpoint: Bool {
        UserDefaults.standard.bool(forKey: "ZAI_USE_CODING_ENDPOINT")
    }
    
    private var apiEndpoint: URL {
        if useCodingEndpoint {
            return URL(string: "https://api.z.ai/api/coding/paas/v4/chat/completions")!
        } else {
            return URL(string: "https://api.z.ai/api/paas/v4/chat/completions")!
        }
    }

    private var orderedModelLanes: [ZAIModelLane] {
        guard !modelLanes.isEmpty else { return [] }
        let startIndex = nextModelLaneStartIndex % modelLanes.count
        nextModelLaneStartIndex = (nextModelLaneStartIndex + 1) % modelLanes.count
        return Array(modelLanes[startIndex...]) + Array(modelLanes[..<startIndex])
    }
    
    func checkReadiness() async -> NativeAIReadiness {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if key.isEmpty {
            return .unavailable("Z.AI API Key not configured in System Settings.")
        }
        do {
            _ = try await executeZAIRequest(
                prompt: "Return exactly this JSON: {\"ok\":true}",
                maxTokens: 12,
                temperature: 0.0,
                responseFormat: "json_object",
                thinkingEnabled: false
            )
            return .available(tokenBudget: "Z.AI model lanes verified")
        } catch {
            logger.error("Z.AI readiness probe failed")
            return .failure(error)
        }
    }
    
    func generateTurn(for state: NativeCampaignState, months: Int) async throws -> NativeGeneratedTurn {
        try await generateTurn(for: state, months: months) { _ in }
    }
    
    func generateTurn(
        for state: NativeCampaignState,
        months: Int,
        progress: @escaping @MainActor (NativeTurnProgress) -> Void
    ) async throws -> NativeGeneratedTurn {
        logger.info("Z.AI turn generation started round=\(state.round) months=\(months)")
        let rawTurn = try await generateSlicedTurn(for: state, months: months, progress: progress)
        do {
            let validated = try NativeGameEngine.validated(rawTurn, state: state, months: months)
            logger.info("Z.AI turn generation validated events=\(validated.events.count)")
            return validated
        } catch {
            logger.error("Z.AI turn validation failed; retrying with repair instruction")
            let retryTurn = try await generateSlicedTurn(
                for: state,
                months: months,
                repairInstruction: error.localizedDescription,
                progress: progress
            )
            do {
                let validated = try NativeGameEngine.validated(retryTurn, state: state, months: months)
                logger.info("Z.AI repaired turn validated events=\(validated.events.count)")
                return validated
            } catch {
                logger.error("Z.AI repaired turn remained invalid: \(error.localizedDescription)")
                throw NativeFoundationModelError.invalidGeneratedTurn(error.localizedDescription)
            }
        }
    }
    
    func generateSuggestedActions(for state: NativeCampaignState) async throws -> [NativeSuggestedAction] {
        logger.info("Z.AI suggestions started round=\(state.round)")
        let suggestions = try await generateStructuredSuggestions(for: state)
        let validSuggestions = suggestions.filter { isValidNativeSuggestion($0) }
        guard validSuggestions.count >= 3 else {
            logger.error("Z.AI suggestions invalid count=\(validSuggestions.count)")
            throw NativeFoundationModelError.invalidSuggestedActions("Expected at least three concrete suggestions from Z.AI Model.")
        }
        logger.info("Z.AI suggestions validated count=\(validSuggestions.count)")
        return Array(validSuggestions.prefix(4))
    }
    
    func generateAdvisorBrief(for state: NativeCampaignState, question: String) async throws -> String {
        let safeQuestion = sanitizeFoundationModelText(question)
        guard hasConcreteFoundationText(safeQuestion, minimumWords: 2) else {
            throw NativeFoundationModelError.generationFailed("Advisor question was empty or placeholder-like.")
        }
        
        logger.info("Z.AI advisor generation started round=\(state.round)")
        let answer = try await generateTextResponse(
            prompt: makeAdvisorPrompt(for: state, question: safeQuestion),
            maxTokens: 520,
            repairNote: "Answer as a blunt strategic advisor in no more than three short paragraphs."
        )
        logger.info("Z.AI advisor generation completed")
        return answer
    }
    
    func generateDiplomaticReply(
        for state: NativeCampaignState,
        thread: NativeDiplomaticThread,
        message: String
    ) async throws -> String {
        let safeMessage = sanitizeFoundationModelText(message)
        guard hasConcreteFoundationText(safeMessage, minimumWords: 2) else {
            throw NativeFoundationModelError.generationFailed("Diplomatic response was empty or placeholder-like.")
        }
        
        logger.info("Z.AI diplomatic reply started round=\(state.round) counterpart=\(thread.participant.code)")
        let reply = try await generateTextResponse(
            prompt: makeDiplomaticPrompt(for: state, thread: thread, message: safeMessage),
            maxTokens: 140,
            repairNote: "Draft a diplomatic response of one or two sentences in the active voice. Keep it under 140 characters."
        )
        logger.info("Z.AI diplomatic reply completed")
        return reply
    }
    
    // MARK: - Internal Lane Slicing
    
    private enum LaneResult {
        case independent(ZAIEventDraft)
        case economic(ZAIEventDraft)
        case domestic(ZAIEventDraft)
        case globalAI(ZAIEventDraft)
        case action(NativePlannedAction, ZAIEventDraft)
    }
    
    private func generateSlicedTurn(
        for state: NativeCampaignState,
        months: Int,
        repairInstruction: String? = nil,
        progress: @escaping @MainActor (NativeTurnProgress) -> Void
    ) async throws -> NativeGeneratedTurn {
        let plannedActions = Array(state.plannedActions
            .filter { $0.status == .planned }
            .prefix(3))
        let totalLanes = NativeStrategyContextDatabase.estimatedLaneCount(for: state)
        var completedLanes = 0
        progress(NativeTurnProgress(
            completedLanes: completedLanes,
            detail: "Launching external, economic, domestic, and action Z.AI lanes in parallel.",
            phase: "Consulting Z.AI",
            totalLanes: totalLanes
        ))
        
        var independentDraft: ZAIEventDraft?
        var economicDraft: ZAIEventDraft?
        var domesticDraft: ZAIEventDraft?
        var globalAIDraft: ZAIEventDraft?
        var actionDrafts: [String: ZAIEventDraft] = [:]
        
        try await withThrowingTaskGroup(of: LaneResult.self) { group in
            group.addTask {
                let draft = try await self.generateEventDraft(
                    prompt: self.makeIndependentEventPrompt(for: state, months: months, repairInstruction: repairInstruction),
                    state: state
                )
                return .independent(draft)
            }
            group.addTask {
                let draft = try await self.generateEventDraft(
                    prompt: self.makeEconomicEventPrompt(for: state, months: months, repairInstruction: repairInstruction),
                    state: state
                )
                return .economic(draft)
            }
            group.addTask {
                let draft = try await self.generateEventDraft(
                    prompt: self.makeDomesticEventPrompt(for: state, months: months, repairInstruction: repairInstruction),
                    state: state
                )
                return .domestic(draft)
            }
            group.addTask {
                let draft = try await self.generateEventDraft(
                    prompt: self.makeGlobalAIActionsPrompt(for: state, months: months, repairInstruction: repairInstruction),
                    state: state
                )
                return .globalAI(draft)
            }
            for action in plannedActions {
                group.addTask {
                    let draft = try await self.generateEventDraft(
                        prompt: self.makeActionEventPrompt(for: state, action: action, months: months, repairInstruction: repairInstruction),
                        state: state
                    )
                    return .action(action, draft)
                }
            }
            
            for try await result in group {
                completedLanes += 1
                let phase: String
                let detail: String
                
                switch result {
                case .independent(let draft):
                    independentDraft = draft
                    phase = NativeFoundationTurnLane.external.title
                    detail = "External facts lane completed: \(sanitizeFoundationModelText(draft.title))"
                case .economic(let draft):
                    economicDraft = draft
                    phase = NativeFoundationTurnLane.economy.title
                    detail = "Economic consequences lane completed: \(sanitizeFoundationModelText(draft.title))"
                case .domestic(let draft):
                    domesticDraft = draft
                    phase = NativeFoundationTurnLane.domestic.title
                    detail = "Domestic response lane completed: \(sanitizeFoundationModelText(draft.title))"
                case .globalAI(let draft):
                    globalAIDraft = draft
                    phase = NativeFoundationTurnLane.external.title
                    detail = "Global AI Action lane completed: \(sanitizeFoundationModelText(draft.title))"
                case .action(let action, let draft):
                    actionDrafts[action.id] = draft
                    phase = NativeFoundationTurnLane.actionConsequence.title
                    detail = "Resolved \(sanitizeFoundationModelText(action.title)): \(sanitizeFoundationModelText(draft.title))"
                }
                
                progress(NativeTurnProgress(
                    completedLanes: completedLanes,
                    detail: detail,
                    phase: phase,
                    totalLanes: totalLanes
                ))
            }
        }
        
        var events: [NativeCampaignEvent] = []
        if let independent = independentDraft {
            events.append(independent.toNativeEvent(
                state: state,
                months: months,
                index: events.count,
                linkedActionID: nil,
                playerRelated: false
            ))
        }
        if let economic = economicDraft {
            events.append(economic.toNativeEvent(
                state: state,
                months: months,
                index: events.count,
                linkedActionID: nil,
                playerRelated: true
            ))
        }
        if let domestic = domesticDraft {
            events.append(domestic.toNativeEvent(
                state: state,
                months: months,
                index: events.count,
                linkedActionID: nil,
                playerRelated: true
            ))
        }
        if let globalAI = globalAIDraft {
            events.append(globalAI.toNativeEvent(
                state: state,
                months: months,
                index: events.count,
                linkedActionID: nil,
                playerRelated: false
            ))
        }
        for action in plannedActions {
            if let draft = actionDrafts[action.id] {
                events.append(draft.toNativeEvent(
                    state: state,
                    months: months,
                    index: events.count,
                    linkedActionID: action.id,
                    playerRelated: true
                ))
            }
        }
        
        progress(NativeTurnProgress(
            completedLanes: max(0, totalLanes - 1),
            detail: "Synthesizing lane outputs into one validated turn.",
            phase: NativeFoundationTurnLane.summary.title,
            totalLanes: totalLanes
        ))
        
        let summary = try await generateTurnSummary(state: state, months: months, events: events)
        progress(NativeTurnProgress(
            completedLanes: totalLanes,
            detail: "Z.AI turn synthesis completed.",
            phase: NativeFoundationTurnLane.summary.title,
            totalLanes: totalLanes
        ))
        logger.info("Z.AI sliced turn assembled events=\(events.count)")
        
        return NativeGeneratedTurn(
            events: events,
            stabilityDelta: summary.stabilityDelta,
            summary: sanitizeFoundationModelText(summary.summary),
            worldTensionDelta: summary.globalFrictionDelta
        )
    }
    
    private func generateEventDraft(
        prompt: String,
        state: NativeCampaignState
    ) async throws -> ZAIEventDraft {
        var repairNotes: [String] = []
        for attempt in 1...3 {
            do {
                logger.info("Z.AI event draft attempt=\(attempt)")
                let draft: ZAIEventDraft = try await generateStructuredJSON(
                    prompt: eventPrompt(prompt, state: state, repairNotes: repairNotes),
                    schema: ZAIEventDraft.schemaInstructions,
                    maximumResponseTokens: 260,
                    temperature: attempt == 1 ? 0.0 : 0.18
                )
                if draft.hasConcreteContent {
                    return draft
                }
                logger.error("Z.AI event draft used non-concrete content attempt=\(attempt) \(draft.validationDiagnostics)")
                repairNotes.append("Previous event used placeholder or draft text. Produce a concrete title, description, target, and effect summary.")
            } catch {
                if attempt == 3 {
                    logger.error("Z.AI event draft failed after retries")
                    throw NativeFoundationModelError.generationFailed(error.localizedDescription)
                }
                logger.error("Z.AI event draft attempt failed attempt=\(attempt)")
                repairNotes.append("Previous event generation failed. Try a simpler civic-planning event with one concrete agency and one measurable game effect.")
            }
        }
        throw NativeFoundationModelError.generationFailed("Z.AI Models returned placeholder event content after three attempts.")
    }
    
    private func generateTurnSummary(
        state: NativeCampaignState,
        months: Int,
        events: [NativeCampaignEvent]
    ) async throws -> ZAITurnSummary {
        let prompt = makeSummaryPrompt(for: state, months: months, events: events)
        return try await generateStructuredJSON(
            prompt: prompt,
            schema: ZAITurnSummary.schemaInstructions,
            maximumResponseTokens: 140,
            temperature: 0.0
        )
    }
    
    private func generateStructuredSuggestions(for state: NativeCampaignState) async throws -> [NativeSuggestedAction] {
        let focusAreas = [
            "fiscal ledger, budget balance, debt, and market confidence",
            "public security, insurgency pressure, and stabilization capacity",
            "map conflict, border pressure, regional logistics, and service corridors",
            "diplomacy, trade balance, global friction, and regional relations",
            "infrastructure, energy, climate resilience, and unemployment",
            "education, service access, administrative capacity, and action memory",
        ]
        
        var suggestions: [NativeSuggestedAction] = []
        await withTaskGroup(of: (Int, NativeSuggestedAction?).self) { group in
            for (index, focus) in focusAreas.enumerated() {
                group.addTask {
                    let suggestion = await self.generateSuggestion(
                        for: state,
                        focus: focus,
                        index: index
                    )
                    return (index, suggestion)
                }
            }

            var indexedSuggestions: [(Int, NativeSuggestedAction)] = []
            for await (index, suggestion) in group {
                if let suggestion, self.isValidNativeSuggestion(suggestion) {
                    indexedSuggestions.append((index, suggestion))
                    if indexedSuggestions.count >= 4 {
                        group.cancelAll()
                        break
                    }
                }
            }
            suggestions = indexedSuggestions
                .sorted { $0.0 < $1.0 }
                .map(\.1)
        }
        return suggestions
    }

    private func generateSuggestion(
        for state: NativeCampaignState,
        focus: String,
        index: Int
    ) async -> NativeSuggestedAction? {
        let basePrompt = makeSuggestionPrompt(for: state, focus: focus, index: index + 1)
        var repairNotes: [String] = []

        for attempt in 1...2 {
            do {
                logger.info("Z.AI suggestion attempt focus=\(index + 1) attempt=\(attempt)")
                let suggestion: ZAISuggestedAction = try await generateStructuredJSON(
                    prompt: suggestionPrompt(basePrompt, repairNotes: repairNotes),
                    schema: ZAISuggestedAction.schemaInstructions,
                    maximumResponseTokens: 1024,
                    temperature: attempt == 1 ? 0.0 : 0.18
                )

                if suggestion.hasConcreteContent {
                    return suggestion.toNativeSuggestion(state: state, index: index)
                }
                logger.error("Z.AI suggestion was not concrete focus=\(index + 1)")
                repairNotes.append("Previous proposal was too vague, used placeholder text, or contradicted current metrics. Produce a concrete neutral proposal.")
            } catch {
                if attempt == 2 {
                    logger.error("Z.AI suggestion failed focus=\(index + 1) error=\(error.localizedDescription, privacy: .public)")
                    return nil
                }
                logger.error("Z.AI suggestion attempt failed focus=\(index + 1) attempt=\(attempt) error=\(error.localizedDescription, privacy: .public)")
                repairNotes.append("Previous proposal generation failed. Try a shorter neutral civic-planning proposal.")
            }
        }

        return nil
    }
    
    // MARK: - Core API Caller
    
    private func generateTextResponse(
        prompt: String,
        maxTokens: Int,
        repairNote: String
    ) async throws -> String {
        var repairNotes: [String] = []
        for attempt in 1...2 {
            do {
                logger.info("Z.AI text generation attempt=\(attempt)")
                let text = try await executeZAIRequest(
                    prompt: textPrompt(prompt, repairNotes: repairNotes),
                    maxTokens: maxTokens,
                    temperature: attempt == 1 ? 0.05 : 0.20,
                    thinkingEnabled: false
                )
                let sanitized = sanitizeFoundationModelText(text)
                if hasConcreteFoundationText(sanitized, minimumWords: 6) {
                    return sanitized
                }
                logger.error("Z.AI text generation returned non-concrete content attempt=\(attempt)")
                repairNotes.append(repairNote)
            } catch {
                if attempt == 2 {
                    logger.error("Z.AI text generation failed after repair")
                    throw NativeFoundationModelError.generationFailed(error.localizedDescription)
                }
                repairNotes.append(repairNote)
            }
        }
        throw NativeFoundationModelError.generationFailed("Z.AI returned empty or placeholder text after repair.")
    }
    
    private func generateStructuredJSON<T: Decodable>(
        prompt: String,
        schema: String,
        maximumResponseTokens: Int,
        temperature: Double
    ) async throws -> T {
        let combinedPrompt = """
        \(prompt)
        
        Required JSON schema:
        \(schema)
        """
        
        let rawResponse = try await executeZAIRequest(
            prompt: combinedPrompt,
            maxTokens: maximumResponseTokens,
            temperature: temperature,
            responseFormat: "json_object",
            thinkingEnabled: false
        )
        
        let decoder = JSONDecoder()
        for candidate in foundationJSONCandidates(from: rawResponse) {
            guard let data = candidate.data(using: .utf8) else { continue }
            if let decoded = try? decoder.decode(T.self, from: data) {
                return decoded
            }
        }
        
        logger.error("Z.AI JSON decoding failed for response: \(rawResponse)")
        throw NativeFoundationModelError.generationFailed("Z.AI returned invalid strict JSON.")
    }
    
    private func executeZAIRequest(
        prompt: String,
        maxTokens: Int,
        temperature: Double,
        responseFormat: String? = nil,
        thinkingEnabled: Bool = true
    ) async throws -> String {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            throw NativeFoundationModelError.modelUnavailable("Z.AI API Key is empty. Please set it in system settings.")
        }
        
        let systemMsg: [String: Any] = [
            "role": "system",
            "content": nativeSystemPrompt
        ]
        
        let userMsg: [String: Any] = [
            "role": "user",
            "content": prompt
        ]

        var lastError: Error?
        for lane in orderedModelLanes {
            await lane.limiter.enter()
            var releaseLane = true
            var request = URLRequest(url: apiEndpoint)
            request.httpMethod = "POST"
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("en-US,en", forHTTPHeaderField: "Accept-Language")
            request.timeoutInterval = thinkingEnabled ? 90 : 45

            var payload: [String: Any] = [
                "model": lane.name,
                "messages": [systemMsg, userMsg],
                "stream": false,
                "temperature": temperature,
                "max_tokens": maxTokens,
                "thinking": [
                    "type": thinkingEnabled ? "enabled" : "disabled"
                ]
            ]
            if let responseFormat {
                payload["response_format"] = ["type": responseFormat]
            }

            do {
                request.httpBody = try JSONSerialization.data(withJSONObject: payload)
                let (data, response) = try await URLSession.shared.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    throw NativeFoundationModelError.generationFailed("Invalid response format from Z.AI API model=\(lane.name).")
                }

                guard httpResponse.statusCode == 200 else {
                    let errorText = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
                    throw NativeFoundationModelError.generationFailed("Z.AI API returned status \(httpResponse.statusCode) model=\(lane.name): \(errorText)")
                }

                do {
                    let content = try Self.decodeCompletionContent(from: data)
                    lane.limiter.exit()
                    releaseLane = false
                    return content
                } catch {
                    if thinkingEnabled {
                        lane.limiter.exit()
                        releaseLane = false
                        logger.error("Z.AI visible content failed with thinking; retrying without thinking model=\(lane.name, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
                        return try await executeZAIRequest(
                            prompt: prompt,
                            maxTokens: maxTokens,
                            temperature: temperature,
                            responseFormat: responseFormat,
                            thinkingEnabled: false
                        )
                    }
                    throw error
                }
            } catch {
                if releaseLane {
                    lane.limiter.exit()
                }
                lastError = error
                logger.error("Z.AI request failed model=\(lane.name, privacy: .public) limit=\(lane.maxConcurrent) error=\(error.localizedDescription, privacy: .public)")
            }
        }

        throw lastError ?? NativeFoundationModelError.generationFailed("Z.AI request failed for all configured models.")
    }

    nonisolated static func decodeCompletionContent(from data: Data) throws -> String {
        struct ZAICompletionResponse: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable {
                    let content: String?
                    let reasoningContent: String?

                    enum CodingKeys: String, CodingKey {
                        case content
                        case reasoningContent = "reasoning_content"
                    }
                }

                let message: Message
                let finishReason: String?

                enum CodingKeys: String, CodingKey {
                    case message
                    case finishReason = "finish_reason"
                }
            }

            let choices: [Choice]
        }

        let decoded: ZAICompletionResponse
        do {
            decoded = try JSONDecoder().decode(ZAICompletionResponse.self, from: data)
        } catch {
            let rawPrefix = String(data: data.prefix(600), encoding: .utf8) ?? "<non-utf8>"
            throw NativeFoundationModelError.generationFailed("Z.AI response decode failed: \(error.localizedDescription). Raw prefix: \(rawPrefix)")
        }
        guard let firstChoice = decoded.choices.first else {
            throw NativeFoundationModelError.generationFailed("Z.AI API returned empty choices.")
        }

        let content = firstChoice.message.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let reasoning = firstChoice.message.reasoningContent?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if let reason = firstChoice.finishReason,
           ["length", "sensitive", "model_context_window_exceeded", "network_error"].contains(reason) {
            throw NativeFoundationModelError.generationFailed("Z.AI returned no visible content (finish_reason=\(reason), choices=\(decoded.choices.count), content_chars=\(content.count), reasoning_chars=\(reasoning.count)).")
        }

        if !content.isEmpty {
            return strippingZAIThinkingTags(from: content)
        }

        throw NativeFoundationModelError.generationFailed("Z.AI returned no visible content (finish_reason=\(firstChoice.finishReason ?? "nil"), choices=\(decoded.choices.count), content_chars=\(content.count), reasoning_chars=\(reasoning.count)).")
    }

    nonisolated private static func strippingZAIThinkingTags(from content: String) -> String {
        var output = content
        while let startRange = output.range(of: "<think>"),
              let endRange = output.range(of: "</think>", range: startRange.upperBound..<output.endIndex) {
            output.removeSubrange(startRange.lowerBound..<endRange.upperBound)
        }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // MARK: - Prompt & Text Helpers (Replicated from Foundation Service)
    
    private var nativeSystemPrompt: String {
        """
        You are the game master for SwiftHistoria, a turn-based civic strategy board game.
        You narrate events like an experienced analyst covering fictional regional developments.
        Be specific: name agencies, cite budget figures, reference corridors and sectors.
        Every event should read like a headline from a planning-industry trade journal.
        Use concrete fictional agencies, dates, sectors, and measurable game effects.
        Connect every answer to the current campaign mechanics instead of giving generic advice.
        Follow the request's response-language instruction for all player-facing prose.
        Keep schema field names, enum values, identifiers, IDs, dates, and game tokens exactly as requested.
        """
    }
    
    private func isValidNativeSuggestion(_ suggestion: NativeSuggestedAction) -> Bool {
        hasConcreteFoundationText(suggestion.title, minimumWords: 2) &&
            hasConcreteFoundationText(suggestion.detail, minimumWords: 8) &&
            hasConcreteFoundationText(suggestion.rationale, minimumWords: 8) &&
            normalizedFoundationUrgency(suggestion.urgency) == suggestion.urgency
    }
    
    private func eventPrompt(_ basePrompt: String, state: NativeCampaignState, repairNotes: [String]) -> String {
        let repairBlock = repairNotes.isEmpty ? "" : "\n\nEvent repair notes:\n\(repairNotes.map { "- \($0)" }.joined(separator: "\n"))"
        
        let recentTitles = state.timeline
            .prefix(4)
            .map { sanitizeFoundationModelText($0.title) }
            .filter { !$0.isEmpty }
        
        let deduplicationLine = recentTitles.isEmpty ? "" : "\nDo not reuse these themes: \(recentTitles.joined(separator: "; "))."
        
        return """
        \(basePrompt)\(repairBlock)\(deduplicationLine)
        
        Return one strict JSON object only. Do not include markdown fences, prose, schema labels, or comments.
        """
    }
    
    private func textPrompt(_ basePrompt: String, repairNotes: [String]) -> String {
        guard !repairNotes.isEmpty else { return basePrompt }
        return """
        \(basePrompt)
        
        Recent correction requests:
        \(repairNotes.map { "- \($0)" }.joined(separator: "\n"))
        """
    }
    
    private func suggestionPrompt(_ basePrompt: String, repairNotes: [String]) -> String {
        let repairBlock = repairNotes.isEmpty ? "" : "\n\nSuggestion repair notes:\n\(repairNotes.map { "- \($0)" }.joined(separator: "\n"))"
        return """
        \(basePrompt)\(repairBlock)
        
        Return one strict JSON object only. Do not include markdown fences, prose, schema labels, or comments.
        """
    }
    
    private func foundationJSONCandidates(from rawText: String) -> [String] {
        let trimmed = rawText
            .replacingOccurrences(of: "\u{FEFF}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        
        var candidates = [trimmed]
        if trimmed.hasPrefix("```") {
            let lines = trimmed.components(separatedBy: .newlines)
            let unfenced = lines
                .dropFirst()
                .dropLast(lines.last?.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("```") == true ? 1 : 0)
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !unfenced.isEmpty {
                candidates.append(unfenced)
            }
        }
        
        if let start = trimmed.firstIndex(of: "{"), let end = trimmed.lastIndex(of: "}"), start <= end {
            let object = String(trimmed[start...end]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !object.isEmpty {
                candidates.append(object)
            }
        }
        
        var seen: Set<String> = []
        return candidates.filter { seen.insert($0).inserted }
    }
    
    // Delegate make... prompts to the static context database or local helper copies
    private func makeIndependentEventPrompt(for state: NativeCampaignState, months: Int, repairInstruction: String?) -> String {
        let targetDate = NativeGameEngine.advance(date: state.gameDate, months: months)
        return """
        Create one external planning development for a SwiftHistoria board-game turn.
        \(languageInstruction(for: state))
        It must be unrelated to the selected region except through broad economic, logistics, climate, energy, education, or market conditions.
        Include one measurable game effect.
        The period starts on \(state.gameDate) and ends on \(targetDate).
        \(repairInstruction != nil ? "Repair note: \(repairInstruction!)" : "")
        
        \(independentEventExamples(for: state.language))
        
        \(recentContext(for: state))
        """
    }
    
    private func makeEconomicEventPrompt(for state: NativeCampaignState, months: Int, repairInstruction: String?) -> String {
        let targetDate = NativeGameEngine.advance(date: state.gameDate, months: months)
        return """
        Create one selected-region economic assessment event for a SwiftHistoria board-game turn.
        \(languageInstruction(for: state))
        Focus on budget surplus or deficit, fiscal space, debt pressure, inflation, growth, trade balance, unemployment, and the cost of planned commitments.
        Include one measurable game effect using either market-confidence or economic-resilience.
        The period starts on \(state.gameDate) and ends on \(targetDate).
        \(repairInstruction != nil ? "Repair note: \(repairInstruction!)" : "")
        
        \(hexLeverCodeInstruction())
        
        Economic examples:
        [Example 1]
        {"title":"Quarterly Fiscal Outlook Narrows","description":"The treasury office updates its revenue forecast after weaker customs intake and higher service commitments, trimming available fiscal space for the next planning period.","kind":"economy","importance":"major","notable":true,"effectTarget":"\(state.country.code)","effectTrack":"market-confidence","effectMagnitude":-1,"effectSummary":"A narrower budget balance weighs on market confidence and slows discretionary spending.","hexLeverCode":"0x0D0004"}
        
        \(recentContext(for: state))
        """
    }
    
    private func makeDomesticEventPrompt(for state: NativeCampaignState, months: Int, repairInstruction: String?) -> String {
        let targetDate = NativeGameEngine.advance(date: state.gameDate, months: months)
        return """
        Create one domestic public-security assessment event for a SwiftHistoria board-game turn.
        \(languageInstruction(for: state))
        Focus on domestic agency operations, public services, border logistics, infrastructure tension, or public safety.
        Include one measurable game effect.
        The period starts on \(state.gameDate) and ends on \(targetDate).
        \(repairInstruction != nil ? "Repair note: \(repairInstruction!)" : "")
        
        \(hexLeverCodeInstruction())
        
        \(recentContext(for: state))
        """
    }
    
    private func makeGlobalAIActionsPrompt(for state: NativeCampaignState, months: Int, repairInstruction: String?) -> String {
        let targetDate = NativeGameEngine.advance(date: state.gameDate, months: months)
        let aiDetails = state.aiCountryStates.sorted(by: { $0.key < $1.key }).map { code, aiState in
            "- \(code): doctrine=\(aiState.doctrine.rawValue), agenda=\"\(aiState.multiTurnAgenda)\""
        }.joined(separator: "\n")
        
        return """
        Create one geopolitical or economic action event initiated by one of the autonomous non-player countries.
        \(languageInstruction(for: state))
        Look at their doctrines and multi-turn agendas:
        \(aiDetails)
        
        Author an event representing an action taken by one of these countries to advance their agenda.
        The event must target the initiator country or one of its rivals, altering market confidence, global friction, or stability.
        
        Use the 'hexLeverCode' to nudge conflict borders or economic ledgers for the initiator or target.
        The period starts on \(state.gameDate) and ends on \(targetDate).
        \(repairInstruction != nil ? "Repair note: \(repairInstruction!)" : "")
        
        \(hexLeverCodeInstruction())
        
        Examples:
        [Example 1]
        {"title":"China Secures Highland Resource Access","description":"China completes a transit corridor integration with neighboring highland districts, securing primary resource inputs to advance its mercantile doctrine.","kind":"world","importance":"major","notable":true,"effectTarget":"CHN","effectTrack":"economic-resilience","effectMagnitude":2,"effectSummary":"Corridor integration secures resource supply, raising economic resilience.","hexLeverCode":"0x120004"}
        
        \(recentContext(for: state))
        """
    }
    
    private func makeActionEventPrompt(for state: NativeCampaignState, action: NativePlannedAction, months: Int, repairInstruction: String?) -> String {
        let targetDate = NativeGameEngine.advance(date: state.gameDate, months: months)
        let safeTitle = sanitizeFoundationModelText(String(action.title.prefix(60)))
        let safeDetail = sanitizeFoundationModelText(String(action.detail.prefix(220)))
        
        return """
        Create one civic action-consequence event for a SwiftHistoria board-game turn.
        \(languageInstruction(for: state))
        The user has implemented this concrete action: "\(safeTitle)" - details: "\(safeDetail)".
        Describe the operational rollout and direct consequences of this specific action over the turn.
        Include one measurable game effect using either market-confidence or economic-resilience.
        The period starts on \(state.gameDate) and ends on \(targetDate).
        \(repairInstruction != nil ? "Repair note: \(repairInstruction!)" : "")
        
        \(hexLeverCodeInstruction())
        
        \(recentContext(for: state))
        """
    }
    
    private func makeSummaryPrompt(for state: NativeCampaignState, months: Int, events: [NativeCampaignEvent]) -> String {
        let targetDate = NativeGameEngine.advance(date: state.gameDate, months: months)
        let eventBriefs = events.map { "- \($0.title): \($0.strategicEffects.first?.summary ?? "")" }.joined(separator: "\n")
        return """
        Synthesize these \(events.count) turn developments into a single concise summary sentence.
        \(languageInstruction(for: state))
        Developments:
        \(eventBriefs)
        
        Evaluate aggregate stabilityDelta (-12 to 12) and globalFrictionDelta (-8 to 8) based on these occurrences.
        Period: \(state.gameDate) to \(targetDate).
        Return one strict JSON object only following the summary schema.
        """
    }
    
    private func makeAdvisorPrompt(for state: NativeCampaignState, question: String) -> String {
        return """
        Strategic advisor consultation.
        \(languageInstruction(for: state))
        Answer in no more than three short paragraphs. Finish every sentence; do not stop mid-phrase.
        Current Date: \(state.gameDate)
        Selected Country: \(state.country.name) (\(state.country.code))
        Stability: \(state.stability)/100
        World Tension: \(state.worldTension)/100
        
        Player's question: "\(question)"
        
        Provide a sharp, evidence-based strategic briefing context.
        """
    }
    
    private func makeDiplomaticPrompt(for state: NativeCampaignState, thread: NativeDiplomaticThread, message: String) -> String {
        let participant = thread.participant
        let dialogue = thread.messages.map { "- \($0.speaker): \($0.text)" }.joined(separator: "\n")
        return """
        Draft a diplomatic response from \(state.country.name) to \(participant.name) (\(participant.code)).
        Language: \(state.language == .portuguese ? "Portuguese" : "English")
        Counterpart doctrine: \(state.aiCountryStates[participant.code]?.doctrine.rawValue ?? "collaborative")
        Dialogue history:
        \(dialogue)
        
        Counterpart's statement: "\(message)"
        
        Write a short response (under 140 chars).
        """
    }
    
    private func makeSuggestionPrompt(for state: NativeCampaignState, focus: String, index: Int) -> String {
        let primaryMetric = "stability"
        return """
        Create one board-game suggestion proposal (proposal \(index)).
        Language: \(state.language == .portuguese ? "Portuguese" : "English")
        Selected Country: \(state.country.name)
        Focus area: \(focus)
        Primary metric: \(primaryMetric)
        
        Provide a concrete neutral proposal.
        """
    }
    
    private func recentContext(for state: NativeCampaignState) -> String {
        let recent = state.timeline.prefix(2)
        if recent.isEmpty { return "No recent events." }
        return "Recent event context:\n" + recent.map { "- \($0.title): \($0.description)" }.joined(separator: "\n")
    }
    
    private func languageInstruction(for state: NativeCampaignState) -> String {
        return state.language == .portuguese ? "Write all description and summary fields in Portuguese." : "Write all description and summary fields in English."
    }
    
    private func independentEventExamples(for lang: NativeGameLanguage) -> String {
        if lang == .portuguese {
            return """
            [Exemplo 1]
            {"title":"Índice de Frete Marítimo Estabiliza","description":"A demanda por comércio transatlântico se alinha com a capacidade de navios cargueiros, reduzindo custos de trânsito em corredores globais de suprimentos.","kind":"world","importance":"major","notable":true,"effectTarget":"GLOBAL","effectTrack":"market-confidence","effectMagnitude":1,"effectSummary":"Custos estáveis de frete marítimo reduzem a fricção de importação, apoiando o comércio."}
            """
        } else {
            return """
            [Exemplo 1]
            {"title":"Maritime Freight Index Stabilizes","description":"Transatlantic shipping demand aligns with carrier capacity, easing transit costs across major logistics corridors.","kind":"world","importance":"major","notable":true,"effectTarget":"GLOBAL","effectTrack":"market-confidence","effectMagnitude":1,"effectSummary":"Stable shipping costs ease import friction, supporting global trade."}
            """
        }
    }
    
    private func hexLeverCodeInstruction() -> String {
        return """
        Hexadecimal Lever Code:
        Output a `"hexLeverCode"` representing standard economic deltas. Use an 8-nibble map nudge only when this prompt explicitly asks for a conflict, border, insurgency, fallout, stabilization, conquest, or de-escalation change; otherwise use a 6-nibble economic code or null.
        Sovereignty change option:
        Use `"sovereigntyChange"` only for formal political changes, not ordinary occupation or insurgency. Kinds: `secession`, `new-country`, `merge`, `dissolution`. Keep targetCode uppercase A-Z, 3-6 characters. Set null for normal events.
        Standard options:
        - `"0x4D21F4"` for Infrastructure Boost
        - `"0xCD42D8"` for External Shock/Recession
        - `"0x22FDF3"` for Trade Diplomacy
        - `"0x11FF12"` for Market confidence signaling
        - `"0xCD42D882"` for Guerrilla Surge
        - `"0xCD42D883"` for Nuclear Fallout
        - `"0x1F1F0264"` for Stabilization Recovery
        - `"0x22FDF305"` for Contested Border
        """
    }
}

// MARK: - Concurrency Limiter Implementation

@MainActor
private final class ZAIModelLane {
    let name: String
    let displayName: String
    let maxConcurrent: Int
    let limiter: ConcurrencyLimiter

    init(name: String, displayName: String, maxConcurrent: Int) {
        self.name = name
        self.displayName = displayName
        self.maxConcurrent = maxConcurrent
        self.limiter = ConcurrencyLimiter(maxConcurrent: maxConcurrent)
    }
}

@MainActor
class ConcurrencyLimiter {
    private let maxConcurrent: Int
    private var activeCount = 0
    private var suspendedTasks: [CheckedContinuation<Void, Never>] = []
    
    init(maxConcurrent: Int) {
        self.maxConcurrent = maxConcurrent
    }
    
    func enter() async {
        if activeCount < maxConcurrent {
            activeCount += 1
        } else {
            await withCheckedContinuation { continuation in
                suspendedTasks.append(continuation)
            }
        }
    }
    
    func exit() {
        if !suspendedTasks.isEmpty {
            let next = suspendedTasks.removeFirst()
            next.resume()
        } else {
            activeCount -= 1
        }
    }
}

// MARK: - Local Clean Decodable Structs for Z.AI API payloads

private struct ZAIEventDraft: Decodable {
    var title: String
    var description: String
    var kind: String
    var importance: String
    var notable: Bool
    var effectTarget: String
    var effectTrack: String
    var effectMagnitude: Int
    var effectSummary: String
    var hexLeverCode: String?
    var sovereigntyChange: NativeSovereigntyChange?
    
    var hasConcreteContent: Bool {
        hasConcreteFoundationText(title, minimumWords: 2) &&
            hasConcreteFoundationText(description, minimumWords: 6) &&
            hasConcreteFoundationText(effectSummary, minimumWords: 6)
    }
    
    var validationDiagnostics: String {
        "titleWords=\(title.split(separator: " ").count) descWords=\(description.split(separator: " ").count)"
    }
    
    func toNativeEvent(
        state: NativeCampaignState,
        months: Int,
        index: Int,
        linkedActionID: String?,
        playerRelated: Bool
    ) -> NativeCampaignEvent {
        let eventDate = NativeGameEngine.advance(date: state.gameDate, months: months)
        let eventID = "zai-event-\(state.round)-\(index)-\(UUID().uuidString.prefix(6).lowercased())"
        
        let target = effectTarget == "GLOBAL" ? "GLOBAL" : (effectTarget == "PLAYER" ? state.country.code : effectTarget)
        let safeTrack: NativeStrategicTrack = effectTrack == "market-confidence" ? .marketConfidence : .economicResilience
        let safeKind: NativeEventKind = kind == "economy" ? .economy : (kind == "domestic" ? .action : .world)
        
        let targetEffect = NativeStrategicEffect(
            date: eventDate,
            eventId: eventID,
            id: "\(eventID)-effect",
            magnitude: Swift.max(-5, Swift.min(5, effectMagnitude)),
            summary: sanitizeFoundationModelText(effectSummary),
            target: sanitizeFoundationModelText(target),
            track: safeTrack
        )
        
        return NativeCampaignEvent(
            date: eventDate,
            description: sanitizeFoundationModelText(description),
            id: eventID,
            importance: importance == "critical" ? .severe : (importance == "major" ? .major : .minor),
            kind: safeKind,
            linkedActionIDs: linkedActionID.map { [$0] } ?? [],
            notable: notable,
            playerRelated: playerRelated,
            strategicEffects: [targetEffect],
            title: sanitizeFoundationModelText(title),
            hexLeverCode: hexLeverCode,
            sovereigntyChange: sovereigntyChange
        )
    }
    
    static let schemaInstructions = """
    {
      "title": "Strict short news headline of the event.",
      "description": "Concrete explanation referencing specific regional corridors or planning institutions.",
      "kind": "economy, domestic, or world",
      "importance": "minor, major, or critical",
      "notable": true,
      "effectTarget": "Country code like USA, CHN, or GLOBAL",
      "effectTrack": "market-confidence or economic-resilience",
      "effectMagnitude": -3 to 3,
      "effectSummary": "One concise sentence describing the game mechanics effect.",
      "hexLeverCode": "0xCode or null",
      "sovereigntyChange": null or {"kind":"secession|new-country|merge|dissolution","targetCode":"3-6 uppercase letters","name":"Country or breakaway polity name","sourceCodes":["Existing country codes"],"regionIDs":["Map region IDs affected"]}
    }
    """
}

private struct ZAITurnSummary: Decodable {
    var summary: String
    var stabilityDelta: Int
    var globalFrictionDelta: Int
    
    static let schemaInstructions = """
    {
      "summary": "One concise sentence summarizing why the generated period matters.",
      "stabilityDelta": 0,
      "globalFrictionDelta": 0
    }
    """
}

private struct ZAISuggestedAction: Decodable {
    var title: String
    var detail: String
    var rationale: String
    var urgency: String
    
    var hasConcreteContent: Bool {
        hasConcreteFoundationText(title, minimumWords: 2) &&
            hasConcreteFoundationText(detail, minimumWords: 6) &&
            hasConcreteFoundationText(rationale, minimumWords: 6)
    }
    
    func toNativeSuggestion(state: NativeCampaignState, index: Int) -> NativeSuggestedAction {
        NativeSuggestedAction(
            detail: sanitizeFoundationModelText(detail),
            id: "SUGGESTION_\(state.round)_\(index + 1)",
            rationale: sanitizeFoundationModelText(rationale),
            title: sanitizeFoundationModelText(title),
            urgency: normalizedFoundationUrgency(urgency)
        )
    }
    
    static let schemaInstructions = """
    {
      "title": "Short imperative title for the civic proposal.",
      "detail": "Concrete board-game planning proposal with primary mechanic.",
      "rationale": "Why this proposal fits current state.",
      "urgency": "immediate, soon, or opportunistic"
    }
    """
}

@MainActor
class DynamicAIService: NativeAIService {
    private let logger = Logger(subsystem: "com.gibavargas.SwiftHistoria", category: "DynamicAIService")
    private let zaiService = NativeZAIService()
    private let foundationService = NativeFoundationModelService()
    
    private var useZAIService: Bool {
        let key = UserDefaults.standard.string(forKey: "ZAI_API_KEY") ?? ""
        return !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    func checkReadiness() async -> NativeAIReadiness {
        if useZAIService {
            return await zaiService.checkReadiness()
        } else {
            return await foundationService.checkReadiness()
        }
    }
    
    func generateTurn(for state: NativeCampaignState, months: Int) async throws -> NativeGeneratedTurn {
        if useZAIService {
            do {
                return try await zaiService.generateTurn(for: state, months: months)
            } catch {
                let zaiError = error
                logger.error("Z.AI turn failed; trying Apple Foundation Models. z_ai_error=\(zaiError.localizedDescription, privacy: .public)")
                do {
                    return try await foundationService.generateTurn(for: state, months: months)
                } catch {
                    logger.error("Apple Foundation turn also failed. apple_error=\(error.localizedDescription, privacy: .public)")
                    throw NativeFoundationModelError.generationFailed("Turn generation failed on Z.AI and Apple Foundation Models. Z.AI: \(zaiError.localizedDescription) Apple: \(error.localizedDescription)")
                }
            }
        }
        return try await foundationService.generateTurn(for: state, months: months)
    }
    
    func generateTurn(
        for state: NativeCampaignState,
        months: Int,
        progress: @escaping @MainActor (NativeTurnProgress) -> Void
    ) async throws -> NativeGeneratedTurn {
        if useZAIService {
            do {
                return try await zaiService.generateTurn(for: state, months: months, progress: progress)
            } catch {
                let zaiError = error
                logger.error("Z.AI turn failed; trying Apple Foundation Models. z_ai_error=\(zaiError.localizedDescription, privacy: .public)")
                do {
                    return try await foundationService.generateTurn(for: state, months: months, progress: progress)
                } catch {
                    logger.error("Apple Foundation turn also failed. apple_error=\(error.localizedDescription, privacy: .public)")
                    throw NativeFoundationModelError.generationFailed("Turn generation failed on Z.AI and Apple Foundation Models. Z.AI: \(zaiError.localizedDescription) Apple: \(error.localizedDescription)")
                }
            }
        }
        return try await foundationService.generateTurn(for: state, months: months, progress: progress)
    }
    
    func generateSuggestedActions(for state: NativeCampaignState) async throws -> [NativeSuggestedAction] {
        if useZAIService {
            do {
                return try await zaiService.generateSuggestedActions(for: state)
            } catch {
                let zaiError = error
                logger.error("Z.AI suggestions failed; trying Apple Foundation Models. z_ai_error=\(zaiError.localizedDescription, privacy: .public)")
                do {
                    return try await foundationService.generateSuggestedActions(for: state)
                } catch {
                    logger.error("Apple Foundation suggestions also failed. apple_error=\(error.localizedDescription, privacy: .public)")
                    throw NativeFoundationModelError.generationFailed("Suggested actions failed on Z.AI and Apple Foundation Models. Z.AI: \(zaiError.localizedDescription) Apple: \(error.localizedDescription)")
                }
            }
        }
        return try await foundationService.generateSuggestedActions(for: state)
    }
    
    func generateAdvisorBrief(for state: NativeCampaignState, question: String) async throws -> String {
        if useZAIService {
            return try await zaiService.generateAdvisorBrief(for: state, question: question)
        } else {
            return try await foundationService.generateAdvisorBrief(for: state, question: question)
        }
    }
    
    func generateDiplomaticReply(
        for state: NativeCampaignState,
        thread: NativeDiplomaticThread,
        message: String
    ) async throws -> String {
        if useZAIService {
            return try await zaiService.generateDiplomaticReply(for: state, thread: thread, message: message)
        } else {
            return try await foundationService.generateDiplomaticReply(for: state, thread: thread, message: message)
        }
    }
}
