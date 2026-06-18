import Foundation

/// Cleans Foundation Model output for display: trims whitespace and collapses
/// accidental duplicate sentences/lines that small on-device models sometimes emit.
/// No content filtering or vocabulary substitution is performed — the game is a
/// geopolitical strategy simulator and AI output is shown verbatim to the player.
public func sanitizeFoundationModelText(_ value: String) -> String {
    let result = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return collapseRepeatedLines(in: collapseRepeatedSentences(in: result))
}

private func collapseRepeatedSentences(in value: String) -> String {
    let parts = value.components(separatedBy: ". ")
    guard parts.count > 1 else { return value }

    let trimSet = CharacterSet.whitespacesAndNewlines
        .union(CharacterSet(charactersIn: ".!?"))
    var seen = Set<String>()
    var collapsed: [String] = []

    for part in parts {
        let normalized = part.trimmingCharacters(in: trimSet).lowercased()
        guard !normalized.isEmpty else {
            collapsed.append(part)
            continue
        }
        guard !seen.contains(normalized) else { continue }
        collapsed.append(part)
        seen.insert(normalized)
    }

    return collapsed.joined(separator: ". ")
}

private func collapseRepeatedLines(in value: String) -> String {
    let lines = value.components(separatedBy: .newlines)
    guard lines.count > 1 else { return value }

    var previousNormalized = ""
    var collapsed: [String] = []

    for line in lines {
        let normalized = line.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else {
            collapsed.append(line)
            previousNormalized = ""
            continue
        }
        guard normalized != previousNormalized else { continue }
        collapsed.append(line)
        previousNormalized = normalized
    }

    return collapsed.joined(separator: "\n")
}

public func hasConcreteFoundationText(_ value: String, minimumWords: Int) -> Bool {
    let cleaned = sanitizeFoundationModelText(value)
    return !containsFoundationPlaceholderText(cleaned) &&
        cleaned.split(separator: " ").count >= minimumWords
}

public func normalizedFoundationUrgency(_ value: String) -> String {
    switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "immediate", "soon", "opportunistic":
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    default:
        "soon"
    }
}

/// Returns the prompt-friendly label for a strategic track.
/// Uses the real track names — no obfuscation.
public func foundationPromptTrackLabel(_ track: NativeStrategicTrack) -> String {
    switch track {
    case .diplomaticLeverage:
        "diplomatic-leverage"
    case .economicResilience:
        "economic-resilience"
    case .internalStability:
        "internal-stability"
    case .marketConfidence:
        "market-confidence"
    case .militaryReadiness:
        "military-readiness"
    case .securityAnxiety:
        "security-anxiety"
    case .worldTension:
        "world-tension"
    }
}

/// Identity function — all strategic tracks are valid and visible to the player.
public func foundationVisibleTrack(_ track: NativeStrategicTrack) -> NativeStrategicTrack {
    track
}

public func containsFoundationPlaceholderText(_ value: String) -> Bool {
    let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let blockedFragments = [
        "applenativegeneratedeventdraft",
        "applenativesuggestedaction",
        "applenativeturnsummary",
        "apple native generated event draft",
        "apple native suggested action",
        "apple native turn summary",
        "generated event draft",
        "schema type",
        "field name",
        "property name",
        "placeholder",
        "example title",
        "sample title",
        "lorem ipsum",
        "todo:",
        "to do",
        "tbd"
    ]
    return blockedFragments.contains { normalized.contains($0) }
}
