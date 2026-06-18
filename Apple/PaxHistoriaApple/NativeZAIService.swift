import Foundation
import OSLog

enum NativeJSONExtraction {
    static func candidates(from rawText: String) -> [String] {
        let trimmed = rawText
            .replacingOccurrences(of: "\u{FEFF}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var sources = [trimmed]
        if trimmed.hasPrefix("```") {
            let lines = trimmed.components(separatedBy: .newlines)
            let unfenced = lines
                .dropFirst()
                .dropLast(lines.last?.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("```") == true ? 1 : 0)
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !unfenced.isEmpty {
                sources.append(unfenced)
            }
        }

        var candidates: [String] = sources
        for source in sources {
            candidates.append(contentsOf: balancedObjects(in: source))
        }

        var seen: Set<String> = []
        return candidates.filter { seen.insert($0).inserted }
    }

    private static func balancedObjects(in source: String) -> [String] {
        var objects: [String] = []
        var depth = 0
        var start: String.Index?
        var inString = false
        var escaping = false

        for index in source.indices {
            let char = source[index]
            if inString {
                if escaping {
                    escaping = false
                } else if char == "\\" {
                    escaping = true
                } else if char == "\"" {
                    inString = false
                }
                continue
            }

            if char == "\"" {
                inString = true
            } else if char == "{" {
                if depth == 0 {
                    start = index
                }
                depth += 1
            } else if char == "}", depth > 0 {
                depth -= 1
                if depth == 0, let objectStart = start {
                    objects.append(String(source[objectStart ... index]).trimmingCharacters(in: .whitespacesAndNewlines))
                    start = nil
                }
            }
        }
        return objects.filter { !$0.isEmpty }
    }
}

@MainActor
class NativeZAIService: NativeAIService {
    let logger = Logger(subsystem: "com.gibavargas.SwiftHistoria", category: "NativeZAIService")
    let defaults: UserDefaults
    private let promptHarness = NativeFoundationModelService()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Whether the provider supports the GLM-specific "thinking" field.
    /// OpenRouter and other non-Z.AI providers should override to false.
    var includesThinkingField: Bool {
        true
    }

    var modelLanes: [ZAIModelLane] = [
        ZAIModelLane(name: "glm-5", displayName: "GLM-5", maxConcurrent: 2),
        ZAIModelLane(name: "glm-4.7-flashx", displayName: "GLM-4.7-FlashX", maxConcurrent: 3),
        ZAIModelLane(name: "glm-4.7-flash", displayName: "GLM-4.7-Flash", maxConcurrent: 1)
    ]

    var providerDisplayName: String {
        "Z.AI"
    }

    var routeDisplayName: String {
        useCodingEndpoint ? "Z.AI Coding Endpoint" : "Z.AI API"
    }

    var primaryModelDisplayName: String {
        modelLanes.first?.displayName ?? "Unknown model"
    }

    var primaryModelIdentifier: String {
        modelLanes.first?.name ?? "unknown"
    }

    private var nextModelLaneStartIndex = 0

    var apiKey: String {
        defaults.string(forKey: "ZAI_API_KEY") ?? ""
    }

    var useCodingEndpoint: Bool {
        defaults.bool(forKey: "ZAI_USE_CODING_ENDPOINT")
    }

    var apiEndpoint: URL {
        if useCodingEndpoint {
            URL(string: "https://api.z.ai/api/coding/paas/v4/chat/completions")!
        } else {
            URL(string: "https://api.z.ai/api/paas/v4/chat/completions")!
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
            return .unavailable("\(providerDisplayName) API Key not configured in System Settings.")
        }
        do {
            _ = try await executeZAIRequest(
                prompt: "Return exactly this JSON: {\"ok\":true}",
                maxTokens: 16,
                temperature: 0.0,
                responseFormat: "json_object",
                thinkingEnabled: false
            )
            return .available(tokenBudget: "\(providerDisplayName) model lanes verified")
        } catch {
            logger.error("\(self.providerDisplayName, privacy: .public) readiness probe failed")
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
        logger.info("\(self.providerDisplayName, privacy: .public) turn generation started round=\(state.round) months=\(months)")
        let rawTurn = try await generateSlicedTurn(for: state, months: months, progress: progress)
        do {
            let validated = try NativeGameEngine.validated(rawTurn, state: state, months: months)
            logger.info("\(self.providerDisplayName, privacy: .public) turn generation validated events=\(validated.events.count)")
            return validated
        } catch {
            logger.error("\(self.providerDisplayName, privacy: .public) turn validation failed; retrying with repair instruction")
            let retryTurn = try await generateSlicedTurn(
                for: state,
                months: months,
                repairInstruction: error.localizedDescription,
                progress: progress
            )
            do {
                let validated = try NativeGameEngine.validated(retryTurn, state: state, months: months)
                logger.info("\(self.providerDisplayName, privacy: .public) repaired turn validated events=\(validated.events.count)")
                return validated
            } catch {
                logger.error("\(self.providerDisplayName, privacy: .public) repaired turn remained invalid: \(error.localizedDescription)")
                throw NativeFoundationModelError.invalidGeneratedTurn(error.localizedDescription)
            }
        }
    }

    func generateSuggestedActions(for state: NativeCampaignState) async throws -> [NativeSuggestedAction] {
        logger.info("\(self.providerDisplayName, privacy: .public) suggestions started round=\(state.round)")
        let suggestions = try await generateStructuredSuggestions(for: state)
        let validSuggestions = suggestions.filter { isValidNativeSuggestion($0) }
        guard validSuggestions.count >= 3 else {
            logger.error("\(self.providerDisplayName, privacy: .public) suggestions invalid count=\(validSuggestions.count)")
            throw NativeFoundationModelError.invalidSuggestedActions("Expected at least three concrete suggestions from \(providerDisplayName).")
        }
        logger.info("\(self.providerDisplayName, privacy: .public) suggestions validated count=\(validSuggestions.count)")
        return Array(validSuggestions.prefix(4))
    }

    func generateAdvisorBrief(for state: NativeCampaignState, question: String) async throws -> String {
        let safeQuestion = sanitizeFoundationModelText(question)
        guard hasConcreteFoundationText(safeQuestion, minimumWords: 2) else {
            throw NativeFoundationModelError.generationFailed("Advisor question was empty or placeholder-like.")
        }

        logger.info("\(self.providerDisplayName, privacy: .public) advisor generation started round=\(state.round)")
        let answer = try await generateTextResponse(
            prompt: makeAdvisorPrompt(for: state, question: safeQuestion),
            maxTokens: 520,
            repairNote: "Answer as a blunt strategic advisor in no more than three short paragraphs."
        )
        logger.info("\(self.providerDisplayName, privacy: .public) advisor generation completed")
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

        logger.info("\(self.providerDisplayName, privacy: .public) diplomatic reply started round=\(state.round) counterpart=\(thread.participant.code)")
        let reply = try await generateTextResponse(
            prompt: makeDiplomaticPrompt(for: state, thread: thread, message: safeMessage),
            maxTokens: 140,
            repairNote: "Draft a diplomatic response of one or two sentences in the active voice. Keep it under 140 characters."
        )
        logger.info("\(self.providerDisplayName, privacy: .public) diplomatic reply completed")
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
            detail: "Calling \(routeDisplayName) with \(primaryModelDisplayName) first; other lanes may use fallback models.",
            phase: "Consulting \(providerDisplayName)",
            totalLanes: totalLanes,
            providerName: providerDisplayName,
            modelName: primaryModelDisplayName,
            modelIdentifier: primaryModelIdentifier
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
                case let .independent(draft):
                    independentDraft = draft
                    phase = NativeFoundationTurnLane.external.title
                    detail = "External facts lane completed: \(sanitizeFoundationModelText(draft.title))"
                case let .economic(draft):
                    economicDraft = draft
                    phase = NativeFoundationTurnLane.economy.title
                    detail = "Economic consequences lane completed: \(sanitizeFoundationModelText(draft.title))"
                case let .domestic(draft):
                    domesticDraft = draft
                    phase = NativeFoundationTurnLane.domestic.title
                    detail = "Domestic response lane completed: \(sanitizeFoundationModelText(draft.title))"
                case let .globalAI(draft):
                    globalAIDraft = draft
                    phase = NativeFoundationTurnLane.external.title
                    detail = "Global AI Action lane completed: \(sanitizeFoundationModelText(draft.title))"
                case let .action(action, draft):
                    actionDrafts[action.id] = draft
                    phase = NativeFoundationTurnLane.actionConsequence.title
                    detail = "Resolved \(sanitizeFoundationModelText(action.title)): \(sanitizeFoundationModelText(draft.title))"
                }

                progress(NativeTurnProgress(
                    completedLanes: completedLanes,
                    detail: detail,
                    phase: phase,
                    totalLanes: totalLanes,
                    providerName: providerDisplayName,
                    modelName: primaryModelDisplayName,
                    modelIdentifier: primaryModelIdentifier
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
            totalLanes: totalLanes,
            providerName: providerDisplayName,
            modelName: primaryModelDisplayName,
            modelIdentifier: primaryModelIdentifier
        ))

        let summary = try await generateTurnSummary(state: state, months: months, events: events)
        progress(NativeTurnProgress(
            completedLanes: totalLanes,
            detail: "\(providerDisplayName) turn synthesis completed.",
            phase: NativeFoundationTurnLane.summary.title,
            totalLanes: totalLanes,
            providerName: providerDisplayName,
            modelName: primaryModelDisplayName,
            modelIdentifier: primaryModelIdentifier
        ))
        logger.info("\(self.providerDisplayName, privacy: .public) sliced turn assembled events=\(events.count)")

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
        for attempt in 1 ... 3 {
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
            "education, service access, administrative capacity, and action memory"
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

        for attempt in 1 ... 2 {
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
        for attempt in 1 ... 2 {
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

    func executeZAIRequest(
        prompt: String,
        maxTokens: Int,
        temperature: Double,
        responseFormat: String? = nil,
        thinkingEnabled: Bool = true
    ) async throws -> String {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            throw NativeFoundationModelError.modelUnavailable("\(providerDisplayName) API Key is empty. Please set it in system settings.")
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
            try await lane.limiter.enter()
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
                "max_tokens": maxTokens
            ]
            if includesThinkingField {
                payload["thinking"] = [
                    "type": thinkingEnabled ? "enabled" : "disabled"
                ]
            }
            if let responseFormat {
                payload["response_format"] = ["type": responseFormat]
            }

            do {
                request.httpBody = try JSONSerialization.data(withJSONObject: payload)
                let (data, response) = try await URLSession.shared.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    throw NativeFoundationModelError.generationFailed("Invalid response format from \(providerDisplayName) model=\(lane.name).")
                }

                guard httpResponse.statusCode == 200 else {
                    let errorText = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
                    throw NativeFoundationModelError.generationFailed("\(providerDisplayName) returned status \(httpResponse.statusCode) model=\(lane.name): \(errorText)")
                }

                do {
                    let content = try Self.decodeCompletionContent(from: data, providerDisplayName: providerDisplayName)
                    lane.limiter.exit()
                    releaseLane = false
                    return content
                } catch {
                    if thinkingEnabled {
                        lane.limiter.exit()
                        releaseLane = false
                        logger.error("\(self.providerDisplayName, privacy: .public) visible content failed with thinking; retrying without thinking model=\(lane.name, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
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
                logger.error("\(self.providerDisplayName, privacy: .public) request failed model=\(lane.name, privacy: .public) limit=\(lane.maxConcurrent) error=\(error.localizedDescription, privacy: .public)")
            }
        }

        throw lastError ?? NativeFoundationModelError.generationFailed("\(providerDisplayName) request failed for all configured models.")
    }

    nonisolated static func decodeCompletionContent(from data: Data, providerDisplayName: String = "Z.AI") throws -> String {
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
            throw NativeFoundationModelError.generationFailed("\(providerDisplayName) response decode failed: \(error.localizedDescription). Raw prefix: \(rawPrefix)")
        }
        guard let firstChoice = decoded.choices.first else {
            throw NativeFoundationModelError.generationFailed("\(providerDisplayName) API returned empty choices.")
        }

        let content = firstChoice.message.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let reasoning = firstChoice.message.reasoningContent?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if let reason = firstChoice.finishReason,
           ["length", "sensitive", "model_context_window_exceeded", "network_error"].contains(reason)
        {
            throw NativeFoundationModelError.generationFailed("\(providerDisplayName) returned no visible content (finish_reason=\(reason), choices=\(decoded.choices.count), content_chars=\(content.count), reasoning_chars=\(reasoning.count)).")
        }

        if !content.isEmpty {
            return strippingZAIThinkingTags(from: content)
        }

        throw NativeFoundationModelError.generationFailed("\(providerDisplayName) returned no visible content (finish_reason=\(firstChoice.finishReason ?? "nil"), choices=\(decoded.choices.count), content_chars=\(content.count), reasoning_chars=\(reasoning.count)).")
    }

    private nonisolated static func strippingZAIThinkingTags(from content: String) -> String {
        var output = content
        while let startRange = output.range(of: "<think>"),
              let endRange = output.range(of: "</think>", range: startRange.upperBound ..< output.endIndex)
        {
            output.removeSubrange(startRange.lowerBound ..< endRange.upperBound)
        }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Prompt & Text Helpers

    private var nativeSystemPrompt: String {
        NativePromptHarness.sharedSystemPrompt
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
        Banned title words: Apple, Native, Generated, Draft, Placeholder, Schema.
        Use a concrete title like Transit Funding Review, Grid Capacity Program, or School Access Plan.
        """
    }

    private func textPrompt(_ basePrompt: String, repairNotes: [String]) -> String {
        guard !repairNotes.isEmpty else { return basePrompt }
        return """
        \(basePrompt)

        Recent correction requests:
        \(repairNotes.map { "- \($0)" }.joined(separator: "\n"))
        Do not return placeholder text, schema labels, unsafe operational instructions, or repeated sentences.
        """
    }

    private func suggestionPrompt(_ basePrompt: String, repairNotes: [String]) -> String {
        let repairBlock = repairNotes.isEmpty ? "" : "\n\nSuggestion repair notes:\n\(repairNotes.map { "- \($0)" }.joined(separator: "\n"))"
        return """
        \(basePrompt)\(repairBlock)

        Return one strict JSON object only. Do not include markdown fences, prose, schema labels, or comments.
        Banned title words: Apple, Native, Generated, Draft, Placeholder, Schema.
        """
    }

    private func foundationJSONCandidates(from rawText: String) -> [String] {
        NativeJSONExtraction.candidates(from: rawText)
    }

    /// Reuse the Apple-native prompt harness so external providers stay aligned with
    /// the same scenario, mechanics, language, and repair contracts.
    private func makeIndependentEventPrompt(for state: NativeCampaignState, months: Int, repairInstruction: String?) -> String {
        promptHarness.makeIndependentEventPrompt(for: state, months: months, repairInstruction: repairInstruction)
    }

    private func makeEconomicEventPrompt(for state: NativeCampaignState, months: Int, repairInstruction: String?) -> String {
        promptHarness.makeEconomicEventPrompt(for: state, months: months, repairInstruction: repairInstruction)
    }

    private func makeDomesticEventPrompt(for state: NativeCampaignState, months: Int, repairInstruction: String?) -> String {
        promptHarness.makeDomesticEventPrompt(for: state, months: months, repairInstruction: repairInstruction)
    }

    private func makeGlobalAIActionsPrompt(for state: NativeCampaignState, months: Int, repairInstruction: String?) -> String {
        promptHarness.makeGlobalAIActionsPrompt(for: state, months: months, repairInstruction: repairInstruction)
    }

    private func makeActionEventPrompt(for state: NativeCampaignState, action: NativePlannedAction, months: Int, repairInstruction: String?) -> String {
        promptHarness.makeActionEventPrompt(for: state, action: action, months: months, repairInstruction: repairInstruction)
    }

    private func makeSummaryPrompt(for state: NativeCampaignState, months: Int, events: [NativeCampaignEvent]) -> String {
        promptHarness.makeSummaryPrompt(for: state, months: months, events: events)
    }

    private func makeAdvisorPrompt(for state: NativeCampaignState, question: String) -> String {
        promptHarness.makeAdvisorPrompt(for: state, question: question)
    }

    private func makeDiplomaticPrompt(for state: NativeCampaignState, thread: NativeDiplomaticThread, message: String) -> String {
        promptHarness.makeDiplomacyPrompt(for: state, thread: thread, message: message)
    }

    private func makeSuggestionPrompt(for state: NativeCampaignState, focus: String, index: Int) -> String {
        promptHarness.makeSuggestionPrompt(for: state, focus: focus, index: index)
    }

    private func recentContext(for state: NativeCampaignState) -> String {
        let recent = state.timeline.prefix(2)
        if recent.isEmpty { return "No recent events." }
        return "Recent event context:\n" + recent.map { "- \($0.title): \($0.description)" }.joined(separator: "\n")
    }

    private func languageInstruction(for state: NativeCampaignState) -> String {
        state.language == .portuguese ? "Write all description and summary fields in Portuguese." : "Write all description and summary fields in English."
    }

    private func independentEventExamples(for lang: NativeGameLanguage) -> String {
        if lang == .portuguese {
            """
            [Exemplo 1]
            {"title":"Índice de Frete Marítimo Estabiliza","description":"A demanda por comércio transatlântico se alinha com a capacidade de navios cargueiros, reduzindo custos de trânsito em corredores globais de suprimentos.","kind":"world","importance":"major","notable":true,"effectTarget":"GLOBAL","effectTrack":"market-confidence","effectMagnitude":1,"effectSummary":"Custos estáveis de frete marítimo reduzem a fricção de importação, apoiando o comércio."}
            """
        } else {
            """
            [Exemplo 1]
            {"title":"Maritime Freight Index Stabilizes","description":"Transatlantic shipping demand aligns with carrier capacity, easing transit costs across major logistics corridors.","kind":"world","importance":"major","notable":true,"effectTarget":"GLOBAL","effectTrack":"market-confidence","effectMagnitude":1,"effectSummary":"Stable shipping costs ease import friction, supporting global trade."}
            """
        }
    }

    private func hexLeverCodeInstruction() -> String {
        """
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
final class ZAIModelLane {
    let name: String
    let displayName: String
    let maxConcurrent: Int
    let limiter: ConcurrencyLimiter

    init(name: String, displayName: String, maxConcurrent: Int) {
        self.name = name
        self.displayName = displayName
        self.maxConcurrent = maxConcurrent
        limiter = ConcurrencyLimiter(maxConcurrent: maxConcurrent)
    }
}

@MainActor
class ConcurrencyLimiter {
    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Bool, Never>
    }

    private let maxConcurrent: Int
    private var activeCount = 0
    private var suspendedTasks: [Waiter] = []

    init(maxConcurrent: Int) {
        self.maxConcurrent = maxConcurrent
    }

    func enter() async throws {
        let waiterID = UUID()
        if activeCount < maxConcurrent {
            activeCount += 1
            return
        }

        let entered = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                suspendedTasks.append(Waiter(id: waiterID, continuation: continuation))
            }
        } onCancel: {
            Task { @MainActor in
                self.cancel(waiterID)
            }
        }

        guard entered, !Task.isCancelled else {
            throw CancellationError()
        }
    }

    func exit() {
        if !suspendedTasks.isEmpty {
            let next = suspendedTasks.removeFirst()
            next.continuation.resume(returning: true)
        } else {
            activeCount = max(0, activeCount - 1)
        }
    }

    private func cancel(_ waiterID: UUID) {
        guard let index = suspendedTasks.firstIndex(where: { $0.id == waiterID }) else {
            return
        }
        let waiter = suspendedTasks.remove(at: index)
        waiter.continuation.resume(returning: false)
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
        let normalizedTrack = effectTrack
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
        let safeTrack = NativeStrategicTrack(rawValue: normalizedTrack) ?? .economicResilience
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
      "effectTrack": "economic-resilience, market-confidence, diplomatic-leverage, internal-stability, world-tension, military-readiness, or security-anxiety",
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
    private let defaults: UserDefaults
    private let openRouterService: NativeOpenRouterService
    private let zaiService: NativeZAIService
    private let foundationService = NativeFoundationModelService()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.openRouterService = NativeOpenRouterService(defaults: defaults)
        self.zaiService = NativeZAIService(defaults: defaults)
    }

    private var providerPreference: NativeAIProviderPreference {
        NativeAIProviderPreference.current(defaults: defaults)
    }

    private var hasOpenRouterKey: Bool {
        let key = defaults.string(forKey: "OPENROUTER_API_KEY") ?? ""
        return !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var hasZAIKey: Bool {
        let key = defaults.string(forKey: "ZAI_API_KEY") ?? ""
        return !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func checkReadiness() async -> NativeAIReadiness {
        switch providerPreference {
        case .appleFoundation:
            return await foundationService.checkReadiness()
        case .openRouter:
            if hasOpenRouterKey {
                let openRouterReadiness = await openRouterService.checkReadiness()
                if openRouterReadiness.ok {
                    return openRouterReadiness
                }
                if hasZAIKey {
                    let zaiReadiness = await zaiService.checkReadiness()
                    if zaiReadiness.ok {
                        return .available(tokenBudget: "OpenRouter unavailable; Z.AI fallback verified")
                    }
                }
                let appleReadiness = await foundationService.checkReadiness()
                if appleReadiness.ok {
                    return .available(tokenBudget: "OpenRouter unavailable; Apple Foundation Models fallback verified")
                }
                return openRouterReadiness
            }
            if hasZAIKey { return await zaiService.checkReadiness() }
            return await foundationService.checkReadiness()
        case .zai:
            if hasZAIKey { return await zaiService.checkReadiness() }
            return await foundationService.checkReadiness()
        }
    }

    private func generateWithAppleFallback<T>(
        label: String,
        operation: () async throws -> T,
        appleOperation: () async throws -> T
    ) async throws -> T {
        do {
            return try await operation()
        } catch {
            logger.error("\(label, privacy: .public) failed; trying Apple Foundation Models. error=\(error.localizedDescription, privacy: .public)")
            do {
                return try await appleOperation()
            } catch {
                logger.error("Apple Foundation fallback also failed. apple_error=\(error.localizedDescription, privacy: .public)")
                throw error
            }
        }
    }

    func generateTurn(for state: NativeCampaignState, months: Int) async throws -> NativeGeneratedTurn {
        switch providerPreference {
        case .appleFoundation:
            return try await foundationService.generateTurn(for: state, months: months)
        case .openRouter:
            if hasOpenRouterKey {
                do {
                    logger.info("OpenRouter turn generation started round=\(state.round)")
                    return try await openRouterService.generateTurn(for: state, months: months)
                } catch {
                    logger.error("OpenRouter turn failed; trying configured fallback. openrouter_error=\(error.localizedDescription, privacy: .public)")
                }
            }
            if hasZAIKey {
                return try await generateWithAppleFallback(
                    label: "Z.AI turn",
                    operation: { try await self.zaiService.generateTurn(for: state, months: months) },
                    appleOperation: { try await self.foundationService.generateTurn(for: state, months: months) }
                )
            }
            return try await foundationService.generateTurn(for: state, months: months)
        case .zai:
            if hasZAIKey {
                return try await generateWithAppleFallback(
                    label: "Z.AI turn",
                    operation: { try await self.zaiService.generateTurn(for: state, months: months) },
                    appleOperation: { try await self.foundationService.generateTurn(for: state, months: months) }
                )
            }
            return try await foundationService.generateTurn(for: state, months: months)
        }
    }

    func generateTurn(
        for state: NativeCampaignState,
        months: Int,
        progress: @escaping @MainActor (NativeTurnProgress) -> Void
    ) async throws -> NativeGeneratedTurn {
        let total = NativeStrategyContextDatabase.estimatedLaneCount(for: state)

        switch providerPreference {
        case .appleFoundation:
            return try await foundationService.generateTurn(for: state, months: months, progress: progress)
        case .openRouter:
            if hasOpenRouterKey {
                do {
                    logger.info("OpenRouter turn generation started round=\(state.round)")
                    return try await openRouterService.generateTurn(for: state, months: months, progress: progress)
                } catch {
                    logger.error("OpenRouter turn failed; trying configured fallback. openrouter_error=\(error.localizedDescription, privacy: .public)")
                    let fallbackProvider = hasZAIKey ? "Z.AI" : "Apple Foundation Models"
                    progress(NativeTurnProgress(
                        completedLanes: 0,
                        detail: "OpenRouter failed: \(error.localizedDescription). Trying \(fallbackProvider) fallback now.",
                        phase: hasZAIKey ? "Falling back to Z.AI" : "Falling back to Apple",
                        totalLanes: total,
                        providerName: hasZAIKey ? "Z.AI" : "Apple Foundation Models",
                        modelName: hasZAIKey ? zaiService.primaryModelDisplayName : "System Language Model",
                        modelIdentifier: hasZAIKey ? zaiService.primaryModelIdentifier : "SystemLanguageModel.default"
                    ))
                }
            } else {
                progress(NativeTurnProgress(
                    completedLanes: 0,
                    detail: hasZAIKey ? "OpenRouter is selected, but no OpenRouter API key is saved. Trying Z.AI fallback now." : "OpenRouter is selected, but no OpenRouter API key is saved. Trying Apple Foundation Models now.",
                    phase: hasZAIKey ? "Falling back to Z.AI" : "Falling back to Apple",
                    totalLanes: total,
                    providerName: hasZAIKey ? "Z.AI" : "Apple Foundation Models",
                    modelName: hasZAIKey ? zaiService.primaryModelDisplayName : "System Language Model",
                    modelIdentifier: hasZAIKey ? zaiService.primaryModelIdentifier : "SystemLanguageModel.default"
                ))
            }
            if hasZAIKey {
                do {
                    return try await zaiService.generateTurn(for: state, months: months, progress: progress)
                } catch {
                    logger.error("Z.AI turn failed; trying Apple Foundation Models. z_ai_error=\(error.localizedDescription, privacy: .public)")
                    progress(NativeTurnProgress(
                        completedLanes: 0,
                        detail: "Z.AI failed: \(error.localizedDescription). Trying Apple Foundation Models now.",
                        phase: "Falling back to Apple",
                        totalLanes: total,
                        providerName: "Apple Foundation Models",
                        modelName: "System Language Model",
                        modelIdentifier: "SystemLanguageModel.default"
                    ))
                }
            }
            return try await foundationService.generateTurn(for: state, months: months, progress: progress)
        case .zai:
            if hasZAIKey {
                do {
                    return try await zaiService.generateTurn(for: state, months: months, progress: progress)
                } catch {
                    logger.error("Z.AI turn failed; trying Apple Foundation Models. z_ai_error=\(error.localizedDescription, privacy: .public)")
                    progress(NativeTurnProgress(
                        completedLanes: 0,
                        detail: "Z.AI failed: \(error.localizedDescription). Trying Apple Foundation Models now.",
                        phase: "Falling back to Apple",
                        totalLanes: total,
                        providerName: "Apple Foundation Models",
                        modelName: "System Language Model",
                        modelIdentifier: "SystemLanguageModel.default"
                    ))
                }
            } else {
                progress(NativeTurnProgress(
                    completedLanes: 0,
                    detail: "Z.AI is selected, but no Z.AI API key is saved. Trying Apple Foundation Models now.",
                    phase: "Falling back to Apple",
                    totalLanes: total,
                    providerName: "Apple Foundation Models",
                    modelName: "System Language Model",
                    modelIdentifier: "SystemLanguageModel.default"
                ))
            }
            return try await foundationService.generateTurn(for: state, months: months, progress: progress)
        }
    }

    func generateSuggestedActions(for state: NativeCampaignState) async throws -> [NativeSuggestedAction] {
        switch providerPreference {
        case .appleFoundation:
            return try await foundationService.generateSuggestedActions(for: state)
        case .openRouter:
            if hasOpenRouterKey, let result = try? await openRouterService.generateSuggestedActions(for: state) { return result }
            if hasZAIKey {
                return try await generateWithAppleFallback(
                    label: "Z.AI suggestions",
                    operation: { try await self.zaiService.generateSuggestedActions(for: state) },
                    appleOperation: { try await self.foundationService.generateSuggestedActions(for: state) }
                )
            }
            return try await foundationService.generateSuggestedActions(for: state)
        case .zai:
            if hasZAIKey {
                return try await generateWithAppleFallback(
                    label: "Z.AI suggestions",
                    operation: { try await self.zaiService.generateSuggestedActions(for: state) },
                    appleOperation: { try await self.foundationService.generateSuggestedActions(for: state) }
                )
            }
            return try await foundationService.generateSuggestedActions(for: state)
        }
    }

    func generateAdvisorBrief(for state: NativeCampaignState, question: String) async throws -> String {
        switch providerPreference {
        case .appleFoundation:
            return try await foundationService.generateAdvisorBrief(for: state, question: question)
        case .openRouter:
            if hasOpenRouterKey, let result = try? await openRouterService.generateAdvisorBrief(for: state, question: question) { return result }
            if hasZAIKey, let result = try? await zaiService.generateAdvisorBrief(for: state, question: question) { return result }
            return try await foundationService.generateAdvisorBrief(for: state, question: question)
        case .zai:
            if hasZAIKey, let result = try? await zaiService.generateAdvisorBrief(for: state, question: question) { return result }
            return try await foundationService.generateAdvisorBrief(for: state, question: question)
        }
    }

    func generateDiplomaticReply(
        for state: NativeCampaignState,
        thread: NativeDiplomaticThread,
        message: String
    ) async throws -> String {
        switch providerPreference {
        case .appleFoundation:
            return try await foundationService.generateDiplomaticReply(for: state, thread: thread, message: message)
        case .openRouter:
            if hasOpenRouterKey, let result = try? await openRouterService.generateDiplomaticReply(for: state, thread: thread, message: message) { return result }
            if hasZAIKey, let result = try? await zaiService.generateDiplomaticReply(for: state, thread: thread, message: message) { return result }
            return try await foundationService.generateDiplomaticReply(for: state, thread: thread, message: message)
        case .zai:
            if hasZAIKey, let result = try? await zaiService.generateDiplomaticReply(for: state, thread: thread, message: message) { return result }
            return try await foundationService.generateDiplomaticReply(for: state, thread: thread, message: message)
        }
    }
}
