import Foundation
import OSLog

#if canImport(FoundationModels)
    import FoundationModels
#endif

enum NativePromptHarness {
    static let foundationCharacterLimit = 8500
    static let trimMarker = "\n\n[Middle context trimmed for the local Apple Foundation Models window. Keep the opening task and closing output constraints authoritative.]\n\n"

    static let sharedSystemPrompt = """
    You are the game master for SwiftHistoria, a turn-based geopolitical strategy game.
    You narrate events like an experienced intelligence analyst covering global developments.
    Treat the current campaign state, selected scenario, start date, and stored mechanics as canon.
    Be specific: use real institutions and economic mechanisms only when supported by the campaign context; otherwise use plausible fictional civic agencies.
    Every event should read like a headline from a serious geopolitical intelligence briefing.
    Use concrete details: organizations, dates, economic indicators, and measurable game effects.
    Connect every answer to the current campaign mechanics instead of giving generic advice.
    Do not present post-start-date facts as already true unless they are stored in the campaign state.
    Follow the request's response-language instruction for all player-facing prose.
    Keep schema field names, enum values, identifiers, IDs, dates, and game tokens exactly as requested.
    """

    static func clamped(_ value: String, characterLimit: Int = foundationCharacterLimit) -> String {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count > characterLimit else { return text }

        let available = max(0, characterLimit - trimMarker.count)
        let headCount = max(0, Int(Double(available) * 0.62))
        let tailCount = max(0, available - headCount)
        let headEnd = text.index(text.startIndex, offsetBy: min(headCount, text.count))
        let tailStart = text.index(text.endIndex, offsetBy: -min(tailCount, text.count))
        return "\(text[..<headEnd])\(trimMarker)\(text[tailStart...])"
    }
}

enum NativeAIProviderPreference: String, CaseIterable {
    case appleFoundation
    case openRouter
    case zai

    static let storageKey = "NATIVE_AI_PROVIDER_PREFERENCE"

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .appleFoundation: "Apple Foundation"
        case .openRouter: "OpenRouter"
        case .zai: "Z.AI"
        }
    }

    var subtitle: String {
        switch self {
        case .appleFoundation:
            "Use Apple's on-device System Language Model. No external API key required."
        case .openRouter:
            "Use OpenRouter's unified Free Models Router. Requires an OpenRouter API key."
        case .zai:
            "Use Z.AI GLM models first, then fall back to Apple if unavailable."
        }
    }

    var providerName: String {
        switch self {
        case .appleFoundation: "Apple Foundation Models"
        case .openRouter: "OpenRouter"
        case .zai: "Z.AI"
        }
    }

    static func current(defaults: UserDefaults = .standard) -> NativeAIProviderPreference {
        if let raw = defaults.string(forKey: storageKey), let value = NativeAIProviderPreference(rawValue: raw) {
            return value
        }
        return .openRouter
    }
}

@MainActor
protocol NativeAIService {
    func checkReadiness() async -> NativeAIReadiness
    func generateTurn(for state: NativeCampaignState, months: Int) async throws -> NativeGeneratedTurn
    func generateTurn(
        for state: NativeCampaignState,
        months: Int,
        progress: @escaping @MainActor (NativeTurnProgress) -> Void
    ) async throws -> NativeGeneratedTurn
    func generateSuggestedActions(for state: NativeCampaignState) async throws -> [NativeSuggestedAction]
    func generateAdvisorBrief(for state: NativeCampaignState, question: String) async throws -> String
    func generateDiplomaticReply(for state: NativeCampaignState, thread: NativeDiplomaticThread, message: String) async throws -> String
}

extension NativeAIService {
    func generateTurn(
        for state: NativeCampaignState,
        months: Int,
        progress: @escaping @MainActor (NativeTurnProgress) -> Void
    ) async throws -> NativeGeneratedTurn {
        let total = NativeStrategyContextDatabase.estimatedLaneCount(for: state)
        progress(NativeTurnProgress(
            completedLanes: 0,
            detail: "Calling selected AI provider.",
            phase: "Consulting AI provider",
            totalLanes: total
        ))
        let generated = try await generateTurn(for: state, months: months)
        progress(NativeTurnProgress(
            completedLanes: max(0, total - 1),
            detail: "Turn generation completed; preparing validation.",
            phase: "Synthesizing turn",
            totalLanes: total
        ))
        return generated
    }
}

/// Native Apple Foundation Models implementation.
///
/// This service owns prompt construction, schema-oriented generation, repair
/// attempts, and text sanitization. It does not own campaign mutation; accepted
/// turns still have to pass through `NativeGameEngine.validated` and `apply`.
@MainActor
final class NativeFoundationModelService: NativeAIService {
    let promptCharacterLimit = NativePromptHarness.foundationCharacterLimit
    let logger = Logger(subsystem: "com.gibavargas.SwiftHistoria", category: "NativeFoundationModelService")

    func checkReadiness() async -> NativeAIReadiness {
        do {
            let tokenBudget = try await runReadinessProbe()
            logger.info("Apple Foundation Models readiness available")
            return .available(tokenBudget: tokenBudget)
        } catch NativeFoundationModelError.unsupportedOS {
            logger.error("Apple Foundation Models unsupported OS")
            return .unavailable("unsupported-os")
        } catch let NativeFoundationModelError.modelUnavailable(reason) {
            logger.error("Apple Foundation Models unavailable reason=\(reason, privacy: .public)")
            return .modelUnavailable(reason)
        } catch {
            logger.error("Apple Foundation Models readiness failed")
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
        #if canImport(FoundationModels)
            if #available(iOS 26.0, macOS 26.0, *) {
                logger.info("Apple Foundation turn generation started round=\(state.round, privacy: .public) months=\(months, privacy: .public)")
                let rawTurn = try await generateSlicedTurn(for: state, months: months, progress: progress)
                do {
                    let validated = try NativeGameEngine.validated(rawTurn, state: state, months: months)
                    logger.info("Apple Foundation turn generation validated events=\(validated.events.count, privacy: .public)")
                    return validated
                } catch {
                    logger.error("Apple Foundation turn validation failed; retrying with repair instruction")
                    let retryTurn = try await generateSlicedTurn(
                        for: state,
                        months: months,
                        repairInstruction: error.localizedDescription,
                        progress: progress
                    )
                    do {
                        let validated = try NativeGameEngine.validated(retryTurn, state: state, months: months)
                        logger.info("Apple Foundation repaired turn validated events=\(validated.events.count, privacy: .public)")
                        return validated
                    } catch {
                        logger.error("Apple Foundation repaired turn remained invalid")
                        throw NativeFoundationModelError.invalidGeneratedTurn(error.localizedDescription)
                    }
                }
            }
        #endif

        throw NativeFoundationModelError.unsupportedOS
    }

    func generateSuggestedActions(for state: NativeCampaignState) async throws -> [NativeSuggestedAction] {
        #if canImport(FoundationModels)
            if #available(iOS 26.0, macOS 26.0, *) {
                logger.info("Apple Foundation suggestions started round=\(state.round, privacy: .public)")
                let suggestions = try await generateStructuredSuggestions(for: state)
                let validSuggestions = suggestions.filter { suggestion in
                    isValidNativeSuggestion(suggestion)
                }
                guard validSuggestions.count >= 3 else {
                    logger.error("Apple Foundation suggestions invalid count=\(validSuggestions.count, privacy: .public)")
                    throw NativeFoundationModelError.invalidSuggestedActions("Expected at least three concrete suggestions from Apple Foundation Models.")
                }
                logger.info("Apple Foundation suggestions validated count=\(validSuggestions.count, privacy: .public)")
                return Array(validSuggestions.prefix(4))
            }
        #endif

        throw NativeFoundationModelError.unsupportedOS
    }

    func generateAdvisorBrief(for state: NativeCampaignState, question: String) async throws -> String {
        let safeQuestion = sanitizeFoundationModelText(question)
        guard hasConcreteFoundationText(safeQuestion, minimumWords: 2) else {
            throw NativeFoundationModelError.generationFailed("Advisor question was empty or placeholder-like.")
        }

        #if canImport(FoundationModels)
            if #available(iOS 26.0, macOS 26.0, *) {
                logger.info("Apple Foundation advisor generation started round=\(state.round, privacy: .public)")
                let answer = try await generateTextResponse(
                    prompt: makeAdvisorPrompt(for: state, question: safeQuestion),
                    maxTokens: 520,
                    repairNote: "Answer as a blunt strategic advisor in no more than three short paragraphs."
                )
                logger.info("Apple Foundation advisor generation completed")
                return answer
            }
        #endif

        throw NativeFoundationModelError.unsupportedOS
    }

    func generateDiplomaticReply(
        for state: NativeCampaignState,
        thread: NativeDiplomaticThread,
        message: String
    ) async throws -> String {
        let safeMessage = sanitizeFoundationModelText(message)
        guard !safeMessage.isEmpty else {
            throw NativeFoundationModelError.generationFailed("Diplomatic message was empty.")
        }

        #if canImport(FoundationModels)
            if #available(iOS 26.0, macOS 26.0, *) {
                logger.info("Apple Foundation diplomacy generation started round=\(state.round, privacy: .public)")
                let reply = try await generateTextResponse(
                    prompt: makeDiplomacyPrompt(for: state, thread: thread, message: safeMessage),
                    maxTokens: 180,
                    repairNote: "Reply in-character as the other polity with one or two concrete sentences."
                )
                logger.info("Apple Foundation diplomacy generation completed partner=\(thread.participant.code, privacy: .public)")
                return reply
            }
        #endif

        throw NativeFoundationModelError.unsupportedOS
    }

    private var nativeSystemPrompt: String {
        NativePromptHarness.sharedSystemPrompt
    }

    // **Foundation Model Prompt Handling Mechanic**:
    // Clamps prompt text to ensure it stays within the local on-device Foundation Model context window.
    // Over-long prompts cause catastrophic context loss.

    // **Prompt Constraints (Hex Lever) Mechanic**:
    // Explicitly instructs the local AI how to format Hex Levers.
    // The strict "6-or-8-nibble contract" is necessary because small, on-device models
    // often hallucinate formatting or invent non-existent hex rules if not given
    // very rigid and explicit prompt boundaries.

    private func runReadinessProbe() async throws -> String {
        #if canImport(FoundationModels)
            if #available(iOS 26.0, macOS 26.0, *) {
                let model = SystemLanguageModel.default
                guard model.isAvailable else {
                    throw NativeFoundationModelError.modelUnavailable(String(describing: model.availability))
                }

                do {
                    let session = LanguageModelSession(
                        model: model,
                        instructions: "You are a one-word readiness probe for SwiftHistoria."
                    )
                    let response = try await session.respond(
                        to: "Reply with a short readiness word.",
                        options: GenerationOptions(
                            sampling: .greedy,
                            temperature: 0,
                            maximumResponseTokens: 8
                        )
                    )
                    guard !response.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        throw NativeFoundationModelError.generationFailed("Readiness probe returned empty output.")
                    }
                    return "guided-generation context=4096, readiness=maxResponse=8"
                } catch let error as NativeFoundationModelError {
                    throw error
                } catch {
                    throw NativeFoundationModelError.generationFailed(error.localizedDescription)
                }
            }
        #endif

        throw NativeFoundationModelError.unsupportedOS
    }
}

#if canImport(FoundationModels)
    @available(iOS 26.0, macOS 26.0, *)
    extension NativeFoundationModelService {
        private enum LaneResult {
            case independent(AppleNativeGeneratedEventDraft)
            case economic(AppleNativeGeneratedEventDraft)
            case domestic(AppleNativeGeneratedEventDraft)
            case globalAI(AppleNativeGeneratedEventDraft)
            case action(NativePlannedAction, AppleNativeGeneratedEventDraft)
        }

        private func generateSlicedTurn(
            for state: NativeCampaignState,
            months: Int,
            repairInstruction: String? = nil,
            progress: @escaping @MainActor (NativeTurnProgress) -> Void
        ) async throws -> NativeGeneratedTurn {
            let model = SystemLanguageModel.default
            guard model.isAvailable else {
                logger.error("Apple Foundation sliced turn unavailable")
                throw NativeFoundationModelError.modelUnavailable(String(describing: model.availability))
            }

            let plannedActions = Array(state.plannedActions
                .filter { $0.status == .planned }
                .prefix(3))
            let totalLanes = NativeStrategyContextDatabase.estimatedLaneCount(for: state)
            var completedLanes = 0
            progress(NativeTurnProgress(
                completedLanes: completedLanes,
                detail: "Calling Apple on-device System Language Model lanes in parallel.",
                phase: "Consulting Apple Foundation",
                totalLanes: totalLanes,
                providerName: "Apple Foundation Models",
                modelName: "System Language Model",
                modelIdentifier: "SystemLanguageModel.default"
            ))

            var independentDraft: AppleNativeGeneratedEventDraft?
            var economicDraft: AppleNativeGeneratedEventDraft?
            var domesticDraft: AppleNativeGeneratedEventDraft?
            var globalAIDraft: AppleNativeGeneratedEventDraft?
            var actionDrafts: [String: AppleNativeGeneratedEventDraft] = [:]

            try await withThrowingTaskGroup(of: LaneResult.self) { group in
                group.addTask {
                    let draft = try await self.generateEventDraft(
                        model: model,
                        prompt: self.makeIndependentEventPrompt(for: state, months: months, repairInstruction: repairInstruction),
                        state: state
                    )
                    return .independent(draft)
                }
                group.addTask {
                    let draft = try await self.generateEventDraft(
                        model: model,
                        prompt: self.makeEconomicEventPrompt(for: state, months: months, repairInstruction: repairInstruction),
                        state: state
                    )
                    return .economic(draft)
                }
                group.addTask {
                    let draft = try await self.generateEventDraft(
                        model: model,
                        prompt: self.makeDomesticEventPrompt(for: state, months: months, repairInstruction: repairInstruction),
                        state: state
                    )
                    return .domestic(draft)
                }
                group.addTask {
                    let draft = try await self.generateEventDraft(
                        model: model,
                        prompt: self.makeGlobalAIActionsPrompt(for: state, months: months, repairInstruction: repairInstruction),
                        state: state
                    )
                    return .globalAI(draft)
                }
                for action in plannedActions {
                    group.addTask {
                        let draft = try await self.generateEventDraft(
                            model: model,
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
                        providerName: "Apple Foundation Models",
                        modelName: "System Language Model",
                        modelIdentifier: "SystemLanguageModel.default"
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
                providerName: "Apple Foundation Models",
                modelName: "System Language Model",
                modelIdentifier: "SystemLanguageModel.default"
            ))

            let summary = try await generateTurnSummary(model: model, state: state, months: months, events: events)
            progress(NativeTurnProgress(
                completedLanes: totalLanes,
                detail: "Apple Foundation turn synthesis completed.",
                phase: NativeFoundationTurnLane.summary.title,
                totalLanes: totalLanes,
                providerName: "Apple Foundation Models",
                modelName: "System Language Model",
                modelIdentifier: "SystemLanguageModel.default"
            ))
            logger.info("Apple Foundation sliced turn assembled events=\(events.count, privacy: .public)")

            return NativeGeneratedTurn(
                events: events,
                stabilityDelta: summary.stabilityDelta,
                summary: sanitizeFoundationModelText(summary.summary),
                worldTensionDelta: summary.globalFrictionDelta
            )
        }

        private func generateEventDraft(
            model: SystemLanguageModel,
            prompt: String,
            state: NativeCampaignState
        ) async throws -> AppleNativeGeneratedEventDraft {
            var repairNotes: [String] = []
            for attempt in 1 ... 3 {
                do {
                    logger.info("Apple Foundation event draft attempt=\(attempt, privacy: .public)")
                    let draft: AppleNativeGeneratedEventDraft = try await generateStructuredJSON(
                        model: model,
                        prompt: eventPrompt(prompt, state: state, repairNotes: repairNotes),
                        schema: AppleNativeGeneratedEventDraft.schemaInstructions,
                        maximumResponseTokens: 260,
                        temperature: attempt == 1 ? 0.0 : 0.18
                    )
                    if draft.hasConcreteContent {
                        return draft
                    }
                    logger.error("Apple Foundation event draft used non-concrete content attempt=\(attempt, privacy: .public) \(draft.validationDiagnostics, privacy: .public)")
                    repairNotes.append("Previous event used placeholder or draft text. Produce a concrete title, description, target, and effect summary.")
                } catch {
                    if attempt == 3 {
                        logger.error("Apple Foundation event draft failed after retries")
                        throw NativeFoundationModelError.generationFailed(error.localizedDescription)
                    }
                    logger.error("Apple Foundation event draft attempt failed attempt=\(attempt, privacy: .public)")
                    repairNotes.append("Previous event generation failed. Try a simpler civic-planning event with one concrete agency and one measurable game effect.")
                }
            }

            throw NativeFoundationModelError.generationFailed("Apple Foundation Models returned placeholder event content after three event-slice attempts.")
        }

        private func eventPrompt(_ basePrompt: String, state: NativeCampaignState, repairNotes: [String]) -> String {
            let repairBlock = repairNotes.isEmpty ? "" : """

            Event repair notes:
            \(repairNotes.map { "- \($0)" }.joined(separator: "\n"))
            """

            let recentTitles = state.timeline
                .prefix(4)
                .map { sanitizeFoundationModelText($0.title) }
                .filter { !$0.isEmpty }

            let deduplicationLine = recentTitles.isEmpty ? "" : "\nDo not reuse these themes: \(recentTitles.joined(separator: "; "))."

            return clampedFoundationPrompt("""
            \(basePrompt)

            Return one strict JSON object only. Do not include markdown fences, prose, schema labels, or comments.
            \(repairBlock)\(deduplicationLine)
            Banned title words: Apple, Native, Generated, Draft, Placeholder, Schema.
            Use a concrete title like Transit Funding Review, Grid Capacity Program, or School Access Plan.
            """)
        }

        private func generateTurnSummary(
            model: SystemLanguageModel,
            state: NativeCampaignState,
            months: Int,
            events: [NativeCampaignEvent]
        ) async throws -> AppleNativeTurnSummary {
            let basePrompt = makeSummaryPrompt(for: state, months: months, events: events)
            var repairNotes: [String] = []

            for attempt in 1 ... 2 {
                do {
                    logger.info("Apple Foundation turn summary attempt=\(attempt, privacy: .public)")
                    let summary: AppleNativeTurnSummary = try await generateStructuredJSON(
                        model: model,
                        prompt: summaryPrompt(basePrompt, repairNotes: repairNotes),
                        schema: AppleNativeTurnSummary.schemaInstructions,
                        maximumResponseTokens: 160,
                        temperature: attempt == 1 ? 0.0 : 0.18
                    )
                    if summary.hasConcreteContent {
                        return summary
                    }
                    logger.error("Apple Foundation turn summary used non-concrete content attempt=\(attempt, privacy: .public)")
                    repairNotes.append("Previous summary was empty, repetitive, or placeholder-like. Write one concrete board-game planning sentence.")
                } catch {
                    if attempt == 2 {
                        logger.error("Apple Foundation turn summary failed after repair")
                        throw NativeFoundationModelError.generationFailed(error.localizedDescription)
                    }
                    logger.error("Apple Foundation turn summary attempt failed attempt=\(attempt, privacy: .public)")
                    repairNotes.append("Previous summary generation failed. Write a shorter neutral period summary.")
                }
            }

            throw NativeFoundationModelError.generationFailed("Apple Foundation Models returned an invalid turn summary after repair.")
        }

        private func summaryPrompt(_ basePrompt: String, repairNotes: [String]) -> String {
            let repairBlock = repairNotes.isEmpty ? "" : """

            Summary repair notes:
            \(repairNotes.map { "- \($0)" }.joined(separator: "\n"))
            """

            return clampedFoundationPrompt("""
            \(basePrompt)

            Return one strict JSON object only. Do not include markdown fences, prose, schema labels, or comments.
            \(repairBlock)
            Do not return field names, schema labels, placeholders, or repeated sentences.
            """)
        }

        private func generateStructuredSuggestions(for state: NativeCampaignState) async throws -> [NativeSuggestedAction] {
            let model = SystemLanguageModel.default
            guard model.isAvailable else {
                logger.error("Apple Foundation suggestions unavailable")
                throw NativeFoundationModelError.modelUnavailable(String(describing: model.availability))
            }

            let focusAreas = [
                "fiscal ledger, budget balance, debt, and market confidence",
                "public security, insurgency pressure, and stabilization capacity",
                "map conflict, border pressure, regional logistics, and service corridors",
                "diplomacy, trade balance, global friction, and regional relations",
                "infrastructure, energy, climate resilience, and unemployment",
                "education, service access, administrative capacity, and action memory"
            ]

            var suggestions: [NativeSuggestedAction] = []
            var suggestionFailures: [String] = []
            for (index, focus) in focusAreas.enumerated() {
                let basePrompt = makeSuggestionPrompt(for: state, focus: focus, index: index + 1)
                var repairNotes: [String] = []
                var acceptedSuggestion: NativeSuggestedAction?

                for attempt in 1 ... 2 {
                    do {
                        logger.info("Apple Foundation suggestion attempt focus=\(index + 1, privacy: .public) attempt=\(attempt, privacy: .public)")
                        let suggestion: AppleNativeSuggestedAction = try await generateStructuredJSON(
                            model: model,
                            prompt: suggestionPrompt(basePrompt, repairNotes: repairNotes),
                            schema: AppleNativeSuggestedAction.schemaInstructions,
                            maximumResponseTokens: 360,
                            temperature: attempt == 1 ? 0.0 : 0.18,
                            useGuidedGeneration: false
                        )

                        if suggestion.hasConcreteContent {
                            acceptedSuggestion = suggestion.toNativeSuggestion(state: state, index: index)
                            break
                        }
                        logger.error("Apple Foundation suggestion was not concrete focus=\(index + 1, privacy: .public)")
                        repairNotes.append("Previous proposal was too vague, used placeholder text, or contradicted current metrics. Produce a concrete neutral proposal.")
                    } catch let error as NativeFoundationModelError {
                        logger.error("Apple Foundation suggestion fatal error focus=\(index + 1, privacy: .public)")
                        throw error
                    } catch {
                        if attempt == 2 {
                            logger.error("Apple Foundation suggestion failed after repair focus=\(index + 1, privacy: .public)")
                            suggestionFailures.append("focus \(index + 1): \(sanitizeFoundationModelText(error.localizedDescription))")
                            break
                        }
                        logger.error("Apple Foundation suggestion attempt failed focus=\(index + 1, privacy: .public) attempt=\(attempt, privacy: .public)")
                        repairNotes.append("Previous proposal generation failed. Try a shorter neutral civic-planning proposal.")
                    }
                }

                if let acceptedSuggestion, isValidNativeSuggestion(acceptedSuggestion) {
                    suggestions.append(acceptedSuggestion)
                } else {
                    suggestionFailures.append("focus \(index + 1): invalid or empty suggestion")
                }

                if suggestions.count == 4 {
                    return suggestions
                }
            }

            guard suggestions.count >= 3 else {
                let detail = suggestionFailures.prefix(3).joined(separator: "; ")
                throw NativeFoundationModelError.invalidSuggestedActions(
                    "Expected at least three concrete suggestions from Apple Foundation Models. \(detail)"
                )
            }

            return suggestions
        }

        private func suggestionPrompt(_ basePrompt: String, repairNotes: [String]) -> String {
            let repairBlock = repairNotes.isEmpty ? "" : """

            Suggestion repair notes:
            \(repairNotes.map { "- \($0)" }.joined(separator: "\n"))
            """

            return clampedFoundationPrompt("""
            \(basePrompt)

            Return one strict JSON object only. Do not include markdown fences, prose, schema labels, or comments.
            \(repairBlock)
            Banned title words: Apple, Native, Generated, Draft, Placeholder, Schema.
            """)
        }

        private func generateStructuredJSON<T: Decodable & Generable>(
            model: SystemLanguageModel,
            prompt: String,
            schema: String,
            maximumResponseTokens: Int,
            temperature: Double,
            useGuidedGeneration: Bool = true
        ) async throws -> T {
            let guidedPrompt = clampedFoundationPrompt(prompt)
            let fallbackPrompt = clampedFoundationPrompt("""
            \(prompt)

            Required JSON schema:
            \(schema)
            """)

            if useGuidedGeneration {
                do {
                    let session = LanguageModelSession(model: model, instructions: nativeSystemPrompt)
                    logger.info("Apple Foundation guided structure generation started type=\(String(describing: T.self), privacy: .public)")
                    let response = try await session.respond(
                        to: guidedPrompt,
                        generating: T.self,
                        includeSchemaInPrompt: true,
                        options: GenerationOptions(
                            sampling: .greedy,
                            temperature: temperature,
                            maximumResponseTokens: maximumResponseTokens
                        )
                    )
                    logger.info("Apple Foundation guided structure generation completed type=\(String(describing: T.self), privacy: .public)")
                    return response.content
                } catch {
                    logger.error("Apple Foundation guided structure generation failed; retrying text JSON fallback type=\(String(describing: T.self), privacy: .public) error=\(error.localizedDescription, privacy: .public)")
                }
            }

            let session = LanguageModelSession(model: model, instructions: nativeSystemPrompt)
            let response = try await session.respond(
                to: fallbackPrompt,
                options: GenerationOptions(
                    sampling: .greedy,
                    temperature: temperature,
                    maximumResponseTokens: maximumResponseTokens
                )
            )
            return try decodeFoundationJSON(response.content, as: T.self)
        }

        private func decodeFoundationJSON<T: Decodable>(_ rawText: String, as type: T.Type) throws -> T {
            let decoder = JSONDecoder()
            for candidate in foundationJSONCandidates(from: rawText) {
                guard let data = candidate.data(using: .utf8) else { continue }
                if let decoded = try? decoder.decode(type, from: data) {
                    return decoded
                }
            }

            throw NativeFoundationModelError.generationFailed("Apple Foundation Models returned invalid strict JSON.")
        }

        private func foundationJSONCandidates(from rawText: String) -> [String] {
            NativeJSONExtraction.candidates(from: rawText)
        }

        private func generateTextResponse(
            prompt: String,
            maxTokens: Int,
            repairNote: String
        ) async throws -> String {
            let model = SystemLanguageModel.default
            guard model.isAvailable else {
                logger.error("Apple Foundation text generation unavailable")
                throw NativeFoundationModelError.modelUnavailable(String(describing: model.availability))
            }

            var repairNotes: [String] = []
            for attempt in 1 ... 2 {
                do {
                    logger.info("Apple Foundation text generation attempt=\(attempt, privacy: .public)")
                    let session = LanguageModelSession(model: model, instructions: nativeSystemPrompt)
                    let response = try await session.respond(
                        to: textPrompt(prompt, repairNotes: repairNotes),
                        options: GenerationOptions(
                            sampling: .greedy,
                            temperature: attempt == 1 ? 0.05 : 0.20,
                            maximumResponseTokens: maxTokens
                        )
                    )
                    let text = sanitizeFoundationModelText(response.content)
                    if hasConcreteFoundationText(text, minimumWords: 6) {
                        return text
                    }
                    logger.error("Apple Foundation text generation returned non-concrete content attempt=\(attempt, privacy: .public)")
                    repairNotes.append(repairNote)
                } catch {
                    if attempt == 2 {
                        logger.error("Apple Foundation text generation failed after repair")
                        throw NativeFoundationModelError.generationFailed(error.localizedDescription)
                    }
                    logger.error("Apple Foundation text generation attempt failed attempt=\(attempt, privacy: .public)")
                    repairNotes.append(repairNote)
                }
            }

            throw NativeFoundationModelError.generationFailed("Apple Foundation Models returned empty or placeholder text after repair.")
        }

        private func textPrompt(_ basePrompt: String, repairNotes: [String]) -> String {
            guard !repairNotes.isEmpty else { return basePrompt }
            return clampedFoundationPrompt("""
            \(basePrompt)

            Text repair notes:
            \(repairNotes.map { "- \($0)" }.joined(separator: "\n"))
            Do not return placeholder text, schema labels, unsafe operational instructions, or repeated sentences.
            """)
        }
    }

    @available(iOS 26.0, macOS 26.0, *)
    @Generable(description: "A single concrete SwiftHistoria event draft with one safe strategic effect.")
    private struct AppleNativeGeneratedEventDraft: Decodable {
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
        var sovereigntyKind: String?
        var sovereigntyName: String?
        var sovereigntyRegionIDs: String?
        var sovereigntySourceCodes: String?
        var sovereigntyTargetCode: String?

        static let schemaInstructions = """
        {
          "title": "Specific civic-planning event title with generic fictional agencies. Never use a schema type name or placeholder title.",
          "description": "Concrete high-level description with generic agencies, sectors, and game consequences. No placeholder or draft text.",
          "kind": "action, economy, or world",
          "importance": "minor or major",
          "notable": true,
          "effectTarget": "Target region, agency, sector, or external system",
          "effectTrack": "economic-resilience, internal-stability, or market-confidence",
          "effectMagnitude": 0,
          "effectSummary": "One concrete sentence explaining the mechanical consequence. No placeholder or draft text.",
          "hexLeverCode": "Optional 6-or-8-character hexadecimal lever code starting with 0x. Six nibbles represent Growth, Budget, Debt, Inflation, Trade, and Fiscal Space; optional seventh and eighth nibbles represent public-security delta and abstract map-control nudge.",
          "sovereigntyKind": "secession, new-country, merge, dissolution, or empty",
          "sovereigntyTargetCode": "3-6 uppercase letters or empty",
          "sovereigntyName": "Country or breakaway polity name or empty",
          "sovereigntySourceCodes": "Comma-separated existing country codes or empty",
          "sovereigntyRegionIDs": "Comma-separated map region IDs or empty"
        }
        """

        private enum CodingKeys: String, CodingKey {
            case title
            case description
            case kind
            case importance
            case notable
            case effectTarget
            case effectTrack
            case effectMagnitude
            case effectSummary
            case hexLeverCode
            case sovereigntyKind
            case sovereigntyName
            case sovereigntyRegionIDs
            case sovereigntySourceCodes
            case sovereigntyTargetCode
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
            description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
            kind = try container.decodeIfPresent(String.self, forKey: .kind) ?? ""
            importance = try container.decodeIfPresent(String.self, forKey: .importance) ?? ""
            notable = try container.decodeIfPresent(Bool.self, forKey: .notable) ?? false
            effectTarget = try container.decodeIfPresent(String.self, forKey: .effectTarget) ?? ""
            effectTrack = try container.decodeIfPresent(String.self, forKey: .effectTrack) ?? ""
            effectMagnitude = try container.decodeIfPresent(Int.self, forKey: .effectMagnitude) ?? 0
            effectSummary = try container.decodeIfPresent(String.self, forKey: .effectSummary) ?? ""
            hexLeverCode = try container.decodeIfPresent(String.self, forKey: .hexLeverCode)
            sovereigntyKind = try container.decodeIfPresent(String.self, forKey: .sovereigntyKind)
            sovereigntyName = try container.decodeIfPresent(String.self, forKey: .sovereigntyName)
            sovereigntyRegionIDs = try container.decodeIfPresent(String.self, forKey: .sovereigntyRegionIDs)
            sovereigntySourceCodes = try container.decodeIfPresent(String.self, forKey: .sovereigntySourceCodes)
            sovereigntyTargetCode = try container.decodeIfPresent(String.self, forKey: .sovereigntyTargetCode)
        }

        var hasConcreteContent: Bool {
            hasConcreteFoundationText(title, minimumWords: 2) &&
                hasConcreteFoundationText(description, minimumWords: 8) &&
                hasConcreteFoundationText(effectSummary, minimumWords: 5) &&
                !containsFoundationPlaceholderText(effectTarget)
        }

        var validationDiagnostics: String {
            "titleConcrete=\(hasConcreteFoundationText(title, minimumWords: 2)) descriptionConcrete=\(hasConcreteFoundationText(description, minimumWords: 8)) effectConcrete=\(hasConcreteFoundationText(effectSummary, minimumWords: 5)) targetConcrete=\(!containsFoundationPlaceholderText(effectTarget))"
        }

        func toNativeEvent(
            state: NativeCampaignState,
            months: Int,
            index: Int,
            linkedActionID: String?,
            playerRelated: Bool
        ) -> NativeCampaignEvent {
            let eventDate = NativeGameEngine.advance(date: state.gameDate, months: months)
            let eventID = "ai-event-\(state.round)-\(index)"
            let target = effectTarget.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || containsFoundationPlaceholderText(effectTarget)
                ? (playerRelated ? state.country.name : "International system")
                : effectTarget
            let generatedKind = NativeEventKind(rawValue: kind) ?? (playerRelated ? .action : .world)
            let safeKind: NativeEventKind = generatedKind == .crisis ? (playerRelated ? .action : .world) : generatedKind
            let safeTrack = appleDraftStrategicTrack(from: effectTrack, playerRelated: playerRelated)
            let safeDescription = hasConcreteFoundationText(description, minimumWords: 8)
                ? sanitizeFoundationModelText(description)
                : fallbackDraftDescription(title: title, state: state, playerRelated: playerRelated)
            let safeEffectSummary = hasConcreteFoundationText(effectSummary, minimumWords: 5)
                ? sanitizeFoundationModelText(effectSummary)
                : fallbackDraftEffectSummary(track: safeTrack, playerRelated: playerRelated)

            return NativeCampaignEvent(
                date: eventDate,
                description: safeDescription,
                id: eventID,
                importance: NativeEventImportance(rawValue: importance) ?? .major,
                kind: safeKind,
                linkedActionIDs: linkedActionID.map { [$0] } ?? [],
                notable: notable,
                playerRelated: playerRelated,
                strategicEffects: [
                    NativeStrategicEffect(
                        date: eventDate,
                        eventId: eventID,
                        id: "\(eventID)-effect",
                        magnitude: Swift.max(-5, Swift.min(5, effectMagnitude)),
                        summary: safeEffectSummary,
                        target: sanitizeFoundationModelText(target),
                        track: safeTrack
                    )
                ],
                title: sanitizeFoundationModelText(title),
                hexLeverCode: hexLeverCode,
                sovereigntyChange: appleSovereigntyChange(
                    kind: sovereigntyKind,
                    name: sovereigntyName,
                    regionIDs: sovereigntyRegionIDs,
                    sourceCodes: sovereigntySourceCodes,
                    targetCode: sovereigntyTargetCode
                )
            )
        }
    }

    private func appleSovereigntyChange(
        kind: String?,
        name: String?,
        regionIDs: String?,
        sourceCodes: String?,
        targetCode: String?
    ) -> NativeSovereigntyChange? {
        let cleanKind = sanitizeFoundationModelText(kind ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsedKind = NativeSovereigntyChangeKind(rawValue: cleanKind), !cleanKind.isEmpty else { return nil }
        return NativeSovereigntyChange(
            kind: parsedKind,
            name: sanitizeFoundationModelText(name ?? ""),
            regionIDs: commaList(regionIDs),
            sourceCodes: commaList(sourceCodes),
            targetCode: sanitizeFoundationModelText(targetCode ?? "")
        )
    }

    private func commaList(_ value: String?) -> [String] {
        (value ?? "")
            .split(separator: ",")
            .map { sanitizeFoundationModelText(String($0)) }
            .filter { !$0.isEmpty }
    }

    private func appleDraftStrategicTrack(from rawValue: String, playerRelated: Bool) -> NativeStrategicTrack {
        let normalized = sanitizeFoundationModelText(rawValue)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if let track = NativeStrategicTrack(rawValue: normalized) {
            return foundationVisibleTrack(track)
        }
        if normalized.contains("stability") || normalized.contains("service") || normalized.contains("administr") {
            return .internalStability
        }
        if normalized.contains("resilience") || normalized.contains("capacity") || normalized.contains("infrastructure") || normalized.contains("energy") {
            return .economicResilience
        }
        if normalized.contains("relation") || normalized.contains("diplom") || normalized.contains("partner") {
            return .diplomaticLeverage
        }
        if normalized.contains("friction") || normalized.contains("tension") || normalized.contains("external") {
            return .worldTension
        }
        if normalized.contains("market") || normalized.contains("trade") || normalized.contains("confidence") || normalized.contains("logistics") {
            return .marketConfidence
        }
        return playerRelated ? .economicResilience : .marketConfidence
    }

    private func appleDraftRawTrackIsUnsafe(_: String) -> Bool {
        false
    }

    private func fallbackDraftDescription(title: String, state: NativeCampaignState, playerRelated: Bool) -> String {
        let safeTitle = sanitizeFoundationModelText(title)
        if playerRelated {
            return "\(state.country.name) agencies convert \(safeTitle) into a staged civic delivery program with budget milestones, service corridors, and public accountability checkpoints."
        }
        return "External planning councils advance \(safeTitle) across trade, logistics, and service capacity forums, shifting expectations for the next game period."
    }

    private func fallbackDraftEffectSummary(track: NativeStrategicTrack, playerRelated: Bool) -> String {
        let label = foundationPromptTrackLabel(track)
        if playerRelated {
            return "Concrete delivery milestones improve \(label) for the selected region."
        }
        return "External coordination shifts \(label) across the wider planning system."
    }

    @available(iOS 26.0, macOS 26.0, *)
    @Generable(description: "A concise SwiftHistoria turn summary and aggregate metric deltas.")
    private struct AppleNativeTurnSummary: Decodable {
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

        private enum CodingKeys: String, CodingKey {
            case summary
            case stabilityDelta
            case globalFrictionDelta
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            summary = try container.decodeIfPresent(String.self, forKey: .summary) ?? ""
            stabilityDelta = try container.decodeIfPresent(Int.self, forKey: .stabilityDelta) ?? 0
            globalFrictionDelta = try container.decodeIfPresent(Int.self, forKey: .globalFrictionDelta) ?? 0
        }

        var hasConcreteContent: Bool {
            hasConcreteFoundationText(summary, minimumWords: 6)
        }
    }

    @available(iOS 26.0, macOS 26.0, *)
    @Generable(description: "A concrete civic proposal suggestion for the next SwiftHistoria turn.")
    private struct AppleNativeSuggestedAction: Decodable {
        var title: String
        var detail: String
        var rationale: String
        var urgency: String

        static let schemaInstructions = """
        {
          "title": "Short imperative title for the civic proposal.",
          "detail": "Accept-ready board-game order with bounded instrument, generic agency or sector, timing, primary mechanic, secondary mechanic, capacity fit, and intended game effect.",
          "rationale": "Why this civic proposal fits the current campaign state and objectives, explicitly naming the primary affected mechanic and one connected secondary mechanic.",
          "urgency": "immediate, soon, or opportunistic"
        }
        """

        private enum CodingKeys: String, CodingKey {
            case title
            case detail
            case rationale
            case urgency
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
            detail = try container.decodeIfPresent(String.self, forKey: .detail) ?? ""
            rationale = try container.decodeIfPresent(String.self, forKey: .rationale) ?? ""
            urgency = try container.decodeIfPresent(String.self, forKey: .urgency) ?? ""
        }

        var hasConcreteContent: Bool {
            hasConcreteFoundationText(title, minimumWords: 2) &&
                hasConcreteFoundationText(detail, minimumWords: 8) &&
                hasConcreteFoundationText(rationale, minimumWords: 8)
        }

        func toNativeSuggestion(state: NativeCampaignState, index: Int) -> NativeSuggestedAction {
            NativeSuggestedAction(
                detail: sanitizeFoundationModelText(detail),
                id: "suggestion-\(state.country.code.lowercased())-\(state.round)-\(index)",
                rationale: sanitizeFoundationModelText(rationale),
                title: sanitizeFoundationModelText(title),
                urgency: normalizedFoundationUrgency(urgency)
            )
        }
    }

#endif
