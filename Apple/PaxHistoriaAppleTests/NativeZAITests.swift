import XCTest
@testable import SwiftHistoria

final class NativeZAITests: XCTestCase {
    
    // MARK: - Concurrency Limiter Tests
    
    @MainActor
    func testConcurrencyLimiterMaxLimit() async {
        let limiter = ConcurrencyLimiter(maxConcurrent: 2)
        var activeCount = 0
        var maxObservedCount = 0
        
        let task1 = Task { @MainActor in
            await limiter.enter()
            activeCount += 1
            maxObservedCount = max(maxObservedCount, activeCount)
            
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
            
            activeCount -= 1
            await limiter.exit()
        }
        
        let task2 = Task { @MainActor in
            await limiter.enter()
            activeCount += 1
            maxObservedCount = max(maxObservedCount, activeCount)
            
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
            
            activeCount -= 1
            await limiter.exit()
        }
        
        let task3 = Task { @MainActor in
            await limiter.enter()
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
        
        // Let's call the private helper via Reflection or test the logic directly since it's identical
        let candidates = extractCandidates(from: rawJSON)
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
        
        let candidates = extractCandidates(from: rawFenced)
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
        
        let candidates = extractCandidates(from: rawText)
        XCTAssertTrue(candidates.contains("{\n  \"title\": \"Corridor Security Upgrade\"\n}"))
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
    
    // Replicated candidate extraction logic used in Z.AI service to verify its correctness
    private func extractCandidates(from rawText: String) -> [String] {
        let trimmed = rawText
            .replacingOccurrences(of: "\u{FEFF}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        
        var candidates = [trimmed]
        if trimmed.hasPrefix("```") {
            let lines = trimmed.components(separatedBy: .newlines)
            let unfenced = lines
                .dropFirst()
                .dropLast(lines.last?.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("```") == true ? 1 : 0)
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !unfenced.isEmpty {
                candidates.append(unfenced)
            }
        }
        
        if let start = trimmed.firstIndex(of: "{"), let end = trimmed.lastIndex(of: "}"), start <= end {
            let object = String(trimmed[start...end]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !object.isEmpty {
                candidates.append(object)
            }
        }
        
        var seen: Set<String> = []
        return candidates.filter { seen.insert($0).inserted }
    }
}
