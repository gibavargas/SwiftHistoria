// DynamicAIService.swift
// DynamicAIService: runtime AI-service dispatcher that routes between
// NVIDIA DiffusionGemma, OpenRouter, ZAI, and Apple Foundation Models based on configuration.

import Foundation
import OSLog

/// Result envelope for the hedged request race.
/// Each task in the race returns success or failure without throwing,
/// so the winner can be determined without actor isolation issues.
private enum HedgedResult<T: Sendable> {
    case nvidia(T)
    case openRouter(T)
    case nvidiaError(Error)
    case openRouterError(Error)
}

@MainActor
class DynamicAIService: NativeAIService {
    private let logger = Logger(subsystem: "com.gibavargas.SwiftHistoria", category: "DynamicAIService")
    private let defaults: UserDefaults
    private let nvidiaService: NativeNVIDIAService
    private let openRouterService: NativeOpenRouterService
    private let zaiService: NativeZAIService
    private let foundationService: NativeFoundationModelService

    /// Tracks which provider last produced a response (for advisor/diplomacy UI labels).
    var lastProviderUsed: String = "None"

    /// Aggregate token usage across all sub-services
    var sessionPromptTokens: Int {
        nvidiaService.sessionPromptTokens + openRouterService.sessionPromptTokens + zaiService.sessionPromptTokens
    }

    var sessionCompletionTokens: Int {
        nvidiaService.sessionCompletionTokens + openRouterService.sessionCompletionTokens + zaiService.sessionCompletionTokens
    }

    var sessionTotalTokens: Int {
        sessionPromptTokens + sessionCompletionTokens
    }

    var tokenBudgetWarning: Bool {
        false
    }

    init(
        defaults: UserDefaults = .standard,
        nvidiaService: NativeNVIDIAService? = nil,
        openRouterService: NativeOpenRouterService? = nil,
        zaiService: NativeZAIService? = nil,
        foundationService: NativeFoundationModelService = NativeFoundationModelService()
    ) {
        self.defaults = defaults
        self.nvidiaService = nvidiaService ?? NativeNVIDIAService(defaults: defaults)
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

    private var hasNVIDIAKey: Bool {
        let key = defaults.string(forKey: "NVIDIA_API_KEY") ?? ""
        return !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var hasZAIKey: Bool {
        let key = defaults.string(forKey: "ZAI_API_KEY") ?? ""
        return !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var unavailableNVIDIARouteMessage: String {
        "NVIDIA NIM is primary, but no NVIDIA API key is saved and the OpenRouter fallback has no API key."
    }

    /// **Hedged request** pattern: races NVIDIA and OpenRouter in parallel and returns
    /// whichever finishes first. If NVIDIA wins, great (fast + free). If NVIDIA times
    /// out or errors, OpenRouter is already mid-flight as a hidden safety net.
    ///
    /// Used specifically for `generateSuggestedActions` where the DiffusionGemma draft
    /// phase can hang for 60s+ on NVIDIA NIM, while OpenRouter Free models produce
    /// results reliably in 5-15s.
    private func hedgedSuggestions(for state: NativeCampaignState) async throws -> [NativeSuggestedAction] {
        guard hasNVIDIAKey else {
            // No NVIDIA key — just use OpenRouter directly
            if hasOpenRouterKey {
                lastProviderUsed = openRouterService.providerDisplayName
                return try await openRouterService.generateSuggestedActions(for: state)
            }
            throw NativeFoundationModelError.modelUnavailable(unavailableNVIDIARouteMessage)
        }

        // If no OpenRouter key, NVIDIA only (no hedging possible)
        guard hasOpenRouterKey else {
            lastProviderUsed = nvidiaService.providerDisplayName
            return try await nvidiaService.generateSuggestedActions(for: state)
        }

        // Race both providers in parallel. First valid result wins.
        return try await withThrowingTaskGroup(of: HedgedResult<[NativeSuggestedAction]>.self) { group in
            group.addTask {
                do {
                    let result = try await self.nvidiaService.generateSuggestedActions(for: state)
                    return .nvidia(result)
                } catch is CancellationError {
                    return .nvidiaError(CancellationError())
                } catch {
                    return .nvidiaError(error)
                }
            }

            group.addTask {
                do {
                    let result = try await self.openRouterService.generateSuggestedActions(for: state)
                    return .openRouter(result)
                } catch is CancellationError {
                    return .openRouterError(CancellationError())
                } catch {
                    return .openRouterError(error)
                }
            }

            var firstResult: [NativeSuggestedAction]?
            var nvidiaError: Error?
            var openRouterError: Error?
            var winner: String?

            for try await result in group {
                switch result {
                case let .nvidia(suggestions):
                    firstResult = suggestions
                    winner = "NVIDIA NIM"
                    group.cancelAll()
                case let .openRouter(suggestions):
                    firstResult = suggestions
                    winner = "OpenRouter Free"
                    group.cancelAll()
                case let .nvidiaError(error):
                    nvidiaError = error
                    logger.info("Hedged suggestions: NVIDIA NIM lost: \(error.localizedDescription, privacy: .public)")
                case let .openRouterError(error):
                    openRouterError = error
                    logger.info("Hedged suggestions: OpenRouter lost: \(error.localizedDescription, privacy: .public)")
                }
                if firstResult != nil { break }
            }

            // Drain remaining after cancellation
            while await (try? group.next()) != nil {}

            if let result = firstResult {
                lastProviderUsed = winner == "NVIDIA NIM" ? nvidiaService.providerDisplayName : openRouterService.providerDisplayName
                logger.info("Hedged suggestions: \(winner ?? "?") won the race")
                return result
            }

            // Both failed — throw the more informative error
            throw nvidiaError ?? openRouterError ?? NativeFoundationModelError.invalidSuggestedActions(
                "Both NVIDIA NIM and OpenRouter Free failed to generate suggestions."
            )
        }
    }

    /// **Hedged request** for turn generation. Same race pattern as suggestions
    /// but for NativeGeneratedTurn. Ensures the player never waits 60s for a
    /// timeout — OpenRouter is already running as backup.
    private func hedgedTurn(
        for state: NativeCampaignState,
        months: Int,
        progress: @escaping @MainActor (NativeTurnProgress) -> Void
    ) async throws -> NativeGeneratedTurn {
        guard hasNVIDIAKey else {
            if hasOpenRouterKey {
                lastProviderUsed = openRouterService.providerDisplayName
                return try await openRouterService.generateTurn(for: state, months: months, progress: progress)
            }
            throw NativeFoundationModelError.modelUnavailable(unavailableNVIDIARouteMessage)
        }

        guard hasOpenRouterKey else {
            lastProviderUsed = nvidiaService.providerDisplayName
            return try await nvidiaService.generateTurn(for: state, months: months, progress: progress)
        }

        let total = NativeStrategyContextDatabase.estimatedLaneCount(for: state)
        let nvidiaName = nvidiaService.providerDisplayName
        let openRouterName = openRouterService.providerDisplayName

        return try await withThrowingTaskGroup(of: HedgedResult<NativeGeneratedTurn>.self) { group in
            group.addTask {
                do {
                    let result = try await self.nvidiaService.generateTurn(for: state, months: months, progress: progress)
                    return .nvidia(result)
                } catch is CancellationError {
                    return .nvidiaError(CancellationError())
                } catch {
                    return .nvidiaError(error)
                }
            }

            group.addTask {
                do {
                    let result = try await self.openRouterService.generateTurn(for: state, months: months, progress: progress)
                    return .openRouter(result)
                } catch is CancellationError {
                    return .openRouterError(CancellationError())
                } catch {
                    return .openRouterError(error)
                }
            }

            var firstResult: NativeGeneratedTurn?
            var nvidiaError: Error?
            var openRouterError: Error?
            var winner: String?

            for try await result in group {
                switch result {
                case let .nvidia(turn):
                    firstResult = turn
                    winner = nvidiaName
                    group.cancelAll()
                case let .openRouter(turn):
                    firstResult = turn
                    winner = openRouterName
                    group.cancelAll()
                case let .nvidiaError(error):
                    nvidiaError = error
                    logger.info("Hedged turn: NVIDIA NIM lost: \(error.localizedDescription, privacy: .public)")
                case let .openRouterError(error):
                    openRouterError = error
                    logger.info("Hedged turn: OpenRouter lost: \(error.localizedDescription, privacy: .public)")
                }
                if firstResult != nil { break }
            }

            while await (try? group.next()) != nil {}

            if let result = firstResult {
                lastProviderUsed = winner ?? nvidiaName
                logger.info("Hedged turn: \(winner ?? "?") won the race")
                return result
            }

            throw nvidiaError ?? openRouterError ?? NativeFoundationModelError.generationFailed(
                "Both NVIDIA NIM and OpenRouter Free failed to generate the turn."
            )
        }
    }

    /// **Hedged request** for text generation (advisor, diplomacy). Races NVIDIA
    /// and OpenRouter in parallel — first valid text result wins.
    private func hedgedText(
        surface: String,
        nvidiaOp: @escaping @MainActor () async throws -> String,
        openRouterOp: @escaping @MainActor () async throws -> String
    ) async throws -> String {
        if !hasNVIDIAKey {
            if hasOpenRouterKey {
                lastProviderUsed = openRouterService.providerDisplayName
                return try await openRouterOp()
            }
            throw NativeFoundationModelError.modelUnavailable(unavailableNVIDIARouteMessage)
        }
        guard hasOpenRouterKey else {
            lastProviderUsed = nvidiaService.providerDisplayName
            return try await nvidiaOp()
        }

        // Use nonisolated wrappers to avoid sending closure issues
        let nvidiaTask = Task { try await nvidiaOp() }
        let orTask = Task { try await openRouterOp() }

        var nvidiaErr: Error?
        var orErr: Error?

        // Try to get NVIDIA result first (it's the preferred provider)
        do {
            let result = try await nvidiaTask.value
            orTask.cancel()
            logger.info("Hedged \(surface, privacy: .public): NVIDIA won")
            return result
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            nvidiaErr = error
            logger.info("Hedged \(surface, privacy: .public): NVIDIA lost: \(error.localizedDescription, privacy: .public)")
        }

        // NVIDIA failed, wait for OpenRouter
        do {
            let result = try await orTask.value
            logger.info("Hedged \(surface, privacy: .public): OpenRouter won")
            return result
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            orErr = error
            logger.info("Hedged \(surface, privacy: .public): OpenRouter lost: \(error.localizedDescription, privacy: .public)")
        }

        throw nvidiaErr ?? orErr ?? NativeFoundationModelError.generationFailed("Both providers failed for \(surface).")
    }

    func checkReadiness() async -> NativeAIReadiness {
        switch providerPreference {
        case .nvidia:
            if hasNVIDIAKey {
                lastProviderUsed = nvidiaService.providerDisplayName
                let primaryReadiness = await nvidiaService.checkReadiness()
                if primaryReadiness.ok || !hasOpenRouterKey {
                    return primaryReadiness
                }
            } else if !hasOpenRouterKey {
                lastProviderUsed = nvidiaService.providerDisplayName
                return .unavailable(unavailableNVIDIARouteMessage)
            }

            lastProviderUsed = openRouterService.providerDisplayName
            let fallbackReadiness = await openRouterService.checkReadiness()
            if fallbackReadiness.ok {
                return .available(tokenBudget: "OpenRouter Free fallback ready; no app-level token cap")
            }
            return fallbackReadiness
        case .appleFoundation:
            lastProviderUsed = "Apple Foundation Models"
            return await foundationService.checkReadiness()
        case .openRouter:
            if hasOpenRouterKey {
                lastProviderUsed = openRouterService.providerDisplayName
                let openRouterReadiness = await openRouterService.checkReadiness()
                if openRouterReadiness.ok {
                    return openRouterReadiness
                }
                return openRouterReadiness
            }
            lastProviderUsed = openRouterService.providerDisplayName
            return .unavailable("OpenRouter is selected, but no OpenRouter API key is saved.")
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
        case .nvidia:
            return try await hedgedTurn(for: state, months: months) { _ in }
        case .appleFoundation:
            lastProviderUsed = "Apple Foundation Models"
            return try await foundationService.generateTurn(for: state, months: months)
        case .openRouter:
            if hasOpenRouterKey {
                do {
                    lastProviderUsed = openRouterService.providerDisplayName
                    logger.info("OpenRouter turn generation started round=\(state.round)")
                    let result = try await openRouterService.generateTurn(for: state, months: months)
                    lastProviderUsed = openRouterService.providerDisplayName
                    return result
                } catch {
                    logger.error("OpenRouter turn failed. openrouter_error=\(error.localizedDescription, privacy: .public)")
                    throw error
                }
            }
            lastProviderUsed = openRouterService.providerDisplayName
            throw NativeFoundationModelError.modelUnavailable("OpenRouter is selected, but no OpenRouter API key is saved.")
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
        case .nvidia:
            return try await hedgedTurn(for: state, months: months, progress: progress)
        case .appleFoundation:
            lastProviderUsed = "Apple Foundation Models"
            return try await foundationService.generateTurn(for: state, months: months, progress: progress)
        case .openRouter:
            if hasOpenRouterKey {
                do {
                    lastProviderUsed = openRouterService.providerDisplayName
                    logger.info("OpenRouter turn generation started round=\(state.round)")
                    let result = try await openRouterService.generateTurn(for: state, months: months, progress: progress)
                    lastProviderUsed = openRouterService.providerDisplayName
                    return result
                } catch {
                    logger.error("OpenRouter turn failed. openrouter_error=\(error.localizedDescription, privacy: .public)")
                    throw error
                }
            }
            lastProviderUsed = openRouterService.providerDisplayName
            progress(NativeTurnProgress(
                completedLanes: 0,
                detail: "OpenRouter is selected, but no OpenRouter API key is saved. Add the key in Settings and retry.",
                phase: "OpenRouter unavailable",
                totalLanes: total,
                providerName: openRouterService.providerDisplayName,
                modelName: openRouterService.primaryModelDisplayName,
                modelIdentifier: openRouterService.primaryModelIdentifier
            ))
            throw NativeFoundationModelError.modelUnavailable("OpenRouter is selected, but no OpenRouter API key is saved.")
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
        case .nvidia:
            // Hedged request: race NVIDIA (DiffusionGemma draft + refine) against
            // OpenRouter Free in parallel. First valid 25-cell matrix wins.
            // This eliminates the 60s timeout problem — if NVIDIA hangs, OpenRouter
            // is already mid-flight and finishes in 5-15s.
            return try await hedgedSuggestions(for: state)
        case .appleFoundation:
            lastProviderUsed = "Apple Foundation Models"
            return try await foundationService.generateSuggestedActions(for: state)
        case .openRouter:
            if hasOpenRouterKey {
                do {
                    lastProviderUsed = openRouterService.providerDisplayName
                    let result = try await openRouterService.generateSuggestedActions(for: state)
                    lastProviderUsed = openRouterService.providerDisplayName
                    return result
                } catch {
                    logger.warning("Suggestions: OpenRouter failed: \(error.localizedDescription, privacy: .public)")
                    throw error
                }
            }
            lastProviderUsed = openRouterService.providerDisplayName
            throw NativeFoundationModelError.modelUnavailable("OpenRouter is selected, but no OpenRouter API key is saved.")
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
        case .nvidia:
            return try await hedgedText(
                surface: "advisor",
                nvidiaOp: { try await self.nvidiaService.generateAdvisorBrief(for: state, question: question) },
                openRouterOp: { try await self.openRouterService.generateAdvisorBrief(for: state, question: question) }
            )
        case .appleFoundation:
            lastProviderUsed = "Apple Foundation Models"
            return try await foundationService.generateAdvisorBrief(for: state, question: question)
        case .openRouter:
            if hasOpenRouterKey {
                do {
                    lastProviderUsed = openRouterService.providerDisplayName
                    let result = try await openRouterService.generateAdvisorBrief(for: state, question: question)
                    lastProviderUsed = openRouterService.providerDisplayName
                    return result
                } catch {
                    logger.warning("Advisor: OpenRouter failed: \(error.localizedDescription, privacy: .public)")
                    throw error
                }
            }
            lastProviderUsed = openRouterService.providerDisplayName
            throw NativeFoundationModelError.modelUnavailable("OpenRouter is selected, but no OpenRouter API key is saved.")
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
        case .nvidia:
            return try await hedgedText(
                surface: "diplomacy",
                nvidiaOp: { try await self.nvidiaService.generateDiplomaticReply(for: state, thread: thread, message: message) },
                openRouterOp: { try await self.openRouterService.generateDiplomaticReply(for: state, thread: thread, message: message) }
            )
        case .appleFoundation:
            lastProviderUsed = "Apple Foundation Models"
            return try await foundationService.generateDiplomaticReply(for: state, thread: thread, message: message)
        case .openRouter:
            if hasOpenRouterKey {
                do {
                    lastProviderUsed = openRouterService.providerDisplayName
                    let result = try await openRouterService.generateDiplomaticReply(for: state, thread: thread, message: message)
                    lastProviderUsed = openRouterService.providerDisplayName
                    return result
                } catch {
                    logger.warning("Diplomacy: OpenRouter failed: \(error.localizedDescription, privacy: .public)")
                    throw error
                }
            }
            lastProviderUsed = openRouterService.providerDisplayName
            throw NativeFoundationModelError.modelUnavailable("OpenRouter is selected, but no OpenRouter API key is saved.")
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
