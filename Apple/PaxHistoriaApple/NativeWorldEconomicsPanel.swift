import Foundation
import SwiftUI

private enum EconomicSortOption: String, CaseIterable, Identifiable {
    case featured
    case gdp
    case growth
    case debt
    case fiscalSpace
    case security

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .featured: "Featured"
        case .gdp: "GDP"
        case .growth: "Growth"
        case .debt: "Debt/GDP"
        case .fiscalSpace: "Fiscal Space"
        case .security: "Security"
        }
    }

    var systemImage: String {
        switch self {
        case .featured: "star.fill"
        case .gdp: "dollarsign.circle"
        case .growth: "chart.line.uptrend.xyaxis"
        case .debt: "creditcard"
        case .fiscalSpace: "gauge.with.needle"
        case .security: "shield.fill"
        }
    }
}

private enum EconomicFilterOption: String, CaseIterable, Identifiable {
    case all
    case majorPowers
    case highGrowth
    case fiscalStress
    case classified

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .all: "All"
        case .majorPowers: "Major Powers"
        case .highGrowth: "High Growth"
        case .fiscalStress: "Fiscal Stress"
        case .classified: "Classified"
        }
    }
}

private enum EconomicDisplayMode: String, CaseIterable, Identifiable {
    case cards
    case table

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .cards: "Dossier Cards"
        case .table: "Compact Ledger Table"
        }
    }

    var systemImage: String {
        switch self {
        case .cards: "rectangle.grid.1x2.fill"
        case .table: "tablecells"
        }
    }
}

private struct EconomicLedgerRowModel: Identifiable {
    let code: String
    let name: String
    let flag: String
    let ledger: NativeEconomicLedger
    let isPlayer: Bool
    let isGlobal: Bool
    let isClassified: Bool
    let visibilityLabel: String?
    let featuredOrder: Int

    var id: String {
        code
    }
}

struct NativeWorldEconomicsPanel: View {
    @ObservedObject var store: NativeCampaignStore
    let state: NativeCampaignState

    @State private var sortOption: EconomicSortOption = .featured
    @State private var filterOption: EconomicFilterOption = .all
    @State private var displayMode: EconomicDisplayMode = .cards
    @State private var searchQuery = ""
    @State private var expandedTableCode: String?

    static let featuredCountryCodes = ["GLOBAL", "USA", "CHN", "BRA", "DEU", "JPN", "GBR", "FRA", "IND", "RUS", "ZAF", "AUS"]

    static func displayedCountryCodes(for state: NativeCampaignState) -> [String] {
        featuredCountryCodes + state.dynamicCountries.keys
            .filter { !featuredCountryCodes.contains($0) }
            .sorted()
    }

    private var allRows: [EconomicLedgerRowModel] {
        let countryCodes = Self.displayedCountryCodes(for: state)
        let scenario = NativeScenarioCatalog.scenario(for: state.scenarioID)

        return countryCodes.enumerated().map { index, code in
            let visibility = NativeGameEngine.intelVisibility(forCountryCode: code, in: state)
            let isGlobal = code == "GLOBAL"
            let isPlayer = code == state.country.code
            let isClassified = visibility == .hidden && !isGlobal && !isPlayer
            let baseLedger = state.economicLedgers[code] ?? NativeEconomicLedger.starting(
                for: PlayerCountry(code: code, name: code),
                scenario: scenario
            )
            let resolvedName = (code == "RUS" && state.scenarioID == "soviet-triumph")
                ? "Soviet Union"
                : CountryNameResolver.name(forCode: code, in: state)
            let flag = isGlobal ? "🌐" : (CountryCatalog.flagEmoji(forAlpha3: code) ?? "🏳️")

            return EconomicLedgerRowModel(
                code: code,
                name: resolvedName,
                flag: flag,
                ledger: isClassified ? maskedLedger() : baseLedger,
                isPlayer: isPlayer,
                isGlobal: isGlobal,
                isClassified: isClassified,
                visibilityLabel: isClassified ? "CLASSIFIED" : (visibility == .partial ? "PARTIAL INTEL" : nil),
                featuredOrder: index
            )
        }
    }

    private var filteredAndSortedRows: [EconomicLedgerRowModel] {
        let trimmedQuery = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        let filtered = allRows.filter { row in
            guard matchesFilter(row, filter: filterOption) else { return false }
            guard !trimmedQuery.isEmpty else { return true }
            return row.name.lowercased().contains(trimmedQuery) || row.code.lowercased().contains(trimmedQuery)
        }

        return filtered.sorted { lhs, rhs in
            if sortOption == .featured {
                return lhs.featuredOrder < rhs.featuredOrder
            }
            if lhs.isGlobal != rhs.isGlobal {
                return lhs.isGlobal
            }
            if lhs.isClassified != rhs.isClassified {
                return !lhs.isClassified
            }
            if lhs.isClassified, rhs.isClassified {
                return lhs.featuredOrder < rhs.featuredOrder
            }

            switch sortOption {
            case .featured:
                return lhs.featuredOrder < rhs.featuredOrder
            case .gdp:
                return compare(lhs.ledger.nominalGDPTrillions, rhs.ledger.nominalGDPTrillions, lhs: lhs, rhs: rhs)
            case .growth:
                return compare(lhs.ledger.realGrowthPercent, rhs.ledger.realGrowthPercent, lhs: lhs, rhs: rhs)
            case .debt:
                return compare(lhs.ledger.publicDebtPercentGDP, rhs.ledger.publicDebtPercentGDP, lhs: lhs, rhs: rhs)
            case .fiscalSpace:
                return compare(Double(lhs.ledger.fiscalSpaceIndex), Double(rhs.ledger.fiscalSpaceIndex), lhs: lhs, rhs: rhs)
            case .security:
                return compare(lhs.ledger.securityIndex, rhs.ledger.securityIndex, lhs: lhs, rhs: rhs)
            }
        }
    }

    private func compare(_ lhsValue: Double, _ rhsValue: Double, lhs: EconomicLedgerRowModel, rhs: EconomicLedgerRowModel) -> Bool {
        if lhsValue == rhsValue {
            if lhs.isPlayer != rhs.isPlayer {
                return lhs.isPlayer
            }
            return lhs.featuredOrder < rhs.featuredOrder
        }
        return lhsValue > rhsValue
    }

    private func matchesFilter(_ row: EconomicLedgerRowModel, filter: EconomicFilterOption) -> Bool {
        switch filter {
        case .all:
            true
        case .majorPowers:
            !row.isClassified && (row.ledger.nominalGDPTrillions >= 2.0 || row.isGlobal || row.isPlayer)
        case .highGrowth:
            !row.isClassified && row.ledger.realGrowthPercent >= 2.5
        case .fiscalStress:
            !row.isClassified && (
                row.ledger.publicDebtPercentGDP >= 90.0
                    || row.ledger.budgetBalancePercentGDP <= -4.0
                    || row.ledger.fiscalSpaceIndex < 45
            )
        case .classified:
            row.isClassified
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PlayerBudgetPanel(store: store, state: state)
                .padding(.bottom, 4)

            NativeResearchAndForcesPanel(store: store, state: state)
                .padding(.bottom, 4)

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("GLOBAL ECONOMIC DOSSIER")
                            .font(NativeWarRoomTheme.labelFont(.caption, weight: .bold))
                            .foregroundStyle(NativeWarRoomTheme.brass)
                            .tracking(1.6)
                        Text("Sovereign Ledgers & Strategic Reserves")
                            .font(NativeWarRoomTheme.displayFont(.title3, weight: .semibold))
                            .foregroundStyle(NativeWarRoomTheme.ink)
                    }
                    Spacer()
                    Text("ROUND \(state.round)")
                        .font(NativeWarRoomTheme.labelFont(.caption2, weight: .bold))
                        .foregroundStyle(NativeWarRoomTheme.brass)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(NativeWarRoomTheme.brass.opacity(0.12), in: Capsule())
                        .overlay {
                            Capsule().stroke(NativeWarRoomTheme.brass.opacity(0.3), lineWidth: 1)
                        }
                }

                Text("Projections of fiscal space, GDP growth, inflation, public debt, resource reserves, and security capacity across major polities.")
                    .font(NativeWarRoomTheme.bodyFont(.subheadline))
                    .foregroundStyle(NativeWarRoomTheme.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)

                ledgerControlsBar
            }

            let rows = filteredAndSortedRows
            if rows.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("No polities match the current ledger filter.", systemImage: "magnifyingglass")
                        .font(NativeWarRoomTheme.labelFont(.caption, weight: .bold))
                        .foregroundStyle(NativeWarRoomTheme.alertAmber)
                    Button("Reset Ledger Filters") {
                        searchQuery = ""
                        filterOption = .all
                        sortOption = .featured
                    }
                    .buttonStyle(.bordered)
                    .tint(NativeWarRoomTheme.brass)
                    .font(NativeWarRoomTheme.labelFont(.caption2, weight: .bold))
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .warRoomDossier(borderColor: NativeWarRoomTheme.brass.opacity(0.2), cornerRadius: 10)
            } else if displayMode == .cards {
                VStack(spacing: 12) {
                    ForEach(rows) { row in
                        ExpansionEconomicCard(
                            code: row.code,
                            name: row.name,
                            ledger: row.ledger,
                            isPlayer: row.isPlayer,
                            scenarioID: state.scenarioID,
                            visibilityLabel: row.visibilityLabel
                        )
                    }
                }
            } else {
                compactLedgerTable(rows: rows)
            }
        }
        .padding(.vertical, 8)
        .accessibilityIdentifier("native-world-economics-panel")
    }

    private var ledgerControlsBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.caption)
                        .foregroundStyle(NativeWarRoomTheme.brass)
                    TextField("Search country or ISO code...", text: $searchQuery)
                        .font(NativeWarRoomTheme.labelFont(.caption, weight: .regular))
                        .foregroundStyle(NativeWarRoomTheme.ink)
                        .textFieldStyle(.plain)
                        .accessibilityIdentifier("native-economics-search")
                    if !searchQuery.isEmpty {
                        Button {
                            searchQuery = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(NativeWarRoomTheme.mutedInk)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear country filter")
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(NativeWarRoomTheme.blackboard.opacity(0.65), in: RoundedRectangle(cornerRadius: 6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(NativeWarRoomTheme.brass.opacity(0.24), lineWidth: 1)
                }

                HStack(spacing: 4) {
                    ForEach(EconomicDisplayMode.allCases) { mode in
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                displayMode = mode
                            }
                        } label: {
                            Label(mode.title, systemImage: mode.systemImage)
                                .font(NativeWarRoomTheme.labelFont(.caption2, weight: .bold))
                                .padding(.horizontal, 9)
                                .padding(.vertical, 6)
                                .background(
                                    displayMode == mode
                                        ? NativeWarRoomTheme.brass.opacity(0.22)
                                        : NativeWarRoomTheme.blackboard.opacity(0.45),
                                    in: RoundedRectangle(cornerRadius: 5)
                                )
                                .overlay {
                                    RoundedRectangle(cornerRadius: 5)
                                        .stroke(
                                            displayMode == mode
                                                ? NativeWarRoomTheme.brass.opacity(0.55)
                                                : NativeWarRoomTheme.brass.opacity(0.14),
                                            lineWidth: 1
                                        )
                                }
                                .foregroundStyle(displayMode == mode ? NativeWarRoomTheme.ink : NativeWarRoomTheme.mutedInk)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("native-economics-mode-\(mode.rawValue)")
                    }
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    Text("SORT")
                        .font(NativeWarRoomTheme.labelFont(.caption2, weight: .bold))
                        .foregroundStyle(NativeWarRoomTheme.oxidizedBrass)
                        .padding(.trailing, 2)

                    ForEach(EconomicSortOption.allCases) { option in
                        Button {
                            sortOption = option
                        } label: {
                            Label(option.title, systemImage: option.systemImage)
                                .font(NativeWarRoomTheme.labelFont(.caption2, weight: .bold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(
                                    sortOption == option
                                        ? NativeWarRoomTheme.brass.opacity(0.22)
                                        : NativeWarRoomTheme.olivePanel.opacity(0.55),
                                    in: Capsule()
                                )
                                .overlay {
                                    Capsule().stroke(
                                        sortOption == option
                                            ? NativeWarRoomTheme.brass.opacity(0.6)
                                            : NativeWarRoomTheme.brass.opacity(0.14),
                                        lineWidth: 1
                                    )
                                }
                                .foregroundStyle(sortOption == option ? NativeWarRoomTheme.ink : NativeWarRoomTheme.mutedInk)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("native-economics-sort-\(option.rawValue)")
                    }
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    Text("FILTER")
                        .font(NativeWarRoomTheme.labelFont(.caption2, weight: .bold))
                        .foregroundStyle(NativeWarRoomTheme.oxidizedBrass)
                        .padding(.trailing, 2)

                    ForEach(EconomicFilterOption.allCases) { filter in
                        let count = allRows.filter { matchesFilter($0, filter: filter) }.count
                        Button {
                            filterOption = filter
                        } label: {
                            HStack(spacing: 4) {
                                Text(filter.title)
                                Text("\(count)")
                                    .foregroundStyle(filterOption == filter ? NativeWarRoomTheme.brass : NativeWarRoomTheme.mutedInk.opacity(0.8))
                            }
                            .font(NativeWarRoomTheme.labelFont(.caption2, weight: .bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(
                                filterOption == filter
                                    ? NativeWarRoomTheme.signalCyan.opacity(0.2)
                                    : NativeWarRoomTheme.olivePanel.opacity(0.45),
                                in: Capsule()
                            )
                            .overlay {
                                Capsule().stroke(
                                    filterOption == filter
                                        ? NativeWarRoomTheme.signalCyan.opacity(0.55)
                                        : NativeWarRoomTheme.brass.opacity(0.14),
                                    lineWidth: 1
                                )
                            }
                            .foregroundStyle(filterOption == filter ? NativeWarRoomTheme.ink : NativeWarRoomTheme.mutedInk)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("native-economics-filter-\(filter.rawValue)")
                    }
                }
            }
        }
        .padding(12)
        .warRoomDossier(borderColor: NativeWarRoomTheme.brass.opacity(0.24), cornerRadius: 10)
    }

    private func compactLedgerTable(rows: [EconomicLedgerRowModel]) -> some View {
        ScrollView(.horizontal, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Text("#")
                        .frame(width: 28, alignment: .leading)
                    Text("POLITY")
                        .frame(width: 170, alignment: .leading)
                    Text("GDP")
                        .frame(width: 72, alignment: .trailing)
                    Text("GROWTH")
                        .frame(width: 68, alignment: .trailing)
                    Text("BUDGET")
                        .frame(width: 68, alignment: .trailing)
                    Text("DEBT")
                        .frame(width: 62, alignment: .trailing)
                    Text("INFL.")
                        .frame(width: 60, alignment: .trailing)
                    Text("SEC.")
                        .frame(width: 58, alignment: .trailing)
                    Text("APPR.")
                        .frame(width: 58, alignment: .trailing)
                }
                .font(NativeWarRoomTheme.labelFont(.caption2, weight: .bold))
                .foregroundStyle(NativeWarRoomTheme.brass)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(NativeWarRoomTheme.olivePanel.opacity(0.95))

                Rectangle()
                    .fill(NativeWarRoomTheme.brass.opacity(0.28))
                    .frame(height: 1)

                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    let isExpanded = expandedTableCode == row.code
                    VStack(spacing: 0) {
                        Button {
                            guard !row.isClassified else { return }
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                expandedTableCode = isExpanded ? nil : row.code
                            }
                        } label: {
                            HStack(spacing: 10) {
                                Text("\(index + 1)")
                                    .foregroundStyle(row.isPlayer ? NativeWarRoomTheme.brass : NativeWarRoomTheme.mutedInk)
                                    .frame(width: 28, alignment: .leading)

                                HStack(spacing: 6) {
                                    Text(row.flag)
                                        .font(.caption)
                                    Text(row.code)
                                        .foregroundStyle(row.isPlayer ? NativeWarRoomTheme.brass : NativeWarRoomTheme.signalCyan)
                                    Text(row.name)
                                        .foregroundStyle(NativeWarRoomTheme.ink)
                                        .lineLimit(1)
                                }
                                .frame(width: 170, alignment: .leading)

                                if row.isClassified {
                                    Text("CLASSIFIED — INTELLIGENCE GAP")
                                        .foregroundStyle(NativeWarRoomTheme.threatRed.opacity(0.85))
                                        .frame(width: 446, alignment: .leading)
                                } else {
                                    Text(String(format: "$%.2fT", row.ledger.nominalGDPTrillions))
                                        .foregroundStyle(NativeWarRoomTheme.ink)
                                        .frame(width: 72, alignment: .trailing)

                                    Text(String(format: "%+.1f%%", row.ledger.realGrowthPercent))
                                        .foregroundStyle(row.ledger.realGrowthPercent >= 0 ? NativeWarRoomTheme.fieldGreen : NativeWarRoomTheme.threatRed)
                                        .frame(width: 68, alignment: .trailing)

                                    Text(String(format: "%+.1f%%", row.ledger.budgetBalancePercentGDP))
                                        .foregroundStyle(row.ledger.budgetBalancePercentGDP >= -3 ? NativeWarRoomTheme.fieldGreen : NativeWarRoomTheme.threatRed)
                                        .frame(width: 68, alignment: .trailing)

                                    Text(String(format: "%.0f%%", row.ledger.publicDebtPercentGDP))
                                        .foregroundStyle(row.ledger.publicDebtPercentGDP <= 90 ? NativeWarRoomTheme.ink : NativeWarRoomTheme.alertAmber)
                                        .frame(width: 62, alignment: .trailing)

                                    Text(String(format: "%.1f%%", row.ledger.inflationPercent))
                                        .foregroundStyle(row.ledger.inflationPercent <= 5 ? NativeWarRoomTheme.ink : NativeWarRoomTheme.alertAmber)
                                        .frame(width: 60, alignment: .trailing)

                                    Text(row.isGlobal ? "—" : String(format: "%.0f", row.ledger.securityIndex))
                                        .foregroundStyle(row.isGlobal ? NativeWarRoomTheme.mutedInk : NativeWarRoomTheme.statusColor(for: Int(row.ledger.securityIndex.rounded())))
                                        .frame(width: 58, alignment: .trailing)

                                    Text(row.isGlobal ? "—" : String(format: "%.0f%%", row.ledger.publicApprovalPercent))
                                        .foregroundStyle(row.isGlobal ? NativeWarRoomTheme.mutedInk : (row.ledger.publicApprovalPercent >= 50 ? NativeWarRoomTheme.fieldGreen : NativeWarRoomTheme.threatRed))
                                        .frame(width: 58, alignment: .trailing)
                                }
                            }
                            .font(NativeWarRoomTheme.labelFont(.caption2, weight: row.isPlayer ? .bold : .medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(
                                row.isPlayer
                                    ? NativeWarRoomTheme.brass.opacity(0.14)
                                    : (index.isMultiple(of: 2) ? NativeWarRoomTheme.graphite.opacity(0.75) : NativeWarRoomTheme.archiveShadow.opacity(0.85))
                            )
                        }
                        .buttonStyle(.plain)

                        if isExpanded, !row.isClassified {
                            ExpansionEconomicCard(
                                code: row.code,
                                name: row.name,
                                ledger: row.ledger,
                                isPlayer: row.isPlayer,
                                scenarioID: state.scenarioID,
                                visibilityLabel: row.visibilityLabel,
                                initiallyExpanded: true
                            )
                            .padding(10)
                            .background(NativeWarRoomTheme.blackboard.opacity(0.75))
                        }

                        Rectangle()
                            .fill(NativeWarRoomTheme.brass.opacity(0.12))
                            .frame(height: 1)
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(NativeWarRoomTheme.brass.opacity(0.28), lineWidth: 1)
        }
        .accessibilityIdentifier("native-world-economics-table")
    }

    /// Returns a zeroed-out ledger for fog-of-war masking.
    private func maskedLedger() -> NativeEconomicLedger {
        NativeEconomicLedger(
            budgetBalancePercentGDP: 0,
            entries: [],
            fiscalSpaceIndex: 0,
            inflationPercent: 0,
            nominalGDPTrillions: 0,
            publicDebtPercentGDP: 0,
            realGrowthPercent: 0,
            tradeBalancePercentGDP: 0,
            unemploymentPercent: 0,
            securityIndex: 0,
            rebelControlPercent: 0,
            resourceReserves: [:]
        )
    }
}

struct ExpansionEconomicCard: View {
    let code: String
    let name: String
    let ledger: NativeEconomicLedger
    let isPlayer: Bool
    let scenarioID: String
    var visibilityLabel: String?
    var initiallyExpanded = false

    @State private var isExpanded = false
    @State private var didApplyInitialExpansion = false

    private var isGlobal: Bool {
        code == "GLOBAL"
    }

    private var flagBadge: String {
        isGlobal ? "🌐" : (CountryCatalog.flagEmoji(forAlpha3: code) ?? "🏳️")
    }

    private var themeColor: Color {
        if isPlayer {
            return NativeWarRoomTheme.brass
        }
        if isGlobal {
            return NativeWarRoomTheme.signalCyan
        }
        return NativeWarRoomTheme.parchment
    }

    private var tagBackground: Color {
        if isPlayer {
            return NativeWarRoomTheme.brass.opacity(0.18)
        }
        if isGlobal {
            return NativeWarRoomTheme.signalCyan.opacity(0.16)
        }
        return NativeWarRoomTheme.olivePanel.opacity(0.65)
    }

    private var tagStroke: Color {
        if isPlayer {
            return NativeWarRoomTheme.brass.opacity(0.5)
        }
        if isGlobal {
            return NativeWarRoomTheme.signalCyan.opacity(0.42)
        }
        return NativeWarRoomTheme.brass.opacity(0.18)
    }

    private var orderedResourceKeys: [String] {
        let preferredOrder = ["oil", "minerals", "agriculture", "rare_earths"]
        let extra = ledger.resourceReserves.keys.filter { !preferredOrder.contains($0) }.sorted()
        return preferredOrder.filter { ledger.resourceReserves[$0] != nil } + extra
    }

    var body: some View {
        VStack(spacing: 0) {
            Button {
                if visibilityLabel != "CLASSIFIED" {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        isExpanded.toggle()
                    }
                }
            } label: {
                HStack(spacing: 12) {
                    HStack(spacing: 5) {
                        Text(flagBadge)
                            .font(.caption)
                        Text(code)
                            .font(NativeWarRoomTheme.labelFont(.caption, weight: .bold))
                            .foregroundStyle(themeColor)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(tagBackground, in: Capsule())
                    .overlay {
                        Capsule().stroke(tagStroke, lineWidth: 1)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(name)
                                .font(NativeWarRoomTheme.displayFont(.headline, weight: .semibold))
                                .foregroundStyle(NativeWarRoomTheme.ink)
                                .lineLimit(1)
                            if isPlayer {
                                Text("PLAYER")
                                    .font(NativeWarRoomTheme.labelFont(.caption2, weight: .bold))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(NativeWarRoomTheme.brass.opacity(0.22), in: RoundedRectangle(cornerRadius: 3))
                                    .foregroundStyle(NativeWarRoomTheme.brass)
                            } else if isGlobal {
                                Text("SYSTEM")
                                    .font(NativeWarRoomTheme.labelFont(.caption2, weight: .bold))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(NativeWarRoomTheme.signalCyan.opacity(0.2), in: RoundedRectangle(cornerRadius: 3))
                                    .foregroundStyle(NativeWarRoomTheme.signalCyan)
                            }
                            if let label = visibilityLabel {
                                Text(label)
                                    .font(NativeWarRoomTheme.labelFont(.caption2, weight: .bold))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(NativeWarRoomTheme.threatRed.opacity(0.18), in: RoundedRectangle(cornerRadius: 3))
                                    .foregroundStyle(NativeWarRoomTheme.threatRed)
                            }
                        }

                        if visibilityLabel == "CLASSIFIED" {
                            Text("INTELLIGENCE GAP — DATA REDACTED")
                                .font(NativeWarRoomTheme.labelFont(.caption2, weight: .semibold))
                                .foregroundStyle(NativeWarRoomTheme.threatRed.opacity(0.8))
                        } else {
                            Text("GDP \(String(format: "$%.2fT", ledger.nominalGDPTrillions)) · Growth \(ledger.realGrowthPercent >= 0 ? "+" : "")\(String(format: "%.1f%%", ledger.realGrowthPercent)) · Fiscal \(ledger.fiscalSpaceIndex)/100")
                                .font(NativeWarRoomTheme.labelFont(.caption2, weight: .medium))
                                .foregroundStyle(NativeWarRoomTheme.mutedInk)
                        }
                    }

                    Spacer()

                    if visibilityLabel != "CLASSIFIED" {
                        HStack(spacing: 10) {
                            MiniMetricIndicator(title: "BUDGET", value: String(format: "%+.1f%%", ledger.budgetBalancePercentGDP), isPositive: ledger.budgetBalancePercentGDP >= -3)
                            MiniMetricIndicator(title: "DEBT", value: String(format: "%.0f%%", ledger.publicDebtPercentGDP), isPositive: ledger.publicDebtPercentGDP <= 90)
                        }

                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption)
                            .foregroundStyle(NativeWarRoomTheme.brass)
                    }
                }
                .padding(12)
                .background(
                    Group {
                        if visibilityLabel == "CLASSIFIED" {
                            ClassifiedPatternBackground()
                        } else if isPlayer {
                            NativeWarRoomTheme.olivePanel.opacity(0.72)
                        } else {
                            NativeWarRoomTheme.graphite.opacity(0.65)
                        }
                    }
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isExpanded ? "Collapse \(name) economic details" : "Expand \(name) economic details")
            .accessibilityHint("Shows budget, debt, inflation, strategic reserves, and other national indicators.")
            .overlay {
                if visibilityLabel == "CLASSIFIED" {
                    HStack {
                        Spacer()
                        ClassifiedStampOverlay()
                            .padding(.trailing, 40)
                    }
                    .allowsHitTesting(false)
                }
            }

            if isExpanded {
                Rectangle()
                    .fill(NativeWarRoomTheme.brass.opacity(0.22))
                    .frame(height: 1)

                VStack(alignment: .leading, spacing: 14) {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        DetailMetricRow(title: "Inflation", value: String(format: "%.1f%%", ledger.inflationPercent), systemImage: "chart.line.uptrend.xyaxis", tintColor: themeColor)
                        DetailMetricRow(title: "Unemployment", value: String(format: "%.1f%%", ledger.unemploymentPercent), systemImage: "person.3", tintColor: themeColor)
                        DetailMetricRow(title: "Trade Balance", value: String(format: "%+.1f%%", ledger.tradeBalancePercentGDP), systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right", tintColor: themeColor)
                        DetailMetricRow(title: "Fiscal Space Index", value: "\(ledger.fiscalSpaceIndex)/100", systemImage: "gauge.with.needle", tintColor: themeColor)
                        if !isGlobal {
                            DetailMetricRow(title: "Government", value: ledger.governmentType.capitalized, systemImage: "building.columns.fill", tintColor: themeColor)
                            let approvalLabel = ledger.governmentType == "democracy" ? "Public Approval" : "Regime Support"
                            DetailMetricRow(title: approvalLabel, value: String(format: "%.1f%%", ledger.publicApprovalPercent), systemImage: "hand.thumbsup.fill", tintColor: ledger.publicApprovalPercent >= 50.0 ? NativeWarRoomTheme.fieldGreen : NativeWarRoomTheme.threatRed)
                            DetailMetricRow(title: "Public Security", value: String(format: "%.1f/100", ledger.securityIndex), systemImage: "shield.fill", tintColor: ledger.securityIndex >= 70.0 ? NativeWarRoomTheme.fieldGreen : (ledger.securityIndex >= 45.0 ? NativeWarRoomTheme.alertAmber : NativeWarRoomTheme.threatRed))
                            DetailMetricRow(title: "Insurgency Pressure", value: String(format: "%.1f%%", ledger.rebelControlPercent), systemImage: "flag.fill", tintColor: ledger.rebelControlPercent == 0.0 ? NativeWarRoomTheme.fieldGreen : (ledger.rebelControlPercent < 25.0 ? NativeWarRoomTheme.alertAmber : NativeWarRoomTheme.threatRed))
                        }
                    }

                    if !isGlobal, !ledger.resourceReserves.isEmpty {
                        Rectangle()
                            .fill(NativeWarRoomTheme.brass.opacity(0.18))
                            .frame(height: 1)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("STRATEGIC RESOURCE RESERVES")
                                .font(NativeWarRoomTheme.labelFont(.caption2, weight: .bold))
                                .foregroundStyle(NativeWarRoomTheme.brass)
                                .tracking(1.2)

                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                                ForEach(orderedResourceKeys, id: \.self) { key in
                                    if let value = ledger.resourceReserves[key] {
                                        ResourceReserveGauge(key: key, abundance: value)
                                    }
                                }
                            }
                        }
                    }

                    if !ledger.entries.isEmpty {
                        Rectangle()
                            .fill(NativeWarRoomTheme.brass.opacity(0.18))
                            .frame(height: 1)

                        VStack(alignment: .leading, spacing: 6) {
                            Text("RECENT FISCAL ENTRIES")
                                .font(NativeWarRoomTheme.labelFont(.caption2, weight: .bold))
                                .foregroundStyle(NativeWarRoomTheme.brass)
                                .tracking(1.2)

                            ForEach(ledger.entries.prefix(3)) { entry in
                                HStack {
                                    Text(entry.turnDate)
                                        .font(NativeWarRoomTheme.labelFont(.caption2, weight: .regular))
                                        .foregroundStyle(NativeWarRoomTheme.mutedInk)
                                    Text(entry.summary)
                                        .font(NativeWarRoomTheme.bodyFont(.caption))
                                        .foregroundStyle(NativeWarRoomTheme.ink)
                                        .lineLimit(1)
                                    Spacer()
                                    let growthVal = entry.growthDelta >= 0 ? "+\(String(format: "%.2f", entry.growthDelta))" : String(format: "%.2f", entry.growthDelta)
                                    Text("Growth \(growthVal)%")
                                        .font(NativeWarRoomTheme.labelFont(.caption2, weight: .bold))
                                        .foregroundStyle(entry.growthDelta >= 0 ? NativeWarRoomTheme.fieldGreen : NativeWarRoomTheme.threatRed)
                                }
                                .padding(7)
                                .background(NativeWarRoomTheme.blackboard.opacity(0.45), in: RoundedRectangle(cornerRadius: 5))
                            }
                        }
                    }
                }
                .padding(12)
                .background(NativeWarRoomTheme.archiveShadow.opacity(0.75))
            }
        }
        .warRoomDossier(
            borderColor: isPlayer ? NativeWarRoomTheme.brass.opacity(0.45) : (isGlobal ? NativeWarRoomTheme.signalCyan.opacity(0.35) : NativeWarRoomTheme.brass.opacity(0.18)),
            cornerRadius: 10
        )
        .onAppear {
            if !didApplyInitialExpansion {
                didApplyInitialExpansion = true
                if initiallyExpanded {
                    isExpanded = true
                }
            }
        }
        .accessibilityIdentifier("expansion-economic-card-\(code.lowercased())")
    }
}

private struct ResourceReserveGauge: View {
    let key: String
    let abundance: Double

    private var clamped: Double {
        max(0, min(100, abundance))
    }

    private var metadata: (label: String, icon: String) {
        switch key.lowercased() {
        case "oil": ("Oil", "drop.fill")
        case "minerals": ("Minerals", "mountain.2.fill")
        case "agriculture": ("Agriculture", "leaf.fill")
        case "rare_earths": ("Rare Earths", "cpu.fill")
        default: (key.replacingOccurrences(of: "_", with: " ").capitalized, "cube.box.fill")
        }
    }

    private var gaugeColor: Color {
        if clamped >= 60 {
            return NativeWarRoomTheme.fieldGreen
        }
        if clamped >= 30 {
            return NativeWarRoomTheme.alertAmber
        }
        return NativeWarRoomTheme.threatRed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: metadata.icon)
                    .font(.caption2)
                    .foregroundStyle(gaugeColor)
                Text(metadata.label)
                    .font(NativeWarRoomTheme.labelFont(.caption2, weight: .semibold))
                    .foregroundStyle(NativeWarRoomTheme.ink)
                Spacer()
                Text("\(Int(clamped.rounded()))/100")
                    .font(NativeWarRoomTheme.labelFont(.caption2, weight: .bold))
                    .foregroundStyle(gaugeColor)
            }

            ProgressView(value: clamped, total: 100)
                .tint(gaugeColor)
        }
        .padding(8)
        .background(NativeWarRoomTheme.blackboard.opacity(0.48), in: RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(gaugeColor.opacity(0.24), lineWidth: 1)
        }
    }
}

struct MiniMetricIndicator: View {
    let title: String
    let value: String
    let isPositive: Bool

    var body: some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(title)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(NativeWarRoomTheme.mutedInk)
            Text(value)
                .font(NativeWarRoomTheme.labelFont(.caption2, weight: .bold))
                .foregroundStyle(isPositive ? NativeWarRoomTheme.fieldGreen : NativeWarRoomTheme.threatRed)
        }
    }
}

struct DetailMetricRow: View {
    let title: String
    let value: String
    let systemImage: String
    var tintColor: Color = NativeWarRoomTheme.brass

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.caption)
                .foregroundStyle(tintColor)
                .frame(width: 22, height: 22)
                .background(tintColor.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 11))
                    .foregroundStyle(NativeWarRoomTheme.mutedInk)
                Text(value)
                    .font(NativeWarRoomTheme.labelFont(.caption2, weight: .bold))
                    .foregroundStyle(NativeWarRoomTheme.ink)
            }
            Spacer()
        }
    }
}

struct PlayerBudgetPanel: View {
    @ObservedObject var store: NativeCampaignStore
    let state: NativeCampaignState

    private var militaryImpact: (label: String, color: Color) {
        if state.budgetMilitarySlider > 0.40 {
            return ("Recruiting Forces · Security +", NativeWarRoomTheme.fieldGreen)
        }
        if state.budgetMilitarySlider < 0.20 {
            return ("Force Attrition", NativeWarRoomTheme.threatRed)
        }
        return ("Readiness Steady", NativeWarRoomTheme.alertAmber)
    }

    private var servicesImpact: (label: String, color: Color) {
        if state.budgetServicesSlider > 0.40 {
            return ("Stability & Approval +", NativeWarRoomTheme.fieldGreen)
        }
        if state.budgetServicesSlider < 0.20 {
            return ("Social Strain Risk", NativeWarRoomTheme.threatRed)
        }
        return ("Baseline Welfare", NativeWarRoomTheme.mutedInk)
    }

    private var diplomacyImpact: (label: String, color: Color) {
        if state.budgetDiplomacySlider > 0.35 {
            return ("Leverage & Trade +", NativeWarRoomTheme.signalCyan)
        }
        if state.budgetDiplomacySlider < 0.15 {
            return ("Embassy Retrenchment", NativeWarRoomTheme.alertAmber)
        }
        return ("Normal Envoy Posture", NativeWarRoomTheme.mutedInk)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("DOMESTIC BUDGET ALLOCATION")
                        .font(NativeWarRoomTheme.labelFont(.caption, weight: .bold))
                        .foregroundStyle(NativeWarRoomTheme.brass)
                        .tracking(1.5)
                    Text("Treasury Distribution")
                        .font(NativeWarRoomTheme.displayFont(.headline, weight: .semibold))
                        .foregroundStyle(NativeWarRoomTheme.ink)
                }
                Spacer()
                Text("100% BALANCED")
                    .font(NativeWarRoomTheme.labelFont(.caption2, weight: .bold))
                    .foregroundStyle(NativeWarRoomTheme.fieldGreen)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(NativeWarRoomTheme.fieldGreen.opacity(0.14), in: Capsule())
            }

            Text("Distribute administrative and fiscal capacity. Sliders auto-balance to total 100% and steer monthly national telemetry.")
                .font(NativeWarRoomTheme.bodyFont(.caption))
                .foregroundStyle(NativeWarRoomTheme.mutedInk)
                .fixedSize(horizontal: false, vertical: true)

            proportionalBudgetBar

            Rectangle()
                .fill(NativeWarRoomTheme.brass.opacity(0.18))
                .frame(height: 1)

            VStack(spacing: 10) {
                budgetSliderRow(
                    title: "Military Spending",
                    systemImage: "shield.fill",
                    value: state.budgetMilitarySlider,
                    tint: NativeWarRoomTheme.threatRed,
                    impact: militaryImpact,
                    onChange: { adjustSliders(changed: .military, value: $0) }
                )

                budgetSliderRow(
                    title: "Public Services & Welfare",
                    systemImage: "person.3.fill",
                    value: state.budgetServicesSlider,
                    tint: NativeWarRoomTheme.fieldGreen,
                    impact: servicesImpact,
                    onChange: { adjustSliders(changed: .services, value: $0) }
                )

                budgetSliderRow(
                    title: "Diplomacy & Foreign Aid",
                    systemImage: "globe",
                    value: state.budgetDiplomacySlider,
                    tint: NativeWarRoomTheme.alertAmber,
                    impact: diplomacyImpact,
                    onChange: { adjustSliders(changed: .diplomacy, value: $0) }
                )
            }
        }
        .padding(14)
        .warRoomDossier(borderColor: NativeWarRoomTheme.brass.opacity(0.3), cornerRadius: 10)
    }

    private var proportionalBudgetBar: some View {
        let total = max(0.0001, state.budgetMilitarySlider + state.budgetServicesSlider + state.budgetDiplomacySlider)
        let milFrac = max(0, state.budgetMilitarySlider / total)
        let svcFrac = max(0, state.budgetServicesSlider / total)
        let dipFrac = max(0, state.budgetDiplomacySlider / total)

        return VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(NativeWarRoomTheme.threatRed)
                        .frame(width: max(0, (geo.size.width - 4) * milFrac))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(NativeWarRoomTheme.fieldGreen)
                        .frame(width: max(0, (geo.size.width - 4) * svcFrac))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(NativeWarRoomTheme.alertAmber)
                        .frame(width: max(0, (geo.size.width - 4) * dipFrac))
                }
            }
            .frame(height: 10)
            .padding(2)
            .background(NativeWarRoomTheme.blackboard.opacity(0.7), in: RoundedRectangle(cornerRadius: 5))
            .overlay {
                RoundedRectangle(cornerRadius: 5)
                    .stroke(NativeWarRoomTheme.brass.opacity(0.24), lineWidth: 1)
            }

            HStack(spacing: 12) {
                legendDot(label: "MIL \(Int((milFrac * 100).rounded()))%", color: NativeWarRoomTheme.threatRed)
                legendDot(label: "SVC \(Int((svcFrac * 100).rounded()))%", color: NativeWarRoomTheme.fieldGreen)
                legendDot(label: "DIP \(Int((dipFrac * 100).rounded()))%", color: NativeWarRoomTheme.alertAmber)
                Spacer()
            }
        }
    }

    private func legendDot(label: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(label)
                .font(NativeWarRoomTheme.labelFont(.caption2, weight: .bold))
                .foregroundStyle(NativeWarRoomTheme.mutedInk)
        }
    }

    private func budgetSliderRow(
        title: String,
        systemImage: String,
        value: Double,
        tint: Color,
        impact: (label: String, color: Color),
        onChange: @escaping (Double) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Label(title, systemImage: systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(NativeWarRoomTheme.ink)
                Spacer()
                Text(impact.label)
                    .font(NativeWarRoomTheme.labelFont(.caption2, weight: .bold))
                    .foregroundStyle(impact.color)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(impact.color.opacity(0.14), in: Capsule())
                    .overlay {
                        Capsule().stroke(impact.color.opacity(0.32), lineWidth: 1)
                    }
                Text("\(Int((value * 100).rounded()))%")
                    .font(NativeWarRoomTheme.labelFont(.caption, weight: .bold))
                    .foregroundStyle(NativeWarRoomTheme.brass)
                    .frame(minWidth: 36, alignment: .trailing)
            }
            Slider(value: Binding<Double>(
                get: { value },
                set: { onChange($0) }
            ), in: 0 ... 1)
                .tint(tint)
        }
    }

    enum BudgetType {
        case military, services, diplomacy
    }

    private func adjustSliders(changed: BudgetType, value: Double) {
        let clamped = max(0, min(1.0, value))
        var m = state.budgetMilitarySlider
        var s = state.budgetServicesSlider
        var d = state.budgetDiplomacySlider

        switch changed {
        case .military:
            m = clamped
            let remain = 1.0 - m
            if remain <= 0 {
                s = 0; d = 0
            } else {
                let sum = s + d
                if sum > 0 {
                    s = (s / sum) * remain
                    d = (d / sum) * remain
                } else {
                    s = remain / 2
                    d = remain / 2
                }
            }
        case .services:
            s = clamped
            let remain = 1.0 - s
            if remain <= 0 {
                m = 0; d = 0
            } else {
                let sum = m + d
                if sum > 0 {
                    m = (m / sum) * remain
                    d = (d / sum) * remain
                } else {
                    m = remain / 2
                    d = remain / 2
                }
            }
        case .diplomacy:
            d = clamped
            let remain = 1.0 - d
            if remain <= 0 {
                m = 0; s = 0
            } else {
                let sum = m + s
                if sum > 0 {
                    m = (m / sum) * remain
                    s = (s / sum) * remain
                } else {
                    m = remain / 2
                    s = remain / 2
                }
            }
        }

        let total = m + s + d
        if total > 0 {
            m /= total
            s /= total
            d /= total
        } else {
            m = 0.33
            s = 0.34
            d = 0.33
        }

        store.updateBudgetSliders(military: m, services: s, diplomacy: d)
    }
}

struct NativeResearchAndForcesPanel: View {
    @ObservedObject var store: NativeCampaignStore
    let state: NativeCampaignState

    private var era: NativeTechEra {
        state.techEraTyped
    }

    private var researchProgress: Double {
        guard era.next != nil else { return 1 }
        return min(1, Double(state.researchPoints) / Double(max(1, era.researchThreshold)))
    }

    private var totalUnits: Int {
        state.militaryUnits.values.reduce(0, +)
    }

    private var forceTrend: (title: String, color: Color) {
        if state.budgetMilitarySlider > 0.40 {
            return ("Recruiting", NativeWarRoomTheme.fieldGreen)
        }
        if state.budgetMilitarySlider < 0.20 {
            return ("Attriting", NativeWarRoomTheme.threatRed)
        }
        return ("Holding", NativeWarRoomTheme.alertAmber)
    }

    private var attackSupport: Int {
        state.militaryUnits["armor", default: 0] / 10 + state.militaryUnits["air", default: 0] / 10
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("RESEARCH & FORCE READINESS", systemImage: "atom")
                    .font(NativeWarRoomTheme.labelFont(.subheadline, weight: .bold))
                    .foregroundStyle(NativeWarRoomTheme.brass)
                    .tracking(1.2)
                Spacer()
                Text(era.displayName.uppercased())
                    .font(NativeWarRoomTheme.labelFont(.caption, weight: .bold))
                    .foregroundStyle(NativeWarRoomTheme.fieldGreen)
            }

            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("Technology era")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(NativeWarRoomTheme.ink)
                    Spacer()
                    if let nextEra = era.next {
                        Text("\(state.researchPoints)/\(era.researchThreshold) → \(nextEra.displayName)")
                            .font(NativeWarRoomTheme.labelFont(.caption, weight: .bold))
                            .foregroundStyle(NativeWarRoomTheme.brass)
                    } else {
                        Text("MAXIMUM ERA")
                            .font(NativeWarRoomTheme.labelFont(.caption, weight: .bold))
                            .foregroundStyle(NativeWarRoomTheme.fieldGreen)
                    }
                }

                ProgressView(value: researchProgress)
                    .tint(NativeWarRoomTheme.fieldGreen)
                    .accessibilityLabel("Research progress")
                    .accessibilityValue(era.next == nil ? "Maximum era reached" : "\(state.researchPoints) of \(era.researchThreshold) points")
                    .accessibilityIdentifier("native-research-progress")

                HStack {
                    Label("Independent research allocation", systemImage: "flask.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(NativeWarRoomTheme.ink)
                    Spacer()
                    Text("\(Int((state.budgetResearchSlider * 100).rounded()))%")
                        .font(NativeWarRoomTheme.labelFont(.caption, weight: .bold))
                        .foregroundStyle(NativeWarRoomTheme.brass)
                }

                Slider(
                    value: Binding(
                        get: { state.budgetResearchSlider },
                        set: { store.updateResearchBudget($0) }
                    ),
                    in: 0 ... 1,
                    step: 0.05
                )
                .tint(NativeWarRoomTheme.brass)
                .disabled(era.next == nil)
                .accessibilityLabel("Research allocation")
                .accessibilityValue("\(Int((state.budgetResearchSlider * 100).rounded())) percent")
                .accessibilityHint("Research is tracked separately from the domestic budget allocation.")
                .accessibilityIdentifier("native-research-budget-slider")

                Text(era.next == nil
                    ? "The technology ladder is complete; the allocation is locked."
                    : "Research is independent from the 100% domestic allocation. Higher investment earns era progress faster.")
                    .font(.caption2)
                    .foregroundStyle(NativeWarRoomTheme.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Rectangle()
                .fill(NativeWarRoomTheme.brass.opacity(0.2))
                .frame(height: 1)

            HStack {
                Text("STANDING FORCES")
                    .font(NativeWarRoomTheme.labelFont(.caption, weight: .bold))
                    .foregroundStyle(NativeWarRoomTheme.parchment)
                Spacer()
                Text(forceTrend.title.uppercased())
                    .font(NativeWarRoomTheme.labelFont(.caption2, weight: .bold))
                    .foregroundStyle(forceTrend.color)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(forceTrend.color.opacity(0.14), in: Capsule())
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                NativeForceCountTile(title: "Infantry", systemImage: "figure.walk", count: state.militaryUnits["infantry", default: 0])
                NativeForceCountTile(title: "Armor", systemImage: "shield.lefthalf.filled", count: state.militaryUnits["armor", default: 0])
                NativeForceCountTile(title: "Air", systemImage: "airplane", count: state.militaryUnits["air", default: 0])
                NativeForceCountTile(title: "Naval", systemImage: "ferry.fill", count: state.militaryUnits["naval", default: 0])
            }

            HStack(spacing: 12) {
                Label("\(totalUnits) total", systemImage: "person.3.sequence.fill")
                Label(String(format: "-%0.2f pp growth/month", Double(totalUnits) * 0.01), systemImage: "chart.line.downtrend.xyaxis")
                Label("+\(attackSupport) attack support", systemImage: "scope")
            }
            .font(.caption2)
            .foregroundStyle(NativeWarRoomTheme.mutedInk)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .warRoomDossier(borderColor: NativeWarRoomTheme.fieldGreen.opacity(0.28), cornerRadius: 10)
        .accessibilityIdentifier("native-research-force-panel")
    }
}

private struct NativeForceCountTile: View {
    let title: String
    let systemImage: String
    let count: Int

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(NativeWarRoomTheme.alertAmber)
                .frame(width: 20)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(NativeWarRoomTheme.ink)
            Spacer()
            Text("\(count)")
                .font(NativeWarRoomTheme.labelFont(.caption, weight: .bold))
                .foregroundStyle(NativeWarRoomTheme.brass)
        }
        .padding(8)
        .background(NativeWarRoomTheme.blackboard.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(NativeWarRoomTheme.brass.opacity(0.14), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(count) units")
        .accessibilityIdentifier("native-force-\(title.lowercased())")
    }
}

struct ClassifiedPatternBackground: View {
    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 20
            let strokeWidth: CGFloat = 2
            var path = Path()

            for x in stride(from: -size.height, to: size.width, by: spacing) {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x + size.height, y: size.height))
            }
            context.stroke(path, with: .color(NativeWarRoomTheme.threatRed.opacity(0.08)), lineWidth: strokeWidth)
        }
        .background(NativeWarRoomTheme.blackboard.opacity(0.7))
    }
}

struct ClassifiedStampOverlay: View {
    var body: some View {
        Text("CLASSIFIED — EYES ONLY")
            .font(.system(size: 8, weight: .black, design: .monospaced))
            .foregroundStyle(NativeWarRoomTheme.threatRed.opacity(0.25))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .border(NativeWarRoomTheme.threatRed.opacity(0.25), width: 1)
            .rotationEffect(.degrees(-10))
    }
}
