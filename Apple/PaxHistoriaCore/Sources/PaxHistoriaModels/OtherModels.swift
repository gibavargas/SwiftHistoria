import Foundation

public struct NativeRegionConflictState: Codable, Hashable, Identifiable, Sendable {
    public var controllerCode: String
    public var intensity: Int
    public var mode: NativeRegionConflictMode
    public var originalCountryCode: String
    public var rebelDelta: Double
    public var regionID: String
    public var securityDelta: Double
    public var sourceEventID: String
    public var summary: String
    public var updatedAt: String

    public var id: String {
        regionID
    }

    public init(
        controllerCode: String,
        intensity: Int,
        mode: NativeRegionConflictMode,
        originalCountryCode: String,
        rebelDelta: Double = 0,
        regionID: String,
        securityDelta: Double = 0,
        sourceEventID: String = "",
        summary: String = "",
        updatedAt: String = ""
    ) {
        self.controllerCode = controllerCode
        self.intensity = max(1, min(5, intensity))
        self.mode = mode
        self.originalCountryCode = originalCountryCode
        self.rebelDelta = rebelDelta
        self.regionID = regionID
        self.securityDelta = securityDelta
        self.sourceEventID = sourceEventID
        self.summary = summary
        self.updatedAt = updatedAt
    }

    public static func countryCode(fromLegacyRegionID regionID: String) -> String {
        let prefix = regionID.split(separator: "_").first.map(String.init) ?? regionID
        return prefix.isEmpty ? regionID : prefix
    }
}

public struct NativeAICountryState: Codable, Hashable, Identifiable, Sendable {
    public var countryCode: String
    public var doctrine: NativeAIDoctrine
    public var budgetPriority: NativeAIBudgetPriority
    public var relationshipScores: [String: Int]
    public var multiTurnAgenda: String
    public var agendaProgress: Int

    public var id: String {
        countryCode
    }

    public init(
        countryCode: String,
        doctrine: NativeAIDoctrine,
        budgetPriority: NativeAIBudgetPriority,
        relationshipScores: [String: Int],
        multiTurnAgenda: String,
        agendaProgress: Int
    ) {
        self.countryCode = countryCode
        self.doctrine = doctrine
        self.budgetPriority = budgetPriority
        self.relationshipScores = relationshipScores
        self.multiTurnAgenda = multiTurnAgenda
        self.agendaProgress = agendaProgress
    }
}

public struct NativeSovereigntyChange: Codable, Hashable, Sendable {
    public var kind: NativeSovereigntyChangeKind
    public var name: String
    public var regionIDs: [String]
    public var sourceCodes: [String]
    public var targetCode: String

    public init(
        kind: NativeSovereigntyChangeKind,
        name: String,
        regionIDs: [String],
        sourceCodes: [String],
        targetCode: String
    ) {
        self.kind = kind
        self.name = name
        self.regionIDs = regionIDs
        self.sourceCodes = sourceCodes
        self.targetCode = targetCode
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case name
        case regionIDs
        case sourceCodes
        case targetCode
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawKind = (try? container.decodeIfPresent(String.self, forKey: .kind)) ?? ""
        kind = NativeSovereigntyChangeKind(rawValue: rawKind) ?? .secession
        name = (try? container.decodeIfPresent(String.self, forKey: .name)) ?? ""
        regionIDs = (try? container.decodeIfPresent([String].self, forKey: .regionIDs)) ?? []
        sourceCodes = (try? container.decodeIfPresent([String].self, forKey: .sourceCodes)) ?? []
        targetCode = (try? container.decodeIfPresent(String.self, forKey: .targetCode)) ?? ""
    }
}

public struct NativeSemanticMemory: Codable, Hashable, Identifiable, Sendable {
    public var date: String
    public var embedding: [Float]
    public var id: String
    public var importance: Int
    public var sourceID: String
    public var text: String
    public var track: NativeStrategicTrack

    public init(
        date: String,
        embedding: [Float],
        id: String,
        importance: Int,
        sourceID: String,
        text: String,
        track: NativeStrategicTrack
    ) {
        self.date = date
        self.embedding = embedding
        self.id = id
        self.importance = importance
        self.sourceID = sourceID
        self.text = text
        self.track = track
    }
}

public struct NativeAdvisorMessage: Codable, Hashable, Identifiable, Sendable {
    public var date: String
    public var id: String
    public var role: NativeAdvisorRole
    public var text: String

    public init(date: String, id: String, role: NativeAdvisorRole, text: String) {
        self.date = date
        self.id = id
        self.role = role
        self.text = text
    }
}

public struct NativeDiplomaticThread: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var lastUpdated: String
    public var messages: [NativeDiplomaticMessage]
    public var participant: PlayerCountry
    public var summary: String

    public init(id: String, lastUpdated: String, messages: [NativeDiplomaticMessage], participant: PlayerCountry, summary: String) {
        self.id = id
        self.lastUpdated = lastUpdated
        self.messages = messages
        self.participant = participant
        self.summary = summary
    }
}

public struct NativeDiplomaticMessage: Codable, Hashable, Identifiable, Sendable {
    public var date: String
    public var id: String
    public var speaker: String
    public var text: String

    public init(date: String, id: String, speaker: String, text: String) {
        self.date = date
        self.id = id
        self.speaker = speaker
        self.text = text
    }
}

public struct NativePlannedAction: Codable, Hashable, Identifiable, Sendable {
    public var createdAt: String
    public var detail: String
    public var id: String
    public var resolvedAt: String?
    public var status: NativeActionStatus
    public var title: String

    public init(createdAt: String, detail: String, id: String, resolvedAt: String? = nil, status: NativeActionStatus, title: String) {
        self.createdAt = createdAt
        self.detail = detail
        self.id = id
        self.resolvedAt = resolvedAt
        self.status = status
        self.title = title
    }
}

public struct NativeDiplomaticOffer: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var proposerCode: String
    public var type: NativeOfferType
    public var description: String
    public var stabilityCost: Int
    public var relationshipEffect: Int
    public var growthDelta: Double
    public var status: NativeOfferStatus
    public var turnProposed: Int

    public init(
        id: String,
        proposerCode: String,
        type: NativeOfferType,
        description: String,
        stabilityCost: Int,
        relationshipEffect: Int,
        growthDelta: Double,
        status: NativeOfferStatus,
        turnProposed: Int
    ) {
        self.id = id
        self.proposerCode = proposerCode
        self.type = type
        self.description = description
        self.stabilityCost = stabilityCost
        self.relationshipEffect = relationshipEffect
        self.growthDelta = growthDelta
        self.status = status
        self.turnProposed = turnProposed
    }
}

public struct NativeObligation: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var type: NativeObligationType
    public var description: String
    public var targetCountry: String?
    public var targetRegion: String?
    public var value: Double

    public init(id: String, type: NativeObligationType, description: String, targetCountry: String? = nil, targetRegion: String? = nil, value: Double) {
        self.id = id
        self.type = type
        self.description = description
        self.targetCountry = targetCountry
        self.targetRegion = targetRegion
        self.value = value
    }
}

public struct NativeTreaty: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var signatoryA: String
    public var signatoryB: String
    public var type: NativeOfferType
    public var signatureDate: String
    public var obligations: [NativeObligation]
    public var termMonths: Int
    public var elapsedMonths: Int
    public var isActive: Bool

    public init(
        id: String,
        name: String,
        signatoryA: String,
        signatoryB: String,
        type: NativeOfferType,
        signatureDate: String,
        obligations: [NativeObligation],
        termMonths: Int,
        elapsedMonths: Int,
        isActive: Bool
    ) {
        self.id = id
        self.name = name
        self.signatoryA = signatoryA
        self.signatoryB = signatoryB
        self.type = type
        self.signatureDate = signatureDate
        self.obligations = obligations
        self.termMonths = termMonths
        self.elapsedMonths = elapsedMonths
        self.isActive = isActive
    }
}

public struct NativeSuggestedAction: Codable, Hashable, Identifiable, Sendable {
    public var detail: String
    public var id: String
    public var rationale: String
    public var title: String
    public var urgency: String

    public init(detail: String, id: String, rationale: String, title: String, urgency: String) {
        self.detail = detail
        self.id = id
        self.rationale = rationale
        self.title = title
        self.urgency = urgency
    }
}

public struct NativeAIReadiness: Codable, Hashable, Sendable {
    public var availability: String
    public var checkedAt: String
    public var lastError: String
    public var ok: Bool
    public var recoverySuggestion: String
    public var tokenBudget: String

    public static let notChecked = NativeAIReadiness(
        availability: "not-checked",
        checkedAt: "",
        lastError: "",
        ok: false,
        recoverySuggestion: "",
        tokenBudget: ""
    )

    public init(
        availability: String,
        checkedAt: String,
        lastError: String,
        ok: Bool,
        recoverySuggestion: String,
        tokenBudget: String
    ) {
        self.availability = availability
        self.checkedAt = checkedAt
        self.lastError = lastError
        self.ok = ok
        self.recoverySuggestion = recoverySuggestion
        self.tokenBudget = tokenBudget
    }

    public static func available(tokenBudget: String) -> NativeAIReadiness {
        NativeAIReadiness(
            availability: "available",
            checkedAt: ISO8601DateFormatter().string(from: Date()),
            lastError: "",
            ok: true,
            recoverySuggestion: "",
            tokenBudget: tokenBudget
        )
    }

    public static func failure(_ error: Error) -> NativeAIReadiness {
        NativeAIReadiness(
            availability: failureAvailability(for: error),
            checkedAt: ISO8601DateFormatter().string(from: Date()),
            lastError: error.localizedDescription,
            ok: false,
            recoverySuggestion: recoverySuggestion(for: error),
            tokenBudget: "context=4096"
        )
    }

    public static func suggestionFailure(_ error: Error) -> NativeAIReadiness {
        NativeAIReadiness(
            availability: failureAvailability(for: error),
            checkedAt: ISO8601DateFormatter().string(from: Date()),
            lastError: error.localizedDescription,
            ok: false,
            recoverySuggestion: "Suggested actions could not be refreshed safely. Keep drafting manual civic proposals and retry when Apple Foundation Models are ready.",
            tokenBudget: "context=4096, suggestions=4x180"
        )
    }

    public static func unavailable(_ reason: String) -> NativeAIReadiness {
        NativeAIReadiness(
            availability: reason,
            checkedAt: ISO8601DateFormatter().string(from: Date()),
            lastError: reason,
            ok: false,
            recoverySuggestion: "Enable Apple Intelligence and make sure the local model is ready. SwiftHistoria will not simulate turns without Apple Foundation Models.",
            tokenBudget: "context=4096"
        )
    }

    public static func modelUnavailable(_ reason: String) -> NativeAIReadiness {
        NativeAIReadiness(
            availability: availabilityCode(for: reason),
            checkedAt: ISO8601DateFormatter().string(from: Date()),
            lastError: reason,
            ok: false,
            recoverySuggestion: "Enable Apple Intelligence and make sure the local model is ready. SwiftHistoria will not simulate turns without Apple Foundation Models.",
            tokenBudget: "context=4096"
        )
    }

    private static func failureAvailability(for error: Error) -> String {
        guard let foundationError = error as? NativeFoundationModelError else {
            return "apple-foundation-error"
        }

        switch foundationError {
        case .unsupportedOS:
            return "unsupported-os"
        case let .modelUnavailable(reason):
            return availabilityCode(for: reason)
        case .generationFailed, .invalidGeneratedTurn, .invalidSuggestedActions:
            return "apple-foundation-error"
        }
    }

    private static func recoverySuggestion(for error: Error) -> String {
        guard let foundationError = error as? NativeFoundationModelError else {
            return "Apple Foundation Models did not complete this request. The game kept the current turn unchanged; add manual civic proposals and retry when the model is ready."
        }

        switch foundationError {
        case .unsupportedOS:
            return "Run SwiftHistoria on an OS that exposes FoundationModels. The current campaign remains editable, but AI turns are paused."
        case .modelUnavailable:
            return "Enable Apple Intelligence and wait for the local model to finish preparing. Manual civic proposals remain available."
        case .generationFailed, .invalidGeneratedTurn, .invalidSuggestedActions:
            return "The model response could not be repaired safely. The campaign was not advanced; revise the proposal as civic planning and retry."
        }
    }

    private static func availabilityCode(for reason: String) -> String {
        let normalized = reason.lowercased()
        if normalized.contains("appleintelligencenotenabled") ||
            normalized.contains("not enabled")
        {
            return "apple-intelligence-not-enabled"
        }

        return "model-not-ready"
    }
}

public enum NativeFoundationModelError: LocalizedError {
    case unsupportedOS
    case modelUnavailable(String)
    case generationFailed(String)
    case invalidGeneratedTurn(String)
    case invalidSuggestedActions(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedOS:
            "This OS does not expose the FoundationModels framework required by the native game."
        case let .modelUnavailable(reason):
            "Apple Foundation Models are unavailable: \(reason)."
        case let .generationFailed(reason):
            "Apple Foundation Models generation failed: \(reason)."
        case let .invalidGeneratedTurn(reason):
            "Apple Foundation Models returned an invalid turn: \(reason)."
        case let .invalidSuggestedActions(reason):
            "Apple Foundation Models returned invalid suggested actions: \(reason)."
        }
    }
}

public struct NativeGeneratedTurn: Codable, Hashable, Sendable {
    public var events: [NativeCampaignEvent]
    public var stabilityDelta: Int
    public var summary: String
    public var worldTensionDelta: Int

    public init(events: [NativeCampaignEvent], stabilityDelta: Int, summary: String, worldTensionDelta: Int) {
        self.events = events
        self.stabilityDelta = stabilityDelta
        self.summary = summary
        self.worldTensionDelta = worldTensionDelta
    }
}

public struct NativeTurnProgress: Codable, Hashable, Sendable {
    public var completedLanes: Int
    public var detail: String
    public var phase: String
    public var totalLanes: Int

    public var fraction: Double {
        guard totalLanes > 0 else { return 0 }
        return min(1.0, max(0.0, Double(completedLanes) / Double(totalLanes)))
    }

    public init(completedLanes: Int, detail: String, phase: String, totalLanes: Int) {
        self.completedLanes = completedLanes
        self.detail = detail
        self.phase = phase
        self.totalLanes = totalLanes
    }
}

public struct NativeFactRecord: Codable, Hashable, Identifiable, Sendable {
    public var countryCodes: [String]
    public var detail: String
    public var id: String
    public var startDate: String
    public var tags: [String]
    public var title: String

    public init(countryCodes: [String], detail: String, id: String, startDate: String, tags: [String], title: String) {
        self.countryCodes = countryCodes
        self.detail = detail
        self.id = id
        self.startDate = startDate
        self.tags = tags
        self.title = title
    }
}

public struct NativeConsequenceRule: Codable, Hashable, Identifiable, Sendable {
    public var budgetBalanceDelta: Double
    public var debtDelta: Double
    public var description: String
    public var fiscalSpaceDelta: Int
    public var growthDelta: Double
    public var id: String
    public var inflationDelta: Double
    public var keywords: [String]
    public var summary: String
    public var tradeBalanceDelta: Double
    public var track: NativeStrategicTrack

    public init(
        budgetBalanceDelta: Double,
        debtDelta: Double,
        description: String,
        fiscalSpaceDelta: Int,
        growthDelta: Double,
        id: String,
        inflationDelta: Double,
        keywords: [String],
        summary: String,
        tradeBalanceDelta: Double,
        track: NativeStrategicTrack
    ) {
        self.budgetBalanceDelta = budgetBalanceDelta
        self.debtDelta = debtDelta
        self.description = description
        self.fiscalSpaceDelta = fiscalSpaceDelta
        self.growthDelta = growthDelta
        self.id = id
        self.inflationDelta = inflationDelta
        self.keywords = keywords
        self.summary = summary
        self.tradeBalanceDelta = tradeBalanceDelta
        self.track = track
    }
}

public struct NativeHexLever: Codable, Hashable, Sendable {
    public var growthDelta: Double
    public var budgetDelta: Double
    public var debtDelta: Double
    public var inflationDelta: Double
    public var tradeDelta: Double
    public var fiscalSpaceDelta: Int
    public var securityDelta: Double = 0.0
    public var rebelDelta: Double = 0.0
    public var invasionNudge: Int = 0

    public var conflictMode: NativeRegionConflictMode? {
        switch invasionNudge {
        case 1, 7:
            .conventionalOccupation
        case 2:
            .guerrillaControl
        case 3:
            .nuclearFallout
        case 4, 6, -1:
            .stabilization
        case 5:
            .contestedBorder
        default:
            nil
        }
    }

    public init(
        growthDelta: Double,
        budgetDelta: Double,
        debtDelta: Double,
        inflationDelta: Double,
        tradeDelta: Double,
        fiscalSpaceDelta: Int,
        securityDelta: Double = 0.0,
        rebelDelta: Double = 0.0,
        invasionNudge: Int = 0
    ) {
        self.growthDelta = growthDelta
        self.budgetDelta = budgetDelta
        self.debtDelta = debtDelta
        self.inflationDelta = inflationDelta
        self.tradeDelta = tradeDelta
        self.fiscalSpaceDelta = fiscalSpaceDelta
        self.securityDelta = securityDelta
        self.rebelDelta = rebelDelta
        self.invasionNudge = invasionNudge
    }
}

public struct NativeActionMemory: Codable, Hashable, Identifiable, Sendable {
    public var actionID: String
    public var createdAt: String
    public var detail: String
    public var economicSummary: String
    public var id: String
    public var resolvedAt: String?
    public var ruleIDs: [String]
    public var source: String
    public var status: NativeActionStatus
    public var title: String

    public init(
        actionID: String,
        createdAt: String,
        detail: String,
        economicSummary: String,
        id: String,
        resolvedAt: String? = nil,
        ruleIDs: [String],
        source: String,
        status: NativeActionStatus,
        title: String
    ) {
        self.actionID = actionID
        self.createdAt = createdAt
        self.detail = detail
        self.economicSummary = economicSummary
        self.id = id
        self.resolvedAt = resolvedAt
        self.ruleIDs = ruleIDs
        self.source = source
        self.status = status
        self.title = title
    }
}

public struct NativeStrategyContextPacket: Hashable, Sendable {
    public var consequenceRules: [NativeConsequenceRule]
    public var dynamicCountries: [String: String] = [:]
    public var economicLedger: NativeEconomicLedger
    public var facts: [NativeFactRecord]
    public var recentActions: [NativeActionMemory]
    public var semanticMemories: [NativeSemanticMemory] = []
    public var aiCountryStates: [String: NativeAICountryState] = [:]

    public init(
        consequenceRules: [NativeConsequenceRule],
        dynamicCountries: [String: String] = [:],
        economicLedger: NativeEconomicLedger,
        facts: [NativeFactRecord],
        recentActions: [NativeActionMemory],
        semanticMemories: [NativeSemanticMemory] = [],
        aiCountryStates: [String: NativeAICountryState] = [:]
    ) {
        self.consequenceRules = consequenceRules
        self.dynamicCountries = dynamicCountries
        self.economicLedger = economicLedger
        self.facts = facts
        self.recentActions = recentActions
        self.semanticMemories = semanticMemories
        self.aiCountryStates = aiCountryStates
    }

    public var promptBlock: String {
        let factLines = facts.prefix(6).map { "- \($0.id): \($0.title) -- \($0.detail)" }.joined(separator: "\n")
        let ruleLines = consequenceRules.prefix(5).map {
            "- \($0.id): \($0.summary); budget \($0.budgetBalanceDelta.signedPercent), growth \($0.growthDelta.signedPercent), inflation \($0.inflationDelta.signedPercent), trade \($0.tradeBalanceDelta.signedPercent)"
        }.joined(separator: "\n")
        let actionLines = recentActions.prefix(5).map {
            "- \($0.status.rawValue): \($0.title) (\($0.createdAt)) rules=\($0.ruleIDs.joined(separator: ",")); \($0.economicSummary)"
        }.joined(separator: "\n")
        let semanticLines = semanticMemories.prefix(5).map {
            "- \($0.date) \(foundationPromptTrackLabel($0.track)): \($0.text)"
        }.joined(separator: "\n")
        let dynamicCountryLines = dynamicCountries.sorted { $0.key < $1.key }.prefix(8).map {
            "- \($0.key): \($0.value)"
        }.joined(separator: "\n")
        let sortedAIStates = aiCountryStates.sorted(by: { lhs, rhs in
            let lScore = abs(lhs.value.relationshipScores.values.reduce(0, +))
            let rScore = abs(rhs.value.relationshipScores.values.reduce(0, +))
            return lScore > rScore
        }).prefix(4)
        let aiLines = sortedAIStates.map { code, aiState in
            let topRelations = aiState.relationshipScores
                .sorted { abs($0.value) > abs($1.value) }
                .prefix(3)
                .map { "\($0.key):\($0.value)" }
                .joined(separator: ",")
            return "- \(code): \(aiState.doctrine.rawValue), priority=\(aiState.budgetPriority.rawValue), relations=[\(topRelations.isEmpty ? "neutral" : topRelations)]"
        }.joined(separator: "\n")
        return """
        Local facts database:
        \(factLines.isEmpty ? "- No matching fact records." : factLines)

        Local consequences database:
        \(ruleLines.isEmpty ? "- Use default civic consequence ranges only." : ruleLines)

        Immediate action memory:
        \(actionLines.isEmpty ? "- No recent action records." : actionLines)

        Retrieved long-term memory:
        \(semanticLines.isEmpty ? "- No semantically related memories." : semanticLines)

        Dynamic sovereignty actors:
        \(dynamicCountryLines.isEmpty ? "- No breakaway, merged, or newly recognized countries." : dynamicCountryLines)

        Current economic ledger:
        GDP \(String(format: "$%.2fT", economicLedger.nominalGDPTrillions)); growth \(economicLedger.realGrowthPercent.signedPercent); inflation \(economicLedger.inflationPercent.percent); budget balance \(economicLedger.budgetBalancePercentGDP.signedPercent) of GDP; public debt \(economicLedger.publicDebtPercentGDP.percent) of GDP; trade balance \(economicLedger.tradeBalancePercentGDP.signedPercent) of GDP; unemployment \(economicLedger.unemploymentPercent.percent); fiscal space \(economicLedger.fiscalSpaceIndex)/100; public security \(String(format: "%.1f", economicLedger.securityIndex))/100; insurgency pressure \(String(format: "%.1f%%", economicLedger.rebelControlPercent)).

        Key AI country postures (top 4 by relationship activity):
        \(aiLines.isEmpty ? "- No autonomous AI states configured." : aiLines)

        Use the IDs above as evidence. Do not invent starting facts or economic, public-security, insurgency, or map-control effects outside these ranges.
        """
    }
}

public extension Double {
    var percent: String {
        String(format: "%.1f%%", self)
    }

    var signedPercent: String {
        String(format: "%+.2f%%", self)
    }
}
