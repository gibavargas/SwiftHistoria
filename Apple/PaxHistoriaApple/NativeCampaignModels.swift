import Foundation

struct NativeCampaignState: Codable, Hashable {
    var advisorMessages: [NativeAdvisorMessage]
    var aiReadiness: NativeAIReadiness
    var country: PlayerCountry
    var diplomaticThreads: [NativeDiplomaticThread]
    var gameDate: String
    var lastSummary: String
    var language: NativeGameLanguage
    var plannedActions: [NativePlannedAction]
    var round: Int
    var scenarioDescription: String
    var scenarioID: String
    var scenarioName: String
    var suggestedActions: [NativeSuggestedAction]
    var stability: Int
    var startDate: String
    var timeline: [NativeCampaignEvent]
    var worldTension: Int
    var worldEffects: [NativeStrategicEffect]

    init(
        advisorMessages: [NativeAdvisorMessage] = [],
        aiReadiness: NativeAIReadiness,
        country: PlayerCountry,
        diplomaticThreads: [NativeDiplomaticThread] = [],
        gameDate: String,
        lastSummary: String,
        language: NativeGameLanguage = .english,
        plannedActions: [NativePlannedAction],
        round: Int,
        scenarioDescription: String,
        scenarioID: String,
        scenarioName: String,
        suggestedActions: [NativeSuggestedAction],
        stability: Int,
        startDate: String,
        timeline: [NativeCampaignEvent],
        worldTension: Int,
        worldEffects: [NativeStrategicEffect]
    ) {
        self.advisorMessages = advisorMessages
        self.aiReadiness = aiReadiness
        self.country = country
        self.diplomaticThreads = diplomaticThreads
        self.gameDate = gameDate
        self.lastSummary = lastSummary
        self.language = language
        self.plannedActions = plannedActions
        self.round = round
        self.scenarioDescription = scenarioDescription
        self.scenarioID = scenarioID
        self.scenarioName = scenarioName
        self.suggestedActions = suggestedActions
        self.stability = stability
        self.startDate = startDate
        self.timeline = timeline
        self.worldTension = worldTension
        self.worldEffects = worldEffects
    }

    private enum CodingKeys: String, CodingKey {
        case advisorMessages
        case aiReadiness
        case country
        case diplomaticThreads
        case gameDate
        case lastSummary
        case language
        case plannedActions
        case round
        case scenarioDescription
        case scenarioID
        case scenarioName
        case suggestedActions
        case stability
        case startDate
        case timeline
        case worldTension
        case worldEffects
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        advisorMessages = (try? container.decodeIfPresent([NativeAdvisorMessage].self, forKey: .advisorMessages)) ?? []
        aiReadiness = (try? container.decodeIfPresent(NativeAIReadiness.self, forKey: .aiReadiness)) ?? .notChecked
        country = try container.decode(PlayerCountry.self, forKey: .country)
        diplomaticThreads = (try? container.decodeIfPresent([NativeDiplomaticThread].self, forKey: .diplomaticThreads)) ?? []
        scenarioID = (try? container.decodeIfPresent(String.self, forKey: .scenarioID)) ?? NativeScenarioCatalog.defaultScenario.id
        let decodedScenario = NativeScenarioCatalog.scenario(for: scenarioID)
        gameDate = (try? container.decodeIfPresent(String.self, forKey: .gameDate)) ?? decodedScenario.gameDate
        lastSummary = (try? container.decodeIfPresent(String.self, forKey: .lastSummary)) ?? "\(decodedScenario.openingSummary) \(country.name) needs to turn intent into concrete plans."
        language = NativeGameLanguage.normalized(try? container.decodeIfPresent(String.self, forKey: .language))
        plannedActions = (try? container.decodeIfPresent([NativePlannedAction].self, forKey: .plannedActions)) ?? []
        round = (try? container.decodeIfPresent(Int.self, forKey: .round)) ?? 1
        scenarioName = (try? container.decodeIfPresent(String.self, forKey: .scenarioName)) ?? decodedScenario.name
        scenarioDescription = (try? container.decodeIfPresent(String.self, forKey: .scenarioDescription)) ?? decodedScenario.heroSubtitle
        suggestedActions = (try? container.decodeIfPresent([NativeSuggestedAction].self, forKey: .suggestedActions)) ?? []
        stability = (try? container.decodeIfPresent(Int.self, forKey: .stability)) ?? decodedScenario.baseStability
        startDate = (try? container.decodeIfPresent(String.self, forKey: .startDate)) ?? decodedScenario.startDate
        timeline = (try? container.decodeIfPresent([NativeCampaignEvent].self, forKey: .timeline)) ?? []
        worldTension = (try? container.decodeIfPresent(Int.self, forKey: .worldTension)) ?? decodedScenario.baseWorldTension
        worldEffects = (try? container.decodeIfPresent([NativeStrategicEffect].self, forKey: .worldEffects)) ?? []
    }
}

enum NativeGameLanguage: String, Codable, CaseIterable, Hashable, Identifiable {
    case english = "English"
    case portuguese = "Portuguese"
    case spanish = "Spanish"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .english:
            return "English"
        case .portuguese:
            return "Português"
        case .spanish:
            return "Español"
        }
    }

    var responseLanguageName: String {
        switch self {
        case .english:
            return "English"
        case .portuguese:
            return "Portuguese (Brazilian Portuguese)"
        case .spanish:
            return "Spanish"
        }
    }

    var promptInstruction: String {
        "Response language: \(responseLanguageName). Write all player-facing prose in \(responseLanguageName). Keep schema field names, enum values, identifiers, IDs, dates, and game tokens exactly as requested."
    }

    static func normalized(_ value: String?) -> NativeGameLanguage {
        let raw = sanitizeFoundationModelText(value ?? "")
        let folded = raw
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
            .replacingOccurrences(of: "(", with: " ")
            .replacingOccurrences(of: ")", with: " ")
        let key = folded.split(separator: " ").joined(separator: " ")

        switch key {
        case "en", "english", "ingles":
            return .english
        case "pt", "pt-br", "portugues", "portuguese", "portugues brasil", "portugues brasileiro", "portuguese brazilian", "brazilian portuguese":
            return .portuguese
        case "es", "espanhol", "espanol", "spanish", "castellano":
            return .spanish
        default:
            return .english
        }
    }
}

struct NativeScenario: Codable, Hashable, Identifiable {
    var accentColor: String
    var baseStability: Int
    var baseWorldTension: Int
    var gameDate: String
    var heroSubtitle: String
    var heroTitle: String
    var id: String
    var name: String
    var openingSummary: String
    var startDate: String
    var subtitle: String
}

enum NativeScenarioCatalog {
    static let defaultScenario = NativeScenario(
        accentColor: "#c49a35",
        baseStability: 62,
        baseWorldTension: 48,
        gameDate: "2030-09-15",
        heroSubtitle: "Modern institutions, brittle supply chains, and fast-moving regional bargains.",
        heroTitle: "Modern Day",
        id: "default",
        name: "Modern Day",
        openingSummary: "The modern-day campaign begins with every council watching markets, services, and diplomatic room for maneuver.",
        startDate: "2025-03-25",
        subtitle: "Bundled save0 configuration"
    )

    static let fragmentedMarkets = NativeScenario(
        accentColor: "#4f9f8f",
        baseStability: 54,
        baseWorldTension: 66,
        gameDate: "2032-04-01",
        heroSubtitle: "Regional blocs, volatile trade corridors, and hard budget choices define the opening.",
        heroTitle: "Fragmented Markets",
        id: "fragmented-markets",
        name: "Fragmented Markets",
        openingSummary: "A fractured market order forces the player to convert scarce administrative capacity into trust, access, and leverage.",
        startDate: "2031-01-01",
        subtitle: "Trade friction and coalition management"
    )

    static let resilienceDecade = NativeScenario(
        accentColor: "#5d8fd8",
        baseStability: 70,
        baseWorldTension: 38,
        gameDate: "2040-01-10",
        heroSubtitle: "Adaptation finance, energy reliability, and public-service legitimacy shape a slower strategic game.",
        heroTitle: "Resilience Decade",
        id: "resilience-decade",
        name: "Resilience Decade",
        openingSummary: "The resilience decade rewards patient institution-building, credible delivery, and alliances that can survive stress.",
        startDate: "2038-06-01",
        subtitle: "Long-horizon civic strategy"
    )

    static let all: [NativeScenario] = [
        defaultScenario,
        fragmentedMarkets,
        resilienceDecade,
    ]

    static func scenario(for id: String?) -> NativeScenario {
        let normalized = sanitizeFoundationModelText(id ?? "")
        return all.first { $0.id == normalized } ?? defaultScenario
    }
}

struct NativeAdvisorMessage: Codable, Hashable, Identifiable {
    var date: String
    var id: String
    var role: NativeAdvisorRole
    var text: String
}

enum NativeAdvisorRole: String, Codable, Hashable {
    case advisor
    case leader
}

struct NativeDiplomaticThread: Codable, Hashable, Identifiable {
    var id: String
    var lastUpdated: String
    var messages: [NativeDiplomaticMessage]
    var participant: PlayerCountry
    var summary: String
}

struct NativeDiplomaticMessage: Codable, Hashable, Identifiable {
    var date: String
    var id: String
    var speaker: String
    var text: String
}

struct NativePlannedAction: Codable, Hashable, Identifiable {
    var createdAt: String
    var detail: String
    var id: String
    var resolvedAt: String?
    var status: NativeActionStatus
    var title: String
}

enum NativeActionStatus: String, Codable, Hashable {
    case planned
    case resolved
}

struct NativeSuggestedAction: Codable, Hashable, Identifiable {
    var detail: String
    var id: String
    var rationale: String
    var title: String
    var urgency: String
}

struct NativeCampaignEvent: Codable, Hashable, Identifiable {
    var date: String
    var description: String
    var id: String
    var importance: NativeEventImportance
    var kind: NativeEventKind
    var linkedActionIDs: [String]
    var notable: Bool
    var playerRelated: Bool
    var strategicEffects: [NativeStrategicEffect]
    var title: String
}

enum NativeEventKind: String, Codable, Hashable {
    case action
    case crisis
    case diplomacy
    case economy
    case world
}

enum NativeEventImportance: String, Codable, Hashable {
    case minor
    case major
    case severe
}

struct NativeStrategicEffect: Codable, Hashable, Identifiable {
    var date: String
    var eventId: String
    var id: String
    var magnitude: Int
    var summary: String
    var target: String
    var track: NativeStrategicTrack
}

enum NativeStrategicTrack: String, Codable, CaseIterable, Hashable, Identifiable {
    case diplomaticLeverage = "diplomatic-leverage"
    case economicResilience = "economic-resilience"
    case internalStability = "internal-stability"
    case marketConfidence = "market-confidence"
    case militaryReadiness = "military-readiness"
    case securityAnxiety = "security-anxiety"
    case worldTension = "world-tension"

    var id: String { rawValue }
}

struct NativeAIReadiness: Codable, Hashable {
    var availability: String
    var checkedAt: String
    var lastError: String
    var ok: Bool
    var recoverySuggestion: String
    var tokenBudget: String

    static let notChecked = NativeAIReadiness(
        availability: "not-checked",
        checkedAt: "",
        lastError: "",
        ok: false,
        recoverySuggestion: "",
        tokenBudget: ""
    )

    init(
        availability: String,
        checkedAt: String,
        lastError: String,
        ok: Bool,
        recoverySuggestion: String,
        tokenBudget: String
    ) {
        self.availability = availability
        self.checkedAt = checkedAt
        self.lastError = lastError
        self.ok = ok
        self.recoverySuggestion = recoverySuggestion
        self.tokenBudget = tokenBudget
    }

    static func available(tokenBudget: String) -> NativeAIReadiness {
        NativeAIReadiness(
            availability: "available",
            checkedAt: NativeGameEngine.todayStamp(),
            lastError: "",
            ok: true,
            recoverySuggestion: "",
            tokenBudget: tokenBudget
        )
    }

    static func failure(_ error: Error) -> NativeAIReadiness {
        NativeAIReadiness(
            availability: failureAvailability(for: error),
            checkedAt: NativeGameEngine.todayStamp(),
            lastError: error.localizedDescription,
            ok: false,
            recoverySuggestion: recoverySuggestion(for: error),
            tokenBudget: "context=4096"
        )
    }

    static func suggestionFailure(_ error: Error) -> NativeAIReadiness {
        NativeAIReadiness(
            availability: failureAvailability(for: error),
            checkedAt: NativeGameEngine.todayStamp(),
            lastError: error.localizedDescription,
            ok: false,
            recoverySuggestion: "Suggested actions could not be refreshed safely. Keep drafting manual civic proposals and retry when Apple Foundation Models are ready.",
            tokenBudget: "context=4096, suggestions=4x180"
        )
    }

    static func unavailable(_ reason: String) -> NativeAIReadiness {
        NativeAIReadiness(
            availability: reason,
            checkedAt: NativeGameEngine.todayStamp(),
            lastError: reason,
            ok: false,
            recoverySuggestion: "Enable Apple Intelligence and make sure the local model is ready. SwiftHistoria will not simulate turns without Apple Foundation Models.",
            tokenBudget: "context=4096"
        )
    }

    static func modelUnavailable(_ reason: String) -> NativeAIReadiness {
        NativeAIReadiness(
            availability: availabilityCode(for: reason),
            checkedAt: NativeGameEngine.todayStamp(),
            lastError: reason,
            ok: false,
            recoverySuggestion: "Enable Apple Intelligence and make sure the local model is ready. SwiftHistoria will not simulate turns without Apple Foundation Models.",
            tokenBudget: "context=4096"
        )
    }

    private static func failureAvailability(for error: Error) -> String {
        guard let foundationError = error as? NativeFoundationModelError else {
            return "apple-foundation-error"
        }

        switch foundationError {
        case .unsupportedOS:
            return "unsupported-os"
        case .modelUnavailable(let reason):
            return availabilityCode(for: reason)
        case .generationFailed, .invalidGeneratedTurn, .invalidSuggestedActions:
            return "apple-foundation-error"
        }
    }

    private static func recoverySuggestion(for error: Error) -> String {
        guard let foundationError = error as? NativeFoundationModelError else {
            return "Apple Foundation Models did not complete this request. The game kept the current turn unchanged; add manual civic proposals and retry when the model is ready."
        }

        switch foundationError {
        case .unsupportedOS:
            return "Run SwiftHistoria on an OS that exposes FoundationModels. The current campaign remains editable, but AI turns are paused."
        case .modelUnavailable:
            return "Enable Apple Intelligence and wait for the local model to finish preparing. Manual civic proposals remain available."
        case .generationFailed, .invalidGeneratedTurn, .invalidSuggestedActions:
            return "The model response could not be repaired safely. The campaign was not advanced; revise the proposal as civic planning and retry."
        }
    }

    private static func availabilityCode(for reason: String) -> String {
        let normalized = reason.lowercased()
        if normalized.contains("appleintelligencenotenabled") ||
            normalized.contains("not enabled") {
            return "apple-intelligence-not-enabled"
        }

        return "model-not-ready"
    }
}

enum NativeFoundationModelError: LocalizedError {
    case unsupportedOS
    case modelUnavailable(String)
    case generationFailed(String)
    case invalidGeneratedTurn(String)
    case invalidSuggestedActions(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedOS:
            return "This OS does not expose the FoundationModels framework required by the native game."
        case .modelUnavailable(let reason):
            return "Apple Foundation Models are unavailable: \(reason)."
        case .generationFailed(let reason):
            return "Apple Foundation Models generation failed: \(reason)."
        case .invalidGeneratedTurn(let reason):
            return "Apple Foundation Models returned an invalid turn: \(reason)."
        case .invalidSuggestedActions(let reason):
            return "Apple Foundation Models returned invalid suggested actions: \(reason)."
        }
    }
}

func sanitizeFoundationModelText(_ value: String) -> String {
    var result = value.trimmingCharacters(in: .whitespacesAndNewlines)
    let replacements: [(String, String)] = [
        ("World Trade Organization", "External Trade Forum"),
        ("United Nations", "Global Coordination Forum"),
        ("World Bank", "Development Finance Forum"),
        ("International Monetary Fund", "Stability Finance Forum"),
        ("Port Rio Grande", "Port Delta"),
        ("Rio Verde", "Valley District"),
        ("Serra Verde", "Highland District"),
        ("Rio de Janeiro", "Metro A"),
        ("São Paulo", "Metro B"),
        ("Sao Paulo", "Metro B"),
        ("government", "regional council"),
        ("Government", "Regional council"),
        ("public health", "community services"),
        ("Public health", "Community services"),
        ("Public Health", "Community Services"),
        ("healthcare", "community services"),
        ("Healthcare", "Community services"),
        ("health", "community services"),
        ("Health", "Community services"),
        ("medical", "service"),
        ("Medical", "Service"),
        ("clinic", "service center"),
        ("Clinic", "Service center"),
        ("emergency", "contingency"),
        ("Emergency", "Contingency"),
        ("mortality", "service delays"),
        ("Mortality", "Service delays"),
        ("death", "service loss"),
        ("Death", "Service loss"),
        ("crisis", "constraint"),
        ("Crisis", "Constraint"),
        ("conflict", "friction"),
        ("Conflict", "Friction"),
        ("security", "resilience"),
        ("Security", "Resilience"),
        ("weapons", "tools"),
        ("Weapons", "Tools"),
        ("weapon", "tool"),
        ("Weapon", "Tool"),
        ("missile", "long-range asset"),
        ("Missile", "Long-range asset"),
        ("bomb", "hazard"),
        ("Bomb", "Hazard"),
        ("cy" + "berattack", "digital disruption"),
        ("Cy" + "berattack", "Digital disruption"),
        ("attack", "pressure event"),
        ("Attack", "Pressure event"),
        ("invasion", "border pressure"),
        ("Invasion", "Border pressure"),
        ("troop", "logistics unit"),
        ("Troop", "Logistics unit"),
        ("troops", "logistics units"),
        ("Troops", "Logistics units"),
        ("military", "logistics"),
        ("Military", "Logistics"),
        ("surveillance", "oversight"),
        ("Surveillance", "Oversight"),
        ("coercion", "pressure"),
        ("Coercion", "Pressure"),
        ("cy" + "ber", "digital"),
        ("Cy" + "ber", "Digital"),
        ("intelligence", "analysis"),
        ("Intelligence", "Analysis"),
        ("market-confidence drops", "market-confidence volatility"),
        ("Market-confidence drops", "Market-confidence volatility"),
        ("market confidence drops", "market confidence volatility"),
        ("Market confidence drops", "Market confidence volatility"),
        ("market-confidence drop", "market-confidence volatility"),
        ("Market-confidence drop", "Market-confidence volatility"),
        ("market confidence drop", "market confidence volatility"),
        ("Market confidence drop", "Market confidence volatility"),
        ("community services services", "community services"),
        ("Community services Services", "Community Services"),
        ("community services service center", "community service center"),
        ("Community services service center", "Community service center"),
    ]

    for (needle, replacement) in replacements {
        result = result.replacingOccurrences(of: needle, with: replacement)
    }
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

func hasConcreteFoundationText(_ value: String, minimumWords: Int) -> Bool {
    let sanitized = sanitizeFoundationModelText(value)
    return !containsFoundationPlaceholderText(sanitized) &&
        sanitized.split(separator: " ").count >= minimumWords
}

func normalizedFoundationUrgency(_ value: String) -> String {
    switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "immediate", "soon", "opportunistic":
        return value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    default:
        return "soon"
    }
}

func foundationPromptTrackLabel(_ track: NativeStrategicTrack) -> String {
    switch track {
    case .diplomaticLeverage:
        return "regional-relations"
    case .economicResilience:
        return "economic-resilience"
    case .internalStability:
        return "internal-stability"
    case .marketConfidence:
        return "market-confidence"
    case .militaryReadiness:
        return "logistics-readiness"
    case .securityAnxiety:
        return "resilience-pressure"
    case .worldTension:
        return "global-friction"
    }
}

func foundationVisibleTrack(_ track: NativeStrategicTrack) -> NativeStrategicTrack {
    switch track {
    case .militaryReadiness:
        return .economicResilience
    case .securityAnxiety:
        return .worldTension
    default:
        return track
    }
}

func containsFoundationPlaceholderText(_ value: String) -> Bool {
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
        "tbd",
    ]
    return blockedFragments.contains { normalized.contains($0) }
}

enum NativeGameEngineError: LocalizedError {
    case invalidTurn(String)

    var errorDescription: String? {
        switch self {
        case .invalidTurn(let reason):
            return "The generated turn could not be applied: \(reason)."
        }
    }
}

struct NativeGeneratedTurn: Codable, Hashable {
    var events: [NativeCampaignEvent]
    var stabilityDelta: Int
    var summary: String
    var worldTensionDelta: Int
}
