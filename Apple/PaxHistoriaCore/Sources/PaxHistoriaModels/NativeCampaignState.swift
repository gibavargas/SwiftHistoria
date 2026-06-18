import Foundation

public struct NativeCampaignState: Codable, Hashable, Sendable {
    public static var defaultStrategicCountryCodes: [String] = {
        let mappedCodes = GeopoliticalMapData.regions.map(\.countryCode).filter { $0 != "WATER" }
        return Array(Set(CountryCatalog.all.map(\.code) + mappedCodes + ["GLOBAL"])).sorted()
    }()

    public var actionMemory: [NativeActionMemory]
    public var advisorMessages: [NativeAdvisorMessage]
    public var aiReadiness: NativeAIReadiness
    public var country: PlayerCountry
    public var diplomaticThreads: [NativeDiplomaticThread]
    public var dynamicCountries: [String: String]
    public var economicLedger: NativeEconomicLedger
    public var economicLedgers: [String: NativeEconomicLedger]
    public var aiCountryStates: [String: NativeAICountryState]

    public var gameDate: String
    public var gameMode: NativeGameMode
    public var lastSummary: String
    public var language: NativeGameLanguage
    public var plannedActions: [NativePlannedAction]
    public var round: Int
    public var scenarioDescription: String
    public var scenarioID: String
    public var scenarioName: String
    public var semanticMemory: [NativeSemanticMemory]
    public var suggestedActions: [NativeSuggestedAction]
    public var stability: Int
    public var startDate: String
    public var timeline: [NativeCampaignEvent]
    public var worldTension: Int
    public var worldEffects: [NativeStrategicEffect]
    public var regionOccupations: [String: String]
    public var nuclearFalloutRegions: [String]
    public var regionConflicts: [String: NativeRegionConflictState]

    // New Grand Strategy Layer fields
    public var administrativeCapacity: Int
    public var victoryStatus: NativeVictoryStatus
    public var activeOffers: [NativeDiplomaticOffer]
    public var activeTreaties: [NativeTreaty]
    public var budgetMilitarySlider: Double
    public var budgetServicesSlider: Double
    public var budgetDiplomacySlider: Double

    public init(
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
        administrativeCapacity: Int = 100,
        victoryStatus: NativeVictoryStatus = .ongoing,
        activeOffers: [NativeDiplomaticOffer] = [],
        activeTreaties: [NativeTreaty] = [],
        budgetMilitarySlider: Double = 0.33,
        budgetServicesSlider: Double = 0.34,
        budgetDiplomacySlider: Double = 0.33
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
            for code in Self.defaultStrategicCountryCodes where code != country.code {
                ledgers[code] = NativeEconomicLedger.starting(forCode: code, scenario: scenarioObj)
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
        self.administrativeCapacity = administrativeCapacity
        self.victoryStatus = victoryStatus
        self.activeOffers = activeOffers
        self.activeTreaties = activeTreaties
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
        case dynamicCountries
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
        case administrativeCapacity
        case victoryStatus
        case activeOffers
        case activeTreaties
        case budgetMilitarySlider
        case budgetServicesSlider
        case budgetDiplomacySlider
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        advisorMessages = (try? container.decodeIfPresent([NativeAdvisorMessage].self, forKey: .advisorMessages)) ?? []
        aiReadiness = (try? container.decodeIfPresent(NativeAIReadiness.self, forKey: .aiReadiness)) ?? .notChecked
        country = try container.decode(PlayerCountry.self, forKey: .country)
        diplomaticThreads = (try? container.decodeIfPresent([NativeDiplomaticThread].self, forKey: .diplomaticThreads)) ?? []
        dynamicCountries = (try? container.decodeIfPresent([String: String].self, forKey: .dynamicCountries)) ?? [:]
        scenarioID = (try? container.decodeIfPresent(String.self, forKey: .scenarioID)) ?? NativeScenarioCatalog.defaultScenario.id
        let decodedScenario = NativeScenarioCatalog.scenario(for: scenarioID)
        actionMemory = (try? container.decodeIfPresent([NativeActionMemory].self, forKey: .actionMemory)) ?? []
        let decodedLedger = (try? container.decodeIfPresent(NativeEconomicLedger.self, forKey: .economicLedger)) ?? NativeEconomicLedger.starting(for: country, scenario: decodedScenario)
        economicLedger = decodedLedger
        var ledgers = (try? container.decodeIfPresent([String: NativeEconomicLedger].self, forKey: .economicLedgers)) ?? [:]
        if ledgers.isEmpty {
            ledgers[country.code] = decodedLedger
            for code in Self.defaultStrategicCountryCodes where code != country.code {
                ledgers[code] = NativeEconomicLedger.starting(forCode: code, scenario: decodedScenario)
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
        semanticMemory = (try? container.decodeIfPresent([NativeSemanticMemory].self, forKey: .semanticMemory)) ?? []
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
        activeTreaties = (try? container.decodeIfPresent([NativeTreaty].self, forKey: .activeTreaties)) ?? []
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
