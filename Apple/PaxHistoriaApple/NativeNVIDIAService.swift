import Foundation

/// NVIDIA-hosted inference using the OpenAI-compatible NIM API.
///
/// Uses a **single-call** architecture for both decision matrix and turn generation:
/// - **Call 1 (Player Setup/Action):** One call generates the complete 5×5 decision matrix (25 cells)
/// - **Call 2 (Advance Turn):** One call generates all events, consequences, and summary
///
/// This eliminates the multi-call approach (5 rows × 2 phases = 15 calls) that caused
/// rate limiting, timeouts, and coordination failures on the NVIDIA NIM free tier.
///
/// Prompt construction, decoding, validation, retry, and telemetry stay shared
/// with the other external providers through `NativeExternalAIService`.
@MainActor
class NativeNVIDIAService: NativeExternalAIService {
    static let modelIdentifier = "minimaxai/minimax-m3"

    private var nvidiaModelLanes: [ZAIModelLane] = [
        ZAIModelLane(
            name: "minimaxai/minimax-m3",
            displayName: "MiniMax-M3",
            maxConcurrent: 2
        ),
        ZAIModelLane(
            name: "moonshotai/kimi-k2.6",
            displayName: "Kimi-K2.6",
            maxConcurrent: 2
        ),
        ZAIModelLane(
            name: "deepseek-ai/deepseek-v4-flash",
            displayName: "DeepSeek-V4-Flash",
            maxConcurrent: 2
        )
    ]

    override var modelLanes: [ZAIModelLane] {
        get { nvidiaModelLanes }
        set { nvidiaModelLanes = newValue }
    }

    override var apiKey: String {
        NativeSecretStore.string(forKey: "NVIDIA_API_KEY", defaults: defaults) ?? ""
    }

    override var useCodingEndpoint: Bool {
        false
    }

    override var apiEndpoint: URL {
        URL(string: "https://integrate.api.nvidia.com/v1/chat/completions")!
    }

    override var includesThinkingField: Bool {
        false
    }

    override var includesMaxTokensField: Bool {
        true
    }

    override var rateLimiter: NativeRateLimiter {
        .nvidia
    }

    override var providerDisplayName: String {
        "NVIDIA NIM"
    }

    override var routeDisplayName: String {
        "NVIDIA Inference API"
    }

    // MARK: - Call 1: Single-Call Decision Matrix

    override func generateSuggestedActions(for state: NativeCampaignState) async throws -> [NativeSuggestedAction] {
        let prompt = NativeDecisionMatrixPrompt.make(for: state)
        let validCodes = NativeStrategyContextDatabase.strategicCountryCodes(for: state)
        var lastFailure = "No response was validated."
        var repairNote = ""

        for attempt in 1 ... 3 {
            let rawResponse = try await executeProviderRequest(
                prompt: prompt + repairNote,
                maxTokens: 8000,
                temperature: attempt == 1 ? 0.6 : (attempt == 2 ? 0.4 : 0.2),
                responseFormat: "json_object",
                thinkingEnabled: false,
                requestTimeout: 45,
                retryLimit: 0
            )

            var suggestions = OpenRouterSuggestionParser.suggestions(from: rawResponse, state: state)

            // Post-hoc repair: fix truncated country codes and invalid directives
            suggestions = suggestions.map { repairSuggestion($0, state: state, validCodes: validCodes) }

            // Fix matrixRow/matrixColumn assignments
            suggestions = fixMatrixCoordinates(suggestions)

            do {
                let matrix = try NativeDecisionMatrixContract.validatedPlayerMatrix(suggestions, state: state)
                logger.info("NVIDIA NIM decision matrix validated cells=\(matrix.count, privacy: .public) attempt=\(attempt, privacy: .public)")
                return matrix
            } catch {
                lastFailure = error.localizedDescription
                logger.warning("NVIDIA NIM decision matrix invalid count=\(suggestions.count, privacy: .public) attempt=\(attempt, privacy: .public): \(lastFailure, privacy: .public)")
                if let tailored = try? NativeDecisionMatrixContract.aiTailoredPlayerMatrix(from: suggestions, state: state) {
                    logger.info("NVIDIA NIM tailored the engine-owned legal matrix cells=\(tailored.count, privacy: .public)")
                    return tailored
                }

                repairNote = """

                REPAIR (attempt \(attempt + 1)): The previous board was rejected: \(lastFailure)
                Return a complete replacement object with exactly 25 eligible suggestions, every matrixRow/matrixColumn pair 0...4 exactly once.
                Do not return only repaired cells. Recheck each cost, target, political directive, region directive, and sovereignty precondition.
                """
            }
        }

        throw NativeFoundationModelError.invalidSuggestedActions(
            "NVIDIA NIM could not produce a valid 5×5 decision matrix after repair. \(lastFailure)"
        )
    }

    /// Repairs matrixRow/matrixColumn assignments by brute-force reassigning
    /// sequential row/column indices. Simpler and more reliable than trying to
    /// interpret whatever the model returned.
    private func fixMatrixCoordinates(_ suggestions: [NativeSuggestedAction]) -> [NativeSuggestedAction] {
        suggestions.enumerated().map { idx, suggestion -> NativeSuggestedAction in
            var sug = suggestion
            sug.matrixRow = idx / 5
            sug.matrixColumn = idx % 5
            return sug
        }
    }

    // MARK: - Post-hoc Repair

    /// Post-hoc repair for common model output errors.
    private func repairSuggestion(
        _ suggestion: NativeSuggestedAction,
        state: NativeCampaignState,
        validCodes: [String]
    ) -> NativeSuggestedAction {
        var repaired = suggestion

        // Fix truncated/invalid diplomacy target codes via fuzzy matching
        if suggestion.actionKind == "diplomacy",
           let target = suggestion.targetCountryCode,
           target != "GLOBAL",
           !validCodes.contains(target)
        {
            let fuzzy = NativeNVIDIAService.closestCountryCode(to: target, from: validCodes)
            repaired.targetCountryCode = fuzzy
        }

        // Fix diplomacy cells that have no targetCountryCode at all
        if suggestion.actionKind == "diplomacy",
           suggestion.targetCountryCode == nil || suggestion.targetCountryCode?.isEmpty == true
        {
            let adjacent = NativeStrategyContextDatabase.adjacentCountryCodes(for: state.country.code)
            repaired.targetCountryCode = adjacent.first(where: { validCodes.contains($0) }) ?? validCodes.first(where: { $0 != state.country.code })
        }

        // Fix political actionKind if not matching an allowed directive template
        if repaired.actionKind == "political" {
            let allowed = NativeQuickActionCatalog.politicalReformActions(state: state)
            let allowedDirectives = allowed.map(\.directiveTemplate)
            if !allowedDirectives.contains(repaired.detail) {
                if let closest = NativeNVIDIAService.closestStringMatch(to: repaired.detail, from: allowedDirectives) {
                    repaired.detail = closest
                } else {
                    repaired.actionKind = "policy"
                }
            }
        }

        // Fix regional actionKind if not matching an allowed directive for the target region
        if repaired.actionKind == "regional" {
            if let regionID = repaired.targetRegionID,
               let region = GeopoliticalMapData.regionByID[regionID]
            {
                let allowed = NativeQuickActionCatalog.regionalActions(for: region, state: state)
                let allowedDirectives = allowed.map(\.directiveTemplate)
                if !allowedDirectives.contains(repaired.detail) {
                    if let closest = NativeNVIDIAService.closestStringMatch(to: repaired.detail, from: allowedDirectives) {
                        repaired.detail = closest
                    } else {
                        repaired.actionKind = "policy"
                    }
                }
            } else {
                repaired.actionKind = "policy"
            }
        }

        // Fix military actionKind if it has a targetRegionID but doesn't match an allowed regional action
        if repaired.actionKind == "military", let regionID = repaired.targetRegionID {
            if let region = GeopoliticalMapData.regionByID[regionID] {
                let allowed = NativeQuickActionCatalog.regionalActions(for: region, state: state)
                let allowedDirectives = allowed.map(\.directiveTemplate)
                if !allowedDirectives.contains(repaired.detail) {
                    if let closest = NativeNVIDIAService.closestStringMatch(to: repaired.detail, from: allowedDirectives) {
                        repaired.detail = closest
                    } else {
                        repaired.actionKind = "policy"
                    }
                }
            } else {
                repaired.actionKind = "policy"
            }
        }

        return repaired
    }

    // MARK: - Fuzzy Matching Utilities

    static func closestCountryCode(to invalid: String, from valid: [String]) -> String {
        let upper = invalid.uppercased()
        if valid.contains(upper) {
            return upper
        }

        let prefixMatches = valid.filter { $0.hasPrefix(String(upper.prefix(2))) }
        if prefixMatches.count == 1 {
            return prefixMatches[0]
        }

        var bestCode = valid.first ?? upper
        var bestDistance = Int.max
        for code in valid {
            let dist = levenshtein(upper, code)
            if dist < bestDistance {
                bestDistance = dist
                bestCode = code
            }
        }
        return bestCode
    }

    private static func levenshtein(_ a: String, _ b: String) -> Int {
        let aChars = Array(a)
        let bChars = Array(b)
        if aChars.isEmpty {
            return bChars.count
        }
        if bChars.isEmpty {
            return aChars.count
        }

        var previousRow = Array(0 ... bChars.count)
        for (i, aChar) in aChars.enumerated() {
            var currentRow = [Int](repeating: 0, count: bChars.count + 1)
            currentRow[0] = i + 1
            for (j, bChar) in bChars.enumerated() {
                let insert = currentRow[j] + 1
                let delete = previousRow[j + 1] + 1
                let substitute = previousRow[j] + (aChar == bChar ? 0 : 1)
                currentRow[j + 1] = min(insert, delete, substitute)
            }
            previousRow = currentRow
        }
        return previousRow[bChars.count]
    }

    static func closestStringMatch(to invalid: String, from valid: [String]) -> String? {
        guard !valid.isEmpty else { return nil }
        let trimmedInvalid = invalid.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if let exact = valid.first(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == trimmedInvalid }) {
            return exact
        }

        var bestMatch: String? = nil
        var bestDistance = Int.max
        for candidate in valid {
            let trimmedCandidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let dist = levenshtein(trimmedInvalid, trimmedCandidate)
            if dist < bestDistance {
                bestDistance = dist
                bestMatch = candidate
            }
        }

        if let match = bestMatch, bestDistance <= 12 {
            return match
        }
        return nil
    }

    // MARK: - Payload Configuration

    override func configureProviderPayload(
        _ payload: inout [String: Any],
        thinkingEnabled: Bool
    ) {
        let model = payload["model"] as? String ?? ""
        if model == "deepseek-ai/deepseek-v4-flash" {
            payload["top_p"] = 0.95
            if payload["temperature"] == nil || thinkingEnabled {
                payload["temperature"] = 1.0
            }
            if thinkingEnabled {
                payload["chat_template_kwargs"] = [
                    "thinking": true,
                    "reasoning_effort": "high"
                ]
            }
        } else {
            // MiniMax-M3 or Kimi-K2.6
            payload["top_p"] = 0.90
            if payload["temperature"] == nil {
                payload["temperature"] = 0.6
            }
        }
    }
}
