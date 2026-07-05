import Foundation

// MARK: — Political Reform & Non-Regional Action Outcome Resolution

extension NativeGameEngine {
    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Political Reform Kinds

    // ─────────────────────────────────────────────────────────────────────────

    /// The five player-driven constitutional reform actions.
    enum NativePoliticalReformKind {
        case snapElection
        case liberalize
        case consolidate
        case suspendConstitution
        case electoralReform

        var displayName: String {
            switch self {
            case .snapElection: "snap election"
            case .liberalize: "liberalization"
            case .consolidate: "power consolidation"
            case .suspendConstitution: "constitutional suspension"
            case .electoralReform: "electoral reform"
            }
        }
    }

    /// Maps a directive text to a `NativePoliticalReformKind`, or nil if it is not a reform action.
    static func politicalReformKind(from text: String) -> NativePoliticalReformKind? {
        let lower = sanitizeFoundationModelText(text).lowercased()
        if lower.hasPrefix("call snap elections") || lower.hasPrefix("call snap election") { return .snapElection }
        if lower.hasPrefix("liberalize the political") || lower.hasPrefix("liberalize") { return .liberalize }
        if lower.hasPrefix("consolidate executive") || lower.hasPrefix("consolidate") { return .consolidate }
        if lower.hasPrefix("suspend constitutional") || lower.hasPrefix("suspend") { return .suspendConstitution }
        if lower.hasPrefix("reform the electoral") || lower.hasPrefix("reform electoral") { return .electoralReform }
        return nil
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Non-Regional Action Outcome Dice Roll

    // ─────────────────────────────────────────────────────────────────────────

    /// Resolves deterministic success/failure for every non-regional, non-invasion resolved action
    /// that is NOT a political reform (those are handled separately).
    ///
    /// The dice seed is deterministic: `"action-outcome-\(action.id)-round-\(round)"`.
    /// A stability modifier shifts the effective threshold: higher stability makes actions easier.
    ///
    /// Returns a list of additional timeline events describing each outcome.
    static func resolveNonRegionalActionOutcomes(
        actions resolvedActions: inout [NativePlannedAction],
        state: NativeCampaignState,
        targetDate: String,
        round: Int,
        finalLedgers: inout [String: NativeEconomicLedger]
    ) -> [NativeCampaignEvent] {
        var events: [NativeCampaignEvent] = []

        for idx in resolvedActions.indices {
            let action = resolvedActions[idx]
            guard action.status == .resolved, action.outcome == nil else { continue }

            let text = action.detail.isEmpty ? action.title : action.detail

            // Skip regional and invasion orders — they have their own resolution
            guard regionOrderKind(from: text) == nil else { continue }
            // Skip political reforms — handled by resolvePoliticalReformOrders
            guard politicalReformKind(from: text) == nil else { continue }

            // Look up base success chance from catalog
            let catalogAction = NativeQuickActionCatalog.action(matching: text)
            let baseChance = catalogAction?.successChance ?? 0.85 // default 85% for freeform directives

            // Stability modifier: each point above 50 adds 0.2%, each point below 50 subtracts 0.2%
            let stabilityMod = Double(state.stability - 50) * 0.002
            let effectiveChance = max(0.10, min(0.98, baseChance + stabilityMod))

            let seed = "action-outcome-\(action.id)-round-\(round)"
            let roll = stablePercentagePublic(seed: seed) // 0.0 to 100.0

            let outcome: NativeActionOutcome
            let eventImportance: NativeEventImportance
            let eventKind: NativeEventKind
            let eventTitle: String
            let eventDesc: String
            let stabilityEffect: Int

            if roll <= effectiveChance * 100.0 {
                // Success
                outcome = .success
                eventImportance = .major
                eventKind = .action
                eventTitle = "Order Executed: \(action.title)"
                eventDesc = "The directive '\(action.title)' was successfully carried out. Administrative teams executed the order within budget and timeline, achieving its primary objectives."
                stabilityEffect = 1
            } else if roll <= (effectiveChance + 0.15) * 100.0 {
                // Partial success — roll within 15% beyond threshold
                outcome = .partial
                eventImportance = .minor
                eventKind = .action
                eventTitle = "Order Partially Executed: \(action.title)"
                eventDesc = "The directive '\(action.title)' was only partially carried out. Implementation encountered bureaucratic friction and resource constraints, achieving reduced effectiveness."
                stabilityEffect = 0
            } else {
                // Failure
                outcome = .failure
                eventImportance = .major
                eventKind = .crisis
                eventTitle = "Order Failed: \(action.title)"
                eventDesc = "The directive '\(action.title)' failed to produce results. Poor implementation, external resistance, or adverse conditions caused the initiative to collapse before achieving its objectives."
                stabilityEffect = -2
            }

            resolvedActions[idx].outcome = outcome

            let effectID = "action-outcome-\(action.id)-\(targetDate)"
            var strategicEffects: [NativeStrategicEffect] = []
            if stabilityEffect != 0 {
                strategicEffects.append(NativeStrategicEffect(
                    date: targetDate,
                    eventId: effectID,
                    id: "\(effectID)-stability",
                    magnitude: stabilityEffect,
                    summary: outcome == .success
                        ? "Successful directive execution marginally bolsters administrative confidence."
                        : "Failed directive erodes public confidence in governance.",
                    target: state.country.code,
                    track: .internalStability
                ))
            }

            // Apply economic penalty on failure
            if outcome == .failure, var playerLedger = finalLedgers[state.country.code] {
                playerLedger.realGrowthPercent = max(-12.0, playerLedger.realGrowthPercent - 0.3)
                finalLedgers[state.country.code] = playerLedger
            }

            events.append(NativeCampaignEvent(
                date: targetDate,
                description: eventDesc,
                id: effectID,
                importance: eventImportance,
                kind: eventKind,
                linkedActionIDs: [action.id],
                notable: outcome != .partial,
                playerRelated: true,
                strategicEffects: strategicEffects,
                title: eventTitle
            ))
        }

        return events
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Political Reform Resolution

    // ─────────────────────────────────────────────────────────────────────────

    /// Resolves all political reform actions in the resolved list.
    /// Mutates `economicLedgers` and `resolvedActions` in place, returns new events.
    static func resolvePoliticalReformOrders(
        actions resolvedActions: inout [NativePlannedAction],
        state: NativeCampaignState,
        targetDate: String,
        round: Int,
        economicLedgers: inout [String: NativeEconomicLedger]
    ) -> [NativeCampaignEvent] {
        var events: [NativeCampaignEvent] = []

        for idx in resolvedActions.indices {
            let action = resolvedActions[idx]
            guard action.status == .resolved, action.outcome == nil else { continue }

            let text = action.detail.isEmpty ? action.title : action.detail
            guard let reformKind = politicalReformKind(from: text) else { continue }

            guard var playerLedger = economicLedgers[state.country.code] else { continue }
            let currentGov = playerLedger.governmentType

            // Base success chance from catalog; fallback to kind-specific default
            let catalogAction = NativeQuickActionCatalog.action(matching: text)
            let baseChance: Double = if let c = catalogAction {
                c.successChance
            } else {
                switch reformKind {
                case .snapElection: 0.80
                case .liberalize: 0.50
                case .consolidate: 0.55
                case .suspendConstitution: 0.40
                case .electoralReform: 0.70
                }
            }

            // Stability and approval modify chance
            let approval = playerLedger.publicApprovalPercent
            let stabilityMod = Double(state.stability - 50) * 0.003
            let approvalMod = (approval - 50.0) * 0.002
            let effectiveChance = max(0.08, min(0.95, baseChance + stabilityMod + approvalMod))

            let seed = "political-reform-\(action.id)-round-\(round)"
            let roll = stablePercentagePublic(seed: seed)
            let isSuccess = roll <= effectiveChance * 100.0

            let (outcome, additionalEvent): (NativeActionOutcome, NativeCampaignEvent)

            switch reformKind {
            case .snapElection:
                (outcome, additionalEvent) = resolveSnapElection(
                    isSuccess: isSuccess, action: action, currentGov: currentGov,
                    targetDate: targetDate, round: round, ledger: &playerLedger, state: state
                )
            case .liberalize:
                (outcome, additionalEvent) = resolveLiberalization(
                    isSuccess: isSuccess, action: action, currentGov: currentGov,
                    targetDate: targetDate, round: round, ledger: &playerLedger, state: state
                )
            case .consolidate:
                (outcome, additionalEvent) = resolveConsolidation(
                    isSuccess: isSuccess, action: action, currentGov: currentGov,
                    targetDate: targetDate, round: round, ledger: &playerLedger, state: state
                )
            case .suspendConstitution:
                (outcome, additionalEvent) = resolveSuspendConstitution(
                    isSuccess: isSuccess, action: action, currentGov: currentGov,
                    targetDate: targetDate, round: round, ledger: &playerLedger, state: state
                )
            case .electoralReform:
                (outcome, additionalEvent) = resolveElectoralReform(
                    isSuccess: isSuccess, action: action, currentGov: currentGov,
                    targetDate: targetDate, round: round, ledger: &playerLedger, state: state
                )
            }

            resolvedActions[idx].outcome = outcome
            economicLedgers[state.country.code] = playerLedger
            events.append(additionalEvent)
        }

        return events
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Individual Reform Resolvers

    // ─────────────────────────────────────────────────────────────────────────

    private static func resolveSnapElection(
        isSuccess: Bool,
        action: NativePlannedAction,
        currentGov: String,
        targetDate: String,
        round: Int,
        ledger: inout NativeEconomicLedger,
        state: NativeCampaignState
    ) -> (NativeActionOutcome, NativeCampaignEvent) {
        let id = "pol-snap-election-\(action.id)-\(targetDate)"
        if isSuccess, currentGov == "democracy" || currentGov == "hybrid" {
            ledger.nextElectionRound = round + 12
            ledger.publicApprovalPercent = min(90.0, ledger.publicApprovalPercent + 5.0)
            let event = NativeCampaignEvent(
                date: targetDate,
                description: "The administration called snap elections, dissolving the current legislature and triggering an early vote. The move was received as a bold democratic commitment, and campaign season begins immediately.",
                id: id,
                importance: .major,
                kind: .world,
                linkedActionIDs: [action.id],
                notable: true,
                playerRelated: true,
                strategicEffects: [
                    NativeStrategicEffect(
                        date: targetDate,
                        eventId: id,
                        id: "\(id)-stability",
                        magnitude: 2,
                        summary: "Democratic renewal boosts public legitimacy.",
                        target: state.country.code,
                        track: .internalStability
                    )
                ],
                title: "Snap Elections Called"
            )
            return (.success, event)
        } else {
            let reason = currentGov == "autocracy"
                ? "The regime lacks the constitutional framework to call snap elections. Opposition leaders rejected the move as political theater."
                : "Attempts to dissolve the legislature were blocked by a coalition of opposition parties who challenged the constitutionality of the order in court."
            let event = NativeCampaignEvent(
                date: targetDate,
                description: "Snap election bid failed: \(reason)",
                id: id,
                importance: .major,
                kind: .crisis,
                linkedActionIDs: [action.id],
                notable: true,
                playerRelated: true,
                strategicEffects: [
                    NativeStrategicEffect(
                        date: targetDate,
                        eventId: id,
                        id: "\(id)-stability",
                        magnitude: -3,
                        summary: "Failed constitutional maneuver damages administration credibility.",
                        target: state.country.code,
                        track: .internalStability
                    )
                ],
                title: "Snap Election Bid Blocked"
            )
            return (.failure, event)
        }
    }

    private static func resolveLiberalization(
        isSuccess: Bool,
        action: NativePlannedAction,
        currentGov: String,
        targetDate: String,
        round: Int,
        ledger: inout NativeEconomicLedger,
        state: NativeCampaignState
    ) -> (NativeActionOutcome, NativeCampaignEvent) {
        let id = "pol-liberalize-\(action.id)-\(targetDate)"
        if isSuccess {
            let previous = currentGov
            ledger.governmentType = "democracy"
            ledger.nextElectionRound = round + 24
            ledger.publicApprovalPercent = min(90.0, ledger.publicApprovalPercent + 10.0)
            let event = NativeCampaignEvent(
                date: targetDate,
                description: "A sweeping constitutional reform package has been enacted, transitioning the country from a \(previous) regime toward full democratic governance. Free and fair elections are scheduled within two years. Civil society organizations celebrated the move, while international partners pledged support.",
                id: id,
                importance: .major,
                kind: .world,
                linkedActionIDs: [action.id],
                notable: true,
                playerRelated: true,
                strategicEffects: [
                    NativeStrategicEffect(
                        date: targetDate,
                        eventId: id,
                        id: "\(id)-stability",
                        magnitude: 8,
                        summary: "Democratic transition bolsters national stability and international standing.",
                        target: state.country.code,
                        track: .internalStability
                    ),
                    NativeStrategicEffect(
                        date: targetDate,
                        eventId: id,
                        id: "\(id)-tension",
                        magnitude: -5,
                        summary: "Democratization reduces geopolitical tension.",
                        target: state.country.code,
                        track: .worldTension
                    )
                ],
                title: "Constitutional Liberalization Enacted"
            )
            return (.success, event)
        } else {
            let event = NativeCampaignEvent(
                date: targetDate,
                description: "The liberalization package was struck down by a coalition of hardline legislators, security apparatus officials, and entrenched economic interests who viewed democratic reform as an existential threat. Street protests broke out in several cities as supporters of reform clashed with loyalist groups.",
                id: id,
                importance: .major,
                kind: .crisis,
                linkedActionIDs: [action.id],
                notable: true,
                playerRelated: true,
                strategicEffects: [
                    NativeStrategicEffect(
                        date: targetDate,
                        eventId: id,
                        id: "\(id)-stability",
                        magnitude: -5,
                        summary: "Failed liberalization triggers political unrest.",
                        target: state.country.code,
                        track: .internalStability
                    )
                ],
                title: "Liberalization Reform Blocked"
            )
            return (.failure, event)
        }
    }

    private static func resolveConsolidation(
        isSuccess: Bool,
        action: NativePlannedAction,
        currentGov: String,
        targetDate: String,
        round _: Int,
        ledger: inout NativeEconomicLedger,
        state: NativeCampaignState
    ) -> (NativeActionOutcome, NativeCampaignEvent) {
        let id = "pol-consolidate-\(action.id)-\(targetDate)"
        if isSuccess {
            let previous = currentGov
            ledger.governmentType = "hybrid"
            ledger.publicApprovalPercent = max(10.0, ledger.publicApprovalPercent - 5.0)
            let event = NativeCampaignEvent(
                date: targetDate,
                description: "The administration successfully consolidated executive authority, bypassing several legislative checks and centralizing decision-making within the executive branch. Critics warned of democratic backsliding, while the government justified the move as necessary for national stability. The country transitions from \(previous) to a hybrid regime.",
                id: id,
                importance: .major,
                kind: .world,
                linkedActionIDs: [action.id],
                notable: true,
                playerRelated: true,
                strategicEffects: [
                    NativeStrategicEffect(
                        date: targetDate,
                        eventId: id,
                        id: "\(id)-stability",
                        magnitude: -3,
                        summary: "Democratic backsliding increases domestic opposition.",
                        target: state.country.code,
                        track: .internalStability
                    ),
                    NativeStrategicEffect(
                        date: targetDate,
                        eventId: id,
                        id: "\(id)-tension",
                        magnitude: 4,
                        summary: "Power consolidation raises international concern.",
                        target: state.country.code,
                        track: .worldTension
                    )
                ],
                title: "Executive Power Consolidated"
            )
            return (.success, event)
        } else {
            let event = NativeCampaignEvent(
                date: targetDate,
                description: "Efforts to consolidate executive authority were defeated by a broad coalition of opposition parties, civil liberties advocates, and international pressure. The constitutional court ruled the consolidation package unconstitutional, forcing a retreat. Public trust in the government fell sharply.",
                id: id,
                importance: .major,
                kind: .crisis,
                linkedActionIDs: [action.id],
                notable: true,
                playerRelated: true,
                strategicEffects: [
                    NativeStrategicEffect(
                        date: targetDate,
                        eventId: id,
                        id: "\(id)-stability",
                        magnitude: -4,
                        summary: "Failed power grab damages administrative credibility.",
                        target: state.country.code,
                        track: .internalStability
                    )
                ],
                title: "Power Consolidation Attempt Defeated"
            )
            return (.failure, event)
        }
    }

    private static func resolveSuspendConstitution(
        isSuccess: Bool,
        action: NativePlannedAction,
        currentGov _: String,
        targetDate: String,
        round _: Int,
        ledger: inout NativeEconomicLedger,
        state: NativeCampaignState
    ) -> (NativeActionOutcome, NativeCampaignEvent) {
        let id = "pol-suspend-\(action.id)-\(targetDate)"
        if isSuccess {
            ledger.governmentType = "autocracy"
            ledger.publicApprovalPercent = max(10.0, ledger.publicApprovalPercent - 15.0)
            let event = NativeCampaignEvent(
                date: targetDate,
                description: "The constitutional order has been suspended. Emergency decrees have been issued granting the executive branch sweeping powers over the judiciary, legislature, and media. International condemnation followed swiftly, with several allies downgrading diplomatic ties. Domestically, security forces suppressed initial protests. The country has entered a period of autocratic rule.",
                id: id,
                importance: .severe,
                kind: .crisis,
                linkedActionIDs: [action.id],
                notable: true,
                playerRelated: true,
                strategicEffects: [
                    NativeStrategicEffect(
                        date: targetDate,
                        eventId: id,
                        id: "\(id)-stability",
                        magnitude: -10,
                        summary: "Constitutional suspension triggers political crisis and domestic unrest.",
                        target: state.country.code,
                        track: .internalStability
                    ),
                    NativeStrategicEffect(
                        date: targetDate,
                        eventId: id,
                        id: "\(id)-tension",
                        magnitude: 12,
                        summary: "Authoritarian transition sharply raises global tension.",
                        target: state.country.code,
                        track: .worldTension
                    ),
                    NativeStrategicEffect(
                        date: targetDate,
                        eventId: id,
                        id: "\(id)-leverage",
                        magnitude: -8,
                        summary: "International isolation erodes diplomatic leverage.",
                        target: state.country.code,
                        track: .diplomaticLeverage
                    )
                ],
                title: "Constitution Suspended: Autocratic Rule Declared"
            )
            return (.success, event)
        } else {
            ledger.publicApprovalPercent = max(10.0, ledger.publicApprovalPercent - 10.0)
            let event = NativeCampaignEvent(
                date: targetDate,
                description: "The attempt to suspend the constitutional order collapsed in the face of coordinated resistance from the armed forces, the constitutional court, and mass civil protests. The administration backed down under international pressure. The failed power grab has left the government severely weakened and facing calls for resignation.",
                id: id,
                importance: .severe,
                kind: .crisis,
                linkedActionIDs: [action.id],
                notable: true,
                playerRelated: true,
                strategicEffects: [
                    NativeStrategicEffect(
                        date: targetDate,
                        eventId: id,
                        id: "\(id)-stability",
                        magnitude: -15,
                        summary: "Failed coup attempt triggers constitutional crisis.",
                        target: state.country.code,
                        track: .internalStability
                    ),
                    NativeStrategicEffect(
                        date: targetDate,
                        eventId: id,
                        id: "\(id)-tension",
                        magnitude: 6,
                        summary: "Political instability raises regional security concerns.",
                        target: state.country.code,
                        track: .worldTension
                    )
                ],
                title: "Constitutional Coup Attempt Fails"
            )
            return (.failure, event)
        }
    }

    private static func resolveElectoralReform(
        isSuccess: Bool,
        action: NativePlannedAction,
        currentGov: String,
        targetDate: String,
        round: Int,
        ledger: inout NativeEconomicLedger,
        state: NativeCampaignState
    ) -> (NativeActionOutcome, NativeCampaignEvent) {
        let id = "pol-electoral-reform-\(action.id)-\(targetDate)"
        if isSuccess, currentGov == "democracy" {
            let adjustSeed = "electoral-reform-adjust-\(action.id)-\(round)"
            let adjustRoll = stablePercentagePublic(seed: adjustSeed)
            let adjustment = adjustRoll < 50.0 ? -6 : 6
            ledger.nextElectionRound = max(round + 6, ledger.nextElectionRound + adjustment)
            ledger.publicApprovalPercent = min(90.0, ledger.publicApprovalPercent + 7.0)

            let directionLabel = adjustment < 0 ? "moved earlier" : "extended"
            let event = NativeCampaignEvent(
                date: targetDate,
                description: "A comprehensive electoral reform package was enacted, modernizing voting procedures, updating constituency boundaries, and strengthening oversight mechanisms. The next election cycle has been \(directionLabel). International election monitors praised the reforms as a significant step forward for democratic integrity.",
                id: id,
                importance: .major,
                kind: .world,
                linkedActionIDs: [action.id],
                notable: true,
                playerRelated: true,
                strategicEffects: [
                    NativeStrategicEffect(
                        date: targetDate,
                        eventId: id,
                        id: "\(id)-stability",
                        magnitude: 4,
                        summary: "Electoral legitimacy strengthens democratic institutions.",
                        target: state.country.code,
                        track: .internalStability
                    ),
                    NativeStrategicEffect(
                        date: targetDate,
                        eventId: id,
                        id: "\(id)-leverage",
                        magnitude: 3,
                        summary: "Democratic reform boosts international diplomatic standing.",
                        target: state.country.code,
                        track: .diplomaticLeverage
                    )
                ],
                title: "Electoral Reform Enacted"
            )
            return (.success, event)
        } else if currentGov != "democracy" {
            let event = NativeCampaignEvent(
                date: targetDate,
                description: "Electoral reform proposals cannot proceed without democratic institutions in place. The initiative was quietly shelved by the administration.",
                id: id,
                importance: .minor,
                kind: .action,
                linkedActionIDs: [action.id],
                notable: false,
                playerRelated: true,
                strategicEffects: [],
                title: "Electoral Reform: No Democratic Framework"
            )
            return (.failure, event)
        } else {
            let event = NativeCampaignEvent(
                date: targetDate,
                description: "The electoral reform package was defeated in parliament, with entrenched parties from both sides of the aisle rejecting changes that could disadvantage their electoral coalitions. The reform effort collapsed after a procedural vote, leaving the existing system intact.",
                id: id,
                importance: .major,
                kind: .crisis,
                linkedActionIDs: [action.id],
                notable: true,
                playerRelated: true,
                strategicEffects: [
                    NativeStrategicEffect(
                        date: targetDate,
                        eventId: id,
                        id: "\(id)-stability",
                        magnitude: -2,
                        summary: "Failed reform signals legislative dysfunction.",
                        target: state.country.code,
                        track: .internalStability
                    )
                ],
                title: "Electoral Reform Blocked in Parliament"
            )
            return (.failure, event)
        }
    }
}
