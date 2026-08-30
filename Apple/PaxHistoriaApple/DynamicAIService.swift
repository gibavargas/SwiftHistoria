// DynamicAIService.swift
// Runtime dispatcher for the two player-selectable external AI routes.

import Foundation

@MainActor
class DynamicAIService: NativeAIService {
    private let defaults: UserDefaults
    private let nvidiaService: NativeNVIDIAService
    private let openRouterService: NativeOpenRouterService

    /// Tracks the selected provider before a request starts so failures remain
    /// visibly attached to the route the player chose.
    var lastProviderUsed: String = "None"

    var sessionPromptTokens: Int {
        nvidiaService.sessionPromptTokens + openRouterService.sessionPromptTokens
    }

    var sessionCompletionTokens: Int {
        nvidiaService.sessionCompletionTokens + openRouterService.sessionCompletionTokens
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
        openRouterService: NativeOpenRouterService? = nil
    ) {
        self.defaults = defaults
        self.nvidiaService = nvidiaService ?? NativeNVIDIAService(defaults: defaults)
        self.openRouterService = openRouterService ?? NativeOpenRouterService(defaults: defaults)
    }

    private var providerPreference: NativeAIProviderPreference {
        NativeAIProviderPreference.current(defaults: defaults)
    }

    private var selectedService: NativeExternalAIService {
        switch providerPreference {
        case .nvidia:
            nvidiaService
        case .openRouter:
            openRouterService
        }
    }

    private var missingKeyMessage: String {
        switch providerPreference {
        case .nvidia:
            "NVIDIA is selected, but no NVIDIA API key is saved. Add the key in Settings and retry."
        case .openRouter:
            "OpenRouter Free is selected, but no OpenRouter API key is saved. Add the key in Settings and retry."
        }
    }

    private func selectedServiceForRequest() throws -> NativeExternalAIService {
        let service = selectedService
        lastProviderUsed = service.providerDisplayName
        guard !service.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NativeFoundationModelError.modelUnavailable(missingKeyMessage)
        }
        return service
    }

    func checkReadiness() async -> NativeAIReadiness {
        let service = selectedService
        lastProviderUsed = service.providerDisplayName
        guard !service.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .unavailable(missingKeyMessage)
        }
        return await service.checkReadiness()
    }

    func generateTurn(for state: NativeCampaignState, months: Int) async throws -> NativeGeneratedTurn {
        let service = try selectedServiceForRequest()
        return try await service.generateTurn(for: state, months: months)
    }

    func generateTurn(
        for state: NativeCampaignState,
        months: Int,
        progress: @escaping @MainActor (NativeTurnProgress) -> Void
    ) async throws -> NativeGeneratedTurn {
        let service: NativeExternalAIService
        do {
            service = try selectedServiceForRequest()
        } catch {
            let selected = selectedService
            progress(NativeTurnProgress(
                completedLanes: 0,
                detail: missingKeyMessage,
                phase: "Selected provider unavailable",
                totalLanes: NativeStrategyContextDatabase.estimatedLaneCount(for: state),
                providerName: selected.providerDisplayName,
                modelName: selected.primaryModelDisplayName,
                modelIdentifier: selected.primaryModelIdentifier
            ))
            throw error
        }
        return try await service.generateTurn(for: state, months: months, progress: progress)
    }

    func generateSuggestedActions(for state: NativeCampaignState) async throws -> [NativeSuggestedAction] {
        let service = try selectedServiceForRequest()
        return try await service.generateSuggestedActions(for: state)
    }

    func generateAdvisorBrief(for state: NativeCampaignState, question: String) async throws -> String {
        let service = try selectedServiceForRequest()
        return try await service.generateAdvisorBrief(for: state, question: question)
    }

    func generateDiplomaticReply(
        for state: NativeCampaignState,
        thread: NativeDiplomaticThread,
        message: String
    ) async throws -> String {
        let service = try selectedServiceForRequest()
        return try await service.generateDiplomaticReply(for: state, thread: thread, message: message)
    }

    func generateRivalAgentTurns(for state: NativeCampaignState) async throws -> [NativeRivalAgentTurn] {
        let service = try selectedServiceForRequest()
        return try await service.generateRivalAgentTurns(for: state)
    }
}
