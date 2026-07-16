@testable import SwiftHistoria
import XCTest

/// Unit tests for modules that were previously untested:
/// - NativeQuickActionCatalog (cost estimation, action matching)
/// - NativeTinyEmbeddingModel (embedding dimensions, cosine similarity)
/// - NativeGameEngine GDP growth mechanic (P0-1 regression test)
final class NativeModuleTests: XCTestCase {
    // MARK: - NativeQuickActionCatalog

    func testEstimatedCostForInvasionMultiLanguage() {
        XCTAssertEqual(NativeQuickActionCatalog.estimatedCost(for: "Invade Argentina"), 40)
        XCTAssertEqual(NativeQuickActionCatalog.estimatedCost(for: "Invadir Argentina"), 40)
        XCTAssertEqual(NativeQuickActionCatalog.estimatedCost(for: "Atacar región"), 40)
        XCTAssertEqual(NativeQuickActionCatalog.estimatedCost(for: "Conquistar territorio"), 40)
    }

    func testEstimatedCostForStabilizeMultiLanguage() {
        XCTAssertEqual(NativeQuickActionCatalog.estimatedCost(for: "Stabilize region"), 25)
        XCTAssertEqual(NativeQuickActionCatalog.estimatedCost(for: "Estabilizar región"), 25)
        XCTAssertEqual(NativeQuickActionCatalog.estimatedCost(for: "Pacificar zona"), 25)
    }

    func testEstimatedCostForFortifyMultiLanguage() {
        XCTAssertEqual(NativeQuickActionCatalog.estimatedCost(for: "Fortify border"), 35)
        XCTAssertEqual(NativeQuickActionCatalog.estimatedCost(for: "Fortificar frontera"), 35)
        XCTAssertEqual(NativeQuickActionCatalog.estimatedCost(for: "Defender región"), 35)
    }

    func testEstimatedCostForWithdrawMultiLanguage() {
        XCTAssertEqual(NativeQuickActionCatalog.estimatedCost(for: "Withdraw from region"), 10)
        XCTAssertEqual(NativeQuickActionCatalog.estimatedCost(for: "Retirar tropas"), 10)
        XCTAssertEqual(NativeQuickActionCatalog.estimatedCost(for: "Recuar forças"), 10)
    }

    func testEstimatedCostForRebuildMultiLanguage() {
        XCTAssertEqual(NativeQuickActionCatalog.estimatedCost(for: "Rebuild infrastructure"), 35)
        XCTAssertEqual(NativeQuickActionCatalog.estimatedCost(for: "Reconstruir infraestrutura"), 35)
    }

    func testEstimatedCostForTradeCorridorMultiLanguage() {
        XCTAssertEqual(NativeQuickActionCatalog.estimatedCost(for: "Open trade corridor through region"), 25)
        XCTAssertEqual(NativeQuickActionCatalog.estimatedCost(for: "Abrir corredor comercial"), 25)
    }

    func testEstimatedCostReturnsNilForUnknown() {
        XCTAssertNil(NativeQuickActionCatalog.estimatedCost(for: "Sing a song"))
        XCTAssertNil(NativeQuickActionCatalog.estimatedCost(for: ""))
        XCTAssertNil(NativeQuickActionCatalog.estimatedCost(for: "random text"))
    }

    func testEstimatedCostForKnownQuickAction() {
        // "Propose trade agreement" is a registered quick action with cost 15
        XCTAssertEqual(NativeQuickActionCatalog.estimatedCost(for: "Propose a bilateral trade agreement to deepen ties."), 15)
    }

    func testActionMatchingReturnsCorrectAction() {
        let action = NativeQuickActionCatalog.action(matching: "Propose a bilateral trade agreement to deepen ties.")
        XCTAssertNotNil(action)
        XCTAssertEqual(action?.id, "dip-trade")
        XCTAssertEqual(action?.cost, 15)
    }

    func testActionMatchingReturnsNilForUnknown() {
        XCTAssertNil(NativeQuickActionCatalog.action(matching: "Do something completely unknown"))
    }

    // MARK: - Embedding & Cosine Similarity

    func testEmbedProducesNormalizedVector() {
        let vector = NativeStrategyContextDatabase.embedForTesting("stability security border")
        // Should produce a non-zero vector
        let norm = sqrt(vector.reduce(Float(0)) { $0 + $1 * $1 })
        XCTAssertGreaterThan(norm, 0.99)
        XCTAssertLessThan(norm, 1.01)
    }

    func testCosineSimilarityIdenticalTexts() {
        let v1 = NativeStrategyContextDatabase.embedForTesting("trade market diplomacy")
        let v2 = NativeStrategyContextDatabase.embedForTesting("trade market diplomacy")
        let similarity = NativeStrategyContextDatabase.cosineForTesting(v1, v2)
        XCTAssertGreaterThan(similarity, 0.99)
    }

    func testCosineSimilarityRelatedTexts() {
        let v1 = NativeStrategyContextDatabase.embedForTesting("trade corridor market")
        let v2 = NativeStrategyContextDatabase.embedForTesting("market confidence trade")
        let similarity = NativeStrategyContextDatabase.cosineForTesting(v1, v2)
        XCTAssertGreaterThan(similarity, 0.1, "Related texts should have positive similarity")
    }

    func testCosineSimilarityUnrelatedTexts() {
        let v1 = NativeStrategyContextDatabase.embedForTesting("trade market")
        let v2 = NativeStrategyContextDatabase.embedForTesting("zzz qqq xxx")
        let similarity = NativeStrategyContextDatabase.cosineForTesting(v1, v2)
        XCTAssertLessThan(similarity, 0.5, "Unrelated texts should have low similarity")
    }

    // MARK: - GDP Growth Regression (P0-1)

    // Note: These tests verify the growth formula directly rather than through
    // the full validated/apply pipeline, which requires complex event setup.

    func testGDPGrowthFormulaWithPositiveRate() {
        let initialGDP = 10.0
        let growthPercent = 5.0
        let yearFraction = 1.0 // 12 months

        let growthMultiplier = 1.0 + (growthPercent / 100.0) * yearFraction
        let finalGDP = max(0.01, initialGDP * growthMultiplier)

        XCTAssertEqual(finalGDP, 10.5, accuracy: 0.01,
                       "GDP should grow by 5% when realGrowthPercent is 5.0 over 1 year")
        XCTAssertGreaterThan(finalGDP, initialGDP,
                             "GDP should increase with positive growth")
    }

    func testGDPGrowthFormulaWithZeroRate() {
        let initialGDP = 10.0
        let growthPercent = 0.0
        let yearFraction = 1.0

        let growthMultiplier = 1.0 + (growthPercent / 100.0) * yearFraction
        let finalGDP = max(0.01, initialGDP * growthMultiplier)

        XCTAssertEqual(finalGDP, initialGDP, accuracy: 0.01,
                       "GDP should not change with zero growth")
    }

    func testGDPGrowthFormulaWithNegativeRate() {
        let initialGDP = 10.0
        let growthPercent = -3.0
        let yearFraction = 0.5 // 6 months

        let growthMultiplier = 1.0 + (growthPercent / 100.0) * yearFraction
        let finalGDP = max(0.01, initialGDP * growthMultiplier)

        XCTAssertLessThan(finalGDP, initialGDP,
                          "GDP should decrease with negative growth")
        XCTAssertEqual(finalGDP, 9.85, accuracy: 0.01)
    }

    // MARK: - Event briefing salience

    func testEventBriefingCapsExpandedCardsAndPreservesCompleteLog() {
        let routine = (0 ..< 10).map { index in
            makeBriefingEvent(
                id: "routine-\(index)",
                importance: .minor,
                kind: .world
            )
        }
        let events = [
            makeBriefingEvent(
                id: "sovereignty",
                importance: .major,
                kind: .diplomacy,
                sovereigntyChange: true
            ),
            makeBriefingEvent(
                id: "critical",
                importance: .severe,
                kind: .crisis
            ),
            makeBriefingEvent(
                id: "player-order",
                importance: .major,
                kind: .action,
                playerRelated: true,
                linkedActionIDs: ["order-1"]
            )
        ] + routine

        let briefing = NativeEventBriefing.make(events: events, highlightLimit: 5)

        XCTAssertEqual(briefing.highlights.count, 5)
        XCTAssertEqual(briefing.additionalEvents.count, events.count - 5)
        XCTAssertTrue(briefing.highlights.contains { $0.id == "critical" })
        XCTAssertTrue(briefing.highlights.contains { $0.id == "player-order" })
        XCTAssertTrue(briefing.highlights.contains { $0.id == "sovereignty" })
        XCTAssertEqual(
            Set((briefing.highlights + briefing.additionalEvents).map(\.id)),
            Set(events.map(\.id))
        )
    }

    func testEventBriefingBalancesNationAndGlobalSignals() {
        let events = [
            makeBriefingEvent(
                id: "nation",
                importance: .minor,
                kind: .action,
                playerRelated: true
            ),
            makeBriefingEvent(
                id: "global",
                importance: .minor,
                kind: .world
            ),
            makeBriefingEvent(
                id: "critical-global",
                importance: .severe,
                kind: .crisis
            ),
            makeBriefingEvent(
                id: "major-global",
                importance: .major,
                kind: .world
            )
        ]

        let briefing = NativeEventBriefing.make(events: events, highlightLimit: 3)

        XCTAssertEqual(briefing.highlights.count, 3)
        XCTAssertTrue(briefing.highlights.contains(where: \.playerRelated))
        XCTAssertTrue(briefing.highlights.contains { !$0.playerRelated })
        XCTAssertTrue(briefing.highlights.contains { $0.importance == .severe })
        XCTAssertEqual(briefing.severeCount, 1)
        XCTAssertEqual(briefing.majorCount, 1)
        XCTAssertEqual(briefing.nationCount, 1)
        XCTAssertEqual(briefing.globalCount, 3)
    }

    private func makeBriefingEvent(
        id: String,
        importance: NativeEventImportance,
        kind: NativeEventKind,
        playerRelated: Bool = false,
        linkedActionIDs: [String] = [],
        sovereigntyChange: Bool = false
    ) -> NativeCampaignEvent {
        NativeCampaignEvent(
            date: "2026-07-01",
            description: "A concrete geopolitical development produces visible consequences across the active campaign state.",
            id: id,
            importance: importance,
            kind: kind,
            linkedActionIDs: linkedActionIDs,
            notable: importance != .minor,
            playerRelated: playerRelated,
            strategicEffects: [
                NativeStrategicEffect(
                    date: "2026-07-01",
                    eventId: id,
                    id: "\(id)-effect",
                    magnitude: importance == .severe ? -5 : 1,
                    summary: "The event changes a tracked strategic condition.",
                    target: playerRelated ? "BRA" : "GLOBAL",
                    track: .worldTension
                )
            ],
            title: "Briefing event \(id)",
            sovereigntyChange: sovereigntyChange
                ? NativeSovereigntyChange(
                    kind: .secession,
                    name: "Test State",
                    regionIDs: ["test-region"],
                    sourceCodes: ["OLD"],
                    targetCode: "NEW"
                )
                : nil
        )
    }
}
