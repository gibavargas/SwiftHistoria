import Foundation

/// Player-selectable campaign mode. The enum is persisted, so raw values should
/// stay stable unless an explicit save migration is added.
enum NativeGameMode: String, Codable, CaseIterable, Identifiable, Hashable {
    case sandbox = "Sandbox"
    case normal = "Normal"
    case ironman = "Iron Man"

    var id: String {
        rawValue
    }

    var description: String {
        switch self {
        case .sandbox: String(localized: "Unlimited administrative freedom and light consequences.")
        case .normal: String(localized: "Standard campaign conditions with active crisis events.")
        case .ironman: String(localized: "Sovereign risks are doubled, and reloading is disabled.")
        }
    }
}

enum NativeTerrainType: String, Codable, CaseIterable, Identifiable, Hashable {
    case ocean
    case strait
    case sea
    case city
    case forest
    case cerrado
    case swamp
    case mountain
    case plains

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .ocean: String(localized: "Ocean")
        case .strait: String(localized: "Strait")
        case .sea: String(localized: "Sea")
        case .city: String(localized: "City")
        case .forest: String(localized: "Forest")
        case .cerrado: String(localized: "Cerrado")
        case .swamp: String(localized: "Swamp")
        case .mountain: String(localized: "Mountain")
        case .plains: String(localized: "Plains")
        }
    }
}

enum NativeRegionConflictMode: String, Codable, CaseIterable, Identifiable, Hashable {
    case contestedBorder = "contested-border"
    case conventionalOccupation = "conventional-occupation"
    case guerrillaControl = "guerrilla-control"
    case nuclearFallout = "nuclear-fallout"
    case stabilization

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .contestedBorder:
            String(localized: "Contested border")
        case .conventionalOccupation:
            String(localized: "Conventional occupation")
        case .guerrillaControl:
            String(localized: "Guerrilla control")
        case .nuclearFallout:
            String(localized: "Nuclear fallout")
        case .stabilization:
            String(localized: "Stabilization corridor")
        }
    }
}

/// Region-level conflict metadata used by the native strategic map.
///
/// `regionOccupations` and `nuclearFalloutRegions` remain the compact legacy
/// rendering indexes. This richer record explains why a region is drawn as
/// occupied, contested, insurgent-held, or devastated so future prompts and UI
/// can reason about the state without inferring too much from color alone.
struct NativeRegionConflictState: Codable, Hashable, Identifiable {
    var controllerCode: String
    var intensity: Int
    var mode: NativeRegionConflictMode
    var originalCountryCode: String
    var rebelDelta: Double
    var regionID: String
    var securityDelta: Double
    var sourceEventID: String
    var summary: String
    var updatedAt: String

    var id: String {
        regionID
    }

    init(
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

    static func countryCode(fromLegacyRegionID regionID: String) -> String {
        let prefix = regionID.split(separator: "_").first.map(String.init) ?? regionID
        return prefix.isEmpty ? regionID : prefix
    }
}

enum NativeAIDoctrine: String, Codable, CaseIterable, Identifiable, Hashable {
    case mercantile
    case expansionist
    case isolationist
    case defensive
    case collaborative

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .mercantile: String(localized: "Mercantile")
        case .expansionist: String(localized: "Expansionist")
        case .isolationist: String(localized: "Isolationist")
        case .defensive: String(localized: "Defensive")
        case .collaborative: String(localized: "Collaborative")
        }
    }
}

enum NativeAIBudgetPriority: String, Codable, CaseIterable, Identifiable, Hashable {
    case growth
    case stability
    case military
    case diplomacy

    var id: String {
        rawValue
    }
}

/// **Tech Tree Eras (#7)**: progressive research eras unlocked by accumulating
/// research points. Each era grants a per-turn real-growth bonus and raises the
/// research threshold required to reach the next era.
enum NativeTechEra: String, Codable, CaseIterable, Identifiable, Hashable {
    case industrial
    case digital
    case aiAge = "ai-age"
    case biotech
    case cleanEnergy = "clean-energy"

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .industrial: String(localized: "Industrial")
        case .digital: String(localized: "Digital")
        case .aiAge: String(localized: "AI Age")
        case .biotech: String(localized: "Biotech")
        case .cleanEnergy: String(localized: "Clean Energy")
        }
    }

    /// 0-based position in the progression ladder.
    var index: Int {
        switch self {
        case .industrial: 0
        case .digital: 1
        case .aiAge: 2
        case .biotech: 3
        case .cleanEnergy: 4
        }
    }

    /// Ordered progression from earliest to most advanced era.
    static let progression: [NativeTechEra] = [.industrial, .digital, .aiAge, .biotech, .cleanEnergy]

    var next: NativeTechEra? {
        let nextIndex = index + 1
        guard Self.progression.indices.contains(nextIndex) else { return nil }
        return Self.progression[nextIndex]
    }

    /// Per-turn real-growth bonus (percentage points) granted by this era.
    var growthBonus: Double {
        switch self {
        case .industrial: 0.0
        case .digital: 0.5
        case .aiAge: 1.0
        case .biotech: 1.5
        case .cleanEnergy: 2.0
        }
    }

    /// Total research points required to advance from this era into the next.
    /// Follows the `100 * targetEraIndex` ladder (digital=100, aiAge=200, ...).
    var researchThreshold: Int {
        100 * (index + 1)
    }

    /// Safely constructs an era from a raw string, falling back to industrial.
    static func from(_ raw: String?) -> NativeTechEra {
        NativeTechEra(rawValue: raw ?? "") ?? .industrial
    }
}

/// Intelligence visibility level for fog of war.
/// Determines what economic/diplomatic data the player can see for each country.
enum NativeIntelVisibility: String, Codable, Hashable {
    /// Ally or player — full ledger, relationships, doctrines visible
    case full
    /// Neutral — GDP, stability visible; detailed entries hidden
    case partial
    /// Rival — only name and flag; all data masked as CLASSIFIED
    case hidden

    var displayName: String {
        switch self {
        case .full: "Full Intelligence"
        case .partial: "Partial Intelligence"
        case .hidden: "Intelligence Gap"
        }
    }
}

enum NativeCountryLifecycle: String, Codable, Hashable {
    case active
    case merged
    case dissolved
    case collapsed

    var isActive: Bool {
        self == .active
    }
}

enum NativeCountrySimulationTier: String, Codable, Hashable {
    case background
    case relevant
    case headline
}

struct NativeCountryFactionPressure: Codable, Hashable {
    var institutions: Int
    var military: Int
    var regional: Int
    var labor: Int

    init(institutions: Int = 50, military: Int = 50, regional: Int = 50, labor: Int = 50) {
        self.institutions = Swift.max(0, Swift.min(100, institutions))
        self.military = Swift.max(0, Swift.min(100, military))
        self.regional = Swift.max(0, Swift.min(100, regional))
        self.labor = Swift.max(0, Swift.min(100, labor))
    }
}

enum NativeDiplomaticPosture: String, Codable, Hashable {
    case hostile
    case wary
    case neutral
    case cooperative
    case allied
}

struct NativeDiplomaticRelation: Codable, Hashable, Identifiable {
    var sourceCode: String
    var targetCode: String
    var trust: Int
    var threat: Int
    var tradeDependence: Int
    var posture: NativeDiplomaticPosture
    var lastInteractionRound: Int
    var grievances: [String]

    var id: String {
        "\(sourceCode)->\(targetCode)"
    }

    init(
        sourceCode: String,
        targetCode: String,
        trust: Int = 0,
        threat: Int = 0,
        tradeDependence: Int = 0,
        posture: NativeDiplomaticPosture = .neutral,
        lastInteractionRound: Int = 0,
        grievances: [String] = []
    ) {
        self.sourceCode = sourceCode
        self.targetCode = targetCode
        self.trust = Swift.max(-100, Swift.min(100, trust))
        self.threat = Swift.max(0, Swift.min(100, threat))
        self.tradeDependence = Swift.max(0, Swift.min(100, tradeDependence))
        self.posture = posture
        self.lastInteractionRound = Swift.max(0, lastInteractionRound)
        self.grievances = Array(grievances.prefix(8))
    }
}

enum NativeCountryOutcomeCausality: String, Codable, Hashable {
    case autonomous
    case playerInfluenced
    case systemic
}

enum NativeCountryOutcomePromotion: String, Codable, Hashable {
    case background
    case relevant
    case headline
}

struct NativeCountryTurnOutcome: Codable, Hashable, Identifiable {
    var id: String
    var countryCode: String
    var date: String
    var round: Int
    var actionTitle: String
    var actionDescription: String
    var actionKind: String
    var matrixRow: Int
    var matrixColumn: Int
    var effectTarget: String
    var strategicEffects: [NativeStrategicEffect]
    var relationshipDeltas: [String: Int]
    var causality: NativeCountryOutcomeCausality
    var promotion: NativeCountryOutcomePromotion
    var playerRelated: Bool
    var sovereigntyChange: NativeSovereigntyChange?
    var linkedEventID: String?

    init(
        id: String,
        countryCode: String,
        date: String,
        round: Int,
        actionTitle: String,
        actionDescription: String,
        actionKind: String,
        matrixRow: Int,
        matrixColumn: Int,
        effectTarget: String,
        strategicEffects: [NativeStrategicEffect],
        relationshipDeltas: [String: Int] = [:],
        causality: NativeCountryOutcomeCausality = .autonomous,
        promotion: NativeCountryOutcomePromotion = .background,
        playerRelated: Bool = false,
        sovereigntyChange: NativeSovereigntyChange? = nil,
        linkedEventID: String? = nil
    ) {
        self.id = id
        self.countryCode = countryCode
        self.date = date
        self.round = round
        self.actionTitle = actionTitle
        self.actionDescription = actionDescription
        self.actionKind = actionKind
        self.matrixRow = matrixRow
        self.matrixColumn = matrixColumn
        self.effectTarget = effectTarget
        self.strategicEffects = strategicEffects
        self.relationshipDeltas = relationshipDeltas
        self.causality = causality
        self.promotion = promotion
        self.playerRelated = playerRelated
        self.sovereigntyChange = sovereigntyChange
        self.linkedEventID = linkedEventID
    }
}

/// An inter-nation diplomatic dispatch generated by an LLM rival AI agent.
struct NativeAIDispatch: Codable, Hashable, Identifiable {
    var id: String
    var senderCode: String
    var recipientCode: String
    var message: String
    var tone: String
    var timestamp: String
    var isIntercepted: Bool

    init(
        id: String = UUID().uuidString,
        senderCode: String,
        recipientCode: String,
        message: String,
        tone: String = "diplomatic",
        timestamp: String = "",
        isIntercepted: Bool = true
    ) {
        self.id = id
        self.senderCode = senderCode
        self.recipientCode = recipientCode
        self.message = message
        self.tone = tone
        self.timestamp = timestamp
        self.isIntercepted = isIntercepted
    }
}

/// A structured turn action emitted by an LLM-driven rival AI agent.
struct NativeRivalAgentTurn: Codable, Hashable, Identifiable {
    var id: String {
        actorCode
    }

    var actorCode: String
    var targetCode: String?
    var intent: String
    var narrativeSummary: String
    var hexLeverCode: String?
    var dispatches: [NativeAIDispatch]

    init(
        actorCode: String,
        targetCode: String? = nil,
        intent: String = "diplomatic",
        narrativeSummary: String = "",
        hexLeverCode: String? = nil,
        dispatches: [NativeAIDispatch] = []
    ) {
        self.actorCode = actorCode
        self.targetCode = targetCode
        self.intent = intent
        self.narrativeSummary = narrativeSummary
        self.hexLeverCode = hexLeverCode
        self.dispatches = dispatches
    }
}

struct NativeAICountryState: Codable, Hashable, Identifiable {
    var countryCode: String
    var doctrine: NativeAIDoctrine
    var budgetPriority: NativeAIBudgetPriority
    var relationshipScores: [String: Int] // target -> score (-100 to 100)
    var multiTurnAgenda: String
    var agendaProgress: Int // 0 to 100
    /// Stable 12-bit policy profile (0...4095) selected from the country's seed.
    var decisionProfileID: Int
    /// Independent deterministic stream for this country inside the campaign.
    var decisionSeed: UInt64
    /// Advances after each autonomous choice without coupling countries together.
    var decisionStep: Int
    /// Summary of the last autonomous action taken by this country.
    var lastAIActionSummary: String
    /// How many turns since this country last received a visible decision.
    var turnsSinceAIAction: Int
    /// Long-horizon rival victory progress earned by completing in-campaign
    /// strategic agendas while every active scenario objective is satisfied.
    /// Opening strength alone never advances this meter.
    var rivalCampaignProgress: Double
    var lifecycle: NativeCountryLifecycle
    var successorCode: String?
    var lifecycleDate: String?
    var simulationTier: NativeCountrySimulationTier
    var factionPressure: NativeCountryFactionPressure
    var lastOutcomeID: String?

    var id: String {
        countryCode
    }

    private enum CodingKeys: String, CodingKey {
        case countryCode, doctrine, budgetPriority, relationshipScores
        case multiTurnAgenda, agendaProgress, decisionProfileID, decisionSeed, decisionStep
        case lastAIActionSummary, turnsSinceAIAction, rivalCampaignProgress
        case lifecycle, successorCode, lifecycleDate, simulationTier, factionPressure, lastOutcomeID
    }

    init(
        countryCode: String,
        doctrine: NativeAIDoctrine,
        budgetPriority: NativeAIBudgetPriority,
        relationshipScores: [String: Int],
        multiTurnAgenda: String,
        agendaProgress: Int,
        decisionProfileID: Int = -1,
        decisionSeed: UInt64 = 0,
        decisionStep: Int = 0,
        lastAIActionSummary: String = "",
        turnsSinceAIAction: Int = 0,
        rivalCampaignProgress: Double = 0,
        lifecycle: NativeCountryLifecycle = .active,
        successorCode: String? = nil,
        lifecycleDate: String? = nil,
        simulationTier: NativeCountrySimulationTier = .background,
        factionPressure: NativeCountryFactionPressure = NativeCountryFactionPressure(),
        lastOutcomeID: String? = nil
    ) {
        self.countryCode = countryCode
        self.doctrine = doctrine
        self.budgetPriority = budgetPriority
        self.relationshipScores = relationshipScores
        self.multiTurnAgenda = multiTurnAgenda
        self.agendaProgress = agendaProgress
        self.decisionProfileID = max(-1, min(4095, decisionProfileID))
        self.decisionSeed = decisionSeed
        self.decisionStep = max(0, decisionStep)
        self.lastAIActionSummary = lastAIActionSummary
        self.turnsSinceAIAction = turnsSinceAIAction
        self.rivalCampaignProgress = max(0, min(100, rivalCampaignProgress.isFinite ? rivalCampaignProgress : 0))
        self.lifecycle = lifecycle
        self.successorCode = successorCode
        self.lifecycleDate = lifecycleDate
        self.simulationTier = simulationTier
        self.factionPressure = factionPressure
        self.lastOutcomeID = lastOutcomeID
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        countryCode = (try? c.decodeIfPresent(String.self, forKey: .countryCode)) ?? ""
        doctrine = (try? c.decodeIfPresent(NativeAIDoctrine.self, forKey: .doctrine)) ?? .isolationist
        budgetPriority = (try? c.decodeIfPresent(NativeAIBudgetPriority.self, forKey: .budgetPriority)) ?? .growth
        relationshipScores = (try? c.decodeIfPresent([String: Int].self, forKey: .relationshipScores)) ?? [:]
        multiTurnAgenda = (try? c.decodeIfPresent(String.self, forKey: .multiTurnAgenda)) ?? ""
        agendaProgress = (try? c.decodeIfPresent(Int.self, forKey: .agendaProgress)) ?? 0
        decisionProfileID = max(-1, min(4095, (try? c.decodeIfPresent(Int.self, forKey: .decisionProfileID)) ?? -1))
        decisionSeed = (try? c.decodeIfPresent(UInt64.self, forKey: .decisionSeed)) ?? 0
        decisionStep = max(0, (try? c.decodeIfPresent(Int.self, forKey: .decisionStep)) ?? 0)
        lastAIActionSummary = (try? c.decodeIfPresent(String.self, forKey: .lastAIActionSummary)) ?? ""
        turnsSinceAIAction = (try? c.decodeIfPresent(Int.self, forKey: .turnsSinceAIAction)) ?? 0
        let decodedRivalProgress = (try? c.decodeIfPresent(Double.self, forKey: .rivalCampaignProgress)) ?? 0
        rivalCampaignProgress = max(0, min(100, decodedRivalProgress.isFinite ? decodedRivalProgress : 0))
        lifecycle = (try? c.decodeIfPresent(NativeCountryLifecycle.self, forKey: .lifecycle)) ?? .active
        successorCode = try? c.decodeIfPresent(String.self, forKey: .successorCode)
        lifecycleDate = try? c.decodeIfPresent(String.self, forKey: .lifecycleDate)
        simulationTier = (try? c.decodeIfPresent(NativeCountrySimulationTier.self, forKey: .simulationTier)) ?? .background
        factionPressure = (try? c.decodeIfPresent(NativeCountryFactionPressure.self, forKey: .factionPressure)) ?? NativeCountryFactionPressure()
        lastOutcomeID = try? c.decodeIfPresent(String.self, forKey: .lastOutcomeID)
    }
}

enum NativeSovereigntyChangeKind: String, Codable, Hashable {
    case dissolution
    case merge
    case newCountry = "new-country"
    case secession
}

struct NativeSovereigntyChange: Codable, Hashable {
    var kind: NativeSovereigntyChangeKind
    var name: String
    var regionIDs: [String]
    var sourceCodes: [String]
    var targetCode: String

    init(
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

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawKind = (try? container.decodeIfPresent(String.self, forKey: .kind)) ?? ""
        kind = NativeSovereigntyChangeKind(rawValue: rawKind) ?? .secession
        name = (try? container.decodeIfPresent(String.self, forKey: .name)) ?? ""
        regionIDs = (try? container.decodeIfPresent([String].self, forKey: .regionIDs)) ?? []
        sourceCodes = (try? container.decodeIfPresent([String].self, forKey: .sourceCodes)) ?? []
        targetCode = (try? container.decodeIfPresent(String.self, forKey: .targetCode)) ?? ""
    }
}

struct NativeSemanticMemory: Codable, Hashable, Identifiable {
    var date: String
    var embedding: [Float]
    var id: String
    var importance: Int
    var sourceID: String
    var text: String
    var track: NativeStrategicTrack
}

struct NativeCampaignObjective: Hashable, Identifiable {
    var currentValue: String
    var detail: String
    var deadline: String
    var id: String
    var isComplete: Bool
    var progress: Double
    var targetValue: String
    var title: String
}

struct NativeDirectivePreview: Hashable {
    var capacityAfter: Int
    var cost: Int
    var expectedEffects: [String]
    var riskLabel: String
    var warning: String?
}

struct NativeAfterActionMetric: Hashable, Identifiable {
    var delta: String
    var id: String
    var label: String
    var value: String
}

struct NativeAfterActionReport: Hashable {
    var events: [NativeCampaignEvent]
    var metrics: [NativeAfterActionMetric]
    var resolvedOrderCount: Int
    var summary: String
}

/// The complete persisted native campaign snapshot.
///
/// This type is intentionally tolerant when decoding: old saves may be missing
/// newer systems such as action memory, economic ledgers, diplomacy, or
/// language. Add new fields with defaults in `init(from:)` so existing campaign
/// files remain loadable.
struct NativeCampaignState: Codable, Hashable {
    var actionMemory: [NativeActionMemory]
    var advisorMessages: [NativeAdvisorMessage]
    var aiReadiness: NativeAIReadiness
    var country: PlayerCountry
    var diplomaticThreads: [NativeDiplomaticThread]
    var dynamicCountries: [String: String]
    var economicLedger: NativeEconomicLedger
    var economicLedgers: [String: NativeEconomicLedger]
    var aiCountryStates: [String: NativeAICountryState]

    var gameDate: String
    var gameMode: NativeGameMode
    /// Campaign-wide immutable seed. Country streams and turn seeds derive from it.
    var worldSeed: UInt64
    var lastSummary: String
    var language: NativeGameLanguage
    var plannedActions: [NativePlannedAction]
    var round: Int
    var scenarioDescription: String
    var scenarioID: String
    var scenarioName: String
    var semanticMemory: [NativeSemanticMemory]
    var suggestedActions: [NativeSuggestedAction]
    var stability: Int
    var startDate: String
    var timeline: [NativeCampaignEvent]
    var worldTension: Int
    var worldEffects: [NativeStrategicEffect]
    var regionOccupations: [String: String]
    var nuclearFalloutRegions: [String]
    var regionConflicts: [String: NativeRegionConflictState]
    var mapArmies: [NativeArmySnapshot]
    var mapBuildings: [NativeBuildingSnapshot]

    // New Grand Strategy Layer fields
    var administrativeCapacity: Int
    var victoryStatus: NativeVictoryStatus
    /// Stable attribution for a latched rival defeat. This prevents overlays
    /// and restored saves from guessing the winner from later state.
    var rivalVictoryCountryCode: String?
    var activeOffers: [NativeDiplomaticOffer]
    var budgetMilitarySlider: Double
    var budgetServicesSlider: Double
    var budgetDiplomacySlider: Double

    // Tech Tree (#7): research progression. `techEra` stores the raw era value
    // (see NativeTechEra) and `researchPoints` accumulates toward the next era.
    var techEra: String
    var researchPoints: Int
    /// Research budget allocation (0-1). Independent of the military/services/
    /// diplomacy revenue split, so it does not participate in their 100% rebalance.
    var budgetResearchSlider: Double

    // Military Units (#8): standing forces for the player's country.
    // Keys: "infantry", "armor", "air", "naval". Values = unit counts.
    var militaryUnits: [String: Int]

    init(
        actionMemory: [NativeActionMemory] = [],
        advisorMessages: [NativeAdvisorMessage] = [],
        aiReadiness: NativeAIReadiness,
        country: PlayerCountry,
        diplomaticThreads: [NativeDiplomaticThread] = [],
        dynamicCountries: [String: String] = [:],
        economicLedger: NativeEconomicLedger? = nil,
        economicLedgers: [String: NativeEconomicLedger]? = nil,
        aiCountryStates: [String: NativeAICountryState]? = nil,
        gameDate: String,
        gameMode: NativeGameMode = .normal,
        worldSeed: UInt64 = 0,
        lastSummary: String,
        language: NativeGameLanguage = .english,
        plannedActions: [NativePlannedAction],
        round: Int,
        scenarioDescription: String,
        scenarioID: String,
        scenarioName: String,
        semanticMemory: [NativeSemanticMemory] = [],
        suggestedActions: [NativeSuggestedAction],
        stability: Int,
        startDate: String,
        timeline: [NativeCampaignEvent],
        worldTension: Int,
        worldEffects: [NativeStrategicEffect],
        regionOccupations: [String: String] = [:],
        nuclearFalloutRegions: [String] = [],
        regionConflicts: [String: NativeRegionConflictState] = [:],
        mapArmies: [NativeArmySnapshot] = [],
        mapBuildings: [NativeBuildingSnapshot] = [],
        administrativeCapacity: Int = 100,
        victoryStatus: NativeVictoryStatus = .ongoing,
        rivalVictoryCountryCode: String? = nil,
        activeOffers: [NativeDiplomaticOffer] = [],
        budgetMilitarySlider: Double = 0.33,
        budgetServicesSlider: Double = 0.34,
        budgetDiplomacySlider: Double = 0.33,
        techEra: String = NativeTechEra.industrial.rawValue,
        researchPoints: Int = 0,
        budgetResearchSlider: Double = 0.15,
        militaryUnits: [String: Int]? = nil
    ) {
        self.actionMemory = actionMemory
        self.advisorMessages = advisorMessages
        self.aiReadiness = aiReadiness
        self.country = country
        self.diplomaticThreads = diplomaticThreads
        self.dynamicCountries = dynamicCountries
        let computedEconomicLedger = economicLedger ?? NativeEconomicLedger.starting(
            for: country,
            scenario: NativeScenarioCatalog.scenario(for: scenarioID)
        )
        self.economicLedger = computedEconomicLedger
        if let economicLedgers {
            self.economicLedgers = economicLedgers
        } else {
            var ledgers: [String: NativeEconomicLedger] = [:]
            ledgers[country.code] = computedEconomicLedger
            let scenarioObj = NativeScenarioCatalog.scenario(for: scenarioID)
            for code in NativeStrategyContextDatabase.defaultStrategicCountryCodes where code != country.code {
                ledgers[code] = NativeStrategyContextDatabase.startingEconomicLedger(forCode: code, scenario: scenarioObj)
            }
            self.economicLedgers = ledgers
        }
        self.aiCountryStates = aiCountryStates ?? [:]
        self.gameDate = gameDate
        self.gameMode = gameMode
        self.worldSeed = worldSeed
        self.lastSummary = lastSummary
        self.language = language
        self.plannedActions = plannedActions
        self.round = round
        self.scenarioDescription = scenarioDescription
        self.scenarioID = scenarioID
        self.scenarioName = scenarioName
        self.semanticMemory = semanticMemory
        self.suggestedActions = suggestedActions
        self.stability = stability
        self.startDate = startDate
        self.timeline = timeline
        self.worldTension = worldTension
        self.worldEffects = worldEffects
        self.regionOccupations = regionOccupations
        self.nuclearFalloutRegions = nuclearFalloutRegions
        self.regionConflicts = regionConflicts
        self.mapArmies = mapArmies
        self.mapBuildings = mapBuildings
        self.administrativeCapacity = administrativeCapacity
        self.victoryStatus = victoryStatus
        self.rivalVictoryCountryCode = rivalVictoryCountryCode
        self.activeOffers = activeOffers
        self.budgetMilitarySlider = budgetMilitarySlider
        self.budgetServicesSlider = budgetServicesSlider
        self.budgetDiplomacySlider = budgetDiplomacySlider
        self.techEra = NativeTechEra.from(techEra).rawValue
        self.researchPoints = max(0, researchPoints)
        self.budgetResearchSlider = min(1.0, max(0.0, budgetResearchSlider.isFinite ? budgetResearchSlider : 0.15))
        self.militaryUnits = militaryUnits ?? Self.defaultMilitaryUnits(forCode: country.code)
    }

    private enum CodingKeys: String, CodingKey {
        case actionMemory
        case advisorMessages
        case aiReadiness
        case country
        case diplomaticThreads
        case dynamicCountries
        case economicLedger
        case economicLedgers
        case aiCountryStates
        case gameDate
        case gameMode
        case worldSeed
        case lastSummary
        case language
        case plannedActions
        case round
        case scenarioDescription
        case scenarioID
        case scenarioName
        case semanticMemory
        case suggestedActions
        case stability
        case startDate
        case timeline
        case worldTension
        case worldEffects
        case regionOccupations
        case nuclearFalloutRegions
        case regionConflicts
        case mapArmies
        case mapBuildings
        case administrativeCapacity
        case victoryStatus
        case rivalVictoryCountryCode
        case activeOffers
        case budgetMilitarySlider
        case budgetServicesSlider
        case budgetDiplomacySlider
        case techEra
        case researchPoints
        case budgetResearchSlider
        case militaryUnits
    }

    /// **Schema Normalization Mechanic**:
    /// Tolerant decoding ensures old save files never break when new features are added.
    /// If a field (e.g. diplomacy, AI states, sliders) is missing in an old save,
    /// the decoder injects safe defaults or derives them from the scenario.
    /// The `normalizedLoadedState` in `NativeCampaignStore` further sanitizes the data
    /// to remove AI placeholders and clamp bounds.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        advisorMessages = Self.decodeLossyArray(NativeAdvisorMessage.self, from: container, forKey: .advisorMessages)
        aiReadiness = (try? container.decodeIfPresent(NativeAIReadiness.self, forKey: .aiReadiness)) ?? .notChecked
        country = try container.decode(PlayerCountry.self, forKey: .country)
        diplomaticThreads = Self.decodeLossyArray(NativeDiplomaticThread.self, from: container, forKey: .diplomaticThreads)
        dynamicCountries = (try? container.decodeIfPresent([String: String].self, forKey: .dynamicCountries)) ?? [:]
        scenarioID = (try? container.decodeIfPresent(String.self, forKey: .scenarioID)) ?? NativeScenarioCatalog.defaultScenario.id
        let decodedScenario = NativeScenarioCatalog.scenario(for: scenarioID)
        actionMemory = Self.decodeLossyArray(NativeActionMemory.self, from: container, forKey: .actionMemory)
        let decodedLedger = (try? container.decodeIfPresent(NativeEconomicLedger.self, forKey: .economicLedger)) ?? NativeEconomicLedger.starting(for: country, scenario: decodedScenario)
        economicLedger = decodedLedger
        var ledgers = (try? container.decodeIfPresent([String: NativeEconomicLedger].self, forKey: .economicLedgers)) ?? [:]
        if ledgers.isEmpty {
            ledgers[country.code] = decodedLedger
            for code in NativeStrategyContextDatabase.defaultStrategicCountryCodes where code != country.code {
                ledgers[code] = NativeStrategyContextDatabase.startingEconomicLedger(forCode: code, scenario: decodedScenario)
            }
        }
        economicLedgers = ledgers
        aiCountryStates = (try? container.decodeIfPresent([String: NativeAICountryState].self, forKey: .aiCountryStates)) ?? [:]
        regionOccupations = (try? container.decodeIfPresent([String: String].self, forKey: .regionOccupations)) ?? [:]
        nuclearFalloutRegions = (try? container.decodeIfPresent([String].self, forKey: .nuclearFalloutRegions)) ?? []
        regionConflicts = (try? container.decodeIfPresent([String: NativeRegionConflictState].self, forKey: .regionConflicts)) ?? [:]
        mapArmies = Self.decodeLossyArray(NativeArmySnapshot.self, from: container, forKey: .mapArmies)
        mapBuildings = Self.decodeLossyArray(NativeBuildingSnapshot.self, from: container, forKey: .mapBuildings)
        if regionConflicts.isEmpty {
            regionConflicts = Self.conflictsFromLegacyMapState(
                occupations: regionOccupations,
                falloutRegions: nuclearFalloutRegions
            )
        }
        gameDate = (try? container.decodeIfPresent(String.self, forKey: .gameDate)) ?? decodedScenario.gameDate
        gameMode = (try? container.decodeIfPresent(NativeGameMode.self, forKey: .gameMode)) ?? .normal
        worldSeed = (try? container.decodeIfPresent(UInt64.self, forKey: .worldSeed)) ?? 0
        lastSummary = (try? container.decodeIfPresent(String.self, forKey: .lastSummary)) ?? "\(decodedScenario.openingSummary) \(country.name) needs to turn intent into concrete plans."
        language = NativeGameLanguage.normalized(try? container.decodeIfPresent(String.self, forKey: .language))
        plannedActions = Self.decodeLossyArray(NativePlannedAction.self, from: container, forKey: .plannedActions)
        round = (try? container.decodeIfPresent(Int.self, forKey: .round)) ?? 1
        scenarioName = (try? container.decodeIfPresent(String.self, forKey: .scenarioName)) ?? decodedScenario.name
        scenarioDescription = (try? container.decodeIfPresent(String.self, forKey: .scenarioDescription)) ?? decodedScenario.heroSubtitle
        semanticMemory = Self.decodeLossyArray(NativeSemanticMemory.self, from: container, forKey: .semanticMemory)
        suggestedActions = Self.decodeLossyArray(NativeSuggestedAction.self, from: container, forKey: .suggestedActions)
        stability = (try? container.decodeIfPresent(Int.self, forKey: .stability)) ?? decodedScenario.baseStability
        startDate = (try? container.decodeIfPresent(String.self, forKey: .startDate)) ?? decodedScenario.startDate
        timeline = Self.decodeLossyArray(NativeCampaignEvent.self, from: container, forKey: .timeline)
        worldTension = (try? container.decodeIfPresent(Int.self, forKey: .worldTension)) ?? decodedScenario.baseWorldTension
        worldEffects = Self.decodeLossyArray(NativeStrategicEffect.self, from: container, forKey: .worldEffects)

        // Decoding new fields with defaults
        administrativeCapacity = (try? container.decodeIfPresent(Int.self, forKey: .administrativeCapacity)) ?? 100
        victoryStatus = (try? container.decodeIfPresent(NativeVictoryStatus.self, forKey: .victoryStatus)) ?? .ongoing
        rivalVictoryCountryCode = try? container.decodeIfPresent(String.self, forKey: .rivalVictoryCountryCode)
        activeOffers = Self.decodeLossyArray(NativeDiplomaticOffer.self, from: container, forKey: .activeOffers)
        budgetMilitarySlider = (try? container.decodeIfPresent(Double.self, forKey: .budgetMilitarySlider)) ?? 0.33
        budgetServicesSlider = (try? container.decodeIfPresent(Double.self, forKey: .budgetServicesSlider)) ?? 0.34
        budgetDiplomacySlider = (try? container.decodeIfPresent(Double.self, forKey: .budgetDiplomacySlider)) ?? 0.33
        // Tech Tree (#7) & Military Units (#8): tolerant decoding for old saves.
        techEra = NativeTechEra.from(try? container.decodeIfPresent(String.self, forKey: .techEra)).rawValue
        researchPoints = (try? container.decodeIfPresent(Int.self, forKey: .researchPoints)) ?? 0
        let decodedResearchSlider = (try? container.decodeIfPresent(Double.self, forKey: .budgetResearchSlider)) ?? 0.15
        budgetResearchSlider = (decodedResearchSlider.isFinite && decodedResearchSlider >= 0 && decodedResearchSlider <= 1) ? decodedResearchSlider : 0.15
        let decodedUnits = (try? container.decodeIfPresent([String: Int].self, forKey: .militaryUnits)) ?? [:]
        militaryUnits = decodedUnits.isEmpty ? Self.defaultMilitaryUnits(forCode: country.code) : decodedUnits
    }

    private static func decodeLossyArray<Element: Decodable>(
        _: Element.Type,
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) -> [Element] {
        (try? container.decodeIfPresent(LossyDecodableArray<Element>.self, forKey: key)?.elements) ?? []
    }

    /// **Military Units (#8)**: starting force composition biased by country.
    /// Recognized military powers receive large standing armies; regional powers
    /// a modest force; all others a small defensive garrison.
    static func defaultMilitaryUnits(forCode code: String) -> [String: Int] {
        let profile = Native2010WorldModel.profile(for: PlayerCountry(code: code, name: code))
        let gdp = profile.nominalGDPTrillions
        let spend = profile.militarySpendingPercent
        let corruption = profile.corruptionIndex

        let milSpendCoeff = spend / 2.0
        let corruptionCoeff = 1.0 - (Double(corruption) / 100.0) * 0.6
        let mpi = gdp * milSpendCoeff * corruptionCoeff

        let total = min(150, max(12, Int((mpi * 4.0).rounded()) + 15))

        let infantry = Int(Double(total) * 0.50)
        let armor = Int(Double(total) * 0.25)
        let air = Int(Double(total) * 0.15)
        let naval = max(0, total - infantry - armor - air)

        return ["infantry": infantry, "armor": armor, "air": air, "naval": naval]
    }

    /// Convenience typed accessor for the current tech era.
    var techEraTyped: NativeTechEra {
        get { NativeTechEra.from(techEra) }
        set { techEra = newValue.rawValue }
    }

    private static func conflictsFromLegacyMapState(
        occupations: [String: String],
        falloutRegions: [String]
    ) -> [String: NativeRegionConflictState] {
        var conflicts: [String: NativeRegionConflictState] = [:]
        for (regionID, controllerCode) in occupations {
            let originalCode = NativeRegionConflictState.countryCode(fromLegacyRegionID: regionID)
            let mode: NativeRegionConflictMode = controllerCode == "REB" ? .guerrillaControl : .conventionalOccupation
            conflicts[regionID] = NativeRegionConflictState(
                controllerCode: controllerCode,
                intensity: controllerCode == "REB" ? 4 : 3,
                mode: mode,
                originalCountryCode: originalCode,
                regionID: regionID,
                summary: "Recovered from legacy occupation map state."
            )
        }
        for regionID in falloutRegions {
            let originalCode = NativeRegionConflictState.countryCode(fromLegacyRegionID: regionID)
            conflicts[regionID] = NativeRegionConflictState(
                controllerCode: occupations[regionID] ?? originalCode,
                intensity: 5,
                mode: .nuclearFallout,
                originalCountryCode: originalCode,
                regionID: regionID,
                summary: "Recovered from legacy nuclear fallout map state."
            )
        }
        return conflicts
    }
}

private struct LossyDecodableArray<Element: Decodable>: Decodable {
    let elements: [Element]

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var decoded: [Element] = []
        while !container.isAtEnd {
            if let element = try? container.decode(Element.self) {
                decoded.append(element)
            } else {
                _ = try? container.decode(DiscardedDecodableValue.self)
            }
        }
        elements = decoded
    }
}

private struct DiscardedDecodableValue: Decodable {}

/// User-facing language selection plus the prompt instruction used by native
/// AI generation. Keep schema keys and identifiers out of translation; only
/// player-visible prose should follow this value.
enum NativeGameLanguage: String, Codable, CaseIterable, Hashable, Identifiable {
    case english = "English"
    case portuguese = "Portuguese"
    case spanish = "Spanish"

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .english:
            "English"
        case .portuguese:
            "Português"
        case .spanish:
            "Español"
        }
    }

    var responseLanguageName: String {
        switch self {
        case .english:
            "English"
        case .portuguese:
            "Portuguese (Brazilian Portuguese)"
        case .spanish:
            "Spanish"
        }
    }

    var promptInstruction: String {
        "Response language: \(responseLanguageName). Write all player-facing prose in \(responseLanguageName). Keep schema field names, enum values, identifiers, IDs, dates, and game tokens exactly as requested."
    }

    static func normalized(_ value: String?) -> NativeGameLanguage {
        let raw = sanitizeFoundationModelText(value ?? "")
        let folded = raw
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
            .replacingOccurrences(of: "(", with: " ")
            .replacingOccurrences(of: ")", with: " ")
        let key = folded.split(separator: " ").joined(separator: " ")

        switch key {
        case "en", "english", "ingles":
            return .english
        case "pt", "pt-br", "portugues", "portuguese", "portugues brasil", "portugues brasileiro", "portuguese brazilian", "brazilian portuguese":
            return .portuguese
        case "es", "espanhol", "espanol", "spanish", "castellano":
            return .spanish
        default:
            return .english
        }
    }
}

/// Localized telemetry ticker lines for the turn-transition overlay.
/// Same contract as `LWProse`: in-code tables keyed by `NativeGameLanguage`,
/// NOT `String(localized:)` — xcstrings resolves from the device locale, while
/// the campaign save carries its own language and the ticker must match the
/// campaign's prose. English fallback; every column stays aligned line-for-line
/// so `.shuffled().prefix(8)` variety is identical across languages.
enum TurnTickerProse {
    private static let lines: [(en: String, pt: String, es: String)] = [
        ("Rebuilding regional intelligence networks...", "Reconstruindo redes de inteligência regional...", "Reconstruyendo redes de inteligencia regional..."),
        ("Calibrating fiscal indicators against the outlook...", "Calibrando indicadores fiscais contra o cenário...", "Calibrando indicadores fiscales frente al escenario..."),
        ("Synthesizing global diplomatic movements...", "Sintetizando movimentos diplomáticos globais...", "Sintetizando movimientos diplomáticos globales..."),
        ("Assessing insurgent pressure along corridors...", "Avaliando pressão insurgente em corredores...", "Evaluando presión insurgente en corredores..."),
        ("Recalibrating market confidence...", "Recalibrando confiança do mercado...", "Recalibrando la confianza del mercado..."),
        ("Mapping strategic movements...", "Mapeando deslocamentos estratégicos...", "Mapeando desplazamientos estratégicos..."),
        ("Compiling public safety reports...", "Compilando relatórios de segurança pública...", "Compilando informes de seguridad pública..."),
        ("Cross-referencing electoral data with stability...", "Cruzando dados eleitorais com estabilidade...", "Cruzando datos electorales con estabilidad..."),
        ("Processing military logistics heat...", "Processando calor logístico militar...", "Procesando presión logística militar..."),
        ("Analyzing bilateral trade patterns...", "Analisando padrões comerciais bilaterais...", "Analizando patrones comerciales bilaterales..."),
        ("Updating power doctrine profiles...", "Atualizando perfis doutrinários de potências...", "Actualizando perfiles doctrinales de potencias..."),
        ("Measuring diplomatic pressure along borders...", "Medindo pressão diplomática em fronteiras...", "Midiendo presión diplomática en fronteras..."),
        ("Integrating climate data into risk...", "Integrando dados climáticos ao risco...", "Integrando datos climáticos al riesgo..."),
        ("Recalculating public policy impact...", "Recalculando impacto de políticas públicas...", "Recalculando impacto de políticas públicas..."),
        ("Cross-referencing campaign semantic memory...", "Cruzando memória semântica da campanha...", "Cruzando memoria semántica de la campaña..."),
        ("Probing emerging geopolitical alignments...", "Sondando alinhamentos geopolíticos emergentes...", "Sondeando alineamientos geopolíticos emergentes..."),
        ("Assessing institutional collapse risk...", "Avaliando risco de colapso institucional...", "Evaluando riesgo de colapso institucional..."),
        ("Simulating rival power reactions...", "Simulando reações de potências rivais...", "Simulando reacciones de potencias rivales..."),
        ("Weighing fiscal costs of pending decisions...", "Pesando custos fiscais de decisões pendentes...", "Ponderando costos fiscales de decisiones pendientes..."),
        ("Mapping supply chains and logistics impact...", "Mapeando cadeias de suprimento e impacto logístico...", "Mapeando cadenas de suministro e impacto logístico..."),
        ("Auditing regional economic resilience...", "Auditando resiliência econômica regional...", "Auditando resiliencia económica regional..."),
        ("Processing military unit telemetry...", "Processando telemetria de unidades militares...", "Procesando telemetría de unidades militares..."),
        ("Analyzing external recession pressure...", "Analisando pressão de recessão externa...", "Analizando presión de recesión externa..."),
        ("Reviewing the multilateral security agenda...", "Revisando agenda multilateral de segurança...", "Revisando la agenda multilateral de seguridad..."),
        ("Quantifying government collapse risk...", "Quantificando risco de queda de governo...", "Cuantificando riesgo de caída de gobierno..."),
        ("Scanning global doctrine shifts...", "Escaneando mudanças doutrinárias globais...", "Escaneando cambios doctrinales globales..."),
        ("Evaluating political reform effectiveness...", "Avaliando efetividade de reformas políticas...", "Evaluando efectividad de reformas políticas..."),
        ("Measuring commercial sanctions impact...", "Medindo impacto de sanções comerciais...", "Midiendo impacto de sanciones comerciales..."),
        ("Computing sovereignty consequences...", "Computando consequências de soberania...", "Computando consecuencias de soberanía..."),
        ("Integrating allied intelligence packages...", "Integrando pacotes de inteligência aliada...", "Integrando paquetes de inteligencia aliada...")
    ]

    static func quotes(for language: NativeGameLanguage) -> [String] {
        switch language {
        case .english:
            lines.map(\.en)
        case .portuguese:
            lines.map(\.pt)
        case .spanish:
            lines.map(\.es)
        }
    }
}

struct NativeScenario: Codable, Hashable, Identifiable {
    var accentColor: String
    var baseStability: Int
    var baseWorldTension: Int
    var gameDate: String
    var heroSubtitle: String
    var heroTitle: String
    var id: String
    var name: String
    var openingSummary: String
    var startDate: String
    var subtitle: String
}

enum NativeScenarioCatalog {
    static let defaultScenario = NativeScenario(
        accentColor: "#c49a35",
        baseStability: 62,
        baseWorldTension: 48,
        gameDate: "2010-01-15",
        heroSubtitle: "Post-recession recovery, rapid technological growth, and regional alignment of the early 2010s.",
        heroTitle: "Modern Day",
        id: "default",
        name: "Modern Day",
        openingSummary: "The campaign begins in 2010. Real-world challenges include post-crisis economic recovery, rising tech connectivity, and shifting geopolitical power balances.",
        startDate: "2010-01-01",
        subtitle: "Real-world facts starting 2010"
    )

    static let fragmentedMarkets = NativeScenario(
        accentColor: "#4f9f8f",
        baseStability: 54,
        baseWorldTension: 66,
        gameDate: "2032-04-01",
        heroSubtitle: "Regional blocs, volatile trade corridors, and hard budget choices define the opening.",
        heroTitle: "Fragmented Markets",
        id: "fragmented-markets",
        name: "Fragmented Markets",
        openingSummary: "A fractured market order forces the player to convert scarce administrative capacity into trust, access, and leverage.",
        startDate: "2031-01-01",
        subtitle: "Trade friction and coalition management"
    )

    static let resilienceDecade = NativeScenario(
        accentColor: "#5d8fd8",
        baseStability: 70,
        baseWorldTension: 38,
        gameDate: "2040-01-10",
        heroSubtitle: "Adaptation finance, energy reliability, and public-service legitimacy shape a slower strategic game.",
        heroTitle: "Resilience Decade",
        id: "resilience-decade",
        name: "Resilience Decade",
        openingSummary: "The resilience decade rewards patient institution-building, credible delivery, and alliances that can survive stress.",
        startDate: "2038-06-01",
        subtitle: "Long-horizon civic strategy"
    )

    static let sovietTriumph = NativeScenario(
        accentColor: "#df2a2a",
        baseStability: 58,
        baseWorldTension: 75,
        gameDate: "1991-11-07",
        heroSubtitle: "Alternate History Cold War: The Soviet Union achieved hegemony. Collectivized command networks and military pacts dominate.",
        heroTitle: "Soviet Triumph",
        id: "soviet-triumph",
        name: "Soviet Triumph",
        openingSummary: "The Soviet Union stands victorious. Direct collectivized industrial grids or manage containment strategies in a tense bipolar world.",
        startDate: "1991-11-01",
        subtitle: "Bipolar containment and planned hegemony"
    )

    static let paxCybernetica = NativeScenario(
        accentColor: "#a855f7",
        baseStability: 64,
        baseWorldTension: 50,
        gameDate: "2055-08-18",
        heroSubtitle: "Decentralized algorithmic protocols and corporate sovereign networks compete for digital supremacy.",
        heroTitle: "Pax Cybernetica",
        id: "pax-cybernetica",
        name: "Pax Cybernetica",
        openingSummary: "Algorithmic DAOs and automated supply webs govern global trade. Administrative capacity represents server scale.",
        startDate: "2055-01-01",
        subtitle: "Corporate sovereign networks"
    )

    static let solarpunkDawn = NativeScenario(
        accentColor: "#10b981",
        baseStability: 68,
        baseWorldTension: 35,
        gameDate: "2060-03-21",
        heroSubtitle: "Ecological restoration and cooperative bioregions strive for global climatic balance.",
        heroTitle: "Solarpunk Dawn",
        id: "solarpunk-dawn",
        name: "Solarpunk Dawn",
        openingSummary: "Cooperative bioregions focus on climate restoration, local micro-grids, and shared tech resources under resource ceilings.",
        startDate: "2060-01-01",
        subtitle: "Climatic balance and cooperative networks"
    )

    static let dividedSovereignty = NativeScenario(
        accentColor: "#d97706",
        baseStability: 60,
        baseWorldTension: 42,
        gameDate: "1895-06-20",
        heroSubtitle: "Multi-polar imperial balancing, mercantilist spheres, and classic balance-of-power diplomacy.",
        heroTitle: "Divided Sovereignty",
        id: "divided-sovereignty",
        name: "Divided Sovereignty",
        openingSummary: "Direct your empire through balance-of-power alignments, coal concessions, and mercantilist treaty ports.",
        startDate: "1895-01-01",
        subtitle: "Imperial balance and treaty ports"
    )

    static let resourceCrucible = NativeScenario(
        accentColor: "#ea580c",
        baseStability: 48,
        baseWorldTension: 80,
        gameDate: "2035-10-31",
        heroSubtitle: "Critical resource bottlenecks, water security friction, and heavily militarized corridors.",
        heroTitle: "Resource Crucible",
        id: "resource-crucible",
        name: "Resource Crucible",
        openingSummary: "Critical mineral bottlenecks and massive climate migrations challenge state survival as aquifers dry up.",
        startDate: "2035-06-01",
        subtitle: "Resource security and migration corridors"
    )

    static let all: [NativeScenario] = [
        defaultScenario,
        fragmentedMarkets,
        resilienceDecade,
        sovietTriumph,
        paxCybernetica,
        solarpunkDawn,
        dividedSovereignty,
        resourceCrucible
    ]

    static func scenario(for id: String?) -> NativeScenario {
        let normalized = sanitizeFoundationModelText(id ?? "")
        return all.first { $0.id == normalized } ?? defaultScenario
    }
}

struct NativeAdvisorMessage: Codable, Hashable, Identifiable {
    var date: String
    var id: String
    var role: NativeAdvisorRole
    var text: String
}

enum NativeAdvisorRole: String, Codable, Hashable {
    case advisor
    case leader
}

struct NativeDiplomaticThread: Codable, Hashable, Identifiable {
    var id: String
    var lastUpdated: String
    var messages: [NativeDiplomaticMessage]
    var participant: PlayerCountry
    var summary: String
}

struct NativeDiplomaticMessage: Codable, Hashable, Identifiable {
    var date: String
    var id: String
    var speaker: String
    var text: String
}

/// The deterministic outcome of a resolved planned action.
///
/// - `success`: The action succeeded and its full primary effects were applied.
/// - `partial`: The action partially succeeded; reduced positive effects were applied.
/// - `failure`: The action failed; a negative stability/economic penalty was applied instead.
enum NativeActionOutcome: String, Codable, Hashable {
    case success
    case partial
    case failure
}

struct NativePlannedAction: Codable, Hashable, Identifiable {
    /// Capacity paid when this matrix cell entered the queue.
    var administrativeCost: Int
    /// Matrix action family used to preserve intent through turn adjudication.
    var decisionKind: String
    var createdAt: String
    var detail: String
    var id: String
    /// The recorded outcome of this action after resolution. Nil while still `.planned`.
    var outcome: NativeActionOutcome?
    var resolvedAt: String?
    var status: NativeActionStatus
    var title: String
    /// Mechanic tracks parsed from the suggestion's primaryMechanic/secondaryMechanic fields at acceptance time.
    var mechanicTracks: [NativeStrategicTrack]
    var targetCountryCode: String?
    var targetRegionID: String?
    var sovereigntyChange: NativeSovereigntyChange?

    private enum CodingKeys: String, CodingKey {
        case administrativeCost, createdAt, decisionKind, detail, id, outcome, resolvedAt, status, title, mechanicTracks
        case targetCountryCode, targetRegionID, sovereigntyChange
    }

    init(
        administrativeCost: Int = 0,
        createdAt: String,
        decisionKind: String = "policy",
        detail: String,
        id: String,
        outcome: NativeActionOutcome? = nil,
        resolvedAt: String? = nil,
        status: NativeActionStatus,
        title: String,
        mechanicTracks: [NativeStrategicTrack] = [],
        targetCountryCode: String? = nil,
        targetRegionID: String? = nil,
        sovereigntyChange: NativeSovereigntyChange? = nil
    ) {
        self.administrativeCost = max(0, administrativeCost)
        self.createdAt = createdAt
        self.decisionKind = decisionKind
        self.detail = detail
        self.id = id
        self.outcome = outcome
        self.resolvedAt = resolvedAt
        self.status = status
        self.title = title
        self.mechanicTracks = mechanicTracks
        self.targetCountryCode = targetCountryCode
        self.targetRegionID = targetRegionID
        self.sovereigntyChange = sovereigntyChange
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        administrativeCost = max(0, (try? c.decodeIfPresent(Int.self, forKey: .administrativeCost)) ?? 0)
        createdAt = (try? c.decodeIfPresent(String.self, forKey: .createdAt)) ?? ""
        decisionKind = (try? c.decodeIfPresent(String.self, forKey: .decisionKind)) ?? "policy"
        detail = (try? c.decodeIfPresent(String.self, forKey: .detail)) ?? ""
        id = (try? c.decodeIfPresent(String.self, forKey: .id)) ?? UUID().uuidString
        outcome = try? c.decodeIfPresent(NativeActionOutcome.self, forKey: .outcome)
        resolvedAt = try? c.decodeIfPresent(String.self, forKey: .resolvedAt)
        let rawStatus = (try? c.decodeIfPresent(String.self, forKey: .status)) ?? "planned"
        status = NativeActionStatus(rawValue: rawStatus) ?? .planned
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? ""
        mechanicTracks = (try? c.decodeIfPresent([NativeStrategicTrack].self, forKey: .mechanicTracks)) ?? []
        targetCountryCode = try? c.decodeIfPresent(String.self, forKey: .targetCountryCode)
        targetRegionID = try? c.decodeIfPresent(String.self, forKey: .targetRegionID)
        sovereigntyChange = try? c.decodeIfPresent(NativeSovereigntyChange.self, forKey: .sovereigntyChange)
    }
}

enum NativeActionStatus: String, Codable, Hashable {
    case planned
    case resolved
}

enum NativeVictoryStatus: String, Codable, Hashable {
    case ongoing
    case won
    case lostCollapse = "lost-collapse"
    case lostRival = "lost-rival"
    case lostTimeout = "lost-timeout"
}

enum NativeOfferType: String, Codable, Hashable {
    case tradeAgreement = "trade-agreement"
    case militaryAlliance = "military-alliance"
    case nonAggressionPact = "non-aggression"
    case territoryDemarcation = "border-deal"

    var displayName: String {
        switch self {
        case .tradeAgreement: String(localized: "Trade Agreement")
        case .militaryAlliance: String(localized: "Military Alliance")
        case .nonAggressionPact: String(localized: "Non-Aggression Pact")
        case .territoryDemarcation: String(localized: "Territory Demarcation")
        }
    }
}

enum NativeOfferStatus: String, Codable, Hashable {
    case pending
    case accepted
    case rejected
    case countered
}

struct NativeDiplomaticOffer: Codable, Hashable, Identifiable {
    var id: String
    var proposerCode: String
    var type: NativeOfferType
    var description: String
    var stabilityCost: Int
    var relationshipEffect: Int
    var growthDelta: Double
    var status: NativeOfferStatus
    var turnProposed: Int
    /// Destination of this offer. `nil` (default) means it is addressed to the
    /// player country. A non-nil value marks an autonomous AI-to-AI agreement
    /// (alliance, trade pact, non-aggression) that the player does not vote on
    /// but whose consequences (relation shifts, ledger buffs) still affect the
    /// world the player must navigate.
    var targetCode: String?

    /// `true` when this offer was struck between two AI countries and the
    /// player is not a party to it. UI surfaces should exclude these from the
    /// player's pending-offers queue and surface them only as world events.
    var isAutonomousAITreaty: Bool {
        guard let target = targetCode else { return false }
        return !target.isEmpty
    }

    private enum CodingKeys: String, CodingKey {
        case id, proposerCode, type, description, stabilityCost
        case relationshipEffect, growthDelta, status, turnProposed, targetCode
    }

    init(
        id: String,
        proposerCode: String,
        type: NativeOfferType,
        description: String,
        stabilityCost: Int,
        relationshipEffect: Int,
        growthDelta: Double,
        status: NativeOfferStatus,
        turnProposed: Int,
        targetCode: String? = nil
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
        self.targetCode = targetCode
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? ""
        proposerCode = (try? c.decode(String.self, forKey: .proposerCode)) ?? ""
        type = (try? c.decode(NativeOfferType.self, forKey: .type)) ?? .tradeAgreement
        description = (try? c.decode(String.self, forKey: .description)) ?? ""
        stabilityCost = (try? c.decode(Int.self, forKey: .stabilityCost)) ?? 0
        relationshipEffect = (try? c.decode(Int.self, forKey: .relationshipEffect)) ?? 0
        growthDelta = (try? c.decode(Double.self, forKey: .growthDelta)) ?? 0
        status = (try? c.decode(NativeOfferStatus.self, forKey: .status)) ?? .pending
        turnProposed = (try? c.decode(Int.self, forKey: .turnProposed)) ?? 0
        targetCode = try? c.decodeIfPresent(String.self, forKey: .targetCode)
    }

    /// `true` when this offer is addressed to the player (the legacy default).
    var isPlayerFacing: Bool {
        !isAutonomousAITreaty
    }
}

struct NativeSuggestedAction: Codable, Hashable, Identifiable {
    var actionKind: String
    var administrativeCost: Int
    var detail: String
    var id: String
    var rationale: String
    var title: String
    var urgency: String
    /// Explicit AI protocol token such as `⟦ECO⟧`; never inferred from narrative in new boards.
    var primaryMechanic: String
    /// Explicit AI protocol token such as `⟦DIP⟧`; never inferred from narrative in new boards.
    var secondaryMechanic: String
    var matrixColumn: Int
    var matrixRow: Int
    /// Fingerprint of the non-queue world snapshot used to generate this board.
    var matrixStateFingerprint: UInt64
    var targetCountryCode: String?
    var targetRegionID: String?
    var sovereigntyChange: NativeSovereigntyChange?

    private enum CodingKeys: String, CodingKey {
        case actionKind, administrativeCost, detail, id, rationale, title, urgency
        case primaryMechanic, secondaryMechanic, matrixColumn, matrixRow, matrixStateFingerprint
        case targetCountryCode, targetRegionID, sovereigntyChange
    }

    init(detail: String, id: String, rationale: String, title: String, urgency: String,
         primaryMechanic: String = "", secondaryMechanic: String = "",
         actionKind: String = "policy", administrativeCost: Int = 0,
         matrixRow: Int = -1, matrixColumn: Int = -1,
         matrixStateFingerprint: UInt64 = 0,
         targetCountryCode: String? = nil, targetRegionID: String? = nil,
         sovereigntyChange: NativeSovereigntyChange? = nil)
    {
        self.actionKind = actionKind
        self.administrativeCost = max(0, administrativeCost)
        self.detail = detail
        self.id = id
        self.rationale = rationale
        self.title = title
        self.urgency = urgency
        self.primaryMechanic = primaryMechanic
        self.secondaryMechanic = secondaryMechanic
        self.matrixColumn = matrixColumn
        self.matrixRow = matrixRow
        self.matrixStateFingerprint = matrixStateFingerprint
        self.targetCountryCode = targetCountryCode
        self.targetRegionID = targetRegionID
        self.sovereigntyChange = sovereigntyChange
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        actionKind = (try? c.decodeIfPresent(String.self, forKey: .actionKind)) ?? "policy"
        administrativeCost = max(0, (try? c.decodeIfPresent(Int.self, forKey: .administrativeCost)) ?? 0)
        detail = (try? c.decodeIfPresent(String.self, forKey: .detail)) ?? ""
        id = (try? c.decodeIfPresent(String.self, forKey: .id)) ?? UUID().uuidString
        rationale = (try? c.decodeIfPresent(String.self, forKey: .rationale)) ?? ""
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? ""
        urgency = (try? c.decodeIfPresent(String.self, forKey: .urgency)) ?? "soon"
        primaryMechanic = (try? c.decodeIfPresent(String.self, forKey: .primaryMechanic)) ?? ""
        secondaryMechanic = (try? c.decodeIfPresent(String.self, forKey: .secondaryMechanic)) ?? ""
        matrixColumn = (try? c.decodeIfPresent(Int.self, forKey: .matrixColumn)) ?? -1
        matrixRow = (try? c.decodeIfPresent(Int.self, forKey: .matrixRow)) ?? -1
        matrixStateFingerprint = (try? c.decodeIfPresent(UInt64.self, forKey: .matrixStateFingerprint)) ?? 0
        targetCountryCode = try? c.decodeIfPresent(String.self, forKey: .targetCountryCode)
        targetRegionID = try? c.decodeIfPresent(String.self, forKey: .targetRegionID)
        sovereigntyChange = try? c.decodeIfPresent(NativeSovereigntyChange.self, forKey: .sovereigntyChange)
    }
}

struct NativeCampaignEvent: Codable, Hashable, Identifiable {
    var date: String
    var description: String
    var id: String
    var importance: NativeEventImportance
    var kind: NativeEventKind
    var linkedActionIDs: [String]
    var notable: Bool
    var playerRelated: Bool
    var strategicEffects: [NativeStrategicEffect]
    var title: String
    var hexLeverCode: String?
    var sovereigntyChange: NativeSovereigntyChange?

    init(
        date: String,
        description: String,
        id: String,
        importance: NativeEventImportance,
        kind: NativeEventKind,
        linkedActionIDs: [String],
        notable: Bool,
        playerRelated: Bool,
        strategicEffects: [NativeStrategicEffect],
        title: String,
        hexLeverCode: String? = nil,
        sovereigntyChange: NativeSovereigntyChange? = nil
    ) {
        self.date = date
        self.description = description
        self.id = id
        self.importance = importance
        self.kind = kind
        self.linkedActionIDs = linkedActionIDs
        self.notable = notable
        self.playerRelated = playerRelated
        self.strategicEffects = strategicEffects
        self.title = title
        self.hexLeverCode = hexLeverCode
        self.sovereigntyChange = sovereigntyChange
    }
}

enum NativeEventKind: String, Codable, Hashable {
    case action
    case crisis
    case diplomacy
    case economy
    case world
}

extension NativeEventKind {
    var displayName: String {
        switch self {
        case .action: String(localized: "Nation Policy")
        case .crisis: String(localized: "Crisis Action")
        case .diplomacy: String(localized: "Diplomacy")
        case .economy: String(localized: "Economic Event")
        case .world: String(localized: "Global Event")
        }
    }
}

enum NativeEventImportance: String, Codable, Hashable {
    case minor
    case major
    case severe
}

struct NativeStrategicEffect: Codable, Hashable, Identifiable {
    var date: String
    var eventId: String
    var id: String
    var magnitude: Int
    var summary: String
    var target: String
    var track: NativeStrategicTrack
}

enum NativeStrategicTrack: String, Codable, CaseIterable, Hashable, Identifiable {
    case diplomaticLeverage = "diplomatic-leverage"
    case economicResilience = "economic-resilience"
    case internalStability = "internal-stability"
    case marketConfidence = "market-confidence"
    case militaryReadiness = "military-readiness"
    case securityAnxiety = "security-anxiety"
    case worldTension = "world-tension"

    var id: String {
        rawValue
    }
}

extension NativeStrategicTrack {
    /// Stable token exchanged with AI providers. The Unicode brackets make
    /// mechanic identifiers visually distinct from player-facing narrative,
    /// while the short ASCII payload remains safe in JSON and persisted text.
    var mechanicCode: String {
        switch self {
        case .economicResilience: "⟦ECO⟧"
        case .marketConfidence: "⟦MKT⟧"
        case .internalStability: "⟦STB⟧"
        case .securityAnxiety: "⟦SEC⟧"
        case .diplomaticLeverage: "⟦DIP⟧"
        case .militaryReadiness: "⟦MIL⟧"
        case .worldTension: "⟦TNS⟧"
        }
    }

    /// Decodes only explicit protocol tokens (plus legacy raw values). It does
    /// not infer mechanics from prose; narrative words are never executable.
    static func decodeMechanicToken(_ value: String) -> NativeStrategicTrack? {
        let token = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let exact = allCases.first(where: { $0.mechanicCode == token }) {
            return exact
        }
        return NativeStrategicTrack(rawValue: token.lowercased())
    }

    static var mechanicCodebookPrompt: String {
        """
        MECHANIC CODEBOOK (output these exact codes; narrative words never trigger mechanics)
        - ⟦ECO⟧ economic resilience: growth, productive capacity, infrastructure, fiscal durability.
        - ⟦MKT⟧ market confidence: trade, investment, inflation expectations, financing confidence.
        - ⟦STB⟧ internal stability: legitimacy, public services, cohesion, institutional delivery.
        - ⟦SEC⟧ security anxiety: insurgency, public insecurity, escalation pressure, civilian fear.
        - ⟦DIP⟧ diplomatic leverage: relationships, negotiations, alliances, international influence.
        - ⟦MIL⟧ military readiness: force preparedness, logistics, deterrence, command readiness.
        - ⟦TNS⟧ world tension: international friction, war risk, systemic escalation or de-escalation.
        Protocol rule: choose codes from state and intended mechanical consequences, then write matching narrative. Never derive or hide a mechanic only inside title, detail, rationale, description, or summary.
        """
    }

    static var compactMechanicCodebookPrompt: String {
        "Mechanic codes: ⟦ECO⟧=economy/infrastructure, ⟦MKT⟧=markets/trade, ⟦STB⟧=legitimacy/services, ⟦SEC⟧=insecurity/insurgency, ⟦DIP⟧=diplomatic leverage, ⟦MIL⟧=military readiness, ⟦TNS⟧=world tension. Output codes in mechanic fields; prose never executes mechanics."
    }

    var displayName: String {
        switch self {
        case .diplomaticLeverage: String(localized: "Diplomatic Leverage")
        case .economicResilience: String(localized: "Economic Resilience")
        case .internalStability: String(localized: "Internal Stability")
        case .marketConfidence: String(localized: "Market Confidence")
        case .militaryReadiness: String(localized: "Military Readiness")
        case .securityAnxiety: String(localized: "Security Anxiety")
        case .worldTension: String(localized: "World Tension")
        }
    }
}

struct NativeAIReadiness: Codable, Hashable {
    var availability: String
    var checkedAt: String
    var lastError: String
    var ok: Bool
    var recoverySuggestion: String
    var tokenBudget: String

    static let notChecked = NativeAIReadiness(
        availability: "not-checked",
        checkedAt: "",
        lastError: "",
        ok: false,
        recoverySuggestion: "",
        tokenBudget: ""
    )

    static func available(tokenBudget: String) -> NativeAIReadiness {
        NativeAIReadiness(
            availability: "available",
            checkedAt: NativeGameEngine.todayStamp(),
            lastError: "",
            ok: true,
            recoverySuggestion: "",
            tokenBudget: tokenBudget
        )
    }

    static func failure(_ error: Error) -> NativeAIReadiness {
        NativeAIReadiness(
            availability: failureAvailability(for: error),
            checkedAt: NativeGameEngine.todayStamp(),
            lastError: error.localizedDescription,
            ok: false,
            recoverySuggestion: recoverySuggestion(for: error),
            tokenBudget: "context=4096"
        )
    }

    static func suggestionFailure(_ error: Error) -> NativeAIReadiness {
        NativeAIReadiness(
            availability: failureAvailability(for: error),
            checkedAt: NativeGameEngine.todayStamp(),
            lastError: error.localizedDescription,
            ok: false,
            recoverySuggestion: "Suggested actions could not be refreshed safely. Keep drafting manual civic proposals, verify the selected AI provider, and retry.",
            tokenBudget: "context=4096, suggestions=4x180"
        )
    }

    static func unavailable(_ reason: String) -> NativeAIReadiness {
        NativeAIReadiness(
            availability: reason,
            checkedAt: NativeGameEngine.todayStamp(),
            lastError: reason,
            ok: false,
            recoverySuggestion: "Configure the selected AI provider in Settings, or choose a provider that is available on this machine. SwiftHistoria will not simulate turns with an unavailable AI route.",
            tokenBudget: "context=4096"
        )
    }

    static func modelUnavailable(_ reason: String) -> NativeAIReadiness {
        NativeAIReadiness(
            availability: availabilityCode(for: reason),
            checkedAt: NativeGameEngine.todayStamp(),
            lastError: reason,
            ok: false,
            recoverySuggestion: "Configure the selected AI provider in Settings, or choose a provider that is available on this machine. SwiftHistoria will not simulate turns with an unavailable AI route.",
            tokenBudget: "context=4096"
        )
    }

    private static func failureAvailability(for error: Error) -> String {
        guard let foundationError = error as? NativeFoundationModelError else {
            return "ai-provider-error"
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
            return "The selected AI provider did not complete this request. The game kept the current turn unchanged; add manual civic proposals, verify the active provider, and retry."
        }

        switch foundationError {
        case .unsupportedOS:
            return "Run SwiftHistoria on an OS that exposes FoundationModels. The current campaign remains editable, but AI turns are paused."
        case .modelUnavailable:
            return "Verify the selected AI provider in Settings and wait for the route to become available. Manual civic proposals remain available."
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

enum NativeFoundationModelError: LocalizedError {
    case unsupportedOS
    case modelUnavailable(String)
    case generationFailed(String)
    case invalidGeneratedTurn(String)
    case invalidSuggestedActions(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedOS:
            "This OS does not expose the FoundationModels framework required by the native game."
        case let .modelUnavailable(reason):
            "Selected AI provider is unavailable: \(reason)."
        case let .generationFailed(reason):
            "Selected AI provider generation failed: \(reason)."
        case let .invalidGeneratedTurn(reason):
            "Selected AI provider returned an invalid turn: \(reason)."
        case let .invalidSuggestedActions(reason):
            "Selected AI provider returned invalid suggested actions: \(reason)."
        }
    }
}

/// Cleans Foundation Model output for display: trims whitespace and collapses
/// accidental duplicate sentences/lines. No content filtering — the game is a
/// geopolitical strategy simulator and AI output is shown verbatim.
func sanitizeFoundationModelText(_ value: String) -> String {
    let result = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return collapseRepeatedLines(in: collapseRepeatedSentences(in: result))
}

private func collapseRepeatedSentences(in value: String) -> String {
    let parts = value.components(separatedBy: ". ")
    guard parts.count > 1 else { return value }

    let trimSet = CharacterSet.whitespacesAndNewlines
        .union(CharacterSet(charactersIn: ".!?"))
    var seen = Set<String>()
    var collapsed: [String] = []

    for part in parts {
        let normalized = part.trimmingCharacters(in: trimSet).lowercased()
        guard !normalized.isEmpty else {
            collapsed.append(part)
            continue
        }
        guard !seen.contains(normalized) else { continue }
        collapsed.append(part)
        seen.insert(normalized)
    }

    return collapsed.joined(separator: ". ")
}

private func collapseRepeatedLines(in value: String) -> String {
    let lines = value.components(separatedBy: .newlines)
    guard lines.count > 1 else { return value }

    var previousNormalized = ""
    var collapsed: [String] = []

    for line in lines {
        let normalized = line.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else {
            collapsed.append(line)
            previousNormalized = ""
            continue
        }
        guard normalized != previousNormalized else { continue }
        collapsed.append(line)
        previousNormalized = normalized
    }

    return collapsed.joined(separator: "\n")
}

func hasConcreteFoundationText(_ value: String, minimumWords: Int) -> Bool {
    let cleaned = sanitizeFoundationModelText(value)
    return !containsFoundationPlaceholderText(cleaned) &&
        cleaned.split(separator: " ").count >= minimumWords
}

func normalizedFoundationUrgency(_ value: String) -> String {
    switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "immediate", "soon", "opportunistic":
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    default:
        "soon"
    }
}

/// Returns the prompt-friendly label for a strategic track using real names.
func foundationPromptTrackLabel(_ track: NativeStrategicTrack) -> String {
    switch track {
    case .diplomaticLeverage:
        "diplomatic-leverage"
    case .economicResilience:
        "economic-resilience"
    case .internalStability:
        "internal-stability"
    case .marketConfidence:
        "market-confidence"
    case .militaryReadiness:
        "military-readiness"
    case .securityAnxiety:
        "security-anxiety"
    case .worldTension:
        "world-tension"
    }
}

/// Identity — all strategic tracks are valid and visible to the player.
func foundationVisibleTrack(_ track: NativeStrategicTrack) -> NativeStrategicTrack {
    track
}

func containsFoundationPlaceholderText(_ value: String) -> Bool {
    let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let blockedFragments = [
        "applenativegeneratedeventdraft",
        "applenativesuggestedaction",
        "applenativeturnsummary",
        "apple native generated event draft",
        "apple native suggested action",
        "apple native turn summary",
        "generated event draft",
        "schema type",
        "field name",
        "property name",
        "placeholder",
        "example title",
        "sample title",
        "lorem ipsum",
        "todo:",
        "to do",
        "tbd"
    ]
    return blockedFragments.contains { normalized.contains($0) }
}

enum NativeGameEngineError: LocalizedError {
    case invalidTurn(String)

    var errorDescription: String? {
        switch self {
        case let .invalidTurn(reason):
            "The generated turn could not be applied: \(reason)."
        }
    }
}

struct NativeGeneratedTurn: Codable, Hashable {
    var events: [NativeCampaignEvent]
    var stabilityDelta: Int
    var summary: String
    var worldTensionDelta: Int
}
