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

    init(
        id: String,
        category: NativeQuickActionCategory,
        title: String,
        directiveTemplate: String,
        hint: String,
        cost: Int,
        primaryEffects: [String],
        cooldownTurns: Int? = nil
    ) {
        self.cooldownTurns = cooldownTurns
        self.cost = cost
        self.id = id
        self.category = category
        self.title = title
        self.directiveTemplate = directiveTemplate
        self.hint = hint
        self.primaryEffects = primaryEffects
    }
}

enum NativeQuickActionCatalog {
    static let actions: [NativeQuickAction] = [
        .init(id: "econ-subsidy", category: .economy,
              title: "Boost agriculture subsidies",
              directiveTemplate: "Increase agricultural subsidies to raise market confidence.",
              hint: "Costs 20 capacity. Raises Market Confidence.",
              cost: 20,
              primaryEffects: ["Market Confidence +", "Budget pressure +"]),
        .init(id: "econ-sanction", category: .economy,
              title: "Impose trade sanctions",
              directiveTemplate: "Impose targeted trade sanctions on a rival economy.",
              hint: "Costs 30 capacity. Lowers a rival's Economic Resilience.",
              cost: 30,
              primaryEffects: ["Rival Economic Resilience -", "World Tension +"]),
        .init(id: "infra-grid", category: .infrastructure,
              title: "Modernize power grid",
              directiveTemplate: "Fund power-grid modernization for long-term resilience.",
              hint: "Costs 40 capacity. Slow Internal Stability gain.",
              cost: 40,
              primaryEffects: ["Economic Resilience +", "Internal Stability +"],
              cooldownTurns: 2),
        .init(id: "welfare-health", category: .welfare,
              title: "Expand healthcare access",
              directiveTemplate: "Expand public healthcare access to improve stability.",
              hint: "Costs 25 capacity. Raises Internal Stability.",
              cost: 25,
              primaryEffects: ["Internal Stability +", "Unrest risk -"]),
        .init(id: "mil-readiness", category: .military,
              title: "Raise military readiness",
              directiveTemplate: "Raise national military readiness and reserve activation.",
              hint: "Costs 35 capacity. Raises Military Readiness, may spike World Tension.",
              cost: 35,
              primaryEffects: ["Military Readiness +", "World Tension +"]),
        .init(id: "dip-trade", category: .diplomacy,
              title: "Propose trade agreement",
              directiveTemplate: "Propose a bilateral trade agreement to deepen ties.",
              hint: "Costs 15 capacity. Best paired with the Diplomacy tab.",
              cost: 15,
              primaryEffects: ["Diplomatic Leverage +", "Trade Balance +"])
    ]

    static func action(matching directive: String) -> NativeQuickAction? {
        let trimmed = sanitizeFoundationModelText(directive)
        return actions.first { $0.directiveTemplate == trimmed }
    }

    static func estimatedCost(for directive: String) -> Int? {
        if let action = action(matching: directive) {
            return action.cost
        }
        let trimmed = sanitizeFoundationModelText(directive)
        if trimmed.hasPrefix("Invade ") { return 40 }
        if trimmed.hasPrefix("Stabilize ") { return 25 }
        if trimmed.hasPrefix("Fortify ") { return 35 }
        if trimmed.hasPrefix("Withdraw from ") { return 10 }
        if trimmed.hasPrefix("Negotiate autonomy for ") { return 30 }
        if trimmed.hasPrefix("Rebuild ") { return 35 }
        if trimmed.hasPrefix("Open trade corridor through ") { return 25 }
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
}
