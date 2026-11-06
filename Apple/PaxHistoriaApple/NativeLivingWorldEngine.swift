import Foundation

// MARK: - Living World: deterministic day-tick simulation core

//
// Design contract (Victoria 3-inspired, open, procedural):
// - Every value is derived from `worldSeed` + the day index. No Date(), no
//   Double.random, no iteration-order dependence: dictionaries are always
//   walked with sortedKeys. Same seed + same player decisions ⇒ same world.
// - War is abstract: fronts and generals, no unit control.
// - Countries are data; behavior lives in swappable brain classes
//   (`LWCountryBrain`), chosen procedurally at world generation from traits.
// - The whole state is Codable so day-based saves use the same slot files.

// MARK: Calendar

/// Deterministic proleptic-Gregorian date. No Foundation calendar lookups.
struct LWDate: Codable, Hashable {
    var year: Int
    var month: Int
    var day: Int

    static let start = LWDate(year: 1936, month: 1, day: 1)

    var dayIndex: Int {
        LWDate.daysSinceStart(self)
    }

    static func from(dayIndex: Int) -> LWDate {
        var remaining = dayIndex
        var year = start.year
        while remaining >= daysInYear(year) {
            remaining -= daysInYear(year)
            year += 1
        }
        var month = 1
        while remaining >= daysInMonth(year: year, month: month) {
            remaining -= daysInMonth(year: year, month: month)
            month += 1
        }
        return LWDate(year: year, month: month, day: remaining + 1)
    }

    static func daysSinceStart(_ date: LWDate) -> Int {
        var total = 0
        var year = start.year
        while year < date.year {
            total += daysInYear(year)
            year += 1
        }
        var month = 1
        while month < date.month {
            total += daysInMonth(year: date.year, month: month)
            month += 1
        }
        return total + date.day - 1
    }

    static func daysInYear(_ year: Int) -> Int {
        (year % 4 == 0 && year % 100 != 0) || year % 400 == 0 ? 366 : 365
    }

    static func daysInMonth(year: Int, month: Int) -> Int {
        switch month {
        case 1, 3, 5, 7, 8, 10, 12: 31
        case 4, 6, 9, 11: 30
        default: (year % 4 == 0 && year % 100 != 0) || year % 400 == 0 ? 29 : 28
        }
    }

    func advanced(byDays days: Int) -> LWDate {
        LWDate.from(dayIndex: dayIndex + days)
    }

    var stamp: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }
}

// MARK: Goods & market

enum LWGoodCategory: String, Codable, CaseIterable {
    case stapleFood
    case luxuryFood
    case textiles
    case minerals
    case lumber
    case steel
    case machinery
    case consumerGoods
    case militaryMateriel
}

struct LWGood: Codable, Hashable {
    var id: String
    var category: LWGoodCategory
    var basePrice: Double
}

/// Single world market with per-good price discovery. Prices are clamped to
/// base ±75% (Victoria 3 bounds the market; we do the same globally).
struct LWMarket: Codable, Hashable {
    var supply: [String: Double]
    var demand: [String: Double]
    var prices: [String: Double]

    static let priceFloorFactor = 0.25
    static let priceCeilingFactor = 1.75

    static func seeded(goods: [LWGood]) -> LWMarket {
        var prices: [String: Double] = [:]
        for good in goods {
            prices[good.id] = good.basePrice
        }
        return LWMarket(supply: [:], demand: [:], prices: prices)
    }

    func price(for goodID: String) -> Double {
        prices[goodID] ?? 10.0
    }

    func basePrice(for goodID: String, goods: [LWGood]) -> Double {
        goods.first { $0.id == goodID }?.basePrice ?? 10.0
    }

    /// Unit-elastic demand factor: consumption scales inversely with price
    /// relative to base, so pop demand stabilizes the market.
    static func elasticDemand(basePrice: Double, price: Double) -> Double {
        basePrice / max(price, 0.01)
    }

    /// One day of price discovery: ratio of demand to supply moves the price
    /// toward its bound, scaled by imbalance strength.
    mutating func resolveDay(goods: [LWGood]) {
        for good in goods {
            let supply = supply[good.id] ?? 0
            let demand = demand[good.id] ?? 0
            let base = good.basePrice
            let floor = base * Self.priceFloorFactor
            let ceiling = base * Self.priceCeilingFactor
            var price = prices[good.id] ?? base
            if supply + demand > 0.0001 {
                let imbalance = (demand - supply) / max(supply + demand, 1.0)
                let move = imbalance * base * 0.02
                price = min(ceiling, max(floor, price + move))
            }
            prices[good.id] = price
        }
    }

    mutating func resetOrders() {
        supply = [:]
        demand = [:]
    }

    mutating func addSupply(_ amount: Double, goodID: String) {
        supply[goodID, default: 0] += max(0, amount)
    }

    mutating func addDemand(_ amount: Double, goodID: String) {
        demand[goodID, default: 0] += max(0, amount)
    }
}

// MARK: Buildings

enum LWBuildingType: String, Codable, CaseIterable {
    case subsistenceFarms
    case commercialFarms
    case mines
    case lumberCamps
    case textileMills
    case steelMills
    case toolingWorks
    case consumerFactories
    case armsIndustry
    case constructionSector

    var outputGood: String {
        switch self {
        case .subsistenceFarms: "grain"
        case .commercialFarms: "grain"
        case .mines: "minerals"
        case .lumberCamps: "lumber"
        case .textileMills: "textiles"
        case .steelMills: "steel"
        case .toolingWorks: "machinery"
        case .consumerFactories: "consumer_goods"
        case .armsIndustry: "materiel"
        case .constructionSector: "construction"
        }
    }

    var inputGoods: [(id: String, amount: Double)] {
        switch self {
        case .subsistenceFarms: []
        case .commercialFarms: [("machinery", 0.2)]
        case .mines: [("machinery", 0.3), ("lumber", 0.1)]
        case .lumberCamps: [("machinery", 0.1)]
        case .textileMills: [("lumber", 0.1)]
        case .steelMills: [("minerals", 1.2), ("lumber", 0.2)]
        case .toolingWorks: [("steel", 0.8), ("lumber", 0.1)]
        case .consumerFactories: [("textiles", 0.5), ("machinery", 0.2)]
        case .armsIndustry: [("steel", 0.6), ("machinery", 0.3)]
        case .constructionSector: [("lumber", 0.4), ("steel", 0.3)]
        }
    }

    var workersPerLevel: Double {
        1000
    }
}

struct LWBuilding: Codable, Hashable {
    var type: LWBuildingType
    var levels: Int
    var staffing: Double // 0..1 fraction of levels employed
    var lastProfit: Double
}

// MARK: Pops & politics

struct LWStrata: Codable, Hashable {
    var lower: Double // millions
    var middle: Double
    var upper: Double

    var total: Double {
        lower + middle + upper
    }
}

struct LWInterestGroup: Codable, Hashable {
    var id: String
    var name: String
    var clout: Double // 0..1, share of national political weight
    var approval: Double // -1..1
    var inGovernment: Bool

    static let industrialists = "ig_industrialists"
    static let landowners = "ig_landowners"
    static let tradeUnions = "ig_trade_unions"
    static let armedForces = "ig_armed_forces"
    static let intelligentsia = "ig_intelligentsia"
    static let devout = "ig_devout"
}

struct LWGovernment: Codable, Hashable {
    var legitimacy: Double // 0..100
    var govIGs: [String]
    var enactedReforms: [String]
    var electionDueDay: Int?
}

// MARK: Country

enum LWCountryStrategy: String, Codable {
    case balanced
    case expansionist
    case economicTurtle
    case opportunist
}

struct LWCountry: Codable, Hashable {
    var code: String
    var name: String
    var strategy: LWCountryStrategy
    var isGreatPower: Bool

    var pops: LWStrata
    var standardOfLiving: Double // 0..30+, Vic3-style index
    var literacy: Double // 0..1
    var radicals: Double // share of pop, 0..1

    var treasury: Double // millions £
    var debt: Double
    var taxLevel: Double // 0..1 (head tax effectiveness)
    var spendingLevel: Double // 0..1
    var government: LWGovernment
    var interestGroups: [LWInterestGroup]

    var buildings: [LWBuilding]
    var infrastructure: Double // 0..100

    var armyPower: Double // abstract front strength
    var warExhaustion: Double // 0..100
    var infamy: Double // 0..100+

    var mobilized: Bool

    func interestGroup(_ id: String) -> LWInterestGroup? {
        interestGroups.first { $0.id == id }
    }

    var gdpEstimate: Double {
        // Proxy: staffed industrial output value. Recomputed daily by the tick.
        buildings.reduce(0) { $0 + Double($1.levels) * $1.staffing * ($1.type == .subsistenceFarms ? 0.05 : 0.4) }
    }
}

// MARK: Diplomacy & war

enum LWPactKind: String, Codable {
    case alliance
    case defensivePact
    case tradeAgreement
    case nonaggression
}

struct LWPact: Codable, Hashable {
    var kind: LWPactKind
    var a: String
    var b: String
    var sinceDay: Int
}

struct LWFront: Codable, Hashable {
    var id: String
    var attacker: String
    var defender: String
    var progress: Double // -100 (defender winning) .. 100 (attacker winning)
    var intensity: Double // 0..1
}

struct LWWar: Codable, Hashable {
    var id: String
    var attacker: String
    var defender: String
    var startedDay: Int
    var warGoal: String
    var attackerAllies: [String]
    var defenderAllies: [String]
    var fronts: [LWFront]
    var exhaustionAttacker: Double
    var exhaustionDefender: Double
}

// MARK: Events

enum LWEventRarity: String, Codable {
    case daily
    case weekly
    case rare
}

struct LWDecisionOption: Codable, Hashable, Identifiable {
    var id: String
    var label: String
    var detail: String
    var treasuryDelta: Double // in millions £
    var radicalsDelta: Double // -1.0 .. +1.0
    var stabilityDelta: Double // -1.0 .. +1.0
    var worldTensionDelta: Double
    var nextChainedEventID: String?
    var flagSet: String?
    var mechanicCode: String? // "⟦ECO⟧", "⟦SEC⟧", etc.

    init(
        id: String,
        label: String,
        detail: String,
        treasuryDelta: Double = 0,
        radicalsDelta: Double = 0,
        stabilityDelta: Double = 0,
        worldTensionDelta: Double = 0,
        nextChainedEventID: String? = nil,
        flagSet: String? = nil,
        mechanicCode: String? = nil
    ) {
        self.id = id
        self.label = label
        self.detail = detail
        self.treasuryDelta = treasuryDelta
        self.radicalsDelta = radicalsDelta
        self.stabilityDelta = stabilityDelta
        self.worldTensionDelta = worldTensionDelta
        self.nextChainedEventID = nextChainedEventID
        self.flagSet = flagSet
        self.mechanicCode = mechanicCode
    }
}

struct LWDecisionEvent: Codable, Hashable, Identifiable {
    var id: String
    var day: Int
    var title: String
    var summary: String
    var countryCode: String
    var rarity: LWEventRarity
    var severity: Double
    var imageAssetName: String?
    var chainID: String?
    var options: [LWDecisionOption]

    init(
        id: String,
        day: Int,
        title: String,
        summary: String,
        countryCode: String,
        rarity: LWEventRarity = .rare,
        severity: Double = 0.8,
        imageAssetName: String? = nil,
        chainID: String? = nil,
        options: [LWDecisionOption]
    ) {
        self.id = id
        self.day = day
        self.title = title
        self.summary = summary
        self.countryCode = countryCode
        self.rarity = rarity
        self.severity = severity
        self.imageAssetName = imageAssetName
        self.chainID = chainID
        self.options = options
    }
}

struct LWEventRecord: Codable, Hashable {
    var id: String
    var day: Int
    var title: String
    var summary: String
    var countryCode: String
    var rarity: LWEventRarity
    var severity: Double // 0..1
    var imageAssetName: String?
    var decisionChosen: String?

    init(
        id: String,
        day: Int,
        title: String,
        summary: String,
        countryCode: String,
        rarity: LWEventRarity,
        severity: Double,
        imageAssetName: String? = nil,
        decisionChosen: String? = nil
    ) {
        self.id = id
        self.day = day
        self.title = title
        self.summary = summary
        self.countryCode = countryCode
        self.rarity = rarity
        self.severity = severity
        self.imageAssetName = imageAssetName
        self.decisionChosen = decisionChosen
    }
}

// MARK: World state

struct LivingWorldState: Codable {
    var worldSeed: UInt64
    var dayIndex: Int
    var goods: [LWGood]
    var market: LWMarket
    var countries: [String: LWCountry]
    var relations: [String: [String: Double]] // code -> code -> -100..100
    var pacts: [LWPact]
    var wars: [LWWar]
    var history: [LWEventRecord]
    var playerCountryCode: String?
    /// Classic-mode hash pending interpretation (LLM mode hand-off).
    var pendingWorldHash: String?
    /// Save language: generated prose (events, status lines) follows it.
    /// Persisted so a save renders identically on any device.
    var language: NativeGameLanguage = .english
    var pendingDecision: LWDecisionEvent?
    var eventFlags: [String] = []
    var completedChainEvents: [String] = []

    private enum CodingKeys: String, CodingKey {
        case worldSeed, dayIndex, goods, market, countries, relations, pacts, wars, history, playerCountryCode, pendingWorldHash, language, pendingDecision, eventFlags, completedChainEvents
    }

    init(
        worldSeed: UInt64,
        dayIndex: Int,
        goods: [LWGood],
        market: LWMarket,
        countries: [String: LWCountry],
        relations: [String: [String: Double]],
        pacts: [LWPact],
        wars: [LWWar],
        history: [LWEventRecord],
        playerCountryCode: String?,
        pendingWorldHash: String?,
        language: NativeGameLanguage = .english,
        pendingDecision: LWDecisionEvent? = nil,
        eventFlags: [String] = [],
        completedChainEvents: [String] = []
    ) {
        self.worldSeed = worldSeed
        self.dayIndex = dayIndex
        self.goods = goods
        self.market = market
        self.countries = countries
        self.relations = relations
        self.pacts = pacts
        self.wars = wars
        self.history = history
        self.playerCountryCode = playerCountryCode
        self.pendingWorldHash = pendingWorldHash
        self.language = language
        self.pendingDecision = pendingDecision
        self.eventFlags = eventFlags
        self.completedChainEvents = completedChainEvents
    }

    /// Tolerant decode: older saves without new fields default safely.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        worldSeed = try container.decodeIfPresent(UInt64.self, forKey: .worldSeed) ?? 0
        dayIndex = try container.decodeIfPresent(Int.self, forKey: .dayIndex) ?? 0
        goods = try container.decodeIfPresent([LWGood].self, forKey: .goods) ?? LivingWorldFactory.defaultGoods()
        market = try container.decodeIfPresent(LWMarket.self, forKey: .market) ?? .seeded(goods: goods)
        countries = try container.decodeIfPresent([String: LWCountry].self, forKey: .countries) ?? [:]
        relations = try container.decodeIfPresent([String: [String: Double]].self, forKey: .relations) ?? [:]
        pacts = try container.decodeIfPresent([LWPact].self, forKey: .pacts) ?? []
        wars = try container.decodeIfPresent([LWWar].self, forKey: .wars) ?? []
        history = try container.decodeIfPresent([LWEventRecord].self, forKey: .history) ?? []
        playerCountryCode = try container.decodeIfPresent(String.self, forKey: .playerCountryCode)
        pendingWorldHash = try container.decodeIfPresent(String.self, forKey: .pendingWorldHash)
        language = try (container.decodeIfPresent(String.self, forKey: .language)).flatMap(NativeGameLanguage.init(rawValue:)) ?? .english
        pendingDecision = try container.decodeIfPresent(LWDecisionEvent.self, forKey: .pendingDecision)
        eventFlags = try container.decodeIfPresent([String].self, forKey: .eventFlags) ?? []
        completedChainEvents = try container.decodeIfPresent([String].self, forKey: .completedChainEvents) ?? []
    }

    var today: LWDate {
        LWDate.from(dayIndex: dayIndex)
    }

    func sortedCountryCodes() -> [String] {
        countries.keys.sorted()
    }

    func relation(from: String, to: String) -> Double {
        relations[from]?[to] ?? 0
    }

    mutating func adjustRelation(from: String, to: String, delta: Double) {
        relations[from, default: [:]][to, default: 0] = min(100, max(-100, (relations[from]?[to] ?? 0) + delta))
        relations[to, default: [:]][from, default: 0] = min(100, max(-100, (relations[to]?[from] ?? 0) + delta * 0.5))
    }
}

// MARK: Deterministic RNG

/// Hash-seeded deterministic generator in the engine's established FNV-1a
/// style. Stateless per draw: every draw names its own stream so tick order
/// cannot change outcomes.
struct LWRNG {
    let worldSeed: UInt64
    let dayIndex: Int

    func unit(_ stream: String) -> Double {
        Double(NativeGameEngine.fnv1aHash("\(worldSeed)-d\(dayIndex)-\(stream)") % 1_000_001) / 1_000_000.0
    }

    func int(_ stream: String, in range: ClosedRange<Int>) -> Int {
        range.lowerBound + Int(unit(stream) * Double(range.count)) % range.count
    }

    /// Half-open convenience (e.g. `rng.int(s, in: 0 ..< list.count)`).
    func int(_ stream: String, in range: Range<Int>) -> Int {
        guard !range.isEmpty else { return range.lowerBound }
        return int(stream, in: range.lowerBound ... (range.upperBound - 1))
    }

    func pick(_ stream: String, from options: [String]) -> String {
        guard !options.isEmpty else { return "" }
        return options[int(stream, in: 0 ..< options.count)]
    }

    func chance(_ stream: String, probability: Double) -> Bool {
        unit(stream) < probability
    }
}

// MARK: Procedural world generation

enum LivingWorldFactory {
    /// Catalog of playable/strategic countries. Procedural worlds combine
    /// this catalog with generated minor nations.
    static let coreCatalog: [(code: String, name: String, industrial: Double, pop: Double)] = [
        ("USA", "United States", 0.9, 130),
        ("GBR", "United Kingdom", 0.95, 47),
        ("DEU", "Germany", 0.85, 65),
        ("FRA", "France", 0.75, 42),
        ("RUS", "Russia", 0.45, 110),
        ("JAP", "Japan", 0.6, 70),
        ("ITA", "Italy", 0.55, 44),
        ("BRA", "Brazil", 0.3, 38),
        ("IND", "British India", 0.25, 340),
        ("CHI", "China", 0.2, 480),
        ("ZAF", "South Africa", 0.4, 48),
        ("AUS", "Australia", 0.65, 22)
    ]

    static let minorNamePartsA = ["New", "Upper", "Lower", "Coastal", "Highland", "Northern", "Southern", "Eastern", "Western", "Free"]
    static let minorNamePartsB = ["Vale", "Marches", "Republic", "Dominion", "Commonwealth", "States", "Lands", "Federation", "Union", "Territory"]

    static func defaultGoods() -> [LWGood] {
        [
            LWGood(id: "grain", category: .stapleFood, basePrice: 20),
            LWGood(id: "luxury_food", category: .luxuryFood, basePrice: 45),
            LWGood(id: "minerals", category: .minerals, basePrice: 30),
            LWGood(id: "lumber", category: .lumber, basePrice: 22),
            LWGood(id: "textiles", category: .textiles, basePrice: 40),
            LWGood(id: "steel", category: .steel, basePrice: 55),
            LWGood(id: "machinery", category: .machinery, basePrice: 70),
            LWGood(id: "consumer_goods", category: .consumerGoods, basePrice: 60),
            LWGood(id: "materiel", category: .militaryMateriel, basePrice: 80)
        ]
    }

    /// Generates a fully procedural 1936 world. `minorCount` minor nations are
    /// derived from the seed; identical seeds produce identical worlds.
    static func makeWorld(seed: UInt64, playerCode: String?, minorCount: Int = 12) -> LivingWorldState {
        let rng = LWRNG(worldSeed: seed, dayIndex: 0)
        var countries: [String: LWCountry] = [:]

        for core in coreCatalog {
            countries[core.code] = makeCountry(
                code: core.code,
                name: core.name,
                industrial: core.industrial,
                pop: core.pop,
                rng: rng,
                stream: "gen-\(core.code)"
            )
        }

        // Ensure the player's chosen country always exists in the world simulation
        if let player = playerCode, countries[player] == nil {
            let name = CountryCatalog.all.first { $0.code == player }?.name ?? player
            let profile = Native2010WorldModel.profile(for: PlayerCountry(code: player, name: name))
            let industrial = max(0.15, min(0.95, Double(profile.techLevel) / 5.0))
            let pop = max(5.0, min(300.0, Double(profile.nominalGDPTrillions * 30.0) + 12.0))
            countries[player] = makeCountry(
                code: player,
                name: name,
                industrial: industrial,
                pop: pop,
                rng: rng,
                stream: "gen-\(player)"
            )
        }

        // Procedural minors. Retry streams include the attempt counter so a
        // colliding name never re-draws the identical combination forever.
        var usedNames = Set(coreCatalog.map(\.name))
        for i in 0 ..< minorCount {
            var name: String
            var attempt = 0
            repeat {
                name = "\(rng.pick("minor-a-\(i)-\(attempt)", from: minorNamePartsA)) \(rng.pick("minor-b-\(i)-\(attempt)", from: minorNamePartsB))"
                attempt += 1
            } while usedNames.contains(name)
            usedNames.insert(name)
            let code = "M\(String(format: "%02d", i + 1))"
            countries[code] = makeCountry(
                code: code,
                name: name,
                industrial: Double.randomSeeded(rng: rng, stream: "minor-ind-\(i)", in: 0.05 ... 0.4),
                pop: Double.randomSeeded(rng: rng, stream: "minor-pop-\(i)", in: 3 ... 25),
                rng: rng,
                stream: "gen-\(code)"
            )
        }

        let goods = defaultGoods()
        var state = LivingWorldState(
            worldSeed: seed,
            dayIndex: 0,
            goods: goods,
            market: .seeded(goods: goods),
            countries: countries,
            relations: [:],
            pacts: [],
            wars: [],
            history: [],
            playerCountryCode: playerCode,
            pendingWorldHash: nil
        )

        // Initial relations: cores know each other; procedurally mixed.
        let codes = state.sortedCountryCodes()
        for a in codes {
            for b in codes where a < b {
                let roll = rng.unit("rel-\(a)-\(b)") * 200 - 100
                state.relations[a, default: [:]][b] = roll
                state.relations[b, default: [:]][a] = roll
            }
        }
        // Seed a couple of alliances among great powers.
        for (a, b) in [("GBR", "FRA"), ("DEU", "ITA"), ("USA", "GBR")] where state.countries[a] != nil && state.countries[b] != nil {
            state.pacts.append(LWPact(kind: .alliance, a: a, b: b, sinceDay: 0))
        }
        return state
    }

    private static func makeCountry(
        code: String,
        name: String,
        industrial: Double,
        pop: Double,
        rng: LWRNG,
        stream: String
    ) -> LWCountry {
        let lower = pop * 0.72
        let middle = pop * (0.18 + industrial * 0.14)
        let upper = max(0.1, pop - lower - middle)

        var buildings: [LWBuilding] = [
            LWBuilding(type: .subsistenceFarms, levels: max(1, Int(pop * 2)), staffing: 0.85, lastProfit: 0),
            LWBuilding(type: .commercialFarms, levels: max(1, Int(Double(pop) * industrial * 1.5)), staffing: 0.8, lastProfit: 0),
            // Primary/processing ratios approximately close the input chains
            // (mines feed steel mills, lumber feeds mills/tooling, tooling
            // meets machinery demand) so goods prices oscillate around
            // interior equilibria instead of pinning at bounds.
            LWBuilding(type: .mines, levels: max(1, Int(Double(pop) * industrial * 0.65)), staffing: 0.75, lastProfit: 0),
            LWBuilding(type: .lumberCamps, levels: max(1, Int(Double(pop) * industrial * 0.35)), staffing: 0.7, lastProfit: 0)
        ]
        if industrial > 0.4 {
            buildings.append(contentsOf: [
                LWBuilding(type: .textileMills, levels: max(1, Int(Double(pop) * industrial * 0.3)), staffing: 0.7, lastProfit: 0),
                LWBuilding(type: .steelMills, levels: max(1, Int(Double(pop) * industrial * 0.55)), staffing: 0.7, lastProfit: 0),
                LWBuilding(type: .toolingWorks, levels: max(1, Int(Double(pop) * industrial * 0.7)), staffing: 0.65, lastProfit: 0),
                LWBuilding(type: .consumerFactories, levels: max(1, Int(Double(pop) * industrial * 0.35)), staffing: 0.7, lastProfit: 0)
            ])
        }
        if industrial > 0.7 {
            buildings.append(LWBuilding(type: .armsIndustry, levels: max(1, Int(Double(pop) * 0.08)), staffing: 0.8, lastProfit: 0))
        }
        buildings.append(LWBuilding(type: .constructionSector, levels: max(1, Int(Double(pop) * 0.05) + 1), staffing: 0.6, lastProfit: 0))

        let govIGs = [LWInterestGroup.industrialists, LWInterestGroup.landowners]
        let interestGroups = [
            LWInterestGroup(id: LWInterestGroup.industrialists, name: "Industrialists", clout: 0.1 + industrial * 0.35, approval: 0.1, inGovernment: govIGs.contains(LWInterestGroup.industrialists)),
            LWInterestGroup(id: LWInterestGroup.landowners, name: "Landowners", clout: 0.3 - industrial * 0.15, approval: 0.0, inGovernment: govIGs.contains(LWInterestGroup.landowners)),
            LWInterestGroup(id: LWInterestGroup.tradeUnions, name: "Trade Unions", clout: 0.05 + industrial * 0.15, approval: -0.1, inGovernment: false),
            LWInterestGroup(id: LWInterestGroup.armedForces, name: "Armed Forces", clout: 0.15, approval: 0.05, inGovernment: false),
            LWInterestGroup(id: LWInterestGroup.intelligentsia, name: "Intelligentsia", clout: 0.1, approval: 0.0, inGovernment: false),
            LWInterestGroup(id: LWInterestGroup.devout, name: "Devout", clout: 0.15, approval: 0.1, inGovernment: false)
        ]

        let strategy: LWCountryStrategy = switch rng.pick("strategy-\(stream)", from: ["balanced", "expansionist", "turtle", "opportunist"]) {
        case "balanced": .balanced
        case "expansionist": .expansionist
        case "turtle": .economicTurtle
        default: .opportunist
        }

        return LWCountry(
            code: code,
            name: name,
            strategy: strategy,
            isGreatPower: industrial >= 0.55,
            pops: LWStrata(lower: lower, middle: middle, upper: upper),
            standardOfLiving: 8 + industrial * 10,
            literacy: 0.2 + industrial * 0.55,
            radicals: 0.05 + (1 - industrial) * 0.1,
            treasury: 10 + industrial * 120,
            debt: 0,
            taxLevel: 0.3,
            spendingLevel: 0.5,
            government: LWGovernment(
                legitimacy: 55 + rng.unit("leg-\(stream)") * 30,
                govIGs: govIGs,
                enactedReforms: [],
                electionDueDay: rng.chance("elections-\(stream)", probability: 0.6) ? rng.int("election-day-\(stream)", in: 900 ... 1400) : nil
            ),
            interestGroups: interestGroups,
            buildings: buildings,
            infrastructure: 30 + industrial * 55,
            armyPower: 20 + industrial * 60 + pop * 0.1,
            warExhaustion: 0,
            infamy: 0,
            mobilized: false
        )
    }
}

extension Double {
    static func randomSeeded(rng: LWRNG, stream: String, in range: ClosedRange<Double>) -> Double {
        range.lowerBound + rng.unit(stream) * (range.upperBound - range.lowerBound)
    }
}
