import Foundation

/// Deterministic rules layer for the native campaign.
///
/// The AI service may draft events, summaries, and suggested effects, but this
/// engine decides whether a generated turn is coherent and how it mutates
/// stored state. Keep this file free of UI concerns and hidden model calls.
enum NativeGameEngine {
    private static let displayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    static func initialState(
        for country: PlayerCountry,
        scenario: NativeScenario = NativeScenarioCatalog.defaultScenario,
        language: NativeGameLanguage = .english
    ) -> NativeCampaignState {
        let openingStability = Native2010WorldModel.stability(for: country, scenario: scenario)
        let openingWorldTension = Native2010WorldModel.worldTension(for: country, scenario: scenario)

        return NativeCampaignState(
            actionMemory: [],
            aiReadiness: .notChecked,
            country: country,
            economicLedger: NativeEconomicLedger.starting(for: country, scenario: scenario),
            economicLedgers: nil,
            aiCountryStates: NativeStrategyContextDatabase.initialAICountryStates(for: scenario.id),
            gameDate: scenario.gameDate,
            lastSummary: openingSummary(for: country, scenario: scenario, language: language),
            language: language,
            plannedActions: [],
            round: 1,
            scenarioDescription: scenario.heroSubtitle,
            scenarioID: scenario.id,
            scenarioName: scenario.name,
            suggestedActions: [],
            stability: openingStability,
            startDate: scenario.startDate,
            timeline: [
                NativeCampaignEvent(
                    date: scenario.gameDate,
                    description: openingDescription(for: country, scenario: scenario, language: language),
                    id: "opening-\(scenario.id)-\(country.code.lowercased())",
                    importance: .major,
                    kind: .world,
                    linkedActionIDs: [],
                    notable: true,
                    playerRelated: true,
                    strategicEffects: [
                        NativeStrategicEffect(
                            date: scenario.gameDate,
                            eventId: "opening-\(scenario.id)-\(country.code.lowercased())",
                            id: "opening-\(scenario.id)-\(country.code.lowercased())-stability",
                            magnitude: 1,
                            summary: openingEffectSummary(for: scenario, language: language),
                            target: country.name,
                            track: .internalStability
                        ),
                    ],
                    title: openingTitle(for: country, scenario: scenario, language: language)
                ),
            ],
            worldTension: openingWorldTension,
            worldEffects: []
        )
    }

    static func estimateDirectiveCount(in text: String) -> Int {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }

        var normalized = trimmed.replacingOccurrences(of: ";", with: "|")
                                .replacingOccurrences(of: "\n", with: "|")
                                .replacingOccurrences(of: "!", with: "|")
                                .replacingOccurrences(of: "?", with: "|")
                                .replacingOccurrences(of: ".", with: "|")

        let transitionWords = [
            " and ", " e ", " y ",
            " then ", " then, ", " então ", " entonces ",
            " also ", " também ", " también ",
            " plus ", " mais ", " más ",
            " additionally ", " adicionalmente ", " além disso ", " además ",
            " as well as ", " bem como ", " así como "
        ]

        for word in transitionWords {
            var searchRange = normalized.startIndex..<normalized.endIndex
            while let range = normalized.range(of: word, options: .caseInsensitive, range: searchRange) {
                normalized.replaceSubrange(range, with: "|")
                searchRange = normalized.startIndex..<normalized.endIndex
            }
        }

        let segments = normalized.components(separatedBy: "|")
        var count = 0
        for segment in segments {
            let segTrimmed = segment.trimmingCharacters(in: .whitespacesAndNewlines)
            if segTrimmed.count >= 4 {
                count += 1
            }
        }

        return max(1, count)
    }

    static func estimateDirectiveCost(for text: String) -> Int {
        return estimateDirectiveCount(in: text) * 30
    }

    static func action(from text: String, date: String) -> NativePlannedAction? {
        let trimmed = sanitizeFoundationModelText(text)
        guard !trimmed.isEmpty else { return nil }

        let title = trimmed
            .components(separatedBy: CharacterSet(charactersIn: ".\n"))
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(72) ?? Substring(trimmed.prefix(72))

        return NativePlannedAction(
            createdAt: date,
            detail: trimmed,
            id: "action-\(UUID().uuidString.lowercased())",
            resolvedAt: nil,
            status: .planned,
            title: String(title)
        )
    }

    /// Validates generated turn drafts before any campaign mutation.
    ///
    /// This is intentionally stricter than `apply`: it rejects missing world
    /// events, duplicate IDs, placeholder prose, invalid dates, unknown action
    /// links, and hidden/internal-only tracks. The store and AI service should
    /// treat thrown errors as repair instructions or visible failures, not as
    /// permission to apply partial model output.
    static func validated(_ turn: NativeGeneratedTurn, state: NativeCampaignState, months: Int) throws -> NativeGeneratedTurn {
        guard months > 0 else {
            throw NativeGameEngineError.invalidTurn("Generated turns require a positive time jump.")
        }
        guard isValidDate(state.gameDate) else {
            throw NativeGameEngineError.invalidTurn("Campaign state has an invalid game date.")
        }

        let candidateEvents = Array(turn.events.prefix(6))
        guard !candidateEvents.isEmpty else {
            throw NativeGameEngineError.invalidTurn("Foundation Models returned no events.")
        }
        guard candidateEvents.contains(where: { !$0.playerRelated }) else {
            throw NativeGameEngineError.invalidTurn("At least one generated event must be independent of the player country.")
        }
        let summary = sanitizeFoundationModelText(turn.summary)
        guard hasConcreteFoundationText(summary, minimumWords: 6) else {
            throw NativeGameEngineError.invalidTurn("Foundation Models returned an empty or placeholder turn summary.")
        }

        let targetDate = advance(date: state.gameDate, months: months)
        guard isValidDate(targetDate) else {
            throw NativeGameEngineError.invalidTurn("Generated turn produced an invalid target date.")
        }

        let plannedActionIDs = Set(state.plannedActions.filter { $0.status == .planned }.map(\.id))
        var seenEventIDs = Set<String>()
        var seenEffectIDs = Set<String>()
        var events: [NativeCampaignEvent] = []

        for (index, rawEvent) in candidateEvents.enumerated() {
            let unsafeTracks = rawEvent.strategicEffects.filter {
                $0.track == .militaryReadiness || $0.track == .securityAnxiety
            }
            guard unsafeTracks.isEmpty else {
                throw NativeGameEngineError.invalidTurn("Event \(index + 1) used an unsafe strategic track.")
            }

            let event = normalized(rawEvent, index: index, targetDate: targetDate, country: state.country)
            guard seenEventIDs.insert(event.id).inserted else {
                throw NativeGameEngineError.invalidTurn("Event \(index + 1) reused a duplicate event ID.")
            }
            guard NativeGameEngine.isValidDate(event.date) else {
                throw NativeGameEngineError.invalidTurn("Event \(index + 1) has an invalid date.")
            }
            guard !event.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw NativeGameEngineError.invalidTurn("Event \(index + 1) is missing a title.")
            }
            guard !containsFoundationPlaceholderText(event.title) else {
                throw NativeGameEngineError.invalidTurn("Event \(index + 1) used a schema placeholder instead of a real title.")
            }
            guard !event.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw NativeGameEngineError.invalidTurn("Event \(index + 1) is missing a description.")
            }
            guard !containsFoundationPlaceholderText(event.description), event.description.split(separator: " ").count >= 8 else {
                throw NativeGameEngineError.invalidTurn("Event \(index + 1) needs a concrete description.")
            }
            guard !event.strategicEffects.isEmpty else {
                throw NativeGameEngineError.invalidTurn("Event \(event.title) has no strategic effects.")
            }
            let invalidLinks = event.linkedActionIDs.filter { !plannedActionIDs.contains($0) }
            guard invalidLinks.isEmpty else {
                throw NativeGameEngineError.invalidTurn("Event \(index + 1) linked to an unknown or already resolved action.")
            }
            guard event.strategicEffects.allSatisfy({
                hasConcreteFoundationText($0.summary, minimumWords: 5) &&
                    !$0.target.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                    !containsFoundationPlaceholderText($0.target) &&
                    NativeGameEngine.isValidDate($0.date) &&
                    $0.eventId == event.id &&
                    $0.track != .militaryReadiness &&
                    $0.track != .securityAnxiety
            }) else {
                throw NativeGameEngineError.invalidTurn("Event \(index + 1) needs a concrete strategic effect summary.")
            }

            for effect in event.strategicEffects {
                guard seenEffectIDs.insert(effect.id).inserted else {
                    throw NativeGameEngineError.invalidTurn("Event \(index + 1) reused a duplicate strategic effect ID.")
                }
            }
            events.append(event)
        }

        return NativeGeneratedTurn(
            events: events,
            stabilityDelta: Swift.max(-12, Swift.min(12, turn.stabilityDelta)),
            summary: summary,
            worldTensionDelta: Swift.max(-12, Swift.min(12, turn.worldTensionDelta))
        )
    }

    static func apply(
        _ generated: NativeGeneratedTurn,
        to state: NativeCampaignState,
        months: Int
    ) -> NativeCampaignState {
        // `apply` assumes `generated` already passed `validated`. It still
        // normalizes defensive defaults, then performs the deterministic state
        // transition: resolve linked actions, update ledgers, append effects,
        // clamp metrics, and preserve full campaign history.
        let targetDate = advance(date: state.gameDate, months: months)
        var generatedEvents = generated.events.enumerated().map { index, event in
            normalized(event, index: index, targetDate: targetDate, country: state.country)
        }
        let linkedActionIDs = Set(generatedEvents.flatMap(\.linkedActionIDs))
        let resolvedActions = state.plannedActions.map { action in
            guard linkedActionIDs.contains(action.id), action.status == .planned else { return action }
            var next = action
            next.status = .resolved
            next.resolvedAt = targetDate
            return next
        }
        let allEffects = generatedEvents.flatMap(\.strategicEffects)
        let economicLedgers = NativeStrategyContextDatabase.updatedEconomicLedgers(
            from: state.economicLedgers,
            state: state,
            events: generatedEvents,
            months: months,
            targetDate: targetDate
        )

        var nextRegionOccupations = state.regionOccupations
        var nextNuclearRegions = state.nuclearFalloutRegions
        var nextRegionConflicts = state.regionConflicts
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

        let economicLedger = mutableLedgers[state.country.code] ?? state.economicLedger
        let actionMemory = NativeStrategyContextDatabase.updatedActionMemory(
            state: state,
            resolvedActions: resolvedActions,
            events: generatedEvents,
            targetDate: targetDate
        )

        var nextAICountryStates = state.aiCountryStates
        if nextAICountryStates.isEmpty {
            nextAICountryStates = NativeStrategyContextDatabase.initialAICountryStates(for: state.scenarioID)
        }

        for event in generatedEvents {
            guard let hex = event.hexLeverCode,
                  let lever = NativeStrategyContextDatabase.decodeHexLever(hex) else {
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

        let negativeMultiplier: Double
        switch state.gameMode {
        case .sandbox: negativeMultiplier = 0.5
        case .normal: negativeMultiplier = 1.0
        case .ironman: negativeMultiplier = 2.0
        }

        let rawStabilityDelta = generated.stabilityDelta
        let adjStabilityDelta = rawStabilityDelta < 0 ? Int((Double(rawStabilityDelta) * negativeMultiplier).rounded()) : rawStabilityDelta

        let rawTensionDelta = generated.worldTensionDelta
        let adjTensionDelta = rawTensionDelta > 0 ? Int((Double(rawTensionDelta) * negativeMultiplier).rounded()) : rawTensionDelta

        // Calculate occupied regions and nuclear fallout counts for the player
        let occupiedCount = nextRegionOccupations.filter { key, val in
            let reg = GeopoliticalMapData.regions.first(where: { $0.id == key })
            return reg?.countryCode == state.country.code && val != state.country.code
        }.count

        let falloutCount = nextNuclearRegions.filter { rid in
            let reg = GeopoliticalMapData.regions.first(where: { $0.id == rid })
            return reg?.countryCode == state.country.code
        }.count

        // Fallout inflicts stability penalty of 2 per region per turn
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

        // Apply dynamic economic ledger penalties
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

        // Calculate dynamic administrative capacity refill
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

        // Calculate dynamic world tension escalation
        let activeConflictsCount = nextRegionConflicts.count
        let armsRaceEscalation = state.budgetMilitarySlider > 0.40 ? 2 : 0
        let globalFalloutCount = nextNuclearRegions.count
        let globalOccupiedCount = nextRegionOccupations.filter { key, val in
            let reg = GeopoliticalMapData.regions.first(where: { $0.id == key })
            return reg?.countryCode == state.country.code && val != state.country.code
        }.count
        let nuclearFalloutEscalation = globalFalloutCount * 5
        let imperialFrictionEscalation = globalOccupiedCount * 1
        let tensionEscalation = activeConflictsCount + armsRaceEscalation + nuclearFalloutEscalation + imperialFrictionEscalation

        var finalState = NativeCampaignState(
            actionMemory: actionMemory,
            advisorMessages: state.advisorMessages,
            aiReadiness: .available(tokenBudget: "guided-generation context=4096, maxResponse=760"),
            country: state.country,
            diplomaticThreads: state.diplomaticThreads,
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
            suggestedActions: [],
            stability: targetStability,
            startDate: state.startDate,
            timeline: generatedEvents + state.timeline,
            worldTension: clamp(state.worldTension + adjTensionDelta + tensionEscalation + allEffects.filter { $0.track == .worldTension || $0.track == .securityAnxiety }.map(\.magnitude).reduce(0, +)),
            worldEffects: allEffects + state.worldEffects,
            regionOccupations: nextRegionOccupations,
            nuclearFalloutRegions: nextNuclearRegions,
            regionConflicts: nextRegionConflicts,
            // New strategy fields
            administrativeCapacity: nextCapacity,
            victoryStatus: nextVictoryStatus,
            activeOffers: state.activeOffers,
            budgetMilitarySlider: state.budgetMilitarySlider,
            budgetServicesSlider: state.budgetServicesSlider,
            budgetDiplomacySlider: state.budgetDiplomacySlider
        )

        if finalState.victoryStatus == .ongoing {
            finalState.victoryStatus = evaluateVictoryStatus(for: finalState)
            if finalState.victoryStatus == .won {
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
            } else if finalState.victoryStatus == .lostTimeout {
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

        NativeStrategyContextDatabase.simulateAIDrift(state: &finalState, months: months)
        return finalState
    }

    private static func processTacticalNudges(
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
                  let lever = NativeStrategyContextDatabase.decodeHexLever(hex) else {
                continue
            }

            let countryCode = resolvedCountryCode(
                from: event.strategicEffects.first?.target ?? state.country.code,
                fallback: state.country.code
            )
            let targetCountryCode = getRivalCountryCode(for: countryCode)
            let eventSummary = "\(event.title): \(NativeStrategyContextDatabase.conflictNudgeLabel(for: lever.invasionNudge))."

            switch lever.invasionNudge {
            case 1:
                let targetRegions = GeopoliticalMapData.regions.filter { $0.countryCode == targetCountryCode }
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
                let domesticRegions = GeopoliticalMapData.regions.filter { $0.countryCode == countryCode }
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
                let targetRegions = GeopoliticalMapData.regions.filter { $0.countryCode == targetCountryCode }
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
                let domesticRegions = GeopoliticalMapData.regions.filter { $0.countryCode == countryCode }
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
                let targetRegions = GeopoliticalMapData.regions.filter { $0.countryCode == targetCountryCode }
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
                let domesticRegions = GeopoliticalMapData.regions.filter { $0.countryCode == countryCode }
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
                let targetRegions = GeopoliticalMapData.regions.filter { $0.countryCode == targetCountryCode }
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
                let domesticRegionIDs = GeopoliticalMapData.regions.filter { $0.countryCode == countryCode }.map(\.id)
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
                let domesticRegions = GeopoliticalMapData.regions.filter { $0.countryCode == code }
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
                let domesticRegions = GeopoliticalMapData.regions.filter { $0.countryCode == code }
                for reg in domesticRegions where regionOccupations[reg.id] == "REB" {
                    regionOccupations.removeValue(forKey: reg.id)
                    if regionConflicts[reg.id]?.mode == .guerrillaControl {
                        regionConflicts.removeValue(forKey: reg.id)
                    }
                }
            }
        }
    }

    private static func setConflict(
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
            rebelDelta: event.hexLeverCode.flatMap { NativeStrategyContextDatabase.decodeHexLever($0)?.rebelDelta } ?? 0,
            regionID: region.id,
            securityDelta: event.hexLeverCode.flatMap { NativeStrategyContextDatabase.decodeHexLever($0)?.securityDelta } ?? 0,
            sourceEventID: event.id,
            summary: summary,
            updatedAt: targetDate
        )
    }

    private static func resolvedCountryCode(from value: String, fallback: String) -> String {
        let text = value.lowercased()
        if let match = CountryCatalog.all.first(where: { country in
            NativeStrategyContextDatabase.countryAliases(for: country.code).contains { alias in
                !alias.isEmpty && text.contains(alias)
            }
        }) {
            return match.code
        }
        return fallback
    }

    private static func getRivalCountryCode(for countryCode: String) -> String {
        switch countryCode {
        case "USA": return "RUS"
        case "CHN": return "USA"
        case "BRA": return "USA"
        case "DEU": return "RUS"
        case "JPN": return "CHN"
        case "GBR": return "RUS"
        case "FRA": return "RUS"
        case "IND": return "CHN"
        case "RUS": return "USA"
        case "ZAF": return "GLOBAL"
        case "AUS": return "CHN"
        default: return "USA"
        }
    }

    static func advance(date: String, months: Int) -> String {
        guard let value = displayFormatter.date(from: date) else { return date }
        let next = Calendar(identifier: .gregorian).date(byAdding: .month, value: months, to: value) ?? value
        return displayFormatter.string(from: next)
    }

    static func isValidDate(_ value: String) -> Bool {
        displayFormatter.date(from: value) != nil
    }

    static func clampedMetric(_ value: Int) -> Int {
        clamp(value)
    }

    static func todayStamp() -> String {
        ISO8601DateFormatter().string(from: Date())
    }

    private static func normalized(_ event: NativeCampaignEvent, index: Int, targetDate: String, country: PlayerCountry) -> NativeCampaignEvent {
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

    private static func clamp(_ value: Int) -> Int {
        Swift.max(0, Swift.min(100, value))
    }

    private static func openingSummary(
        for country: PlayerCountry,
        scenario: NativeScenario,
        language: NativeGameLanguage
    ) -> String {
        if Native2010WorldModel.isReal2010Scenario(scenario) {
            return Native2010WorldModel.openingSummary(for: country, language: language)
        }

        switch language {
        case .english:
            return "\(scenario.openingSummary) \(country.name) needs to turn intent into concrete plans."
        case .portuguese:
            return "A campanha \(scenario.name) começa com \(country.name) avaliando mercados, serviços e margem diplomática. Transforme intenção em planos concretos."
        case .spanish:
            return "La campaña \(scenario.name) comienza con \(country.name) evaluando mercados, servicios y margen diplomático. Convierte la intención en planes concretos."
        }
    }

    private static func openingDescription(
        for country: PlayerCountry,
        scenario: NativeScenario,
        language: NativeGameLanguage
    ) -> String {
        if Native2010WorldModel.isReal2010Scenario(scenario) {
            return Native2010WorldModel.openingEventDescription(for: country, language: language)
        }

        switch language {
        case .english:
            return "\(scenario.heroTitle) begins as a playable scenario. The first important decision is choosing priorities, not reacting to noise."
        case .portuguese:
            return "\(scenario.heroTitle) começa como um cenário jogável. A primeira decisão importante é escolher prioridades, não reagir ao ruído."
        case .spanish:
            return "\(scenario.heroTitle) empieza como un escenario jugable. La primera decisión importante es elegir prioridades, no reaccionar al ruido."
        }
    }

    private static func openingEffectSummary(for scenario: NativeScenario, language: NativeGameLanguage) -> String {
        if Native2010WorldModel.isReal2010Scenario(scenario) {
            return Native2010WorldModel.openingEffectSummary(for: language)
        }

        switch language {
        case .english:
            return "An orderly transition gives the player a small opening margin."
        case .portuguese:
            return "Uma transição ordenada dá ao jogador uma pequena margem inicial."
        case .spanish:
            return "Una transición ordenada da al jugador un pequeño margen inicial."
        }
    }

    private static func openingTitle(for country: PlayerCountry, scenario: NativeScenario, language: NativeGameLanguage) -> String {
        if Native2010WorldModel.isReal2010Scenario(scenario) {
            return Native2010WorldModel.openingEventTitle(for: country, language: language)
        }

        switch language {
        case .english:
            return "\(country.name) opens the planning table"
        case .portuguese:
            return "\(country.name) abre a mesa de planejamento"
        case .spanish:
            return "\(country.name) abre la mesa de planificación"
        }
    }

    private static func clampDouble(_ value: Double, _ lower: Double, _ upper: Double) -> Double {
        Swift.max(lower, Swift.min(upper, value))
    }

    private static func getYear(from dateString: String) -> Int? {
        let parts = dateString.split(separator: "-")
        if let first = parts.first, let year = Int(first) {
            return year
        }
        return nil
    }

    static func evaluateVictoryStatus(for state: NativeCampaignState) -> NativeVictoryStatus {
        if state.stability <= 0 {
            return .lostCollapse
        }

        guard let currentYear = getYear(from: state.gameDate) else {
            return .ongoing
        }

        let pLedger = state.economicLedger
        let occupiedCount = state.regionOccupations.filter { key, val in
            let reg = GeopoliticalMapData.regions.first(where: { $0.id == key })
            return reg?.countryCode == state.country.code && val != state.country.code
        }.count

        switch state.scenarioID {
        case "default":
            if state.stability >= 80 && pLedger.tradeBalancePercentGDP >= 0.0 && occupiedCount == 0 {
                return .won
            }
            if currentYear > 2030 {
                return .lostTimeout
            }
        case "fragmented-markets":
            if state.stability >= 75 && pLedger.nominalGDPTrillions >= 15.0 && pLedger.fiscalSpaceIndex >= 60 {
                return .won
            }
            if currentYear > 2040 {
                return .lostTimeout
            }
        case "resilience-decade":
            if state.stability >= 80 && pLedger.securityIndex >= 85 && pLedger.rebelControlPercent <= 5.0 {
                return .won
            }
            if currentYear > 2050 {
                return .lostTimeout
            }
        case "soviet-triumph":
            let occupiedRivals = state.regionOccupations.filter { key, val in
                let reg = GeopoliticalMapData.regions.first(where: { $0.id == key })
                return reg?.countryCode != state.country.code && val == state.country.code
            }.count
            if state.stability >= 80 && state.worldTension >= 80 && occupiedRivals >= 2 {
                return .won
            }
            if currentYear > 2005 {
                return .lostTimeout
            }
        case "pax-cybernetica":
            if state.stability >= 85 && pLedger.nominalGDPTrillions >= 25.0 && pLedger.tradeBalancePercentGDP >= 2.0 {
                return .won
            }
            if currentYear > 2065 {
                return .lostTimeout
            }
        case "solarpunk-dawn":
            if state.stability >= 85 && pLedger.rebelControlPercent == 0.0 && pLedger.securityIndex >= 80 {
                return .won
            }
            if currentYear > 2070 {
                return .lostTimeout
            }
        default:
            if state.stability >= 85 && currentYear <= 2040 {
                return .won
            }
            if currentYear > 2040 {
                return .lostTimeout
            }
        }

        return .ongoing
    }
}
