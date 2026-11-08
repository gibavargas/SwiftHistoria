import Foundation

private extension NativeEventImportance {
    var semanticWeight: Int {
        switch self {
        case .minor: 1
        case .major: 3
        case .severe: 5
        }
    }
}

// Test-friendly accessors for the private embedding model

enum NativeFoundationTurnLane: String, Codable, CaseIterable, Hashable, Identifiable {
    case external
    case economy
    case budget
    case domestic
    case actionConsequence
    case summary

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .external: "External facts"
        case .economy: "Economic model"
        case .budget: "Budget balance"
        case .domestic: "Domestic response"
        case .actionConsequence: "Action consequence"
        case .summary: "Turn synthesis"
        }
    }
}

struct NativeTurnProgress: Codable, Hashable {
    var completedLanes: Int
    var detail: String
    var phase: String
    var totalLanes: Int
    var providerName: String? = nil
    var modelName: String? = nil
    var modelIdentifier: String? = nil
    var reasoningStatus: NativeReasoningStatus? = nil
    var reasoningText: String? = nil

    var providerSummary: String? {
        guard let providerName else { return nil }
        if let modelName, !modelName.isEmpty {
            return "Calling \(providerName) · \(modelName)"
        }
        return "Calling \(providerName)"
    }

    var fraction: Double {
        guard totalLanes > 0 else { return 0 }
        return min(1.0, max(0.0, Double(completedLanes) / Double(totalLanes)))
    }
}

enum NativeReasoningStatus: String, Codable, Hashable {
    case encrypted
    case live
    case unavailable
    case waiting

    var label: String {
        switch self {
        case .encrypted: "ENCRYPTED"
        case .live: "LIVE"
        case .unavailable: "NOT EXPOSED"
        case .waiting: "WAITING"
        }
    }
}

struct NativeFactRecord: Codable, Hashable, Identifiable {
    var countryCodes: [String]
    var detail: String
    var id: String
    var startDate: String
    var tags: [String]
    var title: String
}

struct NativeConsequenceRule: Codable, Hashable, Identifiable {
    var budgetBalanceDelta: Double
    var debtDelta: Double
    var description: String
    var fiscalSpaceDelta: Int
    var growthDelta: Double
    var id: String
    var inflationDelta: Double
    var keywords: [String]
    var summary: String
    var tradeBalanceDelta: Double
    var track: NativeStrategicTrack
}

struct NativeEconomicLedgerEntry: Codable, Hashable, Identifiable {
    var budgetBalanceDelta: Double
    var debtDelta: Double
    var eventID: String
    var fiscalSpaceDelta: Int
    var growthDelta: Double
    var id: String
    var inflationDelta: Double
    var ruleID: String
    var summary: String
    var tradeBalanceDelta: Double
    var turnDate: String
    var securityDelta: Double?
    var rebelDelta: Double?
}

struct NativeEconomicLedger: Codable, Hashable {
    var budgetBalancePercentGDP: Double
    var entries: [NativeEconomicLedgerEntry]
    var fiscalSpaceIndex: Int
    var inflationPercent: Double
    var nominalGDPTrillions: Double
    var publicDebtPercentGDP: Double
    var realGrowthPercent: Double
    var tradeBalancePercentGDP: Double
    var unemploymentPercent: Double
    var securityIndex: Double
    var rebelControlPercent: Double
    /// Dynamic resource reserves (P1-3). Keys: "oil", "minerals", "agriculture", "rare_earths".
    /// Values represent relative abundance (0-100 scale). Depleted by industrial budget each turn.
    var resourceReserves: [String: Double]
    var governmentType: String
    var publicApprovalPercent: Double
    var nextElectionRound: Int

    enum CodingKeys: String, CodingKey {
        case budgetBalancePercentGDP
        case entries
        case fiscalSpaceIndex
        case inflationPercent
        case nominalGDPTrillions
        case publicDebtPercentGDP
        case realGrowthPercent
        case tradeBalancePercentGDP
        case unemploymentPercent
        case securityIndex
        case rebelControlPercent
        case resourceReserves
        case governmentType
        case publicApprovalPercent
        case nextElectionRound
    }

    init(
        budgetBalancePercentGDP: Double,
        entries: [NativeEconomicLedgerEntry],
        fiscalSpaceIndex: Int,
        inflationPercent: Double,
        nominalGDPTrillions: Double,
        publicDebtPercentGDP: Double,
        realGrowthPercent: Double,
        tradeBalancePercentGDP: Double,
        unemploymentPercent: Double,
        securityIndex: Double = 80.0,
        rebelControlPercent: Double = 0.0,
        resourceReserves: [String: Double] = [:],
        governmentType: String = "democracy",
        publicApprovalPercent: Double = 50.0,
        nextElectionRound: Int = 48
    ) {
        self.budgetBalancePercentGDP = budgetBalancePercentGDP
        self.entries = entries
        self.fiscalSpaceIndex = fiscalSpaceIndex
        self.inflationPercent = inflationPercent
        self.nominalGDPTrillions = nominalGDPTrillions
        self.publicDebtPercentGDP = publicDebtPercentGDP
        self.realGrowthPercent = realGrowthPercent
        self.tradeBalancePercentGDP = tradeBalancePercentGDP
        self.unemploymentPercent = unemploymentPercent
        self.securityIndex = securityIndex
        self.rebelControlPercent = rebelControlPercent
        self.resourceReserves = resourceReserves.isEmpty ? NativeEconomicLedger.defaultResourceReserves() : resourceReserves
        self.governmentType = governmentType
        self.publicApprovalPercent = publicApprovalPercent
        self.nextElectionRound = nextElectionRound
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        budgetBalancePercentGDP = try container.decode(Double.self, forKey: .budgetBalancePercentGDP)
        entries = try container.decode([NativeEconomicLedgerEntry].self, forKey: .entries)
        fiscalSpaceIndex = try container.decode(Int.self, forKey: .fiscalSpaceIndex)
        inflationPercent = try container.decode(Double.self, forKey: .inflationPercent)
        nominalGDPTrillions = try container.decode(Double.self, forKey: .nominalGDPTrillions)
        publicDebtPercentGDP = try container.decode(Double.self, forKey: .publicDebtPercentGDP)
        realGrowthPercent = try container.decode(Double.self, forKey: .realGrowthPercent)
        tradeBalancePercentGDP = try container.decode(Double.self, forKey: .tradeBalancePercentGDP)
        unemploymentPercent = try container.decode(Double.self, forKey: .unemploymentPercent)
        securityIndex = (try? container.decodeIfPresent(Double.self, forKey: .securityIndex)) ?? 80.0
        rebelControlPercent = (try? container.decodeIfPresent(Double.self, forKey: .rebelControlPercent)) ?? 0.0
        resourceReserves = (try? container.decodeIfPresent([String: Double].self, forKey: .resourceReserves)) ?? NativeEconomicLedger.defaultResourceReserves()
        governmentType = (try? container.decodeIfPresent(String.self, forKey: .governmentType)) ?? "democracy"
        publicApprovalPercent = (try? container.decodeIfPresent(Double.self, forKey: .publicApprovalPercent)) ?? 50.0
        nextElectionRound = (try? container.decodeIfPresent(Int.self, forKey: .nextElectionRound)) ?? 48
    }

    /// Default balanced resource reserves for a new country.
    static func defaultResourceReserves() -> [String: Double] {
        ["oil": 30.0, "minerals": 40.0, "agriculture": 50.0, "rare_earths": 15.0]
    }

    /// Resource reserves biased by country code — major producers get higher reserves.
    static func resourceReserves(forCountryCode code: String) -> [String: Double] {
        var reserves = defaultResourceReserves()
        let oilProducers: Set = ["SAU", "RUS", "USA", "IRN", "IRQ", "ARE", "KWT", "VEN", "NGA", "CAN", "BRA", "NOR"]
        let mineralProducers: Set = ["AUS", "CHN", "CHL", "PER", "ZAF", "RUS", "COD", "IDN"]
        let agricultureProducers: Set = ["USA", "BRA", "CHN", "IND", "ARG", "FRA", "AUS", "CAN"]
        let rareEarthProducers: Set = ["CHN", "AUS", "USA", "RUS", "IND", "BRA"]

        if oilProducers.contains(code) {
            reserves["oil"] = 80.0
        }
        if mineralProducers.contains(code) {
            reserves["minerals"] = 75.0
        }
        if agricultureProducers.contains(code) {
            reserves["agriculture"] = 80.0
        }
        if rareEarthProducers.contains(code) {
            reserves["rare_earths"] = 60.0
        }
        return reserves
    }

    static func starting(for country: PlayerCountry, scenario: NativeScenario) -> NativeEconomicLedger {
        NativeStrategyContextDatabase.startingEconomicLedger(for: country, scenario: scenario)
    }
}

struct NativeHexLever: Codable, Hashable {
    var growthDelta: Double
    var budgetDelta: Double
    var debtDelta: Double
    var inflationDelta: Double
    var tradeDelta: Double
    var fiscalSpaceDelta: Int
    var securityDelta: Double = 0.0
    var rebelDelta: Double = 0.0
    var invasionNudge: Int = 0

    /// The eighth hex nibble is the only model-authored path into map-control
    /// changes. It stays abstract on purpose: the engine turns these board-game
    /// nudges into region conflict records, while prompts avoid operational
    /// military or public-security instructions.
    var conflictMode: NativeRegionConflictMode? {
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
}

struct NativeActionMemory: Codable, Hashable, Identifiable {
    var actionID: String
    var createdAt: String
    var detail: String
    var economicSummary: String
    var id: String
    var resolvedAt: String?
    var ruleIDs: [String]
    var source: String
    var status: NativeActionStatus
    var title: String
}

struct NativeStrategyContextPacket: Hashable {
    var consequenceRules: [NativeConsequenceRule]
    var dynamicCountries: [String: String] = [:]
    var economicLedger: NativeEconomicLedger
    var facts: [NativeFactRecord]
    var recentActions: [NativeActionMemory]
    var semanticMemories: [NativeSemanticMemory] = []
    var aiCountryStates: [String: NativeAICountryState] = [:]
    var economicLedgers: [String: NativeEconomicLedger] = [:]

    var promptBlock: String {
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
        // Keep AI country state context compact (max 4 entries) to stay within the
        // 8,500-character Foundation Models prompt budget. Full AI state detail is
        // reserved for the dedicated globalAI generation lane.
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
            let govInfo = economicLedgers[code].map { " (\($0.governmentType), approval=\(String(format: "%.1f%%", $0.publicApprovalPercent)))" } ?? ""
            return "- \(code)\(govInfo): \(aiState.doctrine.rawValue), priority=\(aiState.budgetPriority.rawValue), relations=[\(topRelations.isEmpty ? "neutral" : topRelations)]"
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
        Government: \(economicLedger.governmentType) (Public Approval: \(String(format: "%.1f%%", economicLedger.publicApprovalPercent)), Next Election Round: \(economicLedger.nextElectionRound)).

        Key AI country postures (top 4 by relationship activity):
        \(aiLines.isEmpty ? "- No autonomous AI states configured." : aiLines)

        Use the IDs above as evidence. Do not invent starting facts or economic, public-security, insurgency, or map-control effects outside these ranges.
        """
    }
}

/// Local evidence and deterministic economics used by native generation.
///
/// Prompt packets from this database are the grounding layer for Apple
/// Foundation Models. Ledger updates here are deterministic and bounded so the
/// model can influence the campaign only through validated events and approved
/// consequence ranges.
enum NativeStrategyContextDatabase {
    /// Three completed, fully-ready strategic agendas are required for an AI
    /// country to earn a rival victory (34 + 34 + 34, clamped to 100).
    static let rivalAgendaVictoryAward = 34.0

    static var defaultStrategicCountryCodes: [String] {
        let mappedCodes = GeopoliticalMapData.regions.map(\.countryCode).filter { $0 != "WATER" }
        return Array(Set(CountryCatalog.all.map(\.code) + mappedCodes + ["GLOBAL"])).sorted()
    }

    static func strategicCountryCodes(for state: NativeCampaignState) -> [String] {
        Array(Set(defaultStrategicCountryCodes + Array(state.dynamicCountries.keys) + Array(state.economicLedgers.keys) + [state.country.code])).sorted()
    }

    private static let computedAdjacencyTable: [String: [String]] = {
        let landRegions = GeopoliticalMapData.regions.filter { $0.countryCode != "WATER" && !$0.countryCode.isEmpty }
        struct RegionEnvelope {
            let countryCode: String
            let minX: CGFloat
            let maxX: CGFloat
            let minY: CGFloat
            let maxY: CGFloat
            let samplePoints: [CGPoint]
        }
        let envelopes = landRegions.compactMap { region -> RegionEnvelope? in
            let points = region.rings.flatMap(\.self)
            guard !points.isEmpty else { return nil }
            var minX = CGFloat.greatestFiniteMagnitude
            var maxX = -CGFloat.greatestFiniteMagnitude
            var minY = CGFloat.greatestFiniteMagnitude
            var maxY = -CGFloat.greatestFiniteMagnitude
            for pt in points {
                if pt.x < minX { minX = pt.x }
                if pt.x > maxX { maxX = pt.x }
                if pt.y < minY { minY = pt.y }
                if pt.y > maxY { maxY = pt.y }
            }
            let step = max(1, points.count / 24)
            let sampled = stride(from: 0, to: points.count, by: step).map { points[$0] }
            return RegionEnvelope(
                countryCode: GeopoliticalMapData.canonicalCountryCode(region.countryCode),
                minX: minX,
                maxX: maxX,
                minY: minY,
                maxY: maxY,
                samplePoints: sampled
            )
        }

        let borderThreshold: CGFloat = 0.016
        let borderThresholdSq = borderThreshold * borderThreshold
        var neighborsByCountry: [String: Set<String>] = [
            "USA": ["CHN", "RUS", "GBR", "FRA", "CAN", "MEX"],
            "CHN": ["RUS", "IND", "JPN", "KOR"],
            "BRA": ["USA", "ZAF", "ARG"],
            "DEU": ["FRA", "GBR", "RUS", "ITA", "POL"],
            "JPN": ["CHN", "RUS", "AUS", "KOR", "USA"],
            "GBR": ["FRA", "DEU", "USA", "CAN"],
            "FRA": ["DEU", "GBR", "ZAF", "ITA", "ESP"],
            "IND": ["CHN", "RUS", "ZAF", "GBR"],
            "RUS": ["CHN", "DEU", "JPN", "USA", "POL"],
            "ZAF": ["BRA", "IND", "FRA", "GBR"],
            "AUS": ["JPN", "IND", "USA", "GBR"],
            "ITA": ["FRA", "DEU", "GBR", "ESP"],
            "CAN": ["USA", "GBR", "FRA"],
            "MEX": ["USA", "BRA", "ESP"],
            "KOR": ["JPN", "USA", "CHN"],
            "ESP": ["FRA", "GBR", "ITA", "DEU"],
            "TUR": ["RUS", "DEU", "FRA", "SAU"],
            "SAU": ["USA", "TUR", "FRA", "GBR"],
            "ARG": ["BRA", "USA", "ESP"],
            "POL": ["DEU", "RUS", "FRA", "GBR"]
        ]

        for i in 0 ..< envelopes.count {
            let a = envelopes[i]
            for j in (i + 1) ..< envelopes.count {
                let b = envelopes[j]
                guard a.countryCode != b.countryCode else { continue }
                guard a.maxX + borderThreshold >= b.minX,
                      b.maxX + borderThreshold >= a.minX,
                      a.maxY + borderThreshold >= b.minY,
                      b.maxY + borderThreshold >= a.minY
                else { continue }

                var touches = false
                outer: for pa in a.samplePoints {
                    for pb in b.samplePoints {
                        let dx = pa.x - pb.x
                        let dy = pa.y - pb.y
                        if dx * dx + dy * dy <= borderThresholdSq {
                            touches = true
                            break outer
                        }
                    }
                }
                if touches {
                    neighborsByCountry[a.countryCode, default: []].insert(b.countryCode)
                    neighborsByCountry[b.countryCode, default: []].insert(a.countryCode)
                }
            }
        }

        var result: [String: [String]] = [:]
        for (code, set) in neighborsByCountry {
            result[code] = set.sorted()
        }
        return result
    }()

    static func adjacentCountryCodes(for countryCode: String) -> [String] {
        let canonical = GeopoliticalMapData.canonicalCountryCode(countryCode)
        if let neighbors = computedAdjacencyTable[canonical], !neighbors.isEmpty {
            return neighbors
        }
        // Fallback for island nations without close polygon vertices: nearest 4 countries by centroid
        let allRegions = GeopoliticalMapData.regions.filter { $0.countryCode != "WATER" }
        guard let origin = allRegions.first(where: { GeopoliticalMapData.canonicalCountryCode($0.countryCode) == canonical })?.center else {
            return ["USA", "GBR", "DEU", "CHN"]
        }
        var bestByCountry: [String: CGFloat] = [:]
        for region in allRegions {
            let other = GeopoliticalMapData.canonicalCountryCode(region.countryCode)
            guard other != canonical, other != "WATER" else { continue }
            let dx = region.center.x - origin.x
            let dy = region.center.y - origin.y
            let distSq = dx * dx + dy * dy
            if let existing = bestByCountry[other] {
                bestByCountry[other] = min(existing, distSq)
            } else {
                bestByCountry[other] = distSq
            }
        }
        let nearest = bestByCountry.sorted { $0.value < $1.value }.prefix(4).map(\.key)
        return nearest.isEmpty ? ["USA", "GBR", "DEU", "CHN"] : nearest
    }

    static func startingGovernmentType(for code: String) -> String {
        switch code {
        case "CHN", "SAU": "autocracy"
        case "RUS": "hybrid"
        default: "democracy"
        }
    }

    enum DemocraticSubtype: String {
        case presidential
        case parliamentary
        case semiPresidential
    }

    static func democraticSubtype(for code: String) -> DemocraticSubtype {
        switch code {
        case "GBR", "DEU", "ZAF", "IND", "JPN", "AUS", "ITA", "CAN", "ESP", "TUR", "POL":
            .parliamentary
        case "FRA":
            .semiPresidential
        default:
            .presidential
        }
    }

    struct ElectionProfile {
        let startingRound: Int
        let cycleLength: Int
    }

    static func startingElectionProfile(
        for code: String,
        scenario: NativeScenario = NativeScenarioCatalog.defaultScenario
    ) -> ElectionProfile {
        let base: ElectionProfile = switch code {
        case "BRA":
            ElectionProfile(startingRound: 10, cycleLength: 48) // October 2010 (4 years)
        case "USA":
            ElectionProfile(startingRound: 35, cycleLength: 48) // November 2012 (4 years)
        case "GBR":
            ElectionProfile(startingRound: 5, cycleLength: 60) // May 2010 (5 years)
        case "DEU":
            ElectionProfile(startingRound: 45, cycleLength: 48) // September 2013 (4 years)
        case "FRA":
            ElectionProfile(startingRound: 29, cycleLength: 60) // May 2012 (5 years)
        case "ZAF":
            ElectionProfile(startingRound: 53, cycleLength: 60) // May 2014 (5 years)
        case "IND":
            ElectionProfile(startingRound: 53, cycleLength: 60) // May 2014 (5 years)
        case "JPN":
            ElectionProfile(startingRound: 36, cycleLength: 48) // December 2012 (4 years)
        case "AUS":
            ElectionProfile(startingRound: 8, cycleLength: 36) // August 2010 (3 years)
        case "RUS":
            ElectionProfile(startingRound: 27, cycleLength: 72) // March 2012 (6 years)
        case "ITA":
            ElectionProfile(startingRound: 37, cycleLength: 60) // February 2013 (5 years)
        case "CAN":
            ElectionProfile(startingRound: 16, cycleLength: 48) // May 2011 (4 years)
        case "MEX":
            ElectionProfile(startingRound: 30, cycleLength: 72) // July 2012 (6 years)
        case "ESP":
            ElectionProfile(startingRound: 23, cycleLength: 48) // November 2011 (4 years)
        case "KOR":
            ElectionProfile(startingRound: 36, cycleLength: 60) // December 2012 (5 years)
        default:
            ElectionProfile(startingRound: 48, cycleLength: 48)
        }
        guard !Native2010WorldModel.isReal2010Scenario(scenario) else {
            return base
        }
        let yearPrefix = Int(scenario.startDate.prefix(4)) ?? 2010
        let yearOffsetMonths = abs(yearPrefix - 2010) * 12
        let shiftedStart = ((base.startingRound + yearOffsetMonths - 1) % max(12, base.cycleLength)) + 1
        return ElectionProfile(startingRound: max(3, shiftedStart), cycleLength: base.cycleLength)
    }

    static func scenarioEconomicMultipliers(for scenario: NativeScenario) -> (gdpScale: Double, growthDelta: Double, inflationDelta: Double) {
        switch scenario.id {
        case "divided-sovereignty":
            (0.18, -1.2, -0.8)
        case "soviet-triumph":
            (0.55, -0.8, 1.4)
        case "fragmented-markets":
            (1.35, -0.9, 1.8)
        case "resource-crucible":
            (1.42, -0.6, 2.2)
        case "resilience-decade":
            (1.55, 0.4, 0.6)
        case "pax-cybernetica":
            (2.10, 1.1, -0.5)
        case "solarpunk-dawn":
            (2.35, 1.4, -0.9)
        default:
            (1.0, 0.0, 0.0)
        }
    }

    static func startingEconomicLedger(for country: PlayerCountry, scenario: NativeScenario) -> NativeEconomicLedger {
        let profile = Native2010WorldModel.profile(for: country)
        let supplement = economicSupplement(for: country.code, profile: profile)
        let eraMod = scenarioEconomicMultipliers(for: scenario)
        let openingSecurity = clampDouble(Double(profile.stability) + 18.0 - Double(profile.sanctionsExposurePercent) * 0.35, 35, 92)
        let openingRebelPressure = clampDouble(
            Double(100 - profile.stability) * 0.16 + Double(supplement.unemployment) * 0.22 - Double(supplement.fiscalSpace) * 0.04,
            0,
            28
        )
        let govType = startingGovernmentType(for: country.code)
        let electProfile = startingElectionProfile(for: country.code, scenario: scenario)
        let scaledGDP = max(0.01, Double(round(profile.nominalGDPTrillions * eraMod.gdpScale * 100) / 100))
        let scaledGrowth = clampDouble(profile.gdpGrowthPercent + eraMod.growthDelta, -12, 16)
        let scaledInflation = clampDouble(profile.inflationPercent + eraMod.inflationDelta, -4, 35)
        return NativeEconomicLedger(
            budgetBalancePercentGDP: supplement.budgetBalance,
            entries: [],
            fiscalSpaceIndex: supplement.fiscalSpace,
            inflationPercent: scaledInflation,
            nominalGDPTrillions: scaledGDP,
            publicDebtPercentGDP: supplement.publicDebt,
            realGrowthPercent: scaledGrowth,
            tradeBalancePercentGDP: profile.tradeBalancePercent,
            unemploymentPercent: supplement.unemployment,
            securityIndex: openingSecurity,
            rebelControlPercent: openingRebelPressure,
            governmentType: govType,
            publicApprovalPercent: 50.0,
            nextElectionRound: electProfile.startingRound
        )
    }

    static func startingEconomicLedger(forCode code: String, scenario: NativeScenario) -> NativeEconomicLedger {
        let dummyCountry = PlayerCountry(code: code, name: code)
        return startingEconomicLedger(for: dummyCountry, scenario: scenario)
    }

    static func effectAffectsCountry(effect: NativeStrategicEffect, countryCode: String) -> Bool {
        let targetLower = effect.target.lowercased()
        if isGlobal(targetLower) {
            return true
        }

        return countryAliases(for: countryCode).contains { alias in
            !alias.isEmpty && targetLower.contains(alias)
        }
    }

    private static func isGlobal(_ targetLower: String) -> Bool {
        targetLower.contains("global") || targetLower.contains("international") || targetLower.contains("system")
    }

    static func countryAliases(for code: String) -> [String] {
        let normalizedCode = code.lowercased()
        let catalogName = CountryCatalog.all.first { $0.code == code }?.name.lowercased()
        let fixedAliases: [String] = switch code {
        case "USA":
            ["us", "u.s.", "usa", "united states", "america"]
        case "CHN":
            ["chn", "china"]
        case "BRA":
            ["bra", "brazil", "brasil"]
        case "DEU":
            ["deu", "germany", "deutschland"]
        case "GBR":
            ["gbr", "united kingdom", "uk", "britain"]
        case "RUS":
            ["rus", "russia"]
        case "ZAF":
            ["zaf", "south africa"]
        default:
            [normalizedCode]
        }
        return Array(Set(([normalizedCode, catalogName].compactMap(\.self) + fixedAliases).map { $0.lowercased() }))
    }

    static func contextPacket(for state: NativeCampaignState, months _: Int, action: NativePlannedAction? = nil) -> NativeStrategyContextPacket {
        NativeStrategyContextPacket(
            consequenceRules: consequenceRules(for: action, state: state),
            dynamicCountries: state.dynamicCountries,
            economicLedger: state.economicLedger,
            facts: facts(for: state, action: action),
            recentActions: state.actionMemory.prefix(8).map(\.self),
            semanticMemories: semanticMemories(for: state, action: action),
            aiCountryStates: state.aiCountryStates,
            economicLedgers: state.economicLedgers
        )
    }

    static func estimatedLaneCount(for state: NativeCampaignState) -> Int {
        5 + min(3, state.plannedActions.filter { $0.status == .planned }.count)
    }

    static func remember(action: NativePlannedAction, in records: [NativeActionMemory], source: String, state: NativeCampaignState) -> [NativeActionMemory] {
        var next = records.filter { $0.actionID != action.id }
        let rules = consequenceRules(for: action, state: state)
        next.insert(NativeActionMemory(
            actionID: action.id,
            createdAt: action.createdAt,
            detail: action.detail,
            economicSummary: rules.first?.summary ?? "Awaiting economic assessment.",
            id: "memory-\(action.id)",
            resolvedAt: action.resolvedAt,
            ruleIDs: rules.map(\.id),
            source: source,
            status: action.status,
            title: action.title
        ), at: 0)
        return next
    }

    static func updatedActionMemory(
        state: NativeCampaignState,
        resolvedActions: [NativePlannedAction],
        events: [NativeCampaignEvent],
        targetDate: String
    ) -> [NativeActionMemory] {
        var records = state.actionMemory
        for action in resolvedActions where action.status == .resolved && action.resolvedAt == targetDate {
            let linkedEvents = events.filter { $0.linkedActionIDs.contains(action.id) }
            let ruleIDs = consequenceRules(for: action, state: state).map(\.id)
            let summary = linkedEvents.first?.strategicEffects.first?.summary ?? "Resolved with limited measurable effect."
            records.removeAll { $0.actionID == action.id }
            records.insert(NativeActionMemory(
                actionID: action.id,
                createdAt: action.createdAt,
                detail: action.detail,
                economicSummary: summary,
                id: "memory-\(action.id)",
                resolvedAt: action.resolvedAt ?? targetDate,
                ruleIDs: ruleIDs,
                source: "resolved-turn",
                status: .resolved,
                title: action.title
            ), at: 0)
        }
        return records
    }

    static func updatedSemanticMemory(state: NativeCampaignState, events: [NativeCampaignEvent]) -> [NativeSemanticMemory] {
        var records = state.semanticMemory
        var existing = Set(records.map(\.sourceID))
        for event in events where !existing.contains(event.id) {
            let track = event.strategicEffects.first?.track ?? (event.playerRelated ? .internalStability : .worldTension)
            let effects = event.strategicEffects
                .prefix(3)
                .map { "\(foundationPromptTrackLabel($0.track)) \($0.magnitude): \($0.summary)" }
                .joined(separator: "; ")
            let text = sanitizeFoundationModelText("\(event.title). \(event.description) \(effects)")
            guard !text.isEmpty else { continue }
            records.insert(NativeSemanticMemory(
                date: event.date,
                embedding: NativeTinyEmbeddingModel.embed("\(foundationPromptTrackLabel(track)) \(text)"),
                id: "semantic-\(event.id)",
                importance: event.importance.semanticWeight,
                sourceID: event.id,
                text: String(text.prefix(320)),
                track: track
            ), at: 0)
            existing.insert(event.id)
        }
        // The local query path ranks a bounded result set below, but storage keeps
        // the full archive so long campaigns do not silently forget old events.
        return records
    }

    private static func semanticMemories(for state: NativeCampaignState, action: NativePlannedAction?) -> [NativeSemanticMemory] {
        let query = [
            state.scenarioName,
            state.country.name,
            state.lastSummary,
            action?.title,
            action?.detail,
            state.plannedActions.prefix(3).map { "\($0.title) \($0.detail)" }.joined(separator: " ")
        ].compactMap(\.self).joined(separator: " ")
        let queryEmbedding = NativeTinyEmbeddingModel.embed(query)
        return state.semanticMemory
            .map { memory in
                let similarity = NativeTinyEmbeddingModel.cosine(queryEmbedding, memory.embedding)
                let importanceBoost = Double(memory.importance) * 0.02
                return (score: similarity + importanceBoost, memory: memory)
            }
            .filter { $0.score > 0.05 }
            .sorted { $0.score > $1.score }
            .prefix(5)
            .map(\.memory)
    }

    static func updatedMarketState(
        from market: LWMarket,
        state: NativeCampaignState,
        months: Int
    ) -> LWMarket {
        let goods = LivingWorldFactory.defaultGoods
        var nextMarket = market
        nextMarket.resetOrders()

        let totalMarkets = Double(state.mapBuildings.filter { $0.type == .market }.reduce(0) { $0 + $1.level })
        let totalPorts = Double(state.mapBuildings.filter { $0.type == .port }.reduce(0) { $0 + $1.level })
        let totalBarracks = Double(state.mapBuildings.filter { $0.type == .barracks }.reduce(0) { $0 + $1.level })
        let totalFortresses = Double(state.mapBuildings.filter { $0.type == .fortress }.reduce(0) { $0 + $1.level })

        let globalGDP = max(1.0, state.economicLedgers.values.reduce(0.0) { $0 + $1.nominalGDPTrillions })
        let playerForces = Double(state.militaryUnits.values.reduce(0, +))
        let tensionFactor = 1.0 + Double(state.worldTension) / 100.0

        for good in goods {
            let baseSupply = globalGDP * 0.8 + totalMarkets * 2.5 + totalPorts * 2.0
            let baseDemand = globalGDP * 0.78
            switch good.category {
            case .stapleFood, .luxuryFood:
                nextMarket.addSupply(baseSupply * 1.05, goodID: good.id)
                nextMarket.addDemand(baseDemand * (1.0 + Double(100 - state.stability) * 0.003), goodID: good.id)
            case .minerals, .lumber, .steel:
                nextMarket.addSupply(baseSupply + totalPorts * 1.5, goodID: good.id)
                nextMarket.addDemand(baseDemand * (1.0 + state.budgetResearchSlider * 0.25), goodID: good.id)
            case .machinery, .consumerGoods, .textiles:
                nextMarket.addSupply(baseSupply + totalMarkets * 2.0, goodID: good.id)
                nextMarket.addDemand(baseDemand * (1.0 + state.budgetServicesSlider * 0.3), goodID: good.id)
            case .militaryMateriel:
                nextMarket.addSupply(baseSupply * 0.7 + totalBarracks * 2.5 + totalFortresses * 1.5, goodID: good.id)
                nextMarket.addDemand(
                    (baseDemand * 0.65 + playerForces * 0.08) * tensionFactor * (0.8 + state.budgetMilitarySlider),
                    goodID: good.id
                )
            }
        }

        let ticks = max(1, min(12, months * 3))
        for _ in 0 ..< ticks {
            nextMarket.resolveDay(goods: goods)
        }
        return nextMarket
    }

    /// **Ledger Update Mechanic**:
    /// Processes the economic impact of events across all country ledgers.
    /// Handles AI generated rules, Hex Lever map nudges, deterministic market drift,
    /// Living World commodity market price discovery, and stability-based feedback loops.
    static func updatedEconomicLedgers(
        from ledgers: [String: NativeEconomicLedger],
        state: NativeCampaignState,
        events: [NativeCampaignEvent],
        months: Int,
        targetDate: String
    ) -> [String: NativeEconomicLedger] {
        var nextLedgers = ledgers
        let resolvedMarket = updatedMarketState(from: state.marketState, state: state, months: months)
        let goods = LivingWorldFactory.defaultGoods
        let avgPriceRatio: Double = {
            guard !goods.isEmpty else { return 1.0 }
            let sum = goods.reduce(0.0) { acc, good in
                acc + (resolvedMarket.price(for: good.id) / max(0.01, good.basePrice))
            }
            return sum / Double(goods.count)
        }()
        let marketInflationNudge = clampDouble((avgPriceRatio - 1.0) * 0.35 * Double(months), -0.25, 0.35)

        let countryCodes = strategicCountryCodes(for: state)
        let scenario = NativeScenarioCatalog.scenario(for: state.scenarioID)
        for code in countryCodes {
            if nextLedgers[code] == nil {
                nextLedgers[code] = startingEconomicLedger(forCode: code, scenario: scenario)
            }
        }

        let negativeMultiplier = switch state.gameMode {
        case .sandbox: 0.5
        case .normal: 1.0
        case .ironman: 2.0
        }

        // Build the map indexes once per turn. The previous path rescanned all
        // map regions and all buildings for every country ledger.
        var regionIDsByController: [String: Set<String>] = [:]
        for region in GeopoliticalMapData.regions {
            let controller = state.regionOccupations[region.id] ?? region.countryCode
            regionIDsByController[controller, default: []].insert(region.id)
        }
        let buildingsByRegion = Dictionary(grouping: state.mapBuildings, by: \.regionID)

        for (code, ledger) in nextLedgers {
            var nextLedger = ledger
            var entries = ledger.entries

            for event in events {
                guard let effect = event.strategicEffects.first(where: { effectAffectsCountry(effect: $0, countryCode: code) }) else {
                    continue
                }

                let entry: NativeEconomicLedgerEntry
                if let hex = event.hexLeverCode, let lever = decodeHexLever(hex) {
                    let rawBudget = lever.budgetDelta
                    let rawGrowth = lever.growthDelta
                    let rawInflation = lever.inflationDelta
                    let rawTrade = lever.tradeDelta
                    let rawDebt = lever.debtDelta
                    let rawSecurity = lever.securityDelta + securityNudge(for: lever.invasionNudge)
                    let rawRebel = lever.rebelDelta + rebelNudge(for: lever.invasionNudge)

                    let adjBudget = rawBudget < 0 ? rawBudget * negativeMultiplier : rawBudget
                    let adjGrowth = rawGrowth < 0 ? rawGrowth * negativeMultiplier : rawGrowth
                    let adjInflation = rawInflation > 0 ? rawInflation * negativeMultiplier : rawInflation
                    let adjTrade = rawTrade < 0 ? rawTrade * negativeMultiplier : rawTrade
                    let adjDebt = rawDebt > 0 ? rawDebt * negativeMultiplier : rawDebt
                    let adjSecurity = rawSecurity < 0 ? rawSecurity * negativeMultiplier : rawSecurity
                    let adjRebel = rawRebel > 0 ? rawRebel * negativeMultiplier : rawRebel

                    entry = NativeEconomicLedgerEntry(
                        budgetBalanceDelta: clampDouble(adjBudget, -0.8, 0.8),
                        debtDelta: clampDouble(adjDebt, -1.8, 1.8),
                        eventID: event.id,
                        fiscalSpaceDelta: max(-8, min(8, lever.fiscalSpaceDelta)),
                        growthDelta: clampDouble(adjGrowth, -0.9, 0.9),
                        id: "econ-\(event.id)-\(code.lowercased())",
                        inflationDelta: clampDouble(adjInflation, -0.7, 0.7),
                        ruleID: "hex-lever-\(hex.lowercased())",
                        summary: "\(event.title): Hex lever \(hex.lowercased()) applied (\(conflictNudgeLabel(for: lever.invasionNudge))).",
                        tradeBalanceDelta: clampDouble(adjTrade, -0.8, 0.8),
                        turnDate: targetDate,
                        securityDelta: clampDouble(adjSecurity, -25.0, 25.0),
                        rebelDelta: clampDouble(adjRebel, -25.0, 25.0)
                    )
                } else {
                    let linkedAction = state.plannedActions.first { action in
                        event.linkedActionIDs.contains(action.id)
                    }
                    let rule = consequenceRules(for: linkedAction, state: state).first ?? rule(for: event)
                    let magnitude = Double(effect.magnitude)

                    let defaultSecurityDelta = effect.track == .internalStability ? magnitude * 2.0 : (effect.track == .securityAnxiety ? -magnitude * 2.0 : 0.0)
                    let defaultRebelDelta = -defaultSecurityDelta * 0.5

                    let rawBudget = rule.budgetBalanceDelta + magnitude * 0.015
                    let rawDebt = rule.debtDelta - magnitude * 0.04
                    let rawGrowth = rule.growthDelta + magnitude * 0.025
                    let rawInflation = rule.inflationDelta + (effect.track == .marketConfidence ? -magnitude * 0.01 : 0)
                    let rawTrade = rule.tradeBalanceDelta + magnitude * 0.015

                    let adjBudget = rawBudget < 0 ? rawBudget * negativeMultiplier : rawBudget
                    let adjGrowth = rawGrowth < 0 ? rawGrowth * negativeMultiplier : rawGrowth
                    let adjInflation = rawInflation > 0 ? rawInflation * negativeMultiplier : rawInflation
                    let adjTrade = rawTrade < 0 ? rawTrade * negativeMultiplier : rawTrade
                    let adjDebt = rawDebt > 0 ? rawDebt * negativeMultiplier : rawDebt
                    let adjSecurity = defaultSecurityDelta < 0 ? defaultSecurityDelta * negativeMultiplier : defaultSecurityDelta
                    let adjRebel = defaultRebelDelta > 0 ? defaultRebelDelta * negativeMultiplier : defaultRebelDelta

                    entry = NativeEconomicLedgerEntry(
                        budgetBalanceDelta: clampDouble(adjBudget, -0.8, 0.8),
                        debtDelta: clampDouble(adjDebt, -1.8, 1.8),
                        eventID: event.id,
                        fiscalSpaceDelta: max(-8, min(8, rule.fiscalSpaceDelta + Int(magnitude.rounded()))),
                        growthDelta: clampDouble(adjGrowth, -0.9, 0.9),
                        id: "econ-\(event.id)-\(code.lowercased())",
                        inflationDelta: clampDouble(adjInflation, -0.7, 0.7),
                        ruleID: rule.id,
                        summary: "\(event.title): \(rule.description)",
                        tradeBalanceDelta: clampDouble(adjTrade, -0.8, 0.8),
                        turnDate: targetDate,
                        securityDelta: clampDouble(adjSecurity, -20.0, 20.0),
                        rebelDelta: clampDouble(adjRebel, -20.0, 20.0)
                    )
                }

                entries.insert(entry, at: 0)
                nextLedger.budgetBalancePercentGDP += entry.budgetBalanceDelta
                nextLedger.publicDebtPercentGDP += entry.debtDelta
                nextLedger.realGrowthPercent += entry.growthDelta
                nextLedger.inflationPercent += entry.inflationDelta
                nextLedger.tradeBalancePercentGDP += entry.tradeBalanceDelta
                nextLedger.securityIndex = clampDouble(nextLedger.securityIndex + (entry.securityDelta ?? 0.0), 0, 100)
                nextLedger.rebelControlPercent = clampDouble(nextLedger.rebelControlPercent + (entry.rebelDelta ?? 0.0), 0, 100)
                nextLedger.fiscalSpaceIndex = max(0, min(100, nextLedger.fiscalSpaceIndex + entry.fiscalSpaceDelta))
            }

            // Apply deterministic background drift. The seeded RNG makes the
            // same campaign state produce the same ledger adjustment, avoiding
            // replay surprises while still giving non-player economies motion.
            if let stochastic = rollStochasticEvent(for: nextLedger, code: code, targetDate: targetDate) {
                let sEntry = NativeEconomicLedgerEntry(
                    budgetBalanceDelta: clampDouble(stochastic.deltas.budgetDelta, -0.8, 0.8),
                    debtDelta: clampDouble(stochastic.deltas.debtDelta, -1.8, 1.8),
                    eventID: "stochastic-\(code.lowercased())-\(targetDate)",
                    fiscalSpaceDelta: max(-8, min(8, stochastic.deltas.fiscalSpaceDelta)),
                    growthDelta: clampDouble(stochastic.deltas.growthDelta, -0.9, 0.9),
                    id: "econ-stochastic-\(code.lowercased())-\(targetDate)",
                    inflationDelta: clampDouble(stochastic.deltas.inflationDelta, -0.7, 0.7),
                    ruleID: "stochastic",
                    summary: stochastic.summary,
                    tradeBalanceDelta: clampDouble(stochastic.deltas.tradeDelta, -0.8, 0.8),
                    turnDate: targetDate
                )

                if !stochastic.summary.contains("Market noise") {
                    entries.insert(sEntry, at: 0)
                }

                nextLedger.budgetBalancePercentGDP += sEntry.budgetBalanceDelta
                nextLedger.publicDebtPercentGDP += sEntry.debtDelta
                nextLedger.realGrowthPercent += sEntry.growthDelta
                nextLedger.inflationPercent += sEntry.inflationDelta
                nextLedger.tradeBalancePercentGDP += sEntry.tradeBalanceDelta
                nextLedger.fiscalSpaceIndex = max(0, min(100, nextLedger.fiscalSpaceIndex + sEntry.fiscalSpaceDelta))
            }

            // Apply stability-based security drift and rebel growth feedback
            if code != "GLOBAL" {
                let stabilityScore = Double(state.stability)
                let fiscalStress = max(0.0, Double(45 - nextLedger.fiscalSpaceIndex)) * 0.035
                let unemploymentStress = max(0.0, nextLedger.unemploymentPercent - 8.0) * 0.08
                let debtStress = max(0.0, nextLedger.publicDebtPercentGDP - 90.0) * 0.01
                let stabilitySecurityDrift = (stabilityScore - 60.0) * 0.05 - fiscalStress - unemploymentStress - debtStress
                nextLedger.securityIndex = clampDouble(nextLedger.securityIndex + stabilitySecurityDrift, 0, 100)

                let rebelGrowthRate = nextLedger.securityIndex < 55.0
                    ? (55.0 - nextLedger.securityIndex) * 0.16 + unemploymentStress
                    : -1.5
                nextLedger.rebelControlPercent = clampDouble(nextLedger.rebelControlPercent + rebelGrowthRate, 0, 100)

                if nextLedger.rebelControlPercent > 20.0 {
                    let dragMultiplier = negativeMultiplier
                    nextLedger.realGrowthPercent = clampDouble(nextLedger.realGrowthPercent - (nextLedger.rebelControlPercent * 0.005 * dragMultiplier), -12, 16)
                    nextLedger.publicDebtPercentGDP = clampDouble(nextLedger.publicDebtPercentGDP + (nextLedger.rebelControlPercent * 0.02 * dragMultiplier), 1, 260)
                }

                // **Neighbor Proximity Spillover**:
                let neighbors = adjacentCountryCodes(for: code)
                var neighborRebelSpillover = 0.0
                for nCode in neighbors {
                    if let nLedger = nextLedgers[nCode], nLedger.rebelControlPercent > 30.0 {
                        neighborRebelSpillover += (nLedger.rebelControlPercent - 30.0) * 0.01
                    }
                }
                nextLedger.rebelControlPercent = clampDouble(nextLedger.rebelControlPercent + neighborRebelSpillover * Double(months), 0, 100)

                // **Market & Port Buildings Integration + LWMarket Price Discovery**:
                let controlledRegionIDs = regionIDsByController[code, default: []]
                let countryBuildings = controlledRegionIDs.flatMap { buildingsByRegion[$0, default: []] }
                let marketLevels = countryBuildings.filter { $0.type == .market }.reduce(0) { $0 + $1.level }
                let portLevels = countryBuildings.filter { $0.type == .port }.reduce(0) { $0 + $1.level }

                nextLedger.realGrowthPercent = clampDouble(nextLedger.realGrowthPercent + Double(marketLevels) * 0.05 * Double(months), -12, 16)
                nextLedger.tradeBalancePercentGDP = clampDouble(nextLedger.tradeBalancePercentGDP + Double(portLevels) * 0.10 * Double(months), -20, 20)
                if marketLevels + portLevels > 0 {
                    nextLedger.inflationPercent = clampDouble(nextLedger.inflationPercent + marketInflationNudge, -4, 35)
                }

                // **Tech Diffusion & Catch-Up**:
                let era = state.techEraTyped
                let isAdvanced = era == .aiAge || era == .biotech || era == .cleanEnergy
                if isAdvanced, let playerRel = state.aiCountryStates[code]?.relationshipScores[state.country.code] {
                    if playerRel > 30 {
                        nextLedger.realGrowthPercent = clampDouble(nextLedger.realGrowthPercent + 0.15 * Double(months), -12, 16)
                    } else if playerRel < -20 {
                        nextLedger.realGrowthPercent = clampDouble(nextLedger.realGrowthPercent - 0.10 * Double(months), -12, 16)
                    }
                }

                // **Economic Interdependence**:
                let otherStrategicCountries = strategicCountryCodes(for: state).filter { $0 != code && $0 != "GLOBAL" }
                if !otherStrategicCountries.isEmpty {
                    let avgOtherGrowth = otherStrategicCountries.reduce(0.0) { sum, otherCode in
                        sum + (nextLedgers[otherCode]?.realGrowthPercent ?? 0.0)
                    } / Double(otherStrategicCountries.count)
                    let globalTradeDrift = avgOtherGrowth * 0.03 * Double(months)
                    nextLedger.tradeBalancePercentGDP = clampDouble(nextLedger.tradeBalancePercentGDP + globalTradeDrift, -20.0, 20.0)
                }
            }

            let yearFraction = max(1.0, Double(months)) / 12.0
            nextLedger.nominalGDPTrillions = max(0.01, nextLedger.nominalGDPTrillions * (1.0 + (nextLedger.realGrowthPercent / 100.0) * yearFraction))
            nextLedger.budgetBalancePercentGDP = clampDouble(nextLedger.budgetBalancePercentGDP, -12, 12)
            nextLedger.publicDebtPercentGDP = clampDouble(nextLedger.publicDebtPercentGDP, 1, 260)
            nextLedger.realGrowthPercent = clampDouble(nextLedger.realGrowthPercent, -12, 16)
            nextLedger.inflationPercent = clampDouble(nextLedger.inflationPercent, -4, 35)
            nextLedger.tradeBalancePercentGDP = clampDouble(nextLedger.tradeBalancePercentGDP, -20, 20)
            nextLedger.unemploymentPercent = clampDouble(nextLedger.unemploymentPercent - Double(nextLedger.fiscalSpaceIndex - ledger.fiscalSpaceIndex) * 0.01, 1, 35)
            nextLedger.securityIndex = clampDouble(nextLedger.securityIndex, 0, 100)
            nextLedger.rebelControlPercent = clampDouble(nextLedger.rebelControlPercent, 0, 100)
            nextLedger.entries = entries

            nextLedgers[code] = nextLedger
        }

        return nextLedgers
    }

    static func normalizedEconomicLedger(_ ledger: NativeEconomicLedger, for country: PlayerCountry, scenario: NativeScenario) -> NativeEconomicLedger {
        let baseline = startingEconomicLedger(for: country, scenario: scenario)
        var next = ledger
        if next.nominalGDPTrillions <= 0 || next.fiscalSpaceIndex < 0 || next.fiscalSpaceIndex > 100 {
            next = baseline
        }
        next.budgetBalancePercentGDP = clampDouble(next.budgetBalancePercentGDP, -12, 12)
        next.publicDebtPercentGDP = clampDouble(next.publicDebtPercentGDP, 1, 260)
        next.realGrowthPercent = clampDouble(next.realGrowthPercent, -12, 16)
        next.inflationPercent = clampDouble(next.inflationPercent, -4, 35)
        next.tradeBalancePercentGDP = clampDouble(next.tradeBalancePercentGDP, -20, 20)
        next.unemploymentPercent = clampDouble(next.unemploymentPercent, 1, 35)
        next.fiscalSpaceIndex = max(0, min(100, next.fiscalSpaceIndex))
        next.securityIndex = clampDouble(next.securityIndex, 0, 100)
        next.rebelControlPercent = clampDouble(next.rebelControlPercent, 0, 100)
        return next
    }

    static func promptPacket(for state: NativeCampaignState, months: Int, action: NativePlannedAction? = nil) -> String {
        contextPacket(for: state, months: months, action: action).promptBlock
    }

    private static func facts(for state: NativeCampaignState, action: NativePlannedAction?) -> [NativeFactRecord] {
        let actionText = "\(action?.title ?? "") \(action?.detail ?? "")".lowercased()
        let countryFacts = factRecords.filter { fact in
            fact.countryCodes.isEmpty || fact.countryCodes.contains(state.country.code) || fact.countryCodes.contains("GLOBAL")
        }
        let taggedFacts = countryFacts.filter { fact in
            actionText.isEmpty || fact.tags.contains { actionText.contains($0) }
        }
        return taggedFacts.isEmpty ? Array(countryFacts.prefix(6)) : Array(taggedFacts.prefix(6))
    }

    private static func consequenceRules(for action: NativePlannedAction?, state _: NativeCampaignState) -> [NativeConsequenceRule] {
        guard let action else {
            return [
                rulesByID["macro-demand"]!,
                rulesByID["market-confidence"]!,
                rulesByID["fiscal-drift"]!,
                rulesByID["public-security"]!,
                rulesByID["insurgency-containment"]!
            ]
        }
        let text = "\(action.title) \(action.detail)".lowercased()
        let matches = consequenceRules.filter { rule in
            rule.keywords.contains { text.contains($0) }
        }
        return matches.isEmpty ? [rulesByID["default-civic"]!] : Array(matches.prefix(4))
    }

    private static func rule(for event: NativeCampaignEvent) -> NativeConsequenceRule {
        let track = event.strategicEffects.first?.track ?? .marketConfidence
        switch track {
        case .economicResilience:
            return rulesByID["infrastructure-resilience"]!
        case .marketConfidence:
            return rulesByID["market-confidence"]!
        case .diplomaticLeverage:
            return rulesByID["trade-diplomacy"]!
        case .internalStability:
            return rulesByID["service-delivery"]!
        case .worldTension, .securityAnxiety:
            return rulesByID["external-shock"]!
        case .militaryReadiness:
            return rulesByID["default-civic"]!
        }
    }

    private static let economicSupplements: [String: (budgetBalance: Double, publicDebt: Double, unemployment: Double, fiscalSpace: Int)] = [
        "USA": (-8.6, 95.0, 9.6, 42),
        "CHN": (-1.7, 34.0, 4.1, 71),
        "BRA": (-2.7, 63.0, 6.7, 58),
        "DEU": (-4.2, 82.0, 7.0, 67),
        "JPN": (-8.3, 205.0, 5.1, 35),
        "GBR": (-10.0, 75.0, 7.8, 38),
        "FRA": (-6.9, 85.0, 9.3, 44),
        "IND": (-4.8, 66.0, 5.6, 54),
        "RUS": (-3.4, 12.0, 7.3, 62),
        "ZAF": (-4.8, 34.0, 24.7, 36),
        "AUS": (-4.2, 20.0, 5.2, 69),
        "ITA": (-5.3, 115.0, 8.4, 40),
        "CAN": (-4.8, 81.0, 8.0, 60),
        "MEX": (-2.8, 42.0, 5.3, 58),
        "KOR": (-1.1, 30.0, 3.7, 72),
        "ESP": (-9.4, 60.0, 19.9, 32),
        "TUR": (-3.0, 40.0, 10.7, 52),
        "SAU": (6.8, 8.0, 5.5, 85),
        "ARG": (-1.8, 43.0, 7.7, 45),
        "POL": (-7.3, 53.0, 9.7, 50),
        "GLOBAL": (-3.5, 58.0, 8.0, 48)
    ]

    static func economicSupplement(for code: String, profile: Native2010CountryProfile) -> (budgetBalance: Double, publicDebt: Double, unemployment: Double, fiscalSpace: Int) {
        if let exact = economicSupplements[code] {
            return exact
        }
        let debt = clampDouble(Double(100 - profile.stability) * 0.75 + Double(profile.sanctionsExposurePercent) * 2.0 + 38.0, 18, 120)
        let unemp = clampDouble(Double(100 - profile.stability) * 0.16 + 4.8, 3.5, 24.0)
        let balance = clampDouble(profile.tradeBalancePercent * 0.45 - 3.4, -9.0, 4.0)
        let fiscalSpace = max(18, min(82, Int(100 - debt * 0.55 + Double(profile.energySecurity) * 0.2)))
        return (balance, debt, unemp, fiscalSpace)
    }

    private static let factRecords: [NativeFactRecord] = [
        NativeFactRecord(countryCodes: ["GLOBAL"], detail: "The opening economy is still absorbing the 2008-2009 financial shock, with fiscal stimulus unwinding unevenly.", id: "GLOBAL_2010_POST_CRISIS_RECOVERY", startDate: "2010-01-01", tags: ["budget", "growth", "market", "fiscal"], title: "Post-crisis recovery"),
        NativeFactRecord(countryCodes: ["GLOBAL"], detail: "Energy import exposure matters for inflation, trade balance, and public confidence in infrastructure plans.", id: "GLOBAL_2010_ENERGY_EXPOSURE", startDate: "2010-01-01", tags: ["energy", "infrastructure", "inflation"], title: "Energy exposure"),
        NativeFactRecord(countryCodes: ["GLOBAL"], detail: "Public security capacity affects institutional trust, budget strain, service delivery, and the chance that local unrest becomes territorial control.", id: "GLOBAL_2010_PUBLIC_SECURITY_CAPACITY", startDate: "2010-01-01", tags: ["security", "public order", "insurgency", "rebel", "stability"], title: "Public security capacity"),
        NativeFactRecord(countryCodes: ["GLOBAL"], detail: "Border pressure and unresolved occupations can damage trade corridors even when no capital region changes hands.", id: "GLOBAL_2010_BORDER_PRESSURE", startDate: "2010-01-01", tags: ["border", "occupation", "conventional", "corridor", "trade"], title: "Border pressure"),
        NativeFactRecord(countryCodes: ["USA"], detail: "The United States starts with high deficits, high unemployment, and exceptional reserve-currency financing capacity.", id: "USA_2010_DEFICIT_RECOVERY", startDate: "2010-01-01", tags: ["budget", "debt", "employment"], title: "US deficit recovery"),
        NativeFactRecord(countryCodes: ["CHN"], detail: "China enters 2010 with strong growth, high investment, trade surplus, and rising inflation watchpoints.", id: "CHN_2010_STIMULUS_GROWTH", startDate: "2010-01-01", tags: ["growth", "trade", "inflation"], title: "China stimulus growth"),
        NativeFactRecord(countryCodes: ["BRA"], detail: "Brazil starts with strong growth, commodity leverage, manageable debt, and inflation pressure from demand.", id: "BRA_2010_COMMODITY_EXPANSION", startDate: "2010-01-01", tags: ["commodity", "energy", "budget", "growth"], title: "Brazil commodity expansion"),
        NativeFactRecord(countryCodes: ["DEU", "FRA", "GBR"], detail: "European economies face Eurozone debt stress, bank repair, and tighter fiscal politics.", id: "EUROPE_2010_DEBT_STRESS", startDate: "2010-01-01", tags: ["budget", "debt", "market"], title: "European debt stress"),
        NativeFactRecord(countryCodes: ["JPN"], detail: "Japan starts with deflation pressure, heavy public debt, advanced industry, and high energy import dependence.", id: "JPN_2010_DEFLATION_DEBT", startDate: "2010-01-01", tags: ["debt", "energy", "industry"], title: "Japan deflation and debt"),
        NativeFactRecord(countryCodes: ["IND"], detail: "India starts with fast growth, infrastructure bottlenecks, inflation pressure, and rising services capacity.", id: "IND_2010_GROWTH_INFLATION", startDate: "2010-01-01", tags: ["growth", "inflation", "infrastructure"], title: "India growth and inflation"),
        NativeFactRecord(countryCodes: ["RUS", "SOV"], detail: "The GKChP State Emergency Committee maintained union integrity, halting market shock therapy in favor of cybernetic Gosplan optimization.", id: "SOVIET_1991_GKCHP_COUP", startDate: "1991-08-19", tags: ["soviet", "planning", "security", "bipolar"], title: "GKChP Union Integrity"),
        NativeFactRecord(countryCodes: ["GBR", "FRA"], detail: "Imperial standoff at Fashoda established divided colonial sovereignty along the Upper Nile basin under strict naval parity.", id: "FASHODA_1898_NILE_CONFRONTATION", startDate: "1898-09-18", tags: ["fashoda", "colonial", "naval", "sovereignty"], title: "Fashoda Sovereign Standoff"),
        NativeFactRecord(countryCodes: ["GLOBAL"], detail: "Global aquifer depletion has forced militarized resource checkpoints along trans-border agricultural trade corridors.", id: "RESOURCE_2035_AQUIFER_DEPLETION", startDate: "2035-03-01", tags: ["resource", "water", "logistics", "checkpoint"], title: "Aquifer Depletion Crisis"),
        NativeFactRecord(countryCodes: ["GLOBAL"], detail: "Autonomous cybernetic networks and high-frequency trading protocol bridges enforce automated market clearing.", id: "PAX_2055_CYBERNETIC_PLANNING", startDate: "2055-01-01", tags: ["cyber", "automation", "grid", "dao"], title: "Algorithmic Infrastructure"),
        NativeFactRecord(countryCodes: ["GLOBAL"], detail: "Bioregional ecological assemblies have instituted strict biocapacity accounting and shared microgrid cooperatives.", id: "SOLARPUNK_2060_BIOCAPACITY_PACT", startDate: "2060-01-01", tags: ["ecology", "climate", "bioregion", "solarpunk"], title: "Bioregional Ecological Assembly")
    ]

    private static let consequenceRules: [NativeConsequenceRule] = [
        NativeConsequenceRule(budgetBalanceDelta: -0.18, debtDelta: 0.28, description: "Fiscal buffers reduce short-run risk but widen the deficit until revenue or cuts offset the commitment.", fiscalSpaceDelta: 3, growthDelta: 0.04, id: "fiscal-buffer", inflationDelta: 0.02, keywords: ["buffer", "reserve", "bond", "fiscal"], summary: "Budget buffer: safer services, weaker near-term surplus.", tradeBalanceDelta: 0.00, track: .economicResilience),
        NativeConsequenceRule(budgetBalanceDelta: -0.25, debtDelta: 0.32, description: "Infrastructure spending raises capacity and growth, with near-term deficit pressure and modest import leakage.", fiscalSpaceDelta: 4, growthDelta: 0.16, id: "infrastructure-resilience", inflationDelta: 0.04, keywords: ["grid", "energy", "infrastructure", "transport", "port", "rail"], summary: "Infrastructure: higher growth capacity with upfront fiscal cost.", tradeBalanceDelta: -0.04, track: .economicResilience),
        NativeConsequenceRule(budgetBalanceDelta: -0.08, debtDelta: 0.08, description: "Administrative delivery improves confidence without a large fiscal impulse.", fiscalSpaceDelta: 2, growthDelta: 0.05, id: "service-delivery", inflationDelta: -0.01, keywords: ["service", "education", "audit", "agency", "administrative"], summary: "Service delivery: stability and confidence gains at low cost.", tradeBalanceDelta: 0.00, track: .internalStability),
        NativeConsequenceRule(budgetBalanceDelta: 0.04, debtDelta: -0.05, description: "Trade facilitation can improve receipts and market confidence if logistics capacity keeps up.", fiscalSpaceDelta: 3, growthDelta: 0.10, id: "trade-diplomacy", inflationDelta: -0.02, keywords: ["trade", "customs", "export", "corridor", "diplomacy", "agreement"], summary: "Trade diplomacy: stronger external balance and confidence.", tradeBalanceDelta: 0.16, track: .diplomaticLeverage),
        NativeConsequenceRule(budgetBalanceDelta: 0.02, debtDelta: -0.02, description: "Credible market signaling improves financing conditions but has limited direct real-economy impact.", fiscalSpaceDelta: 2, growthDelta: 0.04, id: "market-confidence", inflationDelta: -0.01, keywords: ["market", "confidence", "transparency", "publish"], summary: "Market confidence: cheaper financing and marginal growth support.", tradeBalanceDelta: 0.03, track: .marketConfidence),
        NativeConsequenceRule(budgetBalanceDelta: -0.12, debtDelta: 0.16, description: "External shocks stress public finances and trade while forcing near-term mitigation.", fiscalSpaceDelta: -4, growthDelta: -0.12, id: "external-shock", inflationDelta: 0.10, keywords: ["shock", "volatility", "disruption", "price"], summary: "External shock: weaker growth and fiscal pressure.", tradeBalanceDelta: -0.10, track: .worldTension),
        NativeConsequenceRule(budgetBalanceDelta: -0.05, debtDelta: 0.06, description: "Default civic programs create modest fiscal cost and modest delivery upside.", fiscalSpaceDelta: 1, growthDelta: 0.03, id: "default-civic", inflationDelta: 0.00, keywords: [], summary: "Civic action: small cost, small institutional gain.", tradeBalanceDelta: 0.00, track: .internalStability),
        NativeConsequenceRule(budgetBalanceDelta: -0.14, debtDelta: 0.18, description: "Public security programs reduce insurgency pressure but require sustained local legitimacy and budget room.", fiscalSpaceDelta: -1, growthDelta: 0.02, id: "public-security", inflationDelta: 0.01, keywords: ["security", "public safety", "public order", "policing", "seguranca", "segurança", "stabilization"], summary: "Public security: lower rebel pressure with budget cost.", tradeBalanceDelta: 0.00, track: .internalStability),
        NativeConsequenceRule(budgetBalanceDelta: -0.18, debtDelta: 0.22, description: "Insurgency containment protects service corridors but drags growth when local control remains contested.", fiscalSpaceDelta: -2, growthDelta: -0.03, id: "insurgency-containment", inflationDelta: 0.03, keywords: ["insurgency", "guerrilla", "rebel", "occupation", "border"], summary: "Insurgency containment: stabilizes control while slowing delivery.", tradeBalanceDelta: -0.02, track: .internalStability),
        NativeConsequenceRule(budgetBalanceDelta: -0.04, debtDelta: 0.08, description: "Macro demand remains fragile and can drift against the player if no credible fiscal path exists.", fiscalSpaceDelta: -1, growthDelta: -0.02, id: "macro-demand", inflationDelta: 0.03, keywords: [], summary: "Macro demand: fragile recovery pressure.", tradeBalanceDelta: -0.02, track: .economicResilience),
        NativeConsequenceRule(budgetBalanceDelta: -0.10, debtDelta: 0.12, description: "Recurring commitments can slowly erode budget space even without a headline shock.", fiscalSpaceDelta: -2, growthDelta: 0.00, id: "fiscal-drift", inflationDelta: 0.01, keywords: [], summary: "Fiscal drift: budget space narrows.", tradeBalanceDelta: 0.00, track: .economicResilience)
    ]

    private static let rulesByID = Dictionary(uniqueKeysWithValues: consequenceRules.map { ($0.id, $0) })

    /// **Hex Lever Decoder Mechanic**:
    /// Parses the optional 8-character hex code generated by the AI model.
    /// Nibbles 1-6 apply direct economic deltas (growth, budget, debt, inflation, trade, fiscal space).
    /// Nibbles 7-8 apply public security penalties and tactical map nudges (invasions, occupations).
    /// This allows the model to nudge deterministic state boundaries without breaking strict typing.
    static func decodeHexLever(_ hex: String) -> NativeHexLever? {
        var clean = hex.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if clean.hasPrefix("0x") {
            clean = String(clean.dropFirst(2))
        }
        guard clean.count == 6 || clean.count == 8 else { return nil }
        let chars = Array(clean)

        func decodeNibble(_ char: Character) -> Int? {
            guard let val = char.hexDigitValue else { return nil }
            return val >= 8 ? val - 16 : val
        }

        guard let g = decodeNibble(chars[0]),
              let b = decodeNibble(chars[1]),
              let d = decodeNibble(chars[2]),
              let i = decodeNibble(chars[3]),
              let t = decodeNibble(chars[4]),
              let f = decodeNibble(chars[5])
        else {
            return nil
        }

        var securityDelta = 0.0
        var rebelDelta = 0.0
        var invasionNudge = 0

        if chars.count == 8 {
            if let s = decodeNibble(chars[6]) {
                securityDelta = Double(s) * 2.5
                rebelDelta = Double(-s) * 1.5
            }
            if let v = decodeNibble(chars[7]) {
                invasionNudge = v
            }
        }

        return NativeHexLever(
            growthDelta: Double(g) * 0.1,
            budgetDelta: Double(b) * 0.05,
            debtDelta: Double(d) * 0.2,
            inflationDelta: Double(i) * 0.05,
            tradeDelta: Double(t) * 0.05,
            fiscalSpaceDelta: f,
            securityDelta: securityDelta,
            rebelDelta: rebelDelta,
            invasionNudge: invasionNudge
        )
    }

    static func conflictNudgeLabel(for value: Int) -> String {
        switch value {
        case 1:
            "conventional border advance"
        case 2:
            "guerrilla control"
        case 3:
            "nuclear fallout"
        case 4:
            "domestic stabilization"
        case 5:
            "contested border"
        case 6:
            "public-security recovery"
        case 7:
            "conquest occupation"
        case -1:
            "de-escalation"
        default:
            "no map nudge"
        }
    }

    private static func securityNudge(for value: Int) -> Double {
        switch value {
        case 1:
            -6
        case 2:
            -14
        case 3:
            -35
        case 4:
            10
        case 5:
            -4
        case 6:
            16
        case 7:
            -10
        case -1:
            8
        default:
            0
        }
    }

    private static func rebelNudge(for value: Int) -> Double {
        switch value {
        case 2:
            22
        case 3:
            12
        case 4, 6, -1:
            -16
        case 5:
            4
        default:
            0
        }
    }

    static func rollStochasticEvent(
        for ledger: NativeEconomicLedger,
        code: String,
        targetDate: String
    ) -> (deltas: NativeHexLever, summary: String)? {
        let seedString = "\(code)-\(targetDate)-\(ledger.publicDebtPercentGDP)-\(ledger.fiscalSpaceIndex)"
        var rng = SimpleRNG(seedString: seedString)

        // 1. Restructuring Check
        if ledger.publicDebtPercentGDP > 150.0 || ledger.fiscalSpaceIndex <= 0 {
            let pRestructure = 0.40
            if rng.nextDouble() < pRestructure {
                let deltas = NativeHexLever(
                    growthDelta: -4.5,
                    budgetDelta: -1.5,
                    debtDelta: -40.0,
                    inflationDelta: 6.0,
                    tradeDelta: -2.0,
                    fiscalSpaceDelta: 25
                )
                return (deltas: deltas, summary: "\(code) Debt Restructuring: Public debt exceeding critical levels triggers emergency restructuring, forcing a sharp contraction but restoring nominal fiscal room.")
            }
        }

        // 2. Sovereign Squeeze Check
        if ledger.publicDebtPercentGDP > 100.0 || ledger.fiscalSpaceIndex < 30 {
            var mult = 1.0
            if ledger.publicDebtPercentGDP > 120.0 {
                mult *= 10.0
            } else if ledger.publicDebtPercentGDP > 100.0 {
                mult *= 5.0
            }

            if ledger.fiscalSpaceIndex < 15 {
                mult *= 6.0
            } else if ledger.fiscalSpaceIndex < 30 {
                mult *= 3.0
            }

            let pSqueeze = min(0.75, 0.03 * mult)
            if rng.nextDouble() < pSqueeze {
                let deltas = NativeHexLever(
                    growthDelta: -0.5,
                    budgetDelta: -0.4,
                    debtDelta: 2.5,
                    inflationDelta: 0.6,
                    tradeDelta: -0.2,
                    fiscalSpaceDelta: -6
                )
                return (deltas: deltas, summary: "\(code) Sovereign Squeeze: Debt servicing costs escalate as yields spike, constraining domestic investment.")
            }
        }

        // 3. Sovereign Upgrade Check
        if ledger.publicDebtPercentGDP < 50.0, ledger.fiscalSpaceIndex > 70 {
            var mult = 1.0
            if ledger.publicDebtPercentGDP < 30.0 {
                mult *= 2.0
            }
            if ledger.fiscalSpaceIndex > 85 {
                mult *= 2.0
            }

            let pUpgrade = min(0.60, 0.05 * mult)
            if rng.nextDouble() < pUpgrade {
                let deltas = NativeHexLever(
                    growthDelta: 0.3,
                    budgetDelta: 0.2,
                    debtDelta: -1.5,
                    inflationDelta: -0.2,
                    tradeDelta: 0.2,
                    fiscalSpaceDelta: 5
                )
                return (deltas: deltas, summary: "\(code) Sovereign Upgrade: Strong fiscal buffers trigger a ratings upgrade, lowering bond yields and financing pressure.")
            }
        }

        // 4. Productivity Breakthrough Check
        var pBreakthrough = 0.04
        if ledger.fiscalSpaceIndex > 70 {
            pBreakthrough *= 1.5
        }
        if ledger.realGrowthPercent > 4.0 {
            pBreakthrough *= 1.5
        }
        if rng.nextDouble() < pBreakthrough {
            let deltas = NativeHexLever(
                growthDelta: 0.6,
                budgetDelta: 0.1,
                debtDelta: -0.5,
                inflationDelta: -0.3,
                tradeDelta: 0.4,
                fiscalSpaceDelta: 3
            )
            return (deltas: deltas, summary: "\(code) Productivity Breakthrough: Industrial automation or tech integration lifts logistics efficiency and potential output.")
        }

        // 5. Productivity Bottleneck Check
        var pBottleneck = 0.04
        if ledger.fiscalSpaceIndex < 30 {
            pBottleneck *= 2.0
        }
        if ledger.realGrowthPercent > 5.0 {
            pBottleneck *= 1.5
        }
        if rng.nextDouble() < pBottleneck {
            let deltas = NativeHexLever(
                growthDelta: -0.4,
                budgetDelta: -0.1,
                debtDelta: 0.5,
                inflationDelta: 0.4,
                tradeDelta: -0.4,
                fiscalSpaceDelta: -3
            )
            return (deltas: deltas, summary: "\(code) Infrastructure Bottleneck: Unresolved capacity constraints in regional corridors cap export volumes.")
        }

        // 6. Consumption Nudge Check
        var pNudge = 0.12
        if ledger.inflationPercent > 6.0 {
            pNudge *= 0.3
        }
        if ledger.unemploymentPercent < 5.0 {
            pNudge *= 1.5
        }
        if rng.nextDouble() < pNudge {
            let deltas = NativeHexLever(
                growthDelta: 0.2,
                budgetDelta: 0.05,
                debtDelta: -0.1,
                inflationDelta: 0.1,
                tradeDelta: 0.1,
                fiscalSpaceDelta: 1
            )
            return (deltas: deltas, summary: "\(code) Consumer Demand Nudge: Private sector demand stabilizes, providing minor growth support.")
        }

        // 7. Cost Drift Check
        var pDrift = 0.12
        if ledger.inflationPercent > 5.0 {
            pDrift *= 2.0
        }
        if ledger.fiscalSpaceIndex < 30 {
            pDrift *= 1.5
        }
        if rng.nextDouble() < pDrift {
            let deltas = NativeHexLever(
                growthDelta: -0.1,
                budgetDelta: -0.05,
                debtDelta: 0.1,
                inflationDelta: 0.2,
                tradeDelta: -0.1,
                fiscalSpaceDelta: -1
            )
            return (deltas: deltas, summary: "\(code) Cost Drift: Rising inputs or regulatory compliance costs create minor price pressures.")
        }

        // 8. Baseline Market Noise
        let noiseGrowth = (rng.nextDouble() * 0.1) - 0.05
        let noiseBudget = (rng.nextDouble() * 0.04) - 0.02
        let noiseDebt = (rng.nextDouble() * 0.2) - 0.1
        let noiseInflation = (rng.nextDouble() * 0.04) - 0.02
        let noiseTrade = (rng.nextDouble() * 0.04) - 0.02

        let fsRoll = rng.nextDouble()
        let noiseFiscalSpace: Int = if fsRoll > 0.85 {
            1
        } else if fsRoll < 0.15 {
            -1
        } else {
            0
        }

        let noiseDeltas = NativeHexLever(
            growthDelta: noiseGrowth,
            budgetDelta: noiseBudget,
            debtDelta: noiseDebt,
            inflationDelta: noiseInflation,
            tradeDelta: noiseTrade,
            fiscalSpaceDelta: noiseFiscalSpace
        )
        return (deltas: noiseDeltas, summary: "\(code) Market noise: Negligible macroeconomic fluctuations.")
    }

    private static func clampDouble(_ value: Double, _ lower: Double, _ upper: Double) -> Double {
        min(upper, max(lower, value))
    }

    // MARK: - Autonomous AI Country State Logic

    static func initialAICountryStates(for scenarioID: String) -> [String: NativeAICountryState] {
        var states: [String: NativeAICountryState] = [:]

        let strategicCodes = defaultStrategicCountryCodes.filter { $0 != "GLOBAL" }

        for code in strategicCodes {
            var doctrine = NativeAIDoctrine.isolationist
            var budgetPriority = NativeAIBudgetPriority.stability
            var multiTurnAgenda = "Focus on domestic administrative and service consolidation."
            var relationships: [String: Int] = [:]

            // Default baseline relationships (most are neutral)
            for otherCode in strategicCodes where otherCode != code {
                relationships[otherCode] = 0
            }

            if scenarioID == "default" || scenarioID == "" {
                // Historically-informed starting states for the 2010 Modern Day scenario
                switch code {
                case "USA":
                    doctrine = .collaborative
                    budgetPriority = .diplomacy
                    multiTurnAgenda = "Strengthen regional alliances and coordinate global trade corridors."
                    relationships["GBR"] = 70
                    relationships["DEU"] = 60
                    relationships["FRA"] = 60
                    relationships["JPN"] = 65
                    relationships["AUS"] = 60
                    relationships["BRA"] = 20
                    relationships["CHN"] = -25
                    relationships["RUS"] = -30
                case "CHN":
                    doctrine = .mercantile
                    budgetPriority = .growth
                    multiTurnAgenda = "Expand export corridors and secure industrial resources."
                    relationships["RUS"] = 40
                    relationships["USA"] = -25
                    relationships["JPN"] = -30
                case "RUS":
                    doctrine = .defensive
                    budgetPriority = .military
                    multiTurnAgenda = "Reinforce security boundaries and modernize logistics capabilities."
                    relationships["CHN"] = 40
                    relationships["USA"] = -30
                    relationships["GBR"] = -25
                    relationships["DEU"] = -15
                    relationships["FRA"] = -15
                case "DEU":
                    doctrine = .mercantile
                    budgetPriority = .growth
                    multiTurnAgenda = "Optimize industrial export grids and maintain fiscal stability."
                    relationships["USA"] = 60
                    relationships["FRA"] = 70
                    relationships["GBR"] = 50
                    relationships["RUS"] = -15
                case "FRA":
                    doctrine = .collaborative
                    budgetPriority = .diplomacy
                    multiTurnAgenda = "Lead European integration and support multilateral agreements."
                    relationships["USA"] = 60
                    relationships["DEU"] = 70
                    relationships["GBR"] = 55
                    relationships["RUS"] = -15
                case "GBR":
                    doctrine = .defensive
                    budgetPriority = .stability
                    multiTurnAgenda = "Recover trade corridors and manage post-recession administrative costs."
                    relationships["USA"] = 70
                    relationships["DEU"] = 50
                    relationships["FRA"] = 55
                    relationships["RUS"] = -25
                case "JPN":
                    doctrine = .defensive
                    budgetPriority = .stability
                    multiTurnAgenda = "Mitigate industrial deflation and reinforce Pacific maritime corridors."
                    relationships["USA"] = 65
                    relationships["CHN"] = -30
                    relationships["KOR"] = -10
                case "BRA":
                    doctrine = .collaborative
                    budgetPriority = .growth
                    multiTurnAgenda = "Develop commodity trade routes and South American infrastructure corridors."
                    relationships["USA"] = 20
                case "AUS":
                    doctrine = .collaborative
                    budgetPriority = .diplomacy
                    multiTurnAgenda = "Secure Asia-Pacific trade agreements and resource partnerships."
                    relationships["USA"] = 60
                    relationships["CHN"] = -15
                default:
                    break
                }
            } else if scenarioID == "soviet-triumph" {
                // Alternate History: Bipolar Cold War containment
                switch code {
                case "USA":
                    doctrine = .defensive
                    budgetPriority = .military
                    multiTurnAgenda = "Contain collectivized command networks and secure trade routes."
                    relationships["RUS"] = -80
                    relationships["CHN"] = -40
                case "RUS": // Stand-in for USSR
                    doctrine = .expansionist
                    budgetPriority = .military
                    multiTurnAgenda = "Integrate command industrial grids and support socialist alignment."
                    relationships["USA"] = -80
                    relationships["CHN"] = 50
                case "CHN":
                    doctrine = .expansionist
                    budgetPriority = .growth
                    multiTurnAgenda = "Expand command economy and strengthen alliance networks."
                    relationships["RUS"] = 50
                    relationships["USA"] = -40
                default:
                    break
                }
            } else if scenarioID == "fragmented-markets" {
                // Blocs, trade friction
                switch code {
                case "USA":
                    doctrine = .defensive
                    budgetPriority = .diplomacy
                    multiTurnAgenda = "Defend core sovereign trade networks from regional fragmentation."
                    relationships["CHN"] = -50
                case "CHN":
                    doctrine = .mercantile
                    budgetPriority = .growth
                    multiTurnAgenda = "Leverage trade access and secure local resource corridors."
                    relationships["USA"] = -50
                default:
                    relationships["USA"] = -10
                    relationships["CHN"] = -10
                }
            }

            states[code] = NativeAICountryState(
                countryCode: code,
                doctrine: doctrine,
                budgetPriority: budgetPriority,
                relationshipScores: relationships,
                multiTurnAgenda: multiTurnAgenda,
                agendaProgress: 0
            )
        }

        return states
    }

    /// **AI Drift & Diplomacy Mechanic**:
    /// Simulates non-player actors based on their budget priority and relationships.
    /// Over time:
    /// 1. Player budget sliders dynamically alter macro economics and security.
    /// 2. Active treaties slowly build up relationship drift and grant passive economic buffs.
    /// 3. High global tension or low relationship scores push AI into arms races and conflict.
    /// 4. Autonomous completion of AI agendas causes stability/economic effects to the player.
    static func simulateAIDrift(state: inout NativeCampaignState, months: Int) {
        let strategicCodes = defaultStrategicCountryCodes.filter { $0 != "GLOBAL" }

        // 1. Apply player budget allocation slider effects
        if var pLedger = state.economicLedgers[state.country.code] {
            let mil = state.budgetMilitarySlider
            let ser = state.budgetServicesSlider
            let dip = state.budgetDiplomacySlider

            var milGrowthDelta = 0.0
            var milDebtDelta = 0.0
            var milSecurityDelta = 0.0
            var milRebelDelta = 0.0

            var serStabilityDelta = 0
            var serUnemploymentDelta = 0.0
            var serGrowthDelta = 0.0
            var serBudgetDelta = 0.0

            var dipTradeDelta = 0.0

            if mil > 0.40 {
                milSecurityDelta = 1.5 * Double(months)
                milRebelDelta = -1.0 * Double(months)
                milDebtDelta = 0.5 * Double(months)
                milGrowthDelta = -0.2 * Double(months)

                let recruitmentFactor = (mil - 0.40) * 10.0 * Double(months)
                state.militaryUnits["infantry", default: 0] += Int(recruitmentFactor * 1.5)
                state.militaryUnits["armor", default: 0] += Int(recruitmentFactor * 0.8)
                state.militaryUnits["air", default: 0] += Int(recruitmentFactor * 0.4)
                state.militaryUnits["naval", default: 0] += Int(recruitmentFactor * 0.2)
            } else if mil < 0.20 {
                milSecurityDelta = -2.0 * Double(months)
                milRebelDelta = 1.5 * Double(months)

                let attritionFactor = (0.20 - mil) * 5.0 * Double(months)
                state.militaryUnits["infantry", default: 0] = max(5, state.militaryUnits["infantry", default: 0] - Int(attritionFactor * 1.5))
                state.militaryUnits["armor", default: 0] = max(2, state.militaryUnits["armor", default: 0] - Int(attritionFactor * 0.8))
                state.militaryUnits["air", default: 0] = max(1, state.militaryUnits["air", default: 0] - Int(attritionFactor * 0.4))
                state.militaryUnits["naval", default: 0] = max(0, state.militaryUnits["naval", default: 0] - Int(attritionFactor * 0.2))
            }

            if ser > 0.40 {
                serStabilityDelta = 1 * months
                serUnemploymentDelta = -0.2 * Double(months)
                serGrowthDelta = 0.2 * Double(months)
                serBudgetDelta = -0.4 * Double(months)
            } else if ser < 0.20 {
                serStabilityDelta = -2 * months
                serUnemploymentDelta = 0.3 * Double(months)
            }

            if dip > 0.40 {
                dipTradeDelta = 0.3 * Double(months)
            }

            let resBudgetDelta = state.budgetResearchSlider > 0.25
                ? -(state.budgetResearchSlider - 0.25) * 0.4 * Double(months)
                : 0.0

            let playerHomeRegionID = GeopoliticalMapData.regions(forCountryCode: state.country.code).first { $0.countryCode != "WATER" }?.id ?? state.country.code
            state.mapArmies = NativeArmySnapshot.synchronizingArmies(
                state.mapArmies,
                with: state.militaryUnits,
                countryCode: state.country.code,
                homeRegionID: playerHomeRegionID
            )

            pLedger.securityIndex = clampDouble(pLedger.securityIndex + milSecurityDelta, 0, 100)
            pLedger.rebelControlPercent = clampDouble(pLedger.rebelControlPercent + milRebelDelta, 0, 100)
            pLedger.publicDebtPercentGDP = clampDouble(pLedger.publicDebtPercentGDP + milDebtDelta, 1, 260)

            // **Tech Tree (#7)**: the active research era grants a per-turn
            // real-growth bonus (digital +0.5%, aiAge +1%, biotech +1.5%,
            // cleanEnergy +2%, scaled by elapsed months).
            let era = state.techEraTyped
            let techGrowthDelta = era.growthBonus * Double(months)

            // **Military Units (#8)**: standing-army maintenance. Each unit
            // costs 0.01% growth per turn, annualized by elapsed months so it
            // composes consistently with the GDP compounding line in `apply`.
            let totalUnits = state.militaryUnits.values.reduce(0, +)
            let maintenanceGrowthDelta = -Double(totalUnits) * 0.01 * Double(months)

            pLedger.realGrowthPercent = clampDouble(pLedger.realGrowthPercent + milGrowthDelta + serGrowthDelta + techGrowthDelta + maintenanceGrowthDelta, -12, 16)

            pLedger.unemploymentPercent = clampDouble(pLedger.unemploymentPercent + serUnemploymentDelta, 1, 35)
            pLedger.budgetBalancePercentGDP = clampDouble(pLedger.budgetBalancePercentGDP + serBudgetDelta + resBudgetDelta, -12, 12)
            pLedger.tradeBalancePercentGDP = clampDouble(pLedger.tradeBalancePercentGDP + dipTradeDelta, -20, 20)

            if milGrowthDelta != 0 || serGrowthDelta != 0 || serBudgetDelta != 0 || resBudgetDelta != 0 || dipTradeDelta != 0 || techGrowthDelta != 0 || maintenanceGrowthDelta != 0 {
                let sliderEntry = NativeEconomicLedgerEntry(
                    budgetBalanceDelta: serBudgetDelta + resBudgetDelta,
                    debtDelta: milDebtDelta,
                    eventID: "budget-slider-\(state.round)",
                    fiscalSpaceDelta: 0,
                    growthDelta: milGrowthDelta + serGrowthDelta + techGrowthDelta + maintenanceGrowthDelta,
                    id: "ledger-entry-slider-\(state.country.code.lowercased())-\(state.gameDate)",
                    inflationDelta: 0.0,
                    ruleID: "budget-allocation",
                    summary: "Adjustments from budget sliders, \(era.displayName) research bonus, and military upkeep",
                    tradeBalanceDelta: dipTradeDelta,
                    turnDate: state.gameDate,
                    securityDelta: milSecurityDelta,
                    rebelDelta: milRebelDelta
                )
                pLedger.entries.insert(sliderEntry, at: 0)
            }

            state.economicLedgers[state.country.code] = pLedger

            // **Tech Tree (#7)**: accumulate research points from the research
            // budget slider and advance the era when the threshold is met.
            let researchYearFraction = Double(months) / 12.0
            let researchGain = Int((state.budgetResearchSlider * 100.0 * researchYearFraction).rounded())
            if researchGain > 0 {
                state.researchPoints += researchGain
            }
            if let nextEra = era.next, state.researchPoints >= era.researchThreshold {
                state.researchPoints = 0
                state.techEraTyped = nextEra
                let eraEvent = NativeCampaignEvent(
                    date: state.gameDate,
                    description: "Our research programs crossed the \(era.researchThreshold)-point threshold, ushering the nation into the \(nextEra.displayName) era. Real-growth outlook improves by \(String(format: "%+.1f", nextEra.growthBonus))%/turn.",
                    id: "tech-era-advance-\(nextEra.rawValue)-\(state.gameDate)",
                    importance: .major,
                    kind: .economy,
                    linkedActionIDs: [],
                    notable: true,
                    playerRelated: true,
                    strategicEffects: [
                        NativeStrategicEffect(
                            date: state.gameDate,
                            eventId: "tech-era-advance-\(nextEra.rawValue)-\(state.gameDate)",
                            id: "tech-era-effect-\(nextEra.rawValue)-\(state.gameDate)",
                            magnitude: 1,
                            summary: "\(nextEra.displayName) era unlocked: +\(String(format: "%.1f", nextEra.growthBonus))%/turn growth.",
                            target: state.country.code,
                            track: .economicResilience
                        )
                    ],
                    title: "TECH ADVANCE: \(nextEra.displayName) Era"
                )
                state.timeline.insert(eraEvent, at: 0)
            }

            if serStabilityDelta != 0 {
                state.stability = max(0, min(100, state.stability + serStabilityDelta))
            }
        }

        // 1.5. Process accepted treaties (relationship drift & ongoing effects)
        // Only player-facing treaties (targetCode == nil) get the ongoing
        // player+partner ledger buffs here. Autonomous AI-to-AI treaties get
        // their one-shot ledger effect in simulateRivalGeopolitics and must NOT
        // be double-counted as if they were player treaties.
        let acceptedOffers = state.activeOffers.filter { $0.status == .accepted && $0.isPlayerFacing }
        let acceptedTreatyPartnerCodes = Set(acceptedOffers.map(\.proposerCode))
        for offer in acceptedOffers {
            let partnerCode = offer.proposerCode

            // Partner relationship boost towards player
            if var partnerState = state.aiCountryStates[partnerCode] {
                let currentRel = partnerState.relationshipScores[state.country.code] ?? 0
                let boost = (offer.type == .militaryAlliance ? 2.0 : 1.0) * Double(months)
                partnerState.relationshipScores[state.country.code] = max(-100, min(100, currentRel + Int(boost.rounded())))
                state.aiCountryStates[partnerCode] = partnerState
            }

            // Ongoing ledger adjustments for player and partner
            let countriesToModify = [state.country.code, partnerCode]
            for cCode in countriesToModify {
                if var ledger = state.economicLedgers[cCode] {
                    var growthDelta = 0.0
                    var secDelta = 0.0
                    var tradeDelta = 0.0

                    if offer.type == .militaryAlliance {
                        growthDelta = -0.05 * Double(months)
                        secDelta = 0.5 * Double(months)
                    } else if offer.type == .tradeAgreement {
                        growthDelta = 0.1 * Double(months)
                        tradeDelta = 0.2 * Double(months)
                    } else if offer.type == .nonAggressionPact {
                        secDelta = 0.2 * Double(months)
                    }

                    ledger.realGrowthPercent = clampDouble(ledger.realGrowthPercent + growthDelta, -12.0, 16.0)
                    ledger.securityIndex = clampDouble(ledger.securityIndex + secDelta, 0.0, 100.0)
                    ledger.tradeBalancePercentGDP = clampDouble(ledger.tradeBalancePercentGDP + tradeDelta, -20.0, 20.0)
                    state.economicLedgers[cCode] = ledger
                }
            }

            // Alliance Bloc Politics: proposer's rivals decay relations with player, and player's rivals decay with proposer
            if offer.type == .militaryAlliance {
                if let partnerState = state.aiCountryStates[partnerCode] {
                    for (otherCode, score) in partnerState.relationshipScores {
                        if score < -30, var rivalState = state.aiCountryStates[otherCode] {
                            let curRel = rivalState.relationshipScores[state.country.code] ?? 0
                            rivalState.relationshipScores[state.country.code] = max(-100, curRel - Int(1.0 * Double(months)))
                            state.aiCountryStates[otherCode] = rivalState
                        }
                    }
                }

                for code in strategicCodes {
                    if code == state.country.code {
                        continue
                    }
                    if let aiState = state.aiCountryStates[code], let playerRel = aiState.relationshipScores[state.country.code], playerRel < -30, var aiStateMut = state.aiCountryStates[code] {
                        let curRel = aiStateMut.relationshipScores[partnerCode] ?? 0
                        aiStateMut.relationshipScores[partnerCode] = max(-100, curRel - Int(1.0 * Double(months)))
                        state.aiCountryStates[code] = aiStateMut
                    }
                }
            }
        }

        // 2. Simulate AI countries
        for code in strategicCodes {
            if code == state.country.code {
                continue
            }
            guard var aiState = state.aiCountryStates[code] else { continue }

            // React to high world tension (>60)
            if state.worldTension > 60 && aiState.budgetPriority != .military {
                var tensionRng = SimpleRNG(seedString: "tension-shift-\(state.scenarioID)-\(state.round)-\(code)")
                let shiftChance = state.budgetMilitarySlider > 0.40 ? 0.40 : 0.20
                if tensionRng.nextDouble() < shiftChance {
                    aiState.doctrine = tensionRng.nextDouble() < 0.5 ? .defensive : .expansionist
                    aiState.budgetPriority = .military
                    aiState.multiTurnAgenda = "High global friction triggers defense consolidation and emergency military preparedness."
                    aiState.agendaProgress = 0
                }
            }

            // React to player tech era advancement (anxiety/doctrine shift)
            let playerEra = state.techEraTyped
            let techRelations = aiState.relationshipScores[state.country.code] ?? 0
            if (playerEra == .aiAge || playerEra == .cleanEnergy) && techRelations < 0 && aiState.doctrine != .defensive && aiState.doctrine != .expansionist {
                var rng = SimpleRNG(seedString: "tech-shift-\(state.scenarioID)-\(state.round)-\(code)")
                if rng.nextDouble() < 0.35 {
                    aiState.doctrine = .defensive
                    aiState.multiTurnAgenda = "Anxious about competitor technological leaps, consolidating defensive security postures."
                    aiState.agendaProgress = 0
                }
            }

            // Advance agenda progress
            aiState.agendaProgress = min(100, aiState.agendaProgress + (months * 4))
            if aiState.agendaProgress >= 100 {
                aiState.agendaProgress = 0
                let oldAgenda = aiState.multiTurnAgenda
                switch aiState.doctrine {
                case .mercantile:
                    aiState.multiTurnAgenda = "Pursuing export route optimization and trade corridor integration."
                case .expansionist:
                    aiState.multiTurnAgenda = "Securing contested borders and projecting regional stabilization corridors."
                case .isolationist:
                    aiState.multiTurnAgenda = "Strengthening domestic service capacity and fiscal space."
                case .defensive:
                    aiState.multiTurnAgenda = "Consolidating security index levels and regional logistics preparedness."
                case .collaborative:
                    aiState.multiTurnAgenda = "Engaging neighbors in collaborative trade and security accords."
                }

                // AI agenda completion consequences on player
                let relations = aiState.relationshipScores[state.country.code] ?? 0
                var consequenceDetail = ""
                var stabilityDelta = 0
                var growthDelta = 0.0
                var tradeDelta = 0.0
                var rebelDelta = 0.0
                var securityDelta = 0.0

                if relations < -30 {
                    switch aiState.doctrine {
                    case .mercantile:
                        tradeDelta = -1.5
                        growthDelta = -0.5
                        consequenceDetail = "decreased our trade balance by 1.5% and slowed growth by 0.5%."
                    case .expansionist:
                        rebelDelta = 3.0
                        stabilityDelta = -5
                        consequenceDetail = "fueled regional instability, increasing rebel presence by 3.0% and reducing stability by 5."
                    case .isolationist:
                        growthDelta = -0.4
                        consequenceDetail = "withdrew from bilateral talks, shaving 0.4% off our growth."
                    case .defensive:
                        stabilityDelta = -3
                        securityDelta = -2.0
                        consequenceDetail = "completed regional militarization, lowering our stability by 3 and security index by 2.0."
                    case .collaborative:
                        stabilityDelta = -2
                        consequenceDetail = "excluded us from regional agreements, reducing stability by 2."
                    }
                } else if relations > 30 {
                    switch aiState.doctrine {
                    case .mercantile:
                        tradeDelta = 1.2
                        growthDelta = 0.3
                        consequenceDetail = "boosted our trade relations, increasing trade balance by 1.2% and growth by 0.3%."
                    case .expansionist:
                        rebelDelta = -2.0
                        securityDelta = 2.0
                        consequenceDetail = "helped suppress regional border insurgencies, reducing rebel control by 2.0% and improving security."
                    case .isolationist:
                        growthDelta = 0.2
                        consequenceDetail = "stabilized regional supply lines, boosting our growth by 0.2%."
                    case .defensive:
                        securityDelta = 4.0
                        consequenceDetail = "shared strategic defense intelligence, raising our security index by 4.0."
                    case .collaborative:
                        stabilityDelta = 4
                        growthDelta = 0.2
                        consequenceDetail = "signed a bilateral security and trade pact, increasing stability by 4 and growth by 0.2%."
                    }
                } else {
                    consequenceDetail = "with no direct impact on our nation due to neutral relations."
                }

                if relations < -30 || relations > 30 {
                    if var pLedger = state.economicLedgers[state.country.code] {
                        pLedger.realGrowthPercent = clampDouble(pLedger.realGrowthPercent + growthDelta, -12, 16)
                        pLedger.tradeBalancePercentGDP = clampDouble(pLedger.tradeBalancePercentGDP + tradeDelta, -20, 20)
                        pLedger.rebelControlPercent = clampDouble(pLedger.rebelControlPercent + rebelDelta, 0, 100)
                        pLedger.securityIndex = clampDouble(pLedger.securityIndex + securityDelta, 0, 100)

                        let agendaEntry = NativeEconomicLedgerEntry(
                            budgetBalanceDelta: 0.0,
                            debtDelta: 0.0,
                            eventID: "agenda-\(code.lowercased())-\(state.round)",
                            fiscalSpaceDelta: 0,
                            growthDelta: growthDelta,
                            id: "ledger-entry-agenda-\(code.lowercased())-\(state.gameDate)",
                            inflationDelta: 0.0,
                            ruleID: "agenda-completion",
                            summary: "\(code) completed agenda: \(oldAgenda)",
                            tradeBalanceDelta: tradeDelta,
                            turnDate: state.gameDate,
                            securityDelta: securityDelta,
                            rebelDelta: rebelDelta
                        )
                        pLedger.entries.insert(agendaEntry, at: 0)
                        state.economicLedgers[state.country.code] = pLedger
                    }
                    if stabilityDelta != 0 {
                        state.stability = max(0, min(100, state.stability + stabilityDelta))
                    }
                }

                let agendaEvent = NativeCampaignEvent(
                    date: state.gameDate,
                    description: "\(code) has completed their multi-turn agenda: \"\(oldAgenda)\". Geopolitical alignment analysis: \(consequenceDetail)",
                    id: "agenda-event-\(code.lowercased())-\(state.gameDate)",
                    importance: .major,
                    kind: .world,
                    linkedActionIDs: [],
                    notable: true,
                    playerRelated: relations > 30 || relations < -30,
                    strategicEffects: stabilityDelta != 0 ? [
                        NativeStrategicEffect(
                            date: state.gameDate,
                            eventId: "agenda-event-\(code.lowercased())",
                            id: "agenda-effect-\(code.lowercased())-\(state.gameDate)",
                            magnitude: stabilityDelta,
                            summary: "Stability altered by \(code)'s completed agenda",
                            target: state.country.code,
                            track: .internalStability
                        )
                    ] : [],
                    title: "\(code) completes agenda: \(oldAgenda.prefix(32))..."
                )
                state.timeline.insert(agendaEvent, at: 0)

                // Rival victory must be earned during this campaign. A country
                // receives one bounded step only when it completes a real
                // multi-turn agenda while all active-scenario objectives are
                // currently satisfied; strong opening ledgers earn nothing.
                if aiVictoryReadiness(forCode: code, in: state) >= 100 {
                    aiState.rivalCampaignProgress = min(
                        100,
                        aiState.rivalCampaignProgress + rivalAgendaVictoryAward
                    )
                }
            }

            // Relationship drift & dynamic slider effects
            let dipSlider = state.budgetDiplomacySlider
            let milSlider = state.budgetMilitarySlider

            // Base drift (if dipSlider is low, decay is faster)
            let baseDrift = dipSlider < 0.20 ? months * 2 : months
            var updatedRelations = aiState.relationshipScores

            for (otherCode, score) in updatedRelations {
                var nextScore = Double(score)

                let tensionPolarization = state.worldTension > 80 ? 1.0 * Double(months) : 0.0

                // 1. Apply natural drift towards neutral (0)
                if score > 0 {
                    let decay = (dipSlider > 0.40 ? 0.0 : Double(baseDrift)) + tensionPolarization
                    nextScore = max(0, nextScore - decay)
                } else if score < 0 {
                    let recovery = (dipSlider > 0.40 ? Double(months * 2) : Double(baseDrift)) + tensionPolarization
                    nextScore = min(0, nextScore + recovery)
                }

                // 2. Apply active diplomacy outreach to player relations.
                // Accepted treaty partners already receive explicit treaty upkeep
                // above, so do not double-count the same budget signal here.
                if otherCode == state.country.code, dipSlider > 0.40, !acceptedTreatyPartnerCodes.contains(code) {
                    nextScore = min(100.0, nextScore + (1.0 * Double(months)))
                }

                // 3. Apply military arms buildup anxiety to player relations
                if otherCode == state.country.code, milSlider > 0.40 {
                    let isRival = score < -30
                    let penalty = isRival ? (-1.0 * Double(months)) : (-0.5 * Double(months))
                    nextScore = max(-100.0, nextScore + penalty)
                }

                updatedRelations[otherCode] = Int(nextScore.rounded())
            }
            aiState.relationshipScores = updatedRelations

            // Diplomatic offer generation
            let hasPending = state.activeOffers.contains(where: { $0.proposerCode == code && $0.status == .pending })
            let relations = aiState.relationshipScores[state.country.code] ?? 0
            if !hasPending, relations >= -20 {
                var rng = SimpleRNG(seedString: "\(state.scenarioID)-\(state.round)-\(code)")
                if rng.nextDouble() < 0.15 {
                    let type: NativeOfferType
                    let desc: String
                    let stabilityCost = 0
                    var relEffect = 10
                    var growthDelta = 0.0

                    if relations > 40 {
                        if rng.nextDouble() < 0.5 {
                            type = .militaryAlliance
                            desc = "\(code) proposes a strategic Military Alliance. Applies +5 security index, but incurs -0.2% growth maintenance."
                            relEffect = 40
                            growthDelta = -0.2
                        } else {
                            type = .tradeAgreement
                            desc = "\(code) proposes a bilateral Trade Agreement. Increases trade balance by +1.2% and GDP growth by +0.4%."
                            relEffect = 20
                            growthDelta = 0.4
                        }
                    } else if rng.nextDouble() < 0.5 {
                        type = .nonAggressionPact
                        desc = "\(code) proposes a Non-Aggression Pact. Boosts public security by +1.0 and stabilizes relations."
                        relEffect = 15
                        growthDelta = 0.0
                    } else {
                        type = .tradeAgreement
                        desc = "\(code) proposes a standard Trade Agreement. Increases trade balance by +0.8%."
                        relEffect = 10
                        growthDelta = 0.2
                    }

                    let newOffer = NativeDiplomaticOffer(
                        id: "offer-\(code.lowercased())-\(state.gameDate)",
                        proposerCode: code,
                        type: type,
                        description: desc,
                        stabilityCost: stabilityCost,
                        relationshipEffect: relEffect,
                        growthDelta: growthDelta,
                        status: .pending,
                        turnProposed: state.round
                    )
                    state.activeOffers.append(newOffer)
                }
            }

            state.aiCountryStates[code] = aiState

            // Deterministic AI ledger metrics drift
            guard var ledger = state.economicLedgers[code] else { continue }
            switch aiState.budgetPriority {
            case .growth:
                ledger.realGrowthPercent = clampDouble(ledger.realGrowthPercent + 0.15 * Double(months), -12, 16)
                ledger.publicDebtPercentGDP = clampDouble(ledger.publicDebtPercentGDP + 0.8 * Double(months), 1, 260)
                ledger.fiscalSpaceIndex = max(0, ledger.fiscalSpaceIndex - months)
            case .stability:
                ledger.securityIndex = clampDouble(ledger.securityIndex + 1.2 * Double(months), 0, 100)
                ledger.rebelControlPercent = clampDouble(ledger.rebelControlPercent - 1.5 * Double(months), 0, 100)
                ledger.budgetBalancePercentGDP = clampDouble(ledger.budgetBalancePercentGDP - 0.2 * Double(months), -12, 12)
            case .military:
                ledger.securityIndex = clampDouble(ledger.securityIndex + 2.0 * Double(months), 0, 100)
                ledger.realGrowthPercent = clampDouble(ledger.realGrowthPercent - 0.1 * Double(months), -12, 16)
                ledger.publicDebtPercentGDP = clampDouble(ledger.publicDebtPercentGDP + 1.0 * Double(months), 1, 260)
            case .diplomacy:
                ledger.fiscalSpaceIndex = min(100, ledger.fiscalSpaceIndex + months)
                ledger.tradeBalancePercentGDP = clampDouble(ledger.tradeBalancePercentGDP + 0.1 * Double(months), -20, 20)
            }
            state.economicLedgers[code] = ledger
        }

        let yearFraction = max(1.0, Double(months)) / 12.0
        // Macroeconomic and security coupling for all countries
        for code in strategicCodes {
            guard var ledger = state.economicLedgers[code] else { continue }

            // 1. Deficit-to-Debt coupling
            let deficit = -ledger.budgetBalancePercentGDP
            ledger.publicDebtPercentGDP = clampDouble(ledger.publicDebtPercentGDP + deficit * yearFraction, 1.0, 260.0)

            // 2. Debt-and-Inflation-to-Fiscal-Space coupling
            let calculatedFiscalSpace = max(0, min(100, 100 - Int(ledger.publicDebtPercentGDP * 0.4) - Int(ledger.inflationPercent * 1.0)))
            ledger.fiscalSpaceIndex = calculatedFiscalSpace

            // 3. Rebel-to-Security coupling
            if ledger.rebelControlPercent > 10.0 {
                let secDecay = -(ledger.rebelControlPercent * 0.1) * Double(months)
                ledger.securityIndex = clampDouble(ledger.securityIndex + secDecay, 0.0, 100.0)
            }

            // 4. Stability-to-Growth feedback (player only)
            if code == state.country.code {
                let playerStability = Double(state.stability)
                if playerStability > 80.0 {
                    let boost = (playerStability - 80.0) * 0.02
                    ledger.realGrowthPercent = clampDouble(ledger.realGrowthPercent + boost, -12.0, 16.0)
                } else if playerStability < 50.0 {
                    let penalty = -(50.0 - playerStability) * 0.03
                    ledger.realGrowthPercent = clampDouble(ledger.realGrowthPercent + penalty, -12.0, 16.0)
                }
            }

            state.economicLedgers[code] = ledger
        }

        // MARK: - P1-1: Adversarial AI Behavior & Victory Pursuit (#9)

        // AI invasions: military/expansionist AI countries with hostile relationships may attack rivals.
        // **AI Pursues Victory (#9)**: expansionist AI near a conquest victory
        // (>= 2 occupied rival regions) are far more aggressive and actually
        // occupy conquered territory rather than merely contesting borders.
        for code in strategicCodes {
            guard let aiState = state.aiCountryStates[code], aiState.doctrine == .expansionist || aiState.doctrine == .defensive, aiState.budgetPriority == .military else { continue }

            // Count rival regions this AI currently controls (victory signal).
            let occupiedRivals = state.regionOccupations.filter { key, val in
                guard val == code else { return false }
                let reg = GeopoliticalMapData.regionByID[key]
                return reg?.countryCode != code && reg?.countryCode != nil
            }.count
            let nearConquestVictory = occupiedRivals >= 2
            // Boost invasion aggressiveness when close to a territorial victory.
            let invasionChance = nearConquestVictory ? 35 : 15

            // Find a rival with relationship < -50
            for (targetCode, score) in aiState.relationshipScores {
                guard score < -50, strategicCodes.contains(targetCode) || targetCode == state.country.code else { continue }

                // Deterministic chance per turn to launch an invasion
                let invasionSeed = "\(state.scenarioID)-\(state.gameDate)-\(code)-invade-\(targetCode)"
                let invasionRoll = NativeGameEngine.stablePercentagePublic(seed: invasionSeed)
                guard invasionRoll < Double(invasionChance) else { continue }

                // Find a border region of the target to contest
                let targetRegions = GeopoliticalMapData.regions(forCountryCode: targetCode)
                guard let targetRegion = targetRegions.first else { continue }

                // Near-victory AI occupies; otherwise it contests the border.
                if nearConquestVictory {
                    state.regionOccupations[targetRegion.id] = code
                }
                state.regionConflicts[targetRegion.id] = NativeRegionConflictState(
                    controllerCode: code,
                    intensity: nearConquestVictory ? 4 : 3,
                    mode: nearConquestVictory ? .conventionalOccupation : .contestedBorder,
                    originalCountryCode: targetCode,
                    regionID: targetRegion.id,
                    sourceEventID: "ai-invasion-\(code)-\(targetCode)-\(state.gameDate)",
                    summary: "\(code) launched a military incursion against \(targetCode)\(nearConquestVictory ? " in a push for regional dominance." : ".")",
                    updatedAt: state.gameDate
                )

                // Relationship penalty for the invasion
                state.aiCountryStates[code]?.relationshipScores[targetCode] = max(-100, score - 5)

                // Create an event
                let invasionEvent = NativeCampaignEvent(
                    date: state.gameDate,
                    description: "\(code) launched a military incursion against \(targetCode) in the \(targetRegion.name) region. Border conflict escalating.",
                    id: "ai-invasion-\(code)-\(targetCode)-\(state.gameDate)",
                    importance: .major,
                    kind: .crisis,
                    linkedActionIDs: [],
                    notable: true,
                    playerRelated: targetCode == state.country.code,
                    strategicEffects: [],
                    title: "\(code) Invades \(targetCode)"
                )
                state.timeline.insert(invasionEvent, at: 0)
                break // One invasion per AI per turn
            }
        }

        // **AI Pursues Victory (#9) — Mercantile doctrine**: prioritize trade
        // offers and relationship building with the strongest economic partners.
        for code in strategicCodes {
            guard var aiState = state.aiCountryStates[code], aiState.doctrine == .mercantile || aiState.budgetPriority == .growth else { continue }

            // Identify this AI's top economic partners (largest GDP ledgers).
            let partnerCodes = strategicCodes.filter { $0 != code }
                .sorted { lhs, rhs in
                    let l = state.economicLedgers[lhs]?.nominalGDPTrillions ?? 0
                    let r = state.economicLedgers[rhs]?.nominalGDPTrillions ?? 0
                    return l > r
                }
                .prefix(3)

            for partnerCode in partnerCodes {
                let current = aiState.relationshipScores[partnerCode] ?? 0
                // Mercantile AI gradually warms to economic partners.
                aiState.relationshipScores[partnerCode] = max(-100, min(100, current + Int(1.0 * Double(months))))
            }

            // Mercantile AI proposes trade agreements more readily with partners.
            let hasPending = state.activeOffers.contains { $0.proposerCode == code && $0.status == .pending }
            if !hasPending {
                for partnerCode in partnerCodes {
                    guard partnerCode != state.country.code else { continue }
                    let tradeSeed = "\(state.scenarioID)-\(state.gameDate)-\(code)-trade-\(partnerCode)"
                    let tradeRoll = NativeGameEngine.stablePercentagePublic(seed: tradeSeed)
                    guard tradeRoll < 25 else { continue }
                    let tradeOffer = NativeDiplomaticOffer(
                        id: "ai-trade-\(code.lowercased())-\(partnerCode.lowercased())-\(state.gameDate)",
                        proposerCode: code,
                        type: .tradeAgreement,
                        description: "\(code) extended a trade corridor proposal to \(partnerCode) to deepen commercial ties.",
                        stabilityCost: 0,
                        relationshipEffect: 10,
                        growthDelta: 0.2,
                        status: .accepted,
                        turnProposed: state.round
                    )
                    state.activeOffers.append(tradeOffer)
                    break
                }
            }
            state.aiCountryStates[code] = aiState
        }

        // Warn once after a rival earns two of the three agenda milestones.
        // A completed rival gets the terminal event instead of a contradictory
        // same-turn "near victory" alert.
        let rivalThreatPrefix = "rival-threat-"
        let hasRivalThreatWarning = state.timeline.contains { $0.id.hasPrefix(rivalThreatPrefix) }
        let warningCandidate: (code: String, progress: Double)? = if !hasRivalThreatWarning {
            strategicCodes.compactMap { code -> (code: String, progress: Double)? in
                guard GeopoliticalMapData.canonicalCountryCode(code) !=
                    GeopoliticalMapData.canonicalCountryCode(state.country.code)
                else { return nil }
                let progress = aiVictoryProgress(forCode: code, in: state)
                guard progress >= rivalAgendaVictoryAward * 2, progress < 100 else { return nil }
                return (code, progress)
            }
            .max { lhs, rhs in
                lhs.progress == rhs.progress ? lhs.code > rhs.code : lhs.progress < rhs.progress
            }
        } else {
            nil
        }

        if let warningCandidate {
            let code = warningCandidate.code
            let progress = warningCandidate.progress
            let threatID = "rival-threat-\(code.lowercased())-\(state.gameDate)"
            let rivalName = CountryNameResolver.name(forCode: code, in: state)
            let threatEvent = NativeCampaignEvent(
                date: state.gameDate,
                description: "Intelligence analysts report \(rivalName) has earned two of the three strategic-agenda milestones required for scenario victory (≈\(Int(progress))% of the rival campaign meter). Its current trajectory could trigger a rival win unless countered.",
                id: threatID,
                importance: .severe,
                kind: .crisis,
                linkedActionIDs: [],
                notable: true,
                playerRelated: true,
                strategicEffects: [
                    NativeStrategicEffect(
                        date: state.gameDate,
                        eventId: threatID,
                        id: "\(threatID)-effect",
                        magnitude: 1,
                        summary: "\(rivalName) has earned two rival-campaign milestones while holding every active objective.",
                        target: state.country.code,
                        track: .securityAnxiety
                    )
                ],
                title: "RIVAL THREAT: \(rivalName) Near Victory"
            )
            state.timeline.insert(threatEvent, at: 0)
        }

        // Coalition formation: when worldTension > 60, allies form mutual defense pacts
        if state.worldTension > 60 {
            for code in strategicCodes {
                guard let aiState = state.aiCountryStates[code] else { continue }
                let playerScore = aiState.relationshipScores[state.country.code] ?? 0
                guard playerScore < -30 else { continue }

                // Find another AI that is friendly to this one and hostile to the player
                for (otherCode, otherScore) in aiState.relationshipScores {
                    guard otherScore > 40, let otherAI = state.aiCountryStates[otherCode] else { continue }
                    let otherPlayerScore = otherAI.relationshipScores[state.country.code] ?? 0
                    guard otherPlayerScore < -30 else { continue }

                    // Check if pact already exists
                    let pactExists = state.activeOffers.contains { offer in
                        offer.proposerCode == code && offer.type == .militaryAlliance && offer.status == .accepted
                    }
                    guard !pactExists else { continue }

                    // Deterministic 20% chance
                    let coalitionSeed = "\(state.scenarioID)-\(state.gameDate)-coalition-\(code)-\(otherCode)"
                    let coalitionRoll = NativeGameEngine.stablePercentagePublic(seed: coalitionSeed)
                    guard coalitionRoll < 20 else { continue }

                    let pactOffer = NativeDiplomaticOffer(
                        id: "coalition-\(code)-\(otherCode)-\(state.gameDate)",
                        proposerCode: code,
                        type: .militaryAlliance,
                        description: "\(code) and \(otherCode) signed a mutual defense pact against growing threats.",
                        stabilityCost: 0,
                        relationshipEffect: 10,
                        growthDelta: 0,
                        status: .accepted,
                        turnProposed: state.round
                    )
                    state.activeOffers.append(pactOffer)

                    let coalitionEvent = NativeCampaignEvent(
                        date: state.gameDate,
                        description: "COALITION: \(code) and \(otherCode) formalized a mutual defense pact amid rising global tensions. Both nations committed to collective security against perceived threats.",
                        id: "coalition-event-\(code)-\(otherCode)-\(state.gameDate)",
                        importance: .major,
                        kind: .diplomacy,
                        linkedActionIDs: [],
                        notable: true,
                        playerRelated: true,
                        strategicEffects: [],
                        title: "Defense Pact: \(code) + \(otherCode)"
                    )
                    state.timeline.insert(coalitionEvent, at: 0)
                    break
                }
            }
        }

        // Player invasion response: allies of invaded countries penalize the player
        let playerOccupations = state.regionOccupations.filter { key, val in
            let reg = GeopoliticalMapData.regionByID[key]
            return reg?.countryCode != state.country.code && val == state.country.code
        }
        for (regionID, _) in playerOccupations {
            guard let region = GeopoliticalMapData.regionByID[regionID] else { continue }
            let defenderCode = region.countryCode
            // Find allies of the defender (relationship > 50 to defender)
            for allyCode in Array(state.aiCountryStates.keys) {
                guard allyCode != state.country.code,
                      var aiState = state.aiCountryStates[allyCode]
                else { continue }
                let allyToDefender = aiState.relationshipScores[defenderCode] ?? 0
                guard allyToDefender > 50 else { continue }
                // Penalize relationship with player
                let currentScore = aiState.relationshipScores[state.country.code] ?? 0
                aiState.relationshipScores[state.country.code] = max(-100, currentScore - max(1, months * 2))
                state.aiCountryStates[allyCode] = aiState
            }
        }

        // 2.5. Process ideological alignment relationship drift
        for codeA in strategicCodes {
            if codeA == state.country.code {
                continue
            }
            guard var aiStateA = state.aiCountryStates[codeA],
                  let ledgerA = state.economicLedgers[codeA] else { continue }

            var updatedRels = aiStateA.relationshipScores
            for (codeB, currentScore) in updatedRels {
                let ledgerB = (codeB == state.country.code) ? state.economicLedger : state.economicLedgers[codeB]
                guard let lB = ledgerB else { continue }

                var drift = 0.0
                if ledgerA.governmentType == lB.governmentType {
                    drift = 0.05 * Double(months) // Slow positive drift
                } else if (ledgerA.governmentType == "democracy" && lB.governmentType == "autocracy") ||
                    (ledgerA.governmentType == "autocracy" && lB.governmentType == "democracy")
                {
                    drift = -0.1 * Double(months) // Slow negative drift
                }

                if drift != 0 {
                    updatedRels[codeB] = max(-100, min(100, currentScore + Int(drift.rounded())))
                }
            }
            aiStateA.relationshipScores = updatedRels
            state.aiCountryStates[codeA] = aiStateA
        }

        // 2.7. Process Elections, Public Approval Drift, and Coups
        for code in strategicCodes {
            guard var ledger = state.economicLedgers[code] else { continue }

            // 2.7.1. Approval Rating Drift
            // Economy factors
            let growthFactor = ledger.realGrowthPercent * 1.5
            let inflationFactor = -(ledger.inflationPercent - 3.0) * 0.8
            let unemploymentFactor = -(ledger.unemploymentPercent - 6.0) * 1.2
            // Security factors
            let securityFactor = (ledger.securityIndex - 70.0) * 0.3
            let rebelFactor = -ledger.rebelControlPercent * 0.6

            let totalApprovalDrift = (growthFactor + inflationFactor + unemploymentFactor + securityFactor + rebelFactor) * Double(months)

            var approvalRng = SimpleRNG(seedString: "approval-\(code)-\(state.round)-\(state.scenarioID)")
            let noise = (approvalRng.nextDouble() * 8.0) - 4.0 // Seeded noise -4.0 to +4.0

            ledger.publicApprovalPercent = clampDouble(ledger.publicApprovalPercent + totalApprovalDrift + noise, 10.0, 90.0)

            // 2.7.2. Handle Democracy Elections & Snap Elections & Democratic Collapses
            if ledger.governmentType == "democracy" {
                var triggerElection = false
                var isSnapElection = false
                let subtype = democraticSubtype(for: code)
                let profile = startingElectionProfile(for: code)

                // Normal election cycle
                if state.round >= ledger.nextElectionRound {
                    triggerElection = true
                }
                // Snap election for parliamentary systems under instability (low stability < 40 or low approval < 35)
                else if subtype == .parliamentary {
                    let currentStability = if code == state.country.code {
                        Double(state.stability)
                    } else {
                        Double(state.economicLedgers[code]?.securityIndex ?? 50.0) // Security index as proxy for AI stability
                    }
                    if currentStability < 40.0 || ledger.publicApprovalPercent < 35.0 {
                        var snapRng = SimpleRNG(seedString: "snap-election-\(code)-\(state.round)-\(state.scenarioID)")
                        if snapRng.nextDouble() < 0.15 {
                            triggerElection = true
                            isSnapElection = true
                        }
                    }
                }

                if triggerElection {
                    var electionRng = SimpleRNG(seedString: "election-\(code)-\(state.round)-\(state.scenarioID)")
                    let winChance = ledger.publicApprovalPercent / 100.0
                    let incumbentWins = electionRng.nextDouble() < winChance
                    let nextElection = state.round + profile.cycleLength

                    let electionTitle: String
                    let electionDesc: String
                    var stabilityDelta = 0

                    let prefix = isSnapElection ? "Snap Elections: " : "Elections: "
                    let reason = isSnapElection ? "following a vote of no confidence and parliament dissolution due to political instability" : "after completing the standard legislative term"

                    if incumbentWins {
                        electionTitle = "\(prefix)Incumbent Wins in \(code)"
                        electionDesc = "Democracy in action: Voters in \(code) \(reason) re-elected the incumbent administration with \(String(format: "%.1f%%", ledger.publicApprovalPercent)) approval rating. The governing doctrine of \(code == state.country.code ? "the player" : state.aiCountryStates[code]?.doctrine.rawValue ?? "administration") remains in place."
                    } else {
                        electionTitle = "\(prefix)Opposition Wins in \(code)"
                        electionDesc = "Democracy in action: Voters in \(code) \(reason) voted for change, defeating the incumbent administration after approval fell to \(String(format: "%.1f%%", ledger.publicApprovalPercent))%. A new government has been sworn into office."

                        if code == state.country.code {
                            stabilityDelta = -5
                            ledger.publicApprovalPercent = 55.0 // Reset to honeymoon approval
                        } else {
                            if var aiState = state.aiCountryStates[code] {
                                let doctrines: [NativeAIDoctrine] = [.mercantile, .expansionist, .isolationist, .defensive, .collaborative]
                                let nextDoc = doctrines[Int(electionRng.nextDouble() * Double(doctrines.count)) % doctrines.count]
                                let budgets: [NativeAIBudgetPriority] = [.growth, .stability, .military, .diplomacy]
                                let nextBudget = budgets[Int(electionRng.nextDouble() * Double(budgets.count)) % budgets.count]

                                aiState.doctrine = nextDoc
                                aiState.budgetPriority = nextBudget
                                aiState.multiTurnAgenda = "A newly elected administration shifts the national agenda toward \(nextDoc.displayName.lowercased()) and \(nextBudget.rawValue) priorities."
                                aiState.agendaProgress = 0
                                state.aiCountryStates[code] = aiState
                            }
                            ledger.publicApprovalPercent = 55.0 // Reset to honeymoon approval
                        }
                    }

                    ledger.nextElectionRound = nextElection

                    if code == state.country.code {
                        let electionEvent = NativeCampaignEvent(
                            date: state.gameDate,
                            description: electionDesc,
                            id: "election-resolution-\(code.lowercased())-\(state.round)",
                            importance: .major,
                            kind: .world,
                            linkedActionIDs: [],
                            notable: true,
                            playerRelated: true,
                            strategicEffects: stabilityDelta != 0 ? [
                                NativeStrategicEffect(
                                    date: state.gameDate,
                                    eventId: "election-resolution-\(code.lowercased())-\(state.round)",
                                    id: "election-stability-effect-\(code.lowercased())-\(state.round)",
                                    magnitude: stabilityDelta,
                                    summary: "Political transition causes temporary stability hit.",
                                    target: state.country.code,
                                    track: .internalStability
                                )
                            ] : [],
                            title: electionTitle
                        )
                        state.timeline.insert(electionEvent, at: 0)
                        state.stability = max(0, min(100, state.stability + stabilityDelta))
                    }
                }

                // Democratic collapse check under severe instability
                let currentStability = if code == state.country.code {
                    Double(state.stability)
                } else {
                    Double(state.economicLedgers[code]?.securityIndex ?? 50.0)
                }
                if currentStability < 20.0 || ledger.publicApprovalPercent < 20.0 {
                    var collapseRng = SimpleRNG(seedString: "collapse-\(code)-\(state.round)-\(state.scenarioID)")
                    if collapseRng.nextDouble() < 0.10 { // 10% chance of collapse under crisis
                        let nextGovType = collapseRng.nextDouble() < 0.5 ? "autocracy" : "hybrid"
                        ledger.governmentType = nextGovType

                        if code == state.country.code {
                            let collapseTitle = "Democracy Collapses in \(code)"
                            let collapseDesc = "Severe institutional instability and collapsing public trust have fractured the democratic system in \(code). The constitution has been suspended, transitioning the state into a \(nextGovType) regime."

                            let collapseEvent = NativeCampaignEvent(
                                date: state.gameDate,
                                description: collapseDesc,
                                id: "democracy-collapse-\(code.lowercased())-\(state.round)",
                                importance: .severe,
                                kind: .crisis,
                                linkedActionIDs: [],
                                notable: true,
                                playerRelated: true,
                                strategicEffects: [
                                    NativeStrategicEffect(
                                        date: state.gameDate,
                                        eventId: "democracy-collapse-\(code.lowercased())-\(state.round)",
                                        id: "democracy-collapse-effect-\(code.lowercased())-\(state.round)",
                                        magnitude: -15,
                                        summary: "Democratic collapse causes severe stability shock.",
                                        target: state.country.code,
                                        track: .internalStability
                                    )
                                ],
                                title: collapseTitle
                            )
                            state.timeline.insert(collapseEvent, at: 0)
                            state.stability = max(0, state.stability - 15)
                        } else if var aiState = state.aiCountryStates[code] {
                            aiState.doctrine = collapseRng.nextDouble() < 0.5 ? .isolationist : .expansionist
                            aiState.budgetPriority = .stability
                            aiState.multiTurnAgenda = "Consolidate control after the fall of the democratic constitution."
                            aiState.agendaProgress = 0
                            state.aiCountryStates[code] = aiState
                        }
                    }
                }
            } else if ledger.governmentType == "autocracy" {
                // 2.7.3. Handle Autocracy Coups under low approval (<25%)
                if ledger.publicApprovalPercent < 25.0 {
                    var coupRng = SimpleRNG(seedString: "coup-\(code)-\(state.round)-\(state.scenarioID)")
                    // 30% chance of coup per turn if approval is critically low
                    if coupRng.nextDouble() < 0.3 {
                        let nextGovType = coupRng.nextDouble() < 0.5 ? "democracy" : "hybrid"
                        ledger.governmentType = nextGovType

                        let coupTitle = "Coup d'État in \(code): Regime Overthrown"
                        let coupDesc = "Faced with severe economic distress and collapsing regime support (\(String(format: "%.1f%%", ledger.publicApprovalPercent))%), military forces and civilian factions staged a coup in \(code), overthrowing the autocracy. The country has transitioned into a \(nextGovType) regime, with democratic elections scheduled in 12 months."
                        var stabilityDelta = 0

                        if code == state.country.code {
                            stabilityDelta = -15
                            ledger.publicApprovalPercent = 45.0 // Regime reset
                        } else {
                            // AI country shifts to defensive/isolationist and resets relationships with democracies
                            if var aiState = state.aiCountryStates[code] {
                                aiState.doctrine = coupRng.nextDouble() < 0.5 ? .defensive : .isolationist
                                aiState.budgetPriority = .stability
                                aiState.multiTurnAgenda = "A transition council secures key infrastructure during the political transition."
                                aiState.agendaProgress = 0

                                // Decay relations with remaining democracies
                                for otherCode in strategicCodes where otherCode != code {
                                    if state.economicLedgers[otherCode]?.governmentType == "democracy" {
                                        aiState.relationshipScores[otherCode] = max(-100, (aiState.relationshipScores[otherCode] ?? 0) - 40)
                                    }
                                }
                                state.aiCountryStates[code] = aiState
                            }
                            ledger.publicApprovalPercent = 45.0
                        }

                        ledger.nextElectionRound = state.round + 12 // Elections scheduled in 1 year

                        if code == state.country.code {
                            let coupEvent = NativeCampaignEvent(
                                date: state.gameDate,
                                description: coupDesc,
                                id: "coup-\(code.lowercased())-\(state.round)",
                                importance: .severe,
                                kind: .crisis,
                                linkedActionIDs: [],
                                notable: true,
                                playerRelated: true,
                                strategicEffects: stabilityDelta != 0 ? [
                                    NativeStrategicEffect(
                                        date: state.gameDate,
                                        eventId: "coup-\(code.lowercased())-\(state.round)",
                                        id: "coup-stability-effect-\(code.lowercased())-\(state.round)",
                                        magnitude: stabilityDelta,
                                        summary: "A military coup fractures national stability.",
                                        target: state.country.code,
                                        track: .internalStability
                                    )
                                ] : [],
                                title: coupTitle
                            )
                            state.timeline.insert(coupEvent, at: 0)
                            state.stability = max(0, min(100, state.stability + stabilityDelta))
                        }
                    }
                }
            } else if ledger.governmentType == "hybrid" {
                // 2.7.4. Handle Hybrid Regime Transitions (Democratic reforms or Autocratic consolidation)
                let currentStability = if code == state.country.code {
                    Double(state.stability)
                } else {
                    Double(state.economicLedgers[code]?.securityIndex ?? 50.0)
                }

                var transitionRng = SimpleRNG(seedString: "hybrid-transition-\(code)-\(state.round)-\(state.scenarioID)")

                // Liberalization to Democracy (High stability > 70 and high approval > 60)
                if currentStability > 70.0 && ledger.publicApprovalPercent > 60.0 {
                    if transitionRng.nextDouble() < 0.10 {
                        ledger.governmentType = "democracy"
                        ledger.nextElectionRound = state.round + 24 // Elections in 2 years

                        if code == state.country.code {
                            let reformTitle = "Political Reform: Democracy Restored in \(code)"
                            let reformDesc = "Following a period of stability and high public confidence, \(code) has enacted sweeping constitutional reforms, consolidating democratic institutions. Open elections are scheduled in 24 months."

                            let reformEvent = NativeCampaignEvent(
                                date: state.gameDate,
                                description: reformDesc,
                                id: "hybrid-reform-\(code.lowercased())-\(state.round)",
                                importance: .major,
                                kind: .world,
                                linkedActionIDs: [],
                                notable: true,
                                playerRelated: true,
                                strategicEffects: [
                                    NativeStrategicEffect(
                                        date: state.gameDate,
                                        eventId: "hybrid-reform-\(code.lowercased())-\(state.round)",
                                        id: "hybrid-reform-effect-\(code.lowercased())-\(state.round)",
                                        magnitude: 8,
                                        summary: "Democratic restoration bolsters national stability.",
                                        target: state.country.code,
                                        track: .internalStability
                                    )
                                ],
                                title: reformTitle
                            )
                            state.timeline.insert(reformEvent, at: 0)
                            state.stability = min(100, state.stability + 8)
                        }
                    }
                }
                // Consolidation to Autocracy (Low stability < 30 or low approval < 30)
                else if currentStability < 30.0 || ledger.publicApprovalPercent < 30.0, transitionRng.nextDouble() < 0.10 {
                    ledger.governmentType = "autocracy"

                    if code == state.country.code {
                        let consTitle = "Autocratic Consolidation in \(code)"
                        let consDesc = "In response to severe instability and public discontent, the administration in \(code) has dissolved checks and balances, consolidating full autocratic control over state institutions."

                        let consEvent = NativeCampaignEvent(
                            date: state.gameDate,
                            description: consDesc,
                            id: "hybrid-consolidation-\(code.lowercased())-\(state.round)",
                            importance: .severe,
                            kind: .crisis,
                            linkedActionIDs: [],
                            notable: true,
                            playerRelated: true,
                            strategicEffects: [
                                NativeStrategicEffect(
                                    date: state.gameDate,
                                    eventId: "hybrid-consolidation-\(code.lowercased())-\(state.round)",
                                    id: "hybrid-consolidation-effect-\(code.lowercased())-\(state.round)",
                                    magnitude: -10,
                                    summary: "Autocratic consolidation impacts stability.",
                                    target: state.country.code,
                                    track: .internalStability
                                )
                            ],
                            title: consTitle
                        )
                        state.timeline.insert(consEvent, at: 0)
                        state.stability = max(0, state.stability - 10)
                    }
                }
            }

            state.economicLedgers[code] = ledger
        }

        // MARK: - Dynamic AI-vs-AI Geopolitics (Rival World Life)

        //
        // The passive drift loop above advances each AI's agenda and relationship
        // toward the *player*. This block is what makes the rivals feel alive
        // among themselves: expansionist powers wage war on their neighbors
        // (changing the occupation map), ideologically aligned regimes form
        // lasting alliances, and mercantile powers sign trade corridors that
        // actually move both countries' ledgers. All paths are deterministic
        // (seeded by scenario/date/actors) and bounded so long campaigns don't
        // cascade into chaos.
        simulateRivalGeopolitics(state: &state, months: months)

        // Update deterministic AI map armies and regional buildings in the unified AI pipeline
        simulateAIMapPresence(state: &state)

        // Evaluate alternative history scenario event chains when active
        if !state.eventFlags.isEmpty {
            evaluateAlternativeHistoryEvents(state: &state)
        }

        // Sync player's main ledger
        if let playerLedger = state.economicLedgers[state.country.code] {
            state.economicLedger = playerLedger
        }
    }

    /// **Unified AI Map Presence**:
    /// Updates visible AI armies and regional buildings (`fortress`, `market`, border repositioning)
    /// deterministically within the single per-turn AI pipeline (replacing `BackgroundSimulationService`).
    static func simulateAIMapPresence(state: inout NativeCampaignState) {
        var armiesByCountry = Dictionary(grouping: state.mapArmies, by: \.countryCode)
        var buildings = state.mapBuildings
        var generatedMoves = 0

        let activeCountries = Set(state.aiCountryStates.keys)
            .union(state.economicLedgers.keys)
            .subtracting([state.country.code, "GLOBAL"])
            .sorted()

        let playerRegions = GeopoliticalMapData.regions(forCountryCode: state.country.code).filter { $0.countryCode != "WATER" }
        let playerCenter = playerRegions.first?.center

        for code in activeCountries {
            let countryRegions = GeopoliticalMapData.regions(forCountryCode: code).filter { $0.countryCode != "WATER" }
            guard let homeRegion = countryRegions.first ?? GeopoliticalMapData.regionByID[code] else { continue }

            let aiState = state.aiCountryStates[code] ?? NativeAICountryState(
                countryCode: code,
                doctrine: .neutral,
                budgetPriority: .economy,
                relationshipScores: [:],
                multiTurnAgenda: "Stabilize regional capacity.",
                agendaProgress: 20
            )
            let ledger = state.economicLedgers[code]

            if armiesByCountry[code, default: []].isEmpty {
                let gdp = ledger?.nominalGDPTrillions ?? 0.5
                let profile = Native2010WorldModel.profile(for: PlayerCountry(code: code, name: code))
                let mpi = gdp * (profile.militarySpendingPercent / 2.0) * (1.0 - (Double(profile.corruptionIndex) / 100.0) * 0.6)
                let strength = min(100, max(12, Int((mpi * 8.0).rounded()) + 20))
                let type: NativeArmyKind = aiState.budgetPriority == .military ? .armor : .infantry
                armiesByCountry[code] = [
                    NativeArmySnapshot(
                        countryCode: code,
                        currentRegionID: homeRegion.id,
                        id: "army-\(code)-\(homeRegion.id)",
                        strength: strength,
                        type: type
                    )
                ]
            }

            let security = ledger?.securityIndex ?? 50.0
            let tension = Double(state.worldTension) / 100.0
            let relation = Double(aiState.relationshipScores[state.country.code] ?? 0) / 100.0
            let roll = Int(NativeGameEngine.fnv1aHash("\(code)|\(state.gameDate)|\(state.round)") % 100)

            if aiState.budgetPriority == .military || relation < -0.35 || tension > 0.68 {
                if roll > 20 {
                    let targetRegion = playerCenter.flatMap { pCenter in
                        countryRegions.min { left, right in
                            let ldx = left.center.x - pCenter.x
                            let ldy = left.center.y - pCenter.y
                            let rdx = right.center.x - pCenter.x
                            let rdy = right.center.y - pCenter.y
                            return (ldx * ldx + ldy * ldy) < (rdx * rdx + rdy * rdy)
                        }
                    } ?? countryRegions.first
                    if let targetRegion, var armies = armiesByCountry[code], var firstArmy = armies.first {
                        firstArmy.targetRegionID = targetRegion.id
                        firstArmy.currentRegionID = targetRegion.id
                        armies[0] = firstArmy
                        armiesByCountry[code] = armies
                        generatedMoves += 1
                    }
                } else if !buildings.contains(where: { $0.regionID == homeRegion.id && $0.ownerCountryCode == code && $0.type == .fortress }) {
                    buildings.append(NativeBuildingSnapshot(ownerCountryCode: code, regionID: homeRegion.id, type: .fortress))
                    generatedMoves += 1
                }
            } else if security < 45 || aiState.doctrine == .defensive {
                if !buildings.contains(where: { $0.regionID == homeRegion.id && $0.ownerCountryCode == code && $0.type == .fortress }) {
                    buildings.append(NativeBuildingSnapshot(ownerCountryCode: code, regionID: homeRegion.id, type: .fortress))
                    generatedMoves += 1
                }
            } else if !buildings.contains(where: { $0.regionID == homeRegion.id && $0.ownerCountryCode == code && $0.type == .market }) {
                buildings.append(NativeBuildingSnapshot(ownerCountryCode: code, regionID: homeRegion.id, type: .market))
                generatedMoves += 1
            }
        }

        state.mapArmies = armiesByCountry.values.flatMap(\.self).sorted { $0.id < $1.id }
        state.mapBuildings = buildings.sorted { $0.id < $1.id }
        if generatedMoves > 0, !state.lastSummary.contains("Background simulation added") {
            state.lastSummary = "\(state.lastSummary) Background simulation added \(generatedMoves) visible strategic movement\(generatedMoves == 1 ? "" : "s")."
        }
    }

    /// **Dynamic AI-vs-AI Geopolitics** — rivals act on each other, not just on
    /// the player. This is the "living world" pass: AI-vs-AI wars that redraw
    /// the occupation map, ideological alliances that persist, and structured
    /// trade corridors with real economic effects on both signatories.
    ///
    /// Design goals:
    /// 1. **Visibility** — events change the map (occupations, conflicts) and
    ///    the economy (ledger deltas on both sides), so the player sees a world
    ///    in motion rather than a static board.
    /// 2. **Determinism** — every roll is seeded by scenario/date/actors, so a
    ///    given campaign replays identically and save diffs stay stable.
    /// 3. **Bounded chaos** — at most one war start, one alliance, and one
    ///    trade pact per AI per turn; relations are clamped to [-100, 100];
    ///    ledger deltas are small and clamped.
    /// 4. **Player relevance** — the player is never a direct party, but
    ///    second-order effects (alliance blocs polarizing against the player,
    ///    trade corridors diverting commerce, wars spilling refugees) ripple
    ///    back into the player's economy and diplomacy over time.
    static func simulateRivalGeopolitics(
        state: inout NativeCampaignState,
        months: Int,
        agentTurns: [NativeRivalAgentTurn] = []
    ) {
        // ── 0. Process LLM Multi-Agent Rival Dispatches & Strategic Orders ──
        for turn in agentTurns {
            let actorName = CountryNameResolver.name(forCode: turn.actorCode, in: state)

            // Intercepted Diplomatic Dispatches
            for dispatch in turn.dispatches {
                let recipientName = CountryNameResolver.name(forCode: dispatch.recipientCode, in: state)
                let dispatchEvent = NativeCampaignEvent(
                    date: state.gameDate,
                    description: "Intercepted diplomatic dispatch from \(actorName) (\(dispatch.senderCode)) to \(recipientName) (\(dispatch.recipientCode)) [Tone: \(dispatch.tone.capitalized)]: \"\(dispatch.message)\"",
                    id: "ai-dispatch-\(dispatch.senderCode)-\(dispatch.recipientCode)-\(state.gameDate)",
                    importance: .minor,
                    kind: .diplomacy,
                    linkedActionIDs: [],
                    notable: true,
                    playerRelated: false,
                    strategicEffects: [],
                    title: "INTELLIGENCE INTERCEPT: \(dispatch.senderCode) ➔ \(dispatch.recipientCode)"
                )
                state.timeline.insert(dispatchEvent, at: 0)
            }

            // Intelligence Timeline Summary
            if !turn.narrativeSummary.isEmpty {
                let summaryEvent = NativeCampaignEvent(
                    date: state.gameDate,
                    description: turn.narrativeSummary,
                    id: "ai-agent-action-\(turn.actorCode)-\(state.gameDate)",
                    importance: .major,
                    kind: .world,
                    linkedActionIDs: [],
                    notable: true,
                    playerRelated: false,
                    strategicEffects: [],
                    title: "RIVAL INTEL: \(actorName) Strategy Update"
                )
                state.timeline.insert(summaryEvent, at: 0)
            }

            // Tactical Hex Nudge Execution
            if let hexCode = turn.hexLeverCode, !hexCode.isEmpty, let lever = decodeHexLever(hexCode), var ledger = state.economicLedgers[turn.actorCode] {
                ledger.realGrowthPercent = max(-10.0, min(15.0, ledger.realGrowthPercent + lever.growthDelta))
                ledger.budgetBalancePercentGDP = max(-20.0, min(15.0, ledger.budgetBalancePercentGDP + lever.budgetDelta))
                ledger.securityIndex = max(0.0, min(100.0, ledger.securityIndex + lever.securityDelta))
                state.economicLedgers[turn.actorCode] = ledger
            }
        }

        let strategicCodes = defaultStrategicCountryCodes.filter { $0 != "GLOBAL" && $0 != state.country.code }

        // ── 1. AI-vs-AI wars: expansionist/military regimes attack their rivals ──
        // More aggressive than the legacy invasion path above because rivals now
        // actively contest each other's territory. Each attack can escalate an
        // existing conflict (raise intensity) or start a new one, and imposes
        // real economic costs on both attacker (war spending) and defender
        // (capital flight, supply disruption).
        //
        // Collect qualifying attackers first, sorted by how provoked they are
        // (most-hated rival first), so the most dramatic conflicts resolve
        // before the per-turn war cap is reached.
        struct WarCandidate {
            let attackerCode: String
            let targetCode: String
            let hatred: Int
            let isAggressor: Bool
        }
        var warCandidates: [WarCandidate] = []
        for attackerCode in strategicCodes {
            guard let attacker = state.aiCountryStates[attackerCode] else { continue }
            let isAggressor = attacker.doctrine == .expansionist && attacker.budgetPriority == .military
            let isThreatenedDefender = attacker.doctrine == .defensive &&
                (attacker.relationshipScores.values.filter { $0 < -60 }.count >= 2)
            guard isAggressor || isThreatenedDefender else { continue }

            let bestTarget = strategicCodes.compactMap { candidate -> (String, Int)? in
                guard candidate != attackerCode else { return nil }
                let score = attacker.relationshipScores[candidate] ?? 0
                guard score < -40, !GeopoliticalMapData.regions(forCountryCode: candidate).isEmpty else { return nil }
                return (candidate, score)
            }
            .min { $0.1 < $1.1 }

            guard let (target, hatred) = bestTarget else { continue }
            warCandidates.append(WarCandidate(
                attackerCode: attackerCode, targetCode: target,
                hatred: abs(hatred), isAggressor: isAggressor
            ))
        }
        // Sort: most provoked (highest hatred) first, aggressors before defenders.
        warCandidates.sort { lhs, rhs in
            if lhs.isAggressor != rhs.isAggressor {
                return lhs.isAggressor
            }
            return lhs.hatred > rhs.hatred
        }

        var warsThisTurn = 0
        for candidate in warCandidates {
            // Cap at 2 war starts per turn to keep the map legible.
            guard warsThisTurn < 2 else { break }
            let attackerCode = candidate.attackerCode
            let targetCode = candidate.targetCode

            // Deterministic war-roll. Base 18% for aggressors, 8% for cornered
            // defenders; scaled slightly by how hated the rival is.
            let hatred = candidate.hatred
            let baseChance: Int = candidate.isAggressor ? 18 : 8
            let scaledChance = min(45, baseChance + hatred / 10)
            let warSeed = "\(state.scenarioID)-\(state.gameDate)-war-\(attackerCode)-\(targetCode)"
            let warRoll = NativeGameEngine.stablePercentagePublic(seed: warSeed)
            guard warRoll < Double(scaledChance) else { continue }

            // Resolve the attack: escalate an existing conflict or open a new one.
            let targetRegions = GeopoliticalMapData.regions(forCountryCode: targetCode)
            guard let primaryTargetRegion = targetRegions.first else { continue }

            // Don't double-open a conflict the attacker already controls.
            if let existing = state.regionConflicts[primaryTargetRegion.id],
               existing.controllerCode == attackerCode,
               existing.mode == .conventionalOccupation
            {
                // Escalate intensity instead (caps at 5).
                state.regionConflicts[primaryTargetRegion.id]?.intensity = min(5, existing.intensity + 1)
                state.regionConflicts[primaryTargetRegion.id]?.updatedAt = state.gameDate
            } else {
                // Aggressors that already hold a rival region occupy; otherwise
                // contest the border. This makes wars *change the map*.
                let attackerOccupations = state.regionOccupations.filter {
                    $0.value == attackerCode &&
                        GeopoliticalMapData.regionByID[$0.key]?.countryCode != attackerCode
                }.count
                let occupy = attackerOccupations >= 1 || candidate.isAggressor

                if occupy {
                    state.regionOccupations[primaryTargetRegion.id] = attackerCode
                }
                state.regionConflicts[primaryTargetRegion.id] = NativeRegionConflictState(
                    controllerCode: attackerCode,
                    intensity: occupy ? 4 : 3,
                    mode: occupy ? .conventionalOccupation : .contestedBorder,
                    originalCountryCode: targetCode,
                    rebelDelta: 0,
                    regionID: primaryTargetRegion.id,
                    securityDelta: 0,
                    sourceEventID: "ai-war-\(attackerCode)-\(targetCode)-\(state.gameDate)",
                    summary: "\(attackerCode) launched a military offensive against \(targetCode) in the \(primaryTargetRegion.name) region.",
                    updatedAt: state.gameDate
                )
            }

            // Relationship collapse between the combatants; ripple to their allies.
            applyRelationDelta(&state, from: attackerCode, to: targetCode, delta: -15)
            applyRelationDelta(&state, from: targetCode, to: attackerCode, delta: -15)

            // Third parties pick sides: enemies of the attacker warm to the
            // defender; allies of the attacker cool toward the defender. This
            // is how a single war cascades into bloc politics.
            if let attackerState = state.aiCountryStates[attackerCode] {
                for (thirdCode, thirdScore) in attackerState.relationshipScores {
                    guard strategicCodes.contains(thirdCode), thirdCode != targetCode else { continue }
                    if thirdScore > 40 {
                        // Attacker's ally: cools toward defender.
                        applyRelationDelta(&state, from: thirdCode, to: targetCode, delta: -4)
                    } else if thirdScore < -40 {
                        // Attacker's enemy: warms toward defender (enemy-of-my-enemy).
                        applyRelationDelta(&state, from: thirdCode, to: targetCode, delta: 5)
                    }
                }
            }

            // Economic costs: war spending on the attacker, capital flight on
            // the defender. Both are clamped and capped so a long war degrades
            // but never bankrupts a country in a single turn.
            applyWarEconomicCost(
                state: &state, countryCode: attackerCode, months: months,
                growthDelta: -0.3, debtDelta: 1.2, securityDelta: 1.5,
                ledgerRuleID: "ai-war-spending", summary: "War spending vs \(targetCode) (\(primaryTargetRegion.name))."
            )
            applyWarEconomicCost(
                state: &state, countryCode: targetCode, months: months,
                growthDelta: -0.6, debtDelta: 0.8, securityDelta: -2.0,
                ledgerRuleID: "ai-war-defense", summary: "Capital flight and supply disruption from war with \(attackerCode) (\(primaryTargetRegion.name))."
            )

            // Bump world tension: wars destabilize the global mood.
            state.worldTension = min(100, state.worldTension + 2)

            let warEvent = NativeCampaignEvent(
                date: state.gameDate,
                description: "\(attackerCode) opened a military offensive against \(targetCode) in the \(primaryTargetRegion.name) region. Combat operations are ongoing; regional trade routes are disrupted and neighboring powers are recalibrating their alignments.",
                id: "ai-war-\(attackerCode)-\(targetCode)-\(state.gameDate)",
                importance: .major,
                kind: .crisis,
                linkedActionIDs: [],
                notable: true,
                playerRelated: false,
                strategicEffects: [
                    NativeStrategicEffect(
                        date: state.gameDate,
                        eventId: "ai-war-\(attackerCode)-\(targetCode)-\(state.gameDate)",
                        id: "ai-war-tension-\(state.gameDate)",
                        magnitude: 2,
                        summary: "\(attackerCode)–\(targetCode) war raised global tension.",
                        target: "GLOBAL",
                        track: .diplomaticLeverage
                    )
                ],
                title: "\(attackerCode) vs \(targetCode): War Erupts"
            )
            state.timeline.insert(warEvent, at: 0)
            warsThisTurn += 1
        }

        // ── 2. Emergent alliances: ideologically aligned regimes formalize pacts ──
        // Unlike the tension-gated coalition above, this fires regardless of
        // world tension: democracies drift toward democracies, autocracies
        // toward autocracies, and close friends (>55) can convert a friendship
        // into a formal mutual-defense pact. The pact then persists and shifts
        // both members' relations with the rest of the world.
        for codeA in strategicCodes {
            guard let aiA = state.aiCountryStates[codeA],
                  let ledgerA = state.economicLedgers[codeA]
            else { continue }

            // Find the best alliance candidate: same government type, high
            // mutual relationship, not already allied.
            let candidate = strategicCodes.compactMap { codeB -> (String, Int)? in
                guard codeB > codeA else { return nil } // unique pair via lexical order
                guard let aiB = state.aiCountryStates[codeB],
                      let ledgerB = state.economicLedgers[codeB]
                else { return nil }
                let sameGov = ledgerA.governmentType == ledgerB.governmentType
                guard sameGov else { return nil }
                let relAB = aiA.relationshipScores[codeB] ?? 0
                let relBA = aiB.relationshipScores[codeA] ?? 0
                let mutual = min(relAB, relBA)
                guard mutual > 55 else { return nil }
                // Skip if an existing AI-to-AI alliance already links them.
                let alreadyAllied = state.activeOffers.contains { offer in
                    offer.type == .militaryAlliance &&
                        offer.status == .accepted &&
                        offer.targetCode != nil &&
                        ((offer.proposerCode == codeA && offer.targetCode == codeB) ||
                            (offer.proposerCode == codeB && offer.targetCode == codeA))
                }
                guard !alreadyAllied else { return nil }
                return (codeB, mutual)
            }
            .max { $0.1 < $1.1 }

            guard let (codeB, _) = candidate else { continue }

            // Deterministic 22% formation chance per qualifying pair per turn.
            let allianceSeed = "\(state.scenarioID)-\(state.gameDate)-alliance-\(codeA)-\(codeB)"
            let allianceRoll = NativeGameEngine.stablePercentagePublic(seed: allianceSeed)
            guard allianceRoll < 22 else { continue }

            let govLabel = ledgerA.governmentType.capitalized
            let pactOffer = NativeDiplomaticOffer(
                id: "ai-alliance-\(codeA)-\(codeB)-\(state.gameDate)",
                proposerCode: codeA,
                type: .militaryAlliance,
                description: "\(codeA) and \(codeB) formalized a \(govLabel) mutual-defense alliance, binding their security policies and aligning their diplomatic stances.",
                stabilityCost: 0,
                relationshipEffect: 15,
                growthDelta: 0,
                status: .accepted,
                turnProposed: state.round,
                targetCode: codeB
            )
            state.activeOffers.append(pactOffer)

            // Both allies gain security; slight growth drag from coordination.
            applyWarEconomicCost(
                state: &state, countryCode: codeA, months: months,
                growthDelta: -0.05, debtDelta: 0, securityDelta: 1.2,
                ledgerRuleID: "ai-alliance-security", summary: "Mutual-defense alliance with \(codeB) improved readiness."
            )
            applyWarEconomicCost(
                state: &state, countryCode: codeB, months: months,
                growthDelta: -0.05, debtDelta: 0, securityDelta: 1.2,
                ledgerRuleID: "ai-alliance-security", summary: "Mutual-defense alliance with \(codeA) improved readiness."
            )

            // Bloc polarization: both allies' enemies become each other's
            // enemies too (cooler relations), and their friends warm slightly.
            if let aiA = state.aiCountryStates[codeA] {
                for (thirdCode, score) in aiA.relationshipScores {
                    guard strategicCodes.contains(thirdCode), thirdCode != codeB else { continue }
                    if score < -30 {
                        applyRelationDelta(&state, from: codeB, to: thirdCode, delta: -3)
                    } else if score > 30 {
                        applyRelationDelta(&state, from: codeB, to: thirdCode, delta: 2)
                    }
                }
            }
            if let aiB = state.aiCountryStates[codeB] {
                for (thirdCode, score) in aiB.relationshipScores {
                    guard strategicCodes.contains(thirdCode), thirdCode != codeA else { continue }
                    if score < -30 {
                        applyRelationDelta(&state, from: codeA, to: thirdCode, delta: -3)
                    } else if score > 30 {
                        applyRelationDelta(&state, from: codeA, to: thirdCode, delta: 2)
                    }
                }
            }

            let allyEvent = NativeCampaignEvent(
                date: state.gameDate,
                description: "\(codeA) and \(codeB) signed a formal \(govLabel) mutual-defense alliance. The pact commits both nations to collective security and signals a new power bloc on the world stage — one the player's diplomacy will have to reckon with.",
                id: "ai-alliance-event-\(codeA)-\(codeB)-\(state.gameDate)",
                importance: .major,
                kind: .diplomacy,
                linkedActionIDs: [],
                notable: true,
                playerRelated: false,
                strategicEffects: [],
                title: "New Alliance: \(codeA) + \(codeB)"
            )
            state.timeline.insert(allyEvent, at: 0)
            break // one alliance per turn
        }

        // ── 3. Structured AI-vs-AI trade corridors ──
        // Mercantile/growth doctrines with a warm (>40) relationship toward
        // another mercantile/growth partner sign a trade corridor that
        // *actually moves both ledgers*: +trade balance and +growth on both
        // sides, small but compounding. This is the "treaties" layer the
        // passive drift loop never had.
        for codeA in strategicCodes {
            guard let aiA = state.aiCountryStates[codeA] else { continue }
            let aIsCommercial = aiA.doctrine == .mercantile || aiA.budgetPriority == .growth
            guard aIsCommercial else { continue }

            let partner = strategicCodes.compactMap { codeB -> (String, Int)? in
                guard codeB > codeA, let aiB = state.aiCountryStates[codeB] else { return nil }
                let bIsCommercial = aiB.doctrine == .mercantile || aiB.budgetPriority == .growth
                guard bIsCommercial else { return nil }
                let mutual = min(
                    aiA.relationshipScores[codeB] ?? 0,
                    aiB.relationshipScores[codeA] ?? 0
                )
                guard mutual > 40 else { return nil }
                // Skip pairs already linked by an active trade treaty.
                let exists = state.activeOffers.contains { offer in
                    offer.type == .tradeAgreement &&
                        offer.status == .accepted &&
                        offer.targetCode != nil &&
                        ((offer.proposerCode == codeA && offer.targetCode == codeB) ||
                            (offer.proposerCode == codeB && offer.targetCode == codeA))
                }
                guard !exists else { return nil }
                return (codeB, mutual)
            }
            .max { $0.1 < $1.1 }
            .map(\.0)

            guard let codeB = partner else { continue }

            let tradeSeed = "\(state.scenarioID)-\(state.gameDate)-ai-trade-\(codeA)-\(codeB)"
            let tradeRoll = NativeGameEngine.stablePercentagePublic(seed: tradeSeed)
            guard tradeRoll < 28 else { continue }

            let tradeOffer = NativeDiplomaticOffer(
                id: "ai-trade-\(codeA)-\(codeB)-\(state.gameDate)",
                proposerCode: codeA,
                type: .tradeAgreement,
                description: "\(codeA) and \(codeB) established a structured trade corridor, lowering tariffs and coordinating commercial policy between their economies.",
                stabilityCost: 0,
                relationshipEffect: 8,
                growthDelta: 0.15,
                status: .accepted,
                turnProposed: state.round,
                targetCode: codeB
            )
            state.activeOffers.append(tradeOffer)

            // Real ledger movement on both sides — this is the whole point.
            applyTradePactBenefit(state: &state, countryCode: codeA, partnerCode: codeB, months: months)
            applyTradePactBenefit(state: &state, countryCode: codeB, partnerCode: codeA, months: months)

            let tradeEvent = NativeCampaignEvent(
                date: state.gameDate,
                description: "\(codeA) and \(codeB) signed a structured trade corridor agreement. Bilateral tariffs fall and commercial traffic between the two economies is projected to rise — a modest but compounding boost to both nations' ledgers, and a pact the player's own merchants will have to compete with.",
                id: "ai-trade-event-\(codeA)-\(codeB)-\(state.gameDate)",
                importance: .minor,
                kind: .economy,
                linkedActionIDs: [],
                notable: false,
                playerRelated: false,
                strategicEffects: [],
                title: "Trade Corridor: \(codeA) ↔ \(codeB)"
            )
            state.timeline.insert(tradeEvent, at: 0)
            break // one trade pact per turn
        }
    }

    /// Clamp a relationship delta into [-100, 100] and write it into both
    /// directions of the `relationshipScores` maps. Safe against missing keys.
    private static func applyRelationDelta(
        _ state: inout NativeCampaignState,
        from sourceCode: String,
        to targetCode: String,
        delta: Int
    ) {
        guard var source = state.aiCountryStates[sourceCode] else { return }
        let current = source.relationshipScores[targetCode] ?? 0
        source.relationshipScores[targetCode] = max(-100, min(100, current + delta))
        state.aiCountryStates[sourceCode] = source
    }

    /// Apply a small, clamped economic cost/benefit to a country's ledger as a
    /// consequence of an AI-vs-AI event (war spending, alliance readiness, etc).
    /// Creates a ledger entry so the effect is visible in the economics panel.
    private static func applyWarEconomicCost(
        state: inout NativeCampaignState,
        countryCode: String,
        months: Int,
        growthDelta: Double,
        debtDelta: Double,
        securityDelta: Double,
        ledgerRuleID: String,
        summary: String
    ) {
        guard var ledger = state.economicLedgers[countryCode] else { return }
        ledger.realGrowthPercent = clampDouble(ledger.realGrowthPercent + growthDelta * Double(months), -12, 16)
        ledger.publicDebtPercentGDP = clampDouble(ledger.publicDebtPercentGDP + debtDelta * Double(months), 1, 260)
        ledger.securityIndex = clampDouble(ledger.securityIndex + securityDelta * Double(months), 0, 100)

        let entry = NativeEconomicLedgerEntry(
            budgetBalanceDelta: 0.0,
            debtDelta: debtDelta * Double(months),
            eventID: "\(ledgerRuleID)-\(countryCode.lowercased())-\(state.gameDate)",
            fiscalSpaceDelta: 0,
            growthDelta: growthDelta * Double(months),
            id: "ledger-\(ledgerRuleID)-\(countryCode.lowercased())-\(state.gameDate)",
            inflationDelta: 0.0,
            ruleID: ledgerRuleID,
            summary: summary,
            tradeBalanceDelta: 0.0,
            turnDate: state.gameDate,
            securityDelta: securityDelta * Double(months),
            rebelDelta: 0
        )
        ledger.entries.insert(entry, at: 0)
        state.economicLedgers[countryCode] = ledger
    }

    /// Apply the compounding trade-pact benefit to a signatory: +trade balance
    /// and +growth, scaled by elapsed months and clamped. Smaller than a
    /// player-facing treaty so AI blocs grow rich slowly rather than overnight.
    private static func applyTradePactBenefit(
        state: inout NativeCampaignState,
        countryCode: String,
        partnerCode: String,
        months: Int
    ) {
        guard var ledger = state.economicLedgers[countryCode] else { return }
        let tradeBoost = 0.15 * Double(months)
        let growthBoost = 0.08 * Double(months)
        ledger.tradeBalancePercentGDP = clampDouble(ledger.tradeBalancePercentGDP + tradeBoost, -20, 20)
        ledger.realGrowthPercent = clampDouble(ledger.realGrowthPercent + growthBoost, -12, 16)

        let entry = NativeEconomicLedgerEntry(
            budgetBalanceDelta: 0.0,
            debtDelta: 0.0,
            eventID: "ai-trade-pact-\(countryCode.lowercased())-\(state.gameDate)",
            fiscalSpaceDelta: 0,
            growthDelta: growthBoost,
            id: "ledger-ai-trade-pact-\(countryCode.lowercased())-\(state.gameDate)",
            inflationDelta: 0.0,
            ruleID: "ai-trade-pact",
            summary: "Trade corridor with \(partnerCode) boosted commerce (+\(String(format: "%.2f", tradeBoost))% trade).",
            tradeBalanceDelta: tradeBoost,
            turnDate: state.gameDate,
            securityDelta: 0,
            rebelDelta: 0
        )
        ledger.entries.insert(entry, at: 0)
        state.economicLedgers[countryCode] = ledger
    }

    /// Evaluates alternative history event chains based on scenario ID, current date/round, and nation status.
    /// Autonomous AI countries resolve their candidate events without player interruption.
    /// When the player country is the executive target, `pendingEventDecision` is set, blocking turn advancement.
    static func evaluateAlternativeHistoryEvents(state: inout NativeCampaignState) {
        guard state.pendingEventDecision == nil else { return }

        // 1. Scenario: Soviet Triumph (1991 August Coup & OGAS Cybernetic Network)
        if state.scenarioID == "soviet-triumph" {
            if state.eventFlags["soviet_gkchp"] == nil, state.round >= 1 {
                let isPlayerTarget = (state.country.code == "RUS" || state.country.code == "SOV")
                let event = NativeCampaignEvent(
                    date: state.gameDate,
                    description: "In August 1991, the State Emergency Committee moved armor into Moscow to arrest radical reformists and secure union integrity. With sovereign central authority re-established, the Central Committee demands an immediate directive on economic planning and regional defense.",
                    id: "event-soviet-coup-1991",
                    importance: .severe,
                    kind: .crisis,
                    linkedActionIDs: [],
                    notable: true,
                    playerRelated: isPlayerTarget,
                    strategicEffects: [
                        NativeStrategicEffect(
                            date: state.gameDate,
                            eventId: "event-soviet-coup-1991",
                            id: "eff-gkchp-stability",
                            magnitude: 8,
                            summary: "Sovereign central authority stabilized across federal republics.",
                            target: isPlayerTarget ? state.country.code : "RUS",
                            track: .internalStability
                        )
                    ],
                    title: "GKChP State Emergency Committee Resolution",
                    imageAssetName: "EventSovietCoup",
                    decisionOptions: [
                        NativeEventDecisionOption(
                            id: "gkchp-hardline",
                            label: "Affirm Hardline Gosplan Centralization",
                            detail: "Re-nationalize decentralized trade corridors and commit state treasury to union heavy industry. [⟦ECO⟧ +5, ⟦SEC⟧ +10, ⟦MKT⟧ -10]",
                            effectTrack: .internalStability,
                            effectMagnitude: 10,
                            nextChainedEventID: "soviet-ogas-launch",
                            setFlag: "soviet_gkchp"
                        ),
                        NativeEventDecisionOption(
                            id: "gkchp-pragmatic",
                            label: "Cybernetic OGAS Network Modernization",
                            detail: "Deploy nationwide computerized resource balancing to automate planned quotas without market price shocks. [⟦ECO⟧ +8, ⟦STB⟧ +5]",
                            effectTrack: .economicResilience,
                            effectMagnitude: 8,
                            nextChainedEventID: "soviet-techno-bloc",
                            setFlag: "soviet_gkchp"
                        ),
                        NativeEventDecisionOption(
                            id: "gkchp-decentralized",
                            label: "Treaty of Sovereign Republics Compromise",
                            detail: "Grant fiscal autonomy to federal republics while maintaining common defense and energy grids. [⟦DIP⟧ +12, ⟦STB⟧ +4]",
                            effectTrack: .diplomaticLeverage,
                            effectMagnitude: 12,
                            nextChainedEventID: "soviet-miners-strike",
                            setFlag: "soviet_gkchp"
                        )
                    ]
                )

                if isPlayerTarget {
                    state.pendingEventDecision = event
                    state.eventFlags["soviet_gkchp"] = "pending"
                    return
                } else {
                    state.timeline.insert(event, at: 0)
                    state.eventFlags["soviet_gkchp"] = "gkchp-hardline"
                    state.eventFlags["next_chain"] = "soviet-ogas-launch"
                }
            } else if state.eventFlags["next_chain"] == "soviet-ogas-launch", state.eventFlags["soviet_ogas_resolved"] == nil {
                let isPlayerTarget = (state.country.code == "RUS" || state.country.code == "SOV")
                let event = NativeCampaignEvent(
                    date: state.gameDate,
                    description: "The All-Union Automated Information System (OGAS) links over 20,000 industrial manufacturing nodes into a real-time computerized resource-clearing grid, bypassing currency arbitrage.",
                    id: "event-soviet-ogas-1992",
                    importance: .major,
                    kind: .world,
                    linkedActionIDs: [],
                    notable: true,
                    playerRelated: isPlayerTarget,
                    strategicEffects: [
                        NativeStrategicEffect(
                            date: state.gameDate,
                            eventId: "event-soviet-ogas-1992",
                            id: "eff-ogas-econ",
                            magnitude: 6,
                            summary: "Automated logistics grid eliminates allocation bottlenecks.",
                            target: isPlayerTarget ? state.country.code : "RUS",
                            track: .economicResilience
                        )
                    ],
                    title: "OGAS Cybernetic Production Network Activated",
                    imageAssetName: "EventCyberBlackout",
                    decisionOptions: [
                        NativeEventDecisionOption(
                            id: "ogas-military",
                            label: "Direct Computing Quotas to Military Pacts",
                            detail: "Prioritize automated tank and avionics fabrication for Warsaw Pact modernization. [⟦MIL⟧ +15, ⟦TNS⟧ +8]",
                            effectTrack: .militaryReadiness,
                            effectMagnitude: 15,
                            nextChainedEventID: nil,
                            setFlag: "soviet_ogas_resolved"
                        ),
                        NativeEventDecisionOption(
                            id: "ogas-consumer",
                            label: "Consumer Goods & Agricultural Optimization",
                            detail: "Automate collective harvest storage and consumer goods distribution to end retail shortages. [⟦ECO⟧ +10, ⟦STB⟧ +8]",
                            effectTrack: .internalStability,
                            effectMagnitude: 8,
                            nextChainedEventID: nil,
                            setFlag: "soviet_ogas_resolved"
                        )
                    ]
                )

                if isPlayerTarget {
                    state.pendingEventDecision = event
                    state.eventFlags["soviet_ogas_resolved"] = "pending"
                    state.eventFlags.removeValue(forKey: "next_chain")
                    return
                } else {
                    state.timeline.insert(event, at: 0)
                    state.eventFlags["soviet_ogas_resolved"] = "ogas-military"
                    state.eventFlags.removeValue(forKey: "next_chain")
                }
            }
        }

        // 2. Scenario: Divided Sovereignty (1898 Fashoda Incident & Dreadnought Crisis)
        if state.scenarioID == "divided-sovereignty", state.eventFlags["fashoda_crisis"] == nil, state.round >= 1 {
            let isPlayerTarget = (state.country.code == "GBR" || state.country.code == "FRA")
            let event = NativeCampaignEvent(
                date: state.gameDate,
                description: "Major Marchand's French expeditionary force and General Kitchener's Anglo-Egyptian flotilla confront each other at the mud fort of Fashoda. Neither empire's officer corps is willing to withdraw without orders from the metropolis.",
                id: "event-fashoda-incident-1898",
                importance: .severe,
                kind: .crisis,
                linkedActionIDs: [],
                notable: true,
                playerRelated: isPlayerTarget,
                strategicEffects: [
                    NativeStrategicEffect(
                        date: state.gameDate,
                        eventId: "event-fashoda-incident-1898",
                        id: "eff-fashoda-tension",
                        magnitude: 14,
                        summary: "Imperial naval standoff elevates world tension.",
                        target: "GLOBAL",
                        track: .worldTension
                    )
                ],
                title: "Fashoda Confrontation on the Upper Nile",
                imageAssetName: "EventFashodaCrisis",
                decisionOptions: [
                    NativeEventDecisionOption(
                        id: "fashoda-ultimatum",
                        label: "Deliver Uncompromising Imperial Ultimatum",
                        detail: "Order total fleet mobilization in the English Channel and threaten immediate bombardment. [⟦TNS⟧ +20, ⟦MIL⟧ +10]",
                        effectTrack: .worldTension,
                        effectMagnitude: 20,
                        nextChainedEventID: "fashoda-channel-mobilization",
                        setFlag: "fashoda_crisis"
                    ),
                    NativeEventDecisionOption(
                        id: "fashoda-condominium",
                        label: "Negotiate Dual-Sovereignty Nile Condominium",
                        detail: "Divide trade navigation rights and establish joint garrisons along the Bahr-el-Ghazal watershed. [⟦DIP⟧ +15, ⟦TNS⟧ -10]",
                        effectTrack: .diplomaticLeverage,
                        effectMagnitude: 15,
                        nextChainedEventID: "fashoda-continental-league",
                        setFlag: "fashoda_crisis"
                    ),
                    NativeEventDecisionOption(
                        id: "fashoda-tactical-pivot",
                        label: "Discreet Tactical Withdrawal for European Leverage",
                        detail: "Cede the fort in exchange for diplomatic guarantees and recognition in North Africa. [⟦STB⟧ +6, ⟦DIP⟧ +8]",
                        effectTrack: .internalStability,
                        effectMagnitude: 6,
                        nextChainedEventID: "fashoda-dreadnought-panic",
                        setFlag: "fashoda_crisis"
                    )
                ]
            )

            if isPlayerTarget {
                state.pendingEventDecision = event
                state.eventFlags["fashoda_crisis"] = "pending"
                return
            } else {
                state.timeline.insert(event, at: 0)
                state.eventFlags["fashoda_crisis"] = "fashoda-condominium"
                state.eventFlags["next_chain"] = "fashoda-continental-league"
            }
        }

        // 3. Scenario: Fragmented Markets (Resource Crucible 2035)
        if state.scenarioID == "fragmented-markets", state.eventFlags["resource_crisis"] == nil, state.round >= 1 {
            let event = NativeCampaignEvent(
                date: state.gameDate,
                description: "Trans-border water tables have fallen below critical reserve volume. Militarized security details have established regional checkpoints along key agricultural trade corridors.",
                id: "event-resource-crisis-2035",
                importance: .severe,
                kind: .crisis,
                linkedActionIDs: [],
                notable: true,
                playerRelated: true,
                strategicEffects: [
                    NativeStrategicEffect(
                        date: state.gameDate,
                        eventId: "event-resource-crisis-2035",
                        id: "eff-res-market",
                        magnitude: -8,
                        summary: "Agricultural supply chain disruptions trigger food price inflation.",
                        target: state.country.code,
                        track: .marketConfidence
                    )
                ],
                title: "Strategic Aquifer Depletion & Logistics Checkpoints",
                imageAssetName: "EventResourceCrisis",
                decisionOptions: [
                    NativeEventDecisionOption(
                        id: "res-rationing",
                        label: "Enforce Federal Strategic Water Rationing",
                        detail: "Nationalize agricultural irrigation conduits and prioritize civilian grain basins. [⟦STB⟧ +8, ⟦ECO⟧ -4]",
                        effectTrack: .internalStability,
                        effectMagnitude: 8,
                        nextChainedEventID: "resource-fertilizer-crisis",
                        setFlag: "resource_crisis"
                    ),
                    NativeEventDecisionOption(
                        id: "res-desalination",
                        label: "Crash Desalination & Solar Pipeline Subsidies",
                        detail: "Authorize emergency capital bonds to construct coastal desalination infrastructure. [⟦ECO⟧ +10, ⟦MKT⟧ +6]",
                        effectTrack: .economicResilience,
                        effectMagnitude: 10,
                        nextChainedEventID: nil,
                        setFlag: "resource_crisis"
                    )
                ]
            )

            state.pendingEventDecision = event
            state.eventFlags["resource_crisis"] = "pending"
            return
        }

        // 4. Scenario: Pax Cybernetica (2055 Digital Blackout)
        if state.scenarioID == "pax-cybernetica", state.eventFlags["cyber_blackout"] == nil, state.round >= 1 {
            let event = NativeCampaignEvent(
                date: state.gameDate,
                description: "A coordinated zero-day cyberstrike desynchronizes subsea data links and algorithmic trading nodes across key industrial sectors, causing nationwide market turbulence.",
                id: "event-cyber-blackout-2055",
                importance: .severe,
                kind: .crisis,
                linkedActionIDs: [],
                notable: true,
                playerRelated: true,
                strategicEffects: [
                    NativeStrategicEffect(
                        date: state.gameDate,
                        eventId: "event-cyber-blackout-2055",
                        id: "eff-cyber-resilience",
                        magnitude: -10,
                        summary: "Algorithmic infrastructure desynchronization stalls trade settlements.",
                        target: state.country.code,
                        track: .marketConfidence
                    )
                ],
                title: "Subsea Cable Severance & Digital Blackout",
                imageAssetName: "EventCyberBlackout",
                decisionOptions: [
                    NativeEventDecisionOption(
                        id: "cyber-airgap",
                        label: "Air-Gap Sovereign Industrial Grids",
                        detail: "Sever external network bridges and revert critical infrastructure to localized manual protocols. [⟦SEC⟧ +15, ⟦MKT⟧ -12]",
                        effectTrack: .securityAnxiety,
                        effectMagnitude: 15,
                        nextChainedEventID: "cyber-microgrid-secession",
                        setFlag: "cyber_blackout"
                    ),
                    NativeEventDecisionOption(
                        id: "cyber-quantum",
                        label: "Deploy Quantum Encryption Safeguards",
                        detail: "Infuse emergency capital into defense quantum key distribution networks. [⟦ECO⟧ +6, ⟦STB⟧ +8]",
                        effectTrack: .economicResilience,
                        effectMagnitude: 8,
                        nextChainedEventID: nil,
                        setFlag: "cyber_blackout"
                    )
                ]
            )

            state.pendingEventDecision = event
            state.eventFlags["cyber_blackout"] = "pending"
            return
        }

        // 5. Scenario: Solarpunk Dawn (2060 Bioregional Assembly)
        if state.scenarioID == "solarpunk-dawn", state.eventFlags["solarpunk_dawn"] == nil, state.round >= 1 {
            let event = NativeCampaignEvent(
                date: state.gameDate,
                description: "Citizen communes and bioregional councils assemble to inaugurate decentralized microgrids and ecological watershed restoration pacts.",
                id: "event-solarpunk-assembly-2060",
                importance: .major,
                kind: .world,
                linkedActionIDs: [],
                notable: true,
                playerRelated: true,
                strategicEffects: [
                    NativeStrategicEffect(
                        date: state.gameDate,
                        eventId: "event-solarpunk-assembly-2060",
                        id: "eff-solarpunk-stb",
                        magnitude: 10,
                        summary: "Bioregional assembly consensus strengthens social trust.",
                        target: state.country.code,
                        track: .internalStability
                    )
                ],
                title: "Bioregional Assembly & Ecological Pact Ratification",
                imageAssetName: "EventSolarpunkDawn",
                decisionOptions: [
                    NativeEventDecisionOption(
                        id: "solar-commons",
                        label: "Codify Bioregional Energy Commons",
                        detail: "Guarantee universal free solar access and community-governed storage arrays. [⟦STB⟧ +12, ⟦ECO⟧ +6]",
                        effectTrack: .internalStability,
                        effectMagnitude: 12,
                        nextChainedEventID: nil,
                        setFlag: "solarpunk_dawn"
                    ),
                    NativeEventDecisionOption(
                        id: "solar-diplomacy",
                        label: "Global Climatic Technology Transfer",
                        detail: "Export carbon-negative modular housing and drought-resistant polyculture crops. [⟦DIP⟧ +16, ⟦TNS⟧ -12]",
                        effectTrack: .diplomaticLeverage,
                        effectMagnitude: 16,
                        nextChainedEventID: nil,
                        setFlag: "solarpunk_dawn"
                    )
                ]
            )

            state.pendingEventDecision = event
            state.eventFlags["solarpunk_dawn"] = "pending"
            return
        }

        // 6. Dynamic Crisis: Bread Riots & General Strike (when stability collapses < 35 in any scenario)
        if state.stability < 35, state.eventFlags["bread_riots"] == nil {
            let event = NativeCampaignEvent(
                date: state.gameDate,
                description: "Severe inflation and declining living conditions have sparked widespread strikes and violent bread riots across industrial centers. Garrisons stand by awaiting political command.",
                id: "event-bread-riots-dynamic",
                importance: .severe,
                kind: .crisis,
                linkedActionIDs: [],
                notable: true,
                playerRelated: true,
                strategicEffects: [
                    NativeStrategicEffect(
                        date: state.gameDate,
                        eventId: "event-bread-riots-dynamic",
                        id: "eff-bread-riots-stb",
                        magnitude: -12,
                        summary: "Urban unrest collapses domestic stability.",
                        target: state.country.code,
                        track: .internalStability
                    )
                ],
                title: "General Strike & Bread Riots in Capital Regions",
                imageAssetName: "EventBreadRiots",
                decisionOptions: [
                    NativeEventDecisionOption(
                        id: "bread-subsidies",
                        label: "Open Strategic Grain Reserves & Subsidize Loaves",
                        detail: "Drain state emergency reserves to provide price ceilings on staple food. [⟦STB⟧ +14, ⟦ECO⟧ -10]",
                        effectTrack: .internalStability,
                        effectMagnitude: 14,
                        nextChainedEventID: nil,
                        setFlag: "bread_riots"
                    ),
                    NativeEventDecisionOption(
                        id: "bread-crackdown",
                        label: "Deploy Military Police to Clear Distribution Hubs",
                        detail: "Enforce curfew and arrest strike organizers to resume port logistics. [⟦SEC⟧ +12, ⟦STB⟧ -6]",
                        effectTrack: .securityAnxiety,
                        effectMagnitude: 12,
                        nextChainedEventID: nil,
                        setFlag: "bread_riots"
                    )
                ]
            )

            state.pendingEventDecision = event
            state.eventFlags["bread_riots"] = "pending"
            return
        }

        // 7. Dynamic Catalog Event Integration (500-Event Scenario Catalog & 196-Country Event Trees)
        if state.pendingEventDecision == nil {
            // If an active chain points to an AI-targeted catalog event, resolve it autonomously in the world timeline first
            if let nextChain = state.eventFlags["next_chain"],
               !nextChain.isEmpty,
               state.eventFlags[nextChain] == nil,
               var aiChained = NativeAlternativeHistoryCatalog.event(byId: nextChain)
            {
                let target = aiChained.strategicEffects.first?.target ?? "GLOBAL"
                let targetsPlayer = (target == state.country.code || target == state.country.name || target == "GLOBAL")
                if !targetsPlayer {
                    aiChained.date = state.gameDate
                    aiChained.playerRelated = false
                    state.timeline.insert(aiChained, at: 0)
                    state.eventFlags[aiChained.id] = "ai_resolved"
                    if let followUp = aiChained.decisionOptions?.first?.nextChainedEventID, !followUp.isEmpty {
                        state.eventFlags["next_chain"] = followUp
                    } else {
                        state.eventFlags.removeValue(forKey: "next_chain")
                    }
                }
            }

            let candidates = NativeAlternativeHistoryCatalog.candidateDecisions(state: state)
            if var selected = candidates.first {
                selected.date = state.gameDate
                selected.strategicEffects = selected.strategicEffects.map { eff in
                    var copy = eff
                    copy.date = state.gameDate
                    return copy
                }
                if state.eventFlags["next_chain"] == selected.id {
                    state.eventFlags.removeValue(forKey: "next_chain")
                }
                let target = selected.strategicEffects.first?.target ?? "GLOBAL"
                let isPlayerTarget = (target == state.country.code || target == state.country.name || target == "GLOBAL")
                if isPlayerTarget {
                    state.pendingEventDecision = selected
                    state.eventFlags[selected.id] = "pending"
                    return
                } else {
                    state.timeline.insert(selected, at: 0)
                    state.eventFlags[selected.id] = "ai_resolved"
                    if let next = selected.decisionOptions?.first?.nextChainedEventID, !next.isEmpty {
                        state.eventFlags["next_chain"] = next
                    } else {
                        state.eventFlags.removeValue(forKey: "next_chain")
                    }
                }
            }
        }
    }

    /// Earned rival-campaign progress, capped by current scenario readiness.
    /// This meter starts at zero for new and migrated campaigns and advances
    /// only when a fully-ready AI completes a real multi-turn agenda.
    static func aiVictoryProgress(forCode code: String, in state: NativeCampaignState) -> Double {
        guard let aiState = state.aiCountryStates[code] else { return 0 }
        return min(
            max(0, min(100, aiState.rivalCampaignProgress)),
            aiVictoryReadiness(forCode: code, in: state)
        )
    }

    /// Scenario-aligned 0-100 readiness snapshot. AI countries do not carry
    /// the player's single stability field, so public security is their
    /// stability proxy; every other component mirrors the active scenario's
    /// visible objective contract. Actors without canonical map regions cannot
    /// enter the rival race.
    static func aiVictoryReadiness(forCode code: String, in state: NativeCampaignState) -> Double {
        guard isCanonicalRivalRepresentative(forCode: code, in: state), let ledger = state.economicLedgers[code] else { return 0 }
        let canonicalCode = GeopoliticalMapData.canonicalCountryCode(code)
        let coreRegions = GeopoliticalMapData.regions(forCountryCode: canonicalCode)
        guard !coreRegions.isEmpty else { return 0 }
        let coreRegionCount = coreRegions.count
        let occupiedCoreCount = state.regionOccupations.filter { regionID, controllerCode in
            let originalCode = GeopoliticalMapData.regionByID[regionID]?.countryCode ?? ""
            return GeopoliticalMapData.canonicalCountryCode(originalCode) == canonicalCode &&
                GeopoliticalMapData.canonicalCountryCode(controllerCode) != canonicalCode
        }.count
        let occupiedRivals = state.regionOccupations.filter { key, val in
            guard GeopoliticalMapData.canonicalCountryCode(val) == canonicalCode else { return false }
            let reg = GeopoliticalMapData.regionByID[key]
            let originalCode = GeopoliticalMapData.canonicalCountryCode(reg?.countryCode ?? "")
            return !originalCode.isEmpty && originalCode != canonicalCode
        }.count

        let stability = risingVictoryProgress(ledger.securityIndex, target: 80)
        let components: [Double] = switch state.scenarioID {
        case "default":
            [
                stability,
                rangedVictoryProgress(ledger.tradeBalancePercentGDP, floor: -20, target: 0),
                risingVictoryProgress(Double(coreRegionCount - occupiedCoreCount), target: Double(coreRegionCount))
            ]
        case "fragmented-markets":
            [
                risingVictoryProgress(ledger.securityIndex, target: 75),
                risingVictoryProgress(ledger.nominalGDPTrillions, target: 15),
                risingVictoryProgress(Double(ledger.fiscalSpaceIndex), target: 60)
            ]
        case "resilience-decade":
            [
                stability,
                risingVictoryProgress(ledger.securityIndex, target: 85),
                fallingVictoryProgress(ledger.rebelControlPercent, target: 5)
            ]
        case "soviet-triumph":
            [
                stability,
                risingVictoryProgress(Double(state.worldTension), target: 80),
                risingVictoryProgress(Double(occupiedRivals), target: 2)
            ]
        case "pax-cybernetica":
            [
                risingVictoryProgress(ledger.securityIndex, target: 85),
                risingVictoryProgress(ledger.nominalGDPTrillions, target: 25),
                rangedVictoryProgress(ledger.tradeBalancePercentGDP, floor: -20, target: 2)
            ]
        case "solarpunk-dawn":
            [
                risingVictoryProgress(ledger.securityIndex, target: 85),
                fallingVictoryProgress(ledger.rebelControlPercent, target: 0.1),
                risingVictoryProgress(ledger.securityIndex, target: 80)
            ]
        default:
            [
                risingVictoryProgress(ledger.securityIndex, target: 85),
                risingVictoryProgress(ledger.securityIndex, target: 70),
                risingVictoryProgress(Double(100 - state.worldTension), target: 31)
            ]
        }

        return components.reduce(0, +) / Double(components.count) * 100
    }

    /// Country catalogs and map geometry use a few aliases (for example,
    /// XXK/KOS and PSE/PSX). Only one state may enter the victory race for each
    /// canonical actor, preferring the canonical geometry code when present.
    static func isCanonicalRivalRepresentative(forCode code: String, in state: NativeCampaignState) -> Bool {
        let canonicalCode = GeopoliticalMapData.canonicalCountryCode(code)
        let playerCode = GeopoliticalMapData.canonicalCountryCode(state.country.code)
        guard !canonicalCode.isEmpty, canonicalCode != "GLOBAL", canonicalCode != playerCode else { return false }

        let matchingCodes = state.aiCountryStates.keys.filter {
            GeopoliticalMapData.canonicalCountryCode($0) == canonicalCode
        }
        guard !matchingCodes.isEmpty else { return false }
        let representative = matchingCodes.min { lhs, rhs in
            if lhs == canonicalCode {
                return true
            }
            if rhs == canonicalCode {
                return false
            }
            return lhs < rhs
        }
        return representative == code
    }

    private static func risingVictoryProgress(_ value: Double, target: Double) -> Double {
        guard target > 0 else { return value >= target ? 1 : 0 }
        return max(0, min(1, value / target))
    }

    private static func rangedVictoryProgress(_ value: Double, floor: Double, target: Double) -> Double {
        guard target > floor else { return value >= target ? 1 : 0 }
        return max(0, min(1, (value - floor) / (target - floor)))
    }

    private static func fallingVictoryProgress(_ value: Double, target: Double) -> Double {
        let ceiling = 100.0
        guard target < ceiling else { return value <= target ? 1 : 0 }
        return max(0, min(1, (ceiling - value) / (ceiling - target)))
    }
}

private struct SimpleRNG {
    private var state: UInt64

    init(seedString: String) {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for char in seedString.utf8 {
            hash ^= UInt64(char)
            hash = hash.addingReportingOverflow(hash &* 1_099_511_628_211).0
        }
        state = hash
    }

    mutating func nextDouble() -> Double {
        state = state.addingReportingOverflow(0x9E37_79B9_7F4A_7C15).0
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return Double(z ^ (z >> 31)) / Double(UInt64.max)
    }
}

private extension Double {
    var percent: String {
        String(format: "%.1f%%", self)
    }

    var signedPercent: String {
        String(format: "%+.2f%%", self)
    }
}
