import Foundation
import PaxHistoriaModels

extension NativeGameEngine {
    /// 512 virtual dice rolls calculation for friction events
    static func roll512DiceFriction(
        scenarioID: String,
        gameDate: String,
        round: Int,
        playerCountryCode _: String
    ) -> [NativeCampaignEvent] {
        let turnSeed = "\(scenarioID)-\(gameDate)-round-\(round)-512dice"
        var events: [NativeCampaignEvent] = []

        for i in 0 ..< 512 {
            let dieSeed = "\(turnSeed)-die-\(i)"
            let roll = stablePercentage(seed: dieSeed)
            if roll < 5.0 {
                switch i {
                case 13:
                    let eventId = "512dice-plague-\(gameDate)"
                    events.append(NativeCampaignEvent(
                        date: gameDate,
                        description: "A major disease epidemic has spread through commercial hubs. Quarantines and worker absenteeism disrupt local and international supply chains.",
                        id: eventId,
                        importance: .severe,
                        kind: .crisis,
                        linkedActionIDs: [],
                        notable: true,
                        playerRelated: false,
                        strategicEffects: [
                            NativeStrategicEffect(
                                date: gameDate,
                                eventId: eventId,
                                id: "\(eventId)-effect-stability",
                                magnitude: -4,
                                summary: "Epidemic quarantine suppresses stability.",
                                target: "global",
                                track: .internalStability
                            ),
                            NativeStrategicEffect(
                                date: gameDate,
                                eventId: eventId,
                                id: "\(eventId)-effect-econ",
                                magnitude: -3,
                                summary: "Labor shortages degrade economic resilience.",
                                target: "global",
                                track: .economicResilience
                            )
                        ],
                        title: "Virulent Epidemic Outbreak"
                    ))
                case 42:
                    let eventId = "512dice-volcano-\(gameDate)"
                    events.append(NativeCampaignEvent(
                        date: gameDate,
                        description: "A massive volcanic eruption has sent ash plumes into the upper atmosphere. Air travel restrictions and sunlight reductions lead to crop failures and logistical blockages.",
                        id: eventId,
                        importance: .severe,
                        kind: .crisis,
                        linkedActionIDs: [],
                        notable: true,
                        playerRelated: false,
                        strategicEffects: [
                            NativeStrategicEffect(
                                date: gameDate,
                                eventId: eventId,
                                id: "\(eventId)-effect-stability",
                                magnitude: -3,
                                summary: "Atmospheric ash plume disrupts commercial stability.",
                                target: "global",
                                track: .internalStability
                            ),
                            NativeStrategicEffect(
                                date: gameDate,
                                eventId: eventId,
                                id: "\(eventId)-effect-trade",
                                magnitude: -4,
                                summary: "Global logistics blockage suppresses trade balance.",
                                target: "global",
                                track: .diplomaticLeverage
                            )
                        ],
                        title: "Atmospheric Volcanic Eruption"
                    ))
                case 99:
                    let eventId = "512dice-flare-\(gameDate)"
                    events.append(NativeCampaignEvent(
                        date: gameDate,
                        description: "An intense solar solar flare has triggered a severe geomagnetic storm. Power grid fluctuations and satellite communication drops degrade financial transaction networks.",
                        id: eventId,
                        importance: .severe,
                        kind: .crisis,
                        linkedActionIDs: [],
                        notable: true,
                        playerRelated: false,
                        strategicEffects: [
                            NativeStrategicEffect(
                                date: gameDate,
                                eventId: eventId,
                                id: "\(eventId)-effect-market",
                                magnitude: -3,
                                summary: "Geomagnetic storm shocks market confidence.",
                                target: "global",
                                track: .marketConfidence
                            ),
                            NativeStrategicEffect(
                                date: gameDate,
                                eventId: eventId,
                                id: "\(eventId)-effect-resilience",
                                magnitude: -3,
                                summary: "Power grid fluctuations degrade infrastructure resilience.",
                                target: "global",
                                track: .economicResilience
                            )
                        ],
                        title: "Severe Solar Storm"
                    ))
                case 256:
                    let eventId = "512dice-ransomware-\(gameDate)"
                    events.append(NativeCampaignEvent(
                        date: gameDate,
                        description: "A coordinated ransomware attack has locked billing systems across major maritime shipping operators. Ports report container backlog and delivery delays.",
                        id: eventId,
                        importance: .severe,
                        kind: .crisis,
                        linkedActionIDs: [],
                        notable: true,
                        playerRelated: false,
                        strategicEffects: [
                            NativeStrategicEffect(
                                date: gameDate,
                                eventId: eventId,
                                id: "\(eventId)-effect-trade",
                                magnitude: -3,
                                summary: "Shipping ransomware suppresses global trade flow.",
                                target: "global",
                                track: .diplomaticLeverage
                            )
                        ],
                        title: "Coordinated Maritime Ransomware"
                    ))
                case 314:
                    let eventId = "512dice-strike-\(gameDate)"
                    events.append(NativeCampaignEvent(
                        date: gameDate,
                        description: "A wave of strikes across major raw material mines has halted extraction. Shortages of inputs push copper and iron prices higher.",
                        id: eventId,
                        importance: .severe,
                        kind: .crisis,
                        linkedActionIDs: [],
                        notable: true,
                        playerRelated: false,
                        strategicEffects: [
                            NativeStrategicEffect(
                                date: gameDate,
                                eventId: eventId,
                                id: "\(eventId)-effect-resilience",
                                magnitude: -2,
                                summary: "Material shortages stress industrial resilience.",
                                target: "global",
                                track: .economicResilience
                            )
                        ],
                        title: "Global Mining Strike"
                    ))
                case 400:
                    let eventId = "512dice-crop-\(gameDate)"
                    events.append(NativeCampaignEvent(
                        date: gameDate,
                        description: "A newly identified rust fungus strain has infected wheat belts. Yields drop sharply, causing staple food price inflation.",
                        id: eventId,
                        importance: .severe,
                        kind: .crisis,
                        linkedActionIDs: [],
                        notable: true,
                        playerRelated: false,
                        strategicEffects: [
                            NativeStrategicEffect(
                                date: gameDate,
                                eventId: eventId,
                                id: "\(eventId)-effect-market",
                                magnitude: -4,
                                summary: "Agricultural shock suppresses global stability margins.",
                                target: "global",
                                track: .internalStability
                            )
                        ],
                        title: "Agricultural Crop Failure"
                    ))
                default:
                    break
                }
            }
        }
        return events
    }

    static func fnv1aHash(_ seed: String) -> UInt64 {
        var hash: UInt64 = 1_469_598_103_934_665_603
        for byte in seed.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return hash
    }

    static func stablePercentage(seed: String) -> Double {
        Double(fnv1aHash(seed) % 10001) / 100.0
    }

    static func deterministicDie(seed: String) -> Int {
        Int(fnv1aHash(seed) % 6) + 1
    }

    static func rollDice(seed: String, count: Int) -> [Int] {
        var rolls: [Int] = []
        for i in 0 ..< count {
            let die = deterministicDie(seed: "\(seed)-die-\(i)")
            rolls.append(die)
        }
        return rolls
    }

    static func processTacticalNudges(
        events: [NativeCampaignEvent],
        state: NativeCampaignState,
        targetDate: String,
        regionOccupations: inout [String: String],
        nuclearFalloutRegions: inout [String],
        regionConflicts: inout [String: NativeRegionConflictState],
        economicLedgers: inout [String: NativeEconomicLedger]
    ) {
        for event in events {
            guard let hex = event.hexLeverCode,
                  let lever = NativeHexLever.decodeHexLever(hex)
            else {
                continue
            }

            let countryCode = resolvedCountryCode(
                from: event.strategicEffects.first?.target ?? state.country.code,
                fallback: state.country.code
            )
            let targetCountryCode = getRivalCountryCode(for: countryCode)
            let eventSummary = "\(event.title): \(conflictNudgeLabel(for: lever.invasionNudge))."

            switch lever.invasionNudge {
            case 1:
                let targetRegions = GeopoliticalMapData.regionsByCountry[targetCountryCode, default: []]
                if let regionToOccupy = targetRegions.first(where: { regionOccupations[$0.id] != countryCode }) {
                    regionOccupations[regionToOccupy.id] = countryCode
                    setConflict(
                        region: regionToOccupy,
                        controllerCode: countryCode,
                        mode: .conventionalOccupation,
                        intensity: 3,
                        event: event,
                        summary: eventSummary,
                        targetDate: targetDate,
                        regionConflicts: &regionConflicts
                    )
                }
            case 2:
                let domesticRegions = GeopoliticalMapData.regionsByCountry[countryCode, default: []]
                if let regionToSeize = domesticRegions.first(where: { regionOccupations[$0.id] != "REB" }) {
                    regionOccupations[regionToSeize.id] = "REB"
                    setConflict(
                        region: regionToSeize,
                        controllerCode: "REB",
                        mode: .guerrillaControl,
                        intensity: 4,
                        event: event,
                        summary: eventSummary,
                        targetDate: targetDate,
                        regionConflicts: &regionConflicts
                    )
                }
            case 3:
                let targetRegions = GeopoliticalMapData.regionsByCountry[targetCountryCode, default: []]
                if let regionToDevastate = targetRegions.first(where: { !nuclearFalloutRegions.contains($0.id) }) {
                    nuclearFalloutRegions.append(regionToDevastate.id)
                    setConflict(
                        region: regionToDevastate,
                        controllerCode: regionOccupations[regionToDevastate.id] ?? regionToDevastate.countryCode,
                        mode: .nuclearFallout,
                        intensity: 5,
                        event: event,
                        summary: eventSummary,
                        targetDate: targetDate,
                        regionConflicts: &regionConflicts
                    )
                    if var targetLedger = economicLedgers[targetCountryCode] {
                        targetLedger.securityIndex = max(0.0, targetLedger.securityIndex - 40.0)
                        targetLedger.rebelControlPercent = min(100.0, targetLedger.rebelControlPercent + 10.0)
                        targetLedger.nominalGDPTrillions = max(0.01, targetLedger.nominalGDPTrillions * 0.85)
                        economicLedgers[targetCountryCode] = targetLedger
                    }
                }
            case 4:
                let domesticRegions = GeopoliticalMapData.regionsByCountry[countryCode, default: []]
                if let occupiedRegion = domesticRegions.first(where: { regionOccupations[$0.id] != nil && regionOccupations[$0.id] != countryCode }) {
                    regionOccupations.removeValue(forKey: occupiedRegion.id)
                    setConflict(
                        region: occupiedRegion,
                        controllerCode: countryCode,
                        mode: .stabilization,
                        intensity: 2,
                        event: event,
                        summary: eventSummary,
                        targetDate: targetDate,
                        regionConflicts: &regionConflicts
                    )
                }
            case 5:
                let targetRegions = GeopoliticalMapData.regionsByCountry[targetCountryCode, default: []]
                if let contestedRegion = targetRegions.first {
                    setConflict(
                        region: contestedRegion,
                        controllerCode: countryCode,
                        mode: .contestedBorder,
                        intensity: 3,
                        event: event,
                        summary: eventSummary,
                        targetDate: targetDate,
                        regionConflicts: &regionConflicts
                    )
                }
            case 6:
                let domesticRegions = GeopoliticalMapData.regionsByCountry[countryCode, default: []]
                if let rebelRegion = domesticRegions.first(where: { regionOccupations[$0.id] == "REB" }) {
                    regionOccupations.removeValue(forKey: rebelRegion.id)
                    setConflict(
                        region: rebelRegion,
                        controllerCode: countryCode,
                        mode: .stabilization,
                        intensity: 3,
                        event: event,
                        summary: eventSummary,
                        targetDate: targetDate,
                        regionConflicts: &regionConflicts
                    )
                }
                if var ledger = economicLedgers[countryCode] {
                    ledger.securityIndex = min(100.0, ledger.securityIndex + 12.0)
                    ledger.rebelControlPercent = max(0.0, ledger.rebelControlPercent - 18.0)
                    economicLedgers[countryCode] = ledger
                }
            case 7:
                let targetRegions = GeopoliticalMapData.regionsByCountry[targetCountryCode, default: []]
                for regionToOccupy in targetRegions.prefix(2) {
                    regionOccupations[regionToOccupy.id] = countryCode
                    setConflict(
                        region: regionToOccupy,
                        controllerCode: countryCode,
                        mode: .conventionalOccupation,
                        intensity: 5,
                        event: event,
                        summary: eventSummary,
                        targetDate: targetDate,
                        regionConflicts: &regionConflicts
                    )
                }
            case -1:
                let domesticRegionIDs = GeopoliticalMapData.regionsByCountry[countryCode, default: []].map(\.id)
                for rid in domesticRegionIDs {
                    regionOccupations.removeValue(forKey: rid)
                    if regionConflicts[rid]?.mode != .nuclearFallout {
                        regionConflicts.removeValue(forKey: rid)
                    }
                }
            default:
                break
            }
        }

        for (code, ledger) in economicLedgers {
            if ledger.rebelControlPercent > 65.0 {
                let domesticRegions = GeopoliticalMapData.regionsByCountry[code, default: []]
                let seizureCount = ledger.rebelControlPercent > 82.0 ? 2 : 1
                for regionToSeize in domesticRegions.filter({ regionOccupations[$0.id] != "REB" }).prefix(seizureCount) {
                    regionOccupations[regionToSeize.id] = "REB"
                    regionConflicts[regionToSeize.id] = NativeRegionConflictState(
                        controllerCode: "REB",
                        intensity: ledger.rebelControlPercent > 82.0 ? 5 : 4,
                        mode: .guerrillaControl,
                        originalCountryCode: regionToSeize.countryCode,
                        rebelDelta: ledger.rebelControlPercent,
                        regionID: regionToSeize.id,
                        securityDelta: ledger.securityIndex - 50.0,
                        summary: "Insurgency pressure exceeded public-security capacity.",
                        updatedAt: targetDate
                    )
                }
            } else if ledger.rebelControlPercent < 10.0 {
                let domesticRegions = GeopoliticalMapData.regionsByCountry[code, default: []]
                for reg in domesticRegions where regionOccupations[reg.id] == "REB" {
                    regionOccupations.removeValue(forKey: reg.id)
                    if regionConflicts[reg.id]?.mode == .guerrillaControl {
                        regionConflicts.removeValue(forKey: reg.id)
                    }
                }
            }
        }
    }

    static func setConflict(
        region: MapRegion,
        controllerCode: String,
        mode: NativeRegionConflictMode,
        intensity: Int,
        event: NativeCampaignEvent,
        summary: String,
        targetDate: String,
        regionConflicts: inout [String: NativeRegionConflictState]
    ) {
        regionConflicts[region.id] = NativeRegionConflictState(
            controllerCode: controllerCode,
            intensity: intensity,
            mode: mode,
            originalCountryCode: region.countryCode,
            rebelDelta: event.hexLeverCode.flatMap { NativeHexLever.decodeHexLever($0)?.rebelDelta } ?? 0,
            regionID: region.id,
            securityDelta: event.hexLeverCode.flatMap { NativeHexLever.decodeHexLever($0)?.securityDelta } ?? 0,
            sourceEventID: event.id,
            summary: summary,
            updatedAt: targetDate
        )
    }

    public static func conflictNudgeLabel(for value: Int) -> String {
        switch value {
        case 1: "conventional occupation (1 region)"
        case 2: "guerrilla mobilization"
        case 3: "nuclear fallout contamination"
        case 4: "regional pacification"
        case 5: "contested border escalation"
        case 6: "stabilization campaign"
        case 7: "conventional occupation (2 regions)"
        case -1: "complete demilitarization"
        default: "neutral operations"
        }
    }
}
