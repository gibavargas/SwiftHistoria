import Foundation

/// Deterministic rules layer for the native campaign.
///
/// The AI service may draft events, summaries, and suggested effects, but this
/// engine decides whether a generated turn is coherent and how it mutates
/// stored state. Keep this file free of UI concerns and hidden model calls.
enum NativeGameEngine {
    nonisolated(unsafe) static var force512DiceFrictionForTesting = false
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
                        )
                    ],
                    title: openingTitle(for: country, scenario: scenario, language: language)
                )
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
            var searchRange = normalized.startIndex ..< normalized.endIndex
            while let range = normalized.range(of: word, options: .caseInsensitive, range: searchRange) {
                normalized.replaceSubrange(range, with: "|")
                searchRange = normalized.startIndex ..< normalized.endIndex
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
        if let quickActionCost = NativeQuickActionCatalog.estimatedCost(for: text) {
            return quickActionCost
        }
        return estimateDirectiveCount(in: text) * 30
    }

    static func previewDirective(_ text: String, in state: NativeCampaignState) -> NativeDirectivePreview {
        let trimmed = sanitizeFoundationModelText(text)
        let cost = estimateDirectiveCost(for: trimmed)
        let capacityAfter = state.administrativeCapacity - cost
        let warning = capacityAfter < 0 ? "Insufficient administrative capacity." : nil
        let quickAction = NativeQuickActionCatalog.action(matching: trimmed)
        var expectedEffects = quickAction?.primaryEffects ?? []
        var riskLabel = "Standard"

        if let kind = regionOrderKind(from: trimmed),
           let regionID = regionID(from: trimmed),
           let region = GeopoliticalMapData.regionByID[regionID]
        {
            switch kind {
            case .invade:
                let terrainRisk = switch region.terrain {
                case .mountain, .strait, .ocean, .sea: "High"
                case .swamp, .forest, .city, .cerrado: "Medium"
                case .plains: "Low"
                }
                riskLabel = "\(terrainRisk) terrain risk"
                expectedEffects = [
                    "Dice battle uses military budget and \(region.terrain.displayName.lowercased()) terrain.",
                    "Success creates occupation; failure creates contested border pressure.",
                    "World tension rises while the conflict persists."
                ]
            case .stabilize:
                riskLabel = "Low"
                expectedEffects = ["Reduces regional conflict pressure.", "Can restore domestic stability."]
            case .fortify:
                riskLabel = "Escalatory"
                expectedEffects = ["Improves defensive posture.", "Raises world tension if overused."]
            case .withdraw:
                riskLabel = "De-escalatory"
                expectedEffects = ["Removes player occupation from non-core territory.", "Lowers tension and occupation burden."]
            case .autonomy:
                riskLabel = "Political"
                expectedEffects = ["Trades central control for lower insurgency pressure.", "Improves diplomatic leverage."]
            case .rebuild:
                riskLabel = "Recovery"
                expectedEffects = ["Repairs fallout or conflict damage.", "Improves resilience and stability."]
            case .tradeCorridor:
                riskLabel = "Economic"
                expectedEffects = ["Raises market confidence.", "Supports economic resilience and trade balance."]
            }
        } else if expectedEffects.isEmpty {
            let directiveCount = estimateDirectiveCount(in: trimmed)
            expectedEffects = [
                "\(directiveCount) directive\(directiveCount == 1 ? "" : "s") queued for AI adjudication.",
                "Concrete effects resolve during the next turn."
            ]
        }

        return NativeDirectivePreview(
            capacityAfter: capacityAfter,
            cost: cost,
            expectedEffects: expectedEffects,
            riskLabel: riskLabel,
            warning: warning
        )
    }

    // Multi-language order classifier. Detects regional orders in English,
    // Portuguese, and Spanish so the game works regardless of the player's
    // selected language or the LLM's response language.

    // Public wrapper for deterministic percentage used by AI drift simulation.

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
            id: "action-\(date)-\(fnv1aHash(trimmed) % 100_000)",
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
    ///
    /// **Mechanical Interaction**:
    /// - Checks that AI generated events contain at least one independent world event (`playerRelated == false`).
    /// - Verifies that the summary and event descriptions are concrete, rejecting placeholder text.
    /// - Ensures that strategic effects do not improperly manipulate hidden tracks like `.militaryReadiness` directly.
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
            let event = normalized(rawEvent, index: index, targetDate: targetDate, country: state.country)
            guard seenEventIDs.insert(event.id).inserted else {
                throw NativeGameEngineError.invalidTurn("Event \(index + 1) reused a duplicate event ID.")
            }
            guard NativeGameEngine.isDate(event.date, inWindowFrom: state.gameDate, to: targetDate) else {
                throw NativeGameEngineError.invalidTurn("Event \(index + 1) date must fall within the generated turn window.")
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
                    NativeGameEngine.isDate($0.date, inWindowFrom: state.gameDate, to: targetDate) &&
                    $0.date == event.date &&
                    $0.eventId == event.id
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
            events: eventsWithSingleMapNudge(events),
            stabilityDelta: Swift.max(-12, Swift.min(12, turn.stabilityDelta)),
            summary: summary,
            worldTensionDelta: Swift.max(-12, Swift.min(12, turn.worldTensionDelta))
        )
    }

    private static func eventsWithSingleMapNudge(_ events: [NativeCampaignEvent]) -> [NativeCampaignEvent] {
        var keptMapNudge = false
        return events.map { event in
            guard let hex = event.hexLeverCode,
                  NativeStrategyContextDatabase.decodeHexLever(hex)?.conflictMode != nil
            else {
                return event
            }
            if !keptMapNudge {
                keptMapNudge = true
                return event
            }

            var next = event
            var clean = hex.trimmingCharacters(in: .whitespacesAndNewlines)
            if clean.lowercased().hasPrefix("0x") {
                clean = String(clean.dropFirst(2))
            }
            next.hexLeverCode = clean.count >= 6 ? "0x\(clean.prefix(6))" : nil
            return next
        }
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
        //
        // **Mechanical Interaction**:
        // 1. Resolves all planned actions linked to the generated events.
        // 2. Evaluates specific action triggers (like "Invade [Region]").
        // 3. Modifies the Economic Ledgers and processes Tactical Nudges (Hex Lever Codes).
        // 4. Applies dynamic penalties (fallout hits, occupation hits) and bounds (clamps) to core metrics (stability, tension).
        // 5. Checks for critical state changes like Collapses or Victory conditions.
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
        let regionalActionIDs = Set(state.plannedActions
            .filter { action in
                let actionText = action.detail.isEmpty ? action.title : action.detail
                return action.status == .planned && regionOrderKind(from: actionText) != nil
            }
            .map(\.id))
        var resolvedActions = state.plannedActions.map { action in
            guard linkedActionIDs.contains(action.id),
                  action.status == .planned,
                  !regionalActionIDs.contains(action.id) else { return action }
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
            let actionText = action.detail.isEmpty ? action.title : action.detail
            if action.status == .planned,
               let regionKind = regionOrderKind(from: actionText)
            {
                guard let regionID = regionID(from: actionText),
                      let region = GeopoliticalMapData.regionByID[regionID]
                else {
                    var next = action
                    next.status = .resolved
                    next.resolvedAt = targetDate
                    resolvedActions[idx] = next
                    additionalEvents.append(unresolvedRegionalOrderEvent(
                        kind: regionKind,
                        action: action,
                        targetDate: targetDate
                    ))
                    continue
                }

                if regionKind != .invade {
                    var next = action
                    next.status = .resolved
                    next.resolvedAt = targetDate
                    resolvedActions[idx] = next
                    additionalEvents.append(resolveRegionalOrder(
                        kind: regionKind,
                        action: action,
                        region: region,
                        state: state,
                        targetDate: targetDate,
                        regionOccupations: &nextRegionOccupations,
                        nuclearFalloutRegions: &nextNuclearRegions,
                        regionConflicts: &nextRegionConflicts
                    ))
                    continue
                }
            }

            if action.status == .planned, regionOrderKind(from: actionText) == .invade {
                if let regionID = regionID(from: actionText) {
                    if let region = GeopoliticalMapData.regionByID[regionID] {
                        let defenderCode = state.regionOccupations[region.id] ?? region.countryCode

                        // **Combat Mechanic**: RISK-style dice roll.
                        // Dice count is determined by military budget sliders.
                        // Attacker parameters: Military budget > 0.6 yields 3 dice. > 0.3 yields 2.
                        let attackerDiceCount: Int = {
                            if state.budgetMilitarySlider > 0.6 { return 3 }
                            if state.budgetMilitarySlider > 0.3 { return 2 }
                            return 1
                        }()
                        let baseAttackerModifier = state.budgetMilitarySlider > 0.8 ? 1 : 0
                        // **Military Units (#8)**: armor and air wings boost the
                        // attacker. Armor/air units each contribute +1 per ~10
                        // units (scaled for balance on a d6 dice system).
                        let armorUnits = state.militaryUnits["armor", default: 0]
                        let airUnits = state.militaryUnits["air", default: 0]
                        let armorBonus = min(1, armorUnits / 10)
                        let airBonus = min(1, airUnits / 10)
                        let unitAttackBonus = armorBonus + airBonus
                        let attackerModifier = baseAttackerModifier + unitAttackBonus

                        // Defender parameters: Local regions defend harder (>0.4 yields 2 dice). AI defends based on budgetPriority.
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

                        // Deterministic Dice Roll (RISK mechanic)
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

                        // Attacker wins if they win more matchups
                        let isSuccess = attackerWins > defenderWins

                        // Detailed Battle Log
                        let defenderName = state.aiCountryStates[defenderCode]?.countryCode ?? defenderCode
                        let battleLog = "Dice Battle for \(region.name): Attacker rolled \(attackerRawRolls) (Mil: +\(baseAttackerModifier), Units: +\(unitAttackBonus) [armor:\(armorUnits), air:\(airUnits)] -> \(attackerSorted)). Defender \(defenderName) rolled \(defenderRawRolls) (Terrain: +\(terrainModifier), Mil: +\(defenderModifier) -> \(defenderSorted)). Matchups: \(matchupDetails.joined(separator: ", "))."

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
        let economicLedgers = NativeStrategyContextDatabase.updatedEconomicLedgers(
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
                  let lever = NativeStrategyContextDatabase.decodeHexLever(hex)
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

        // Calculate occupied regions and nuclear fallout counts for the player
        let occupiedCount = nextRegionOccupations.filter { key, val in
            let reg = GeopoliticalMapData.regionByID[key]
            return reg?.countryCode == state.country.code && val != state.country.code
        }.count

        let falloutCount = nextNuclearRegions.filter { rid in
            let reg = GeopoliticalMapData.regionByID[rid]
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

        // **Crisis Mechanic**: Dynamic economic ledger penalties.
        // Sustaining occupations and dealing with nuclear fallout aggressively drains economic growth,
        // crashes public security, and skyrockets inflation, simulating the domestic cost of warfare.
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
                    id: "ledger-entry-penalty-\(targetDate)",
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
                id: "stability-collapse-\(targetDate)",
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
                    id: "ledger-entry-crisis-\(targetDate)",
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
                id: "stability-crisis-\(targetDate)",
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

        // **Administrative Mechanic**: Dynamic capacity refill.
        // High stability and high service budget refill administrative capacity faster.
        // High rebel control and low stability drain it.
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

        // **Tension Mechanic**: Dynamic world tension escalation.
        // The international system becomes more volatile based on global conflicts,
        // arms races, and aggressive territorial expansions (imperial friction).
        let tensionConflictModes: Set<NativeRegionConflictMode> = [
            .contestedBorder,
            .conventionalOccupation,
            .guerrillaControl,
            .nuclearFallout
        ]
        let activeConflictsCount = nextRegionConflicts.values.filter { tensionConflictModes.contains($0.mode) }.count
        let armsRaceEscalation = state.budgetMilitarySlider > 0.40 ? 2 : 0
        let globalFalloutCount = nextNuclearRegions.count
        let globalOccupiedCount = nextRegionOccupations.filter { key, val in
            let reg = GeopoliticalMapData.regionByID[key]
            return reg?.countryCode == state.country.code && val != state.country.code
        }.count
        let nuclearFalloutEscalation = globalFalloutCount * 5
        let imperialFrictionEscalation = globalOccupiedCount * 1
        let tensionEscalation = activeConflictsCount + armsRaceEscalation + nuclearFalloutEscalation + imperialFrictionEscalation

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

        // **GDP Growth Mechanic**: nominal GDP compounds from real growth each turn.
        // Without this, victory conditions referencing nominalGDPTrillions are unreachable.
        let yearFraction = Double(months) / 12.0
        for (code, var ledger) in finalLedgers {
            let growthMultiplier = 1.0 + (ledger.realGrowthPercent / 100.0) * yearFraction
            ledger.nominalGDPTrillions = Swift.max(0.01, ledger.nominalGDPTrillions * growthMultiplier)

            // **P1-3: Resource depletion** — industrial budget drives extraction.
            // Higher budget = more extraction = faster depletion + trade bonus.
            // Scarcity (< 20% of default) penalizes growth.
            let industryBudget = (code == state.country.code) ? state.budgetMilitarySlider : 0.3
            let extractionRate = 2.0 * industryBudget * yearFraction
            var resourceTradeBonus = 0.0
            var scarcityPenalty = 0.0
            for (resource, reserves) in ledger.resourceReserves {
                let depleted = Swift.max(0, reserves - extractionRate * 10)
                ledger.resourceReserves[resource] = depleted
                // Trade bonus from resource production
                resourceTradeBonus += depleted * 0.01
                // Scarcity penalty when below 20% of default (30 for most, varies)
                let defaultLevel = NativeEconomicLedger.defaultResourceReserves()[resource] ?? 30.0
                if depleted < defaultLevel * 0.2 {
                    scarcityPenalty -= 0.3
                }
            }
            ledger.tradeBalancePercentGDP = clampDouble(ledger.tradeBalancePercentGDP + resourceTradeBonus * yearFraction, -20, 20)
            if scarcityPenalty != 0 {
                ledger.realGrowthPercent = clampDouble(ledger.realGrowthPercent + scarcityPenalty * yearFraction, -12, 16)
            }

            finalLedgers[code] = ledger
        }

        var finalState = NativeCampaignState(
            actionMemory: actionMemory,
            advisorMessages: state.advisorMessages,
            aiReadiness: .available(tokenBudget: "provider-specific context, maxResponse=760"),
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
            mapArmies: state.mapArmies,
            mapBuildings: state.mapBuildings,
            // New strategy fields
            administrativeCapacity: nextCapacity,
            victoryStatus: nextVictoryStatus,
            activeOffers: state.activeOffers,
            budgetMilitarySlider: state.budgetMilitarySlider,
            budgetServicesSlider: state.budgetServicesSlider,
            budgetDiplomacySlider: state.budgetDiplomacySlider,
            techEra: state.techEra,
            researchPoints: state.researchPoints,
            budgetResearchSlider: state.budgetResearchSlider,
            militaryUnits: state.militaryUnits
        )

        if finalState.victoryStatus == .ongoing {
            finalState.victoryStatus = evaluateVictoryStatus(for: finalState)
            if finalState.victoryStatus == .won {
                let winEvent = NativeCampaignEvent(
                    date: targetDate,
                    description: "VICTORY: Your administration successfully achieved all objectives for scenario \(state.scenarioName)!",
                    id: "victory-\(targetDate)",
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
                    id: "timeout-\(targetDate)",
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
        finalState = BackgroundSimulationService.shared.simulatedTurn(finalState)
        finalState.semanticMemory = NativeStrategyContextDatabase.updatedSemanticMemory(
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
                    setConflict(region: region, controllerCode: targetCode, mode: .contestedBorder, intensity: 3, event: event, summary: "\(event.title): \(dynamicCountries[targetCode] ?? targetCode) gains separate political control.", targetDate: targetDate, regionConflicts: &regionConflicts)
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
                    setConflict(region: region, controllerCode: "REB", mode: .guerrillaControl, intensity: 4, event: event, summary: "\(event.title): local control fragments after state dissolution.", targetDate: targetDate, regionConflicts: &regionConflicts)
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
            let sourceRegions = GeopoliticalMapData.regions(forCountryCode: source)
            if let first = sourceRegions.first {
                return [first]
            }
        }
        return GeopoliticalMapData.regions(forCountryCode: state.country.code).prefix(1).map(\.self)
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
            NativeStrategyContextDatabase.startingEconomicLedger(forCode: code, scenario: scenario)
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
                  let lever = NativeStrategyContextDatabase.decodeHexLever(hex)
            else {
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
                let targetRegions = GeopoliticalMapData.regions(forCountryCode: targetCountryCode)
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
                let domesticRegions = GeopoliticalMapData.regions(forCountryCode: countryCode)
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
                let targetRegions = GeopoliticalMapData.regions(forCountryCode: targetCountryCode)
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
                let domesticRegions = GeopoliticalMapData.regions(forCountryCode: countryCode)
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
                let targetRegions = GeopoliticalMapData.regions(forCountryCode: targetCountryCode)
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
                let domesticRegions = GeopoliticalMapData.regions(forCountryCode: countryCode)
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
                let targetRegions = GeopoliticalMapData.regions(forCountryCode: targetCountryCode)
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
                let domesticRegionIDs = GeopoliticalMapData.regions(forCountryCode: countryCode).map(\.id)
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
                let domesticRegions = GeopoliticalMapData.regions(forCountryCode: code)
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
                let domesticRegions = GeopoliticalMapData.regions(forCountryCode: code)
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

    static func advance(date: String, months: Int) -> String {
        guard let value = displayFormatter.date(from: date) else { return date }
        let next = Calendar(identifier: .gregorian).date(byAdding: .month, value: months, to: value) ?? value
        return displayFormatter.string(from: next)
    }

    static func isValidDate(_ value: String) -> Bool {
        displayFormatter.date(from: value) != nil
    }

    static func isDate(_ value: String, inWindowFrom start: String, to end: String) -> Bool {
        guard let date = displayFormatter.date(from: value),
              let startDate = displayFormatter.date(from: start),
              let endDate = displayFormatter.date(from: end)
        else {
            return false
        }
        return date >= startDate && date <= endDate
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

    static func getYear(from dateString: String) -> Int? {
        let parts = dateString.split(separator: "-")
        if let first = parts.first, let year = Int(first) {
            return year
        }
        return nil
    }

    // MARK: - Fog of War

    /// Determines intelligence visibility for a country based on relationship with the player.
    static func intelVisibility(forCountryCode code: String, in state: NativeCampaignState) -> NativeIntelVisibility {
        if code == state.country.code { return .full }
        let relation = state.aiCountryStates[code]?.relationshipScores[state.country.code] ?? 0
        if relation > 50 { return .full }
        if relation > 0 { return .partial }
        return .hidden
    }

    static func afterActionReport(for turn: NativeGeneratedTurn, state: NativeCampaignState) -> NativeAfterActionReport {
        let effects = turn.events.flatMap(\.strategicEffects)
        let stabilityEffects = effects.filter { $0.track == .internalStability }.map(\.magnitude).reduce(0, +)
        let tensionEffects = effects.filter { $0.track == .worldTension || $0.track == .securityAnxiety }.map(\.magnitude).reduce(0, +)
        let economyEffects = effects.filter { $0.track == .economicResilience || $0.track == .marketConfidence }.map(\.magnitude).reduce(0, +)
        let resolvedOrderCount = Set(turn.events.flatMap(\.linkedActionIDs)).count

        return NativeAfterActionReport(
            events: Array(turn.events.prefix(5)),
            metrics: [
                NativeAfterActionMetric(delta: signed(turn.stabilityDelta + stabilityEffects), id: "stability", label: "Stability pressure", value: "\(state.stability)/100"),
                NativeAfterActionMetric(delta: signed(turn.worldTensionDelta + tensionEffects), id: "tension", label: "World tension pressure", value: "\(state.worldTension)/100"),
                NativeAfterActionMetric(delta: signed(economyEffects), id: "economy", label: "Economic effect weight", value: "\(state.economicLedger.fiscalSpaceIndex)/100 fiscal")
            ],
            resolvedOrderCount: resolvedOrderCount,
            summary: sanitizeFoundationModelText(turn.summary)
        )
    }
}
