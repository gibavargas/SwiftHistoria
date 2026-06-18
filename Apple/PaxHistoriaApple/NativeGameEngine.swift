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

    private enum NativeRegionOrderKind {
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

    private static func regionOrderKind(from text: String) -> NativeRegionOrderKind? {
        let trimmed = sanitizeFoundationModelText(text)
        if trimmed.hasPrefix("Invade ") { return .invade }
        if trimmed.hasPrefix("Stabilize ") { return .stabilize }
        if trimmed.hasPrefix("Fortify ") { return .fortify }
        if trimmed.hasPrefix("Withdraw from ") { return .withdraw }
        if trimmed.hasPrefix("Negotiate autonomy for ") { return .autonomy }
        if trimmed.hasPrefix("Rebuild ") { return .rebuild }
        if trimmed.hasPrefix("Open trade corridor through ") { return .tradeCorridor }
        return nil
    }

    private static func regionID(from text: String) -> String? {
        guard let range = text.range(of: "(ID: "),
              let endRange = text.range(of: ")", range: range.upperBound ..< text.endIndex)
        else {
            return nil
        }
        let regionID = String(text[range.upperBound ..< endRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        return regionID.isEmpty ? nil : regionID
    }

    private static func fnv1aHash(_ seed: String) -> UInt64 {
        var hash: UInt64 = 1_469_598_103_934_665_603
        for byte in seed.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return hash
    }

    private static func stablePercentage(seed: String) -> Double {
        Double(fnv1aHash(seed) % 10001) / 100.0
    }

    private static func deterministicDie(seed: String) -> Int {
        Int(fnv1aHash(seed) % 6) + 1
    }

    private static func rollDice(seed: String, count: Int) -> [Int] {
        var rolls: [Int] = []
        for i in 0 ..< count {
            let die = deterministicDie(seed: "\(seed)-die-\(i)")
            rolls.append(die)
        }
        return rolls
    }

    private static func roll512DiceFriction(
        scenarioID: String,
        gameDate: String,
        round: Int,
        playerCountryCode _: String
    ) -> [NativeCampaignEvent] {
        let turnSeed = "\(scenarioID)-\(gameDate)-round-\(round)-512dice"
        var frictionCount = 0
        var events: [NativeCampaignEvent] = []

        // 1. Roll 512 virtual dice with a 5% threshold
        for i in 0 ..< 512 {
            let dieSeed = "\(turnSeed)-die-\(i)"
            let roll = stablePercentage(seed: dieSeed)
            if roll < 5.0 {
                frictionCount += 1

                // Check specific dice to trigger specific narrative events
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
                        description: "A major tectonic volcanic eruption has spewed massive ash clouds into the upper atmosphere. Solar radiation is reduced, cooling global climates and impacting agricultural yields.",
                        id: eventId,
                        importance: .severe,
                        kind: .world,
                        linkedActionIDs: [],
                        notable: true,
                        playerRelated: false,
                        strategicEffects: [
                            NativeStrategicEffect(
                                date: gameDate,
                                eventId: eventId,
                                id: "\(eventId)-effect-econ",
                                magnitude: -3,
                                summary: "Reduced crop yields drag economic resilience.",
                                target: "global",
                                track: .economicResilience
                            ),
                            NativeStrategicEffect(
                                date: gameDate,
                                eventId: eventId,
                                id: "\(eventId)-effect-stability",
                                magnitude: -1,
                                summary: "Food price inflation spikes localized unrest.",
                                target: "global",
                                track: .internalStability
                            )
                        ],
                        title: "Tectonic Eruption & Climate Cooling"
                    ))
                case 88:
                    let eventId = "512dice-fiscal-\(gameDate)"
                    events.append(NativeCampaignEvent(
                        date: gameDate,
                        description: "Credit markets tighten suddenly following high sovereign default risks. Interbank lending freezes, dragging down investor confidence.",
                        id: eventId,
                        importance: .major,
                        kind: .economy,
                        linkedActionIDs: [],
                        notable: true,
                        playerRelated: false,
                        strategicEffects: [
                            NativeStrategicEffect(
                                date: gameDate,
                                eventId: eventId,
                                id: "\(eventId)-effect-market",
                                magnitude: -5,
                                summary: "Credit freeze collapses market confidence.",
                                target: "global",
                                track: .marketConfidence
                            )
                        ],
                        title: "Sovereign Debt Credit Panic"
                    ))
                case 121:
                    let eventId = "512dice-revolts-\(gameDate)"
                    events.append(NativeCampaignEvent(
                        date: gameDate,
                        description: "Widespread strikes and peasant revolts erupt due to compounding economic stress and taxes, causing security concerns in major urban areas.",
                        id: eventId,
                        importance: .major,
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
                                summary: "Widespread protests drop stability.",
                                target: "global",
                                track: .internalStability
                            )
                        ],
                        title: "Widespread Labor & Civil Unrest"
                    ))
                case 201:
                    let eventId = "512dice-pirates-\(gameDate)"
                    events.append(NativeCampaignEvent(
                        date: gameDate,
                        description: "Pirate activity and regional blockades surge in crucial shipping straits. Global trade logistics suffer delays and increased security insurance rates.",
                        id: eventId,
                        importance: .minor,
                        kind: .world,
                        linkedActionIDs: [],
                        notable: false,
                        playerRelated: false,
                        strategicEffects: [
                            NativeStrategicEffect(
                                date: gameDate,
                                eventId: eventId,
                                id: "\(eventId)-effect-econ",
                                magnitude: -3,
                                summary: "Trade lane friction decreases economic resilience.",
                                target: "global",
                                track: .economicResilience
                            )
                        ],
                        title: "Surge in Maritime Piracy"
                    ))
                case 315:
                    let eventId = "512dice-blight-\(gameDate)"
                    events.append(NativeCampaignEvent(
                        date: gameDate,
                        description: "A virulent plant fungus attacks staple grains. Low food supply triggers high prices and drops standard of living.",
                        id: eventId,
                        importance: .major,
                        kind: .economy,
                        linkedActionIDs: [],
                        notable: true,
                        playerRelated: false,
                        strategicEffects: [
                            NativeStrategicEffect(
                                date: gameDate,
                                eventId: eventId,
                                id: "\(eventId)-effect-econ",
                                magnitude: -3,
                                summary: "Blight decreases economic resilience.",
                                target: "global",
                                track: .economicResilience
                            )
                        ],
                        title: "Agrarian Crop Blight"
                    ))
                case 412:
                    let eventId = "512dice-schism-\(gameDate)"
                    events.append(NativeCampaignEvent(
                        date: gameDate,
                        description: "A polarization of ideas splits domestic and international governing bodies, complicating diplomatic consensus.",
                        id: eventId,
                        importance: .minor,
                        kind: .diplomacy,
                        linkedActionIDs: [],
                        notable: false,
                        playerRelated: false,
                        strategicEffects: [
                            NativeStrategicEffect(
                                date: gameDate,
                                eventId: eventId,
                                id: "\(eventId)-effect-diplomacy",
                                magnitude: -2,
                                summary: "Governing polarization reduces diplomatic leverage.",
                                target: "global",
                                track: .diplomaticLeverage
                            )
                        ],
                        title: "Ideological Polarization"
                    ))
                case 501:
                    let eventId = "512dice-breakthrough-\(gameDate)"
                    events.append(NativeCampaignEvent(
                        date: gameDate,
                        description: "A sudden breakthrough in metallurgy and industrial tooling rolls out across manufacturing hubs, accelerating efficiency.",
                        id: eventId,
                        importance: .major,
                        kind: .economy,
                        linkedActionIDs: [],
                        notable: true,
                        playerRelated: false,
                        strategicEffects: [
                            NativeStrategicEffect(
                                date: gameDate,
                                eventId: eventId,
                                id: "\(eventId)-effect-market",
                                magnitude: 4,
                                summary: "Industrial advancement boosts market confidence.",
                                target: "global",
                                track: .marketConfidence
                            )
                        ],
                        title: "Manufacturing & Metallurgical Breakthrough"
                    ))
                default:
                    break
                }
            }
        }

        // 2. Generate the overall global turbulence event based on total friction count
        let overallEventId = "512dice-overall-\(gameDate)"
        if frictionCount < 15 {
            events.append(NativeCampaignEvent(
                date: gameDate,
                description: "With only \(frictionCount) global friction points active (out of 512), the world experiences a rare Golden Age of peace and prosperity. Productivity and domestic satisfaction surge.",
                id: overallEventId,
                importance: .major,
                kind: .world,
                linkedActionIDs: [],
                notable: true,
                playerRelated: false,
                strategicEffects: [
                    NativeStrategicEffect(
                        date: gameDate,
                        eventId: overallEventId,
                        id: "\(overallEventId)-effect-stability",
                        magnitude: 5,
                        summary: "Era of peace raises domestic stability.",
                        target: "global",
                        track: .internalStability
                    ),
                    NativeStrategicEffect(
                        date: gameDate,
                        eventId: overallEventId,
                        id: "\(overallEventId)-effect-market",
                        magnitude: 4,
                        summary: "Global optimism boosts market confidence.",
                        target: "global",
                        track: .marketConfidence
                    )
                ],
                title: "Global Pax Era (Golden Age)"
            ))
        } else if frictionCount >= 15, frictionCount <= 35 {
            events.append(NativeCampaignEvent(
                date: gameDate,
                description: "Normal historical friction recorded at \(frictionCount) points. Standard seasonal fluctuations, minor trade disruptions, and normal labor turnover slightly impact economic resilient buffers.",
                id: overallEventId,
                importance: .minor,
                kind: .world,
                linkedActionIDs: [],
                notable: false,
                playerRelated: false,
                strategicEffects: [
                    NativeStrategicEffect(
                        date: gameDate,
                        eventId: overallEventId,
                        id: "\(overallEventId)-effect-econ",
                        magnitude: -1,
                        summary: "Routine friction slightly drags economic resilience.",
                        target: "global",
                        track: .economicResilience
                    )
                ],
                title: "Historical Friction: Minor Setbacks"
            ))
        } else if frictionCount >= 36, frictionCount <= 45 {
            events.append(NativeCampaignEvent(
                date: gameDate,
                description: "High global friction detected at \(frictionCount) points. Strained resources, border administrative congestion, and localized labor disputes threaten domestic stability.",
                id: overallEventId,
                importance: .major,
                kind: .crisis,
                linkedActionIDs: [],
                notable: true,
                playerRelated: false,
                strategicEffects: [
                    NativeStrategicEffect(
                        date: gameDate,
                        eventId: overallEventId,
                        id: "\(overallEventId)-effect-stability",
                        magnitude: -3,
                        summary: "Widespread friction drags internal stability.",
                        target: "global",
                        track: .internalStability
                    )
                ],
                title: "Global Turbulence: Severe Crises"
            ))
        } else {
            events.append(NativeCampaignEvent(
                date: gameDate,
                description: "Systemic collapse conditions met with \(frictionCount) friction points. Co-occurring natural, economic, and political crises shock the international order.",
                id: overallEventId,
                importance: .severe,
                kind: .crisis,
                linkedActionIDs: [],
                notable: true,
                playerRelated: false,
                strategicEffects: [
                    NativeStrategicEffect(
                        date: gameDate,
                        eventId: overallEventId,
                        id: "\(overallEventId)-effect-stability",
                        magnitude: -6,
                        summary: "Severe cascading instability shocks governments.",
                        target: "global",
                        track: .internalStability
                    ),
                    NativeStrategicEffect(
                        date: gameDate,
                        eventId: overallEventId,
                        id: "\(overallEventId)-effect-econ",
                        magnitude: -5,
                        summary: "Systemic trade breakdown erodes economic resilience.",
                        target: "global",
                        track: .economicResilience
                    ),
                    NativeStrategicEffect(
                        date: gameDate,
                        eventId: overallEventId,
                        id: "\(overallEventId)-effect-market",
                        magnitude: -5,
                        summary: "Panic in credit markets drops market confidence.",
                        target: "global",
                        track: .marketConfidence
                    )
                ],
                title: "BLACK SWAN: Systemic Global Crisis"
            ))
        }

        return events
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

            if action.status == .planned, actionText.hasPrefix("Invade ") {
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
                        let attackerModifier = state.budgetMilitarySlider > 0.8 ? 1 : 0

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
        finalState.semanticMemory = NativeStrategyContextDatabase.updatedSemanticMemory(
            state: finalState,
            events: Array(finalState.timeline.prefix(generatedEvents.count + 2))
        )
        return finalState
    }

    private static func unresolvedRegionalOrderEvent(
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

    private static func resolveRegionalOrder(
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

    private static func signed(_ value: Int) -> String {
        value >= 0 ? "+\(value)" : "\(value)"
    }
}
