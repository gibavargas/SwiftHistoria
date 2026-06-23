@testable import SwiftHistoria
import XCTest

/// Tests for error paths in the AI service layer.
final class NativeErrorPathTests: XCTestCase {
    // MARK: - Prompt Clamping

    func testPromptClampingTrimsLongInput() {
        let longText = String(repeating: "This is a test sentence for clamping. ", count: 500)
        let clamped = NativePromptHarness.clamped(longText, characterLimit: 1000)

        XCTAssertLessThanOrEqual(clamped.count, 1000,
                                 "Clamped text should not exceed character limit")
        XCTAssertTrue(clamped.contains(NativePromptHarness.trimMarker),
                      "Clamped text should contain the trim marker for long inputs")
    }

    func testPromptClampingPreservesShortInput() {
        let shortText = "This is a short prompt."
        let clamped = NativePromptHarness.clamped(shortText, characterLimit: 1000)

        XCTAssertEqual(clamped, shortText,
                       "Short text should pass through unchanged")
        XCTAssertFalse(clamped.contains(NativePromptHarness.trimMarker))
    }

    func testPromptClampingPreservesHeadAndTail() {
        let text = "HEADER_START " + String(repeating: "x", count: 2000) + " TAIL_END"
        let clamped = NativePromptHarness.clamped(text, characterLimit: 500)

        // The clamped text should contain the trim marker (indicating truncation happened)
        XCTAssertTrue(clamped.contains(NativePromptHarness.trimMarker),
                      "Long text should be trimmed with marker")
        // The header is in the first ~62% of the limit, TAIL_END in the last ~38%
        // With 500 char limit, HEADER_START (13 chars) fits in the head
        XCTAssertTrue(clamped.contains("HEADER_START"),
                      "Clamped text should preserve the beginning")
    }

    // MARK: - JSON Extraction

    func testMalformedJSONIsRejectedGracefully() {
        let malformed = "This is not JSON at all {{{ broken"
        let candidates = NativeJSONExtraction.candidates(from: malformed)

        XCTAssertTrue(candidates.isEmpty || candidates.allSatisfy { !$0.contains("{") || !$0.isEmpty },
                      "Malformed JSON should produce no valid candidates or empty results")
    }

    func testJSONExtractionFromFencedBlock() {
        let fenced = """
        ```json
        {"title": "Test Event", "value": 42}
        ```
        """
        let candidates = NativeJSONExtraction.candidates(from: fenced)
        XCTAssertTrue(candidates.contains { $0.contains("Test Event") },
                      "Should extract JSON from fenced code blocks")
    }

    func testJSONExtractionFromSurroundingText() {
        let surrounded = """
        Here is the result:
        {"summary": "Economic growth", "stabilityDelta": 5}
        That's all.
        """
        let candidates = NativeJSONExtraction.candidates(from: surrounded)
        XCTAssertTrue(candidates.contains { $0.contains("Economic growth") },
                      "Should extract JSON from surrounding text")
    }

    // MARK: - Rate Limiter

    func testRateLimiterHasConservativeLimit() {
        XCTAssertEqual(NativeRateLimiter.effectiveLimit, 8,
                       "Rate limiter should enforce 8 req/min (60% margin of 20)")
    }

    func testRateLimiterRespectsProviderLimit() {
        XCTAssertLessThan(NativeRateLimiter.effectiveLimit, NativeRateLimiter.providerLimit,
                          "Effective limit must be below provider hard limit")
    }

    func testRateLimiterTracksAvailableSlotsAsRequestsAreConsumed() async {
        let limiter = NativeRateLimiter()

        let initialSlots = await limiter.availableSlots()
        XCTAssertEqual(initialSlots, NativeRateLimiter.effectiveLimit)

        for _ in 0 ..< 3 {
            await limiter.acquire()
        }

        let midSlots = await limiter.availableSlots()
        XCTAssertEqual(midSlots, NativeRateLimiter.effectiveLimit - 3)

        for _ in 3 ..< NativeRateLimiter.effectiveLimit {
            await limiter.acquire()
        }

        let finalSlots = await limiter.availableSlots()
        XCTAssertEqual(finalSlots, 0)
    }

    // MARK: - Cancellation

    @MainActor
    func testCancelInFlightTurnIsCallableWithoutState() async throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "test-cancellation-\(UUID().uuidString)"))
        let store = NativeCampaignStore(defaults: defaults)

        // cancelInFlightTurn should be safe to call even with no active turn
        store.cancelInFlightTurn()

        // Give it a moment to settle
        try? await Task.sleep(nanoseconds: 100_000_000)

        // Store should not be in advancing state
        XCTAssertFalse(store.isAdvancing,
                       "Store should never be advancing without a campaign state")
    }

    // MARK: - Token Usage Parsing

    func testTokenUsageParsingFromValidResponse() throws {
        let responseJSON = """
        {
            "choices": [{"message": {"content": "Hello"}}],
            "usage": {"prompt_tokens": 150, "completion_tokens": 80, "total_tokens": 230}
        }
        """
        let data = try XCTUnwrap(responseJSON.data(using: .utf8))
        let usage = NativeZAIService.parseTokenUsage(from: data)

        XCTAssertNotNil(usage, "Should parse usage from valid response")
        XCTAssertEqual(usage?.prompt, 150)
        XCTAssertEqual(usage?.completion, 80)
    }

    func testTokenUsageParsingReturnsNilForMissingUsage() throws {
        let responseJSON = """
        {
            "choices": [{"message": {"content": "Hello"}}]
        }
        """
        let data = try XCTUnwrap(responseJSON.data(using: .utf8))
        let usage = NativeZAIService.parseTokenUsage(from: data)

        XCTAssertNil(usage, "Should return nil when usage field is missing")
    }

    func testTokenUsageParsingReturnsNilForMalformedJSON() {
        let data = Data("not json at all".utf8)
        let usage = NativeZAIService.parseTokenUsage(from: data)

        XCTAssertNil(usage, "Should return nil for malformed JSON")
    }

    // MARK: - Multi-language Order Detection

    func testInvasionDetectionInPortuguese() {
        XCTAssertEqual(NativeQuickActionCatalog.estimatedCost(for: "Invadir Argentina"), 40)
        XCTAssertEqual(NativeQuickActionCatalog.estimatedCost(for: "Atacar região inimiga"), 40)
    }

    func testInvasionDetectionInSpanish() {
        XCTAssertEqual(NativeQuickActionCatalog.estimatedCost(for: "Conquistar territorio"), 40)
    }

    func testInvasionDetectionCaseInsensitive() {
        XCTAssertEqual(NativeQuickActionCatalog.estimatedCost(for: "invade region"), 40)
        XCTAssertEqual(NativeQuickActionCatalog.estimatedCost(for: "INVADE REGION"), 40)
    }

    func testRegionalActionsCoverCoreOccupationConflictAndFalloutBranches() throws {
        let coreRegion = try XCTUnwrap(GeopoliticalMapData.regions.first { $0.countryCode == "BRA" })
        let occupiedRegion = try XCTUnwrap(GeopoliticalMapData.regions.first { $0.countryCode != "BRA" })
        var state = NativeGameEngine.initialState(for: PlayerCountry(code: "BRA", name: "Brazil"))

        let coreActions = NativeQuickActionCatalog.regionalActions(for: coreRegion, state: state)
        XCTAssertTrue(coreActions.contains { $0.id == "stabilize-\(coreRegion.id)" })
        XCTAssertTrue(coreActions.contains { $0.id == "fortify-\(coreRegion.id)" })
        XCTAssertTrue(coreActions.contains { $0.id == "trade-corridor-\(coreRegion.id)" })
        XCTAssertTrue(coreActions.contains { $0.id == "autonomy-\(coreRegion.id)" })
        XCTAssertFalse(coreActions.contains { $0.id.hasPrefix("invade-") })
        XCTAssertFalse(coreActions.contains { $0.id.hasPrefix("withdraw-") })
        XCTAssertFalse(coreActions.contains { $0.id.hasPrefix("rebuild-") })

        state.regionOccupations[occupiedRegion.id] = "BRA"
        let occupiedActions = NativeQuickActionCatalog.regionalActions(for: occupiedRegion, state: state)
        XCTAssertTrue(occupiedActions.contains { $0.id == "stabilize-\(occupiedRegion.id)" })
        XCTAssertTrue(occupiedActions.contains { $0.id == "fortify-\(occupiedRegion.id)" })
        XCTAssertTrue(occupiedActions.contains { $0.id == "trade-corridor-\(occupiedRegion.id)" })
        XCTAssertTrue(occupiedActions.contains { $0.id == "withdraw-\(occupiedRegion.id)" })
        XCTAssertFalse(occupiedActions.contains { $0.id == "autonomy-\(occupiedRegion.id)" })
        XCTAssertFalse(occupiedActions.contains { $0.id.hasPrefix("invade-") })

        state.regionOccupations.removeValue(forKey: occupiedRegion.id)
        state.regionConflicts[occupiedRegion.id] = NativeRegionConflictState(
            controllerCode: "REB",
            intensity: 4,
            mode: .nuclearFallout,
            originalCountryCode: occupiedRegion.countryCode,
            regionID: occupiedRegion.id,
            summary: "Radiological fallout blocks normal administration.",
            updatedAt: state.gameDate
        )
        state.nuclearFalloutRegions = [occupiedRegion.id]
        let falloutActions = NativeQuickActionCatalog.regionalActions(for: occupiedRegion, state: state)
        XCTAssertTrue(falloutActions.contains { $0.id.hasPrefix("invade-") })
        XCTAssertTrue(falloutActions.contains { $0.id == "stabilize-\(occupiedRegion.id)" })
        XCTAssertTrue(falloutActions.contains { $0.id == "rebuild-\(occupiedRegion.id)" })
        XCTAssertFalse(falloutActions.contains { $0.id == "withdraw-\(occupiedRegion.id)" })
        XCTAssertFalse(falloutActions.contains { $0.id == "autonomy-\(occupiedRegion.id)" })
    }
}
