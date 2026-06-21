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

        let pLedger = state.economicLedger
        let occupiedCount = state.regionOccupations.filter { key, val in
            let reg = GeopoliticalMapData.regionByID[key]
            return reg?.countryCode == state.country.code && val != state.country.code
        }.count

        switch state.scenarioID {
        case "default":
            if state.stability >= 80, pLedger.tradeBalancePercentGDP >= 0.0, occupiedCount == 0 {
                return .won
            }
            if currentYear > 2030 {
                return .lostTimeout
            }
        case "fragmented-markets":
            if state.stability >= 75, pLedger.nominalGDPTrillions >= 15.0, pLedger.fiscalSpaceIndex >= 60 {
                return .won
            }
            if currentYear > 2040 {
                return .lostTimeout
            }
        case "resilience-decade":
            if state.stability >= 80, pLedger.securityIndex >= 85, pLedger.rebelControlPercent <= 5.0 {
                return .won
            }
            if currentYear > 2050 {
                return .lostTimeout
            }
        case "soviet-triumph":
            let occupiedRivals = state.regionOccupations.filter { key, val in
                let reg = GeopoliticalMapData.regionByID[key]
                return reg?.countryCode != state.country.code && val == state.country.code
            }.count
            if state.stability >= 80, state.worldTension >= 80, occupiedRivals >= 2 {
                return .won
            }
            if currentYear > 2005 {
                return .lostTimeout
            }
        case "pax-cybernetica":
            if state.stability >= 85, pLedger.nominalGDPTrillions >= 25.0, pLedger.tradeBalancePercentGDP >= 2.0 {
                return .won
            }
            if currentYear > 2065 {
                return .lostTimeout
            }
        case "solarpunk-dawn":
            if state.stability >= 85, pLedger.rebelControlPercent <= 0.1, pLedger.securityIndex >= 80 {
                return .won
            }
            if currentYear > 2070 {
                return .lostTimeout
            }
        default:
            if state.stability >= 85, currentYear <= 2040 {
                return .won
            }
            if currentYear > 2040 {
                return .lostTimeout
            }
        }

        return .ongoing
    }

    static func campaignObjectives(for state: NativeCampaignState) -> [NativeCampaignObjective] {
        let pLedger = state.economicLedger
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
                objective(id: "stability", title: "Domestic legitimacy", detail: "Reach 80 stability before the post-crisis decade closes.", current: state.stability, target: 80, suffix: "/100", deadline: "2030", complete: state.stability >= 80),
                objective(id: "trade", title: "External balance", detail: "Bring trade balance to zero or better.", current: pLedger.tradeBalancePercentGDP, target: 0, suffix: "% GDP", deadline: "2030", complete: pLedger.tradeBalancePercentGDP >= 0),
                objective(id: "core", title: "Territorial integrity", detail: "Keep all core regions out of occupation or guerrilla control.", current: max(0, coreRegionCount - occupiedCoreCount), target: coreRegionCount, suffix: " secure", deadline: "2030", complete: occupiedCoreCount == 0)
            ]
        case "fragmented-markets":
            return [
                objective(id: "stability", title: "Bloc stability", detail: "Hold 75 stability in a fractured market order.", current: state.stability, target: 75, suffix: "/100", deadline: "2040", complete: state.stability >= 75),
                objective(id: "gdp", title: "Economic mass", detail: "Reach $15T nominal GDP.", current: pLedger.nominalGDPTrillions, target: 15, prefix: "$", suffix: "T", deadline: "2040", complete: pLedger.nominalGDPTrillions >= 15),
                objective(id: "fiscal", title: "Fiscal room", detail: "Preserve 60 fiscal-space index.", current: pLedger.fiscalSpaceIndex, target: 60, suffix: "/100", deadline: "2040", complete: pLedger.fiscalSpaceIndex >= 60)
            ]
        case "resilience-decade":
            return [
                objective(id: "stability", title: "Institutional trust", detail: "Reach 80 stability through patient delivery.", current: state.stability, target: 80, suffix: "/100", deadline: "2050", complete: state.stability >= 80),
                objective(id: "security", title: "Public security", detail: "Reach 85 public-security index.", current: pLedger.securityIndex, target: 85, suffix: "/100", deadline: "2050", complete: pLedger.securityIndex >= 85),
                objective(id: "insurgency", title: "Local calm", detail: "Reduce rebel control to 5% or less.", current: max(0, 100 - pLedger.rebelControlPercent), target: 95, suffix: "% calm", deadline: "2050", complete: pLedger.rebelControlPercent <= 5)
            ]
        case "soviet-triumph":
            return [
                objective(id: "stability", title: "Command legitimacy", detail: "Reach 80 stability under hegemonic pressure.", current: state.stability, target: 80, suffix: "/100", deadline: "2005", complete: state.stability >= 80),
                objective(id: "tension", title: "Bipolar leverage", detail: "Keep world tension at 80 or higher.", current: state.worldTension, target: 80, suffix: "/100", deadline: "2005", complete: state.worldTension >= 80),
                objective(id: "rivals", title: "Forward control", detail: "Occupy at least two rival regions.", current: occupiedRivals, target: 2, suffix: " regions", deadline: "2005", complete: occupiedRivals >= 2)
            ]
        case "pax-cybernetica":
            return [
                objective(id: "stability", title: "Protocol legitimacy", detail: "Reach 85 stability.", current: state.stability, target: 85, suffix: "/100", deadline: "2065", complete: state.stability >= 85),
                objective(id: "gdp", title: "Network scale", detail: "Reach $25T nominal GDP.", current: pLedger.nominalGDPTrillions, target: 25, prefix: "$", suffix: "T", deadline: "2065", complete: pLedger.nominalGDPTrillions >= 25),
                objective(id: "trade", title: "Data-trade surplus", detail: "Reach +2% trade balance.", current: pLedger.tradeBalancePercentGDP, target: 2, suffix: "% GDP", deadline: "2065", complete: pLedger.tradeBalancePercentGDP >= 2)
            ]
        case "solarpunk-dawn":
            return [
                objective(id: "stability", title: "Cooperative legitimacy", detail: "Reach 85 stability.", current: state.stability, target: 85, suffix: "/100", deadline: "2070", complete: state.stability >= 85),
                objective(id: "rebel", title: "Zero insurgency", detail: "Reduce rebel control to zero.", current: max(0, 100 - pLedger.rebelControlPercent), target: 100, suffix: "% calm", deadline: "2070", complete: pLedger.rebelControlPercent <= 0.1),
                objective(id: "security", title: "Bioregion security", detail: "Hold 80 public-security index.", current: pLedger.securityIndex, target: 80, suffix: "/100", deadline: "2070", complete: pLedger.securityIndex >= 80)
            ]
        default:
            return [
                objective(id: "stability", title: "Regime durability", detail: "Reach 85 stability.", current: state.stability, target: 85, suffix: "/100", deadline: "2040", complete: state.stability >= 85),
                objective(id: "security", title: "Strategic security", detail: "Keep public security above 70.", current: pLedger.securityIndex, target: 70, suffix: "/100", deadline: "2040", complete: pLedger.securityIndex >= 70),
                objective(id: "tension", title: "Manage global friction", detail: "Keep world tension below 70.", current: max(0, 100 - state.worldTension), target: 31, suffix: " safe", deadline: "2040", complete: state.worldTension < 70)
            ]
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
