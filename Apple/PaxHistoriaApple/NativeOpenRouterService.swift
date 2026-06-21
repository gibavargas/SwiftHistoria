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
        ZAIModelLane(name: "openrouter/free", displayName: "Free Models Router", maxConcurrent: 5)
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

        let rawResponse = try await executeProviderRequest(
            prompt: prompt,
            maxTokens: 1400,
            temperature: 0.1,
            responseFormat: "json_object",
            thinkingEnabled: false
        )

        let decoder = JSONDecoder()
        for candidate in NativeJSONExtraction.candidates(from: rawResponse) {
            guard let data = candidate.data(using: .utf8),
                  let decoded = try? decoder.decode(OpenRouterSuggestionBatch.self, from: data)
            else {
                continue
            }
            let suggestions = decoded.suggestions
                .enumerated()
                .map { index, suggestion in suggestion.toNativeSuggestion(state: state, index: index) }
                .filter { isValidNativeSuggestion($0) }
            guard suggestions.count >= 3 else { continue }
            orLogger.info("OpenRouter batched suggestions validated count=\(suggestions.count, privacy: .public)")
            return Array(suggestions.prefix(4))
        }

        throw NativeFoundationModelError.invalidSuggestedActions("OpenRouter Free returned invalid suggested actions JSON.")
    }
}

private struct OpenRouterSuggestionBatch: Decodable {
    var suggestions: [OpenRouterSuggestedAction]
}

private struct OpenRouterSuggestedAction: Decodable {
    var title: String
    var detail: String
    var rationale: String
    var urgency: String

    func toNativeSuggestion(state: NativeCampaignState, index: Int) -> NativeSuggestedAction {
        NativeSuggestedAction(
            detail: sanitizeFoundationModelText(detail),
            id: "suggestion-\(state.country.code.lowercased())-\(state.round)-openrouter-\(index + 1)",
            rationale: sanitizeFoundationModelText(rationale),
            title: sanitizeFoundationModelText(title),
            urgency: normalizedFoundationUrgency(urgency)
        )
    }
}
