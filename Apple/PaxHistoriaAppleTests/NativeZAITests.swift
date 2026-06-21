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
            await limiter.exit()
        }

        let task2 = Task { @MainActor in
            try? await limiter.enter()
            activeCount += 1
            maxObservedCount = max(maxObservedCount, activeCount)

            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms

            activeCount -= 1
            await limiter.exit()
        }

        let task3 = Task { @MainActor in
            try? await limiter.enter()
            activeCount += 1
            maxObservedCount = max(maxObservedCount, activeCount)

            try? await Task.sleep(nanoseconds: 10_000_000) // 10ms

            activeCount -= 1
            await limiter.exit()
        }

        _ = await (task1.value, task2.value, task3.value)

        XCTAssertLessThanOrEqual(maxObservedCount, 2, "Concurrency Limiter failed to restrict execution under max concurrent count.")
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
}
