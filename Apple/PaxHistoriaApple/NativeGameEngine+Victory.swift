import Foundation

/// Victory evaluation, campaign objectives, and related helpers.
extension NativeGameEngine {
    static func evaluateVictoryStatus(for state: NativeCampaignState) -> NativeVictoryStatus {
        if state.stability <= 0 {
            return .lostCollapse
        }

        guard let currentYear = getYear(from: state.gameDate) else {
            return .ongoing
        }

        // A deadline is terminal even if the objectives are first satisfied on
        // a later turn. The objective panel describes them as deadline-bound,
        // so allowing a post-deadline win would contradict the player-facing
        // contract.
        if currentYear > campaignDeadlineYear(for: state) {
            return .lostTimeout
        }

        // The objective panel is the canonical victory contract. Evaluating
        // the same objective values prevents UI/evaluator drift when scenarios
        // are added or their thresholds change.
        if campaignObjectives(for: state).allSatisfy(\.isComplete) {
            return .won
        }

        if victoriousRivalCode(in: state) != nil {
            return .lostRival
        }

        return .ongoing
    }

    /// Returns the first rival that has earned a complete campaign meter while
    /// still satisfying every active-scenario objective. Opening ledgers cannot
    /// win by themselves: the meter advances only on completed AI agendas.
    /// Sorting makes simultaneous completions deterministic across launches.
    static func victoriousRivalCode(in state: NativeCampaignState) -> String? {
        if state.victoryStatus == .lostRival,
           let persistedCode = state.rivalVictoryCountryCode,
           !persistedCode.isEmpty
        {
            return persistedCode
        }

        let playerCode = GeopoliticalMapData.canonicalCountryCode(state.country.code)
        return state.aiCountryStates.keys
            .filter {
                $0 != "GLOBAL" &&
                    GeopoliticalMapData.canonicalCountryCode($0) != playerCode
            }
            .sorted()
            .first {
                NativeStrategyContextDatabase.aiVictoryProgress(forCode: $0, in: state) >= 100 &&
                    NativeStrategyContextDatabase.aiVictoryReadiness(forCode: $0, in: state) >= 100
            }
    }

    static func victoriousRivalName(in state: NativeCampaignState) -> String? {
        victoriousRivalCode(in: state).map { CountryNameResolver.name(forCode: $0, in: state) }
    }

    static func terminalCampaignEvent(
        for status: NativeVictoryStatus,
        state: NativeCampaignState,
        targetDate: String
    ) -> NativeCampaignEvent? {
        let event: (id: String, importance: NativeEventImportance, title: String, description: String)?
        switch status {
        case .ongoing:
            event = nil
        case .won:
            event = (
                "victory-\(targetDate)",
                .major,
                "CAMPAIGN VICTORY ACHIEVED",
                "VICTORY: Your administration successfully achieved all objectives for scenario \(state.scenarioName)!"
            )
        case .lostCollapse:
            event = (
                "stability-collapse-\(targetDate)",
                .severe,
                "NATION COLLAPSED",
                "COLLAPSE: Government authority has completely dissolved. The nation has entered a period of total anarchic collapse."
            )
        case .lostRival:
            let rivalCode = state.rivalVictoryCountryCode ?? victoriousRivalCode(in: state) ?? "rival"
            let rivalName = victoriousRivalName(in: state) ?? "A rival power"
            event = (
                "rival-victory-\(rivalCode.lowercased())-\(targetDate)",
                .severe,
                "RIVAL VICTORY: \(rivalName)",
                "DEFEAT: \(rivalName) completed the active scenario objectives before your administration secured its own victory."
            )
        case .lostTimeout:
            event = (
                "timeout-\(targetDate)",
                .severe,
                "CAMPAIGN DEADLINE EXCEEDED",
                "DEFEAT: Time has run out. Your administration failed to meet the objectives by the deadline."
            )
        }

        guard let event else { return nil }
        return NativeCampaignEvent(
            date: targetDate,
            description: event.description,
            id: event.id,
            importance: event.importance,
            kind: .world,
            linkedActionIDs: [],
            notable: true,
            playerRelated: true,
            strategicEffects: [],
            title: event.title
        )
    }

    static func campaignObjectives(for state: NativeCampaignState) -> [NativeCampaignObjective] {
        let pLedger = state.economicLedger
        let deadline = String(campaignDeadlineYear(for: state))
        let playerCode = GeopoliticalMapData.canonicalCountryCode(state.country.code)
        let occupiedCoreCount = state.regionOccupations.filter { key, val in
            let reg = GeopoliticalMapData.regionByID[key]
            return GeopoliticalMapData.canonicalCountryCode(reg?.countryCode ?? "") == playerCode &&
                GeopoliticalMapData.canonicalCountryCode(val) != playerCode
        }.count
        let coreRegionCount = max(1, GeopoliticalMapData.regions(forCountryCode: state.country.code).count)
        let occupiedRivals = state.regionOccupations.filter { key, val in
            let reg = GeopoliticalMapData.regionByID[key]
            return GeopoliticalMapData.canonicalCountryCode(reg?.countryCode ?? "") != playerCode &&
                GeopoliticalMapData.canonicalCountryCode(val) == playerCode
        }.count

        switch state.scenarioID {
        case "default":
            return [
                objective(id: "stability", title: "Domestic legitimacy", detail: "Reach 80 stability before the post-crisis decade closes.", current: state.stability, target: 80, suffix: "/100", deadline: deadline, complete: state.stability >= 80),
                objective(id: "trade", title: "External balance", detail: "Bring trade balance to zero or better.", current: pLedger.tradeBalancePercentGDP, target: 0, suffix: "% GDP", deadline: deadline, complete: pLedger.tradeBalancePercentGDP >= 0),
                objective(id: "core", title: "Territorial integrity", detail: "Keep all core regions out of occupation or guerrilla control.", current: max(0, coreRegionCount - occupiedCoreCount), target: coreRegionCount, suffix: " secure", deadline: deadline, complete: occupiedCoreCount == 0)
            ]
        case "fragmented-markets":
            return [
                objective(id: "stability", title: "Bloc stability", detail: "Hold 75 stability in a fractured market order.", current: state.stability, target: 75, suffix: "/100", deadline: deadline, complete: state.stability >= 75),
                objective(id: "gdp", title: "Economic mass", detail: "Reach $15T nominal GDP.", current: pLedger.nominalGDPTrillions, target: 15, prefix: "$", suffix: "T", deadline: deadline, complete: pLedger.nominalGDPTrillions >= 15),
                objective(id: "fiscal", title: "Fiscal room", detail: "Preserve 60 fiscal-space index.", current: pLedger.fiscalSpaceIndex, target: 60, suffix: "/100", deadline: deadline, complete: pLedger.fiscalSpaceIndex >= 60)
            ]
        case "resilience-decade":
            return [
                objective(id: "stability", title: "Institutional trust", detail: "Reach 80 stability through patient delivery.", current: state.stability, target: 80, suffix: "/100", deadline: deadline, complete: state.stability >= 80),
                objective(id: "security", title: "Public security", detail: "Reach 85 public-security index.", current: pLedger.securityIndex, target: 85, suffix: "/100", deadline: deadline, complete: pLedger.securityIndex >= 85),
                objective(id: "insurgency", title: "Local calm", detail: "Reduce rebel control to 5% or less.", current: max(0, 100 - pLedger.rebelControlPercent), target: 95, suffix: "% calm", deadline: deadline, complete: pLedger.rebelControlPercent <= 5)
            ]
        case "soviet-triumph":
            return [
                objective(id: "stability", title: "Command legitimacy", detail: "Reach 80 stability under hegemonic pressure.", current: state.stability, target: 80, suffix: "/100", deadline: deadline, complete: state.stability >= 80),
                objective(id: "tension", title: "Bipolar leverage", detail: "Keep world tension at 80 or higher.", current: state.worldTension, target: 80, suffix: "/100", deadline: deadline, complete: state.worldTension >= 80),
                objective(id: "rivals", title: "Forward control", detail: "Occupy at least two rival regions.", current: occupiedRivals, target: 2, suffix: " regions", deadline: deadline, complete: occupiedRivals >= 2)
            ]
        case "pax-cybernetica":
            return [
                objective(id: "stability", title: "Protocol legitimacy", detail: "Reach 85 stability.", current: state.stability, target: 85, suffix: "/100", deadline: deadline, complete: state.stability >= 85),
                objective(id: "gdp", title: "Network scale", detail: "Reach $25T nominal GDP.", current: pLedger.nominalGDPTrillions, target: 25, prefix: "$", suffix: "T", deadline: deadline, complete: pLedger.nominalGDPTrillions >= 25),
                objective(id: "trade", title: "Data-trade surplus", detail: "Reach +2% trade balance.", current: pLedger.tradeBalancePercentGDP, target: 2, suffix: "% GDP", deadline: deadline, complete: pLedger.tradeBalancePercentGDP >= 2)
            ]
        case "solarpunk-dawn":
            return [
                objective(id: "stability", title: "Cooperative legitimacy", detail: "Reach 85 stability.", current: state.stability, target: 85, suffix: "/100", deadline: deadline, complete: state.stability >= 85),
                objective(id: "rebel", title: "Zero insurgency", detail: "Reduce rebel control to zero.", current: max(0, 100 - pLedger.rebelControlPercent), target: 100, suffix: "% calm", deadline: deadline, complete: pLedger.rebelControlPercent <= 0.1),
                objective(id: "security", title: "Bioregion security", detail: "Hold 80 public-security index.", current: pLedger.securityIndex, target: 80, suffix: "/100", deadline: deadline, complete: pLedger.securityIndex >= 80)
            ]
        default:
            return [
                objective(id: "stability", title: "Regime durability", detail: "Reach 85 stability.", current: state.stability, target: 85, suffix: "/100", deadline: deadline, complete: state.stability >= 85),
                objective(id: "security", title: "Strategic security", detail: "Keep public security above 70.", current: pLedger.securityIndex, target: 70, suffix: "/100", deadline: deadline, complete: pLedger.securityIndex >= 70),
                objective(id: "tension", title: "Manage global friction", detail: "Keep world tension below 70.", current: max(0, 100 - state.worldTension), target: 31, suffix: " safe", deadline: deadline, complete: state.worldTension < 70)
            ]
        }
    }

    private static func campaignDeadlineYear(for state: NativeCampaignState) -> Int {
        switch state.scenarioID {
        case "default": 2030
        case "fragmented-markets": 2040
        case "resilience-decade": 2050
        case "soviet-triumph": 2005
        case "pax-cybernetica": 2065
        case "solarpunk-dawn": 2070
        case "divided-sovereignty": 1910
        case "resource-crucible": 2050
        default:
            (getYear(from: state.startDate) ?? getYear(from: state.gameDate) ?? 2025) + 15
        }
    }

    private static func objective(
        id: String,
        title: String,
        detail: String,
        current: Double,
        target: Double,
        prefix: String = "",
        suffix: String,
        deadline: String,
        complete: Bool
    ) -> NativeCampaignObjective {
        let progress = target == 0 ? (complete ? 1.0 : 0.0) : max(0, min(1, current / target))
        return NativeCampaignObjective(
            currentValue: "\(prefix)\(formatObjectiveNumber(current))\(suffix)",
            detail: detail,
            deadline: deadline,
            id: id,
            isComplete: complete,
            progress: progress,
            targetValue: "\(prefix)\(formatObjectiveNumber(target))\(suffix)",
            title: title
        )
    }

    private static func objective(
        id: String,
        title: String,
        detail: String,
        current: Int,
        target: Int,
        prefix: String = "",
        suffix: String,
        deadline: String,
        complete: Bool
    ) -> NativeCampaignObjective {
        objective(
            id: id,
            title: title,
            detail: detail,
            current: Double(current),
            target: Double(target),
            prefix: prefix,
            suffix: suffix,
            deadline: deadline,
            complete: complete
        )
    }

    private static func formatObjectiveNumber(_ value: Double) -> String {
        if value.rounded() == value {
            return "\(Int(value))"
        }
        return String(format: "%.1f", value)
    }

    static func signed(_ value: Int) -> String {
        value >= 0 ? "+\(value)" : "\(value)"
    }
}
