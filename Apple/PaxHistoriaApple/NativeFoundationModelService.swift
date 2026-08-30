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
    The deterministic game engine owns legality, costs, dates, targets, sovereignty transitions, and state mutation. Never invent or silently override those fields.
    Distinguish observed stored facts from forecasts and recommendations. Advisor or diplomacy prose cannot itself change campaign state or finalize an agreement.
    Be specific: use real institutions and economic mechanisms only when supported by the campaign context; otherwise use plausible fictional civic agencies.
    Every event should read like a headline from a serious geopolitical intelligence briefing.
    Use concrete details: organizations, dates, economic indicators, and measurable game effects.
    Connect every answer to the current campaign mechanics instead of giving generic advice.
    Do not present post-start-date facts as already true unless they are stored in the campaign state.
    Follow the request's response-language instruction for all player-facing prose.
    Keep schema field names, enum values, identifiers, IDs, dates, and game tokens exactly as requested.
    \(NativeStrategicTrack.mechanicCodebookPrompt)
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
    case nvidia
    case openRouter

    static let storageKey = "NATIVE_AI_PROVIDER_PREFERENCE"

    static func migrateLegacyDefaultIfNeeded(defaults: UserDefaults = .standard) {
        let normalized = current(defaults: defaults)
        guard defaults.string(forKey: storageKey) != normalized.rawValue else { return }
        defaults.set(normalized.rawValue, forKey: storageKey)
    }

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .nvidia: "NVIDIA NIM"
        case .openRouter: "OpenRouter Free"
        }
    }

    var subtitle: String {
        switch self {
        case .nvidia:
            "Use MiniMax-M3, Kimi-K2.6, and DeepSeek-V4-Flash through the NVIDIA API. Requests never switch providers automatically."
        case .openRouter:
            "Use OpenRouter's unified Free Models Router directly. Requests never switch providers automatically."
        }
    }

    var providerName: String {
        switch self {
        case .nvidia: "NVIDIA NIM"
        case .openRouter: "OpenRouter Free"
        }
    }

    static func current(defaults: UserDefaults = .standard) -> NativeAIProviderPreference {
        if let raw = defaults.string(forKey: storageKey), let value = NativeAIProviderPreference(rawValue: raw) {
            return value
        }
        return .nvidia
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
    func generateRivalAgentTurns(for state: NativeCampaignState) async throws -> [NativeRivalAgentTurn]
}

extension NativeAIService {
    func generateRivalAgentTurns(for _: NativeCampaignState) async throws -> [NativeRivalAgentTurn] {
        []
    }

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

// The Apple Foundation Models service was retired when strict AI routing made
// the route unselectable. Its prompt builders live on in NativePromptHarness
// (+Prompts.swift); the routes below are the only selectable AI surfaces.
