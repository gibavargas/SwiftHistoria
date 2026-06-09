import Foundation

enum NativeFoundationTurnLane: String, Codable, CaseIterable, Hashable, Identifiable {
    case external
    case economy
    case budget
    case domestic
    case actionConsequence
    case summary

    var id: String { rawValue }

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

    var fraction: Double {
        guard totalLanes > 0 else { return 0 }
        return min(1.0, max(0.0, Double(completedLanes) / Double(totalLanes)))
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
            return .conventionalOccupation
        case 2:
            return .guerrillaControl
        case 3:
            return .nuclearFallout
        case 4, 6, -1:
            return .stabilization
        case 5:
            return .contestedBorder
        default:
            return nil
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
    var economicLedger: NativeEconomicLedger
    var facts: [NativeFactRecord]
    var recentActions: [NativeActionMemory]
    var aiCountryStates: [String: NativeAICountryState] = [:]

    var promptBlock: String {
        let factLines = facts.prefix(6).map { "- \($0.id): \($0.title) -- \($0.detail)" }.joined(separator: "\n")
        let ruleLines = consequenceRules.prefix(5).map {
            "- \($0.id): \($0.summary); budget \($0.budgetBalanceDelta.signedPercent), growth \($0.growthDelta.signedPercent), inflation \($0.inflationDelta.signedPercent), trade \($0.tradeBalanceDelta.signedPercent)"
        }.joined(separator: "\n")
        let actionLines = recentActions.prefix(5).map {
            "- \($0.status.rawValue): \($0.title) (\($0.createdAt)) rules=\($0.ruleIDs.joined(separator: ",")); \($0.economicSummary)"
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
            return "- \(code): \(aiState.doctrine.rawValue), priority=\(aiState.budgetPriority.rawValue), relations=[\(topRelations.isEmpty ? "neutral" : topRelations)]"
        }.joined(separator: "\n")
        return """
        Local facts database:
        \(factLines.isEmpty ? "- No matching fact records." : factLines)

        Local consequences database:
        \(ruleLines.isEmpty ? "- Use default civic consequence ranges only." : ruleLines)

        Immediate action memory:
        \(actionLines.isEmpty ? "- No recent action records." : actionLines)

        Current economic ledger:
        GDP \(String(format: "$%.2fT", economicLedger.nominalGDPTrillions)); growth \(economicLedger.realGrowthPercent.signedPercent); inflation \(economicLedger.inflationPercent.percent); budget balance \(economicLedger.budgetBalancePercentGDP.signedPercent) of GDP; public debt \(economicLedger.publicDebtPercentGDP.percent) of GDP; trade balance \(economicLedger.tradeBalancePercentGDP.signedPercent) of GDP; unemployment \(economicLedger.unemploymentPercent.percent); fiscal space \(economicLedger.fiscalSpaceIndex)/100; public security \(String(format: "%.1f", economicLedger.securityIndex))/100; insurgency pressure \(String(format: "%.1f%%", economicLedger.rebelControlPercent)).

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
    static var defaultStrategicCountryCodes: [String] {
        let mappedCodes = GeopoliticalMapData.regions.map(\.countryCode)
        return Array(Set(CountryCatalog.all.map(\.code) + mappedCodes + ["GLOBAL"])).sorted()
    }

    static func strategicCountryCodes(for state: NativeCampaignState) -> [String] {
        Array(Set(defaultStrategicCountryCodes + Array(state.economicLedgers.keys) + [state.country.code])).sorted()
    }

    static func startingEconomicLedger(for country: PlayerCountry, scenario: NativeScenario) -> NativeEconomicLedger {
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
        return targetLower.contains("global") || targetLower.contains("international") || targetLower.contains("system")
    }

    static func countryAliases(for code: String) -> [String] {
        let normalizedCode = code.lowercased()
        let catalogName = CountryCatalog.all.first { $0.code == code }?.name.lowercased()
        let fixedAliases: [String]
        switch code {
        case "USA":
            fixedAliases = ["us", "u.s.", "usa", "united states", "america"]
        case "CHN":
            fixedAliases = ["chn", "china"]
        case "BRA":
            fixedAliases = ["bra", "brazil", "brasil"]
        case "DEU":
            fixedAliases = ["deu", "germany", "deutschland"]
        case "GBR":
            fixedAliases = ["gbr", "united kingdom", "uk", "britain"]
        case "RUS":
            fixedAliases = ["rus", "russia"]
        case "ZAF":
            fixedAliases = ["zaf", "south africa"]
        default:
            fixedAliases = [normalizedCode]
        }
        return Array(Set(([normalizedCode, catalogName].compactMap { $0 } + fixedAliases).map { $0.lowercased() }))
    }

    static func contextPacket(for state: NativeCampaignState, months: Int, action: NativePlannedAction? = nil) -> NativeStrategyContextPacket {
        NativeStrategyContextPacket(
            consequenceRules: consequenceRules(for: action, state: state),
            economicLedger: state.economicLedger,
            facts: facts(for: state, action: action),
            recentActions: state.actionMemory.prefix(8).map { $0 },
            aiCountryStates: state.aiCountryStates
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
        for action in resolvedActions where action.status == .resolved {
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

    static func updatedEconomicLedgers(
        from ledgers: [String: NativeEconomicLedger],
        state: NativeCampaignState,
        events: [NativeCampaignEvent],
        months: Int,
        targetDate: String
    ) -> [String: NativeEconomicLedger] {
        var nextLedgers = ledgers

        let countryCodes = strategicCountryCodes(for: state)
        let scenario = NativeScenarioCatalog.scenario(for: state.scenarioID)
        for code in countryCodes {
            if nextLedgers[code] == nil {
                nextLedgers[code] = startingEconomicLedger(forCode: code, scenario: scenario)
            }
        }

        let negativeMultiplier: Double
        switch state.gameMode {
        case .sandbox: negativeMultiplier = 0.5
        case .normal: negativeMultiplier = 1.0
        case .ironman: negativeMultiplier = 2.0
        }

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

    private static func consequenceRules(for action: NativePlannedAction?, state: NativeCampaignState) -> [NativeConsequenceRule] {
        guard let action else {
            return [
                rulesByID["macro-demand"]!,
                rulesByID["market-confidence"]!,
                rulesByID["fiscal-drift"]!,
                rulesByID["public-security"]!,
                rulesByID["insurgency-containment"]!,
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
        "GLOBAL": (-3.5, 58.0, 8.0, 48),
    ]

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
        NativeConsequenceRule(budgetBalanceDelta: -0.10, debtDelta: 0.12, description: "Recurring commitments can slowly erode budget space even without a headline shock.", fiscalSpaceDelta: -2, growthDelta: 0.00, id: "fiscal-drift", inflationDelta: 0.01, keywords: [], summary: "Fiscal drift: budget space narrows.", tradeBalanceDelta: 0.00, track: .economicResilience),
    ]

    private static let rulesByID = Dictionary(uniqueKeysWithValues: consequenceRules.map { ($0.id, $0) })

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
              let f = decodeNibble(chars[5]) else {
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
            return "conventional border advance"
        case 2:
            return "guerrilla control"
        case 3:
            return "nuclear fallout"
        case 4:
            return "domestic stabilization"
        case 5:
            return "contested border"
        case 6:
            return "public-security recovery"
        case 7:
            return "conquest occupation"
        case -1:
            return "de-escalation"
        default:
            return "no map nudge"
        }
    }

    private static func securityNudge(for value: Int) -> Double {
        switch value {
        case 1:
            return -6
        case 2:
            return -14
        case 3:
            return -35
        case 4:
            return 10
        case 5:
            return -4
        case 6:
            return 16
        case 7:
            return -10
        case -1:
            return 8
        default:
            return 0
        }
    }

    private static func rebelNudge(for value: Int) -> Double {
        switch value {
        case 2:
            return 22
        case 3:
            return 12
        case 4, 6, -1:
            return -16
        case 5:
            return 4
        default:
            return 0
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
            if ledger.publicDebtPercentGDP > 120.0 { mult *= 10.0 }
            else if ledger.publicDebtPercentGDP > 100.0 { mult *= 5.0 }

            if ledger.fiscalSpaceIndex < 15 { mult *= 6.0 }
            else if ledger.fiscalSpaceIndex < 30 { mult *= 3.0 }

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
        if ledger.publicDebtPercentGDP < 50.0 && ledger.fiscalSpaceIndex > 70 {
            var mult = 1.0
            if ledger.publicDebtPercentGDP < 30.0 { mult *= 2.0 }
            if ledger.fiscalSpaceIndex > 85 { mult *= 2.0 }

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
        if ledger.fiscalSpaceIndex > 70 { pBreakthrough *= 1.5 }
        if ledger.realGrowthPercent > 4.0 { pBreakthrough *= 1.5 }
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
        if ledger.fiscalSpaceIndex < 30 { pBottleneck *= 2.0 }
        if ledger.realGrowthPercent > 5.0 { pBottleneck *= 1.5 }
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
        if ledger.inflationPercent > 6.0 { pNudge *= 0.3 }
        if ledger.unemploymentPercent < 5.0 { pNudge *= 1.5 }
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
        if ledger.inflationPercent > 5.0 { pDrift *= 2.0 }
        if ledger.fiscalSpaceIndex < 30 { pDrift *= 1.5 }
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
        let noiseFiscalSpace: Int
        if fsRoll > 0.85 { noiseFiscalSpace = 1 }
        else if fsRoll < 0.15 { noiseFiscalSpace = -1 }
        else { noiseFiscalSpace = 0 }

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
            } else if mil < 0.20 {
                milSecurityDelta = -2.0 * Double(months)
                milRebelDelta = 1.5 * Double(months)
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

            pLedger.securityIndex = clampDouble(pLedger.securityIndex + milSecurityDelta, 0, 100)
            pLedger.rebelControlPercent = clampDouble(pLedger.rebelControlPercent + milRebelDelta, 0, 100)
            pLedger.publicDebtPercentGDP = clampDouble(pLedger.publicDebtPercentGDP + milDebtDelta, 1, 260)
            pLedger.realGrowthPercent = clampDouble(pLedger.realGrowthPercent + milGrowthDelta + serGrowthDelta, -12, 16)

            pLedger.unemploymentPercent = clampDouble(pLedger.unemploymentPercent + serUnemploymentDelta, 1, 35)
            pLedger.budgetBalancePercentGDP = clampDouble(pLedger.budgetBalancePercentGDP + serBudgetDelta, -12, 12)
            pLedger.tradeBalancePercentGDP = clampDouble(pLedger.tradeBalancePercentGDP + dipTradeDelta, -20, 20)

            if milGrowthDelta != 0 || serGrowthDelta != 0 || serBudgetDelta != 0 || dipTradeDelta != 0 {
                let sliderEntry = NativeEconomicLedgerEntry(
                    budgetBalanceDelta: serBudgetDelta,
                    debtDelta: milDebtDelta,
                    eventID: "budget-slider-\(state.round)",
                    fiscalSpaceDelta: 0,
                    growthDelta: milGrowthDelta + serGrowthDelta,
                    id: "ledger-entry-slider-\(UUID().uuidString.lowercased())",
                    inflationDelta: 0.0,
                    ruleID: "budget-allocation",
                    summary: "Adjustments from budget sliders",
                    tradeBalanceDelta: dipTradeDelta,
                    turnDate: state.gameDate,
                    securityDelta: milSecurityDelta,
                    rebelDelta: milRebelDelta
                )
                pLedger.entries.insert(sliderEntry, at: 0)
            }

            state.economicLedgers[state.country.code] = pLedger

            if serStabilityDelta != 0 {
                state.stability = max(0, min(100, state.stability + serStabilityDelta))
            }
        }

        // 1.5. Process accepted treaties (relationship drift & ongoing effects)
        let acceptedOffers = state.activeOffers.filter { $0.status == .accepted }
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
                        if score < -30 {
                            if var rivalState = state.aiCountryStates[otherCode] {
                                let curRel = rivalState.relationshipScores[state.country.code] ?? 0
                                rivalState.relationshipScores[state.country.code] = max(-100, curRel - Int(1.0 * Double(months)))
                                state.aiCountryStates[otherCode] = rivalState
                            }
                        }
                    }
                }

                for code in strategicCodes {
                    if code == state.country.code { continue }
                    if let aiState = state.aiCountryStates[code], let playerRel = aiState.relationshipScores[state.country.code], playerRel < -30 {
                        if var aiStateMut = state.aiCountryStates[code] {
                            let curRel = aiStateMut.relationshipScores[partnerCode] ?? 0
                            aiStateMut.relationshipScores[partnerCode] = max(-100, curRel - Int(1.0 * Double(months)))
                            state.aiCountryStates[code] = aiStateMut
                        }
                    }
                }
            }
        }

        // 2. Simulate AI countries
        for code in strategicCodes {
            if code == state.country.code { continue }
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
                            id: "ledger-entry-agenda-\(code.lowercased())-\(UUID().uuidString.lowercased())",
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
                    id: "agenda-event-\(code.lowercased())-\(UUID().uuidString.lowercased())",
                    importance: .major,
                    kind: .world,
                    linkedActionIDs: [],
                    notable: true,
                    playerRelated: relations > 30 || relations < -30,
                    strategicEffects: stabilityDelta != 0 ? [
                        NativeStrategicEffect(
                            date: state.gameDate,
                            eventId: "agenda-event-\(code.lowercased())",
                            id: "agenda-effect-\(code.lowercased())-\(UUID().uuidString.lowercased())",
                            magnitude: stabilityDelta,
                            summary: "Stability altered by \(code)'s completed agenda",
                            target: state.country.code,
                            track: .internalStability
                        )
                    ] : [],
                    title: "\(code) completes agenda: \(oldAgenda.prefix(32))..."
                )
                state.timeline.insert(agendaEvent, at: 0)
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
                if otherCode == state.country.code && dipSlider > 0.40 && !acceptedTreatyPartnerCodes.contains(code) {
                    nextScore = min(100.0, nextScore + (1.0 * Double(months)))
                }

                // 3. Apply military arms buildup anxiety to player relations
                if otherCode == state.country.code && milSlider > 0.40 {
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
            if !hasPending && relations >= -20 {
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
                    } else {
                        if rng.nextDouble() < 0.5 {
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
                    }

                    let newOffer = NativeDiplomaticOffer(
                        id: "offer-\(code.lowercased())-\(UUID().uuidString.lowercased())",
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

        // Sync player's main ledger
        if let playerLedger = state.economicLedgers[state.country.code] {
            state.economicLedger = playerLedger
        }
    }
}

private struct SimpleRNG {
    private var state: UInt64

    init(seedString: String) {
        var hash: UInt64 = 14695981039346656037
        for char in seedString.utf8 {
            hash ^= UInt64(char)
            hash = hash.addingReportingOverflow(hash &* 1099511628211).0
        }
        self.state = hash
    }

    mutating func nextDouble() -> Double {
        state = state.addingReportingOverflow(0x9e3779b97f4a7c15).0
        var z = state
        z = (z ^ (z >> 30)) &* 0xbf58476d1ce4e5b9
        z = (z ^ (z >> 27)) &* 0x94d049bb133111eb
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
