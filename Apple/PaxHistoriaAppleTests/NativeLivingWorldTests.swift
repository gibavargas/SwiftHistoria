@testable import SwiftHistoria
import XCTest

// MARK: - Living World (day-tick) determinism & mechanics

@MainActor
final class LivingWorldEngineTests: XCTestCase {
    /// Canonical fingerprint: sorted-country aggregate metrics so dictionary
    /// ordering can never flake the comparison.
    private func fingerprint(_ world: LivingWorldState) -> String {
        let countries = world.countries.keys.sorted().map { code -> String in
            let c = world.countries[code]!
            let wars = world.wars.filter { $0.attacker == code || $0.defender == code }.count
            return String(
                format: "%@|sol=%.4f|treasury=%.4f|tax=%.4f|infamy=%.2f|mobilized=%d|wars=%d",
                code, c.standardOfLiving, c.treasury, c.taxLevel, c.infamy, c.mobilized ? 1 : 0, wars
            )
        }
        let market = world.goods.map { good -> String in
            String(format: "%@=%.4f", good.id, world.market.prices[good.id] ?? 0)
        }.joined(separator: ";")
        return "day=\(world.dayIndex)\ncountries=\(countries.joined(separator: "\n"))\nmarket=\(market)"
    }

    func testFactoryProducesIdenticalWorldsForSameSeed() {
        let a = LivingWorldFactory.makeWorld(seed: 12345, playerCode: "BRA", minorCount: 12)
        let b = LivingWorldFactory.makeWorld(seed: 12345, playerCode: "BRA", minorCount: 12)
        XCTAssertEqual(fingerprint(a), fingerprint(b), "Same seed must generate the identical world")
        XCTAssertEqual(a.countries.count, b.countries.count)
    }

    func testFactoryVariesWithSeed() {
        let a = LivingWorldFactory.makeWorld(seed: 1, playerCode: nil, minorCount: 8)
        let b = LivingWorldFactory.makeWorld(seed: 2, playerCode: nil, minorCount: 8)
        XCTAssertNotEqual(fingerprint(a), fingerprint(b), "Different seeds must generate different worlds")
    }

    func testThirtyTicksAreDeterministic() {
        let a = LivingWorldFactory.makeWorld(seed: 777, playerCode: "BRA", minorCount: 10)
        let b = LivingWorldFactory.makeWorld(seed: 777, playerCode: "BRA", minorCount: 10)
        var worldA = a
        var worldB = b
        for _ in 0 ..< 30 {
            worldA = LivingWorldTick.advanceDay(worldA, playerOrders: nil)
        }
        for _ in 0 ..< 30 {
            worldB = LivingWorldTick.advanceDay(worldB, playerOrders: nil)
        }
        XCTAssertEqual(fingerprint(worldA), fingerprint(worldB), "Same seed + same ticks must stay identical")
        XCTAssertEqual(worldA.dayIndex, 30)
    }

    func testPlayerOrdersOverrideBrainForPlayerCountry() throws {
        var world = LivingWorldFactory.makeWorld(seed: 42, playerCode: "BRA", minorCount: 6)
        var orders = LWBrainOrders()
        orders.taxAdjust = 0.1
        let before = try XCTUnwrap(world.countries["BRA"]?.taxLevel)
        world = LivingWorldTick.advanceDay(world, playerOrders: orders)
        let after = try XCTUnwrap(world.countries["BRA"]?.taxLevel)
        XCTAssertGreaterThan(after, before, "Player orders must drive the player country")
    }

    func testMarketPricesStayInsideVicStyleBounds() {
        var world = LivingWorldFactory.makeWorld(seed: 99, playerCode: nil, minorCount: 6)
        for _ in 0 ..< 120 {
            world = LivingWorldTick.advanceDay(world, playerOrders: nil)
        }
        for good in world.goods {
            let price = world.market.prices[good.id] ?? 0
            XCTAssertGreaterThanOrEqual(price, good.basePrice * LWMarket.priceFloorFactor - 0.0001)
            XCTAssertLessThanOrEqual(price, good.basePrice * LWMarket.priceCeilingFactor + 0.0001)
        }
    }

    func testDateArithmeticAcrossLeapYear() {
        XCTAssertEqual(LWDate.start.dayIndex, 0)
        XCTAssertEqual(LWDate.from(dayIndex: 0), LWDate(year: 1936, month: 1, day: 1))
        XCTAssertEqual(LWDate.from(dayIndex: 365), LWDate(year: 1936, month: 12, day: 31))
        // 1940 is a leap year: Feb 29 1940 exists.
        let feb29 = LWDate(year: 1940, month: 2, day: 29)
        XCTAssertEqual(feb29.advanced(byDays: 1), LWDate(year: 1940, month: 3, day: 1))
    }

    func testHashBridgeInterpretationRoundTrip() throws {
        let world = LivingWorldFactory.makeWorld(seed: 5, playerCode: "BRA", minorCount: 4)
        let interpretation = LivingWorldHashBridge.interpret(hash: "0x80808080", world: world)
        XCTAssertNotNil(interpretation)
        // Nibble pair (8,0) = 128/255 ≈ 0.502, so the delta is ≈ +0.02, near-neutral.
        XCTAssertEqual(try XCTUnwrap(interpretation?.stabilityDelta), 0.0196, accuracy: 0.03, "0x80 pair should map to ~neutral 50%")
        XCTAssertNotNil(LivingWorldHashBridge.interpret(hash: "WORLDHASH:0xABCDEF12", world: world))
        XCTAssertNil(LivingWorldHashBridge.interpret(hash: "nonsense", world: world))
        XCTAssertNil(LivingWorldHashBridge.interpret(hash: "0x123", world: world), "Short hash must be rejected")
    }

    func testHashBridgePromptContainsSnapshotAndContract() {
        let world = LivingWorldFactory.makeWorld(seed: 5, playerCode: "BRA", minorCount: 4)
        let prompt = LivingWorldHashBridge.makeWorldPrompt(for: world)
        XCTAssertTrue(prompt.contains("WORLDHASH:0x"))
        XCTAssertTrue(prompt.contains("BRA"))
        XCTAssertTrue(prompt.contains("worldSeed"))
    }

    func testWarDeclarationAndPeaceCycle() throws {
        let session = try LivingWorldSession(playerCountryCode: "DEU", seed: 2024, slot: 3,
                                             defaults: XCTUnwrap(UserDefaults(suiteName: "lw-test-\(UUID().uuidString)")))
        session.declareWar(on: "USA")
        XCTAssertFalse(session.world.wars.isEmpty, "Declared war must exist")
        let declaredWarID = session.world.wars[0].id
        for _ in 0 ..< 400 {
            session.stepDay()
        }
        // AI brains may start their own wars during the window (fresh wars have
        // near-zero exhaustion), so only the *declared* war is asserted on.
        // Peace consuming it is a pass; surviving 400 days requires a
        // near-balanced stalemate, which must show real exhaustion. A winning
        // attacker's exhaustion can shrink (progress rebate), so the max of
        // both sides is the meaningful signal.
        if let declared = session.world.wars.first(where: { $0.id == declaredWarID }) {
            XCTAssertGreaterThan(max(declared.exhaustionAttacker, declared.exhaustionDefender), 30,
                                 "A war surviving 400 days must be accruing exhaustion")
        }
    }

    func testBrainsKeepEconomyParametersInLegalRange() {
        var world = LivingWorldFactory.makeWorld(seed: 31337, playerCode: nil, minorCount: 10)
        for _ in 0 ..< 90 {
            world = LivingWorldTick.advanceDay(world, playerOrders: nil)
        }
        for country in world.countries.values {
            XCTAssertGreaterThanOrEqual(country.taxLevel, 0.0499)
            XCTAssertLessThanOrEqual(country.taxLevel, 0.6001)
            XCTAssertGreaterThanOrEqual(country.spendingLevel, 0.0999)
            XCTAssertLessThanOrEqual(country.spendingLevel, 1.0001)
            XCTAssertLessThanOrEqual(country.radicals, 1.0001)
        }
    }

    func testConstructionTargetsVaryWithSeededRNG() {
        // Balanced and Turtle brains gate construction on seeded dice; across
        // many days the same country must not queue one building forever.
        let world = LivingWorldFactory.makeWorld(seed: 4242, playerCode: nil, minorCount: 8)
        for strategy in [LWCountryStrategy.balanced, .economicTurtle] {
            guard let country = world.countries.values.first(where: { $0.strategy == strategy }) else {
                continue
            }
            let brain = LWBrainFactory.brain(for: country)
            var targets = Set<LWBuildingType>()
            for day in 0 ..< 200 {
                let rng = LWRNG(worldSeed: world.worldSeed, dayIndex: day)
                if let target = brain.makeOrders(world: world, country: country, rng: rng).constructionTarget {
                    targets.insert(target)
                }
            }
            XCTAssertGreaterThan(targets.count, 1, "\(strategy.rawValue) brain must vary construction across days")
        }
    }

    func testThousandDayTicksAreDeterministicAndBounded() {
        let seed: UInt64 = 90210
        var worldA = LivingWorldFactory.makeWorld(seed: seed, playerCode: "BRA", minorCount: 10)
        var worldB = LivingWorldFactory.makeWorld(seed: seed, playerCode: "BRA", minorCount: 10)

        var warsDeclared = 0
        var warsConcluded = 0
        var previousWarIDs = Set(worldA.wars.map(\.id))
        // Track the tail of history for event-derived counters (history is
        // capped at 400 records, so cumulative counts must be diffed daily).
        var pinDays: [String: Int] = [:]
        var days = 0

        for day in 1 ... 1000 {
            worldA = LivingWorldTick.advanceDay(worldA, playerOrders: nil)
            worldB = LivingWorldTick.advanceDay(worldB, playerOrders: nil)
            days = day

            let currentWarIDs = Set(worldA.wars.map(\.id))
            warsDeclared += currentWarIDs.subtracting(previousWarIDs).count
            warsConcluded += previousWarIDs.subtracting(currentWarIDs).count
            previousWarIDs = currentWarIDs

            for good in worldA.goods {
                let base = good.basePrice
                let price = worldA.market.prices[good.id] ?? base
                if abs(price - base * LWMarket.priceFloorFactor) < 0.0001 || abs(price - base * LWMarket.priceCeilingFactor) < 0.0001 {
                    pinDays[good.id, default: 0] += 1
                }
            }

            if day == 100 || day == 500 || day == 1000 {
                XCTAssertEqual(fingerprint(worldA), fingerprint(worldB), "Determinism must hold at day \(day)")
            }
        }

        XCTAssertEqual(days, 1000)
        // Real activity: expansionist brains declare wars, exhaustion ends them.
        XCTAssertGreaterThan(warsDeclared, 0, "1,000 days must see at least one war declaration")
        XCTAssertGreaterThan(warsConcluded, 0, "1,000 days must see at least one peace deal")

        // Coupled industrial goods must not sit at a price bound; their
        // supply and demand are linked through input chains.
        for good in worldA.goods where [.minerals, .lumber, .steel, .machinery, .textiles].contains(good.category) {
            let pinned = pinDays[good.id] ?? 0
            XCTAssertLessThan(Double(pinned), 900, "\(good.id) pinned at a price bound for \(pinned)/1000 days")
        }

        // No terminal state: finite numbers everywhere, radicals bounded,
        // every country still has a viable ledger.
        for country in worldA.countries.values {
            XCTAssertLessThanOrEqual(country.radicals, 1.0001)
            XCTAssertTrue(country.treasury.isFinite)
            XCTAssertTrue(country.standardOfLiving.isFinite)
        }
        for good in worldA.goods {
            XCTAssertTrue((worldA.market.prices[good.id] ?? 0).isFinite)
        }
    }

    func testCommentaryIsStateGroundedAndDeterministic() {
        let world = LivingWorldFactory.makeWorld(seed: 8, playerCode: nil, minorCount: 8)
        let rng = LWRNG(worldSeed: world.worldSeed, dayIndex: 0)
        for country in world.countries.values {
            let brain = LWBrainFactory.brain(for: country)
            let line = brain.commentary(world: world, country: country, language: .english, rng: rng)
            XCTAssertFalse(line.isEmpty)
            XCTAssertTrue(line.contains(country.name), "Commentary should name its country")
            XCTAssertEqual(line, brain.commentary(world: world, country: country, language: .english, rng: rng),
                           "Same world + same day must yield identical commentary")
        }
    }

    func testCommentaryReflectsWarStateAndLanguage() throws {
        var world = LivingWorldFactory.makeWorld(seed: 55, playerCode: "BRA", minorCount: 6)
        world.language = .portuguese
        var orders = LWBrainOrders()
        orders.warDeclarationTarget = "USA"
        world = LivingWorldTick.advanceDay(world, playerOrders: orders)
        let brazil = try XCTUnwrap(world.countries["BRA"])
        let rng = LWRNG(worldSeed: world.worldSeed, dayIndex: world.dayIndex)
        let line = LWBrainFactory.brain(for: brazil).commentary(world: world, country: brazil, language: world.language, rng: rng)
        XCTAssertTrue(line.contains("frentes ativas"), "A war-participating country must draw the at-war situation fragment, got: \(line)")
    }

    func testProseTablesCoverEveryLanguage() {
        let interp = ["goal": "X", "winner": "X", "loser": "X", "country": "X", "target": "X", "wars": "1", "powers": "6", "date": "1936-01-01"]
        for key in LWProseKey.allCases {
            for language in [NativeGameLanguage.english, .portuguese, .spanish] {
                let template = LWProse.tables[key]?[language]
                XCTAssertNotNil(template, "\(key.rawValue) missing \(language.rawValue) template")
                let resolved = LWProse.string(key, language: language, interp)
                XCTAssertFalse(resolved.contains("{"), "\(key.rawValue)/\(language.rawValue) resolved with an unknown placeholder: \(resolved)")
                XCTAssertFalse(resolved.isEmpty)
            }
        }
    }

    func testProseResolvesPerLanguageWithInterpolation() {
        let en = LWProse.string(.warDeclarationTitle, language: .english, ["country": "Brazil", "target": "France"])
        XCTAssertEqual(en, "Brazil declares war on France")
        let pt = LWProse.string(.warDeclarationTitle, language: .portuguese, ["country": "Brazil", "target": "France"])
        XCTAssertEqual(pt, "Brazil declara guerra a France")
        let es = LWProse.string(.warDeclarationTitle, language: .spanish, ["country": "Brazil", "target": "France"])
        XCTAssertEqual(es, "Brazil declara la guerra a France")
    }

    func testGeneratedEventsFollowWorldLanguage() throws {
        var world = LivingWorldFactory.makeWorld(seed: 42, playerCode: "BRA", minorCount: 4)
        world.language = .portuguese
        var orders = LWBrainOrders()
        orders.warDeclarationTarget = "USA"
        world = LivingWorldTick.advanceDay(world, playerOrders: orders)
        let warEvent = try XCTUnwrap(world.history.first { $0.id.hasPrefix("war-") }, "Player-ordered war must emit an event the same day")
        XCTAssertEqual(warEvent.title, "Brazil declara guerra a United States")
        XCTAssertEqual(world.wars.first?.warGoal, "Concessões de United States")
        XCTAssertFalse(warEvent.summary.contains("embassies"), "English summary must not leak into a pt save")
    }

    func testSessionStatusLinesRespectLanguage() throws {
        let session = try LivingWorldSession(playerCountryCode: "BRA", seed: 42, slot: 3, language: .portuguese,
                                             defaults: XCTUnwrap(UserDefaults(suiteName: "lw-prose-\(UUID().uuidString)")))
        XCTAssertTrue(session.worldSituationLine().contains("grandes potências"), "Peace status line must render in the save language")
        XCTAssertFalse(session.menuCommentary().isEmpty)
    }

    func testLanguageSurvivesPersistenceRoundTrip() throws {
        let suite = try XCTUnwrap(UserDefaults(suiteName: "lw-lang-\(UUID().uuidString)"))
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("lw-lang-\(UUID().uuidString)")
        let session = LivingWorldSession(playerCountryCode: "BRA", seed: 77, slot: 2, language: .spanish, defaults: suite, persistenceDirectory: dir)
        session.persistNow()
        let loaded = LivingWorldSession(playerCountryCode: "BRA", seed: 0, slot: 2, defaults: suite, persistenceDirectory: dir)
        XCTAssertEqual(loaded.world.language, .spanish, "Save language must survive the persistence round trip")
    }

    func testSessionPersistenceRoundTrip() throws {
        let suite = try XCTUnwrap(UserDefaults(suiteName: "lw-persist-\(UUID().uuidString)"))
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("lw-test-\(UUID().uuidString)")
        let session = LivingWorldSession(playerCountryCode: "GBR", seed: 606, slot: 2, defaults: suite, persistenceDirectory: dir)
        for _ in 0 ..< 5 {
            session.stepDay()
        }
        session.persistNow()
        let loaded = LivingWorldSession(playerCountryCode: "GBR", seed: 0, slot: 2, defaults: suite, persistenceDirectory: dir)
        XCTAssertEqual(loaded.world.dayIndex, 5, "Resume must restore the tick count")
        XCTAssertTrue(LivingWorldSession.hasSave(slot: 2, directory: dir))
    }

    // MARK: - Alternative History Event Chains & Decision Interruption Tests

    func testDecisionEventPausesPlayerLivingWorldSession() {
        var world = LivingWorldFactory.makeWorld(seed: 101, playerCode: "BRA", minorCount: 4)
        let decision = LWDecisionEvent(
            id: "test-crisis",
            title: "Test Crisis",
            summary: "A critical crisis demands executive intervention.",
            day: world.dayIndex,
            targetCountryCode: "BRA",
            imageAssetName: "EventBreadRiots",
            options: [
                LWDecisionOption(
                    id: "opt-1",
                    text: "Option 1",
                    consequenceSummary: "Subsidize",
                    radicalDelta: -0.1,
                    treasuryDelta: -5.0,
                    stabilityDelta: 0.1,
                    nextChainedEventID: nil,
                    setFlag: "opt1_chosen"
                ),
                LWDecisionOption(
                    id: "opt-2",
                    text: "Option 2",
                    consequenceSummary: "Crackdown",
                    radicalDelta: 0.1,
                    treasuryDelta: 0.0,
                    stabilityDelta: -0.05,
                    nextChainedEventID: nil,
                    setFlag: "opt2_chosen"
                )
            ]
        )
        world.pendingDecision = decision

        let initialDay = world.dayIndex
        let nextWorld = LivingWorldTick.advanceDay(world, playerOrders: nil)

        // Day tick must be halted when a decision is pending
        XCTAssertEqual(nextWorld.dayIndex, initialDay, "AdvanceDay must pause when pendingDecision is not nil")
        XCTAssertNotNil(nextWorld.pendingDecision, "Pending decision must remain until player makes a choice")
    }

    func testResolveDecisionAppliesEffectsAndClearsPending() throws {
        var world = LivingWorldFactory.makeWorld(seed: 102, playerCode: "BRA", minorCount: 4)
        let initialTreasury = try XCTUnwrap(world.countries["BRA"]?.treasury)
        let initialRadicals = try XCTUnwrap(world.countries["BRA"]?.radicals)

        let option = LWDecisionOption(
            id: "opt-reform",
            text: "Enact Emergency Subsidy",
            consequenceSummary: "Drains treasury but lowers radicals.",
            radicalDelta: -0.15,
            treasuryDelta: -8.0,
            stabilityDelta: 0.12,
            nextChainedEventID: "next-strike-settlement",
            setFlag: "reform_passed"
        )
        let decision = LWDecisionEvent(
            id: "strike-event",
            title: "Strike Event",
            summary: "Workers strike across the capital.",
            day: world.dayIndex,
            targetCountryCode: "BRA",
            imageAssetName: "EventBreadRiots",
            options: [option]
        )
        world.pendingDecision = decision

        let resolved = LivingWorldTick.resolveDecision(world: world, decision: decision, chosenOption: option)

        XCTAssertNil(resolved.pendingDecision, "Pending decision must be cleared upon resolution")
        XCTAssertEqual(resolved.eventFlags["reform_passed"], "opt-reform")
        XCTAssertEqual(resolved.eventFlags["next_chain"], "next-strike-settlement")

        let updatedCountry = try XCTUnwrap(resolved.countries["BRA"])
        XCTAssertEqual(updatedCountry.treasury, max(0, initialTreasury - 8.0), accuracy: 0.001)
        XCTAssertLessThan(updatedCountry.radicals, initialRadicals)
        XCTAssertTrue(resolved.completedChainEvents.contains("strike-event"))

        // History must record the resolution with chosen option text
        let record = try XCTUnwrap(resolved.history.first { $0.id == "strike-event" })
        XCTAssertEqual(record.decisionChosen, "Enact Emergency Subsidy")
    }

    func testAINationAutonomouslyResolvesDecisionEvents() throws {
        var world = LivingWorldFactory.makeWorld(seed: 103, playerCode: "BRA", minorCount: 4)
        let aiCountryCode = "USA"
        let initialTreasury = try XCTUnwrap(world.countries[aiCountryCode]?.treasury)

        // Target an AI nation with a decision event
        let decision = LWDecisionEvent(
            id: "ai-event-1",
            title: "AI Geopolitical Decision",
            summary: "AI government evaluates crisis autonomously.",
            day: world.dayIndex,
            targetCountryCode: aiCountryCode,
            imageAssetName: "EventCyberBlackout",
            options: [
                LWDecisionOption(
                    id: "ai-opt-a",
                    text: "Strengthen Defense Posture",
                    consequenceSummary: "Invests treasury into security.",
                    radicalDelta: -0.05,
                    treasuryDelta: -4.0,
                    stabilityDelta: 0.05,
                    nextChainedEventID: nil,
                    setFlag: "ai_defense"
                )
            ]
        )

        // Direct AI option choice
        let aiBrain = LWBrainFactory.brain(for: try XCTUnwrap(world.countries[aiCountryCode]))
        let chosen = LivingWorldTick.chooseAIOption(decision.options, for: try XCTUnwrap(world.countries[aiCountryCode]), brain: aiBrain)
        XCTAssertEqual(chosen.id, "ai-opt-a")

        let resolved = LivingWorldTick.resolveDecision(world: world, decision: decision, chosenOption: chosen)
        XCTAssertNil(resolved.pendingDecision, "AI resolution must not block player")
        XCTAssertEqual(resolved.eventFlags["ai_defense"], "ai-opt-a")
        let updatedAI = try XCTUnwrap(resolved.countries[aiCountryCode])
        XCTAssertEqual(updatedAI.treasury, max(0, initialTreasury - 4.0), accuracy: 0.001)
    }

    func testSessionChooseDecisionOptionResumesClock() throws {
        let suite = try XCTUnwrap(UserDefaults(suiteName: "lw-decision-\(UUID().uuidString)"))
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("lw-decision-\(UUID().uuidString)")
        let session = LivingWorldSession(playerCountryCode: "BRA", seed: 55, slot: 2, defaults: suite, persistenceDirectory: dir)

        let option = LWDecisionOption(
            id: "opt-1",
            text: "Executive Directive A",
            consequenceSummary: "Stabilizes capital.",
            radicalDelta: -0.1,
            treasuryDelta: -2.0,
            stabilityDelta: 0.1,
            nextChainedEventID: nil,
            setFlag: "test_flag"
        )
        let decision = LWDecisionEvent(
            id: "session-decision",
            title: "Cabinet Emergency",
            summary: "Cabinet awaits presidential directive.",
            day: session.world.dayIndex,
            targetCountryCode: "BRA",
            imageAssetName: "EventBreadRiots",
            options: [option]
        )
        session.world.pendingDecision = decision

        // Attempting to step or play while decision is pending should be blocked
        let dayBefore = session.world.dayIndex
        session.stepDay()
        XCTAssertEqual(session.world.dayIndex, dayBefore, "stepDay must be blocked while decision is pending")

        // Player makes decision
        session.chooseDecisionOption(option)
        XCTAssertNil(session.world.pendingDecision, "Pending decision must be cleared")
        XCTAssertEqual(session.world.eventFlags["test_flag"], "opt-1")

        // Clock can now advance
        session.stepDay()
        XCTAssertEqual(session.world.dayIndex, dayBefore + 1, "Clock must resume advancing after decision is resolved")
    }
}
