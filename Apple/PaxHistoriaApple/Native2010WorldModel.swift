import Foundation

enum Native2010SignalLevel: String, Codable, Hashable {
    case low
    case medium
    case high
    case watch
}

enum Native2010Relation: String, Codable, Hashable {
    case ally
    case neutral
    case partner
    case rival
    case watch
}

enum EconomicDirection: Hashable {
    case up, down
}

struct Native2010CountryProfile: Codable, Hashable {
    let code: String
    let nominalGDPTrillions: Double
    let gdpGrowthPercent: Double
    let stability: Int
    let influence: Int
    let techLevel: Double
    let energySecurity: Int
    let foodSecurity: Int
    let nuclearStatus: String
    let publicSupport: Int
    let neutralOpinion: Int
    let inflationPercent: Double
    let tradeBalancePercent: Double
    let energyDependencePercent: Int
    let sanctionsExposurePercent: Int
    let historicalBrief: String
    let militarySpendingPercent: Double
    let corruptionIndex: Int
}

struct Native2010Alignment: Identifiable, Hashable {
    var id: String {
        name
    }

    let name: String
    let stance: String
    let score: Int
    let relation: Native2010Relation
}

struct Native2010RiskSignal: Identifiable, Hashable {
    var id: String {
        name
    }

    let name: String
    let intensity: String
    let level: Native2010SignalLevel
}

struct Native2010Commitment: Identifiable, Hashable {
    var id: String {
        name
    }

    let name: String
    let countLabel: String
    let status: String
    let level: Native2010SignalLevel
}

struct Native2010EconomicPressure: Identifiable, Hashable {
    var id: String {
        name
    }

    let name: String
    let value: String
    let direction: EconomicDirection
    let level: Native2010SignalLevel
}

struct Native2010PublicOpinion: Hashable {
    let support: Int
    let neutral: Int
    var oppose: Int {
        max(0, 100 - support - neutral)
    }
}

struct Native2010MapSector: Identifiable, Hashable {
    var id: String {
        code
    }

    let name: String
    let code: String
    let latitude: Double
    let longitude: Double
    let stability: Int
    let relation: Native2010Relation
}

/// Real 2010 opening baseline used by the native campaign.
///
/// Data in this file is intentionally static and compact: it gives the game a
/// historically anchored start state, then later turns become alternate-history
/// simulation driven by player actions, validated events, and ledger effects.
enum Native2010WorldModel {
    static let historicalStartDate = "2010-01-01"
    static let openingGameDate = "2010-01-15"
    static let canonNotice = "Real public history is authoritative through 2010-01-01; every later turn is an alternate-history simulation."

    static let unavailableAtStart = Set(["SSD"])

    private static let fallbackProfile = Native2010CountryProfile(
        code: "GLOBAL",
        nominalGDPTrillions: 66.20,
        gdpGrowthPercent: 4.3,
        stability: 58,
        influence: 100,
        techLevel: 3.5,
        energySecurity: 60,
        foodSecurity: 65,
        nuclearStatus: "No arsenal",
        publicSupport: 58,
        neutralOpinion: 50,
        inflationPercent: 3.5,
        tradeBalancePercent: 0.0,
        energyDependencePercent: 0,
        sanctionsExposurePercent: 0,
        historicalBrief: "The global system enters 2010 inside the real post-financial-crisis international order, with institutions absorbing uneven recovery.",
        militarySpendingPercent: 2.0,
        corruptionIndex: 50
    )

    private static let profiles: [String: Native2010CountryProfile] = [
        "USA": Native2010CountryProfile(code: "USA", nominalGDPTrillions: 14.99, gdpGrowthPercent: 2.6, stability: 64, influence: 88, techLevel: 5.0, energySecurity: 73, foodSecurity: 90, nuclearStatus: "NPT nuclear", publicSupport: 53, neutralOpinion: 25, inflationPercent: 1.6, tradeBalancePercent: -3.0, energyDependencePercent: 24, sanctionsExposurePercent: 6, historicalBrief: "The United States opens 2010 in recovery from the financial crisis, with major commitments in Afghanistan and Iraq, high diplomatic reach, and polarized domestic confidence.", militarySpendingPercent: 4.7, corruptionIndex: 25),
        "CHN": Native2010CountryProfile(code: "CHN", nominalGDPTrillions: 6.09, gdpGrowthPercent: 10.6, stability: 70, influence: 72, techLevel: 4.2, energySecurity: 61, foodSecurity: 76, nuclearStatus: "NPT nuclear", publicSupport: 72, neutralOpinion: 18, inflationPercent: 3.3, tradeBalancePercent: 3.9, energyDependencePercent: 55, sanctionsExposurePercent: 7, historicalBrief: "China enters 2010 with rapid growth after stimulus, rising trade weight, growing energy demand, and a more visible role in regional diplomacy.", militarySpendingPercent: 1.9, corruptionIndex: 65),
        "BRA": Native2010CountryProfile(code: "BRA", nominalGDPTrillions: 2.21, gdpGrowthPercent: 7.5, stability: 68, influence: 52, techLevel: 3.2, energySecurity: 82, foodSecurity: 86, nuclearStatus: "No arsenal", publicSupport: 72, neutralOpinion: 18, inflationPercent: 5.0, tradeBalancePercent: -2.1, energyDependencePercent: 16, sanctionsExposurePercent: 2, historicalBrief: "Brazil begins 2010 with strong post-crisis growth, expanding commodity and energy leverage, active South American diplomacy, and high public optimism.", militarySpendingPercent: 1.5, corruptionIndex: 60),
        "DEU": Native2010CountryProfile(code: "DEU", nominalGDPTrillions: 3.40, gdpGrowthPercent: 4.2, stability: 73, influence: 67, techLevel: 4.6, energySecurity: 63, foodSecurity: 82, nuclearStatus: "No arsenal", publicSupport: 61, neutralOpinion: 25, inflationPercent: 1.1, tradeBalancePercent: 5.6, energyDependencePercent: 61, sanctionsExposurePercent: 5, historicalBrief: "Germany opens 2010 as the Eurozone's industrial anchor, balancing export recovery, energy import exposure, and leadership inside the European Union.", militarySpendingPercent: 1.3, corruptionIndex: 18),
        "JPN": Native2010CountryProfile(code: "JPN", nominalGDPTrillions: 5.70, gdpGrowthPercent: 4.2, stability: 69, influence: 63, techLevel: 4.8, energySecurity: 42, foodSecurity: 72, nuclearStatus: "No arsenal", publicSupport: 47, neutralOpinion: 34, inflationPercent: -0.7, tradeBalancePercent: 3.3, energyDependencePercent: 83, sanctionsExposurePercent: 4, historicalBrief: "Japan begins 2010 with advanced technology, deflation pressure, heavy energy import dependence, and close security ties with the United States.", militarySpendingPercent: 1.0, corruptionIndex: 20),
        "GBR": Native2010CountryProfile(code: "GBR", nominalGDPTrillions: 2.49, gdpGrowthPercent: 1.9, stability: 61, influence: 64, techLevel: 4.5, energySecurity: 58, foodSecurity: 79, nuclearStatus: "NPT nuclear", publicSupport: 50, neutralOpinion: 29, inflationPercent: 3.3, tradeBalancePercent: -2.2, energyDependencePercent: 37, sanctionsExposurePercent: 6, historicalBrief: "The United Kingdom enters 2010 after recession, with a coalition election year, financial-sector repair, NATO commitments, and continuing global diplomatic reach.", militarySpendingPercent: 2.4, corruptionIndex: 20),
        "FRA": Native2010CountryProfile(code: "FRA", nominalGDPTrillions: 2.65, gdpGrowthPercent: 2.0, stability: 64, influence: 64, techLevel: 4.4, energySecurity: 76, foodSecurity: 83, nuclearStatus: "NPT nuclear", publicSupport: 49, neutralOpinion: 30, inflationPercent: 1.5, tradeBalancePercent: -1.7, energyDependencePercent: 48, sanctionsExposurePercent: 5, historicalBrief: "France opens 2010 with Eurozone influence, a large nuclear-electricity base, active diplomacy, and public pressure from post-crisis employment concerns.", militarySpendingPercent: 2.2, corruptionIndex: 22),
        "IND": Native2010CountryProfile(code: "IND", nominalGDPTrillions: 1.71, gdpGrowthPercent: 8.5, stability: 60, influence: 55, techLevel: 3.5, energySecurity: 48, foodSecurity: 67, nuclearStatus: "Nuclear outside NPT", publicSupport: 62, neutralOpinion: 23, inflationPercent: 9.5, tradeBalancePercent: -2.8, energyDependencePercent: 44, sanctionsExposurePercent: 5, historicalBrief: "India begins 2010 with fast growth, inflation pressure, rising technology capacity, and a complex security and diplomacy environment across South Asia.", militarySpendingPercent: 2.7, corruptionIndex: 67),
        "RUS": Native2010CountryProfile(code: "RUS", nominalGDPTrillions: 1.52, gdpGrowthPercent: 4.5, stability: 62, influence: 63, techLevel: 3.9, energySecurity: 86, foodSecurity: 70, nuclearStatus: "NPT nuclear", publicSupport: 60, neutralOpinion: 24, inflationPercent: 6.9, tradeBalancePercent: 4.8, energyDependencePercent: 12, sanctionsExposurePercent: 8, historicalBrief: "Russia opens 2010 with energy-export leverage, nuclear parity, cautious reset diplomacy with the United States, and regional-security influence.", militarySpendingPercent: 3.7, corruptionIndex: 78),
        "ZAF": Native2010CountryProfile(code: "ZAF", nominalGDPTrillions: 0.42, gdpGrowthPercent: 3.0, stability: 54, influence: 42, techLevel: 3.0, energySecurity: 50, foodSecurity: 64, nuclearStatus: "No arsenal", publicSupport: 57, neutralOpinion: 25, inflationPercent: 4.3, tradeBalancePercent: -2.0, energyDependencePercent: 35, sanctionsExposurePercent: 3, historicalBrief: "South Africa begins 2010 with World Cup visibility, regional influence, infrastructure strain, and post-crisis employment pressure.", militarySpendingPercent: 1.2, corruptionIndex: 55),
        "AUS": Native2010CountryProfile(code: "AUS", nominalGDPTrillions: 1.15, gdpGrowthPercent: 2.1, stability: 76, influence: 44, techLevel: 4.0, energySecurity: 78, foodSecurity: 88, nuclearStatus: "No arsenal", publicSupport: 60, neutralOpinion: 27, inflationPercent: 2.9, tradeBalancePercent: -2.6, energyDependencePercent: 18, sanctionsExposurePercent: 3, historicalBrief: "Australia enters 2010 with stable institutions, commodity demand from Asia, alliance ties with the United States, and climate-policy tension.", militarySpendingPercent: 1.8, corruptionIndex: 12),
        "ITA": Native2010CountryProfile(code: "ITA", nominalGDPTrillions: 2.13, gdpGrowthPercent: 1.7, stability: 62, influence: 58, techLevel: 4.3, energySecurity: 45, foodSecurity: 82, nuclearStatus: "No arsenal", publicSupport: 52, neutralOpinion: 26, inflationPercent: 1.6, tradeBalancePercent: -1.9, energyDependencePercent: 82, sanctionsExposurePercent: 4, historicalBrief: "Italy enters 2010 managing sovereign debt constraints, Eurozone integration, industrial capacity in the north, and regional Mediterranean diplomacy.", militarySpendingPercent: 1.4, corruptionIndex: 45),
        "CAN": Native2010CountryProfile(code: "CAN", nominalGDPTrillions: 1.61, gdpGrowthPercent: 3.1, stability: 80, influence: 50, techLevel: 4.4, energySecurity: 88, foodSecurity: 92, nuclearStatus: "No arsenal", publicSupport: 62, neutralOpinion: 24, inflationPercent: 1.8, tradeBalancePercent: -1.5, energyDependencePercent: 10, sanctionsExposurePercent: 2, historicalBrief: "Canada begins 2010 with resilient financial institutions, high commodity exports, Arctic sovereignty discussions, and close integration with North American supply chains.", militarySpendingPercent: 1.4, corruptionIndex: 11),
        "MEX": Native2010CountryProfile(code: "MEX", nominalGDPTrillions: 1.05, gdpGrowthPercent: 5.1, stability: 56, influence: 42, techLevel: 3.1, energySecurity: 70, foodSecurity: 75, nuclearStatus: "No arsenal", publicSupport: 55, neutralOpinion: 25, inflationPercent: 4.2, tradeBalancePercent: -0.8, energyDependencePercent: 22, sanctionsExposurePercent: 3, historicalBrief: "Mexico enters 2010 rebounding strongly from the global trade contraction, expanding manufacturing exports, managing internal security challenges, and deepening regional trade ties.", militarySpendingPercent: 0.5, corruptionIndex: 69),
        "KOR": Native2010CountryProfile(code: "KOR", nominalGDPTrillions: 1.14, gdpGrowthPercent: 6.8, stability: 72, influence: 54, techLevel: 4.7, energySecurity: 32, foodSecurity: 65, nuclearStatus: "No arsenal", publicSupport: 58, neutralOpinion: 22, inflationPercent: 2.9, tradeBalancePercent: 4.0, energyDependencePercent: 86, sanctionsExposurePercent: 6, historicalBrief: "South Korea opens 2010 with vigorous export recovery led by electronics and shipbuilding, high technology capacity, and active security vigilance across the Korean Peninsula.", militarySpendingPercent: 2.6, corruptionIndex: 29),
        "ESP": Native2010CountryProfile(code: "ESP", nominalGDPTrillions: 1.42, gdpGrowthPercent: -0.2, stability: 60, influence: 48, techLevel: 4.1, energySecurity: 42, foodSecurity: 80, nuclearStatus: "No arsenal", publicSupport: 48, neutralOpinion: 28, inflationPercent: 1.8, tradeBalancePercent: -4.5, energyDependencePercent: 78, sanctionsExposurePercent: 3, historicalBrief: "Spain enters 2010 working through the aftermath of the property contraction, restructuring banking networks, and expanding renewable energy capacity across the peninsula.", militarySpendingPercent: 1.2, corruptionIndex: 30),
        "TUR": Native2010CountryProfile(code: "TUR", nominalGDPTrillions: 0.77, gdpGrowthPercent: 8.5, stability: 58, influence: 52, techLevel: 3.4, energySecurity: 40, foodSecurity: 74, nuclearStatus: "No arsenal", publicSupport: 60, neutralOpinion: 22, inflationPercent: 8.6, tradeBalancePercent: -5.8, energyDependencePercent: 72, sanctionsExposurePercent: 4, historicalBrief: "Turkey begins 2010 with rapid industrial growth, transit corridor leverage connecting Europe and the Middle East, active regional diplomacy, and inflation management.", militarySpendingPercent: 2.3, corruptionIndex: 56),
        "SAU": Native2010CountryProfile(code: "SAU", nominalGDPTrillions: 0.53, gdpGrowthPercent: 5.0, stability: 68, influence: 58, techLevel: 3.3, energySecurity: 98, foodSecurity: 35, nuclearStatus: "No arsenal", publicSupport: 65, neutralOpinion: 20, inflationPercent: 5.3, tradeBalancePercent: 18.2, energyDependencePercent: 0, sanctionsExposurePercent: 4, historicalBrief: "Saudi Arabia opens 2010 with dominant hydrocarbon export capacity, strong fiscal reserves, active Gulf diplomacy, and early industrial diversification initiatives.", militarySpendingPercent: 8.6, corruptionIndex: 53),
        "ARG": Native2010CountryProfile(code: "ARG", nominalGDPTrillions: 0.46, gdpGrowthPercent: 10.1, stability: 55, influence: 40, techLevel: 3.2, energySecurity: 68, foodSecurity: 88, nuclearStatus: "No arsenal", publicSupport: 54, neutralOpinion: 25, inflationPercent: 10.5, tradeBalancePercent: 2.5, energyDependencePercent: 14, sanctionsExposurePercent: 5, historicalBrief: "Argentina enters 2010 with strong agricultural commodity export demand, industrial expansion, active Mercosur coordination, and fiscal debt negotiations.", militarySpendingPercent: 0.8, corruptionIndex: 71),
        "POL": Native2010CountryProfile(code: "POL", nominalGDPTrillions: 0.48, gdpGrowthPercent: 3.6, stability: 69, influence: 44, techLevel: 3.8, energySecurity: 65, foodSecurity: 78, nuclearStatus: "No arsenal", publicSupport: 56, neutralOpinion: 26, inflationPercent: 2.6, tradeBalancePercent: -1.8, energyDependencePercent: 32, sanctionsExposurePercent: 4, historicalBrief: "Poland opens 2010 as one of the few European economies avoiding outright recession, expanding domestic manufacturing, and strengthening regional Eastern European integration.", militarySpendingPercent: 1.8, corruptionIndex: 47)
    ]

    static func isReal2010Scenario(_ scenario: NativeScenario) -> Bool {
        scenario.startDate == historicalStartDate && scenario.gameDate.hasPrefix("2010-")
    }

    static func isSelectableCountryCode(_ code: String) -> Bool {
        !unavailableAtStart.contains(code)
    }

    static func profile(for country: PlayerCountry) -> Native2010CountryProfile {
        if let existing = profiles[country.code] {
            return existing
        }
        return generateDynamicProfile(for: country)
    }

    private static func generateDynamicProfile(for country: PlayerCountry) -> Native2010CountryProfile {
        let code = country.code.uppercased()
        let hash = NativeGameEngine.fnv1aHash("2010-profile-\(code)")
        let gdpSeed = Double((hash >> 16) & 0xFF) / 255.0
        let stabilitySeed = Double((hash >> 8) & 0xFF) / 255.0
        let techSeed = Double(hash & 0xFF) / 255.0

        let nominalGDP = max(0.04, Double(round((0.08 + gdpSeed * 0.45) * 100) / 100))
        let growth = Double(round((1.5 + gdpSeed * 4.5) * 10) / 10)
        let stability = clamp(48 + Int(stabilitySeed * 30), 40, 82)
        let influence = clamp(25 + Int(gdpSeed * 25), 20, 60)
        let techLevel = Double(round((2.4 + techSeed * 1.8) * 10) / 10)
        let energySec = clamp(40 + Int(gdpSeed * 40), 20, 85)
        let foodSec = clamp(45 + Int(stabilitySeed * 38), 25, 90)

        return Native2010CountryProfile(
            code: code,
            nominalGDPTrillions: nominalGDP,
            gdpGrowthPercent: growth,
            stability: stability,
            influence: influence,
            techLevel: techLevel,
            energySecurity: energySec,
            foodSecurity: foodSec,
            nuclearStatus: "No arsenal",
            publicSupport: clamp(50 + Int((stabilitySeed - 0.5) * 20), 40, 75),
            neutralOpinion: 25,
            inflationPercent: Double(round((2.0 + (1.0 - stabilitySeed) * 5.0) * 10) / 10),
            tradeBalancePercent: Double(round(((gdpSeed - 0.5) * 6.0) * 10) / 10),
            energyDependencePercent: clamp(30 + Int((1.0 - gdpSeed) * 50), 10, 85),
            sanctionsExposurePercent: clamp(Int((1.0 - stabilitySeed) * 8), 1, 10),
            historicalBrief: "\(country.name) opens 2010 balancing internal development priorities, regional diplomatic engagements, and international economic recovery.",
            militarySpendingPercent: Double(round((1.0 + gdpSeed * 1.5) * 10) / 10),
            corruptionIndex: clamp(30 + Int((1.0 - stabilitySeed) * 45), 15, 80)
        )
    }

    static func stability(for country: PlayerCountry, scenario: NativeScenario) -> Int {
        isReal2010Scenario(scenario) ? profile(for: country).stability : scenario.baseStability
    }

    static func worldTension(for country: PlayerCountry, scenario: NativeScenario) -> Int {
        guard isReal2010Scenario(scenario) else { return scenario.baseWorldTension }
        return min(72, max(32, scenario.baseWorldTension + (profile(for: country).sanctionsExposurePercent / 3)))
    }

    static func openingSummary(for country: PlayerCountry, language: NativeGameLanguage) -> String {
        let profile = profile(for: country)
        switch language {
        case .english:
            return "\(country.name) starts on 1 January 2010 inside the real post-crisis world order. \(profile.historicalBrief) \(canonNotice)"
        case .portuguese:
            return "\(country.name) começa em 1 de janeiro de 2010 dentro da ordem mundial real do pós-crise. \(profile.historicalBrief) A história pública real vale até 2010-01-01; depois disso, cada turno é simulação alternativa."
        case .spanish:
            return "\(country.name) comienza el 1 de enero de 2010 dentro del orden mundial real posterior a la crisis. \(profile.historicalBrief) La historia pública real vale hasta 2010-01-01; después, cada turno es una simulación alternativa."
        }
    }

    static func openingEventDescription(for country: PlayerCountry, language: NativeGameLanguage) -> String {
        let profile = profile(for: country)
        switch language {
        case .english:
            return "The campaign opens from a real 2010 baseline: GDP growth \(formatPercent(profile.gdpGrowthPercent)), inflation \(formatPercent(profile.inflationPercent)), and known diplomatic alignments are already on the table."
        case .portuguese:
            return "A campanha abre a partir de uma linha de base real de 2010: crescimento do PIB \(formatPercent(profile.gdpGrowthPercent)), inflação \(formatPercent(profile.inflationPercent)) e alinhamentos diplomáticos conhecidos já estão no tabuleiro."
        case .spanish:
            return "La campaña abre desde una línea base real de 2010: crecimiento del PIB \(formatPercent(profile.gdpGrowthPercent)), inflación \(formatPercent(profile.inflationPercent)) y alineamientos diplomáticos conocidos ya están sobre el tablero."
        }
    }

    static func openingEventTitle(for country: PlayerCountry, language: NativeGameLanguage) -> String {
        switch language {
        case .english: "\(country.name) enters the 2010 baseline"
        case .portuguese: "\(country.name) entra na linha de base de 2010"
        case .spanish: "\(country.name) entra en la línea base de 2010"
        }
    }

    static func openingEffectSummary(for language: NativeGameLanguage) -> String {
        switch language {
        case .english: "A real 2010 baseline gives the player concrete starting conditions instead of fictional blocs."
        case .portuguese: "Uma linha de base real de 2010 dá condições iniciais concretas ao jogador, não blocos fictícios."
        case .spanish: "Una línea base real de 2010 da condiciones iniciales concretas al jugador, no bloques ficticios."
        }
    }

    static func gdpMetric(for state: NativeCampaignState) -> (value: String, delta: String) {
        let ledger = state.economicLedger
        return (String(format: "$%.2fT", ledger.nominalGDPTrillions), String(format: "%+.1f%% ledger", ledger.realGrowthPercent))
    }

    static func influenceMetric(for state: NativeCampaignState) -> (value: String, delta: String) {
        let base = profile(for: state.country).influence
        let delta = max(-8, min(8, state.worldEffects.filter { $0.track == .diplomaticLeverage }.map(\.magnitude).reduce(0, +)))
        return ("\(max(0, min(100, base + delta)))", String(format: "%+d", delta))
    }

    static func techMetric(for state: NativeCampaignState) -> (value: String, delta: String) {
        let base = profile(for: state.country).techLevel
        let drift = Double(max(0, state.round - 1)) * 0.03
        return (String(format: "%.1f", min(5.0, base + drift)), String(format: "+%.1f", drift))
    }

    static func energyMetric(for state: NativeCampaignState) -> String {
        "\(clamp(profile(for: state.country).energySecurity + trackDelta(state, .economicResilience)))%"
    }

    static func foodMetric(for state: NativeCampaignState) -> String {
        "\(clamp(profile(for: state.country).foodSecurity + trackDelta(state, .internalStability) / 2))%"
    }

    static func nuclearMetric(for state: NativeCampaignState) -> String {
        profile(for: state.country).nuclearStatus
    }

    static func publicOpinion(for state: NativeCampaignState) -> Native2010PublicOpinion {
        let profile = profile(for: state.country)
        let support = clamp(profile.publicSupport + ((state.stability - profile.stability) / 2))
        return Native2010PublicOpinion(support: support, neutral: profile.neutralOpinion)
    }

    static func economicPressures(for state: NativeCampaignState) -> [Native2010EconomicPressure] {
        let ledger = state.economicLedger
        return [
            Native2010EconomicPressure(name: "Budget Balance", value: formatPercent(ledger.budgetBalancePercentGDP), direction: ledger.budgetBalancePercentGDP >= 0 ? .up : .down, level: ledger.budgetBalancePercentGDP <= -7 ? .high : (ledger.budgetBalancePercentGDP <= -3 ? .medium : .low)),
            Native2010EconomicPressure(name: "Public Debt", value: formatUnsignedPercent(ledger.publicDebtPercentGDP), direction: .up, level: ledger.publicDebtPercentGDP >= 110 ? .high : (ledger.publicDebtPercentGDP >= 70 ? .medium : .low)),
            Native2010EconomicPressure(name: "Inflation", value: formatUnsignedPercent(ledger.inflationPercent), direction: .up, level: ledger.inflationPercent >= 8 ? .high : (ledger.inflationPercent >= 4 ? .medium : .low)),
            Native2010EconomicPressure(name: "Trade Balance", value: formatPercent(ledger.tradeBalancePercentGDP), direction: ledger.tradeBalancePercentGDP >= 0 ? .up : .down, level: abs(ledger.tradeBalancePercentGDP) >= 4 ? .high : .medium),
            Native2010EconomicPressure(name: "Unemployment", value: formatUnsignedPercent(ledger.unemploymentPercent), direction: .up, level: ledger.unemploymentPercent >= 12 ? .high : (ledger.unemploymentPercent >= 7 ? .medium : .low))
        ]
    }

    static func alignments(for state: NativeCampaignState) -> [Native2010Alignment] {
        switch state.country.code {
        case "USA":
            [
                Native2010Alignment(name: "NATO", stance: "Ally", score: 82, relation: .ally),
                Native2010Alignment(name: "Japan Treaty", stance: "Ally", score: 76, relation: .ally),
                Native2010Alignment(name: "China", stance: "Competitor", score: 46, relation: .rival),
                Native2010Alignment(name: "Russia Reset", stance: "Watch", score: 52, relation: .watch)
            ]
        case "BRA":
            [
                Native2010Alignment(name: "Mercosur", stance: "Partner", score: 78, relation: .partner),
                Native2010Alignment(name: "UNASUR", stance: "Partner", score: 68, relation: .partner),
                Native2010Alignment(name: "United States", stance: "Partner", score: 61, relation: .partner),
                Native2010Alignment(name: "Venezuela", stance: "Watch", score: 48, relation: .watch)
            ]
        case "CHN":
            [
                Native2010Alignment(name: "Russia", stance: "Partner", score: 64, relation: .partner),
                Native2010Alignment(name: "ASEAN Trade", stance: "Partner", score: 58, relation: .partner),
                Native2010Alignment(name: "United States", stance: "Competitor", score: 47, relation: .rival),
                Native2010Alignment(name: "Japan", stance: "Watch", score: 43, relation: .watch)
            ]
        case "DEU", "FRA", "GBR":
            [
                Native2010Alignment(name: "European Union", stance: "Ally", score: 78, relation: .ally),
                Native2010Alignment(name: "NATO", stance: "Ally", score: 73, relation: .ally),
                Native2010Alignment(name: "Russia Energy", stance: "Watch", score: 49, relation: .watch),
                Native2010Alignment(name: "G20", stance: "Partner", score: 65, relation: .partner)
            ]
        default:
            [
                Native2010Alignment(name: "United Nations", stance: "Neutral", score: 55, relation: .neutral),
                Native2010Alignment(name: "G20 System", stance: "Partner", score: 58, relation: .partner),
                Native2010Alignment(name: "Regional Neighbors", stance: "Watch", score: 50, relation: .watch),
                Native2010Alignment(name: "Global Markets", stance: "Neutral", score: 52, relation: .neutral)
            ]
        }
    }

    static func riskSignals(for state: NativeCampaignState) -> [Native2010RiskSignal] {
        switch state.country.code {
        case "USA", "GBR", "FRA", "DEU":
            [
                Native2010RiskSignal(name: "Afghanistan War", intensity: "High", level: .high),
                Native2010RiskSignal(name: "Eurozone Debt Stress", intensity: "Medium", level: .medium),
                Native2010RiskSignal(name: "Iran Nuclear File", intensity: "Medium", level: .medium)
            ]
        case "BRA":
            [
                Native2010RiskSignal(name: "Haiti Stabilization Mission", intensity: "Medium", level: .medium),
                Native2010RiskSignal(name: "Commodity Price Volatility", intensity: "Medium", level: .medium),
                Native2010RiskSignal(name: "Amazon Infrastructure Pressure", intensity: "Low", level: .low)
            ]
        case "CHN", "JPN", "KOR":
            [
                Native2010RiskSignal(name: "Korean Peninsula", intensity: "High", level: .high),
                Native2010RiskSignal(name: "South China Sea Claims", intensity: "Medium", level: .medium),
                Native2010RiskSignal(name: "Export Demand Volatility", intensity: "Medium", level: .medium)
            ]
        default:
            [
                Native2010RiskSignal(name: "Global Recovery Fragility", intensity: "Medium", level: .medium),
                Native2010RiskSignal(name: "Energy Price Volatility", intensity: "Medium", level: .medium),
                Native2010RiskSignal(name: "Food Price Pressure", intensity: "Low", level: .low)
            ]
        }
    }

    static func commitments(for state: NativeCampaignState) -> [Native2010Commitment] {
        switch state.country.code {
        case "USA":
            [
                Native2010Commitment(name: "Afghanistan Commitment", countLabel: "NATO-led", status: "Active", level: .high),
                Native2010Commitment(name: "Iraq Drawdown", countLabel: "Transition", status: "Reducing", level: .medium),
                Native2010Commitment(name: "Korea Deterrence", countLabel: "Alliance", status: "Standing", level: .medium)
            ]
        case "BRA":
            [
                Native2010Commitment(name: "Haiti MINUSTAH Role", countLabel: "UN mission", status: "Active", level: .medium),
                Native2010Commitment(name: "Mercosur Mediation", countLabel: "Regional", status: "Engaged", level: .medium),
                Native2010Commitment(name: "Pre-salt Energy Buildout", countLabel: "Domestic", status: "Scaling", level: .low)
            ]
        default:
            [
                Native2010Commitment(name: "UN Diplomacy", countLabel: "Multilateral", status: "Active", level: .medium),
                Native2010Commitment(name: "Trade Corridor Watch", countLabel: "Economic", status: "Monitoring", level: .low),
                Native2010Commitment(name: "Energy Security Planning", countLabel: "Domestic", status: "Staging", level: .medium)
            ]
        }
    }

    static func mapSectors(for state: NativeCampaignState) -> [Native2010MapSector] {
        let entries: [(String, String, Double, Double)] = [
            ("United States", "USA", 37.0902, -95.7129),
            ("Brazil", "BRA", -14.2350, -51.9253),
            ("Germany", "DEU", 51.1657, 10.4515),
            ("Russia", "RUS", 61.5240, 105.3188),
            ("China", "CHN", 35.8617, 104.1954),
            ("India", "IND", 20.5937, 78.9629),
            ("Japan", "JPN", 36.2048, 138.2529),
            ("South Africa", "ZAF", -30.5595, 22.9375),
            ("Australia", "AUS", -25.2744, 133.7751)
        ]

        return entries.map { name, code, latitude, longitude in
            let country = PlayerCountry(code: code, name: name)
            return Native2010MapSector(
                name: name,
                code: code,
                latitude: latitude,
                longitude: longitude,
                stability: profile(for: country).stability,
                relation: relation(from: state.country.code, to: code)
            )
        }
    }

    static func promptContext(for state: NativeCampaignState) -> String {
        let profile = profile(for: state.country)
        let alignments = alignments(for: state)
            .prefix(4)
            .map { "\($0.name): \($0.stance) \($0.score)" }
            .joined(separator: "; ")
        let conflictSummary = state.regionConflicts.values
            .sorted { $0.regionID < $1.regionID }
            .prefix(6)
            .map { "\($0.regionID): \($0.mode.displayName), controller \($0.controllerCode), intensity \($0.intensity)/5" }
            .joined(separator: "; ")
        return """
        2010 historical canon: \(canonNotice)
        Selected country: \(state.country.name) (\(state.country.code)).
        2010 baseline: nominal GDP \(String(format: "$%.2fT", profile.nominalGDPTrillions)), GDP growth \(formatPercent(profile.gdpGrowthPercent)), inflation \(formatPercent(profile.inflationPercent)), energy security \(profile.energySecurity)%, food security \(profile.foodSecurity)%, nuclear status \(profile.nuclearStatus).
        Current alternate-history ledger: nominal GDP \(String(format: "$%.2fT", state.economicLedger.nominalGDPTrillions)), growth \(formatPercent(state.economicLedger.realGrowthPercent)), inflation \(formatUnsignedPercent(state.economicLedger.inflationPercent)), budget balance \(formatPercent(state.economicLedger.budgetBalancePercentGDP)) of GDP, public debt \(formatUnsignedPercent(state.economicLedger.publicDebtPercentGDP)) of GDP, trade balance \(formatPercent(state.economicLedger.tradeBalancePercentGDP)) of GDP, public security \(String(format: "%.1f", state.economicLedger.securityIndex))/100, insurgency pressure \(String(format: "%.1f%%", state.economicLedger.rebelControlPercent)).
        Current map conflict states: \(conflictSummary.isEmpty ? "No contested, occupied, insurgent-held, or nuclear fallout regions are recorded." : conflictSummary).
        2010 diplomatic alignment: \(alignments).
        Do not invent future blocs, fictional wars, or post-2010 countries as starting facts.
        """
    }

    private static func relation(from playerCode: String, to code: String) -> Native2010Relation {
        if playerCode == code { return .ally }
        switch (playerCode, code) {
        case ("USA", "DEU"), ("USA", "GBR"), ("USA", "FRA"), ("USA", "JPN"), ("USA", "AUS"),
             ("DEU", "USA"), ("FRA", "USA"), ("GBR", "USA"), ("JPN", "USA"), ("AUS", "USA"):
            return .ally
        case ("BRA", "USA"), ("BRA", "DEU"), ("BRA", "CHN"), ("CHN", "RUS"), ("RUS", "CHN"):
            return .partner
        case ("USA", "CHN"), ("USA", "RUS"), ("CHN", "USA"), ("RUS", "USA"), ("JPN", "CHN"), ("CHN", "JPN"):
            return .rival
        default:
            return .neutral
        }
    }

    private static func trackDelta(_ state: NativeCampaignState, _ track: NativeStrategicTrack) -> Int {
        state.worldEffects.filter { $0.track == track }.map(\.magnitude).reduce(0, +)
    }

    private static func clamp(_ value: Int) -> Int {
        max(0, min(100, value))
    }

    private static func formatPercent(_ value: Double) -> String {
        String(format: "%+.1f%%", value)
    }

    private static func formatUnsignedPercent(_ value: Double) -> String {
        String(format: "%.1f%%", value)
    }
}
