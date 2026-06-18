import Foundation
import OSLog

/// OpenRouter-based AI service using free models. Falls back before Z.AI.
///
/// Inherits ALL prompt construction, JSON decoding, validation, and retry logic
/// from `NativeZAIService` — only the endpoint, API key, model list, and thinking
/// field differ. OpenRouter uses the same OpenAI-compatible chat completions API.
@MainActor
final class NativeOpenRouterService: NativeZAIService {
    private let orLogger = Logger(subsystem: "com.gibavargas.SwiftHistoria", category: "NativeOpenRouterService")
    private var openRouterModelLanes: [ZAIModelLane] = [
        ZAIModelLane(name: "openrouter/free", displayName: "Free Models Router", maxConcurrent: 4)
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
        do {
            _ = try await executeZAIRequest(
                prompt: "Return exactly this JSON: {\"ok\":true}",
                maxTokens: 16,
                temperature: 0.0,
                responseFormat: "json_object",
                thinkingEnabled: false
            )
            return .available(tokenBudget: "OpenRouter free models verified")
        } catch {
            orLogger.error("OpenRouter readiness probe failed: \(error.localizedDescription, privacy: .public)")
            return .failure(error)
        }
    }
}
