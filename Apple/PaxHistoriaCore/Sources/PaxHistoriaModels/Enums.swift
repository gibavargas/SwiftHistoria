import Foundation

public enum NativeGameMode: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case sandbox = "Sandbox"
    case normal = "Normal"
    case ironman = "Iron Man"

    public var id: String {
        rawValue
    }

    public var description: String {
        switch self {
        case .sandbox: String(localized: "Unlimited administrative freedom and light consequences.")
        case .normal: String(localized: "Standard campaign conditions with active crisis events.")
        case .ironman: String(localized: "Sovereign risks are doubled, and reloading is disabled.")
        }
    }
}

public enum NativeTerrainType: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case ocean
    case strait
    case sea
    case city
    case forest
    case cerrado
    case swamp
    case mountain
    case plains

    public var id: String {
        rawValue
    }

    public var displayName: String {
        switch self {
        case .ocean: String(localized: "Ocean")
        case .strait: String(localized: "Strait")
        case .sea: String(localized: "Sea")
        case .city: String(localized: "City")
        case .forest: String(localized: "Forest")
        case .cerrado: String(localized: "Cerrado")
        case .swamp: String(localized: "Swamp")
        case .mountain: String(localized: "Mountain")
        case .plains: String(localized: "Plains")
        }
    }
}

public enum NativeRegionConflictMode: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case contestedBorder = "contested-border"
    case conventionalOccupation = "conventional-occupation"
    case guerrillaControl = "guerrilla-control"
    case nuclearFallout = "nuclear-fallout"
    case stabilization

    public var id: String {
        rawValue
    }

    public var displayName: String {
        switch self {
        case .contestedBorder:
            String(localized: "Contested border")
        case .conventionalOccupation:
            String(localized: "Conventional occupation")
        case .guerrillaControl:
            String(localized: "Guerrilla control")
        case .nuclearFallout:
            String(localized: "Nuclear fallout")
        case .stabilization:
            String(localized: "Stabilization corridor")
        }
    }
}

public enum NativeAIDoctrine: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case mercantile
    case expansionist
    case isolationist
    case defensive
    case collaborative

    public var id: String {
        rawValue
    }

    public var displayName: String {
        switch self {
        case .mercantile: String(localized: "Mercantile")
        case .expansionist: String(localized: "Expansionist")
        case .isolationist: String(localized: "Isolationist")
        case .defensive: String(localized: "Defensive")
        case .collaborative: String(localized: "Collaborative")
        }
    }
}

public enum NativeAIBudgetPriority: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case growth
    case stability
    case military
    case diplomacy

    public var id: String {
        rawValue
    }
}

public enum NativeSovereigntyChangeKind: String, Codable, Hashable, Sendable {
    case dissolution
    case merge
    case newCountry = "new-country"
    case secession
}

public enum NativeGameLanguage: String, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    case english = "English"
    case portuguese = "Portuguese"
    case spanish = "Spanish"

    public var id: String {
        rawValue
    }

    public var label: String {
        switch self {
        case .english:
            "English"
        case .portuguese:
            "Português"
        case .spanish:
            "Español"
        }
    }

    public var responseLanguageName: String {
        switch self {
        case .english:
            "English"
        case .portuguese:
            "Portuguese (Brazilian Portuguese)"
        case .spanish:
            "Spanish"
        }
    }

    public var promptInstruction: String {
        "Response language: \(responseLanguageName). Write all player-facing prose in \(responseLanguageName). Keep schema field names, enum values, identifiers, IDs, dates, and game tokens exactly as requested."
    }

    public static func normalized(_ value: String?) -> NativeGameLanguage {
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

public enum NativeAdvisorRole: String, Codable, Hashable, Sendable {
    case advisor
    case leader
}

public enum NativeActionStatus: String, Codable, Hashable, Sendable {
    case planned
    case resolved
}

public enum NativeVictoryStatus: String, Codable, Hashable, Sendable {
    case ongoing
    case won
    case lostCollapse = "lost-collapse"
    case lostTimeout = "lost-timeout"
}

public enum NativeOfferType: String, Codable, Hashable, Sendable {
    case tradeAgreement = "trade-agreement"
    case militaryAlliance = "military-alliance"
    case nonAggressionPact = "non-aggression"
    case territoryDemarcation = "border-deal"

    public var displayName: String {
        switch self {
        case .tradeAgreement: String(localized: "Trade Agreement")
        case .militaryAlliance: String(localized: "Military Alliance")
        case .nonAggressionPact: String(localized: "Non-Aggression Pact")
        case .territoryDemarcation: String(localized: "Territory Demarcation")
        }
    }
}

public enum NativeOfferStatus: String, Codable, Hashable, Sendable {
    case pending
    case accepted
    case rejected
    case countered
}

public enum NativeObligationType: String, Codable, CaseIterable, Hashable, Sendable {
    case nonAggression = "non-aggression"
    case mutualDefense = "mutual-defense"
    case tradeCooperation = "trade-cooperation"
    case demilitarization
    case financialSubsidy = "financial-subsidy"
}

public enum NativeEventKind: String, Codable, Hashable, Sendable {
    case action
    case crisis
    case diplomacy
    case economy
    case world

    public var displayName: String {
        switch self {
        case .action: String(localized: "Nation Policy")
        case .crisis: String(localized: "Crisis Action")
        case .diplomacy: String(localized: "Diplomacy")
        case .economy: String(localized: "Economic Event")
        case .world: String(localized: "Global Event")
        }
    }
}

public enum NativeEventImportance: String, Codable, Hashable, Sendable {
    case minor
    case major
    case severe
}

public enum NativeStrategicTrack: String, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    case diplomaticLeverage = "diplomatic-leverage"
    case economicResilience = "economic-resilience"
    case internalStability = "internal-stability"
    case marketConfidence = "market-confidence"
    case militaryReadiness = "military-readiness"
    case securityAnxiety = "security-anxiety"
    case worldTension = "world-tension"

    public var id: String {
        rawValue
    }

    public var displayName: String {
        switch self {
        case .diplomaticLeverage: String(localized: "Diplomatic Leverage")
        case .economicResilience: String(localized: "Economic Resilience")
        case .internalStability: String(localized: "Internal Stability")
        case .marketConfidence: String(localized: "Market Confidence")
        case .militaryReadiness: String(localized: "Military Readiness")
        case .securityAnxiety: String(localized: "Security Anxiety")
        case .worldTension: String(localized: "World Tension")
        }
    }
}

public enum NativeFoundationTurnLane: String, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    case external
    case economy
    case budget
    case domestic
    case actionConsequence
    case summary

    public var id: String {
        rawValue
    }

    public var title: String {
        switch self {
        case .external: String(localized: "External facts")
        case .economy: String(localized: "Economic model")
        case .budget: String(localized: "Budget balance")
        case .domestic: String(localized: "Domestic response")
        case .actionConsequence: String(localized: "Action consequence")
        case .summary: String(localized: "Turn synthesis")
        }
    }
}

public enum NativeGameEngineError: LocalizedError, Sendable {
    case invalidTurn(String)

    public var errorDescription: String? {
        switch self {
        case let .invalidTurn(reason):
            String(localized: "The generated turn could not be applied: \(reason).")
        }
    }
}
