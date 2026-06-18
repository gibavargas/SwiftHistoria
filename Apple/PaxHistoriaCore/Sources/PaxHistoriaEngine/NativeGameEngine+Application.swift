import Foundation
import PaxHistoriaModels

extension NativeGameEngine {
    public static func apply(
        _ generated: NativeGeneratedTurn,
        state: NativeCampaignState,
        months: Int
    ) -> NativeCampaignState {
        let targetDate = advance(date: state.gameDate, months: months)
        var generatedEvents = generated.events.enumerated().map { index, event in
            normalized(event, index: index, targetDate: targetDate, country: state.country)
        }
        let isTesting = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil || NSClassFromString("XCTestCase") != nil
        if !isTesting || force512DiceFrictionForTesting {
            let pollutionEvents = roll512DiceFriction(
                scenarioID: state.scenarioID,
                gameDate: targetDate,
                round: state.round,
                playerCountryCode: state.country.code
            )
            generatedEvents.append(contentsOf: pollutionEvents)
        }
        let linkedActionIDs = Set(generatedEvents.flatMap(\.linkedActionIDs))
        let invasionActionIDs = Set(state.plannedActions
            .filter { $0.status == .planned && $0.title.hasPrefix("Invade ") }
            .map(\.id))
        var resolvedActions = state.plannedActions.map { action in
            guard linkedActionIDs.contains(action.id),
                  action.status == .planned,
                  !invasionActionIDs.contains(action.id) else { return action }
            var next = action
            next.status = .resolved
            next.resolvedAt = targetDate
            return next
        }

        var nextRegionOccupations = state.regionOccupations
        var nextNuclearRegions = state.nuclearFalloutRegions
        var nextRegionConflicts = state.regionConflicts

        var additionalEvents: [NativeCampaignEvent] = []
        for idx in 0 ..< resolvedActions.count {
            let action = resolvedActions[idx]
            if action.status == .planned, action.title.hasPrefix("Invade ") {
                if let range = action.title.range(of: "(ID: "),
                   let endRange = action.title.range(of: ")", range: range.upperBound ..< action.title.endIndex)
                {
                    let regionID = String(action.title[range.upperBound ..< endRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if let region = GeopoliticalMapData.regionByID[regionID] {
                        let defenderCode = state.regionOccupations[region.id] ?? region.countryCode

                        let attackerDiceCount: Int = {
                            if state.budgetMilitarySlider > 0.6 { return 3 }
                            if state.budgetMilitarySlider > 0.3 { return 2 }
                            return 1
                        }()
                        let attackerModifier = state.budgetMilitarySlider > 0.8 ? 1 : 0

                        let defenderDiceCount: Int = {
                            if defenderCode == state.country.code {
                                return state.budgetMilitarySlider > 0.4 ? 2 : 1
                            } else {
                                if state.aiCountryStates[defenderCode]?.budgetPriority == .military { return 2 }
                                return 1
                            }
                        }()
                        let defenderModifier: Int = if defenderCode == state.country.code {
                            state.budgetMilitarySlider > 0.8 ? 1 : 0
                        } else {
                            state.aiCountryStates[defenderCode]?.budgetPriority == .military ? 1 : 0
                        }

                        let terrainModifier = switch region.terrain {
                        case .mountain, .strait, .ocean, .sea: 2
                        case .swamp, .forest, .city, .cerrado: 1
                        default: 0
                        }

                        let seed = [action.id, region.id, state.gameDate].joined(separator: "|")
                        let attackerRawRolls = rollDice(seed: seed + "-atk", count: attackerDiceCount)
                        let defenderRawRolls = rollDice(seed: seed + "-def", count: defenderDiceCount)

                        let attackerModifiedRolls = attackerRawRolls.map { $0 + attackerModifier }
                        let defenderModifiedRolls = defenderRawRolls.map { $0 + defenderModifier + terrainModifier }

                        let attackerSorted = attackerModifiedRolls.sorted(by: >)
                        let defenderSorted = defenderModifiedRolls.sorted(by: >)

                        let matchCount = min(attackerSorted.count, defenderSorted.count)
                        var attackerWins = 0
                        var defenderWins = 0
                        var matchupDetails: [String] = []

                        for i in 0 ..< matchCount {
                            let aVal = attackerSorted[i]
                            let dVal = defenderSorted[i]
                            if aVal > dVal {
                                attackerWins += 1
                                matchupDetails.append("\(aVal) vs \(dVal) (Attacker Wins)")
                            } else {
                                defenderWins += 1
                                matchupDetails.append("\(aVal) vs \(dVal) (Defender Wins)")
                            }
                        }

                        let isSuccess = attackerWins > defenderWins
                        let defenderName = state.aiCountryStates[defenderCode]?.countryCode ?? defenderCode
                        let battleLog = "Dice Battle for \(region.name): Attacker rolled \(attackerRawRolls) (Mil: +\(attackerModifier) -> \(attackerSorted)). Defender \(defenderName) rolled \(defenderRawRolls) (Terrain: +\(terrainModifier), Mil: +\(defenderModifier) -> \(defenderSorted)). Matchups: \(matchupDetails.joined(separator: ", "))."

                        var next = action
                        next.status = .resolved
                        next.resolvedAt = targetDate
                        resolvedActions[idx] = next

                        if isSuccess {
                            nextRegionOccupations[region.id] = state.country.code
                            nextRegionConflicts[region.id] = NativeRegionConflictState(
                                controllerCode: state.country.code,
                                intensity: 3,
                                mode: .conventionalOccupation,
                                originalCountryCode: region.countryCode,
                                regionID: region.id,
                                summary: "Successful border conquest. \(battleLog)",
                                updatedAt: targetDate
                            )

                            let successEvent = NativeCampaignEvent(
                                date: targetDate,
                                description: "Conquest of \(region.name) Successful. Our forces advanced through the \(region.terrain.displayName.lowercased()) terrain of \(region.name) and secured tactical control. \(battleLog)",
                                id: "invasion-success-\(region.id)-\(targetDate)",
                                importance: .major,
                                kind: .action,
                                linkedActionIDs: [action.id],
                                notable: true,
                                playerRelated: true,
                                strategicEffects: [
                                    NativeStrategicEffect(
                                        date: targetDate,
                                        eventId: "invasion-success-\(region.id)-\(targetDate)",
                                        id: "invasion-success-effect-\(region.id)-\(targetDate)",
                                        magnitude: 1,
                                        summary: "Sovereign advance raises domestic stability.",
                                        target: state.country.code,
                                        track: .internalStability
                                    )
                                ],
                                title: "Conquest of \(region.name) Successful"
                            )
                            additionalEvents.append(successEvent)
                        } else {
                            nextRegionConflicts[region.id] = NativeRegionConflictState(
                                controllerCode: state.regionOccupations[region.id] ?? region.countryCode,
                                intensity: 4,
                                mode: .contestedBorder,
                                originalCountryCode: region.countryCode,
                                regionID: region.id,
                                summary: "Invasion repelled. \(battleLog)",
                                updatedAt: targetDate
                            )

                            let failEvent = NativeCampaignEvent(
                                date: targetDate,
                                description: "Invasion of \(region.name) Repelled. Defensive forces utilized the local \(region.terrain.displayName.lowercased()) terrain to stall and repel our advance. \(battleLog)",
                                id: "invasion-fail-\(region.id)-\(targetDate)",
                                importance: .severe,
                                kind: .crisis,
                                linkedActionIDs: [action.id],
                                notable: true,
                                playerRelated: true,
                                strategicEffects: [
                                    NativeStrategicEffect(
                                        date: targetDate,
                                        eventId: "invasion-fail-\(region.id)-\(targetDate)",
                                        id: "invasion-fail-effect-\(region.id)-\(targetDate)",
                                        magnitude: -2,
                                        summary: "Military repulse inflicts domestic stability setback.",
                                        target: state.country.code,
                                        track: .internalStability
                                    )
                                ],
                                title: "Invasion of \(region.name) Repelled"
                            )
                            additionalEvents.append(failEvent)
                        }
                    }
                }
            }
        }

        generatedEvents.insert(contentsOf: additionalEvents, at: 0)
        let allEffects = generatedEvents.flatMap(\.strategicEffects)
        let economicLedgers = updatedEconomicLedgers(
            from: state.economicLedgers,
            state: state,
            events: generatedEvents,
            months: months,
            targetDate: targetDate
        )

        var mutableLedgers = economicLedgers

        processTacticalNudges(
            events: generatedEvents,
            state: state,
            targetDate: targetDate,
            regionOccupations: &nextRegionOccupations,
            nuclearFalloutRegions: &nextNuclearRegions,
            regionConflicts: &nextRegionConflicts,
            economicLedgers: &mutableLedgers
        )

        let actionMemory = updatedActionMemory(
            state: state,
            resolvedActions: resolvedActions,
            events: generatedEvents,
            targetDate: targetDate
        )

        var nextAICountryStates = state.aiCountryStates
        if nextAICountryStates.isEmpty {
            nextAICountryStates = NativeAICountryState.initialAICountryStates(for: state.scenarioID, strategicCountryCodes: NativeCampaignState.defaultStrategicCountryCodes)
        }

        for event in generatedEvents {
            guard let hex = event.hexLeverCode,
                  let lever = NativeHexLever.decodeHexLever(hex)
            else {
                continue
            }

            let actorCode = resolvedCountryCode(
                from: event.strategicEffects.first?.target ?? state.country.code,
                fallback: state.country.code
            )
            let rivalCode = getRivalCountryCode(for: actorCode)

            var delta = 0
            switch lever.invasionNudge {
            case 1, 7:
                delta = -50
            case 2:
                delta = -15
            case 3:
                delta = -90
            case 5:
                delta = -30
            case 4, 6, -1:
                delta = 10
            default:
                break
            }

            if delta != 0 {
                if var actorState = nextAICountryStates[actorCode] {
                    let currentScore = actorState.relationshipScores[rivalCode] ?? 0
                    actorState.relationshipScores[rivalCode] = Swift.max(-100, Swift.min(100, currentScore + delta))
                    nextAICountryStates[actorCode] = actorState
                }
                if var rivalState = nextAICountryStates[rivalCode] {
                    let currentScore = rivalState.relationshipScores[actorCode] ?? 0
                    rivalState.relationshipScores[actorCode] = Swift.max(-100, Swift.min(100, currentScore + delta))
                    nextAICountryStates[rivalCode] = rivalState
                }
            }
        }

        let negativeMultiplier = switch state.gameMode {
        case .sandbox: 0.5
        case .normal: 1.0
        case .ironman: 2.0
        }

        let rawStabilityDelta = generated.stabilityDelta
        let adjStabilityDelta = rawStabilityDelta < 0 ? Int((Double(rawStabilityDelta) * negativeMultiplier).rounded()) : rawStabilityDelta

        let rawTensionDelta = generated.worldTensionDelta
        let adjTensionDelta = rawTensionDelta > 0 ? Int((Double(rawTensionDelta) * negativeMultiplier).rounded()) : rawTensionDelta

        let occupiedCount = nextRegionOccupations.filter { key, val in
            let reg = GeopoliticalMapData.regionByID[key]
            return reg?.countryCode == state.country.code && val != state.country.code
        }.count

        let falloutCount = nextNuclearRegions.filter { rid in
            let reg = GeopoliticalMapData.regionByID[rid]
            return reg?.countryCode == state.country.code
        }.count

        let falloutStabilityHit = falloutCount * 2

        let playerLedgerForStability = mutableLedgers[state.country.code] ?? state.economicLedger
        let inflationStabilityHit = playerLedgerForStability.inflationPercent > 10.0 ? Int((playerLedgerForStability.inflationPercent - 10.0) * 0.2) : 0
        let growthStabilityHit = playerLedgerForStability.realGrowthPercent < 0.0 ? Int(-playerLedgerForStability.realGrowthPercent * 0.5) : 0
        let growthStabilityBoost = playerLedgerForStability.realGrowthPercent > 5.0 ? Int(playerLedgerForStability.realGrowthPercent * 0.1) : 0
        let securityStabilityBoost = playerLedgerForStability.securityIndex > 80.0 ? 1 : 0
        let securityStabilityHit = playerLedgerForStability.securityIndex < 40.0 ? Int((40.0 - playerLedgerForStability.securityIndex) * 0.15) : 0
        let feedbackStabilityChange = growthStabilityBoost + securityStabilityBoost - inflationStabilityHit - growthStabilityHit - securityStabilityHit

        var targetStability = clamp(state.stability + adjStabilityDelta - falloutStabilityHit + feedbackStabilityChange + allEffects.filter { $0.track == .internalStability }.map(\.magnitude).reduce(0, +))
        var nextVictoryStatus = state.victoryStatus
        var finalLedgers = mutableLedgers

        if occupiedCount > 0 || falloutCount > 0 {
            if var playerLedger = finalLedgers[state.country.code] {
                let occupiedGrowthHit = -0.5 * Double(occupiedCount)
                let occupiedSecurityHit = -2.0 * Double(occupiedCount)
                let falloutGrowthHit = -2.0 * Double(falloutCount)
                let falloutInflationHit = 3.0 * Double(falloutCount)

                playerLedger.realGrowthPercent = clampDouble(playerLedger.realGrowthPercent + occupiedGrowthHit + falloutGrowthHit, -12, 16)
                playerLedger.securityIndex = clampDouble(playerLedger.securityIndex + occupiedSecurityHit, 0, 100)
                playerLedger.inflationPercent = clampDouble(playerLedger.inflationPercent + falloutInflationHit, 0, 100)

                let penaltyEntry = NativeEconomicLedgerEntry(
                    budgetBalanceDelta: 0.0,
                    debtDelta: 0.0,
                    eventID: "occupation-fallout-\(targetDate)",
                    fiscalSpaceDelta: 0,
                    growthDelta: occupiedGrowthHit + falloutGrowthHit,
                    id: "ledger-entry-penalty-\(UUID().uuidString.lowercased())",
                    inflationDelta: falloutInflationHit,
                    ruleID: "territorial-crisis",
                    summary: "Penalties from \(occupiedCount) occupied / \(falloutCount) fallout regions",
                    tradeBalanceDelta: 0.0,
                    turnDate: targetDate,
                    securityDelta: occupiedSecurityHit,
                    rebelDelta: 0.0
                )
                playerLedger.entries.insert(penaltyEntry, at: 0)
                finalLedgers[state.country.code] = playerLedger
            }
        }

        if targetStability <= 0 {
            targetStability = 0
            nextVictoryStatus = .lostCollapse
            let collapseEvent = NativeCampaignEvent(
                date: targetDate,
                description: "COLLAPSE: Government authority has completely dissolved. The nation has entered a period of total anarchic collapse.",
                id: "stability-collapse-\(targetDate)-\(UUID().uuidString.lowercased())",
                importance: .severe,
                kind: .crisis,
                linkedActionIDs: [],
                notable: true,
                playerRelated: true,
                strategicEffects: [],
                title: "NATION COLLAPSED"
            )
            generatedEvents.insert(collapseEvent, at: 0)
        } else if targetStability < 20 {
            if var playerLedger = finalLedgers[state.country.code] {
                playerLedger.realGrowthPercent = clampDouble(playerLedger.realGrowthPercent - 1.0, -12, 16)
                playerLedger.rebelControlPercent = clampDouble(playerLedger.rebelControlPercent + 3.0, 0, 100)
                playerLedger.inflationPercent = clampDouble(playerLedger.inflationPercent + 2.0, 0, 100)

                let crisisEntry = NativeEconomicLedgerEntry(
                    budgetBalanceDelta: 0.0,
                    debtDelta: 0.0,
                    eventID: "crisis-\(targetDate)",
                    fiscalSpaceDelta: 0,
                    growthDelta: -1.0,
                    id: "ledger-entry-crisis-\(UUID().uuidString.lowercased())",
                    inflationDelta: 2.0,
                    ruleID: "stability-crisis",
                    summary: "Economic drag from stability crisis",
                    tradeBalanceDelta: 0.0,
                    turnDate: targetDate,
                    securityDelta: 0.0,
                    rebelDelta: 3.0
                )
                playerLedger.entries.insert(crisisEntry, at: 0)
                finalLedgers[state.country.code] = playerLedger
            }

            let crisisEvent = NativeCampaignEvent(
                date: targetDate,
                description: "CRISIS ALERT: Stability is dangerously low (\(targetStability)%). Severe civil unrest, supply chain bottlenecks, and hyperinflation have been triggered across the nation.",
                id: "stability-crisis-\(targetDate)-\(UUID().uuidString.lowercased())",
                importance: .severe,
                kind: .crisis,
                linkedActionIDs: [],
                notable: true,
                playerRelated: true,
                strategicEffects: [],
                title: "CRISIS: Stability Below 20%"
            )
            generatedEvents.insert(crisisEvent, at: 0)
        }

        let baseRefill = 100
        let stabilityPenalty = Int(Double(100 - targetStability) * 0.4)
        var rebelPenalty = 0
        if let playerLedger = finalLedgers[state.country.code] {
            rebelPenalty = Int(playerLedger.rebelControlPercent)
        }
        var servicesBonus = 0
        if state.budgetServicesSlider > 0.40 {
            servicesBonus = 15
        } else if state.budgetServicesSlider < 0.20 {
            servicesBonus = -15
        }
        let refillAmount = baseRefill - stabilityPenalty - rebelPenalty + servicesBonus
        let nextCapacity = max(20, min(120, refillAmount))

        let activeConflictsCount = nextRegionConflicts.count
        let armsRaceEscalation = state.budgetMilitarySlider > 0.40 ? 2 : 0
        let globalFalloutCount = nextNuclearRegions.count
        let globalOccupiedCount = nextRegionOccupations.filter { key, val in
            let reg = GeopoliticalMapData.regionByID[key]
            return reg?.countryCode == state.country.code && val != state.country.code
        }.count
        let nuclearFalloutEscalation = globalFalloutCount * 5
        let imperialFrictionEscalation = globalOccupiedCount * 1
        let tensionEscalation = activeConflictsCount + armsRaceEscalation + nuclearFalloutEscalation + imperialFrictionEscalation

        var nextActiveTreaties = state.activeTreaties
        if nextActiveTreaties.isEmpty {
            let acceptedOffers = state.activeOffers.filter { $0.status == .accepted }
            for offer in acceptedOffers {
                let signatoryA = state.country.code
                let signatoryB = offer.proposerCode

                var obligations: [NativeObligation] = []
                switch offer.type {
                case .militaryAlliance:
                    obligations.append(NativeObligation(
                        id: "obg-migrated-\(UUID().uuidString.lowercased())",
                        type: .nonAggression,
                        description: "Non-Aggression Obligation: Signatories \(signatoryA) and \(signatoryB) must not occupy or invade each other's regions.",
                        value: 0
                    ))
                    obligations.append(NativeObligation(
                        id: "obg-migrated-\(UUID().uuidString.lowercased())",
                        type: .mutualDefense,
                        description: "Mutual Defense Obligation: Signatories \(signatoryA) and \(signatoryB) must support each other in external conflicts.",
                        value: 0.5
                    ))
                case .tradeAgreement:
                    obligations.append(NativeObligation(
                        id: "obg-migrated-\(UUID().uuidString.lowercased())",
                        type: .tradeCooperation,
                        description: "Trade Cooperation Obligation: Signatories \(signatoryA) and \(signatoryB) will reduce trade barriers and boost mutual growth.",
                        value: 0.1
                    ))
                case .nonAggressionPact:
                    obligations.append(NativeObligation(
                        id: "obg-migrated-\(UUID().uuidString.lowercased())",
                        type: .nonAggression,
                        description: "Non-Aggression Obligation: Signatories \(signatoryA) and \(signatoryB) agree to resolve disputes peacefully and avoid aggression.",
                        value: 0.2
                    ))
                case .territoryDemarcation:
                    obligations.append(NativeObligation(
                        id: "obg-migrated-\(UUID().uuidString.lowercased())",
                        type: .demilitarization,
                        description: "Demilitarization Obligation: Signatories \(signatoryA) and \(signatoryB) agree to keep border zones free of active conflict.",
                        value: 0
                    ))
                }

                let migrated = NativeTreaty(
                    id: "treaty-migrated-\(offer.id)",
                    name: offer.type.displayName,
                    signatoryA: signatoryA,
                    signatoryB: signatoryB,
                    type: offer.type,
                    signatureDate: state.gameDate,
                    obligations: obligations,
                    termMonths: 24,
                    elapsedMonths: 0,
                    isActive: true
                )
                nextActiveTreaties.append(migrated)
            }
        }
        for idx in 0 ..< nextActiveTreaties.count {
            guard nextActiveTreaties[idx].isActive else { continue }
            var treaty = nextActiveTreaties[idx]

            treaty.elapsedMonths += months
            if treaty.termMonths > 0, treaty.elapsedMonths >= treaty.termMonths {
                treaty.isActive = false
                let expireEvent = NativeCampaignEvent(
                    date: targetDate,
                    description: "TREATY EXPIRED: The \(treaty.name) between \(treaty.signatoryA) and \(treaty.signatoryB) has run its full term and expired peacefully.",
                    id: "treaty-expire-\(treaty.id)-\(UUID().uuidString.lowercased())",
                    importance: .minor,
                    kind: .diplomacy,
                    linkedActionIDs: [],
                    notable: false,
                    playerRelated: treaty.signatoryA == state.country.code || treaty.signatoryB == state.country.code,
                    strategicEffects: [],
                    title: "Treaty Expired: \(treaty.name)"
                )
                generatedEvents.append(expireEvent)
                nextActiveTreaties[idx] = treaty
                continue
            }

            var isViolated = false
            var violationDescription = ""
            var violatorCode = ""
            var victimCode = ""

            for obligation in treaty.obligations {
                switch obligation.type {
                case .nonAggression:
                    for (rid, controller) in nextRegionOccupations {
                        let originalOwner = NativeRegionConflictState.countryCode(fromLegacyRegionID: rid)
                        if originalOwner == treaty.signatoryA, controller == treaty.signatoryB {
                            isViolated = true
                            violatorCode = treaty.signatoryB
                            victimCode = treaty.signatoryA
                            violationDescription = "by occupying region \(rid)"
                            break
                        }
                        if originalOwner == treaty.signatoryB, controller == treaty.signatoryA {
                            isViolated = true
                            violatorCode = treaty.signatoryA
                            victimCode = treaty.signatoryB
                            violationDescription = "by occupying region \(rid)"
                            break
                        }
                    }

                    if !isViolated {
                        for (rid, conflict) in nextRegionConflicts {
                            if conflict.mode == .contestedBorder || conflict.mode == .conventionalOccupation {
                                if conflict.originalCountryCode == treaty.signatoryA, conflict.controllerCode == treaty.signatoryB {
                                    isViolated = true
                                    violatorCode = treaty.signatoryB
                                    victimCode = treaty.signatoryA
                                    violationDescription = "by initiating military operations in region \(rid)"
                                    break
                                }
                                if conflict.originalCountryCode == treaty.signatoryB, conflict.controllerCode == treaty.signatoryA {
                                    isViolated = true
                                    violatorCode = treaty.signatoryA
                                    victimCode = treaty.signatoryB
                                    violationDescription = "by initiating military operations in region \(rid)"
                                    break
                                }
                            }
                        }
                    }

                case .demilitarization:
                    if let targetReg = obligation.targetRegion {
                        if let conflict = nextRegionConflicts[targetReg] {
                            if conflict.mode == .conventionalOccupation || conflict.mode == .contestedBorder {
                                isViolated = true
                                violatorCode = conflict.controllerCode
                                victimCode = violatorCode == treaty.signatoryA ? treaty.signatoryB : treaty.signatoryA
                                violationDescription = "by militarizing the designated zone \(targetReg)"
                            }
                        }
                    }

                case .tradeCooperation:
                    let relScore = nextAICountryStates[treaty.signatoryB]?.relationshipScores[treaty.signatoryA] ?? 100
                    if relScore < -30 {
                        isViolated = true
                        violatorCode = treaty.signatoryB
                        victimCode = treaty.signatoryA
                        violationDescription = "due to a severe diplomatic breakdown"
                    }

                default:
                    break
                }

                if isViolated { break }
            }

            if isViolated {
                treaty.isActive = false

                if violatorCode == state.country.code {
                    targetStability = max(0, targetStability - 20)
                } else {
                    if var violatorState = nextAICountryStates[violatorCode] {
                        let curRel = violatorState.relationshipScores[state.country.code] ?? 0
                        violatorState.relationshipScores[state.country.code] = max(-100, curRel - 30)
                        nextAICountryStates[violatorCode] = violatorState
                    }
                }

                if var stateA = nextAICountryStates[treaty.signatoryA] {
                    let cur = stateA.relationshipScores[treaty.signatoryB] ?? 0
                    stateA.relationshipScores[treaty.signatoryB] = max(-100, cur - 40)
                    nextAICountryStates[treaty.signatoryA] = stateA
                }
                if var stateB = nextAICountryStates[treaty.signatoryB] {
                    let cur = stateB.relationshipScores[treaty.signatoryA] ?? 0
                    stateB.relationshipScores[treaty.signatoryA] = max(-100, cur - 40)
                    nextAICountryStates[treaty.signatoryB] = stateB
                }

                let breachEvent = NativeCampaignEvent(
                    date: targetDate,
                    description: "TREATY VIOLATION: \(violatorCode) has breached the terms of the \(treaty.name) treaty with \(victimCode) \(violationDescription). The treaty is nullified, causing a severe diplomatic crisis.",
                    id: "treaty-breach-\(treaty.id)-\(UUID().uuidString.lowercased())",
                    importance: .severe,
                    kind: .diplomacy,
                    linkedActionIDs: [],
                    notable: true,
                    playerRelated: treaty.signatoryA == state.country.code || treaty.signatoryB == state.country.code,
                    strategicEffects: [],
                    title: "Treaty Breached: \(treaty.name)"
                )
                generatedEvents.append(breachEvent)
            }

            nextActiveTreaties[idx] = treaty
        }

        var nextDynamicCountries = state.dynamicCountries
        processSovereigntyChanges(
            events: generatedEvents,
            state: state,
            targetDate: targetDate,
            dynamicCountries: &nextDynamicCountries,
            regionOccupations: &nextRegionOccupations,
            regionConflicts: &nextRegionConflicts,
            aiCountryStates: &nextAICountryStates,
            economicLedgers: &finalLedgers
        )

        var finalState = NativeCampaignState(
            actionMemory: actionMemory,
            advisorMessages: state.advisorMessages,
            aiReadiness: .available(tokenBudget: "guided-generation context=4096, maxResponse=760"),
            country: state.country,
            diplomaticThreads: state.diplomaticThreads,
            dynamicCountries: nextDynamicCountries,
            economicLedger: finalLedgers[state.country.code] ?? state.economicLedger,
            economicLedgers: finalLedgers,
            aiCountryStates: nextAICountryStates,
            gameDate: targetDate,
            gameMode: state.gameMode,
            lastSummary: sanitizeFoundationModelText(generated.summary),
            language: state.language,
            plannedActions: resolvedActions,
            round: state.round + 1,
            scenarioDescription: state.scenarioDescription,
            scenarioID: state.scenarioID,
            scenarioName: state.scenarioName,
            semanticMemory: state.semanticMemory,
            suggestedActions: [],
            stability: targetStability,
            startDate: state.startDate,
            timeline: generatedEvents + state.timeline,
            worldTension: clamp(state.worldTension + adjTensionDelta + tensionEscalation + allEffects.filter { $0.track == .worldTension || $0.track == .securityAnxiety }.map(\.magnitude).reduce(0, +)),
            worldEffects: allEffects + state.worldEffects,
            regionOccupations: nextRegionOccupations,
            nuclearFalloutRegions: nextNuclearRegions,
            regionConflicts: nextRegionConflicts,
            administrativeCapacity: nextCapacity,
            victoryStatus: nextVictoryStatus,
            activeOffers: state.activeOffers,
            activeTreaties: nextActiveTreaties,
            budgetMilitarySlider: state.budgetMilitarySlider,
            budgetServicesSlider: state.budgetServicesSlider,
            budgetDiplomacySlider: state.budgetDiplomacySlider
        )

        if finalState.victoryStatus == NativeVictoryStatus.ongoing {
            finalState.victoryStatus = evaluateVictoryStatus(for: finalState)
            if finalState.victoryStatus == NativeVictoryStatus.won {
                let winEvent = NativeCampaignEvent(
                    date: targetDate,
                    description: "VICTORY: Your administration successfully achieved all objectives for scenario \(state.scenarioName)!",
                    id: "victory-\(targetDate)-\(UUID().uuidString.lowercased())",
                    importance: .major,
                    kind: .world,
                    linkedActionIDs: [],
                    notable: true,
                    playerRelated: true,
                    strategicEffects: [],
                    title: "CAMPAIGN VICTORY ACHIEVED"
                )
                finalState.timeline.insert(winEvent, at: 0)
            } else if finalState.victoryStatus == NativeVictoryStatus.lostTimeout {
                let timeoutEvent = NativeCampaignEvent(
                    date: targetDate,
                    description: "DEFEAT: Time has run out. Your administration failed to meet the objectives by the deadline.",
                    id: "timeout-\(targetDate)-\(UUID().uuidString.lowercased())",
                    importance: .severe,
                    kind: .world,
                    linkedActionIDs: [],
                    notable: true,
                    playerRelated: true,
                    strategicEffects: [],
                    title: "CAMPAIGN DEADLINE EXCEEDED"
                )
                finalState.timeline.insert(timeoutEvent, at: 0)
            }
        }

        simulateAIDrift(state: &finalState, months: months)
        finalState.semanticMemory = updatedSemanticMemory(
            state: finalState,
            events: Array(finalState.timeline.prefix(generatedEvents.count + 2))
        )
        return finalState
    }

    private static func processSovereigntyChanges(
        events: [NativeCampaignEvent],
        state: NativeCampaignState,
        targetDate: String,
        dynamicCountries: inout [String: String],
        regionOccupations: inout [String: String],
        regionConflicts: inout [String: NativeRegionConflictState],
        aiCountryStates: inout [String: NativeAICountryState],
        economicLedgers: inout [String: NativeEconomicLedger]
    ) {
        for event in events {
            guard var change = event.sovereigntyChange else { continue }
            change.targetCode = normalizedCountryCode(change.targetCode)
            change.sourceCodes = change.sourceCodes.map(normalizedCountryCode).filter { !$0.isEmpty }
            change.name = sanitizeFoundationModelText(change.name)
            let targetCode = change.targetCode.isEmpty ? normalizedCountryCode(String(change.name.prefix(3))) : change.targetCode
            guard !targetCode.isEmpty else { continue }
            let affectedRegions = sovereigntyRegions(for: change, state: state, targetCode: targetCode)

            switch change.kind {
            case .secession, .newCountry:
                dynamicCountries[targetCode] = change.name.isEmpty ? targetCode : change.name
                ensureLedger(for: targetCode, basedOn: change.sourceCodes.first ?? state.country.code, state: state, economicLedgers: &economicLedgers)
                ensureAIState(for: targetCode, sourceCodes: change.sourceCodes, state: state, aiCountryStates: &aiCountryStates)
                for region in affectedRegions {
                    regionOccupations[region.id] = targetCode
                    setConflict(region: region, controllerCode: targetCode, mode: NativeRegionConflictMode.contestedBorder, intensity: 3, event: event, summary: "\(event.title): \(dynamicCountries[targetCode] ?? targetCode) gains separate political control.", targetDate: targetDate, regionConflicts: &regionConflicts)
                }
            case .merge:
                dynamicCountries[targetCode] = change.name.isEmpty ? (dynamicCountries[targetCode] ?? targetCode) : change.name
                ensureLedger(for: targetCode, basedOn: change.sourceCodes.first ?? targetCode, state: state, economicLedgers: &economicLedgers)
                ensureAIState(for: targetCode, sourceCodes: change.sourceCodes, state: state, aiCountryStates: &aiCountryStates)
                for source in change.sourceCodes where source != targetCode {
                    dynamicCountries.removeValue(forKey: source)
                    aiCountryStates.removeValue(forKey: source)
                    for (regionID, controller) in regionOccupations where controller == source {
                        regionOccupations[regionID] = targetCode
                    }
                    for (regionID, conflict) in regionConflicts where conflict.controllerCode == source {
                        regionConflicts[regionID]?.controllerCode = targetCode
                    }
                }
            case .dissolution:
                dynamicCountries.removeValue(forKey: targetCode)
                aiCountryStates.removeValue(forKey: targetCode)
                for region in affectedRegions {
                    regionOccupations[region.id] = "REB"
                    setConflict(region: region, controllerCode: "REB", mode: NativeRegionConflictMode.guerrillaControl, intensity: 4, event: event, summary: "\(event.title): local control fragments after state dissolution.", targetDate: targetDate, regionConflicts: &regionConflicts)
                }
            }
        }
    }

    private static func normalizedCountryCode(_ value: String) -> String {
        let code = value.uppercased().filter { $0 >= "A" && $0 <= "Z" }
        return String(code.prefix(6))
    }

    private static func sovereigntyRegions(
        for change: NativeSovereigntyChange,
        state: NativeCampaignState,
        targetCode _: String
    ) -> [MapRegion] {
        let explicit = change.regionIDs.compactMap { GeopoliticalMapData.regionByID[$0] }
        if !explicit.isEmpty { return explicit }
        for source in change.sourceCodes {
            let sourceRegions = GeopoliticalMapData.regionsByCountry[source, default: []]
            if let first = sourceRegions.first {
                return [first]
            }
        }
        return GeopoliticalMapData.regionsByCountry[state.country.code, default: []].prefix(1).map(\.self)
    }

    private static func ensureLedger(
        for code: String,
        basedOn sourceCode: String,
        state: NativeCampaignState,
        economicLedgers: inout [String: NativeEconomicLedger]
    ) {
        guard economicLedgers[code] == nil else { return }
        let scenario = NativeScenarioCatalog.scenario(for: state.scenarioID)
        economicLedgers[code] = economicLedgers[sourceCode] ??
            NativeEconomicLedger.starting(forCode: code, scenario: scenario)
    }

    private static func ensureAIState(
        for code: String,
        sourceCodes: [String],
        state: NativeCampaignState,
        aiCountryStates: inout [String: NativeAICountryState]
    ) {
        guard aiCountryStates[code] == nil else { return }
        var relationships = aiCountryStates[sourceCodes.first ?? ""]?.relationshipScores ?? [:]
        relationships[state.country.code] = min(relationships[state.country.code] ?? 0, -10)
        aiCountryStates[code] = NativeAICountryState(
            countryCode: code,
            doctrine: .defensive,
            budgetPriority: .stability,
            relationshipScores: relationships,
            multiTurnAgenda: "Secure recognition, basic state capacity, and defensible borders.",
            agendaProgress: 10
        )
    }

    static func resolvedCountryCode(from value: String, fallback: String) -> String {
        let text = value.lowercased()
        if let match = CountryCatalog.all.first(where: { country in
            countryAliases(for: country.code).contains { alias in
                !alias.isEmpty && text.contains(alias)
            }
        }) {
            return match.code
        }
        return fallback
    }

    static func countryAliases(for code: String) -> [String] {
        switch code.uppercased() {
        case "USA": ["usa", "united states", "america", "washington"]
        case "CHN": ["chn", "china", "beijing", "chinese"]
        case "RUS": ["rus", "russia", "moscow", "russian"]
        case "DEU": ["deu", "germany", "berlin", "german"]
        case "FRA": ["fra", "france", "paris", "french"]
        case "GBR": ["gbr", "united kingdom", "london", "british", "uk"]
        case "JPN": ["jpn", "japan", "tokyo", "japanese"]
        case "BRA": ["bra", "brazil", "brasilia", "brazilian"]
        case "IND": ["ind", "india", "delhi", "indian"]
        case "ZAF": ["zaf", "south africa", "pretoria", "african"]
        case "AUS": ["aus", "australia", "canberra", "australian"]
        default: [code.lowercased()]
        }
    }

    static func getRivalCountryCode(for countryCode: String) -> String {
        switch countryCode {
        case "USA": "RUS"
        case "CHN": "USA"
        case "BRA": "USA"
        case "DEU": "RUS"
        case "JPN": "CHN"
        case "GBR": "RUS"
        case "FRA": "RUS"
        case "IND": "CHN"
        case "RUS": "USA"
        case "ZAF": "GLOBAL"
        case "AUS": "CHN"
        default: "USA"
        }
    }

    public static func evaluateVictoryStatus(for state: NativeCampaignState) -> NativeVictoryStatus {
        let activeScore = state.economicLedger.securityIndex
        let targetEnd = state.startDate

        let formatter = ISO8601DateFormatter()
        guard let start = formatter.date(from: targetEnd + "T00:00:00Z") else {
            return .ongoing
        }
        guard let current = displayFormatter.date(from: state.gameDate) else {
            return .ongoing
        }

        let elapsed = Calendar.current.dateComponents([.month], from: start, to: current).month ?? 0
        let isTimeout = elapsed >= 120

        if activeScore >= 90.0 {
            return NativeVictoryStatus.won
        }
        if isTimeout {
            return NativeVictoryStatus.lostTimeout
        }
        return NativeVictoryStatus.ongoing
    }

    private static func clampDouble(_ value: Double, _ lower: Double, _ upper: Double) -> Double {
        min(upper, max(lower, value))
    }

    private static func getYear(from dateString: String) -> Int? {
        let parts = dateString.components(separatedBy: "-")
        guard let first = parts.first, let val = Int(first) else { return nil }
        return val
    }

    static func normalized(_ event: NativeCampaignEvent, index: Int, targetDate: String, country: PlayerCountry) -> NativeCampaignEvent {
        var next = event
        if next.id.isEmpty {
            next.id = "generated-\(targetDate)-\(index)"
        }
        if next.date.isEmpty {
            next.date = targetDate
        }
        if next.title.isEmpty {
            next.title = next.playerRelated ? "\(country.name) faces a new decision point" : "The international system shifts"
        }
        next.title = sanitizeFoundationModelText(next.title)
        next.description = sanitizeFoundationModelText(next.description)
        if var sovereignty = next.sovereigntyChange {
            sovereignty.targetCode = normalizedCountryCode(sovereignty.targetCode)
            sovereignty.name = sanitizeFoundationModelText(sovereignty.name)
            sovereignty.sourceCodes = sovereignty.sourceCodes.map(normalizedCountryCode).filter { !$0.isEmpty }
            sovereignty.regionIDs = sovereignty.regionIDs.map(sanitizeFoundationModelText).filter { !$0.isEmpty }
            next.sovereigntyChange = sovereignty.targetCode.isEmpty && sovereignty.name.isEmpty ? nil : sovereignty
        }
        if next.kind == .crisis {
            next.kind = next.playerRelated ? .action : .world
        }
        next.strategicEffects = next.strategicEffects.enumerated().map { effectIndex, effect in
            var nextEffect = effect
            if nextEffect.id.isEmpty {
                nextEffect.id = "\(next.id)-effect-\(effectIndex)"
            }
            if nextEffect.eventId.isEmpty {
                nextEffect.eventId = next.id
            }
            if nextEffect.date.isEmpty {
                nextEffect.date = next.date
            }
            if nextEffect.target.isEmpty {
                nextEffect.target = next.playerRelated ? country.name : "International system"
            }
            nextEffect.summary = sanitizeFoundationModelText(nextEffect.summary)
            nextEffect.target = sanitizeFoundationModelText(nextEffect.target)
            nextEffect.track = foundationVisibleTrack(nextEffect.track)
            nextEffect.magnitude = Swift.max(-5, Swift.min(5, nextEffect.magnitude))
            return nextEffect
        }
        return next
    }

    private static func foundationVisibleTrack(_ track: NativeStrategicTrack) -> NativeStrategicTrack {
        track
    }

    public static func strategicCountryCodes(for state: NativeCampaignState) -> [String] {
        Array(Set(NativeCampaignState.defaultStrategicCountryCodes + Array(state.dynamicCountries.keys) + Array(state.economicLedgers.keys) + [state.country.code])).sorted()
    }

    private static func effectAffectsCountry(effect: NativeStrategicEffect, countryCode: String) -> Bool {
        let targetLower = effect.target.lowercased()
        let codeLower = countryCode.lowercased()
        if targetLower == codeLower { return true }
        if isGlobal(targetLower), codeLower != "global" {
            return true
        }
        return false
    }

    private static func isGlobal(_ targetLower: String) -> Bool {
        targetLower == "global" || targetLower == "world" || targetLower == "international system"
    }

    public static func updatedEconomicLedgers(
        from ledgers: [String: NativeEconomicLedger],
        state: NativeCampaignState,
        events: [NativeCampaignEvent],
        months _: Int,
        targetDate: String
    ) -> [String: NativeEconomicLedger] {
        var nextLedgers = ledgers

        let countryCodes = strategicCountryCodes(for: state)
        let scenario = NativeScenarioCatalog.scenario(for: state.scenarioID)
        for code in countryCodes {
            if nextLedgers[code] == nil {
                nextLedgers[code] = NativeEconomicLedger.starting(forCode: code, scenario: scenario)
            }
        }

        let negativeMultiplier = switch state.gameMode {
        case .sandbox: 0.5
        case .normal: 1.0
        case .ironman: 2.0
        }

        for (code, ledger) in nextLedgers {
            var nextLedger = ledger
            var entries = ledger.entries

            for event in events {
                guard let effect = event.strategicEffects.first(where: { effectAffectsCountry(effect: $0, countryCode: code) }) else {
                    continue
                }

                let entry: NativeEconomicLedgerEntry
                if let hex = event.hexLeverCode, let lever = NativeHexLever.decodeHexLever(hex) {
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
                    let rules = consequenceRules(for: linkedAction, state: state)
                    let matchedRule = rules.first ?? ruleForEvent(event)
                    let magnitude = Double(effect.magnitude)

                    let defaultSecurityDelta = effect.track == .internalStability ? magnitude * 2.0 : (effect.track == .securityAnxiety ? -magnitude * 2.0 : 0.0)
                    let defaultRebelDelta = -defaultSecurityDelta * 0.5

                    let rawBudget = matchedRule.budgetBalanceDelta + magnitude * 0.015
                    let rawDebt = matchedRule.debtDelta - magnitude * 0.04
                    let rawGrowth = matchedRule.growthDelta + magnitude * 0.025
                    let rawInflation = matchedRule.inflationDelta + (effect.track == .marketConfidence ? -magnitude * 0.01 : 0)
                    let rawTrade = matchedRule.tradeBalanceDelta + magnitude * 0.015

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
                        fiscalSpaceDelta: max(-8, min(8, matchedRule.fiscalSpaceDelta + Int(magnitude.rounded()))),
                        growthDelta: clampDouble(adjGrowth, -0.9, 0.9),
                        id: "econ-\(event.id)-\(code.lowercased())",
                        inflationDelta: clampDouble(adjInflation, -0.7, 0.7),
                        ruleID: matchedRule.id,
                        summary: "\(event.title): \(matchedRule.description)",
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

            if let stochastic = rollStochasticEvent(for: nextLedger, code: code, targetDate: targetDate) {
                let sEntry = NativeEconomicLedgerEntry(
                    budgetBalanceDelta: clampDouble(stochastic.deltas.budgetDelta, -0.8, 0.8),
                    debtDelta: clampDouble(stochastic.deltas.debtDelta, -1.8, 1.8),
                    eventID: "stochastic-\(code.lowercased())-\(targetDate)",
                    fiscalSpaceDelta: max(-8, min(8, stochastic.deltas.fiscalSpaceDelta)),
                    growthDelta: clampDouble(stochastic.deltas.growthDelta, -0.9, 0.9),
                    id: "econ-stochastic-\(code.lowercased())-\(targetDate)",
                    inflationDelta: clampDouble(stochastic.deltas.inflationDelta, -0.7, 0.7),
                    ruleID: "stochastic-drift",
                    summary: stochastic.summary,
                    tradeBalanceDelta: clampDouble(stochastic.deltas.tradeDelta, -0.8, 0.8),
                    turnDate: targetDate,
                    securityDelta: clampDouble(stochastic.deltas.securityDelta, -25.0, 25.0),
                    rebelDelta: clampDouble(stochastic.deltas.rebelDelta, -25.0, 25.0)
                )
                entries.insert(sEntry, at: 0)
                nextLedger.budgetBalancePercentGDP += sEntry.budgetBalanceDelta
                nextLedger.publicDebtPercentGDP += sEntry.debtDelta
                nextLedger.realGrowthPercent += sEntry.growthDelta
                nextLedger.inflationPercent += sEntry.inflationDelta
                nextLedger.tradeBalancePercentGDP += sEntry.tradeBalanceDelta
                nextLedger.securityIndex = clampDouble(nextLedger.securityIndex + (sEntry.securityDelta ?? 0.0), 0, 100)
                nextLedger.rebelControlPercent = clampDouble(nextLedger.rebelControlPercent + (sEntry.rebelDelta ?? 0.0), 0, 100)
                nextLedger.fiscalSpaceIndex = max(0, min(100, nextLedger.fiscalSpaceIndex + sEntry.fiscalSpaceDelta))
            }

            nextLedger.entries = Array(entries.prefix(20))
            nextLedgers[code] = nextLedger
        }

        return nextLedgers
    }

    private static func securityNudge(for value: Int) -> Double {
        switch value {
        case 4: 8.0
        case 6: 12.0
        case 2: -15.0
        case 3: -35.0
        default: 0.0
        }
    }

    private static func rebelNudge(for value: Int) -> Double {
        switch value {
        case 4: -5.0
        case 6: -12.0
        case 2: 18.0
        case 3: 10.0
        default: 0.0
        }
    }

    public static func updatedActionMemory(
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

    public static func updatedSemanticMemory(state: NativeCampaignState, events: [NativeCampaignEvent]) -> [NativeSemanticMemory] {
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
        return Array(records.prefix(NativeConsequenceCatalog.semanticMemoryLimit))
    }

    private static func foundationPromptTrackLabel(_ track: NativeStrategicTrack) -> String {
        switch track {
        case .economicResilience: "ECON_RESILIENCE"
        case .marketConfidence: "MARKET_CONFIDENCE"
        case .diplomaticLeverage: "DIPLOMATIC_LEVERAGE"
        case .internalStability: "INTERNAL_STABILITY"
        case .worldTension: "WORLD_TENSION"
        case .militaryReadiness: "MILITARY_READINESS"
        case .securityAnxiety: "SECURITY_ANXIETY"
        }
    }

    public static func simulateAIDrift(state: inout NativeCampaignState, months: Int) {
        let strategicCodes = NativeCampaignState.defaultStrategicCountryCodes.filter { $0 != "GLOBAL" }

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

        let acceptedTreatyPartnerCodes = Set(state.activeTreaties.filter { $0.isActive && ($0.signatoryA == state.country.code || $0.signatoryB == state.country.code) }.map { $0.signatoryA == state.country.code ? $0.signatoryB : $0.signatoryA })
        for treaty in state.activeTreaties where treaty.isActive {
            let codeA = treaty.signatoryA
            let codeB = treaty.signatoryB

            if codeA != state.country.code {
                if var stateA = state.aiCountryStates[codeA] {
                    let cur = stateA.relationshipScores[codeB] ?? 0
                    let boost = (treaty.type == .militaryAlliance ? 2.0 : 1.0) * Double(months)
                    stateA.relationshipScores[codeB] = max(-100, min(100, cur + Int(boost.rounded())))
                    state.aiCountryStates[codeA] = stateA
                }
            }
            if codeB != state.country.code {
                if var stateB = state.aiCountryStates[codeB] {
                    let cur = stateB.relationshipScores[codeA] ?? 0
                    let boost = (treaty.type == .militaryAlliance ? 2.0 : 1.0) * Double(months)
                    stateB.relationshipScores[codeA] = max(-100, min(100, cur + Int(boost.rounded())))
                    state.aiCountryStates[codeB] = stateB
                }
            }

            for cCode in [codeA, codeB] {
                if var ledger = state.economicLedgers[cCode] {
                    var growthDelta = 0.0
                    var secDelta = 0.0
                    var tradeDelta = 0.0

                    if treaty.type == .militaryAlliance {
                        growthDelta = -0.05 * Double(months)
                        secDelta = 0.5 * Double(months)
                    } else if treaty.type == .tradeAgreement {
                        growthDelta = 0.1 * Double(months)
                        tradeDelta = 0.2 * Double(months)
                    } else if treaty.type == .nonAggressionPact {
                        secDelta = 0.2 * Double(months)
                    }

                    ledger.realGrowthPercent = clampDouble(ledger.realGrowthPercent + growthDelta, -12.0, 16.0)
                    ledger.securityIndex = clampDouble(ledger.securityIndex + secDelta, 0.0, 100.0)
                    ledger.tradeBalancePercentGDP = clampDouble(ledger.tradeBalancePercentGDP + tradeDelta, -20.0, 20.0)
                    state.economicLedgers[cCode] = ledger
                }
            }

            if treaty.type == .militaryAlliance {
                for (actor, target) in [(codeA, codeB), (codeB, codeA)] {
                    if actor == state.country.code {
                        for code in strategicCodes {
                            if code == state.country.code { continue }
                            if let aiState = state.aiCountryStates[code], let playerRel = aiState.relationshipScores[state.country.code], playerRel < -30 {
                                if var aiStateMut = state.aiCountryStates[code] {
                                    let curRel = aiStateMut.relationshipScores[target] ?? 0
                                    aiStateMut.relationshipScores[target] = max(-100, curRel - Int(1.0 * Double(months)))
                                    state.aiCountryStates[code] = aiStateMut
                                }
                            }
                        }
                    } else {
                        if let actorState = state.aiCountryStates[actor] {
                            for (otherCode, score) in actorState.relationshipScores {
                                if score < -30 {
                                    if var rivalState = state.aiCountryStates[otherCode] {
                                        let cur = rivalState.relationshipScores[target] ?? 0
                                        rivalState.relationshipScores[target] = max(-100, cur - Int(1.0 * Double(months)))
                                        state.aiCountryStates[otherCode] = rivalState
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        for code in strategicCodes {
            if code == state.country.code { continue }
            guard var aiState = state.aiCountryStates[code] else { continue }

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

            let dipSlider = state.budgetDiplomacySlider
            let milSlider = state.budgetMilitarySlider
            let baseDrift = dipSlider < 0.20 ? months * 2 : months
            var updatedRelations = aiState.relationshipScores

            for (otherCode, score) in updatedRelations {
                var nextScore = Double(score)
                let tensionPolarization = state.worldTension > 80 ? 1.0 * Double(months) : 0.0

                if score > 0 {
                    let decay = (dipSlider > 0.40 ? 0.0 : Double(baseDrift)) + tensionPolarization
                    nextScore = max(0, nextScore - decay)
                } else if score < 0 {
                    let recovery = (dipSlider > 0.40 ? Double(months * 2) : Double(baseDrift)) + tensionPolarization
                    nextScore = min(0, nextScore + recovery)
                }

                if otherCode == state.country.code, dipSlider > 0.40, !acceptedTreatyPartnerCodes.contains(code) {
                    nextScore = min(100.0, nextScore + (1.0 * Double(months)))
                }

                if otherCode == state.country.code, milSlider > 0.40 {
                    let isRival = score < -30
                    let penalty = isRival ? (-1.0 * Double(months)) : (-0.5 * Double(months))
                    nextScore = max(-100.0, nextScore + penalty)
                }

                updatedRelations[otherCode] = Int(nextScore.rounded())
            }
            aiState.relationshipScores = updatedRelations

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
        for code in strategicCodes {
            guard var ledger = state.economicLedgers[code] else { continue }

            let deficit = -ledger.budgetBalancePercentGDP
            ledger.publicDebtPercentGDP = clampDouble(ledger.publicDebtPercentGDP + deficit * yearFraction, 1.0, 260.0)

            let calculatedFiscalSpace = max(0, min(100, 100 - Int(ledger.publicDebtPercentGDP * 0.4) - Int(ledger.inflationPercent * 1.0)))
            ledger.fiscalSpaceIndex = calculatedFiscalSpace

            if ledger.rebelControlPercent > 10.0 {
                let secDecay = -(ledger.rebelControlPercent * 0.1) * Double(months)
                ledger.securityIndex = clampDouble(ledger.securityIndex + secDecay, 0.0, 100.0)
            }

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

        var rngTreaty = SimpleRNG(seedString: "ai-ai-treaty-\(state.scenarioID)-\(state.round)")
        for i in 0 ..< strategicCodes.count {
            let codeA = strategicCodes[i]
            for j in (i + 1) ..< strategicCodes.count {
                let codeB = strategicCodes[j]
                guard codeA != state.country.code, codeB != state.country.code else { continue }

                let relAToB = state.aiCountryStates[codeA]?.relationshipScores[codeB] ?? 0
                let relBToA = state.aiCountryStates[codeB]?.relationshipScores[codeA] ?? 0
                let avgRelations = (relAToB + relBToA) / 2

                let existingIndex = state.activeTreaties.firstIndex(where: {
                    $0.isActive &&
                        (($0.signatoryA == codeA && $0.signatoryB == codeB) ||
                            ($0.signatoryA == codeB && $0.signatoryB == codeA))
                })

                if let idx = existingIndex {
                    if avgRelations < 0 {
                        var treaty = state.activeTreaties[idx]
                        treaty.isActive = false
                        state.activeTreaties[idx] = treaty

                        let breakEvent = NativeCampaignEvent(
                            date: state.gameDate,
                            description: "TREATY DISSOLVED: Deteriorating diplomatic relations between \(codeA) and \(codeB) have led to the peaceful cancellation of their \(treaty.name) treaty.",
                            id: "treaty-dissolve-\(treaty.id)-\(UUID().uuidString.lowercased())",
                            importance: .minor,
                            kind: .diplomacy,
                            linkedActionIDs: [],
                            notable: false,
                            playerRelated: false,
                            strategicEffects: [],
                            title: "Treaty Dissolved: \(treaty.name)"
                        )
                        state.timeline.insert(breakEvent, at: 0)
                    }
                } else {
                    if avgRelations > 40, rngTreaty.nextDouble() < 0.08 {
                        let offerType: NativeOfferType = rngTreaty.nextDouble() < 0.5 ? .tradeAgreement : .nonAggressionPact

                        var obligations: [NativeObligation] = []
                        switch offerType {
                        case .tradeAgreement:
                            obligations.append(NativeObligation(
                                id: "obg-ai-\(UUID().uuidString.lowercased())",
                                type: .tradeCooperation,
                                description: "Trade Cooperation Obligation: Signatories \(codeA) and \(codeB) will reduce trade barriers and boost mutual growth.",
                                value: 0.1
                            ))
                        case .nonAggressionPact:
                            obligations.append(NativeObligation(
                                id: "obg-ai-\(UUID().uuidString.lowercased())",
                                type: .nonAggression,
                                description: "Non-Aggression Obligation: Signatories \(codeA) and \(codeB) agree to resolve disputes peacefully.",
                                value: 0.2
                            ))
                        default:
                            break
                        }

                        let newTreaty = NativeTreaty(
                            id: "treaty-ai-\(codeA.lowercased())-\(codeB.lowercased())-\(UUID().uuidString.lowercased())",
                            name: offerType.displayName,
                            signatoryA: codeA,
                            signatoryB: codeB,
                            type: offerType,
                            signatureDate: state.gameDate,
                            obligations: obligations,
                            termMonths: 24,
                            elapsedMonths: 0,
                            isActive: true
                        )
                        state.activeTreaties.append(newTreaty)

                        let signEvent = NativeCampaignEvent(
                            date: state.gameDate,
                            description: "TREATY SIGNED: \(codeA) and \(codeB) have signed a bilateral \(newTreaty.name) to coordinate their strategic policies.",
                            id: "treaty-sign-event-\(newTreaty.id)-\(UUID().uuidString.lowercased())",
                            importance: .minor,
                            kind: .diplomacy,
                            linkedActionIDs: [],
                            notable: false,
                            playerRelated: false,
                            strategicEffects: [],
                            title: "Treaty Signed: \(newTreaty.name)"
                        )
                        state.timeline.insert(signEvent, at: 0)
                    }
                }
            }
        }

        if let playerLedger = state.economicLedgers[state.country.code] {
            state.economicLedger = playerLedger
        }
    }

    public static func consequenceRules(for action: NativePlannedAction?, state _: NativeCampaignState) -> [NativeConsequenceRule] {
        guard let action else {
            return [
                NativeConsequenceCatalog.rulesByID["macro-demand"]!,
                NativeConsequenceCatalog.rulesByID["market-confidence"]!,
                NativeConsequenceCatalog.rulesByID["fiscal-drift"]!,
                NativeConsequenceCatalog.rulesByID["public-security"]!,
                NativeConsequenceCatalog.rulesByID["insurgency-containment"]!
            ]
        }
        let text = "\(action.title) \(action.detail)".lowercased()
        let matches = NativeConsequenceCatalog.consequenceRules.filter { rule in
            rule.keywords.contains { text.contains($0) }
        }
        return matches.isEmpty ? [NativeConsequenceCatalog.rulesByID["default-civic"]!] : Array(matches.prefix(4))
    }

    public static func ruleForEvent(_ event: NativeCampaignEvent) -> NativeConsequenceRule {
        let track = event.strategicEffects.first?.track ?? .marketConfidence
        switch track {
        case .economicResilience:
            return NativeConsequenceCatalog.rulesByID["infrastructure-resilience"]!
        case .marketConfidence:
            return NativeConsequenceCatalog.rulesByID["market-confidence"]!
        case .diplomaticLeverage:
            return NativeConsequenceCatalog.rulesByID["trade-diplomacy"]!
        case .internalStability:
            return NativeConsequenceCatalog.rulesByID["service-delivery"]!
        case .worldTension, .securityAnxiety:
            return NativeConsequenceCatalog.rulesByID["external-shock"]!
        case .militaryReadiness:
            return NativeConsequenceCatalog.rulesByID["default-civic"]!
        }
    }

    public static func rollStochasticEvent(
        for ledger: NativeEconomicLedger,
        code: String,
        targetDate: String
    ) -> (deltas: NativeHexLever, summary: String)? {
        let seedString = "\(code)-\(targetDate)-\(ledger.publicDebtPercentGDP)-\(ledger.fiscalSpaceIndex)"
        var rng = SimpleRNG(seedString: seedString)

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

        if ledger.publicDebtPercentGDP < 50.0, ledger.fiscalSpaceIndex > 70 {
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

        let noiseGrowth = (rng.nextDouble() * 0.1) - 0.05
        let noiseBudget = (rng.nextDouble() * 0.04) - 0.02
        let noiseDebt = (rng.nextDouble() * 0.2) - 0.1
        let noiseInflation = (rng.nextDouble() * 0.04) - 0.02
        let noiseTrade = (rng.nextDouble() * 0.04) - 0.02

        let fsRoll = rng.nextDouble()
        let noiseFiscalSpace: Int = if fsRoll > 0.85 { 1 }
        else if fsRoll < 0.15 { -1 }
        else { 0 }

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
}

// MARK: - Private Helper Structs

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

private enum NativeTinyEmbeddingModel {
    private static let dimensions = 64

    static func embed(_ text: String) -> [Float] {
        var vector = Array(repeating: Float(0), count: dimensions)
        for token in tokens(text) {
            let hash = token.unicodeScalars.reduce(UInt64(5381)) { ($0 << 5) &+ $0 &+ UInt64($1.value) }
            let index = Int(hash % UInt64(dimensions))
            vector[index] += (hash & 1) == 0 ? 1 : -1
        }
        let norm = sqrt(vector.reduce(Float(0)) { $0 + $1 * $1 })
        guard norm > 0 else { return vector }
        return vector.map { $0 / norm }
    }

    private static func tokens(_ text: String) -> [String] {
        let base = text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 2 }
        return base.flatMap { token in [token] + aliases[token, default: []] }
    }

    private static let aliases: [String: [String]] = [
        "airport": ["logistics", "corridor", "trade"],
        "border": ["security", "sovereignty", "conflict"],
        "budget": ["fiscal", "debt", "capacity"],
        "corridor": ["logistics", "trade", "infrastructure"],
        "debt": ["budget", "fiscal", "market"],
        "diplomacy": ["relations", "treaty", "leverage"],
        "education": ["services", "capacity", "stability"],
        "energy": ["infrastructure", "resilience", "industry"],
        "fiscal": ["budget", "debt", "capacity"],
        "inflation": ["prices", "market", "stability"],
        "insurgency": ["security", "stabilization", "rebel"],
        "market": ["confidence", "trade", "growth"],
        "port": ["logistics", "corridor", "trade"],
        "rail": ["logistics", "corridor", "infrastructure"],
        "rebel": ["insurgency", "security", "stabilization"],
        "security": ["stabilization", "insurgency", "resilience"],
        "services": ["education", "health", "stability"],
        "stability": ["services", "security", "legitimacy"],
        "stabilization": ["security", "insurgency", "resilience"],
        "trade": ["corridor", "market", "diplomacy"]
    ]
}

private extension NativeEventImportance {
    var semanticWeight: Int {
        switch self {
        case .minor: 1
        case .major: 3
        case .severe: 5
        }
    }
}
