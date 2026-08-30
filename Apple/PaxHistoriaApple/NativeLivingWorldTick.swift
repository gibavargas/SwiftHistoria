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
    func commentary(world _: LivingWorldState, country: LWCountry) -> String {
        let mood = country.standardOfLiving > 15 ? "content" : (country.radicals > 0.2 ? "restless" : "uneasy")
        return "The government of \(country.name) watches the world \(mood)."
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
    override func makeOrders(world: LivingWorldState, country: LWCountry, rng _: LWRNG) -> LWBrainOrders {
        var orders = LWBrainOrders()
        let balance = fiscalBalance(country)
        orders.taxAdjust = balance < 0 ? 0.01 : -0.005
        orders.spendingAdjust = balance > 0 ? 0.01 : -0.01
        orders.constructionTarget = country.infrastructure < 50 ? .constructionSector : .commercialFarms
        if threatLevel(world: world, country: country) > 0.5 {
            orders.mobilization = true
        }
        return orders
    }

    override func commentary(world _: LivingWorldState, country: LWCountry) -> String {
        let balance = fiscalBalance(country)
        if balance < 0 {
            return "\(country.name) runs a deficit; the treasury urges moderation."
        }
        if country.mobilized {
            return "\(country.name) keeps its reserves ready while markets stay open."
        }
        return "\(country.name) enjoys steady finances and quiet borders."
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

    override func commentary(world _: LivingWorldState, country: LWCountry) -> String {
        if country.infamy > 40 {
            return "Foreign chancelleries denounce \(country.name)'s appetite for conquest."
        }
        if country.mobilized {
            return "\(country.name)'s staff officers finalize contingency plans."
        }
        return "\(country.name) dreams of empire while its arsenals grow."
    }
}

final class LWTurtleBrain: LWCountryBrain {
    override func makeOrders(world: LivingWorldState, country: LWCountry, rng _: LWRNG) -> LWBrainOrders {
        var orders = LWBrainOrders()
        let balance = fiscalBalance(country)
        orders.taxAdjust = balance < 0 ? 0.008 : 0.0
        orders.spendingAdjust = balance < 0 ? -0.02 : -0.005
        orders.constructionTarget = .commercialFarms
        orders.mobilization = threatLevel(world: world, country: country) > 0.8 ? true : nil
        return orders
    }

    override func commentary(world _: LivingWorldState, country: LWCountry) -> String {
        "In \(country.name), the merchant classes champion quiet trade over grand politics."
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

    override func commentary(world: LivingWorldState, country: LWCountry) -> String {
        let wars = world.wars.count
        if wars > 0 {
            return "\(country.name) watches the world's wars for an opening."
        }
        return "\(country.name) bides its time, prospering on others' quarrels."
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
                    title: "Peace in \(war.warGoal)",
                    summary: "\(winner.name) dictates terms; \(loser.name) concedes.",
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
                    warGoal: "Concessions from \(targetCountry.name)",
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
                    title: "\(country.name) declares war on \(targetCountry.name)",
                    summary: "Armies mobilize along the border; embassies are withdrawn.",
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
                    title: "Alliance signed",
                    summary: "\(country.name) and \(world.countries[target]?.name ?? target) enter a defensive alliance.",
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
                let flavors = [
                    "A bumper harvest steadies grain prices in \(country.name).",
                    "Strikers blockade the docks of \(country.name).",
                    "\(country.name)'s parliament debates tariff reform.",
                    "A banking scandal rattles confidence in \(country.name).",
                    "Railway expansion reaches the interior of \(country.name)."
                ]
                newEvents.append(LWEventRecord(
                    id: "flavor-\(world.dayIndex)-\(code)",
                    day: world.dayIndex,
                    title: "Dispatch from \(country.name)",
                    summary: flavors[rng.int("flavor-pick", in: 0 ..< flavors.count)],
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
                    title: "Crisis in \(country.name)",
                    summary: "Riots erupt over the price of bread; the government scrambles to respond.",
                    countryCode: code,
                    rarity: .weekly,
                    severity: 0.5
                ))
            }
        }

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
}
