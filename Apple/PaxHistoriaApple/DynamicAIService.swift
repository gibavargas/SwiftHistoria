// DynamicAIService.swift
// DynamicAIService: runtime AI-service dispatcher that routes between
// OpenRouter, ZAI, and Apple Foundation Models based on configuration.

import Foundation
import OSLog

@MainActor
class DynamicAIService: NativeAIService {
    private let logger = Logger(subsystem: "com.gibavargas.SwiftHistoria", category: "DynamicAIService")
    private let defaults: UserDefaults
    private let openRouterService: NativeOpenRouterService
    private let zaiService: NativeZAIService
    private let foundationService: NativeFoundationModelService

    /// Tracks which provider last produced a response (for advisor/diplomacy UI labels).
    var lastProviderUsed: String = "None"

    /// Aggregate token usage across all sub-services
    var sessionPromptTokens: Int {
        openRouterService.sessionPromptTokens + zaiService.sessionPromptTokens
    }

    var sessionCompletionTokens: Int {
        openRouterService.sessionCompletionTokens + zaiService.sessionCompletionTokens
    }

    var sessionTotalTokens: Int {
        sessionPromptTokens + sessionCompletionTokens
    }

    var tokenBudgetWarning: Bool {
        sessionTotalTokens > 100_000
    }

    init(
        defaults: UserDefaults = .standard,
        openRouterService: NativeOpenRouterService? = nil,
        zaiService: NativeZAIService? = nil,
        foundationService: NativeFoundationModelService = NativeFoundationModelService()
    ) {
        self.defaults = defaults
        self.openRouterService = openRouterService ?? NativeOpenRouterService(defaults: defaults)
        self.zaiService = zaiService ?? NativeZAIService(defaults: defaults)
        self.foundationService = foundationService
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
            lastProviderUsed = "Apple Foundation Models"
            return await foundationService.checkReadiness()
        case .openRouter:
            if hasOpenRouterKey {
                let openRouterReadiness = await openRouterService.checkReadiness()
                if openRouterReadiness.ok {
                    lastProviderUsed = openRouterService.providerDisplayName
                    return openRouterReadiness
                }
                if hasZAIKey {
                    let zaiReadiness = await zaiService.checkReadiness()
                    if zaiReadiness.ok {
                        lastProviderUsed = zaiService.providerDisplayName
                        return .available(tokenBudget: "OpenRouter unavailable; Z.AI fallback verified")
                    }
                }
                let appleReadiness = await foundationService.checkReadiness()
                if appleReadiness.ok {
                    lastProviderUsed = "Apple Foundation Models"
                    return .available(tokenBudget: "OpenRouter unavailable; Apple Foundation Models fallback verified")
                }
                return openRouterReadiness
            }
            if hasZAIKey {
                lastProviderUsed = zaiService.providerDisplayName
                return await zaiService.checkReadiness()
            }
            lastProviderUsed = "Apple Foundation Models"
            return await foundationService.checkReadiness()
        case .zai:
            if hasZAIKey {
                lastProviderUsed = zaiService.providerDisplayName
                return await zaiService.checkReadiness()
            }
            lastProviderUsed = "Apple Foundation Models"
            return await foundationService.checkReadiness()
        }
    }

    func generateTurn(for state: NativeCampaignState, months: Int) async throws -> NativeGeneratedTurn {
        switch providerPreference {
        case .appleFoundation:
            lastProviderUsed = "Apple Foundation Models"
            return try await foundationService.generateTurn(for: state, months: months)
        case .openRouter:
            if hasOpenRouterKey {
                do {
                    logger.info("OpenRouter turn generation started round=\(state.round)")
                    let result = try await openRouterService.generateTurn(for: state, months: months)
                    lastProviderUsed = openRouterService.providerDisplayName
                    return result
                } catch {
                    logger.error("OpenRouter turn failed; trying configured fallback. openrouter_error=\(error.localizedDescription, privacy: .public)")
                }
            }
            if hasZAIKey {
                do {
                    let result = try await zaiService.generateTurn(for: state, months: months)
                    lastProviderUsed = zaiService.providerDisplayName
                    return result
                } catch {
                    logger.error("Z.AI turn failed; trying Apple Foundation Models. z_ai_error=\(error.localizedDescription, privacy: .public)")
                }
            }
            lastProviderUsed = "Apple Foundation Models"
            return try await foundationService.generateTurn(for: state, months: months)
        case .zai:
            if hasZAIKey {
                do {
                    let result = try await zaiService.generateTurn(for: state, months: months)
                    lastProviderUsed = zaiService.providerDisplayName
                    return result
                } catch {
                    logger.error("Z.AI turn failed; trying Apple Foundation Models. z_ai_error=\(error.localizedDescription, privacy: .public)")
                }
            }
            lastProviderUsed = "Apple Foundation Models"
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
            lastProviderUsed = "Apple Foundation Models"
            return try await foundationService.generateTurn(for: state, months: months, progress: progress)
        case .openRouter:
            if hasOpenRouterKey {
                do {
                    logger.info("OpenRouter turn generation started round=\(state.round)")
                    let result = try await openRouterService.generateTurn(for: state, months: months, progress: progress)
                    lastProviderUsed = openRouterService.providerDisplayName
                    return result
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
                    let result = try await zaiService.generateTurn(for: state, months: months, progress: progress)
                    lastProviderUsed = zaiService.providerDisplayName
                    return result
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
            lastProviderUsed = "Apple Foundation Models"
            return try await foundationService.generateTurn(for: state, months: months, progress: progress)
        case .zai:
            if hasZAIKey {
                do {
                    let result = try await zaiService.generateTurn(for: state, months: months, progress: progress)
                    lastProviderUsed = zaiService.providerDisplayName
                    return result
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
            lastProviderUsed = "Apple Foundation Models"
            return try await foundationService.generateTurn(for: state, months: months, progress: progress)
        }
    }

    func generateSuggestedActions(for state: NativeCampaignState) async throws -> [NativeSuggestedAction] {
        switch providerPreference {
        case .appleFoundation:
            lastProviderUsed = "Apple Foundation Models"
            return try await foundationService.generateSuggestedActions(for: state)
        case .openRouter:
            if hasOpenRouterKey {
                do {
                    let result = try await openRouterService.generateSuggestedActions(for: state)
                    lastProviderUsed = openRouterService.providerDisplayName
                    return result
                } catch {
                    logger.warning("Suggestions: OpenRouter failed, falling back: \(error.localizedDescription, privacy: .public)")
                }
            }
            if hasZAIKey {
                do {
                    let result = try await zaiService.generateSuggestedActions(for: state)
                    lastProviderUsed = zaiService.providerDisplayName
                    return result
                } catch {
                    logger.warning("Suggestions: Z.AI failed, falling back to Apple: \(error.localizedDescription, privacy: .public)")
                }
            }
            lastProviderUsed = "Apple Foundation Models"
            return try await foundationService.generateSuggestedActions(for: state)
        case .zai:
            if hasZAIKey {
                do {
                    let result = try await zaiService.generateSuggestedActions(for: state)
                    lastProviderUsed = zaiService.providerDisplayName
                    return result
                } catch {
                    logger.warning("Suggestions: Z.AI failed, falling back to Apple: \(error.localizedDescription, privacy: .public)")
                }
            }
            lastProviderUsed = "Apple Foundation Models"
            return try await foundationService.generateSuggestedActions(for: state)
        }
    }

    func generateAdvisorBrief(for state: NativeCampaignState, question: String) async throws -> String {
        switch providerPreference {
        case .appleFoundation:
            lastProviderUsed = "Apple Foundation Models"
            return try await foundationService.generateAdvisorBrief(for: state, question: question)
        case .openRouter:
            if hasOpenRouterKey {
                do {
                    let result = try await openRouterService.generateAdvisorBrief(for: state, question: question)
                    lastProviderUsed = openRouterService.providerDisplayName
                    return result
                } catch {
                    logger.warning("Advisor: OpenRouter failed, falling back: \(error.localizedDescription, privacy: .public)")
                }
            }
            if hasZAIKey {
                do {
                    let result = try await zaiService.generateAdvisorBrief(for: state, question: question)
                    lastProviderUsed = zaiService.providerDisplayName
                    return result
                } catch {
                    logger.warning("Advisor: Z.AI failed, falling back to Apple: \(error.localizedDescription, privacy: .public)")
                }
            }
            lastProviderUsed = "Apple Foundation Models"
            return try await foundationService.generateAdvisorBrief(for: state, question: question)
        case .zai:
            if hasZAIKey {
                do {
                    let result = try await zaiService.generateAdvisorBrief(for: state, question: question)
                    lastProviderUsed = zaiService.providerDisplayName
                    return result
                } catch {
                    logger.warning("Advisor: Z.AI failed, falling back to Apple: \(error.localizedDescription, privacy: .public)")
                }
            }
            lastProviderUsed = "Apple Foundation Models"
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
            lastProviderUsed = "Apple Foundation Models"
            return try await foundationService.generateDiplomaticReply(for: state, thread: thread, message: message)
        case .openRouter:
            if hasOpenRouterKey {
                do {
                    let result = try await openRouterService.generateDiplomaticReply(for: state, thread: thread, message: message)
                    lastProviderUsed = openRouterService.providerDisplayName
                    return result
                } catch {
                    logger.warning("Diplomacy: OpenRouter failed, falling back: \(error.localizedDescription, privacy: .public)")
                }
            }
            if hasZAIKey {
                do {
                    let result = try await zaiService.generateDiplomaticReply(for: state, thread: thread, message: message)
                    lastProviderUsed = zaiService.providerDisplayName
                    return result
                } catch {
                    logger.warning("Diplomacy: Z.AI failed, falling back to Apple: \(error.localizedDescription, privacy: .public)")
                }
            }
            lastProviderUsed = "Apple Foundation Models"
            return try await foundationService.generateDiplomaticReply(for: state, thread: thread, message: message)
        case .zai:
            if hasZAIKey {
                do {
                    let result = try await zaiService.generateDiplomaticReply(for: state, thread: thread, message: message)
                    lastProviderUsed = zaiService.providerDisplayName
                    return result
                } catch {
                    logger.warning("Diplomacy: Z.AI failed, falling back to Apple: \(error.localizedDescription, privacy: .public)")
                }
            }
            lastProviderUsed = "Apple Foundation Models"
            return try await foundationService.generateDiplomaticReply(for: state, thread: thread, message: message)
        }
    }
}
