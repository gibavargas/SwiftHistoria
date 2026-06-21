import Foundation

/// Regional military/diplomatic order resolution.
extension NativeGameEngine {
    enum NativeRegionOrderKind {
        case autonomy
        case fortify
        case invade
        case rebuild
        case stabilize
        case tradeCorridor
        case withdraw

        var displayName: String {
            switch self {
            case .autonomy: "autonomy"
            case .fortify: "fortification"
            case .invade: "invasion"
            case .rebuild: "rebuild"
            case .stabilize: "stabilization"
            case .tradeCorridor: "trade corridor"
            case .withdraw: "withdrawal"
            }
        }
    }

    static func regionOrderKind(from text: String) -> NativeRegionOrderKind? {
        let lower = sanitizeFoundationModelText(text).lowercased()
        let firstWord = lower.split(separator: " ").first.map(String.init) ?? ""

        // Invasion keywords (EN/PT/ES)
        let invadeWords: Set = ["invade", "invadir", "atacar", "attack", "conquer", "conquistar"]
        let stabilizeWords: Set = ["stabilize", "estabilizar", "pacificar", "pacify"]
        let fortifyWords: Set = ["fortify", "fortificar", "reforzar", "reforçar", "defend", "defender"]
        let withdrawWords: Set = ["withdraw", "retirar", "retirarse", "recuar"]
        let rebuildWords: Set = ["rebuild", "reconstruir", "reconstrução"]

        if invadeWords.contains(firstWord) { return .invade }
        if stabilizeWords.contains(firstWord) { return .stabilize }
        if fortifyWords.contains(firstWord) { return .fortify }
        if withdrawWords.contains(firstWord) { return .withdraw }
        if rebuildWords.contains(firstWord) { return .rebuild }

        // Multi-word prefixes for autonomy and trade corridor
        if lower.hasPrefix("negotiate autonomy") || lower.hasPrefix("negociar autonomia") { return .autonomy }
        if lower.hasPrefix("open trade corridor") || lower.hasPrefix("abrir corredor") { return .tradeCorridor }

        // Fallback: check original English prefixes for backward compatibility
        if lower.hasPrefix("invade ") { return .invade }
        if lower.hasPrefix("stabilize ") { return .stabilize }
        if lower.hasPrefix("fortify ") { return .fortify }
        if lower.hasPrefix("withdraw from ") { return .withdraw }
        if lower.hasPrefix("negotiate autonomy for ") { return .autonomy }
        if lower.hasPrefix("rebuild ") { return .rebuild }
        if lower.hasPrefix("open trade corridor through ") { return .tradeCorridor }
        return nil
    }

    static func regionID(from text: String) -> String? {
        guard let range = text.range(of: "(ID: "),
              let endRange = text.range(of: ")", range: range.upperBound ..< text.endIndex)
        else {
            return nil
        }
        let regionID = String(text[range.upperBound ..< endRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        return regionID.isEmpty ? nil : regionID
    }

    static func unresolvedRegionalOrderEvent(
        kind: NativeRegionOrderKind,
        action: NativePlannedAction,
        targetDate: String
    ) -> NativeCampaignEvent {
        NativeCampaignEvent(
            date: targetDate,
            description: "The regional command could not be executed because its region marker is missing or no longer matches the current map. Open the map and issue a fresh \(kind.displayName) order from a region detail panel.",
            id: "regional-invalid-\(action.id)-\(targetDate)",
            importance: .minor,
            kind: .action,
            linkedActionIDs: [action.id],
            notable: false,
            playerRelated: true,
            strategicEffects: [],
            title: "Regional Order Not Executed"
        )
    }

    static func resolveRegionalOrder(
        kind: NativeRegionOrderKind,
        action: NativePlannedAction,
        region: MapRegion,
        state: NativeCampaignState,
        targetDate: String,
        regionOccupations: inout [String: String],
        nuclearFalloutRegions: inout [String],
        regionConflicts: inout [String: NativeRegionConflictState]
    ) -> NativeCampaignEvent {
        let eventID: String
        let title: String
        let description: String
        let importance: NativeEventImportance
        let effects: [(NativeStrategicTrack, Int, String)]

        switch kind {
        case .stabilize:
            if region.countryCode == state.country.code || regionOccupations[region.id] == "REB" {
                regionOccupations.removeValue(forKey: region.id)
            }
            regionConflicts[region.id] = NativeRegionConflictState(
                controllerCode: regionOccupations[region.id] ?? region.countryCode,
                intensity: 2,
                mode: .stabilization,
                originalCountryCode: region.countryCode,
                regionID: region.id,
                summary: "Administrative stabilization teams reduced visible conflict pressure.",
                updatedAt: targetDate
            )
            eventID = "regional-stabilize-\(region.id)-\(targetDate)"
            title = "Stabilization Corridor Opened in \(region.name)"
            description = "Regional administrators opened a stabilization corridor in \(region.name), prioritizing local services, de-escalation channels, and public-security coordination."
            importance = .major
            effects = [
                (.internalStability, 2, "Stabilization lowers domestic conflict pressure."),
                (.economicResilience, 1, "Restored local administration supports service delivery.")
            ]
        case .fortify:
            regionConflicts[region.id] = NativeRegionConflictState(
                controllerCode: regionOccupations[region.id] ?? state.country.code,
                intensity: 3,
                mode: .stabilization,
                originalCountryCode: region.countryCode,
                regionID: region.id,
                summary: "Defensive works and logistics reserves hardened the regional posture.",
                updatedAt: targetDate
            )
            eventID = "regional-fortify-\(region.id)-\(targetDate)"
            title = "\(region.name) Fortification Program"
            description = "Defense planners fortified \(region.name), expanding logistics reserves and local readiness while signaling a firmer posture to nearby rivals."
            importance = .major
            effects = [
                (.militaryReadiness, 2, "Fortification improves regional defensive readiness."),
                (.worldTension, 1, "Visible military works increase external concern.")
            ]
        case .withdraw:
            if regionOccupations[region.id] == state.country.code, region.countryCode != state.country.code {
                regionOccupations.removeValue(forKey: region.id)
            }
            regionConflicts[region.id] = NativeRegionConflictState(
                controllerCode: region.countryCode,
                intensity: 1,
                mode: .stabilization,
                originalCountryCode: region.countryCode,
                regionID: region.id,
                summary: "Withdrawal reduced occupation burden and opened de-escalation channels.",
                updatedAt: targetDate
            )
            eventID = "regional-withdraw-\(region.id)-\(targetDate)"
            title = "Withdrawal from \(region.name)"
            description = "The cabinet authorized a managed withdrawal from \(region.name), lowering occupation costs and converting the file into a monitored de-escalation channel."
            importance = .major
            effects = [
                (.worldTension, -2, "Withdrawal lowers external friction."),
                (.internalStability, 1, "Lower occupation burden improves domestic legitimacy.")
            ]
        case .autonomy:
            if region.countryCode == state.country.code {
                regionOccupations.removeValue(forKey: region.id)
            }
            regionConflicts[region.id] = NativeRegionConflictState(
                controllerCode: region.countryCode,
                intensity: 2,
                mode: .stabilization,
                originalCountryCode: region.countryCode,
                regionID: region.id,
                summary: "Autonomy talks traded central control for lower insurgency pressure.",
                updatedAt: targetDate
            )
            eventID = "regional-autonomy-\(region.id)-\(targetDate)"
            title = "\(region.name) Autonomy Framework"
            description = "Negotiators opened an autonomy framework for \(region.name), exchanging limited local discretion for a calmer security environment and clearer tax-service obligations."
            importance = .major
            effects = [
                (.diplomaticLeverage, 1, "Autonomy talks improve negotiated legitimacy."),
                (.internalStability, 1, "Local concessions reduce insurgency pressure.")
            ]
        case .rebuild:
            nuclearFalloutRegions.removeAll { $0 == region.id }
            regionConflicts[region.id] = NativeRegionConflictState(
                controllerCode: regionOccupations[region.id] ?? region.countryCode,
                intensity: 2,
                mode: .stabilization,
                originalCountryCode: region.countryCode,
                regionID: region.id,
                summary: "Reconstruction teams repaired critical systems and reduced exclusion-zone pressure.",
                updatedAt: targetDate
            )
            eventID = "regional-rebuild-\(region.id)-\(targetDate)"
            title = "\(region.name) Reconstruction Push"
            description = "Reconstruction agencies concentrated engineers, public-health teams, and logistics contractors in \(region.name), repairing damage and restoring economic access."
            importance = .major
            effects = [
                (.economicResilience, 2, "Reconstruction restores productive capacity."),
                (.internalStability, 1, "Visible recovery improves local legitimacy.")
            ]
        case .tradeCorridor:
            regionConflicts[region.id] = NativeRegionConflictState(
                controllerCode: regionOccupations[region.id] ?? region.countryCode,
                intensity: 1,
                mode: .stabilization,
                originalCountryCode: region.countryCode,
                regionID: region.id,
                summary: "A protected trade corridor improved predictable market access.",
                updatedAt: targetDate
            )
            eventID = "regional-corridor-\(region.id)-\(targetDate)"
            title = "\(region.name) Trade Corridor"
            description = "Transport ministries opened a monitored trade corridor through \(region.name), prioritizing customs reliability, service access, and market confidence."
            importance = .minor
            effects = [
                (.marketConfidence, 2, "Reliable corridor access raises market confidence."),
                (.economicResilience, 1, "Trade throughput supports resilience.")
            ]
        case .invade:
            eventID = "regional-noop-\(region.id)-\(targetDate)"
            title = "Regional Order Deferred"
            description = "The regional order for \(region.name) was deferred for standard military resolution."
            importance = .minor
            effects = []
        }

        let strategicEffects = effects.enumerated().map { index, effect in
            NativeStrategicEffect(
                date: targetDate,
                eventId: eventID,
                id: "\(eventID)-effect-\(index)",
                magnitude: effect.1,
                summary: effect.2,
                target: state.country.code,
                track: effect.0
            )
        }

        return NativeCampaignEvent(
            date: targetDate,
            description: description,
            id: eventID,
            importance: importance,
            kind: .action,
            linkedActionIDs: [action.id],
            notable: true,
            playerRelated: true,
            strategicEffects: strategicEffects,
            title: title
        )
    }
}
