import Foundation

/// Resolves 3-letter country codes (ISO alpha-3) to human-readable names.
///
/// Used throughout the UI to replace raw codes like "USA", "CHN", "RUS" with
/// "United States", "China", "Russia". Dynamic countries (created mid-campaign
/// via sovereignty changes) are resolved from the campaign's `dynamicCountries`
/// dictionary. Unknown codes fall back to the code itself so the player always
/// sees something.
enum CountryNameResolver {
    /// Cached lookup: alpha-3 code → display name from CountryCatalog.
    private static let catalogByName: [String: String] = Dictionary(CountryCatalog.all.map { ($0.code, $0.name) }, uniquingKeysWith: { _, last in last })
    /// Map-geometry codes sometimes differ from catalog ISO codes. Index both
    /// directions so PSX/PSE and KOS/XXK resolve to one human-readable actor.
    private static let catalogByCanonicalCode: [String: String] = Dictionary(
        CountryCatalog.all.map { (GeopoliticalMapData.canonicalCountryCode($0.code), $0.name) },
        uniquingKeysWith: { _, last in last }
    )

    /// Special display names for non-country entities that appear as effect targets.
    private static let specialNames: [String: String] = [
        "GLOBAL": "International System",
        "INTERNATIONAL SYSTEM": "International System",
        "INTERNATION SYSTEM": "International System",
        "REB": "Rebel Forces",
        "WATER": ""
    ]

    /// Resolves a single code to a display name.
    /// - Parameters:
    ///   - code: The 3-letter code (case-insensitive).
    ///   - dynamicCountries: Optional map of dynamic country codes → names from campaign state.
    /// - Returns: The human-readable name, or the original code if unrecognized.
    static func name(forCode code: String, dynamicCountries: [String: String] = [:]) -> String {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let upper = trimmed.uppercased()

        // Dynamic countries take priority (they may shadow an existing code)
        if let dynamic = dynamicCountries[upper], !dynamic.isEmpty {
            return dynamic
        }
        if let dynamic = dynamicCountries[trimmed], !dynamic.isEmpty {
            return dynamic
        }

        // Special targets
        if let special = specialNames[upper] {
            return special.isEmpty ? upper : special
        }

        // Standard catalog lookup
        if let name = catalogByName[upper] {
            return name
        }

        // Canonical normalization in either direction (for example PSE/PSX).
        let canonical = GeopoliticalMapData.canonicalCountryCode(upper)
        if let name = catalogByCanonicalCode[canonical] {
            return name
        }

        // Unknown — return the code so the player sees *something*
        return upper
    }

    /// Convenience for resolving from a `NativeCampaignState`.
    static func name(forCode code: String, in state: NativeCampaignState?) -> String {
        name(forCode: code, dynamicCountries: state?.dynamicCountries ?? [:])
    }

    /// Resolves a code and formats it as "Name (CODE)" for contexts where both
    /// the name and the identifier are useful (intelligence reports, diplomacy logs).
    static func nameWithCode(_ code: String, dynamicCountries: [String: String] = [:]) -> String {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let resolved = name(forCode: trimmed, dynamicCountries: dynamicCountries)
        let upper = trimmed.uppercased()
        // Don't append the code if it's already the resolved name (unknown code)
        if resolved == upper {
            return resolved
        }
        // Don't append for special names
        if specialNames[upper] != nil {
            return resolved
        }
        return "\(resolved) (\(upper))"
    }

    /// Scans a block of text and replaces standalone 3+ letter uppercase country
    /// codes with their resolved names. Used for event descriptions and summaries
    /// where the LLM may have embedded raw codes.
    ///
    /// Only replaces tokens that are entirely uppercase A-Z and length 3-6 (matching
    /// the sovereignty code contract). Lowercase words and mixed-case tokens are left
    /// untouched to avoid mangling normal prose.
    static func replaceCodesInText(_ text: String, dynamicCountries: [String: String] = [:]) -> String {
        // Only replace if we have a catalog to check against — skip trivial text
        guard !text.isEmpty else { return text }

        let pattern = "\\b([A-Z]{3,6})\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return text
        }

        let range = NSRange(text.startIndex..., in: text)
        let mutable = NSMutableString(string: text)
        // Collect matches in reverse so indices don't shift
        let matches = regex.matches(in: text, range: range).reversed()

        for match in matches {
            guard let matchRange = Range(match.range, in: text) else { continue }
            let code = String(text[matchRange])
            let resolved = name(forCode: code, dynamicCountries: dynamicCountries)

            // Only replace if resolution found a real name (not the fallback code itself)
            // and it's not a special target that should stay as-is
            if resolved != code, resolved != code.uppercased() {
                let nsRange = NSRange(location: match.range.location, length: match.range.length)
                mutable.replaceCharacters(in: nsRange, with: resolved)
            }
        }

        return String(mutable)
    }

    /// Convenience for `replaceCodesInText` using campaign state.
    static func replaceCodesInText(_ text: String, in state: NativeCampaignState?) -> String {
        replaceCodesInText(text, dynamicCountries: state?.dynamicCountries ?? [:])
    }
}
