import Foundation

/// Player-selectable campaign mode. The enum is persisted, so raw values should
/// stay stable unless an explicit save migration is added.
enum NativeGameMode: String, Codable, CaseIterable, Identifiable, Hashable {
    case sandbox = "Sandbox"
    case normal = "Normal"
    case ironman = "Iron Man"

    var id: String { rawValue }

    var description: String {
        switch self {
        case .sandbox: return "Unlimited administrative freedom and light consequences."
        case .normal: return "Standard campaign conditions with active crisis events."
        case .ironman: return "Sovereign risks are doubled, and reloading is disabled."
        }
    }
}

enum NativeTerrainType: String, Codable, CaseIterable, Identifiable, Hashable {
    case ocean = "ocean"
    case strait = "strait"
    case sea = "sea"
    case city = "city"
    case forest = "forest"
    case cerrado = "cerrado"
    case swamp = "swamp"
    case mountain = "mountain"
    case plains = "plains"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ocean: return "Ocean"
        case .strait: return "Strait"
        case .sea: return "Sea"
        case .city: return "City"
        case .forest: return "Forest"
        case .cerrado: return "Cerrado"
        case .swamp: return "Swamp"
        case .mountain: return "Mountain"
        case .plains: return "Plains"
        }
    }
}

enum NativeRegionConflictMode: String, Codable, CaseIterable, Identifiable, Hashable {
    case contestedBorder = "contested-border"
    case conventionalOccupation = "conventional-occupation"
    case guerrillaControl = "guerrilla-control"
    case nuclearFallout = "nuclear-fallout"
    case stabilization = "stabilization"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .contestedBorder:
            return "Contested border"
        case .conventionalOccupation:
            return "Conventional occupation"
        case .guerrillaControl:
            return "Guerrilla control"
        case .nuclearFallout:
            return "Nuclear fallout"
        case .stabilization:
            return "Stabilization corridor"
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

    var id: String { regionID }

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
    case mercantile = "mercantile"
    case expansionist = "expansionist"
    case isolationist = "isolationist"
    case defensive = "defensive"
    case collaborative = "collaborative"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .mercantile: return "Mercantile"
        case .expansionist: return "Expansionist"
        case .isolationist: return "Isolationist"
        case .defensive: return "Defensive"
        case .collaborative: return "Collaborative"
        }
    }
}

enum NativeAIBudgetPriority: String, Codable, CaseIterable, Identifiable, Hashable {
    case growth = "growth"
    case stability = "stability"
    case military = "military"
    case diplomacy = "diplomacy"

    var id: String { rawValue }
}

struct NativeAICountryState: Codable, Hashable, Identifiable {
    var countryCode: String
    var doctrine: NativeAIDoctrine
    var budgetPriority: NativeAIBudgetPriority
    var relationshipScores: [String: Int] // target -> score (-100 to 100)
    var multiTurnAgenda: String
    var agendaProgress: Int // 0 to 100

    var id: String { countryCode }
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
    var economicLedger: NativeEconomicLedger
    var economicLedgers: [String: NativeEconomicLedger]
    var aiCountryStates: [String: NativeAICountryState]

    var gameDate: String
    var gameMode: NativeGameMode
    var lastSummary: String
    var language: NativeGameLanguage
    var plannedActions: [NativePlannedAction]
    var round: Int
    var scenarioDescription: String
    var scenarioID: String
    var scenarioName: String
    var suggestedActions: [NativeSuggestedAction]
    var stability: Int
    var startDate: String
    var timeline: [NativeCampaignEvent]
    var worldTension: Int
    var worldEffects: [NativeStrategicEffect]
    var regionOccupations: [String: String]
    var nuclearFalloutRegions: [String]
    var regionConflicts: [String: NativeRegionConflictState]

    // New Grand Strategy Layer fields
    var administrativeCapacity: Int
    var victoryStatus: NativeVictoryStatus
    var activeOffers: [NativeDiplomaticOffer]
    var budgetMilitarySlider: Double
    var budgetServicesSlider: Double
    var budgetDiplomacySlider: Double

    init(
        actionMemory: [NativeActionMemory] = [],
        advisorMessages: [NativeAdvisorMessage] = [],
        aiReadiness: NativeAIReadiness,
        country: PlayerCountry,
        diplomaticThreads: [NativeDiplomaticThread] = [],
        economicLedger: NativeEconomicLedger? = nil,
        economicLedgers: [String: NativeEconomicLedger]? = nil,
        aiCountryStates: [String: NativeAICountryState]? = nil,
        gameDate: String,
        gameMode: NativeGameMode = .normal,
        lastSummary: String,
        language: NativeGameLanguage = .english,
        plannedActions: [NativePlannedAction],
        round: Int,
        scenarioDescription: String,
        scenarioID: String,
        scenarioName: String,
        suggestedActions: [NativeSuggestedAction],
        stability: Int,
        startDate: String,
        timeline: [NativeCampaignEvent],
        worldTension: Int,
        worldEffects: [NativeStrategicEffect],
        regionOccupations: [String: String] = [:],
        nuclearFalloutRegions: [String] = [],
        regionConflicts: [String: NativeRegionConflictState] = [:],
        administrativeCapacity: Int = 100,
        victoryStatus: NativeVictoryStatus = .ongoing,
        activeOffers: [NativeDiplomaticOffer] = [],
        budgetMilitarySlider: Double = 0.33,
        budgetServicesSlider: Double = 0.34,
        budgetDiplomacySlider: Double = 0.33
    ) {
        self.actionMemory = actionMemory
        self.advisorMessages = advisorMessages
        self.aiReadiness = aiReadiness
        self.country = country
        self.diplomaticThreads = diplomaticThreads
        let computedEconomicLedger = economicLedger ?? NativeEconomicLedger.starting(
            for: country,
            scenario: NativeScenarioCatalog.scenario(for: scenarioID)
        )
        self.economicLedger = computedEconomicLedger
        if let economicLedgers = economicLedgers {
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
        self.lastSummary = lastSummary
        self.language = language
        self.plannedActions = plannedActions
        self.round = round
        self.scenarioDescription = scenarioDescription
        self.scenarioID = scenarioID
        self.scenarioName = scenarioName
        self.suggestedActions = suggestedActions
        self.stability = stability
        self.startDate = startDate
        self.timeline = timeline
        self.worldTension = worldTension
        self.worldEffects = worldEffects
        self.regionOccupations = regionOccupations
        self.nuclearFalloutRegions = nuclearFalloutRegions
        self.regionConflicts = regionConflicts
        self.administrativeCapacity = administrativeCapacity
        self.victoryStatus = victoryStatus
        self.activeOffers = activeOffers
        self.budgetMilitarySlider = budgetMilitarySlider
        self.budgetServicesSlider = budgetServicesSlider
        self.budgetDiplomacySlider = budgetDiplomacySlider
    }

    private enum CodingKeys: String, CodingKey {
        case actionMemory
        case advisorMessages
        case aiReadiness
        case country
        case diplomaticThreads
        case economicLedger
        case economicLedgers
        case aiCountryStates
        case gameDate
        case gameMode
        case lastSummary
        case language
        case plannedActions
        case round
        case scenarioDescription
        case scenarioID
        case scenarioName
        case suggestedActions
        case stability
        case startDate
        case timeline
        case worldTension
        case worldEffects
        case regionOccupations
        case nuclearFalloutRegions
        case regionConflicts
        case administrativeCapacity
        case victoryStatus
        case activeOffers
        case budgetMilitarySlider
        case budgetServicesSlider
        case budgetDiplomacySlider
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        advisorMessages = (try? container.decodeIfPresent([NativeAdvisorMessage].self, forKey: .advisorMessages)) ?? []
        aiReadiness = (try? container.decodeIfPresent(NativeAIReadiness.self, forKey: .aiReadiness)) ?? .notChecked
        country = try container.decode(PlayerCountry.self, forKey: .country)
        diplomaticThreads = (try? container.decodeIfPresent([NativeDiplomaticThread].self, forKey: .diplomaticThreads)) ?? []
        scenarioID = (try? container.decodeIfPresent(String.self, forKey: .scenarioID)) ?? NativeScenarioCatalog.defaultScenario.id
        let decodedScenario = NativeScenarioCatalog.scenario(for: scenarioID)
        actionMemory = (try? container.decodeIfPresent([NativeActionMemory].self, forKey: .actionMemory)) ?? []
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
        if regionConflicts.isEmpty {
            regionConflicts = Self.conflictsFromLegacyMapState(
                occupations: regionOccupations,
                falloutRegions: nuclearFalloutRegions
            )
        }
        gameDate = (try? container.decodeIfPresent(String.self, forKey: .gameDate)) ?? decodedScenario.gameDate
        gameMode = (try? container.decodeIfPresent(NativeGameMode.self, forKey: .gameMode)) ?? .normal
        lastSummary = (try? container.decodeIfPresent(String.self, forKey: .lastSummary)) ?? "\(decodedScenario.openingSummary) \(country.name) needs to turn intent into concrete plans."
        language = NativeGameLanguage.normalized(try? container.decodeIfPresent(String.self, forKey: .language))
        plannedActions = (try? container.decodeIfPresent([NativePlannedAction].self, forKey: .plannedActions)) ?? []
        round = (try? container.decodeIfPresent(Int.self, forKey: .round)) ?? 1
        scenarioName = (try? container.decodeIfPresent(String.self, forKey: .scenarioName)) ?? decodedScenario.name
        scenarioDescription = (try? container.decodeIfPresent(String.self, forKey: .scenarioDescription)) ?? decodedScenario.heroSubtitle
        suggestedActions = (try? container.decodeIfPresent([NativeSuggestedAction].self, forKey: .suggestedActions)) ?? []
        stability = (try? container.decodeIfPresent(Int.self, forKey: .stability)) ?? decodedScenario.baseStability
        startDate = (try? container.decodeIfPresent(String.self, forKey: .startDate)) ?? decodedScenario.startDate
        timeline = (try? container.decodeIfPresent([NativeCampaignEvent].self, forKey: .timeline)) ?? []
        worldTension = (try? container.decodeIfPresent(Int.self, forKey: .worldTension)) ?? decodedScenario.baseWorldTension
        worldEffects = (try? container.decodeIfPresent([NativeStrategicEffect].self, forKey: .worldEffects)) ?? []

        // Decoding new fields with defaults
        administrativeCapacity = (try? container.decodeIfPresent(Int.self, forKey: .administrativeCapacity)) ?? 100
        victoryStatus = (try? container.decodeIfPresent(NativeVictoryStatus.self, forKey: .victoryStatus)) ?? .ongoing
        activeOffers = (try? container.decodeIfPresent([NativeDiplomaticOffer].self, forKey: .activeOffers)) ?? []
        budgetMilitarySlider = (try? container.decodeIfPresent(Double.self, forKey: .budgetMilitarySlider)) ?? 0.33
        budgetServicesSlider = (try? container.decodeIfPresent(Double.self, forKey: .budgetServicesSlider)) ?? 0.34
        budgetDiplomacySlider = (try? container.decodeIfPresent(Double.self, forKey: .budgetDiplomacySlider)) ?? 0.33
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

/// User-facing language selection plus the prompt instruction used by native
/// AI generation. Keep schema keys and identifiers out of translation; only
/// player-visible prose should follow this value.
enum NativeGameLanguage: String, Codable, CaseIterable, Hashable, Identifiable {
    case english = "English"
    case portuguese = "Portuguese"
    case spanish = "Spanish"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .english:
            return "English"
        case .portuguese:
            return "Português"
        case .spanish:
            return "Español"
        }
    }

    var responseLanguageName: String {
        switch self {
        case .english:
            return "English"
        case .portuguese:
            return "Portuguese (Brazilian Portuguese)"
        case .spanish:
            return "Spanish"
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

struct NativePlannedAction: Codable, Hashable, Identifiable {
    var createdAt: String
    var detail: String
    var id: String
    var resolvedAt: String?
    var status: NativeActionStatus
    var title: String
}

enum NativeActionStatus: String, Codable, Hashable {
    case planned
    case resolved
}

enum NativeVictoryStatus: String, Codable, Hashable {
    case ongoing = "ongoing"
    case won = "won"
    case lostCollapse = "lost-collapse"
    case lostTimeout = "lost-timeout"
}

enum NativeOfferType: String, Codable, Hashable {
    case tradeAgreement = "trade-agreement"
    case militaryAlliance = "military-alliance"
    case nonAggressionPact = "non-aggression"
    case territoryDemarcation = "border-deal"

    var displayName: String {
        switch self {
        case .tradeAgreement: return "Trade Agreement"
        case .militaryAlliance: return "Military Alliance"
        case .nonAggressionPact: return "Non-Aggression Pact"
        case .territoryDemarcation: return "Territory Demarcation"
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
}


struct NativeSuggestedAction: Codable, Hashable, Identifiable {
    var detail: String
    var id: String
    var rationale: String
    var title: String
    var urgency: String
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
        hexLeverCode: String? = nil
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
        case .action: "Nation Policy"
        case .crisis: "Crisis Action"
        case .diplomacy: "Diplomacy"
        case .economy: "Economic Event"
        case .world: "Global Event"
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

    var id: String { rawValue }
}

extension NativeStrategicTrack {
    var displayName: String {
        switch self {
        case .diplomaticLeverage: "Diplomatic Leverage"
        case .economicResilience: "Economic Resilience"
        case .internalStability: "Internal Stability"
        case .marketConfidence: "Market Confidence"
        case .militaryReadiness: "Military Readiness"
        case .securityAnxiety: "Security Anxiety"
        case .worldTension: "World Tension"
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

    init(
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
            recoverySuggestion: "Suggested actions could not be refreshed safely. Keep drafting manual civic proposals and retry when Apple Foundation Models are ready.",
            tokenBudget: "context=4096, suggestions=4x180"
        )
    }

    static func unavailable(_ reason: String) -> NativeAIReadiness {
        NativeAIReadiness(
            availability: reason,
            checkedAt: NativeGameEngine.todayStamp(),
            lastError: reason,
            ok: false,
            recoverySuggestion: "Enable Apple Intelligence and make sure the local model is ready. SwiftHistoria will not simulate turns without Apple Foundation Models.",
            tokenBudget: "context=4096"
        )
    }

    static func modelUnavailable(_ reason: String) -> NativeAIReadiness {
        NativeAIReadiness(
            availability: availabilityCode(for: reason),
            checkedAt: NativeGameEngine.todayStamp(),
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
        case .modelUnavailable(let reason):
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
            normalized.contains("not enabled") {
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
            return "This OS does not expose the FoundationModels framework required by the native game."
        case .modelUnavailable(let reason):
            return "Apple Foundation Models are unavailable: \(reason)."
        case .generationFailed(let reason):
            return "Apple Foundation Models generation failed: \(reason)."
        case .invalidGeneratedTurn(let reason):
            return "Apple Foundation Models returned an invalid turn: \(reason)."
        case .invalidSuggestedActions(let reason):
            return "Apple Foundation Models returned invalid suggested actions: \(reason)."
        }
    }
}

func sanitizeFoundationModelText(_ value: String) -> String {
    var result = value.trimmingCharacters(in: .whitespacesAndNewlines)
    let replacements: [(String, String)] = [
        ("World Trade Organization", "External Trade Forum"),
        ("United Nations", "Global Coordination Forum"),
        ("World Bank", "Development Finance Forum"),
        ("International Monetary Fund", "Stability Finance Forum"),
        ("Port Rio Grande", "Port Delta"),
        ("Rio Verde", "Valley District"),
        ("Serra Verde", "Highland District"),
        ("Rio de Janeiro", "Metro A"),
        ("São Paulo", "Metro B"),
        ("Sao Paulo", "Metro B"),
        ("government", "regional council"),
        ("Government", "Regional council"),
        ("public health", "community services"),
        ("Public health", "Community services"),
        ("Public Health", "Community Services"),
        ("healthcare", "community services"),
        ("Healthcare", "Community services"),
        ("health", "community services"),
        ("Health", "Community services"),
        ("medical", "service"),
        ("Medical", "Service"),
        ("clinic", "service center"),
        ("Clinic", "Service center"),
        ("emergency", "contingency"),
        ("Emergency", "Contingency"),
        ("mortality", "service delays"),
        ("Mortality", "Service delays"),
        ("death", "service loss"),
        ("Death", "Service loss"),
        ("crisis", "constraint"),
        ("Crisis", "Constraint"),
        ("conflict", "friction"),
        ("Conflict", "Friction"),
        ("security", "resilience"),
        ("Security", "Resilience"),
        ("weapons", "tools"),
        ("Weapons", "Tools"),
        ("weapon", "tool"),
        ("Weapon", "Tool"),
        ("missile", "long-range asset"),
        ("Missile", "Long-range asset"),
        ("bomb", "hazard"),
        ("Bomb", "Hazard"),
        ("cy" + "berattack", "digital disruption"),
        ("Cy" + "berattack", "Digital disruption"),
        ("attack", "pressure event"),
        ("Attack", "Pressure event"),
        ("invasion", "border pressure"),
        ("Invasion", "Border pressure"),
        ("troop", "logistics unit"),
        ("Troop", "Logistics unit"),
        ("troops", "logistics units"),
        ("Troops", "Logistics units"),
        ("military", "logistics"),
        ("Military", "Logistics"),
        ("surveillance", "oversight"),
        ("Surveillance", "Oversight"),
        ("coercion", "pressure"),
        ("Coercion", "Pressure"),
        ("cy" + "ber", "digital"),
        ("Cy" + "ber", "Digital"),
        ("intelligence", "analysis"),
        ("Intelligence", "Analysis"),
        ("market-confidence drops", "market-confidence volatility"),
        ("Market-confidence drops", "Market-confidence volatility"),
        ("market confidence drops", "market confidence volatility"),
        ("Market confidence drops", "Market confidence volatility"),
        ("market-confidence drop", "market-confidence volatility"),
        ("Market-confidence drop", "Market-confidence volatility"),
        ("market confidence drop", "market confidence volatility"),
        ("Market confidence drop", "Market confidence volatility"),
        ("community services services", "community services"),
        ("Community services Services", "Community Services"),
        ("community services service center", "community service center"),
        ("Community services service center", "Community service center"),
    ]

    for (needle, replacement) in replacements {
        result = result.replacingOccurrences(of: needle, with: replacement)
    }
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
    let sanitized = sanitizeFoundationModelText(value)
    return !containsFoundationPlaceholderText(sanitized) &&
        sanitized.split(separator: " ").count >= minimumWords
}

func normalizedFoundationUrgency(_ value: String) -> String {
    switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "immediate", "soon", "opportunistic":
        return value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    default:
        return "soon"
    }
}

func foundationPromptTrackLabel(_ track: NativeStrategicTrack) -> String {
    switch track {
    case .diplomaticLeverage:
        return "regional-relations"
    case .economicResilience:
        return "economic-resilience"
    case .internalStability:
        return "internal-stability"
    case .marketConfidence:
        return "market-confidence"
    case .militaryReadiness:
        return "logistics-readiness"
    case .securityAnxiety:
        return "resilience-pressure"
    case .worldTension:
        return "global-friction"
    }
}

func foundationVisibleTrack(_ track: NativeStrategicTrack) -> NativeStrategicTrack {
    switch track {
    case .militaryReadiness:
        return .economicResilience
    case .securityAnxiety:
        return .worldTension
    default:
        return track
    }
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
        "tbd",
    ]
    return blockedFragments.contains { normalized.contains($0) }
}

enum NativeGameEngineError: LocalizedError {
    case invalidTurn(String)

    var errorDescription: String? {
        switch self {
        case .invalidTurn(let reason):
            return "The generated turn could not be applied: \(reason)."
        }
    }
}

struct NativeGeneratedTurn: Codable, Hashable {
    var events: [NativeCampaignEvent]
    var stabilityDelta: Int
    var summary: String
    var worldTensionDelta: Int
}
