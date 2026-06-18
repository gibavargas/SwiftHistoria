import Foundation
import PaxHistoriaModels

public protocol NativeGameEngineInterface {
    static func initialState(for country: PlayerCountry, scenario: NativeScenario, language: NativeGameLanguage) -> NativeCampaignState
    static func validated(_ turn: NativeGeneratedTurn, state: NativeCampaignState, months: Int) throws -> NativeGeneratedTurn
    static func apply(_ turn: NativeGeneratedTurn, state: NativeCampaignState, months: Int) -> NativeCampaignState
}

public enum NativeGameEngine: NativeGameEngineInterface {
    public nonisolated(unsafe) static var force512DiceFrictionForTesting = false

    public static let displayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    public static func initialState(
        for country: PlayerCountry,
        scenario: NativeScenario = NativeScenarioCatalog.defaultScenario,
        language: NativeGameLanguage = .english
    ) -> NativeCampaignState {
        let openingStability = Native2010WorldModel.stability(for: country, scenario: scenario)
        let openingWorldTension = Native2010WorldModel.worldTension(for: country, scenario: scenario)

        return NativeCampaignState(
            actionMemory: [],
            aiReadiness: .notChecked,
            country: country,
            economicLedger: NativeEconomicLedger.starting(for: country, scenario: scenario),
            economicLedgers: nil,
            aiCountryStates: NativeAICountryState.initialAICountryStates(for: scenario.id, strategicCountryCodes: NativeCampaignState.defaultStrategicCountryCodes),
            gameDate: scenario.gameDate,
            lastSummary: openingSummary(for: country, scenario: scenario, language: language),
            language: language,
            plannedActions: [],
            round: 1,
            scenarioDescription: scenario.heroSubtitle,
            scenarioID: scenario.id,
            scenarioName: scenario.name,
            suggestedActions: [],
            stability: openingStability,
            startDate: scenario.startDate,
            timeline: [
                NativeCampaignEvent(
                    date: scenario.gameDate,
                    description: openingDescription(for: country, scenario: scenario, language: language),
                    id: "opening-\(scenario.id)-\(country.code.lowercased())",
                    importance: .major,
                    kind: .world,
                    linkedActionIDs: [],
                    notable: true,
                    playerRelated: true,
                    strategicEffects: [
                        NativeStrategicEffect(
                            date: scenario.gameDate,
                            eventId: "opening-\(scenario.id)-\(country.code.lowercased())",
                            id: "opening-\(scenario.id)-\(country.code.lowercased())-stability",
                            magnitude: 1,
                            summary: openingEffectSummary(for: scenario, language: language),
                            target: country.name,
                            track: .internalStability
                        )
                    ],
                    title: openingTitle(for: country, scenario: scenario, language: language)
                )
            ],
            worldTension: openingWorldTension,
            worldEffects: []
        )
    }

    public static func estimateDirectiveCount(in text: String) -> Int {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }

        var normalized = trimmed.replacingOccurrences(of: ";", with: "|")
            .replacingOccurrences(of: "\n", with: "|")
            .replacingOccurrences(of: "!", with: "|")
            .replacingOccurrences(of: "?", with: "|")
            .replacingOccurrences(of: ".", with: "|")

        let transitionWords = [
            " and ", " e ", " y ",
            " then ", " then, ", " então ", " entonces ",
            " also ", " também ", " también ",
            " plus ", " mais ", " más ",
            " additionally ", " adicionalmente ", " além disso ", " además ",
            " as well as ", " bem como ", " así como "
        ]

        for word in transitionWords {
            var searchRange = normalized.startIndex ..< normalized.endIndex
            while let range = normalized.range(of: word, options: .caseInsensitive, range: searchRange) {
                normalized.replaceSubrange(range, with: "|")
                searchRange = normalized.startIndex ..< normalized.endIndex
            }
        }

        let segments = normalized.components(separatedBy: "|")
        var count = 0
        for segment in segments {
            let segTrimmed = segment.trimmingCharacters(in: .whitespacesAndNewlines)
            if segTrimmed.count >= 4 {
                count += 1
            }
        }

        return max(1, count)
    }

    public static func estimateDirectiveCost(for text: String) -> Int {
        if text.hasPrefix("Invade ") {
            return 40
        }
        return estimateDirectiveCount(in: text) * 30
    }

    public static func action(from text: String, date: String) -> NativePlannedAction? {
        let trimmed = sanitizeFoundationModelText(text)
        guard !trimmed.isEmpty else { return nil }

        let title = trimmed
            .components(separatedBy: CharacterSet(charactersIn: ".\n"))
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(72) ?? Substring(trimmed.prefix(72))

        return NativePlannedAction(
            createdAt: date,
            detail: trimmed,
            id: "action-\(UUID().uuidString.lowercased())",
            resolvedAt: nil,
            status: .planned,
            title: String(title)
        )
    }

    public static func advance(date: String, months: Int) -> String {
        guard let value = displayFormatter.date(from: date) else { return date }
        let next = Calendar(identifier: .gregorian).date(byAdding: .month, value: months, to: value) ?? value
        return displayFormatter.string(from: next)
    }

    public static func isValidDate(_ value: String) -> Bool {
        displayFormatter.date(from: value) != nil
    }

    public static func clampedMetric(_ value: Int) -> Int {
        clamp(value)
    }

    public static func todayStamp() -> String {
        ISO8601DateFormatter().string(from: Date())
    }

    static func clamp(_ value: Int) -> Int {
        max(0, min(100, value))
    }

    private static func openingSummary(
        for country: PlayerCountry,
        scenario: NativeScenario,
        language: NativeGameLanguage
    ) -> String {
        if Native2010WorldModel.isReal2010Scenario(scenario) {
            return Native2010WorldModel.openingSummary(for: country, language: language)
        }

        switch language {
        case .english:
            return "\(scenario.openingSummary) \(country.name) needs to turn intent into concrete plans."
        case .portuguese:
            return "A campanha \(scenario.name) começa com \(country.name) avaliando mercados, serviços e margem diplomática. Transforme intenção em planos concretos."
        case .spanish:
            return "La campaña \(scenario.name) comienza con \(country.name) evaluando mercados, servicios y margen diplomático. Convierte la intención en planes concretos."
        }
    }

    private static func openingDescription(
        for country: PlayerCountry,
        scenario: NativeScenario,
        language: NativeGameLanguage
    ) -> String {
        if Native2010WorldModel.isReal2010Scenario(scenario) {
            return Native2010WorldModel.openingEventDescription(for: country, language: language)
        }

        switch language {
        case .english:
            return "\(scenario.heroTitle) begins as a playable scenario. The first important decision is choosing priorities, not reacting to noise."
        case .portuguese:
            return "\(scenario.heroTitle) começa como um cenário jogável. A primeira decisão importante é escolher prioridades, não reagir ao ruído."
        case .spanish:
            return "\(scenario.heroTitle) empieza como un escenario jugable. La primera decisión importante es elegir prioridades, no reaccionar al ruido."
        }
    }

    private static func openingEffectSummary(for scenario: NativeScenario, language: NativeGameLanguage) -> String {
        if Native2010WorldModel.isReal2010Scenario(scenario) {
            return Native2010WorldModel.openingEffectSummary(for: language)
        }

        switch language {
        case .english:
            return "An orderly transition gives the player a small opening margin."
        case .portuguese:
            return "Uma transição ordenada dá ao jogador uma pequena margem inicial."
        case .spanish:
            return "Una transición ordenada da al jugador un pequeño margen inicial."
        }
    }

    private static func openingTitle(for country: PlayerCountry, scenario: NativeScenario, language: NativeGameLanguage) -> String {
        if Native2010WorldModel.isReal2010Scenario(scenario) {
            return Native2010WorldModel.openingEventTitle(for: country, language: language)
        }

        switch language {
        case .english:
            return "\(country.name) opens the planning table"
        case .portuguese:
            return "\(country.name) abre a mesa de planejamento"
        case .spanish:
            return "\(country.name) abre la mesa de planificación"
        }
    }
}
