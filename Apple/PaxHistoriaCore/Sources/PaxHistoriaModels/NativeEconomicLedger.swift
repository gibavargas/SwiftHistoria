import Foundation

public struct NativeEconomicLedgerEntry: Codable, Hashable, Identifiable, Sendable {
    public var budgetBalanceDelta: Double
    public var debtDelta: Double
    public var eventID: String
    public var fiscalSpaceDelta: Int
    public var growthDelta: Double
    public var id: String
    public var inflationDelta: Double
    public var ruleID: String
    public var summary: String
    public var tradeBalanceDelta: Double
    public var turnDate: String
    public var securityDelta: Double?
    public var rebelDelta: Double?

    public init(
        budgetBalanceDelta: Double,
        debtDelta: Double,
        eventID: String,
        fiscalSpaceDelta: Int,
        growthDelta: Double,
        id: String,
        inflationDelta: Double,
        ruleID: String,
        summary: String,
        tradeBalanceDelta: Double,
        turnDate: String,
        securityDelta: Double? = nil,
        rebelDelta: Double? = nil
    ) {
        self.budgetBalanceDelta = budgetBalanceDelta
        self.debtDelta = debtDelta
        self.eventID = eventID
        self.fiscalSpaceDelta = fiscalSpaceDelta
        self.growthDelta = growthDelta
        self.id = id
        self.inflationDelta = inflationDelta
        self.ruleID = ruleID
        self.summary = summary
        self.tradeBalanceDelta = tradeBalanceDelta
        self.turnDate = turnDate
        self.securityDelta = securityDelta
        self.rebelDelta = rebelDelta
    }
}

public struct NativeEconomicLedger: Codable, Hashable, Sendable {
    public var budgetBalancePercentGDP: Double
    public var entries: [NativeEconomicLedgerEntry]
    public var fiscalSpaceIndex: Int
    public var inflationPercent: Double
    public var nominalGDPTrillions: Double
    public var publicDebtPercentGDP: Double
    public var realGrowthPercent: Double
    public var tradeBalancePercentGDP: Double
    public var unemploymentPercent: Double
    public var securityIndex: Double
    public var rebelControlPercent: Double

    public enum CodingKeys: String, CodingKey {
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
    }

    public init(
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
        rebelControlPercent: Double = 0.0
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
    }

    public init(from decoder: Decoder) throws {
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
    }

    public static let economicSupplements: [String: (budgetBalance: Double, publicDebt: Double, unemployment: Double, fiscalSpace: Int)] = [
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
        "GLOBAL": (-3.5, 58.0, 8.0, 48)
    ]

    private static func clampDouble(_ value: Double, _ lower: Double, _ upper: Double) -> Double {
        min(upper, max(lower, value))
    }

    public static func starting(for country: PlayerCountry, scenario _: NativeScenario) -> NativeEconomicLedger {
        let profile = Native2010WorldModel.profile(for: country)
        let supplement = economicSupplements[country.code] ?? economicSupplements["GLOBAL"]!
        let openingSecurity = clampDouble(Double(profile.stability) + 18.0 - Double(profile.sanctionsExposurePercent) * 0.35, 35, 92)
        let openingRebelPressure = clampDouble(
            Double(100 - profile.stability) * 0.16 + Double(supplement.unemployment) * 0.22 - Double(supplement.fiscalSpace) * 0.04,
            0,
            28
        )
        return NativeEconomicLedger(
            budgetBalancePercentGDP: supplement.budgetBalance,
            entries: [],
            fiscalSpaceIndex: supplement.fiscalSpace,
            inflationPercent: profile.inflationPercent,
            nominalGDPTrillions: profile.nominalGDPTrillions,
            publicDebtPercentGDP: supplement.publicDebt,
            realGrowthPercent: profile.gdpGrowthPercent,
            tradeBalancePercentGDP: profile.tradeBalancePercent,
            unemploymentPercent: supplement.unemployment,
            securityIndex: openingSecurity,
            rebelControlPercent: openingRebelPressure
        )
    }

    public static func starting(forCode code: String, scenario: NativeScenario) -> NativeEconomicLedger {
        let dummyCountry = PlayerCountry(code: code, name: code)
        return starting(for: dummyCountry, scenario: scenario)
    }
}
