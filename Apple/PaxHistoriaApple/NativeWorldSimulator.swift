import Foundation
#if canImport(CoreML)
    import CoreML
#endif

// MARK: - Shared 5 x 5 decision contract

enum NativeDecisionMatrixRow: Int, Codable, CaseIterable, Hashable, Identifiable {
    case economy
    case society
    case diplomacy
    case security
    case sovereignty

    var id: Int {
        rawValue
    }

    var title: String {
        switch self {
        case .economy: "Economy"
        case .society: "Society"
        case .diplomacy: "Diplomacy"
        case .security: "Security"
        case .sovereignty: "Sovereignty"
        }
    }

    var systemImage: String {
        switch self {
        case .economy: "chart.line.uptrend.xyaxis"
        case .society: "person.3"
        case .diplomacy: "bubble.left.and.bubble.right"
        case .security: "shield.lefthalf.filled"
        case .sovereignty: "map"
        }
    }
}

enum NativeDecisionMatrixColumn: Int, Codable, CaseIterable, Hashable, Identifiable {
    case stabilize
    case prepare
    case cooperate
    case project
    case transform

    var id: Int {
        rawValue
    }

    var title: String {
        switch self {
        case .stabilize: "Stabilize"
        case .prepare: "Prepare"
        case .cooperate: "Cooperate"
        case .project: "Project"
        case .transform: "Transform"
        }
    }
}

enum NativeDecisionMatrixContract {
    static let cellCount = NativeDecisionMatrixRow.allCases.count * NativeDecisionMatrixColumn.allCases.count

    static func validatedPlayerMatrix(
        _ rawSuggestions: [NativeSuggestedAction],
        state: NativeCampaignState
    ) throws -> [NativeSuggestedAction] {
        var coordinates = Set<String>()
        var titles = Set<String>()
        var validated: [NativeSuggestedAction] = []
        var failures: [String] = []

        for raw in rawSuggestions {
            var suggestion = raw
            suggestion.title = sanitizeFoundationModelText(suggestion.title)
            suggestion.detail = sanitizeFoundationModelText(suggestion.detail)
            suggestion.rationale = sanitizeFoundationModelText(suggestion.rationale)
            suggestion.actionKind = sanitizeFoundationModelText(suggestion.actionKind).lowercased()
            suggestion.targetCountryCode = normalizedOptionalCode(suggestion.targetCountryCode)
            suggestion.targetRegionID = sanitizedOptional(suggestion.targetRegionID)
            suggestion.administrativeCost = effectiveCost(of: suggestion)

            let coordinate = "\(suggestion.matrixRow):\(suggestion.matrixColumn)"
            let normalizedTitle = suggestion.title.lowercased()
            guard coordinates.insert(coordinate).inserted else {
                failures.append("duplicate coordinate \(coordinate)")
                continue
            }
            guard titles.insert(normalizedTitle).inserted else {
                failures.append("duplicate title at \(coordinate)")
                continue
            }
            guard let reason = eligibilityFailure(for: suggestion, state: state) else {
                suggestion.id = "matrix-\(state.country.code.lowercased())-\(state.round)-\(suggestion.matrixRow)-\(suggestion.matrixColumn)"
                suggestion.matrixStateFingerprint = stateFingerprint(for: state)
                validated.append(suggestion)
                continue
            }
            failures.append("\(coordinate): \(reason)")
        }

        let expectedCoordinates = Set(NativeDecisionMatrixRow.allCases.flatMap { row in
            NativeDecisionMatrixColumn.allCases.map { "\(row.rawValue):\($0.rawValue)" }
        })
        let actualCoordinates = Set(validated.map { "\($0.matrixRow):\($0.matrixColumn)" })
        let missing = expectedCoordinates.subtracting(actualCoordinates).sorted()
        guard validated.count == cellCount, missing.isEmpty else {
            let detail = (failures.prefix(8) + missing.prefix(8).map { "missing \($0)" }).joined(separator: "; ")
            throw NativeFoundationModelError.invalidSuggestedActions(
                "Decision matrix contains \(validated.count)/\(cellCount) eligible cells. \(detail)"
            )
        }

        return validated.sorted {
            ($0.matrixRow, $0.matrixColumn) < ($1.matrixRow, $1.matrixColumn)
        }
    }

    static func eligibilityFailure(
        for suggestion: NativeSuggestedAction,
        state: NativeCampaignState
    ) -> String? {
        if suggestion.matrixStateFingerprint != 0,
           suggestion.matrixStateFingerprint != stateFingerprint(for: state)
        {
            return "world state changed after this matrix was generated"
        }
        guard NativeDecisionMatrixRow(rawValue: suggestion.matrixRow) != nil,
              NativeDecisionMatrixColumn(rawValue: suggestion.matrixColumn) != nil
        else { return "coordinate is outside 0...4" }
        guard hasConcreteFoundationText(suggestion.title, minimumWords: 2) else { return "title is not concrete" }
        guard hasConcreteFoundationText(suggestion.detail, minimumWords: 4) else { return "detail is not concrete" }
        guard hasConcreteFoundationText(suggestion.rationale, minimumWords: 5) else { return "rationale is not grounded" }
        guard suggestion.administrativeCost > 0 else { return "administrativeCost must be positive" }
        guard suggestion.administrativeCost <= state.administrativeCapacity else {
            return "cost \(suggestion.administrativeCost) exceeds capacity \(state.administrativeCapacity)"
        }

        let allowedKinds: Set = ["policy", "political", "diplomacy", "military", "regional", "sovereignty"]
        guard allowedKinds.contains(suggestion.actionKind) else { return "unknown actionKind \(suggestion.actionKind)" }
        if NativeGameEngine.politicalReformKind(from: suggestion.detail) != nil,
           suggestion.actionKind != "political"
        {
            return "political reform is misclassified as \(suggestion.actionKind)"
        }
        if NativeGameEngine.regionOrderKind(from: suggestion.detail) != nil,
           suggestion.actionKind != "regional", suggestion.actionKind != "military"
        {
            return "territorial order is misclassified as \(suggestion.actionKind)"
        }
        let lowerDetail = suggestion.detail.lowercased()
        let sovereigntyWords = ["secede", "secession", "breakaway", "merge countries", "political union", "dissolve the state"]
        if sovereigntyWords.contains(where: lowerDetail.contains), suggestion.sovereigntyChange == nil {
            return "formal sovereignty language requires structured sovereigntyChange"
        }

        let knownCodes = Set(NativeStrategyContextDatabase.strategicCountryCodes(for: state))
        if let targetCode = suggestion.targetCountryCode,
           targetCode != "GLOBAL", targetCode != state.country.code,
           !knownCodes.contains(targetCode)
        {
            return "target country \(targetCode) does not exist"
        }

        if let regionID = suggestion.targetRegionID, GeopoliticalMapData.regionByID[regionID] == nil {
            return "target region \(regionID) does not exist"
        }

        switch suggestion.actionKind {
        case "political":
            let allowed = NativeQuickActionCatalog.politicalReformActions(state: state)
            guard allowed.contains(where: { $0.directiveTemplate == suggestion.detail }) else {
                return "political reform is unavailable under \(state.economicLedger.governmentType)"
            }
        case "regional":
            guard let regionID = suggestion.targetRegionID,
                  let region = GeopoliticalMapData.regionByID[regionID]
            else { return "regional action requires targetRegionID" }
            let allowed = NativeQuickActionCatalog.regionalActions(for: region, state: state)
            guard allowed.contains(where: { $0.directiveTemplate == suggestion.detail }) else {
                return "regional directive is not currently legal for \(regionID)"
            }
        case "military":
            guard state.militaryUnits.values.reduce(0, +) > 0 else { return "country has no deployable forces" }
            if let regionID = suggestion.targetRegionID {
                guard let region = GeopoliticalMapData.regionByID[regionID] else { return "military target is missing" }
                let allowed = NativeQuickActionCatalog.regionalActions(for: region, state: state)
                guard allowed.contains(where: { $0.directiveTemplate == suggestion.detail }) else {
                    return "military region order is not currently legal"
                }
            }
        case "diplomacy":
            guard let target = suggestion.targetCountryCode,
                  target != state.country.code, target != "GLOBAL", knownCodes.contains(target)
            else { return "diplomacy requires an existing foreign target" }
        case "sovereignty":
            guard let change = suggestion.sovereigntyChange else {
                return "sovereignty action requires structured sovereigntyChange"
            }
            if let failure = sovereigntyFailure(change, state: state) { return failure }
        default:
            break
        }

        return nil
    }

    static func effectiveCost(of suggestion: NativeSuggestedAction) -> Int {
        if suggestion.administrativeCost > 0 { return suggestion.administrativeCost }
        return NativeGameEngine.estimateDirectiveCost(for: suggestion.detail)
    }

    static func stateFingerprint(for state: NativeCampaignState) -> UInt64 {
        let ledgers = state.economicLedgers.sorted { $0.key < $1.key }.map { code, ledger in
            "\(code):\(ledger.nominalGDPTrillions):\(ledger.realGrowthPercent):\(ledger.inflationPercent):\(ledger.budgetBalancePercentGDP):\(ledger.publicDebtPercentGDP):\(ledger.tradeBalancePercentGDP):\(ledger.fiscalSpaceIndex):\(ledger.securityIndex):\(ledger.rebelControlPercent):\(ledger.governmentType):\(ledger.publicApprovalPercent):\(ledger.nextElectionRound):\(ledger.resourceReserves.sorted { $0.key < $1.key })"
        }.joined(separator: "|")
        let countries = state.aiCountryStates.sorted { $0.key < $1.key }.map { code, ai in
            "\(code):\(ai.doctrine.rawValue):\(ai.budgetPriority.rawValue):\(ai.agendaProgress):\(ai.decisionStep):\(ai.relationshipScores.sorted { $0.key < $1.key })"
        }.joined(separator: "|")
        let conflicts = state.regionConflicts.sorted { $0.key < $1.key }.map { id, conflict in
            "\(id):\(conflict.controllerCode):\(conflict.mode.rawValue):\(conflict.intensity)"
        }.joined(separator: "|")
        let armies = state.mapArmies.sorted { $0.id < $1.id }.map {
            "\($0.id):\($0.countryCode):\($0.currentRegionID):\($0.strength):\($0.type.rawValue)"
        }.joined(separator: "|")
        return NativeWorldSimulator.stableSeed([
            String(NativeWorldSimulator.resolvedWorldSeed(for: state)), state.scenarioID, state.country.code,
            state.gameDate, String(state.round), String(state.stability), String(state.worldTension),
            String(state.budgetMilitarySlider), String(state.budgetServicesSlider),
            String(state.budgetDiplomacySlider), String(state.budgetResearchSlider),
            state.techEra, String(state.researchPoints), String(describing: state.militaryUnits.sorted { $0.key < $1.key }),
            String(describing: state.dynamicCountries.sorted { $0.key < $1.key }),
            String(describing: state.regionOccupations.sorted { $0.key < $1.key }),
            String(describing: state.nuclearFalloutRegions.sorted()),
            String(describing: state.activeOffers.sorted { $0.id < $1.id }),
            ledgers, countries, conflicts, armies
        ].joined(separator: "#"))
    }

    private static func sovereigntyFailure(
        _ change: NativeSovereigntyChange,
        state: NativeCampaignState
    ) -> String? {
        let knownCodes = Set(NativeStrategyContextDatabase.strategicCountryCodes(for: state))
        let target = normalizedOptionalCode(change.targetCode) ?? ""
        guard target.count >= 3 else { return "sovereignty targetCode must contain 3-6 letters" }
        guard change.sourceCodes.allSatisfy({ knownCodes.contains($0) }) else {
            return "sovereignty sourceCodes include a country that does not exist"
        }
        guard change.regionIDs.allSatisfy({ GeopoliticalMapData.regionByID[$0] != nil }) else {
            return "sovereignty regionIDs include an unknown region"
        }

        switch change.kind {
        case .secession, .newCountry:
            guard !change.sourceCodes.isEmpty, !change.regionIDs.isEmpty else {
                return "secession requires sourceCodes and regionIDs"
            }
            let pressureExists = change.sourceCodes.contains { code in
                (state.economicLedgers[code]?.rebelControlPercent ?? 0) >= 20
            } || change.regionIDs.contains { state.regionConflicts[$0]?.intensity ?? 0 >= 3 }
            return pressureExists ? nil : "secession lacks stored insurgency or territorial pressure"
        case .merge:
            guard change.sourceCodes.count >= 2 else { return "merge requires at least two sourceCodes" }
            let pairs = change.sourceCodes.flatMap { lhs in change.sourceCodes.map { (lhs, $0) } }
            let cooperative = pairs.contains { lhs, rhs in
                lhs != rhs && (state.aiCountryStates[lhs]?.relationshipScores[rhs] ?? 0) >= 40
            }
            return cooperative ? nil : "merge lacks a stored cooperative relationship"
        case .dissolution:
            let collapsePressure = change.sourceCodes.contains {
                (state.economicLedgers[$0]?.rebelControlPercent ?? 0) >= 70
            }
            return collapsePressure ? nil : "dissolution lacks collapse-level pressure"
        }
    }

    private static func normalizedOptionalCode(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.uppercased().filter { $0 >= "A" && $0 <= "Z" }
        return normalized.isEmpty ? nil : String(normalized.prefix(6))
    }

    private static func sanitizedOptional(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = sanitizeFoundationModelText(value)
        return normalized.isEmpty ? nil : normalized
    }
}

// MARK: - External-provider matrix prompt

enum NativeDecisionMatrixPrompt {
    static func make(for state: NativeCampaignState, matrixRow: Int? = nil) -> String {
        let worldSeed = NativeWorldSimulator.resolvedWorldSeed(for: state)
        let turnSeed = NativeWorldSimulator.turnSeed(worldSeed: worldSeed, round: state.round)
        let stateFingerprint = NativeDecisionMatrixContract.stateFingerprint(for: state)
        let objectives = NativeGameEngine.campaignObjectives(for: state).map {
            "- \($0.title): \($0.currentValue) / \($0.targetValue); deadline=\($0.deadline); complete=\($0.isComplete)"
        }.joined(separator: "\n")
        let political = NativeQuickActionCatalog.politicalReformActions(state: state)
            .filter { $0.cost <= state.administrativeCapacity }
            .map { "- detail=\($0.directiveTemplate) | cost=\($0.cost) | effects=\($0.primaryEffects.joined(separator: ","))" }
            .joined(separator: "\n")
        let regional = regionalOptions(state: state).joined(separator: "\n")
        let countries = countryStateLines(state: state).joined(separator: "\n")
        let timeline = state.timeline.prefix(16).map { event in
            let effects = event.strategicEffects.map { "\($0.target):\($0.track.rawValue):\($0.magnitude)" }.joined(separator: ",")
            let sovereignty = event.sovereigntyChange.map { " sovereignty=\($0.kind.rawValue):\($0.targetCode)" } ?? ""
            return "- \(event.date) [\(event.kind.rawValue)] \(event.title) | \(effects)\(sovereignty)"
        }.joined(separator: "\n")
        let conflicts = state.regionConflicts.values.sorted { $0.regionID < $1.regionID }.map {
            "- \($0.regionID): owner=\($0.originalCountryCode), controller=\($0.controllerCode), mode=\($0.mode.rawValue), intensity=\($0.intensity), securityDelta=\($0.securityDelta), rebelDelta=\($0.rebelDelta)"
        }.joined(separator: "\n")
        let armies = state.mapArmies.sorted { $0.id < $1.id }.prefix(80).map {
            "\($0.countryCode):\($0.type.rawValue):\($0.strength)@\($0.currentRegionID)"
        }.joined(separator: ", ")
        let buildings = state.mapBuildings.sorted { $0.id < $1.id }.prefix(80).map {
            "\($0.ownerCountryCode):\($0.type.rawValue)@\($0.regionID):L\($0.level)"
        }.joined(separator: ", ")
        let actionMemory = state.actionMemory.prefix(12).map {
            "- \($0.createdAt) \($0.status.rawValue) \($0.title) | rules=\($0.ruleIDs.joined(separator: ",")) | \($0.economicSummary)"
        }.joined(separator: "\n")
        let language = switch state.language {
        case .portuguese: "Brazilian Portuguese"
        case .spanish: "Spanish"
        case .english: "English"
        }
        let boardInstruction = if let matrixRow {
            "Produce exactly 5 actions for matrixRow=\(matrixRow), one for every matrixColumn 0...4. Do not return cells from any other row."
        } else {
            "Produce exactly 25 actions in a 5 x 5 matrix."
        }
        let coordinateInstruction = if let matrixRow {
            "Return matrixRow=\(matrixRow) with every matrixColumn 0...4 exactly once. Make the 5 actions meaningfully distinct."
        } else {
            "Return every coordinate exactly once. Make the 25 actions meaningfully distinct."
        }

        return """
        You generate a player decision board for SwiftHistoria using a small-model-friendly strict JSON contract.
        \(boardInstruction) Every cell must be executable NOW from the supplied state; do not recommend powers, institutions, territories, wars, elections, treaties, secessions, or mergers that the player does not currently possess or qualify for.

        SEEDS AND IDENTITY
        worldSeed=\(worldSeed)
        turnSeed=\(turnSeed)
        stateFingerprint=\(stateFingerprint)
        round=\(state.round); date=\(state.gameDate); startDate=\(state.startDate)
        scenario=\(state.scenarioID) | \(state.scenarioName) | \(state.scenarioDescription)
        player=\(state.country.name) (\(state.country.code)); gameMode=\(state.gameMode.rawValue); language=\(language)
        The seeds identify this campaign. Do not invent new random state; derive variety from the state and turnSeed.

        MATRIX AXES
        Rows (matrixRow): 0 Economy, 1 Society/Governance, 2 Diplomacy, 3 Security/Military, 4 Sovereignty/Territory.
        Columns (matrixColumn): 0 Stabilize, 1 Prepare, 2 Cooperate, 3 Project, 4 Transform.
        \(coordinateInstruction)

        PLAYER POWER AND VICTORY
        administrativeCapacity=\(state.administrativeCapacity)/120; stability=\(state.stability)/100; worldTension=\(state.worldTension)/100
        government=\(state.economicLedger.governmentType); approval=\(format(state.economicLedger.publicApprovalPercent)); nextElectionRound=\(state.economicLedger.nextElectionRound)
        budgets military=\(format(state.budgetMilitarySlider * 100)), services=\(format(state.budgetServicesSlider * 100)), diplomacy=\(format(state.budgetDiplomacySlider * 100)), research=\(format(state.budgetResearchSlider * 100))
        techEra=\(state.techEra); researchPoints=\(state.researchPoints); militaryUnits=\(state.militaryUnits.sorted { $0.key < $1.key })
        victoryStatus=\(state.victoryStatus.rawValue)
        Objectives:
        \(objectives.isEmpty ? "- Sandbox: no fixed victory objectives." : objectives)

        PLAYER ECONOMIC LEDGER
        \(ledgerLine(code: state.country.code, ledger: state.economicLedger))

        ALL COUNTRY STATES (shared world snapshot)
        \(countries)

        DYNAMIC COUNTRIES AND SOVEREIGNTY
        \(state.dynamicCountries.sorted { $0.key < $1.key }.map { "- \($0.key)=\($0.value)" }.joined(separator: "\n").nilIfEmpty ?? "- none")
        Region occupations: \(state.regionOccupations.sorted { $0.key < $1.key })
        Fallout regions: \(state.nuclearFalloutRegions.sorted())
        Active region conflicts:
        \(conflicts.nilIfEmpty ?? "- none")

        DEPLOYED ARMIES AND BUILDINGS
        Armies: \(armies.nilIfEmpty ?? "none")
        Buildings: \(buildings.nilIfEmpty ?? "none")

        EXACT POLITICAL DIRECTIVES CURRENTLY AVAILABLE
        Use actionKind="political" only with a detail copied exactly from this list:
        \(political.nilIfEmpty ?? "- none; use ordinary policy actions in the Society row")

        EXACT REGIONAL/MILITARY DIRECTIVES CURRENTLY AVAILABLE
        Use actionKind="regional" or a region-targeted actionKind="military" only with detail, targetRegionID, and cost copied exactly from this list:
        \(regional.nilIfEmpty ?? "- none; use non-territorial security policy")

        VALID DIPLOMACY TARGET COUNTRY CODES
        For actionKind="diplomacy", targetCountryCode MUST be exactly one of these codes (3-letter uppercase). Do not abbreviate, truncate, or invent codes:
        \(diplomacyTargetCodes(state: state).joined(separator: ", "))

        RECENT CAUSAL HISTORY
        \(timeline.nilIfEmpty ?? "- none")

        ACTION MEMORY
        \(actionMemory.nilIfEmpty ?? "- none")

        HARD ELIGIBILITY RULES
        - You are generating matrixRow=\(matrixRow ?? -1). Every cell MUST have this exact matrixRow value.
        - administrativeCost must be an integer > 0 and <= \(state.administrativeCapacity) for every cell. Cost is paid when selected.
        - actionKind is exactly policy, political, diplomacy, military, regional, or sovereignty.
        - diplomacy requires targetCountryCode from the VALID DIPLOMACY TARGET COUNTRY CODES list above. Do NOT use codes that are not on that list.
        - political and region-targeted actions must use the exact allowed directive strings above.
        - military action requires real units; invasion requires an exact listed region directive.
        - actionKind=sovereignty requires sovereigntyChange. Secession/new-country requires stored rebel/conflict pressure plus exact sourceCodes and regionIDs. Merge requires at least two sourceCodes with relationship >= 40. Dissolution requires rebelControl >= 70. Otherwise keep row 4 as autonomy, recognition, border, federal, or integration policy without sovereigntyChange.
        - Align the board with objectives, armies, budgets, government type, diplomatic relationships, conflicts, and victory/defeat risks.
        - Do not repeat a recently resolved action. Do not promise guaranteed outcomes.
        - Write title/detail/rationale in \(language). Keep enum strings and codes unchanged.

        Return one JSON object only, no markdown, with this exact shape:
        {"suggestions":[{"matrixRow":0,"matrixColumn":0,"title":"...","detail":"...","rationale":"...","urgency":"immediate|soon|opportunistic","primaryMechanic":"economic-resilience|market-confidence|internal-stability|security-anxiety|diplomatic-leverage|military-readiness|world-tension","secondaryMechanic":"same enum","actionKind":"policy|political|diplomacy|military|regional|sovereignty","administrativeCost":10,"targetCountryCode":null,"targetRegionID":null,"sovereigntyChange":null}]}
        sovereigntyChange shape when legally applicable: {"kind":"secession|new-country|merge|dissolution","name":"...","regionIDs":["existing-id"],"sourceCodes":["existing-code"],"targetCode":"3-6 uppercase letters"}.
        """
    }

    private static func diplomacyTargetCodes(state: NativeCampaignState) -> [String] {
        NativeStrategyContextDatabase.strategicCountryCodes(for: state)
            .filter { $0 != "GLOBAL" && $0 != state.country.code }
    }

    private static func regionalOptions(state: NativeCampaignState) -> [String] {
        let relevantRegionIDs = Set(
            GeopoliticalMapData.regions(forCountryCode: state.country.code).map(\.id) +
                state.regionOccupations.keys + state.regionConflicts.keys + state.nuclearFalloutRegions +
                NativeStrategyContextDatabase.adjacentCountryCodes(for: state.country.code).flatMap {
                    GeopoliticalMapData.regions(forCountryCode: $0).prefix(2).map(\.id)
                }
        )
        return relevantRegionIDs.sorted().flatMap { regionID -> [String] in
            guard let region = GeopoliticalMapData.regionByID[regionID] else { return [] }
            return NativeQuickActionCatalog.regionalActions(for: region, state: state)
                .filter { $0.cost <= state.administrativeCapacity }
                .map { "- detail=\($0.directiveTemplate) | targetRegionID=\(regionID) | cost=\($0.cost) | effects=\($0.primaryEffects.joined(separator: ","))" }
        }
    }

    private static func countryStateLines(state: NativeCampaignState) -> [String] {
        NativeStrategyContextDatabase.strategicCountryCodes(for: state).filter { $0 != "GLOBAL" }.map { code in
            let ledger = state.economicLedgers[code]
            let ai = state.aiCountryStates[code]
            let relation = ai?.relationshipScores[state.country.code] ?? 0
            let profile = NativeWorldSimulator.profile(for: code, state: state, aiState: ai).id
            let seed = NativeWorldSimulator.countrySeed(worldSeed: NativeWorldSimulator.resolvedWorldSeed(for: state), countryCode: code)
            let posture = ai.map { "doctrine=\($0.doctrine.rawValue), priority=\($0.budgetPriority.rawValue), agenda=\($0.agendaProgress)% \($0.multiTurnAgenda), relationToPlayer=\(relation), profile=\(profile), seed=\(seed), step=\($0.decisionStep), last=\($0.lastAIActionSummary)" } ?? "profile=\(profile), seed=\(seed)"
            return "- \(code): \(ledger.map { ledgerLine(code: code, ledger: $0) } ?? "ledger unavailable"); \(posture)"
        }
    }

    private static func ledgerLine(code: String, ledger: NativeEconomicLedger) -> String {
        "\(code) GDP=\(format(ledger.nominalGDPTrillions))T growth=\(format(ledger.realGrowthPercent)) inflation=\(format(ledger.inflationPercent)) budget=\(format(ledger.budgetBalancePercentGDP)) debt=\(format(ledger.publicDebtPercentGDP)) trade=\(format(ledger.tradeBalancePercentGDP)) unemployment=\(format(ledger.unemploymentPercent)) fiscalSpace=\(ledger.fiscalSpaceIndex) security=\(format(ledger.securityIndex)) rebels=\(format(ledger.rebelControlPercent)) government=\(ledger.governmentType) approval=\(format(ledger.publicApprovalPercent)) resources=\(ledger.resourceReserves.sorted { $0.key < $1.key })"
    }

    private static func format(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}

// MARK: - 4096 deterministic CPU profiles

struct NativeCPUDecisionProfile: Codable, Hashable, Identifiable {
    let id: Int

    init(id: Int) {
        self.id = max(0, min(4095, id))
    }

    /// Six independent two-bit traits yield exactly 4^6 = 4096 profiles.
    var risk: Int {
        trait(0)
    }

    var patience: Int {
        trait(1)
    }

    var cooperation: Int {
        trait(2)
    }

    var force: Int {
        trait(3)
    }

    var welfare: Int {
        trait(4)
    }

    var sovereignty: Int {
        trait(5)
    }

    private func trait(_ index: Int) -> Int {
        (id >> (index * 2)) & 0b11
    }
}

struct NativeAICountryDecision: Codable, Hashable {
    var countryCode: String
    var actionTitle: String
    var actionDescription: String
    var effectTarget: String
    var effectTrack: String
    var effectMagnitude: Int
    var effectSummary: String
    var hexLeverCode: String?
    var matrixRow: Int = 0
    var matrixColumn: Int = 0
    var sovereigntyChange: NativeSovereigntyChange? = nil
}

private struct NativeCPUCandidate: Hashable {
    let decision: NativeAICountryDecision
    let baseWeight: Int
}

enum NativeWorldSimulator {
    static let profileCount = 4096
    private static let visibleDecisionLimit = 24

    static func makeCampaignSeed() -> UInt64 {
        UInt64.random(in: 1 ... UInt64.max)
    }

    static func stableSeed(_ text: String) -> UInt64 {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return hash == 0 ? 1 : hash
    }

    static func resolvedWorldSeed(for state: NativeCampaignState) -> UInt64 {
        state.worldSeed == 0
            ? stableSeed("legacy|\(state.scenarioID)|\(state.country.code)|\(state.startDate)")
            : state.worldSeed
    }

    static func countrySeed(worldSeed: UInt64, countryCode: String) -> UInt64 {
        mixed(worldSeed ^ stableSeed(countryCode.uppercased()))
    }

    static func turnSeed(worldSeed: UInt64, round: Int) -> UInt64 {
        mixed(worldSeed &+ UInt64(max(0, round)) &* 0x9E37_79B9_7F4A_7C15)
    }

    static func profile(
        for countryCode: String,
        state: NativeCampaignState,
        aiState: NativeAICountryState? = nil
    ) -> NativeCPUDecisionProfile {
        if let profileID = aiState?.decisionProfileID, (0 ..< profileCount).contains(profileID) {
            return NativeCPUDecisionProfile(id: profileID)
        }
        let seed = aiState?.decisionSeed ?? 0
        let resolvedSeed = seed == 0
            ? countrySeed(worldSeed: resolvedWorldSeed(for: state), countryCode: countryCode)
            : seed
        return NativeCPUDecisionProfile(id: Int(resolvedSeed & 0x0FFF))
    }

    static func matrix(
        for countryCode: String,
        state: NativeCampaignState,
        aiState: NativeAICountryState
    ) -> [NativeAICountryDecision] {
        NativeDecisionMatrixRow.allCases.flatMap { row in
            NativeDecisionMatrixColumn.allCases.map { column in
                candidate(for: countryCode, row: row, column: column, state: state, aiState: aiState).decision
            }
        }
    }

    /// Every CPU country chooses from its own 5 x 5 matrix without an LLM.
    /// Pure country evaluation runs concurrently; results are sorted before use,
    /// so scheduling cannot change a campaign replay.
    static func simulate(
        state: NativeCampaignState,
        months: Int
    ) async -> (events: [NativeCampaignEvent], updatedStates: [String: NativeAICountryState]) {
        let actorCodes = state.aiCountryStates.keys.filter { $0 != state.country.code }.sorted()
        guard !actorCodes.isEmpty else { return ([], [:]) }
        let worldSeed = resolvedWorldSeed(for: state)

        let results = await withTaskGroup(of: (String, NativeAICountryDecision, NativeAICountryState, Int).self) { group in
            for code in actorCodes {
                guard let aiState = state.aiCountryStates[code] else { continue }
                group.addTask {
                    let decision = chooseDecision(for: code, state: state, aiState: aiState, worldSeed: worldSeed)
                    var updated = aiState
                    let seed = aiState.decisionSeed == 0 ? countrySeed(worldSeed: worldSeed, countryCode: code) : aiState.decisionSeed
                    let profile = profile(for: code, state: state, aiState: aiState)
                    updated.decisionSeed = seed
                    updated.decisionProfileID = profile.id
                    updated.decisionStep = aiState.decisionStep + 1
                    updated.turnsSinceAIAction = 0
                    updated.lastAIActionSummary = "\(decision.actionTitle): \(decision.actionDescription)"
                    updated.agendaProgress = min(100, aiState.agendaProgress + 2 + decision.matrixColumn)
                    updateRelationships(for: decision, state: state, aiState: &updated)
                    let salience = decisionSalience(decision, state: state)
                    return (code, decision, updated, salience)
                }
            }

            var collected: [(String, NativeAICountryDecision, NativeAICountryState, Int)] = []
            for await result in group {
                collected.append(result)
            }
            return collected.sorted { $0.0 < $1.0 }
        }

        let ranked = results.sorted {
            if $0.3 == $1.3 { return $0.0 < $1.0 }
            return $0.3 > $1.3
        }
        let visible = Array(ranked.prefix(visibleDecisionLimit))
        let hidden = ranked.dropFirst(visibleDecisionLimit)
        let targetDate = NativeGameEngine.advance(date: state.gameDate, months: months)
        var events = visible.map { event(for: $0.1, targetDate: targetDate, round: state.round + 1, playerCode: state.country.code) }

        if !hidden.isEmpty {
            let net = hidden.map { $0.1.effectTrack == NativeStrategicTrack.worldTension.rawValue ? $0.1.effectMagnitude : 0 }.reduce(0, +)
            let magnitude = max(-3, min(3, net / max(1, hidden.count / 8)))
            let eventID = "worldsim-\(state.round + 1)-aggregate"
            events.append(NativeCampaignEvent(
                date: targetDate,
                description: "\(hidden.count) autonomous governments executed lower-salience decisions from their national policy matrices; trade, diplomacy, security, and sovereignty pressures propagated through the shared world state.",
                id: eventID,
                importance: abs(magnitude) >= 2 ? .major : .minor,
                kind: .world,
                linkedActionIDs: [],
                notable: false,
                playerRelated: false,
                strategicEffects: [NativeStrategicEffect(
                    date: targetDate,
                    eventId: eventID,
                    id: "\(eventID)-effect",
                    magnitude: magnitude,
                    summary: "Aggregate autonomous decisions shift international pressure.",
                    target: "GLOBAL",
                    track: .worldTension
                )],
                title: "Autonomous world policy cycle"
            ))
        }

        return (events, Dictionary(uniqueKeysWithValues: results.map { ($0.0, $0.2) }))
    }

    static func chooseDecision(
        for countryCode: String,
        state: NativeCampaignState,
        aiState: NativeAICountryState,
        worldSeed: UInt64? = nil
    ) -> NativeAICountryDecision {
        let resolvedSeed = aiState.decisionSeed == 0
            ? countrySeed(worldSeed: worldSeed ?? resolvedWorldSeed(for: state), countryCode: countryCode)
            : aiState.decisionSeed
        let profile = profile(for: countryCode, state: state, aiState: aiState)
        let candidates = NativeDecisionMatrixRow.allCases.flatMap { row in
            NativeDecisionMatrixColumn.allCases.map { column in
                candidate(for: countryCode, row: row, column: column, state: state, aiState: aiState)
            }
        }
        let heuristicScores = candidates.map {
            max(1, $0.baseWeight + adaptiveWeight(
                decision: $0.decision,
                profile: profile,
                countryCode: countryCode,
                aiState: aiState,
                state: state
            ))
        }
        let scores = NativeDecisionPolicyAccelerator.shared.scores(
            heuristicScores: heuristicScores,
            profile: profile,
            countryCode: countryCode,
            state: state
        )
        var generator = NativeSplitMix64(seed: mixed(resolvedSeed ^ UInt64(aiState.decisionStep) ^ turnSeed(worldSeed: worldSeed ?? resolvedWorldSeed(for: state), round: state.round)))
        let total = max(1, scores.reduce(0, +))
        var roll = Int(generator.next() % UInt64(total))
        for (index, score) in scores.enumerated() {
            if roll < score { return candidates[index].decision }
            roll -= score
        }
        return candidates[0].decision
    }

    private static func candidate(
        for code: String,
        row: NativeDecisionMatrixRow,
        column: NativeDecisionMatrixColumn,
        state: NativeCampaignState,
        aiState: NativeAICountryState
    ) -> NativeCPUCandidate {
        let friendly = relationshipTarget(aiState: aiState, preferFriendly: true, excluding: code) ?? state.country.code
        let hostile = relationshipTarget(aiState: aiState, preferFriendly: false, excluding: code) ?? state.country.code
        let selfTarget = code
        let columnLabel = column.title.lowercased()
        var title: String
        var detail: String
        var target = selfTarget
        var track = NativeStrategicTrack.internalStability
        var magnitude = min(3, 1 + column.rawValue / 2)
        var sovereigntyChange: NativeSovereigntyChange?

        switch row {
        case .economy:
            title = "\(code) launches \(columnLabel) economic program"
            detail = "\(code) aligns fiscal space, infrastructure, employment, and trade instruments with its \(columnLabel) posture."
            track = column == .cooperate ? .marketConfidence : .economicResilience
            target = column == .cooperate ? friendly : selfTarget
        case .society:
            title = "\(code) advances \(columnLabel) social compact"
            detail = "\(code) adjusts services, administrative delivery, public security, and political legitimacy through a bounded \(columnLabel) program."
            track = (state.economicLedgers[code]?.securityIndex ?? 50) < 45 ? .securityAnxiety : .internalStability
        case .diplomacy:
            target = column.rawValue >= NativeDecisionMatrixColumn.project.rawValue ? hostile : friendly
            title = "\(code) opens \(columnLabel) diplomacy with \(target)"
            detail = "\(code) uses its current relationships and trade agenda to pursue a \(columnLabel) diplomatic initiative with \(target)."
            track = .diplomaticLeverage
            magnitude = target == hostile && column.rawValue >= 3 ? -magnitude : magnitude
        case .security:
            target = column.rawValue >= NativeDecisionMatrixColumn.project.rawValue ? hostile : selfTarget
            title = "\(code) adopts \(columnLabel) security posture"
            detail = "\(code) rebalances readiness, border logistics, and deterrence toward \(target) without exceeding its stored force posture."
            track = column.rawValue >= 3 ? .worldTension : .militaryReadiness
        case .sovereignty:
            let opportunity = sovereigntyOpportunity(for: code, friendlyTarget: friendly, state: state, aiState: aiState, column: column)
            sovereigntyChange = opportunity.change
            target = opportunity.target
            title = opportunity.title
            detail = opportunity.detail
            track = opportunity.change == nil ? .diplomaticLeverage : .worldTension
        }

        let summary = "\(title) changes \(track.rawValue) for \(target) by \(magnitude)."
        return NativeCPUCandidate(
            decision: NativeAICountryDecision(
                countryCode: code,
                actionTitle: title,
                actionDescription: detail,
                effectTarget: target,
                effectTrack: track.rawValue,
                effectMagnitude: max(-3, min(3, magnitude)),
                effectSummary: summary,
                hexLeverCode: nil,
                matrixRow: row.rawValue,
                matrixColumn: column.rawValue,
                sovereigntyChange: sovereigntyChange
            ),
            baseWeight: 8
        )
    }

    private static func adaptiveWeight(
        decision: NativeAICountryDecision,
        profile: NativeCPUDecisionProfile,
        countryCode: String,
        aiState: NativeAICountryState,
        state: NativeCampaignState
    ) -> Int {
        guard let row = NativeDecisionMatrixRow(rawValue: decision.matrixRow),
              let column = NativeDecisionMatrixColumn(rawValue: decision.matrixColumn)
        else { return 0 }
        let ledger = state.economicLedgers[countryCode]
        var score = 0

        switch row {
        case .economy:
            if aiState.budgetPriority == .growth { score += 18 }
            if (ledger?.realGrowthPercent ?? 0) < 1 { score += 16 }
            score += profile.patience * 3
        case .society:
            if aiState.budgetPriority == .stability { score += 18 }
            if (ledger?.securityIndex ?? 50) < 50 { score += 18 }
            if (ledger?.rebelControlPercent ?? 0) > 10 { score += 14 }
            score += profile.welfare * 4
        case .diplomacy:
            if aiState.budgetPriority == .diplomacy || aiState.doctrine == .collaborative { score += 18 }
            score += profile.cooperation * 5
            if state.worldTension > 65, column.rawValue <= 2 { score += 10 }
        case .security:
            if aiState.budgetPriority == .military || aiState.doctrine == .expansionist { score += 18 }
            if state.worldTension > 55 { score += 14 }
            if (aiState.relationshipScores.values.min() ?? 0) < -35 { score += 12 }
            score += profile.force * 5
        case .sovereignty:
            if (ledger?.rebelControlPercent ?? 0) > 20 || decision.sovereigntyChange != nil { score += 24 }
            score += profile.sovereignty * 5
        }

        let riskDistance = abs(column.rawValue - profile.risk)
        score += max(0, 12 - riskDistance * 4)
        if aiState.agendaProgress >= 70, column == .transform { score += 18 }
        if aiState.turnsSinceAIAction >= 3 { score += min(12, aiState.turnsSinceAIAction * 2) }
        let interactionNoise = Int(stableSeed("\(countryCode)|\(decision.effectTarget)|\(state.round)|\(decision.matrixRow)|\(decision.matrixColumn)") % 9)
        return score + interactionNoise
    }

    private static func relationshipTarget(
        aiState: NativeAICountryState,
        preferFriendly: Bool,
        excluding code: String
    ) -> String? {
        aiState.relationshipScores.filter { $0.key != code }.min {
            if $0.value == $1.value { return $0.key < $1.key }
            return preferFriendly ? $0.value > $1.value : $0.value < $1.value
        }?.key
    }

    private static func sovereigntyOpportunity(
        for code: String,
        friendlyTarget: String,
        state: NativeCampaignState,
        aiState: NativeAICountryState,
        column: NativeDecisionMatrixColumn
    ) -> (title: String, detail: String, target: String, change: NativeSovereigntyChange?) {
        let rebelliousRegion = GeopoliticalMapData.regions(forCountryCode: code).first { region in
            (state.regionConflicts[region.id]?.intensity ?? 0) >= 3
        }
        let rebelPressure = state.economicLedgers[code]?.rebelControlPercent ?? 0
        if column.rawValue >= 3, rebelPressure >= 20, let region = rebelliousRegion {
            let targetCode = generatedCountryCode(source: code, regionID: region.id)
            let change = NativeSovereigntyChange(
                kind: .secession,
                name: "\(region.name) Republic",
                regionIDs: [region.id],
                sourceCodes: [code],
                targetCode: targetCode
            )
            return (
                "\(region.name) declares separate sovereignty",
                "Stored insurgency and territorial pressure in \(region.name) produces a formal secession from \(code).",
                targetCode,
                change
            )
        }

        let relation = aiState.relationshipScores[friendlyTarget] ?? 0
        if column == .transform,
           relation >= 70,
           NativeStrategyContextDatabase.adjacentCountryCodes(for: code).contains(friendlyTarget)
        {
            let change = NativeSovereigntyChange(
                kind: .merge,
                name: "\(code)-\(friendlyTarget) Union",
                regionIDs: [],
                sourceCodes: [code, friendlyTarget],
                targetCode: code
            )
            return (
                "\(code) and \(friendlyTarget) approve political union",
                "Deep stored cooperation and adjacency culminate in a negotiated merger led by \(code).",
                code,
                change
            )
        }

        let verbs = ["reviews autonomy guarantees", "maps federal contingencies", "opens integration talks", "projects border guarantees", "renegotiates its territorial compact"]
        let verb = verbs[column.rawValue]
        return (
            "\(code) \(verb)",
            "\(code) uses the \(column.title.lowercased()) lane to adjust recognition, autonomy, borders, and integration without creating an unsupported state change.",
            code,
            nil
        )
    }

    private static func generatedCountryCode(source: String, regionID: String) -> String {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        var value = stableSeed("\(source)|\(regionID)")
        return String((0 ..< 4).map { _ in
            defer { value /= 26 }
            return alphabet[Int(value % 26)]
        })
    }

    private static func updateRelationships(
        for decision: NativeAICountryDecision,
        state: NativeCampaignState,
        aiState: inout NativeAICountryState
    ) {
        guard decision.effectTarget != decision.countryCode,
              decision.effectTarget != "GLOBAL",
              state.aiCountryStates[decision.effectTarget] != nil || decision.effectTarget == state.country.code
        else { return }
        let delta: Int = switch NativeDecisionMatrixRow(rawValue: decision.matrixRow) {
        case .diplomacy: decision.effectMagnitude >= 0 ? 3 : -3
        case .security: -max(1, decision.matrixColumn)
        case .sovereignty: decision.sovereigntyChange == nil ? 1 : -2
        default: 0
        }
        aiState.relationshipScores[decision.effectTarget] = max(
            -100,
            min(100, (aiState.relationshipScores[decision.effectTarget] ?? 0) + delta)
        )
    }

    private static func decisionSalience(_ decision: NativeAICountryDecision, state: NativeCampaignState) -> Int {
        var score = abs(decision.effectMagnitude) * 10 + decision.matrixColumn * 4
        if decision.effectTarget == state.country.code { score += 80 }
        if decision.sovereigntyChange != nil { score += 100 }
        if NativeStrategyContextDatabase.adjacentCountryCodes(for: state.country.code).contains(decision.countryCode) { score += 30 }
        score += Int((state.economicLedgers[decision.countryCode]?.nominalGDPTrillions ?? 0) * 2)
        return score
    }

    private static func event(
        for decision: NativeAICountryDecision,
        targetDate: String,
        round: Int,
        playerCode: String
    ) -> NativeCampaignEvent {
        let eventID = "worldsim-\(round)-\(decision.countryCode)"
        return NativeCampaignEvent(
            date: targetDate,
            description: decision.actionDescription,
            id: eventID,
            importance: decision.sovereigntyChange != nil || abs(decision.effectMagnitude) >= 3 ? .severe : (abs(decision.effectMagnitude) >= 2 ? .major : .minor),
            kind: decision.sovereigntyChange == nil ? .world : .crisis,
            linkedActionIDs: [],
            notable: true,
            playerRelated: decision.effectTarget == playerCode || decision.countryCode == playerCode,
            strategicEffects: [NativeStrategicEffect(
                date: targetDate,
                eventId: eventID,
                id: "\(eventID)-effect",
                magnitude: decision.effectMagnitude,
                summary: decision.effectSummary,
                target: decision.effectTarget,
                track: NativeStrategicTrack(rawValue: decision.effectTrack) ?? .worldTension
            )],
            title: decision.actionTitle,
            hexLeverCode: decision.hexLeverCode,
            sovereigntyChange: decision.sovereigntyChange
        )
    }

    private static func mixed(_ value: UInt64) -> UInt64 {
        var z = value &+ 0x9E37_79B9_7F4A_7C15
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

private struct NativeSplitMix64 {
    var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

// MARK: - Optional Neural Engine policy adapter

/// If a compiled `CountryPolicyAgent.mlmodelc` is bundled, Core ML scores the
/// 25 CPU cells with `.cpuAndNeuralEngine`. The deterministic heuristic remains
/// the replay-safe fallback and is also used when the model is absent.
private final class NativeDecisionPolicyAccelerator: @unchecked Sendable {
    static let shared = NativeDecisionPolicyAccelerator()

    #if canImport(CoreML)
        private let model: MLModel?
    #endif

    private init() {
        #if canImport(CoreML)
            guard let url = Bundle.main.url(forResource: "CountryPolicyAgent", withExtension: "mlmodelc") else {
                model = nil
                return
            }
            let configuration = MLModelConfiguration()
            configuration.computeUnits = .cpuAndNeuralEngine
            model = try? MLModel(contentsOf: url, configuration: configuration)
        #endif
    }

    func scores(
        heuristicScores: [Int],
        profile: NativeCPUDecisionProfile,
        countryCode: String,
        state: NativeCampaignState
    ) -> [Int] {
        #if canImport(CoreML)
            guard let model,
                  let features = try? MLMultiArray(shape: [32], dataType: .double)
            else { return heuristicScores }
            let profileValues = [profile.risk, profile.patience, profile.cooperation, profile.force, profile.welfare, profile.sovereignty]
            let ledger = state.economicLedgers[countryCode]
            let values: [Double] = profileValues.map { Double($0) / 3.0 } + [
                Double(state.worldTension) / 100.0,
                (ledger?.realGrowthPercent ?? 0) / 20.0,
                (ledger?.securityIndex ?? 50) / 100.0,
                (ledger?.rebelControlPercent ?? 0) / 100.0,
                Double(state.round % 64) / 64.0
            ] + heuristicScores.prefix(21).map { Double($0) / 100.0 }
            for index in 0 ..< min(values.count, features.count) {
                features[index] = NSNumber(value: values[index])
            }
            guard let provider = try? MLDictionaryFeatureProvider(dictionary: ["features": features]),
                  let output = try? model.prediction(from: provider),
                  let logits = output.featureValue(for: "scores")?.multiArrayValue,
                  logits.count >= heuristicScores.count
            else { return heuristicScores }
            return heuristicScores.indices.map { index in
                max(1, heuristicScores[index] + Int(truncating: logits[index]))
            }
        #else
            return heuristicScores
        #endif
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
