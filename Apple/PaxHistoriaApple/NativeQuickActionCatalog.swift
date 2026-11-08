import Foundation

/// A button-driven templated action. Reuses the proven invasion pattern:
/// setting `store.draftAction` to a templated title, then `store.addDraftAction()`.
enum NativeQuickActionCategory: String, CaseIterable, Identifiable {
    case economy
    case diplomacy
    case military
    case infrastructure
    case welfare
    case regional
    case political

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .economy: "Economy"
        case .diplomacy: "Diplomacy"
        case .military: "Military"
        case .infrastructure: "Infrastructure"
        case .welfare: "Welfare"
        case .regional: "Regional"
        case .political: "Political Reforms"
        }
    }

    var systemImage: String {
        switch self {
        case .economy: "chart.bar.xaxis"
        case .diplomacy: "bubble.left.and.bubble.right"
        case .military: "shield"
        case .infrastructure: "hammer"
        case .welfare: "heart.text.square"
        case .regional: "map"
        case .political: "building.columns"
        }
    }
}

struct NativeQuickAction: Identifiable {
    let cooldownTurns: Int?
    let cost: Int
    let id: String
    let category: NativeQuickActionCategory
    let title: String
    let directiveTemplate: String
    let hint: String
    let primaryEffects: [String]
    /// Probability (0–1) that this action succeeds when resolved.
    /// Modulated at resolution time by stability and budget sliders.
    let successChance: Double

    init(
        id: String,
        category: NativeQuickActionCategory,
        title: String,
        directiveTemplate: String,
        hint: String,
        cost: Int,
        primaryEffects: [String],
        cooldownTurns: Int? = nil,
        successChance: Double = 1.0
    ) {
        self.cooldownTurns = cooldownTurns
        self.cost = cost
        self.id = id
        self.category = category
        self.title = title
        self.directiveTemplate = directiveTemplate
        self.hint = hint
        self.primaryEffects = primaryEffects
        self.successChance = max(0.0, min(1.0, successChance))
    }
}

enum NativeQuickActionCatalog {
    static let actions: [NativeQuickAction] = [
        // MARK: — Economy

        .init(id: "econ-subsidy", category: .economy,
              title: "Boost agriculture subsidies",
              directiveTemplate: "Increase agricultural subsidies to raise market confidence.",
              hint: "Costs 20 capacity. Raises Market Confidence. 90% success.",
              cost: 20,
              primaryEffects: ["Market Confidence +", "Budget pressure +"],
              successChance: 0.90),
        .init(id: "econ-sanction", category: .economy,
              title: "Impose trade sanctions",
              directiveTemplate: "Impose targeted trade sanctions on a rival economy.",
              hint: "Costs 30 capacity. Lowers a rival's Economic Resilience. 65% success — rival may retaliate.",
              cost: 30,
              primaryEffects: ["Rival Economic Resilience -", "World Tension +"],
              successChance: 0.65),

        // MARK: — Infrastructure

        .init(id: "infra-grid", category: .infrastructure,
              title: "Modernize power grid",
              directiveTemplate: "Fund power-grid modernization for long-term resilience.",
              hint: "Costs 40 capacity. Slow Internal Stability gain. 80% success.",
              cost: 40,
              primaryEffects: ["Economic Resilience +", "Internal Stability +"],
              cooldownTurns: 2,
              successChance: 0.80),

        // MARK: — Welfare

        .init(id: "welfare-health", category: .welfare,
              title: "Expand healthcare access",
              directiveTemplate: "Expand public healthcare access to improve stability.",
              hint: "Costs 25 capacity. Raises Internal Stability. 85% success.",
              cost: 25,
              primaryEffects: ["Internal Stability +", "Unrest risk -"],
              successChance: 0.85),

        // MARK: — Military

        .init(id: "mil-readiness", category: .military,
              title: "Raise military readiness",
              directiveTemplate: "Raise national military readiness and reserve activation.",
              hint: "Costs 35 capacity. Raises Military Readiness, may spike World Tension. 75% success.",
              cost: 35,
              primaryEffects: ["Military Readiness +", "World Tension +"],
              successChance: 0.75),

        // MARK: — Diplomacy

        .init(id: "dip-trade", category: .diplomacy,
              title: "Propose trade agreement",
              directiveTemplate: "Propose a bilateral trade agreement to deepen ties.",
              hint: "Costs 15 capacity. Best paired with the Diplomacy tab. 70% success.",
              cost: 15,
              primaryEffects: ["Diplomatic Leverage +", "Trade Balance +"],
              successChance: 0.70),

        // MARK: — Political Reforms

        .init(id: "pol-snap-election", category: .political,
              title: "Call snap elections",
              directiveTemplate: "Call snap elections to renew democratic mandate.",
              hint: "Costs 30 capacity. Resets election cycle early. Requires democracy or hybrid. 80% success.",
              cost: 30,
              primaryEffects: ["Election cycle reset", "Public Approval reset"],
              successChance: 0.80),
        .init(id: "pol-liberalize", category: .political,
              title: "Liberalize toward democracy",
              directiveTemplate: "Liberalize the political system toward democratic governance.",
              hint: "Costs 50 capacity. Moves autocracy/hybrid → democracy. 50% success — hardliners may block.",
              cost: 50,
              primaryEffects: ["Government Type →  democracy", "Stability +", "World Tension -"],
              successChance: 0.50),
        .init(id: "pol-consolidate", category: .political,
              title: "Consolidate executive power",
              directiveTemplate: "Consolidate executive power and reduce legislative oversight.",
              hint: "Costs 45 capacity. Moves democracy/hybrid → hybrid. 55% success — democratic opposition may resist.",
              cost: 45,
              primaryEffects: ["Government Type → hybrid", "Internal Stability ±"],
              successChance: 0.55),
        .init(id: "pol-suspend-constitution", category: .political,
              title: "Suspend constitutional limits",
              directiveTemplate: "Suspend constitutional constraints and consolidate full executive authority.",
              hint: "Costs 60 capacity. Moves any regime → autocracy. 40% success — very high risk of crisis.",
              cost: 60,
              primaryEffects: ["Government Type → autocracy", "Stability risk", "Diplomatic cost"],
              successChance: 0.40),
        .init(id: "pol-electoral-reform", category: .political,
              title: "Reform electoral system",
              directiveTemplate: "Reform the electoral system to modernize democratic institutions.",
              hint: "Costs 35 capacity. Adjusts next election timing, raises approval. Requires democracy. 70% success.",
              cost: 35,
              primaryEffects: ["Public Approval +", "Election cycle adjusted", "Stability +"],
              successChance: 0.70)
    ]

    static func action(matching directive: String) -> NativeQuickAction? {
        let trimmed = sanitizeFoundationModelText(directive)
        return actions.first { $0.directiveTemplate == trimmed }
    }

    static func estimatedCost(for directive: String) -> Int? {
        if let action = action(matching: directive) {
            return action.cost
        }
        let trimmed = sanitizeFoundationModelText(directive).lowercased()
        let firstWord = trimmed.split(separator: " ").first.map(String.init) ?? ""
        // Multi-language invasion detection (EN/PT/ES)
        let invadeWords: Set = ["invade", "invadir", "atacar", "attack", "conquer", "conquistar"]
        if invadeWords.contains(firstWord) {
            return 40
        }
        let stabilizeWords: Set = ["stabilize", "estabilizar", "pacificar", "pacify"]
        if stabilizeWords.contains(firstWord) {
            return 25
        }
        let fortifyWords: Set = ["fortify", "fortificar", "reforzar", "reforçar", "defend", "defender"]
        if fortifyWords.contains(firstWord) {
            return 35
        }
        let withdrawWords: Set = ["withdraw", "retirar", "retirarse", "recuar"]
        if withdrawWords.contains(firstWord) {
            return 10
        }
        if trimmed.hasPrefix("negotiate autonomy") || trimmed.hasPrefix("negociar autonomia") {
            return 30
        }
        let rebuildWords: Set = ["rebuild", "reconstruir", "reconstrução"]
        if rebuildWords.contains(firstWord) {
            return 35
        }
        if trimmed.hasPrefix("open trade corridor") || trimmed.hasPrefix("abrir corredor") {
            return 25
        }
        // Political reform keywords
        let liberalizeWords: Set = ["liberalize", "liberalizar", "democratize", "democratizar"]
        if liberalizeWords.contains(firstWord) {
            return 50
        }
        let consolidateWords: Set = ["consolidate", "consolidar"]
        if consolidateWords.contains(firstWord) {
            return 45
        }
        let suspendWords: Set = ["suspend", "suspender"]
        if suspendWords.contains(firstWord) {
            return 60
        }
        let reformWords: Set = ["reform", "reformar"]
        if reformWords.contains(firstWord) {
            return 35
        }
        return nil
    }

    static func invasionActions(for regionName: String, regionID: String) -> [NativeQuickAction] {
        [.init(id: "invade-\(regionID)", category: .military,
               title: "Invade \(regionName)",
               directiveTemplate: "Invade \(regionName) (ID: \(regionID))",
               hint: "Costs 40 capacity. Success depends on terrain and readiness.",
               cost: 40,
               primaryEffects: ["Territorial control ?", "World Tension +", "Stability risk"])]
    }

    static func regionalActions(for region: MapRegion, state: NativeCampaignState) -> [NativeQuickAction] {
        let occupier = state.regionOccupations[region.id] ?? region.countryCode
        let isPlayerControlled = occupier == state.country.code
        let isPlayerCore = region.countryCode == state.country.code
        let hasFallout = state.nuclearFalloutRegions.contains(region.id)
        var actions: [NativeQuickAction] = []

        if !isPlayerControlled {
            actions.append(contentsOf: invasionActions(for: region.name, regionID: region.id))
        }

        if isPlayerCore || isPlayerControlled || state.regionConflicts[region.id] != nil {
            actions.append(.init(
                id: "stabilize-\(region.id)",
                category: .regional,
                title: "Stabilize \(region.name)",
                directiveTemplate: "Stabilize \(region.name) (ID: \(region.id))",
                hint: "Costs 25 capacity. Reduces insurgency or contested pressure.",
                cost: 25,
                primaryEffects: ["Internal Stability +", "Conflict intensity -"]
            ))
        }

        if isPlayerControlled {
            actions.append(.init(
                id: "fortify-\(region.id)",
                category: .regional,
                title: "Fortify \(region.name)",
                directiveTemplate: "Fortify \(region.name) (ID: \(region.id))",
                hint: "Costs 35 capacity. Improves defense but raises tension.",
                cost: 35,
                primaryEffects: ["Military Readiness +", "World Tension +"]
            ))
            actions.append(.init(
                id: "trade-corridor-\(region.id)",
                category: .regional,
                title: "Open trade corridor",
                directiveTemplate: "Open trade corridor through \(region.name) (ID: \(region.id))",
                hint: "Costs 25 capacity. Supports trade and resilience.",
                cost: 25,
                primaryEffects: ["Market Confidence +", "Economic Resilience +"]
            ))
        }

        if isPlayerControlled, !isPlayerCore {
            actions.append(.init(
                id: "withdraw-\(region.id)",
                category: .regional,
                title: "Withdraw from \(region.name)",
                directiveTemplate: "Withdraw from \(region.name) (ID: \(region.id))",
                hint: "Costs 10 capacity. Reduces occupation burden and tension.",
                cost: 10,
                primaryEffects: ["World Tension -", "Occupation burden -"]
            ))
        }

        if isPlayerCore {
            actions.append(.init(
                id: "autonomy-\(region.id)",
                category: .regional,
                title: "Negotiate autonomy",
                directiveTemplate: "Negotiate autonomy for \(region.name) (ID: \(region.id))",
                hint: "Costs 30 capacity. Lowers rebel pressure at political cost.",
                cost: 30,
                primaryEffects: ["Insurgency -", "Diplomatic Leverage +"]
            ))
        }

        if hasFallout || state.regionConflicts[region.id]?.mode == .nuclearFallout {
            actions.append(.init(
                id: "rebuild-\(region.id)",
                category: .regional,
                title: "Rebuild \(region.name)",
                directiveTemplate: "Rebuild \(region.name) (ID: \(region.id))",
                hint: "Costs 35 capacity. Repairs fallout and economic damage.",
                cost: 35,
                primaryEffects: ["Economic Resilience +", "Fallout pressure -"],
                cooldownTurns: 2
            ))
        }

        return actions
    }

    // MARK: — Political Reform Quick Actions

    /// Returns political reform actions available for the player's current regime.
    static func politicalReformActions(state: NativeCampaignState) -> [NativeQuickAction] {
        let govType = state.economicLedger.governmentType
        return actions.filter { action in
            guard action.category == .political else { return false }
            switch action.id {
            case "pol-snap-election":
                return govType == "democracy" || govType == "hybrid"
            case "pol-liberalize":
                return govType == "hybrid" || govType == "autocracy"
            case "pol-consolidate":
                return govType == "democracy" || govType == "hybrid"
            case "pol-suspend-constitution":
                return true // Available from any regime, highest risk
            case "pol-electoral-reform":
                return govType == "democracy"
            default:
                return false
            }
        }
    }
}
