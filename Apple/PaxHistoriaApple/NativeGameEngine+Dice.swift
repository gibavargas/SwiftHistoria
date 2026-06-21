import Foundation

/// Deterministic dice / FNV-1a hashing / stochastic friction events.
extension NativeGameEngine {
    static func fnv1aHash(_ seed: String) -> UInt64 {
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

    static func stablePercentagePublic(seed: String) -> Double {
        stablePercentage(seed: seed)
    }

    private static func deterministicDie(seed: String) -> Int {
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

    static func roll512DiceFriction(
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
}
