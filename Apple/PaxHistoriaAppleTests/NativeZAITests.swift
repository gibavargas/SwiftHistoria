@testable import SwiftHistoria
import XCTest

final class NativeZAITests: XCTestCase {
    // MARK: - Concurrency Limiter Tests

    @MainActor
    func testConcurrencyLimiterMaxLimit() async {
        let limiter = ConcurrencyLimiter(maxConcurrent: 2)
        var activeCount = 0
        var maxObservedCount = 0

        let task1 = Task { @MainActor in
            try? await limiter.enter()
            activeCount += 1
            maxObservedCount = max(maxObservedCount, activeCount)

            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms

            activeCount -= 1
            limiter.exit()
        }

        let task2 = Task { @MainActor in
            try? await limiter.enter()
            activeCount += 1
            maxObservedCount = max(maxObservedCount, activeCount)

            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms

            activeCount -= 1
            limiter.exit()
        }

        let task3 = Task { @MainActor in
            try? await limiter.enter()
            activeCount += 1
            maxObservedCount = max(maxObservedCount, activeCount)

            try? await Task.sleep(nanoseconds: 10_000_000) // 10ms

            activeCount -= 1
            limiter.exit()
        }

        _ = await (task1.value, task2.value, task3.value)

        XCTAssertLessThanOrEqual(maxObservedCount, 2, "Concurrency Limiter failed to restrict execution under max concurrent count.")
    }

    @MainActor
    func testConcurrencyLimiterCancellationReturnsPermit() async throws {
        let limiter = ConcurrencyLimiter(maxConcurrent: 1)
        try await limiter.enter()

        let waiter = Task { @MainActor in
            do {
                try await limiter.enter()
                limiter.exit()
                return false
            } catch is CancellationError {
                return true
            } catch {
                XCTFail("Unexpected limiter error: \(error)")
                return false
            }
        }
        await Task.yield()
        waiter.cancel()
        limiter.exit()

        let cancellationObserved = await waiter.value
        XCTAssertTrue(cancellationObserved)
        try await limiter.enter()
        limiter.exit()
    }

    // MARK: - JSON Candidate Extraction Tests

    func testJSONCandidatesExtractionStandard() {
        let rawJSON = """
        {
          "title": "Corridor Security Upgrade",
          "description": "Standard border logistics coordination."
        }
        """

        let candidates = NativeJSONExtraction.candidates(from: rawJSON)
        XCTAssertTrue(candidates.contains(rawJSON.trimmingCharacters(in: .whitespacesAndNewlines)))
    }

    func testJSONCandidatesExtractionFenced() {
        let rawFenced = """
        ```json
        {
          "title": "Corridor Security Upgrade"
        }
        ```
        """

        let candidates = NativeJSONExtraction.candidates(from: rawFenced)
        XCTAssertTrue(candidates.contains("{\n  \"title\": \"Corridor Security Upgrade\"\n}"))
    }

    func testJSONCandidatesExtractionWithSurroundingText() {
        let rawText = """
        Here is the JSON you requested:
        {
          "title": "Corridor Security Upgrade"
        }
        Hope this helps!
        """

        let candidates = NativeJSONExtraction.candidates(from: rawText)
        XCTAssertTrue(candidates.contains("{\n  \"title\": \"Corridor Security Upgrade\"\n}"))
    }

    func testJSONCandidatesExtractionUsesBalancedObjectsInsteadOfGreedyRange() {
        let rawText = """
        First option:
        {"title":"Corridor Security Upgrade"}
        Second option:
        {"title":"Port Clearance Delay","effectTrack":"market-confidence"}
        """

        let candidates = NativeJSONExtraction.candidates(from: rawText)

        XCTAssertTrue(candidates.contains("{\"title\":\"Corridor Security Upgrade\"}"))
        XCTAssertTrue(candidates.contains("{\"title\":\"Port Clearance Delay\",\"effectTrack\":\"market-confidence\"}"))
        XCTAssertFalse(candidates.contains("""
        {"title":"Corridor Security Upgrade"}
        Second option:
        {"title":"Port Clearance Delay","effectTrack":"market-confidence"}
        """))
    }

    func testCompletionDecoderAcceptsVisibleContentWithReasoning() throws {
        let response = """
        {
          "choices": [
            {
              "message": {
                "role": "assistant",
                "reasoning_content": "Internal analysis",
                "content": "<think>Internal analysis</think>{\\"title\\":\\"Corridor Security Upgrade\\"}"
              },
              "finish_reason": "stop"
            }
          ]
        }
        """

        let content = try NativeZAIService.decodeCompletionContent(from: XCTUnwrap(response.data(using: .utf8)))
        XCTAssertEqual(content, "{\"title\":\"Corridor Security Upgrade\"}")
    }

    func testReasoningDeltaPrefersVisibleDetailsAndMarksEncryptedPayloads() {
        let delta: [String: Any] = [
            "reasoning_details": [
                ["type": "reasoning.text", "text": "Compare the queued orders. "],
                ["type": "reasoning.summary", "summary": "Check regional reactions."],
                ["type": "reasoning.encrypted", "data": "opaque-provider-payload"]
            ]
        ]

        let parsed = NativeZAIService.reasoningDelta(from: delta)

        XCTAssertEqual(parsed.text, "Compare the queued orders. Check regional reactions.")
        XCTAssertTrue(parsed.encrypted)
    }

    func testReasoningDeltaAcceptsOpenAICompatibleAliases() {
        XCTAssertEqual(
            NativeZAIService.reasoningDelta(from: ["reasoning": "Reasoning alias"]).text,
            "Reasoning alias"
        )
        XCTAssertEqual(
            NativeZAIService.reasoningDelta(from: ["reasoning_content": "Legacy alias"]).text,
            "Legacy alias"
        )
    }

    func testReasoningPreviewIsWhitespaceStableAndBounded() {
        let preview = NativeZAIService.reasoningPreview(
            from: "First\n\nstep   then a much longer final conclusion",
            characterLimit: 24
        )

        XCTAssertLessThanOrEqual(preview.count, 25)
        XCTAssertTrue(preview.hasPrefix("…"))
        XCTAssertFalse(preview.contains("\n"))
    }

    func testCompletionDecoderReportsEmptyVisibleContent() throws {
        let response = """
        {
          "choices": [
            {
              "message": {
                "role": "assistant",
                "reasoning_content": "Internal analysis",
                "content": null
              },
              "finish_reason": "length"
            }
          ]
        }
        """

        XCTAssertThrowsError(try NativeZAIService.decodeCompletionContent(from: XCTUnwrap(response.data(using: .utf8)))) { error in
            XCTAssertTrue(error.localizedDescription.contains("finish_reason=length"))
        }
    }

    func testCompletionDecoderRejectsPartialContentWhenFinishReasonIsLength() throws {
        let response = """
        {
          "choices": [
            {
              "message": {
                "role": "assistant",
                "content": "# STRATEGIC ADVISORY BRIEF\\n\\nWorld Tension sits at 80 and Brazil's"
              },
              "finish_reason": "length"
            }
          ]
        }
        """

        XCTAssertThrowsError(try NativeZAIService.decodeCompletionContent(from: XCTUnwrap(response.data(using: .utf8)))) { error in
            XCTAssertTrue(error.localizedDescription.contains("finish_reason=length"))
        }
    }

    // MARK: - Deterministic 5 x 5 World Simulator Tests

    func testCPUProfileSpaceContainsExactly4096UniquePolicies() {
        let profiles = (0 ..< NativeWorldSimulator.profileCount).map(NativeCPUDecisionProfile.init)

        XCTAssertEqual(profiles.count, 4096)
        XCTAssertEqual(Set(profiles.map(\.id)).count, 4096)
        XCTAssertTrue(profiles.allSatisfy {
            [$0.risk, $0.patience, $0.cooperation, $0.force, $0.welfare, $0.sovereignty]
                .allSatisfy { (0 ... 3).contains($0) }
        })
    }

    func testEveryCPUCountryBuildsOneDecisionForEveryMatrixCoordinate() throws {
        let state = NativeGameEngine.initialState(
            for: PlayerCountry(code: "BRA", name: "Brazil"),
            worldSeed: 0xCAFE_BABE
        )
        let aiState = try XCTUnwrap(state.aiCountryStates["USA"])
        let matrix = NativeWorldSimulator.matrix(for: "USA", state: state, aiState: aiState)

        XCTAssertEqual(matrix.count, 25)
        XCTAssertEqual(Set(matrix.map { "\($0.matrixRow):\($0.matrixColumn)" }).count, 25)
        XCTAssertEqual(Set(matrix.map(\.countryCode)), Set(["USA"]))
    }

    func testCountryDecisionReplayUsesSeedProfileAndStep() throws {
        let first = NativeGameEngine.initialState(
            for: PlayerCountry(code: "BRA", name: "Brazil"),
            worldSeed: 12345
        )
        let second = NativeGameEngine.initialState(
            for: PlayerCountry(code: "BRA", name: "Brazil"),
            worldSeed: 12345
        )
        let firstAI = try XCTUnwrap(first.aiCountryStates["CHN"])
        let secondAI = try XCTUnwrap(second.aiCountryStates["CHN"])

        XCTAssertEqual(firstAI.decisionSeed, secondAI.decisionSeed)
        XCTAssertEqual(firstAI.decisionProfileID, secondAI.decisionProfileID)
        XCTAssertEqual(
            NativeWorldSimulator.chooseDecision(for: "CHN", state: first, aiState: firstAI),
            NativeWorldSimulator.chooseDecision(for: "CHN", state: second, aiState: secondAI)
        )
    }

    func testParallelWorldSimulationIsScheduleIndependent() async {
        let state = NativeGameEngine.initialState(
            for: PlayerCountry(code: "BRA", name: "Brazil"),
            worldSeed: 987_654_321
        )

        async let first = NativeWorldSimulator.simulate(state: state, months: 3)
        async let second = NativeWorldSimulator.simulate(state: state, months: 3)
        let (lhs, rhs) = await (first, second)

        XCTAssertEqual(lhs.events, rhs.events)
        XCTAssertEqual(lhs.updatedStates, rhs.updatedStates)
        XCTAssertEqual(lhs.updatedStates.count, state.aiCountryStates.count - 1)
        XCTAssertTrue(lhs.updatedStates.values.allSatisfy { $0.decisionStep == 1 })
        XCTAssertTrue(lhs.events.allSatisfy {
            $0.date == NativeGameEngine.advance(date: state.gameDate, months: 3)
        })
    }

    func testCPUMatrixAccommodatesSecessionWhenStoredPressureExists() throws {
        var state = NativeGameEngine.initialState(
            for: PlayerCountry(code: "BRA", name: "Brazil"),
            worldSeed: 77
        )
        let region = try XCTUnwrap(GeopoliticalMapData.regions(forCountryCode: "ARG").first)
        state.economicLedgers["ARG"]?.rebelControlPercent = 55
        state.regionConflicts[region.id] = NativeRegionConflictState(
            controllerCode: "REB",
            intensity: 4,
            mode: .guerrillaControl,
            originalCountryCode: "ARG",
            regionID: region.id
        )
        let aiState = try XCTUnwrap(state.aiCountryStates["ARG"])
        let matrix = NativeWorldSimulator.matrix(for: "ARG", state: state, aiState: aiState)
        let secession = try XCTUnwrap(matrix.first { $0.sovereigntyChange?.kind == .secession })

        XCTAssertEqual(secession.matrixRow, NativeDecisionMatrixRow.sovereignty.rawValue)
        XCTAssertEqual(secession.sovereigntyChange?.sourceCodes, ["ARG"])
        XCTAssertEqual(secession.sovereigntyChange?.regionIDs, [region.id])
    }
}
