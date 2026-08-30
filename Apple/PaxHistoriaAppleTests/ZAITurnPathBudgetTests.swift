@testable import SwiftHistoria
import XCTest

// MARK: - Turn-path provider-call budget

/// The batched turn path must complete a full campaign turn in exactly ONE
/// provider call (two only when validation forces a repair retry). This pins
/// the call-budget contract that replaced the 5-8-call lane fan-out.
@MainActor
final class ZAITurnPathBudgetTests: XCTestCase {
    /// Counts transport-layer invocations instead of hitting the network.
    private final class CountingZAIService: NativeExternalAIService {
        private(set) var requestCount = 0

        override func executeProviderRequest(
            prompt _: String,
            maxTokens _: Int,
            temperature _: Double,
            responseFormat _: String?,
            thinkingEnabled _: Bool,
            onStreamProgress _: (@MainActor (String) -> Void)?,
            onReasoningProgress _: (@MainActor (NativeReasoningStreamUpdate) -> Void)?,
            requestTimeout _: TimeInterval,
            retryLimit _: Int
        ) async throws -> String {
            requestCount += 1
            return Self.envelopeJSON
        }

        static let eventJSON = """
        {"title":"Corridor Resilience Program Advances","description":"The regional planning office completes a freight resilience audit covering two priority corridors and one intermodal yard.","kind":"world","importance":"major","notable":true,"effectTarget":"PLAYER","effectTrack":"\u{27E6}ECO\u{27E7}","effectMagnitude":1,"effectSummary":"Freight audit findings lift logistics reliability and economic resilience modestly."}
        """

        static let envelopeJSON = """
        {
          "independent": \(eventJSON),
          "economic": \(eventJSON),
          "domestic": \(eventJSON),
          "globalAI": \(eventJSON),
          "actions": [],
          "summary": {
            "summary": "The quarter closes with a resilient freight program and steady fiscal footing.",
            "stabilityDelta": 1,
            "globalFrictionDelta": 0
          }
        }
        """
    }

    private func makeState() -> NativeCampaignState {
        NativeGameEngine.initialState(
            for: PlayerCountry(code: "BRA", name: "Brazil"),
            scenario: NativeScenarioCatalog.resilienceDecade,
            language: .english
        )
    }

    func testTurnPathUsesSingleProviderCall() async throws {
        let service = CountingZAIService()
        let state = makeState()

        let generated = try await service.generateTurn(for: state, months: 1) { _ in }

        XCTAssertEqual(service.requestCount, 1, "Batched turn must use exactly one provider call")
        XCTAssertEqual(generated.events.count, 4, "Envelope must yield independent, economic, domestic, and global AI events")
        XCTAssertTrue(generated.events.contains { $0.playerRelated })
        XCTAssertTrue(generated.events.contains { !$0.playerRelated })
        XCTAssertFalse(generated.summary.isEmpty)
    }
}
