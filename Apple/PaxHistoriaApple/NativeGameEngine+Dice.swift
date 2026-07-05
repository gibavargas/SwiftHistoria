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
        playerCountryCode: String,
        stability: Int = 50,
        securityIndex: Double = 50.0,
        worldTension: Int = 50,
        techEra: NativeTechEra = .industrial
    ) -> [NativeCampaignEvent] {
        let turnSeed = "\(scenarioID)-\(gameDate)-round-\(round)-512dice"
        var frictionCount = 0
        var events: [NativeCampaignEvent] = []

        // State-reactive probability modulation
        let stabilityMod = stability > 80 ? 0.3 : (stability < 25 ? 2.0 : 1.0)
        let securityMod = securityIndex > 80 ? 0.4 : (securityIndex < 30 ? 1.5 : 1.0)
        let tensionMod = worldTension > 70 ? 1.5 : (worldTension < 20 ? 0.7 : 1.0)

        // Tension-adjusted global turbulence thresholds
        let goldenAgeThreshold = 15.0 / tensionMod
        let blackSwanThreshold = 45.0 / tensionMod

        // 1. Roll 512 virtual dice with a 5% threshold
        for i in 0 ..< 512 {
            let dieSeed = "\(turnSeed)-die-\(i)"
            let roll = stablePercentage(seed: dieSeed)
            if roll < 5.0 {
                frictionCount += 1

                // Check specific dice to trigger specific narrative events
                switch i {
                case 13: // Epidemic — stability-modulated
                    let effectiveThreshold = 5.0 * stabilityMod
                    if roll < effectiveThreshold {
                        let eventId = "512dice-plague-\(gameDate)"
                        let baseMag1: Double = -4
                        let baseMag2: Double = -3
                        let scaledMag1 = max(-6, min(-2, Int(baseMag1 * tensionMod)))
                        let scaledMag2 = max(-5, min(-1, Int(baseMag2 * tensionMod)))
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
                                    magnitude: scaledMag1,
                                    summary: "Epidemic quarantine suppresses stability.",
                                    target: "global",
                                    track: .internalStability
                                ),
                                NativeStrategicEffect(
                                    date: gameDate,
                                    eventId: eventId,
                                    id: "\(eventId)-effect-econ",
                                    magnitude: scaledMag2,
                                    summary: "Labor shortages degrade economic resilience.",
                                    target: "global",
                                    track: .economicResilience
                                )
                            ],
                            title: "Virulent Epidemic Outbreak"
                        ))
                    }
                case 42: // Volcanic eruption — tension-modulated magnitude
                    let eventId = "512dice-volcano-\(gameDate)"
                    let baseMag1: Double = -3
                    let baseMag2: Double = -1
                    let scaledMag1 = max(-5, min(-1, Int(baseMag1 * tensionMod)))
                    let scaledMag2 = max(-3, min(1, Int(baseMag2 * tensionMod)))
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
                                magnitude: scaledMag1,
                                summary: "Reduced crop yields drag economic resilience.",
                                target: "global",
                                track: .economicResilience
                            ),
                            NativeStrategicEffect(
                                date: gameDate,
                                eventId: eventId,
                                id: "\(eventId)-effect-stability",
                                magnitude: scaledMag2,
                                summary: "Food price inflation spikes localized unrest.",
                                target: "global",
                                track: .internalStability
                            )
                        ],
                        title: "Tectonic Eruption & Climate Cooling"
                    ))
                case 88: // Fiscal credit panic — tension-modulated magnitude
                    let eventId = "512dice-fiscal-\(gameDate)"
                    let baseMag: Double = -5
                    let scaledMag = max(-7, min(-3, Int(baseMag * tensionMod)))
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
                                magnitude: scaledMag,
                                summary: "Credit freeze collapses market confidence.",
                                target: "global",
                                track: .marketConfidence
                            )
                        ],
                        title: "Sovereign Debt Credit Panic"
                    ))
                case 121: // Labor unrest — stability-modulated
                    let effectiveThreshold = 5.0 * stabilityMod
                    if roll < effectiveThreshold {
                        let eventId = "512dice-revolts-\(gameDate)"
                        let baseMag: Double = -4
                        let scaledMag = max(-6, min(-2, Int(baseMag * tensionMod)))
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
                                    magnitude: scaledMag,
                                    summary: "Widespread protests drop stability.",
                                    target: "global",
                                    track: .internalStability
                                )
                            ],
                            title: "Widespread Labor & Civil Unrest"
                        ))
                    }
                case 201: // Piracy — security-modulated
                    let effectiveThreshold = 5.0 * securityMod
                    if roll < effectiveThreshold {
                        let eventId = "512dice-pirates-\(gameDate)"
                        let baseMag: Double = -3
                        let scaledMag = max(-5, min(-1, Int(baseMag * tensionMod)))
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
                                    magnitude: scaledMag,
                                    summary: "Trade lane friction decreases economic resilience.",
                                    target: "global",
                                    track: .economicResilience
                                )
                            ],
                            title: "Surge in Maritime Piracy"
                        ))
                    }
                case 315: // Crop blight — tension-modulated magnitude
                    let eventId = "512dice-blight-\(gameDate)"
                    let baseMag: Double = -3
                    let scaledMag = max(-5, min(-1, Int(baseMag * tensionMod)))
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
                                magnitude: scaledMag,
                                summary: "Blight decreases economic resilience.",
                                target: "global",
                                track: .economicResilience
                            )
                        ],
                        title: "Agrarian Crop Blight"
                    ))
                case 412: // Ideological schism — tension-modulated magnitude
                    let eventId = "512dice-schism-\(gameDate)"
                    let baseMag: Double = -2
                    let scaledMag = max(-4, min(0, Int(baseMag * tensionMod)))
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
                                magnitude: scaledMag,
                                summary: "Governing polarization reduces diplomatic leverage.",
                                target: "global",
                                track: .diplomaticLeverage
                            )
                        ],
                        title: "Ideological Polarization"
                    ))
                case 501: // Tech breakthrough — tension-modulated magnitude
                    let eventId = "512dice-breakthrough-\(gameDate)"
                    let baseMag: Double = 4
                    let scaledMag = max(2, min(6, Int(baseMag * tensionMod)))
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
                                magnitude: scaledMag,
                                summary: "Industrial advancement boosts market confidence.",
                                target: "global",
                                track: .marketConfidence
                            )
                        ],
                        title: "Manufacturing & Metallurgical Breakthrough"
                    ))
                // ── C2: New conditional friction events ──
                case 67: // Cyberattack (digital era+ + low security)
                    if roll < 4.0, techEra != .industrial, securityIndex < 50 {
                        let eventId = "dice-\(scenarioID)-\(round)-cyberattack"
                        let baseMag: Double = -4
                        let scaledMag = max(-6, min(-2, Int(baseMag * tensionMod)))
                        events.append(NativeCampaignEvent(
                            date: gameDate,
                            description: "A coordinated cyberattack targeted critical national infrastructure, disrupting government communications and financial systems for 48 hours.",
                            id: eventId,
                            importance: .severe,
                            kind: .crisis,
                            linkedActionIDs: [],
                            notable: true,
                            playerRelated: false,
                            strategicEffects: [
                                NativeStrategicEffect(
                                    date: gameDate, eventId: eventId,
                                    id: "\(eventId)-eff",
                                    magnitude: scaledMag, summary: "Cyberattack disrupts critical infrastructure, reducing stability.",
                                    target: playerCountryCode, track: .internalStability
                                )
                            ],
                            title: "Cyberattack Disrupts Critical Infrastructure"
                        ))
                    }
                case 156: // Refugee crisis (high tension)
                    if roll < 5.0, worldTension > 50 {
                        let eventId = "dice-\(scenarioID)-\(round)-refugee"
                        let baseMag: Double = -3
                        let scaledMag = max(-5, min(-1, Int(baseMag * tensionMod)))
                        events.append(NativeCampaignEvent(
                            date: gameDate,
                            description: "A surge of displaced persons crossed regional borders following neighboring instability, straining emergency services and temporary shelters.",
                            id: eventId,
                            importance: .major,
                            kind: .crisis,
                            linkedActionIDs: [],
                            notable: true,
                            playerRelated: false,
                            strategicEffects: [
                                NativeStrategicEffect(
                                    date: gameDate, eventId: eventId,
                                    id: "\(eventId)-eff",
                                    magnitude: scaledMag, summary: "Refugee influx strains public services and stability.",
                                    target: playerCountryCode, track: .internalStability
                                )
                            ],
                            title: "Refugee Crisis Strains Border Services"
                        ))
                    }
                case 234: // Energy grid failure (pre-AI age + low stability)
                    if roll < 4.0, techEra == .industrial || techEra == .digital, stability < 40 {
                        let eventId = "dice-\(scenarioID)-\(round)-grid"
                        let baseMagEcon: Double = -3
                        let baseMagStab: Double = -2
                        let scaledMagEcon = max(-5, min(-1, Int(baseMagEcon * tensionMod)))
                        let scaledMagStab = max(-4, min(0, Int(baseMagStab * tensionMod)))
                        events.append(NativeCampaignEvent(
                            date: gameDate,
                            description: "Cascading failures in the aging energy grid left several regions without power for days, disrupting commerce and public services.",
                            id: eventId,
                            importance: .severe,
                            kind: .crisis,
                            linkedActionIDs: [],
                            notable: true,
                            playerRelated: false,
                            strategicEffects: [
                                NativeStrategicEffect(
                                    date: gameDate, eventId: eventId,
                                    id: "\(eventId)-eff",
                                    magnitude: scaledMagEcon, summary: "Grid failures reduce economic resilience and stability.",
                                    target: playerCountryCode, track: .economicResilience
                                ),
                                NativeStrategicEffect(
                                    date: gameDate, eventId: eventId,
                                    id: "\(eventId)-stab",
                                    magnitude: scaledMagStab, summary: "Grid failures reduce public stability.",
                                    target: playerCountryCode, track: .internalStability
                                )
                            ],
                            title: "Cascading Energy Grid Failure"
                        ))
                    }
                case 378: // Pro-democracy protests (low stability)
                    if roll < 4.5, stability < 35 {
                        let eventId = "dice-\(scenarioID)-\(round)-protest"
                        let baseMagStab: Double = -4
                        let baseMagDip: Double = 2
                        let scaledMagStab = max(-6, min(-2, Int(baseMagStab * tensionMod)))
                        let scaledMagDip = max(0, min(4, Int(baseMagDip * tensionMod)))
                        events.append(NativeCampaignEvent(
                            date: gameDate,
                            description: "Mass demonstrations demanding democratic reforms erupted in urban centers, challenging the current government's legitimacy.",
                            id: eventId,
                            importance: .major,
                            kind: .crisis,
                            linkedActionIDs: [],
                            notable: true,
                            playerRelated: false,
                            strategicEffects: [
                                NativeStrategicEffect(
                                    date: gameDate, eventId: eventId,
                                    id: "\(eventId)-eff",
                                    magnitude: scaledMagStab, summary: "Pro-democracy protests threaten internal stability.",
                                    target: playerCountryCode, track: .internalStability
                                ),
                                NativeStrategicEffect(
                                    date: gameDate, eventId: eventId,
                                    id: "\(eventId)-dip",
                                    magnitude: scaledMagDip, summary: "Democratic movement increases diplomatic leverage with liberal nations.",
                                    target: playerCountryCode, track: .diplomaticLeverage
                                )
                            ],
                            title: "Pro-Democracy Protests Erupt Nationwide"
                        ))
                    }
                case 445: // Tech sector boom (digital era+)
                    if roll < 5.0, techEra != .industrial {
                        let eventId = "dice-\(scenarioID)-\(round)-techboom"
                        let baseMag: Double = 3
                        let scaledMag = max(1, min(5, Int(baseMag * tensionMod)))
                        events.append(NativeCampaignEvent(
                            date: gameDate,
                            description: "A breakthrough in technology applications sparked a surge in venture capital investment and startup formation, boosting economic outlook.",
                            id: eventId,
                            importance: .major,
                            kind: .economy,
                            linkedActionIDs: [],
                            notable: true,
                            playerRelated: false,
                            strategicEffects: [
                                NativeStrategicEffect(
                                    date: gameDate, eventId: eventId,
                                    id: "\(eventId)-eff",
                                    magnitude: scaledMag, summary: "Tech sector boom boosts market confidence.",
                                    target: playerCountryCode, track: .marketConfidence
                                )
                            ],
                            title: "Tech Sector Boom Drives Investment Surge"
                        ))
                    }
                default:
                    break
                }
            }
        }

        // 2. Generate the overall global turbulence event based on total friction count
        let overallEventId = "512dice-overall-\(gameDate)"
        if frictionCount < Int(goldenAgeThreshold) {
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
        } else if frictionCount < Int(blackSwanThreshold) {
            if frictionCount <= 35 {
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
            } else {
                // High turbulence zone
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
            }
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
