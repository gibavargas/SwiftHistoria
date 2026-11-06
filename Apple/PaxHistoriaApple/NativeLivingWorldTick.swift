import Foundation

// MARK: - Living World: OOP country brains + deterministic daily tick

//
// Each country is governed by a `LWCountryBrain` subclass chosen procedurally
// at world generation from the country's strategy. Brains make the decisions;
// the tick applies them with shared mechanics. Brains are pure decision
// objects: they receive the world and their country, and emit orders — no
// mutation, so they stay testable and side-effect free.

// MARK: Brain orders

struct LWBrainOrders {
    var taxAdjust: Double = 0 // -0.02...0.02 daily drift
    var spendingAdjust: Double = 0
    var constructionTarget: LWBuildingType?
    var warDeclarationTarget: String?
    var allianceProposalTarget: String?
    var mobilization: Bool?
}

// MARK: Brain base class (OOP)

class LWCountryBrain {
    let countryCode: String
    init(countryCode: String) {
        self.countryCode = countryCode
    }

    func makeOrders(world _: LivingWorldState, country _: LWCountry, rng _: LWRNG) -> LWBrainOrders {
        LWBrainOrders()
    }

    /// Vic3-style one-line situation commentary used by the main menu.
    /// State-grounded: situation and cause slots are driven by world
    /// predicates (war participation, fiscal balance, mobilization, infamy,
    /// unrest, threat); the outlook slot reflects brain temperament with a
    /// seeded pick so identical-state countries still differ deterministically.
    func commentary(world: LivingWorldState, country: LWCountry, language: NativeGameLanguage, rng: LWRNG) -> String {
        let atWar = world.wars.contains { $0.attacker == countryCode || $0.defender == countryCode }
        let situation: LWProseKey = atWar
            ? .sitAtWar
            : (fiscalBalance(country) < 0 ? .sitDeficit : (country.mobilized ? .sitMobilized : .sitSteady))
        let threat = threatLevel(world: world, country: country)
        let cause: LWProseKey = if country.infamy > 40 {
            .causeInfamy
        } else if country.radicals > 0.2 {
            .causeRadicals
        } else if threat > 0.4 {
            .causeThreat
        } else {
            .causePeace
        }
        let outlooks = temperamentOutlooks
        let outlook = outlooks[rng.int("outlook-\(countryCode)", in: 0 ..< outlooks.count)]
        let interp = ["country": country.name]
        return [
            LWProse.string(situation, language: language, interp),
            LWProse.string(cause, language: language, interp),
            LWProse.string(outlook, language: language)
        ].joined(separator: " ")
    }

    /// Outlook fragments matching this brain's temperament.
    var temperamentOutlooks: [LWProseKey] {
        [.outlookCaution, .outlookTrade]
    }

    // Shared heuristics -------------------------------------------------

    /// Fiscal balance estimate used by every brain.
    func fiscalBalance(_ country: LWCountry) -> Double {
        let income = country.pops.total * country.taxLevel * 0.02
        let spending = country.pops.total * (0.008 + country.spendingLevel * 0.012)
        return income - spending
    }

    func threatLevel(world: LivingWorldState, country: LWCountry) -> Double {
        var threat = 0.0
        for war in world.wars {
            if war.defender == countryCode {
                threat += 0.6
            } else if war.attacker == countryCode {
                threat += 0.2
            }
            let attacker = world.countries[war.attacker]
            if let attacker, war.defender == countryCode, attacker.armyPower > country.armyPower * 1.2 {
                threat += 0.3
            }
        }
        // Hostile great-power neighbors raise anxiety.
        for (code, other) in world.countries.sorted(by: { $0.key < $1.key }) {
            guard code != countryCode else { continue }
            if world.relation(from: code, to: countryCode) < -40, other.isGreatPower {
                threat += 0.15
            }
        }
        return threat
    }

    func weakestNeighbor(world: LivingWorldState, country _: LWCountry) -> String? {
        let candidates = world.countries.values
            .filter { $0.code != countryCode && world.relation(from: countryCode, to: $0.code) < 10 }
            .sorted { $0.armyPower < $1.armyPower }
        return candidates.first?.code
    }
}

// MARK: Concrete brains

final class LWBalancedBrain: LWCountryBrain {
    override func makeOrders(world: LivingWorldState, country: LWCountry, rng: LWRNG) -> LWBrainOrders {
        var orders = LWBrainOrders()
        let balance = fiscalBalance(country)
        orders.taxAdjust = balance < 0 ? 0.01 : -0.005
        orders.spendingAdjust = balance > 0 ? 0.01 : -0.01
        // Construction focus drifts with a seeded die so balanced economies
        // don't all queue the identical building forever.
        if country.infrastructure < 50 {
            orders.constructionTarget = rng.chance("build-infra-\(countryCode)", probability: 0.8) ? .constructionSector : .commercialFarms
        } else {
            orders.constructionTarget = rng.chance("build-farms-\(countryCode)", probability: 0.8) ? .commercialFarms : .toolingWorks
        }
        if threatLevel(world: world, country: country) > 0.5 {
            orders.mobilization = true
        }
        return orders
    }
}

final class LWExpansionistBrain: LWCountryBrain {
    override func makeOrders(world: LivingWorldState, country: LWCountry, rng: LWRNG) -> LWBrainOrders {
        var orders = LWBrainOrders()
        let balance = fiscalBalance(country)
        orders.taxAdjust = balance < 0 ? 0.015 : 0.0
        orders.constructionTarget = .armsIndustry
        let threat = threatLevel(world: world, country: country)

        // Declare war when strong, calm at home, and a soft target exists.
        if !country.mobilized {
            orders.mobilization = threat > 0.2 || rng.chance("mob-\(countryCode)", probability: 0.002)
        }
        if country.mobilized, country.warExhaustion < 20, country.infamy < 60,
           rng.chance("war-\(countryCode)", probability: 0.004),
           let target = weakestNeighbor(world: world, country: country)
        {
            let targetCountry = world.countries[target]
            if let targetCountry, targetCountry.armyPower < country.armyPower * 0.8 {
                orders.warDeclarationTarget = target
            }
        }
        // Seek allies against stronger worlds.
        if threat > 0.4, rng.chance("ally-\(countryCode)", probability: 0.01) {
            orders.allianceProposalTarget = world.sortedCountryCodes().first { $0 != countryCode && world.relation(from: countryCode, to: $0) > 30 }
        }
        return orders
    }

    override var temperamentOutlooks: [LWProseKey] {
        [.outlookAmbition, .outlookOpportunity]
    }
}

final class LWTurtleBrain: LWCountryBrain {
    override func makeOrders(world: LivingWorldState, country: LWCountry, rng: LWRNG) -> LWBrainOrders {
        var orders = LWBrainOrders()
        let balance = fiscalBalance(country)
        orders.taxAdjust = balance < 0 ? 0.008 : 0.0
        orders.spendingAdjust = balance < 0 ? -0.02 : -0.005
        // Turtles diversify slowly: mostly farms, occasionally mines.
        orders.constructionTarget = rng.chance("build-diversify-\(countryCode)", probability: 0.2) ? .mines : .commercialFarms
        orders.mobilization = threatLevel(world: world, country: country) > 0.8 ? true : nil
        return orders
    }

    override var temperamentOutlooks: [LWProseKey] {
        [.outlookTrade]
    }
}

final class LWOpportunistBrain: LWCountryBrain {
    override func makeOrders(world: LivingWorldState, country: LWCountry, rng: LWRNG) -> LWBrainOrders {
        var orders = LWBrainOrders()
        let balance = fiscalBalance(country)
        orders.taxAdjust = balance < 0 ? 0.012 : -0.004
        orders.constructionTarget = rng.chance("build-\(countryCode)", probability: 0.5) ? .mines : .consumerFactories

        // Pounce on countries already losing a war.
        if country.mobilized, country.warExhaustion < 15,
           rng.chance("pounce-\(countryCode)", probability: 0.003),
           let losing = world.wars.first(where: { $0.exhaustionDefender > 40 })?.defender,
           losing != countryCode,
           let losingCountry = world.countries[losing],
           losingCountry.armyPower < country.armyPower * 0.7
        {
            orders.warDeclarationTarget = losing
        }
        if !country.mobilized, rng.chance("mob-\(countryCode)", probability: 0.001) {
            orders.mobilization = true
        }
        return orders
    }

    override var temperamentOutlooks: [LWProseKey] {
        [.outlookOpportunity, .outlookTrade]
    }
}

// MARK: Brain selection

enum LWBrainFactory {
    static func brain(for country: LWCountry) -> LWCountryBrain {
        switch country.strategy {
        case .balanced: LWBalancedBrain(countryCode: country.code)
        case .expansionist: LWExpansionistBrain(countryCode: country.code)
        case .economicTurtle: LWTurtleBrain(countryCode: country.code)
        case .opportunist: LWOpportunistBrain(countryCode: country.code)
        }
    }
}

// MARK: Daily tick

enum LivingWorldTick {
    /// Advances the world one day. Pure function: same inputs, same outputs.
    /// `playerOrders` allow the player country to act like any other.
    static func advanceDay(_ world: LivingWorldState, playerOrders: LWBrainOrders?) -> LivingWorldState {
        // If a critical decision is pending, the world clock is held until a choice is formed.
        guard world.pendingDecision == nil else {
            return world
        }
        var world = world
        world.dayIndex += 1
        let rng = LWRNG(worldSeed: world.worldSeed, dayIndex: world.dayIndex)
        var newEvents: [LWEventRecord] = []

        // 1. Brains issue orders.
        var ordersByCode: [String: LWBrainOrders] = [:]
        for code in world.sortedCountryCodes() {
            guard var country = world.countries[code] else { continue }
            let orders: LWBrainOrders = if code == world.playerCountryCode, let playerOrders {
                playerOrders
            } else {
                LWBrainFactory.brain(for: country).makeOrders(world: world, country: country, rng: rng)
            }
            ordersByCode[code] = orders
            country.mobilized = orders.mobilization ?? country.mobilized
            world.countries[code] = country
        }

        // 2. Production: buildings consume inputs, produce output, pay wages.
        var market = world.market
        for code in world.sortedCountryCodes() {
            guard var country = world.countries[code] else { continue }
            var revenue = 0.0
            var wages = 0.0
            for index in country.buildings.indices {
                let building = country.buildings[index]
                let efficiency = country.infrastructure / 100.0
                let output = Double(building.levels) * building.staffing * (building.type.workersPerLevel / 1000.0) * efficiency
                market.addSupply(output, goodID: building.type.outputGood)
                let price = market.price(for: building.type.outputGood)
                revenue += output * price * 0.01
                for (inputID, amount) in building.type.inputGoods {
                    market.addDemand(output * amount, goodID: inputID)
                    wages -= output * amount * market.price(for: inputID) * 0.01
                }
                wages += output * 0.008
                let profit = revenue - wages
                country.buildings[index].lastProfit = profit
            }
            // Treasury: taxes + spending.
            let balance = country.pops.total * (country.taxLevel * 0.02 - (0.008 + country.spendingLevel * 0.012))
            country.treasury += balance
            if country.treasury < 0 {
                country.debt += -country.treasury
                country.treasury = 0
                country.radicals = min(1, country.radicals + 0.0008)
            }
            // Pops buy from the market with unit price elasticity (clamped):
            // demand contracts as prices rise and expands as they fall, which
            // is the negative feedback that lets prices find an interior
            // equilibrium instead of ratcheting to a bound.
            let grainElastic = min(2.0, max(0.5, LWMarket.elasticDemand(basePrice: 20, price: market.price(for: "grain"))))
            market.addDemand(country.pops.total * 1.8 * grainElastic, goodID: "grain")
            let consumerElastic = min(2.0, max(0.5, LWMarket.elasticDemand(basePrice: 60, price: market.price(for: "consumer_goods"))))
            market.addDemand(country.pops.total * 0.15 * (country.infrastructure / 100.0) * min(2, country.standardOfLiving / 10) * consumerElastic, goodID: "consumer_goods")
            let luxuryElastic = min(2.0, max(0.5, LWMarket.elasticDemand(basePrice: 45, price: market.price(for: "luxury_food"))))
            market.addDemand(country.pops.total * 0.06 * max(0, (country.standardOfLiving - 10) / 10) * luxuryElastic, goodID: "luxury_food")
            // Standard of living drifts with market participation + spending.
            let solTarget = 8.0 + country.spendingLevel * 6 + min(10, revenue * 0.02) - country.radicals * 4
            country.standardOfLiving += (solTarget - country.standardOfLiving) * 0.01
            world.countries[code] = country
        }

        // 3. Price discovery.
        market.resolveDay(goods: world.goods)
        world.market = market

        // 4. Diplomacy drift + pact fulfillment.
        for pact in world.pacts {
            world.adjustRelation(from: pact.a, to: pact.b, delta: 0.05)
        }

        // 5. Wars: fronts move, exhaustion accrues, peace becomes possible.
        var survivingWars: [LWWar] = []
        for war in world.wars {
            var war = war
            let attacker = world.countries[war.attacker]
            let defender = world.countries[war.defender]
            guard let attacker, let defender else { continue }
            var frontProgress: Double = 0
            for index in war.fronts.indices {
                let attackStrength = attacker.armyPower * (attacker.mobilized ? 1.0 : 0.6) * (1 + Double(war.attackerAllies.count) * 0.1)
                let defenseStrength = defender.armyPower * (defender.mobilized ? 1.15 : 0.7) * (1 + Double(war.defenderAllies.count) * 0.1)
                let push = (attackStrength - defenseStrength) / max(attackStrength + defenseStrength, 1) * 2 * war.fronts[index].intensity
                war.fronts[index].progress = min(100, max(-100, war.fronts[index].progress + push))
                frontProgress += war.fronts[index].progress
            }
            let avgProgress = frontProgress / Double(max(1, war.fronts.count))
            war.exhaustionAttacker = min(100, war.exhaustionAttacker + 0.15 - max(0, avgProgress) * 0.002)
            war.exhaustionDefender = min(100, war.exhaustionDefender + 0.15 - max(0, -avgProgress) * 0.002)

            // Peace: exhaustion or decisive progress ends the war.
            let exhausted = min(war.exhaustionAttacker, war.exhaustionDefender) > 70
            let decisive = abs(avgProgress) > 80
            if exhausted || decisive {
                let winnerIsAttacker = avgProgress > 0
                var winner = world.countries[winnerIsAttacker ? war.attacker : war.defender]!
                var loser = world.countries[winnerIsAttacker ? war.defender : war.attacker]!
                winner.infamy = min(100, winner.infamy + 8)
                loser.radicals = min(1, loser.radicals + 0.05)
                winner.treasury += min(50, max(5, loser.treasury * 0.2))
                loser.treasury -= min(50, max(5, loser.treasury * 0.2))
                world.countries[winner.code] = winner
                world.countries[loser.code] = loser
                newEvents.append(LWEventRecord(
                    id: "peace-\(war.id)-\(world.dayIndex)",
                    day: world.dayIndex,
                    title: LWProse.string(.peaceTitle, language: world.language, ["goal": war.warGoal]),
                    summary: LWProse.string(.peaceSummary, language: world.language, ["winner": winner.name, "loser": loser.name]),
                    countryCode: winner.code,
                    rarity: .rare,
                    severity: 0.7
                ))
                continue
            }
            survivingWars.append(war)
        }
        world.wars = survivingWars

        // 6. Execute brain orders (war declarations, alliances, construction).
        for code in world.sortedCountryCodes() {
            guard let orders = ordersByCode[code], var country = world.countries[code] else { continue }
            country.taxLevel = min(0.6, max(0.05, country.taxLevel + orders.taxAdjust))
            country.spendingLevel = min(1, max(0.1, country.spendingLevel + orders.spendingAdjust))
            if let target = orders.constructionTarget, country.treasury > 20 {
                if let index = country.buildings.firstIndex(where: { $0.type == target }) {
                    country.buildings[index].levels += 1
                    country.treasury -= 8
                }
            }
            if let target = orders.warDeclarationTarget,
               !world.wars.contains(where: { $0.attacker == code && $0.defender == target }),
               let targetCountry = world.countries[target],
               country.armyPower > 5
            {
                let warID = "war-\(code)-\(target)-\(world.dayIndex)"
                world.wars.append(LWWar(
                    id: warID,
                    attacker: code,
                    defender: target,
                    startedDay: world.dayIndex,
                    warGoal: LWProse.string(.warGoalConcessions, language: world.language, ["country": targetCountry.name]),
                    attackerAllies: allies(of: code, world: world),
                    defenderAllies: allies(of: target, world: world),
                    fronts: [
                        LWFront(id: "\(warID)-front-1", attacker: code, defender: target, progress: 0, intensity: 0.8)
                    ],
                    exhaustionAttacker: 0,
                    exhaustionDefender: 0
                ))
                country.infamy = min(100, country.infamy + 12)
                world.adjustRelation(from: code, to: target, delta: -60)
                newEvents.append(LWEventRecord(
                    id: "war-\(warID)",
                    day: world.dayIndex,
                    title: LWProse.string(.warDeclarationTitle, language: world.language, ["country": country.name, "target": targetCountry.name]),
                    summary: LWProse.string(.warDeclarationSummary, language: world.language),
                    countryCode: code,
                    rarity: .rare,
                    severity: 0.9
                ))
            }
            if let target = orders.allianceProposalTarget,
               !world.pacts.contains(where: { $0.kind == .alliance && (($0.a == code && $0.b == target) || ($0.a == target && $0.b == code)) }),
               world.relation(from: target, to: code) > 25
            {
                world.pacts.append(LWPact(kind: .alliance, a: code, b: target, sinceDay: world.dayIndex))
                world.adjustRelation(from: code, to: target, delta: 15)
                newEvents.append(LWEventRecord(
                    id: "pact-\(code)-\(target)-\(world.dayIndex)",
                    day: world.dayIndex,
                    title: LWProse.string(.allianceTitle, language: world.language),
                    summary: LWProse.string(.allianceSummary, language: world.language, ["country": country.name, "target": world.countries[target]?.name ?? target]),
                    countryCode: code,
                    rarity: .weekly,
                    severity: 0.3
                ))
            }
            world.countries[code] = country
        }

        // 7. Procedural daily/weekly/rare events (common vs rare cadence).
        if rng.chance("daily-flavor", probability: 0.30) {
            let codes = world.sortedCountryCodes()
            if let code = codes.isEmpty ? nil : codes[rng.int("daily-pick", in: 0 ..< codes.count)], let country = world.countries[code] {
                newEvents.append(LWEventRecord(
                    id: "flavor-\(world.dayIndex)-\(code)",
                    day: world.dayIndex,
                    title: LWProse.string(.dispatchTitle, language: world.language, ["country": country.name]),
                    summary: LWProse.dispatchFlavor(language: world.language, country: country.name, rng: rng, stream: "flavor-pick"),
                    countryCode: code,
                    rarity: .daily,
                    severity: 0.1
                ))
            }
        }
        if rng.chance("weekly-crisis", probability: 0.02) {
            let codes = world.sortedCountryCodes()
            if let code = codes.isEmpty ? nil : codes[rng.int("crisis-pick", in: 0 ..< codes.count)], var country = world.countries[code] {
                country.radicals = min(1, country.radicals + 0.03)
                world.countries[code] = country
                newEvents.append(LWEventRecord(
                    id: "crisis-\(world.dayIndex)-\(code)",
                    day: world.dayIndex,
                    title: LWProse.string(.crisisTitle, language: world.language, ["country": country.name]),
                    summary: LWProse.string(.crisisSummary, language: world.language),
                    countryCode: code,
                    rarity: .weekly,
                    severity: 0.5
                ))
            }
        }

        // 7.5. Alternative History & Dynamic Causality Event Chains
        let chainEvents = processEventChains(world: &world, rng: rng)
        newEvents.append(contentsOf: chainEvents)

        // 8. History (presentational feed cap; state keeps authoritative tail).
        newEvents.sort { $0.day < $1.day }
        world.history.append(contentsOf: newEvents)
        if world.history.count > 400 {
            world.history.removeFirst(world.history.count - 400)
        }

        return world
    }

    static func allies(of code: String, world: LivingWorldState) -> [String] {
        world.pacts
            .filter { $0.kind == .alliance || $0.kind == .defensivePact }
            .map { pact -> String in
                if pact.a == code { return pact.b }
                if pact.b == code { return pact.a }
                return ""
            }
            .filter { !$0.isEmpty && world.countries[$0] != nil }
    }

    // MARK: - Event Chains & Interactive Decisions

    /// Evaluates dynamic triggers and story chains. If an event targets the player,
    /// `world.pendingDecision` is set to pause the clock until a choice is selected.
    /// If an event targets an AI nation, the AI chooses an option autonomously according
    /// to its temperament and logs the dispatch to global history.
    static func processEventChains(world: inout LivingWorldState, rng: LWRNG) -> [LWEventRecord] {
        var records: [LWEventRecord] = []
        guard world.pendingDecision == nil else { return records }

        guard let event = evaluateNextChainCandidate(world: world, rng: rng) else {
            return records
        }

        if event.countryCode == world.playerCountryCode {
            // Player nation: halt gameplay until decision forms
            world.pendingDecision = event
            records.append(LWEventRecord(
                id: "decision-pending-\(event.id)",
                day: world.dayIndex,
                title: "CRITICAL DECISION: \(event.title)",
                summary: "\(event.summary) The executive must select a response to proceed.",
                countryCode: event.countryCode,
                rarity: event.rarity,
                severity: event.severity,
                imageAssetName: event.imageAssetName
            ))
        } else {
            // Autonomous AI nation resolution: world progresses without player action
            if let country = world.countries[event.countryCode] {
                let chosenOption = chooseAIOption(for: country, event: event, rng: rng)
                world = applyDecisionEffects(world: world, countryCode: event.countryCode, decision: event, option: chosenOption)
                world.completedChainEvents.append(event.id)
                if let next = chosenOption.nextChainedEventID {
                    world.eventFlags.append(next)
                }
                if let flag = chosenOption.flagSet {
                    world.eventFlags.append(flag)
                }
                records.append(LWEventRecord(
                    id: "ai-decision-\(event.id)-\(world.dayIndex)",
                    day: world.dayIndex,
                    title: "\(country.name): \(event.title)",
                    summary: "\(event.summary) Government response: \(chosenOption.label).",
                    countryCode: event.countryCode,
                    rarity: event.rarity,
                    severity: event.severity,
                    imageAssetName: event.imageAssetName,
                    decisionChosen: chosenOption.label
                ))
            }
        }

        return records
    }

    /// Evaluates active event flags, dynamic economic triggers, and historical dates.
    static func evaluateNextChainCandidate(world: LivingWorldState, rng: LWRNG) -> LWDecisionEvent? {
        let completed = Set(world.completedChainEvents)
        let flags = Set(world.eventFlags)
        let day = world.dayIndex
        let playerCode = world.playerCountryCode

        // --- 1. Follow-up chained events triggered by previous decisions ---

        // Soviet Coup follow-ups
        if flags.contains("soviet-miners-strike") && !completed.contains("soviet-miners-strike") {
            let target = resolveTarget(preferredCodes: ["SOV", "RUS"], world: world)
            return LWDecisionEvent(
                id: "soviet-miners-strike",
                day: day,
                title: "Donbas Miners General Strike & Factory Lockouts",
                summary: "Over 120,000 coal miners extinguish blast furnaces across the industrial basin, cutting off coking coal to metallurgical plants and heating gas as winter arrives.",
                countryCode: target,
                rarity: .rare,
                severity: 0.85,
                imageAssetName: "EventBreadRiots",
                chainID: "soviet-coup",
                options: [
                    LWDecisionOption(
                        id: "soviet-miners-force",
                        label: "Deploy Internal Troops to Secure Mineheads",
                        detail: "Garrison mine pits by armed detachment to enforce extraction quotas.",
                        treasuryDelta: 6,
                        radicalsDelta: 0.08,
                        mechanicCode: "⟦MIL⟧"
                    ),
                    LWDecisionOption(
                        id: "soviet-miners-integrate",
                        label: "Integrate Strike Councils into Gosplan Digital Boards",
                        detail: "Offer digital planning seats and wage indexation to end the wildcat stoppage.",
                        treasuryDelta: -10,
                        radicalsDelta: -0.06,
                        nextChainedEventID: "soviet-ogas-launch",
                        mechanicCode: "⟦ECO⟧"
                    )
                ]
            )
        }

        if flags.contains("soviet-ogas-launch") && !completed.contains("soviet-ogas-launch") {
            let target = resolveTarget(preferredCodes: ["SOV", "RUS"], world: world)
            return LWDecisionEvent(
                id: "soviet-ogas-launch",
                day: day,
                title: "Directive 44: OGAS-2 Cybernetic Network Launch",
                summary: "Mainframe arrays across industrial ministries are interconnected with high-capacity optical lines, automating supply allocations across 24,000 state enterprises.",
                countryCode: target,
                rarity: .rare,
                severity: 0.8,
                imageAssetName: "EventCyberBlackout",
                chainID: "soviet-coup",
                options: [
                    LWDecisionOption(
                        id: "soviet-ogas-quotas",
                        label: "Enforce Automated Enterprise Quotas",
                        detail: "Automated input-output allocations bypass regional bureaucracy.",
                        treasuryDelta: 20,
                        radicalsDelta: 0.02,
                        nextChainedEventID: "soviet-techno-bloc",
                        mechanicCode: "⟦ECO⟧"
                    ),
                    LWDecisionOption(
                        id: "soviet-ogas-dual",
                        label: "Permit Dual-Track Electronic Enterprise Trade",
                        detail: "Allow enterprises to trade above-quota surplus on monitored digital exchanges.",
                        treasuryDelta: 12,
                        stabilityDelta: 0.05,
                        mechanicCode: "⟦MKT⟧"
                    )
                ]
            )
        }

        if flags.contains("soviet-techno-bloc") && !completed.contains("soviet-techno-bloc") {
            let target = resolveTarget(preferredCodes: ["SOV", "RUS"], world: world)
            return LWDecisionEvent(
                id: "soviet-techno-bloc",
                day: day,
                title: "Comecon Red Techno-Bloc Customs Union",
                summary: "A unified closed technological common market is established with East Berlin, Warsaw, and Minsk clearing settlements in digital Inforubles.",
                countryCode: target,
                rarity: .rare,
                severity: 0.8,
                imageAssetName: "EventSovietCoup",
                chainID: "soviet-coup",
                options: [
                    LWDecisionOption(
                        id: "soviet-techno-fabs",
                        label: "Subsidize Dresden & Minsk Silicon Lithography Fabs",
                        detail: "Finance indigenous microchip manufacturing to insulate the bloc from Western embargoes.",
                        treasuryDelta: -16,
                        stabilityDelta: 0.07,
                        mechanicCode: "⟦ECO⟧"
                    ),
                    LWDecisionOption(
                        id: "soviet-techno-nordic",
                        label: "Offer Energy-for-Tech Pacts to Nordic Neutrals",
                        detail: "Trade cheap Siberian natural gas for Scandinavian telecommunication tooling.",
                        treasuryDelta: 24,
                        radicalsDelta: -0.03,
                        mechanicCode: "⟦DIP⟧"
                    )
                ]
            )
        }

        // Fashoda / Imperial Confrontation follow-ups
        if flags.contains("fashoda-channel-mobilization") && !completed.contains("fashoda-channel-mobilization") {
            let target = resolveTarget(preferredCodes: ["GBR", "FRA"], world: world)
            return LWDecisionEvent(
                id: "fashoda-channel-mobilization",
                day: day,
                title: "Channel Fleet Mobilization & Toulon Standoff",
                summary: "Battle squadrons concentrate at Portsmouth and Toulon as war preparations accelerate over the Nile expedition crisis. Maritime insurance rates surge.",
                countryCode: target,
                rarity: .rare,
                severity: 0.85,
                imageAssetName: "EventFashodaCrisis",
                chainID: "fashoda",
                options: [
                    LWDecisionOption(
                        id: "fashoda-channel-league",
                        label: "Propose Secret Tripartite League in Berlin",
                        detail: "Approach the German Kaiser to form a continental counter-weight.",
                        treasuryDelta: -10,
                        nextChainedEventID: "fashoda-continental-league",
                        mechanicCode: "⟦DIP⟧"
                    ),
                    LWDecisionOption(
                        id: "fashoda-channel-arbitrate",
                        label: "Accept American Maritime Arbitration",
                        detail: "Concede diplomatic arbitration to avert catastrophic naval clash.",
                        treasuryDelta: -4,
                        worldTensionDelta: -15,
                        mechanicCode: "⟦DIP⟧"
                    )
                ]
            )
        }

        if flags.contains("fashoda-continental-league") && !completed.contains("fashoda-continental-league") {
            let target = resolveTarget(preferredCodes: ["DEU", "FRA", "RUS"], world: world)
            return LWDecisionEvent(
                id: "fashoda-continental-league",
                day: day,
                title: "The Continental League of Berlin: The Kaiser's Gambit",
                summary: "Diplomats gather in Berlin to negotiate a tripartite alliance balancing British naval dominance across Atlantic and Indian Ocean sealanes.",
                countryCode: target,
                rarity: .rare,
                severity: 0.8,
                imageAssetName: "EventFashodaCrisis",
                chainID: "fashoda",
                options: [
                    LWDecisionOption(
                        id: "fashoda-league-ratify",
                        label: "Ratify Tripartite Naval Construction Quotas",
                        detail: "Coordinate capital ship building programs across continental yards.",
                        treasuryDelta: -20,
                        worldTensionDelta: 15,
                        nextChainedEventID: "fashoda-dreadnought-panic",
                        mechanicCode: "⟦MIL⟧"
                    ),
                    LWDecisionOption(
                        id: "fashoda-league-treaty-ports",
                        label: "Direct League Pressure toward Asian Treaty Ports",
                        detail: "Claim joint colonial concessions along the Yangtze River.",
                        treasuryDelta: 15,
                        mechanicCode: "⟦ECO⟧"
                    )
                ]
            )
        }

        if flags.contains("fashoda-dreadnought-panic") && !completed.contains("fashoda-dreadnought-panic") {
            let target = resolveTarget(preferredCodes: ["GBR", "DEU"], world: world)
            return LWDecisionEvent(
                id: "fashoda-dreadnought-panic",
                day: day,
                title: "The Dreadnought Panic: Arms Race in the North Sea",
                summary: "All-big-gun turbine battleships render existing fleets second-class overnight, setting off emergency naval appropriation debates in parliament.",
                countryCode: target,
                rarity: .rare,
                severity: 0.85,
                imageAssetName: "EventBreadRiots",
                chainID: "fashoda",
                options: [
                    LWDecisionOption(
                        id: "dreadnought-build",
                        label: "Authorize Emergency Battlecruiser Program",
                        detail: "Lay down six turbine dreadnoughts to maintain maritime supremacy.",
                        treasuryDelta: -28,
                        radicalsDelta: 0.04,
                        mechanicCode: "⟦MIL⟧"
                    ),
                    LWDecisionOption(
                        id: "dreadnought-hague",
                        label: "Sponsor Hague Naval Limitation Convention",
                        detail: "Propose international fleet tonnage caps to avert fiscal ruin.",
                        treasuryDelta: 4,
                        worldTensionDelta: -10,
                        mechanicCode: "⟦DIP⟧"
                    )
                ]
            )
        }

        // Cyber & Resource follow-ups
        if flags.contains("cyber-microgrid-secession") && !completed.contains("cyber-microgrid-secession") {
            let target = resolveTarget(preferredCodes: ["USA", "DEU", "JPN"], world: world)
            return LWDecisionEvent(
                id: "cyber-microgrid-secession",
                day: day,
                title: "Smart Microgrid Cleavage: Bioregional Energy Secession",
                summary: "Agrarian cooperatives and municipal districts detach from centralized high-voltage grids into autonomous solar-battery networks.",
                countryCode: target,
                rarity: .rare,
                severity: 0.75,
                imageAssetName: "EventSolarpunkDawn",
                chainID: "cyber",
                options: [
                    LWDecisionOption(
                        id: "microgrid-charter",
                        label: "Charter Cooperative Regional Energy Commons",
                        detail: "Recognize decentralized energy micro-grids and issue bioregional energy credits.",
                        treasuryDelta: -10,
                        stabilityDelta: 0.08,
                        mechanicCode: "⟦STB⟧"
                    ),
                    LWDecisionOption(
                        id: "microgrid-enforce",
                        label: "Reassert Central Grid Primacy with National Guard",
                        detail: "Mandate high-voltage interconnection and federal transmission rights-of-way.",
                        treasuryDelta: 8,
                        radicalsDelta: 0.06,
                        mechanicCode: "⟦SEC⟧"
                    )
                ]
            )
        }

        if flags.contains("resource-fertilizer-crisis") && !completed.contains("resource-fertilizer-crisis") {
            let target = resolveTarget(preferredCodes: ["IND", "BRA", "EGY"], world: world)
            return LWDecisionEvent(
                id: "resource-fertilizer-crisis",
                day: day,
                title: "Global Nitrogen Fertilizer Deficit & Sovereign Bread Riots",
                summary: "Natural gas feed supply bottlenecks shutter synthetic fertilizer plants worldwide. Phosphate and urea prices surge 220%, sparking demonstrations.",
                countryCode: target,
                rarity: .rare,
                severity: 0.85,
                imageAssetName: "EventBreadRiots",
                chainID: "resource",
                options: [
                    LWDecisionOption(
                        id: "fertilizer-subsidies",
                        label: "Issue Universal Bread Subsidies from Treasury",
                        detail: "Cap consumer grain prices and absorb bakery deficits from state reserves.",
                        treasuryDelta: -25,
                        radicalsDelta: -0.07,
                        mechanicCode: "⟦ECO⟧"
                    ),
                    LWDecisionOption(
                        id: "fertilizer-guard",
                        label: "Deploy Gendarmerie to Secure Granary Depots",
                        detail: "Impose curfews around regional grain silos to prevent hoarding.",
                        treasuryDelta: -4,
                        radicalsDelta: 0.08,
                        mechanicCode: "⟦SEC⟧"
                    )
                ]
            )
        }

        // --- 2. Dynamic Victoria-style mechanics feedback loops ---

        // Staple grain price surge (> +50% over base)
        if (world.market.prices["grain"] ?? 20) >= 30.0 && !completed.contains("lw-grain-surge") {
            let target = resolveTargetByRadicalsOrPlayer(world: world)
            return LWDecisionEvent(
                id: "lw-grain-surge",
                day: day,
                title: "Staple Grain Price Surge & Food Insecurity",
                summary: "Grain spot markets have climbed over 50% above baseline. Working-class household budgets are strained, and bakeries report flour rationing.",
                countryCode: target,
                rarity: .rare,
                severity: 0.8,
                imageAssetName: "EventBreadRiots",
                chainID: "economic-feedback",
                options: [
                    LWDecisionOption(
                        id: "grain-subsidize",
                        label: "Fund Universal Bread Subsidies from Treasury",
                        detail: "Absorb milling cost increases to keep staple bread affordable.",
                        treasuryDelta: -16,
                        radicalsDelta: -0.06,
                        mechanicCode: "⟦ECO⟧"
                    ),
                    LWDecisionOption(
                        id: "grain-tariffs",
                        label: "Suspend Import Duties on Foreign Grain",
                        detail: "Lower customs barriers to invite agricultural cargo into ports.",
                        treasuryDelta: -6,
                        radicalsDelta: -0.02,
                        mechanicCode: "⟦MKT⟧"
                    ),
                    LWDecisionOption(
                        id: "grain-gendarmerie",
                        label: "Deploy Gendarmerie to Guard Granaries",
                        detail: "Enforce anti-hoarding decrees against grain syndicates.",
                        treasuryDelta: -3,
                        radicalsDelta: 0.07,
                        nextChainedEventID: "lw-general-strike",
                        mechanicCode: "⟦SEC⟧"
                    )
                ]
            )
        }

        // Radicalization crisis (radicals > 30%)
        if let unrestCountry = world.countries.values.first(where: { $0.radicals >= 0.30 }),
           !completed.contains("lw-general-strike-\(unrestCountry.code)")
        {
            return LWDecisionEvent(
                id: "lw-general-strike-\(unrestCountry.code)",
                day: day,
                title: "General Strike & Factory Pickets",
                summary: "Radicalized labor unions and industrial workers walk off the job, blockading rail yards and blast furnaces in protest against living conditions.",
                countryCode: unrestCountry.code,
                rarity: .rare,
                severity: 0.85,
                imageAssetName: "EventBreadRiots",
                chainID: "political-feedback",
                options: [
                    LWDecisionOption(
                        id: "strike-reforms",
                        label: "Enact Workplace Protections & Minimum Wage",
                        detail: "Concede industrial reforms and housing support to restore social order.",
                        treasuryDelta: -14,
                        radicalsDelta: -0.09,
                        stabilityDelta: 0.05,
                        mechanicCode: "⟦STB⟧"
                    ),
                    LWDecisionOption(
                        id: "strike-martial-law",
                        label: "Declare Martial Law to Disperse Picket Lines",
                        detail: "Send military units with mounted cavalry to clear transport arteries.",
                        treasuryDelta: -4,
                        radicalsDelta: 0.12,
                        nextChainedEventID: "lw-barracks-rebellion",
                        mechanicCode: "⟦MIL⟧"
                    ),
                    LWDecisionOption(
                        id: "strike-council",
                        label: "Invite Union Delegations to National Dialogue",
                        detail: "Form a bipartite emergency council to negotiate terms.",
                        treasuryDelta: -2,
                        radicalsDelta: -0.04,
                        stabilityDelta: 0.03,
                        mechanicCode: "⟦DIP⟧"
                    )
                ]
            )
        }

        // Treasury insolvency / debt spiral
        if let brokeCountry = world.countries.values.first(where: { $0.treasury <= 2.0 && $0.taxLevel >= 0.30 }),
           !completed.contains("lw-debt-spiral-\(brokeCountry.code)")
        {
            return LWDecisionEvent(
                id: "lw-debt-spiral-\(brokeCountry.code)",
                day: day,
                title: "Treasury Liquidity Exhaustion & Debt Spiral",
                summary: "State reserves are near zero while tax revenues struggle to cover administrative and security obligations. Creditors freeze bond issues.",
                countryCode: brokeCountry.code,
                rarity: .rare,
                severity: 0.9,
                chainID: "fiscal-feedback",
                options: [
                    LWDecisionOption(
                        id: "debt-moratorium",
                        label: "Declare Sovereign Debt Moratorium",
                        detail: "Repudiate speculative foreign debts to retain domestic capital.",
                        treasuryDelta: 25,
                        radicalsDelta: 0.04,
                        worldTensionDelta: 10,
                        mechanicCode: "⟦MKT⟧"
                    ),
                    LWDecisionOption(
                        id: "debt-austerity",
                        label: "Enact Emergency Public Spending Slashes",
                        detail: "Slash government salaries and pension outlays to balance the books.",
                        treasuryDelta: 18,
                        radicalsDelta: 0.08,
                        mechanicCode: "⟦ECO⟧"
                    ),
                    LWDecisionOption(
                        id: "debt-bailout",
                        label: "Secure International Stabilization Credit",
                        detail: "Accept foreign loan facilities with fiscal reform covenants.",
                        treasuryDelta: 30,
                        radicalsDelta: -0.02,
                        mechanicCode: "⟦DIP⟧"
                    )
                ]
            )
        }

        // Barracks rebellion follow-up
        if flags.contains("lw-barracks-rebellion") && !completed.contains("lw-barracks-rebellion") {
            let target = resolveTargetByRadicalsOrPlayer(world: world)
            return LWDecisionEvent(
                id: "lw-barracks-rebellion",
                day: day,
                title: "The Barracks Defection & Military Council Ultimatum",
                summary: "Garrison commanders in the capital refuse to fire upon civic demonstrations, issuing a joint manifesto demanding constitutional reorganization.",
                countryCode: target,
                rarity: .rare,
                severity: 0.95,
                imageAssetName: "EventBreadRiots",
                chainID: "military-rebellion",
                options: [
                    LWDecisionOption(
                        id: "rebellion-transition",
                        label: "Accede to Civil-Military Transition Board",
                        detail: "Cede executive oversight to a transitional council to avert fratricide.",
                        treasuryDelta: -8,
                        radicalsDelta: -0.06,
                        mechanicCode: "⟦STB⟧"
                    ),
                    LWDecisionOption(
                        id: "rebellion-garrison",
                        label: "Rally Loyal Palace Guard to Defend Executive",
                        detail: "Order loyalists to hold government headquarters against rogue brigades.",
                        treasuryDelta: -5,
                        radicalsDelta: 0.14,
                        worldTensionDelta: 20,
                        mechanicCode: "⟦MIL⟧"
                    )
                ]
            )
        }

        // --- 3. Milestone timeline story arcs (Alternative History Timelines) ---

        // Day 35: Soviet August Coup (Soviet Triumph POD)
        if day >= 35 && !completed.contains("soviet-coup-sweep") {
            let target = resolveTarget(preferredCodes: ["SOV", "RUS"], world: world)
            return LWDecisionEvent(
                id: "soviet-coup-sweep",
                day: day,
                title: "The Arkhangelskoye Sweep: State Emergency Committee",
                summary: "KGB Alpha units detain reformist leaders outside Moscow. The State Committee on the State of Emergency assumes executive control as tanks deploy to the Garden Ring.",
                countryCode: target,
                rarity: .rare,
                severity: 0.9,
                imageAssetName: "EventSovietCoup",
                chainID: "soviet-coup",
                options: [
                    LWDecisionOption(
                        id: "soviet-coup-emergency",
                        label: "Declare All-Union State of Emergency",
                        detail: "Mobilize internal security forces and establish military tribunals.",
                        treasuryDelta: -8,
                        radicalsDelta: 0.05,
                        nextChainedEventID: "soviet-miners-strike",
                        mechanicCode: "⟦SEC⟧"
                    ),
                    LWDecisionOption(
                        id: "soviet-coup-compromise",
                        label: "Broadcast Conciliatory Federation Manifesto",
                        detail: "Promise immediate economic subsidies and decentralization concessions.",
                        treasuryDelta: -16,
                        radicalsDelta: -0.05,
                        nextChainedEventID: "soviet-ogas-launch",
                        mechanicCode: "⟦STB⟧"
                    ),
                    LWDecisionOption(
                        id: "soviet-coup-technocrat",
                        label: "Form Coalition with Reform Technocrats",
                        detail: "Invite Gosplan economists to lead administrative reorganization.",
                        treasuryDelta: -6,
                        stabilityDelta: 0.06,
                        mechanicCode: "⟦DIP⟧"
                    )
                ]
            )
        }

        // Day 50: Fashoda Confrontation (Divided Sovereignty POD)
        if day >= 50 && !completed.contains("fashoda-confrontation") {
            let target = resolveTarget(preferredCodes: ["GBR", "FRA"], world: world)
            return LWDecisionEvent(
                id: "fashoda-confrontation",
                day: day,
                title: "The Gunboats of Fashoda: Nile Valley Ultimatum",
                summary: "Colonial expeditions from rival empires confront each other at a weathered Upper Nile fort. Armed gunboats exchange warnings as news reaches the capitals.",
                countryCode: target,
                rarity: .rare,
                severity: 0.85,
                imageAssetName: "EventFashodaCrisis",
                chainID: "fashoda",
                options: [
                    LWDecisionOption(
                        id: "fashoda-refuse",
                        label: "Refuse Evacuation & Reinforce Nile Garrison",
                        detail: "Hold the strategic river fortress and dare the opposing fleet to engage.",
                        treasuryDelta: -12,
                        radicalsDelta: 0.03,
                        worldTensionDelta: 20,
                        nextChainedEventID: "fashoda-channel-mobilization",
                        mechanicCode: "⟦MIL⟧"
                    ),
                    LWDecisionOption(
                        id: "fashoda-mediate",
                        label: "Accept American Diplomatic Mediation",
                        detail: "Concede river demarcation in exchange for border security assurances.",
                        treasuryDelta: -4,
                        worldTensionDelta: -12,
                        mechanicCode: "⟦DIP⟧"
                    ),
                    LWDecisionOption(
                        id: "fashoda-berlin",
                        label: "Seek Secret Naval Alignment in Berlin",
                        detail: "Dispatch diplomatic envoys to negotiate a mutual assistance pact.",
                        treasuryDelta: -8,
                        nextChainedEventID: "fashoda-continental-league",
                        mechanicCode: "⟦DIP⟧"
                    )
                ]
            )
        }

        // Day 75: Indus-Ganges Aquifer Crisis (Resource Crucible POD)
        if day >= 75 && !completed.contains("resource-aquifer-crisis") {
            let target = resolveTarget(preferredCodes: ["IND", "BRA", "USA"], world: world)
            return LWDecisionEvent(
                id: "resource-aquifer-crisis",
                day: day,
                title: "Indus-Ganges Aquifer Depletion & Irrigation Moratorium",
                summary: "Catastrophic groundwater depletion forces an emergency ban on agricultural tube wells. Canal flows fall to record lows, triggering cross-border disputes.",
                countryCode: target,
                rarity: .rare,
                severity: 0.85,
                imageAssetName: "EventResourceCrisis",
                chainID: "resource",
                options: [
                    LWDecisionOption(
                        id: "aquifer-sluices",
                        label: "Seize Trans-Boundary Canal Sluices by Military Force",
                        detail: "Deploy mechanized garrisons to ensure sovereign irrigation flow.",
                        treasuryDelta: -14,
                        radicalsDelta: 0.06,
                        worldTensionDelta: 25,
                        nextChainedEventID: "resource-migration-corridors",
                        mechanicCode: "⟦MIL⟧"
                    ),
                    LWDecisionOption(
                        id: "aquifer-desal",
                        label: "Issue Emergency Bonds for Solar Desalination",
                        detail: "Launch crash construction of coastal reverse-osmosis pipelines.",
                        treasuryDelta: -24,
                        radicalsDelta: -0.04,
                        mechanicCode: "⟦ECO⟧"
                    ),
                    LWDecisionOption(
                        id: "aquifer-rationing",
                        label: "Enforce Strict Urban Water Rationing",
                        detail: "Cut municipal water allocations by 40% to sustain grain harvests.",
                        treasuryDelta: -5,
                        radicalsDelta: 0.05,
                        nextChainedEventID: "resource-fertilizer-crisis",
                        mechanicCode: "⟦STB⟧"
                    )
                ]
            )
        }

        // Day 95: Subsea Fiber Fracture (Pax Cybernetica POD)
        if day >= 95 && !completed.contains("cyber-fiber-blackout") {
            let target = resolveTarget(preferredCodes: ["USA", "GBR", "JPN"], world: world)
            return LWDecisionEvent(
                id: "cyber-fiber-blackout",
                day: day,
                title: "The Subsea Fiber Fracture: Algorithmic Flash Crash",
                summary: "Simultaneous fiber cuts across oceanic trunks blind international clearing corridors. Autonomous high-frequency DAOs trigger \$4T in cascade liquidations.",
                countryCode: target,
                rarity: .rare,
                severity: 0.9,
                imageAssetName: "EventCyberBlackout",
                chainID: "cyber",
                options: [
                    LWDecisionOption(
                        id: "cyber-killswitch",
                        label: "Activate Sovereign Cryptographic Kill-Switches",
                        detail: "Isolate national financial networks from international automated contagion.",
                        treasuryDelta: -16,
                        stabilityDelta: 0.06,
                        nextChainedEventID: "cyber-microgrid-secession",
                        mechanicCode: "⟦SEC⟧"
                    ),
                    LWDecisionOption(
                        id: "cyber-nationalize",
                        label: "Nationalize Quantum Telecom Nodes under Military Cyber Command",
                        detail: "Place strategic network infrastructure under martial coordination.",
                        treasuryDelta: -10,
                        radicalsDelta: 0.04,
                        mechanicCode: "⟦MIL⟧"
                    ),
                    LWDecisionOption(
                        id: "cyber-liquidity",
                        label: "Inject Emergency Liquidity into Algorithmic Clearing DAOs",
                        detail: "Guarantee digital asset clearinghouses with sovereign treasury reserves.",
                        treasuryDelta: -28,
                        radicalsDelta: -0.02,
                        mechanicCode: "⟦MKT⟧"
                    )
                ]
            )
        }

        // --- 4. Dynamic Catalog Event Integration (500-Event Living World Sampling) ---
        for flag in flags {
            if let catalogEvent = NativeAlternativeHistoryCatalog.event(byId: flag),
               !completed.contains(catalogEvent.id) {
                let target = resolveTarget(preferredCodes: [catalogEvent.strategicEffects.first?.target ?? "GLOBAL"], world: world)
                return NativeAlternativeHistoryCatalog.livingWorldDecision(from: catalogEvent, day: day, targetCountry: target)
            }
        }

        // Periodic milestone sampling from 500-event alternative history catalog
        if day > 0 && day % 10 == 0 {
            let candidateIndex = (day / 10) % NativeAlternativeHistoryCatalog.events.count
            let candidateEvent = NativeAlternativeHistoryCatalog.events[candidateIndex]
            if !completed.contains(candidateEvent.id) {
                let target = resolveTarget(preferredCodes: [candidateEvent.strategicEffects.first?.target ?? "GLOBAL"], world: world)
                return NativeAlternativeHistoryCatalog.livingWorldDecision(from: candidateEvent, day: day, targetCountry: target)
            }
        }

        return nil
    }

    /// Resolves preferred country target: prefers player if eligible, else falls back to candidate code or a great power.
    private static func resolveTarget(preferredCodes: [String], world: LivingWorldState) -> String {
        if let player = world.playerCountryCode, preferredCodes.contains(player) {
            return player
        }
        for code in preferredCodes where world.countries[code] != nil {
            return code
        }
        // Fall back to player if present, else first available country
        return world.playerCountryCode ?? (world.countries.keys.sorted().first ?? "USA")
    }

    private static func resolveTargetByRadicalsOrPlayer(world: LivingWorldState) -> String {
        if let player = world.playerCountryCode, let pc = world.countries[player], pc.radicals > 0.20 {
            return player
        }
        let sorted = world.countries.values.sorted { $0.radicals > $1.radicals }
        return sorted.first?.code ?? (world.playerCountryCode ?? "USA")
    }

    /// AI Brain chooses a decision option deterministically according to its archetype.
    static func chooseAIOption(for country: LWCountry, event: LWDecisionEvent, rng: LWRNG) -> LWDecisionOption {
        guard !event.options.isEmpty else {
            return LWDecisionOption(id: "default", label: "Acknowledge", detail: "Government observes developments.")
        }
        let brain = LWBrainFactory.brain(for: country)
        if brain is LWExpansionistBrain {
            if let mil = event.options.first(where: { $0.mechanicCode == "⟦MIL⟧" || $0.worldTensionDelta > 0 }) {
                return mil
            }
        } else if brain is LWTurtleBrain {
            if let sec = event.options.first(where: { $0.mechanicCode == "⟦SEC⟧" || $0.mechanicCode == "⟦STB⟧" || $0.radicalsDelta < 0 }) {
                return sec
            }
        } else if brain is LWOpportunistBrain {
            if let eco = event.options.first(where: { $0.treasuryDelta > 0 || $0.mechanicCode == "⟦MKT⟧" }) {
                return eco
            }
        }
        let index = rng.int("ai-choice-\(event.id)", in: 0 ..< event.options.count)
        return event.options[index]
    }

    /// Applies numerical deltas from a chosen option to the nation's ledger.
    static func applyDecisionEffects(world: LivingWorldState, countryCode: String, decision: LWDecisionEvent, option: LWDecisionOption) -> LivingWorldState {
        var world = world
        if var country = world.countries[countryCode] {
            country.treasury = max(0, country.treasury + option.treasuryDelta)
            country.radicals = min(1.0, max(0.0, country.radicals + option.radicalsDelta))
            country.standardOfLiving = max(1.0, country.standardOfLiving + option.stabilityDelta * 2.0)
            world.countries[countryCode] = country
        }
        return world
    }

    /// Resolves an interactive player decision, applies effects, registers follow-ups, and clears pending state.
    static func resolveDecision(world: LivingWorldState, decision: LWDecisionEvent, option: LWDecisionOption) -> LivingWorldState {
        var world = applyDecisionEffects(world: world, countryCode: decision.countryCode, decision: decision, option: option)
        world.completedChainEvents.append(decision.id)
        if let next = option.nextChainedEventID {
            world.eventFlags.append(next)
        }
        if let flag = option.flagSet {
            world.eventFlags.append(flag)
        }
        world.pendingDecision = nil
        let countryName = world.countries[decision.countryCode]?.name ?? decision.countryCode
        let record = LWEventRecord(
            id: "resolved-\(decision.id)-\(world.dayIndex)",
            day: world.dayIndex,
            title: "\(countryName): \(decision.title)",
            summary: "Executive Directive Formed: \(option.label). \(option.detail)",
            countryCode: decision.countryCode,
            rarity: decision.rarity,
            severity: decision.severity,
            imageAssetName: decision.imageAssetName,
            decisionChosen: option.label
        )
        world.history.append(record)
        return world
    }
}

