import Foundation
import SwiftUI

struct NativeWorldEconomicsPanel: View {
    @ObservedObject var store: NativeCampaignStore
    let state: NativeCampaignState

    static let featuredCountryCodes = ["GLOBAL", "USA", "CHN", "BRA", "DEU", "JPN", "GBR", "FRA", "IND", "RUS", "ZAF", "AUS"]

    static func displayedCountryCodes(for state: NativeCampaignState) -> [String] {
        featuredCountryCodes + state.dynamicCountries.keys
            .filter { !featuredCountryCodes.contains($0) }
            .sorted()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PlayerBudgetPanel(store: store, state: state)
                .padding(.bottom, 6)

            NativeResearchAndForcesPanel(store: store, state: state)
                .padding(.bottom, 6)

            HStack {
                Label("GLOBAL ECONOMIC DOSSIER", systemImage: "chart.bar.xaxis")
                    .font(.system(.subheadline, design: .monospaced).weight(.bold))
                    .foregroundStyle(Color.glowingCyan)
                    .tracking(1.5)
                Spacer()
                Text("ROUND \(state.round)")
                    .font(.system(.caption, design: .monospaced).weight(.bold))
                    .foregroundStyle(.secondary)
            }

            Text("Projections of fiscal space, GDP growth, inflation, public debt, and trade balances across all major game polities. Selected policies dynamically trigger domestic and external adjustments.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            let countryCodes = Self.displayedCountryCodes(for: state)
            VStack(spacing: 12) {
                ForEach(countryCodes, id: \.self) { code in
                    let visibility = NativeGameEngine.intelVisibility(forCountryCode: code, in: state)
                    let ledger = state.economicLedgers[code] ?? NativeEconomicLedger.starting(for: PlayerCountry(code: code, name: code), scenario: NativeScenarioCatalog.scenario(for: state.scenarioID))
                    let resolvedName = (code == "RUS" && state.scenarioID == "soviet-triumph")
                        ? "Soviet Union"
                        : CountryNameResolver.name(forCode: code, in: state)

                    if visibility == .hidden, code != "GLOBAL", code != state.country.code {
                        // Fog of war: rival data is masked
                        ExpansionEconomicCard(
                            code: code,
                            name: resolvedName,
                            ledger: maskedLedger(),
                            isPlayer: false,
                            scenarioID: state.scenarioID,
                            visibilityLabel: "CLASSIFIED"
                        )
                    } else {
                        ExpansionEconomicCard(
                            code: code,
                            name: resolvedName,
                            ledger: ledger,
                            isPlayer: code == state.country.code,
                            scenarioID: state.scenarioID,
                            visibilityLabel: visibility == .partial ? "PARTIAL INTEL" : nil
                        )
                    }
                }
            }
        }
        .padding(.vertical, 8)
        .accessibilityIdentifier("native-world-economics-panel")
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

    @State private var isExpanded = false

    private var isGlobal: Bool {
        code == "GLOBAL"
    }

    private var themeColor: Color {
        if isPlayer { return Color.glowingCyan }
        if isGlobal { return NativeWarRoomTheme.signalCyan }
        return Color.iceBlue
    }

    private var tagBackground: Color {
        if isPlayer { return Color.glowingCyan.opacity(0.15) }
        if isGlobal { return NativeWarRoomTheme.signalCyan.opacity(0.15) }
        return Color.white.opacity(0.06)
    }

    private var tagStroke: Color {
        if isPlayer { return Color.glowingCyan.opacity(0.4) }
        if isGlobal { return NativeWarRoomTheme.signalCyan.opacity(0.4) }
        return Color.white.opacity(0.1)
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
                    Text(code)
                        .font(.system(.caption, design: .monospaced).weight(.bold))
                        .foregroundStyle(themeColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(tagBackground, in: Capsule())
                        .overlay {
                            Capsule().stroke(tagStroke, lineWidth: 1)
                        }

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(name.uppercased())
                                .font(.system(.body, design: .monospaced).weight(.bold))
                                .foregroundStyle(.white)
                            if isPlayer {
                                Text("PLAYER")
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Color.glowingCyan.opacity(0.2), in: RoundedRectangle(cornerRadius: 3))
                                    .foregroundStyle(Color.glowingCyan)
                            } else if isGlobal {
                                Text("SYSTEM")
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(NativeWarRoomTheme.signalCyan.opacity(0.2), in: RoundedRectangle(cornerRadius: 3))
                                    .foregroundStyle(NativeWarRoomTheme.signalCyan)
                            }
                            if let label = visibilityLabel {
                                Text(label)
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Color.softRed.opacity(0.15), in: RoundedRectangle(cornerRadius: 3))
                                    .foregroundStyle(Color.softRed)
                            }
                        }

                        if visibilityLabel == "CLASSIFIED" {
                            Text("INTELLIGENCE GAP — DATA REDACTED")
                                .font(.caption2.monospaced())
                                .foregroundStyle(Color.softRed.opacity(0.7))
                        } else {
                            Text("GDP \(String(format: "$%.2fT", ledger.nominalGDPTrillions)) · Growth \(ledger.realGrowthPercent >= 0 ? "+" : "")\(String(format: "%.1f%%", ledger.realGrowthPercent))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    if visibilityLabel != "CLASSIFIED" {
                        HStack(spacing: 8) {
                            MiniMetricIndicator(title: "BUDGET", value: String(format: "%+.1f%%", ledger.budgetBalancePercentGDP), isPositive: ledger.budgetBalancePercentGDP >= -3)
                            MiniMetricIndicator(title: "DEBT", value: String(format: "%.0f%%", ledger.publicDebtPercentGDP), isPositive: ledger.publicDebtPercentGDP <= 90)
                        }

                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(12)
                .background(
                    Group {
                        if visibilityLabel == "CLASSIFIED" {
                            ClassifiedPatternBackground()
                        } else if isPlayer {
                            Color.deepSlate.opacity(0.6)
                        } else {
                            Color.spaceBlack.opacity(0.4)
                        }
                    }
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isExpanded ? "Collapse \(name) economic details" : "Expand \(name) economic details")
            .accessibilityHint("Shows budget, debt, inflation, and other national indicators.")
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
                Divider().background(Color.white.opacity(0.08))

                VStack(spacing: 12) {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        DetailMetricRow(title: "Inflation", value: String(format: "%.1f%%", ledger.inflationPercent), systemImage: "chart.line.uptrend.xyaxis", tintColor: themeColor)
                        DetailMetricRow(title: "Unemployment", value: String(format: "%.1f%%", ledger.unemploymentPercent), systemImage: "person.3", tintColor: themeColor)
                        DetailMetricRow(title: "Trade Balance", value: String(format: "%+.1f%%", ledger.tradeBalancePercentGDP), systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right", tintColor: themeColor)
                        DetailMetricRow(title: "Fiscal Space Index", value: "\(ledger.fiscalSpaceIndex)/100", systemImage: "gauge.with.needle", tintColor: themeColor)
                        if !isGlobal {
                            DetailMetricRow(title: "Government", value: ledger.governmentType.capitalized, systemImage: "building.columns.fill", tintColor: themeColor)
                            let approvalLabel = ledger.governmentType == "democracy" ? "Public Approval" : "Regime Support"
                            DetailMetricRow(title: approvalLabel, value: String(format: "%.1f%%", ledger.publicApprovalPercent), systemImage: "hand.thumbsup.fill", tintColor: ledger.publicApprovalPercent >= 50.0 ? Color.neonTeal : Color.softRed)
                            DetailMetricRow(title: "Public Security", value: String(format: "%.1f/100", ledger.securityIndex), systemImage: "shield.fill", tintColor: ledger.securityIndex >= 70.0 ? Color.neonTeal : (ledger.securityIndex >= 45.0 ? Color.alertGold : Color.softRed))
                            DetailMetricRow(title: "Insurgency Pressure", value: String(format: "%.1f%%", ledger.rebelControlPercent), systemImage: "flag.fill", tintColor: ledger.rebelControlPercent == 0.0 ? Color.neonTeal : (ledger.rebelControlPercent < 25.0 ? Color.alertGold : Color.softRed))
                        }
                    }

                    if !ledger.entries.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("RECENT FISCAL ENTRIES")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color.iceBlue)

                            ForEach(ledger.entries.prefix(3)) { entry in
                                HStack {
                                    Text(entry.turnDate)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                    Text(entry.summary)
                                        .font(.system(size: 11))
                                        .foregroundStyle(.white)
                                        .lineLimit(1)
                                    Spacer()
                                    let growthVal = entry.growthDelta >= 0 ? "+\(String(format: "%.2f", entry.growthDelta))" : String(format: "%.2f", entry.growthDelta)
                                    Text("Growth \(growthVal)%")
                                        .font(.system(size: 11, design: .monospaced).weight(.bold))
                                        .foregroundStyle(entry.growthDelta >= 0 ? Color.neonTeal : Color.softRed)
                                }
                                .padding(6)
                                .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 4))
                            }
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(12)
                .background(Color.deepSlate.opacity(0.2))
            }
        }
        .glassmorphicCard(borderColor: isPlayer ? Color.glowingCyan.opacity(0.3) : (isGlobal ? NativeWarRoomTheme.signalCyan.opacity(0.3) : Color.white.opacity(0.08)), cornerRadius: 10)
        .accessibilityIdentifier("expansion-economic-card-\(code.lowercased())")
    }
}

struct MiniMetricIndicator: View {
    let title: String
    let value: String
    let isPositive: Bool

    var body: some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(title)
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(isPositive ? Color.neonTeal : Color.softRed)
        }
    }
}

struct DetailMetricRow: View {
    let title: String
    let value: String
    let systemImage: String
    var tintColor: Color = .glowingCyan

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.caption)
                .foregroundStyle(tintColor)
                .frame(width: 20, height: 20)
                .background(tintColor.opacity(0.1), in: Circle())

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
            }
            Spacer()
        }
    }
}

struct PlayerBudgetPanel: View {
    @ObservedObject var store: NativeCampaignStore
    let state: NativeCampaignState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("DOMESTIC BUDGET ALLOCATION")
                .font(.system(.subheadline, design: .monospaced).weight(.bold))
                .foregroundStyle(Color.glowingCyan)
                .tracking(1.5)

            Text("Distribute your administrative and financial resources. Sliders auto-balance to total 100%.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 8) {
                // Military Slider
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Label("Military Spending", systemImage: "shield.fill")
                            .font(.caption)
                            .foregroundStyle(.white)
                        Spacer()
                        Text("\(Int(state.budgetMilitarySlider * 100))%")
                            .font(.system(.caption, design: .monospaced).weight(.bold))
                            .foregroundStyle(Color.glowingCyan)
                    }
                    Slider(value: Binding<Double>(
                        get: { state.budgetMilitarySlider },
                        set: { newValue in
                            adjustSliders(changed: .military, value: newValue)
                        }
                    ), in: 0 ... 1)
                        .tint(Color.softRed)
                }

                // Services Slider
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Label("Public Services & Welfare", systemImage: "person.3.fill")
                            .font(.caption)
                            .foregroundStyle(.white)
                        Spacer()
                        Text("\(Int(state.budgetServicesSlider * 100))%")
                            .font(.system(.caption, design: .monospaced).weight(.bold))
                            .foregroundStyle(Color.glowingCyan)
                    }
                    Slider(value: Binding<Double>(
                        get: { state.budgetServicesSlider },
                        set: { newValue in
                            adjustSliders(changed: .services, value: newValue)
                        }
                    ), in: 0 ... 1)
                        .tint(Color.neonTeal)
                }

                // Diplomacy Slider
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Label("Diplomacy & Foreign Aid", systemImage: "globe")
                            .font(.caption)
                            .foregroundStyle(.white)
                        Spacer()
                        Text("\(Int(state.budgetDiplomacySlider * 100))%")
                            .font(.system(.caption, design: .monospaced).weight(.bold))
                            .foregroundStyle(Color.glowingCyan)
                    }
                    Slider(value: Binding<Double>(
                        get: { state.budgetDiplomacySlider },
                        set: { newValue in
                            adjustSliders(changed: .diplomacy, value: newValue)
                        }
                    ), in: 0 ... 1)
                        .tint(Color.alertGold)
                }
            }
        }
        .padding(12)
        .glassmorphicCard(borderColor: Color.glowingCyan.opacity(0.3), cornerRadius: 10)
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
            return ("Recruiting", .neonTeal)
        }
        if state.budgetMilitarySlider < 0.20 {
            return ("Attriting", .softRed)
        }
        return ("Holding", .alertGold)
    }

    private var attackSupport: Int {
        state.militaryUnits["armor", default: 0] / 10 + state.militaryUnits["air", default: 0] / 10
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("RESEARCH & FORCE READINESS", systemImage: "atom")
                    .font(.system(.subheadline, design: .monospaced).weight(.bold))
                    .foregroundStyle(Color.glowingCyan)
                    .tracking(1.2)
                Spacer()
                Text(era.displayName.uppercased())
                    .font(.system(.caption, design: .monospaced).weight(.bold))
                    .foregroundStyle(Color.neonTeal)
            }

            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("Technology era")
                        .font(.caption)
                        .foregroundStyle(.white)
                    Spacer()
                    if let nextEra = era.next {
                        Text("\(state.researchPoints)/\(era.researchThreshold) → \(nextEra.displayName)")
                            .font(.system(.caption, design: .monospaced).weight(.bold))
                            .foregroundStyle(Color.glowingCyan)
                    } else {
                        Text("MAXIMUM ERA")
                            .font(.system(.caption, design: .monospaced).weight(.bold))
                            .foregroundStyle(Color.neonTeal)
                    }
                }

                ProgressView(value: researchProgress)
                    .tint(Color.neonTeal)
                    .accessibilityLabel("Research progress")
                    .accessibilityValue(era.next == nil ? "Maximum era reached" : "\(state.researchPoints) of \(era.researchThreshold) points")
                    .accessibilityIdentifier("native-research-progress")

                HStack {
                    Label("Independent research allocation", systemImage: "flask.fill")
                        .font(.caption)
                        .foregroundStyle(.white)
                    Spacer()
                    Text("\(Int((state.budgetResearchSlider * 100).rounded()))%")
                        .font(.system(.caption, design: .monospaced).weight(.bold))
                        .foregroundStyle(Color.glowingCyan)
                }

                Slider(
                    value: Binding(
                        get: { state.budgetResearchSlider },
                        set: { store.updateResearchBudget($0) }
                    ),
                    in: 0 ... 1,
                    step: 0.05
                )
                .tint(Color.glowingCyan)
                .disabled(era.next == nil)
                .accessibilityLabel("Research allocation")
                .accessibilityValue("\(Int((state.budgetResearchSlider * 100).rounded())) percent")
                .accessibilityHint("Research is tracked separately from the domestic budget allocation.")
                .accessibilityIdentifier("native-research-budget-slider")

                Text(era.next == nil
                    ? "The technology ladder is complete; the allocation is locked."
                    : "Research is independent from the 100% domestic allocation. Higher investment earns era progress faster.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider().background(Color.white.opacity(0.08))

            HStack {
                Text("STANDING FORCES")
                    .font(.system(.caption, design: .monospaced).weight(.bold))
                    .foregroundStyle(Color.iceBlue)
                Spacer()
                Text(forceTrend.title.uppercased())
                    .font(.system(.caption2, design: .monospaced).weight(.bold))
                    .foregroundStyle(forceTrend.color)
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
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .glassmorphicCard(borderColor: Color.neonTeal.opacity(0.28), cornerRadius: 10)
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
                .foregroundStyle(Color.alertGold)
                .frame(width: 20)
            Text(title)
                .font(.caption)
                .foregroundStyle(.white)
            Spacer()
            Text("\(count)")
                .font(.system(.caption, design: .monospaced).weight(.bold))
                .foregroundStyle(Color.glowingCyan)
        }
        .padding(8)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
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
            context.stroke(path, with: .color(Color.softRed.opacity(0.06)), lineWidth: strokeWidth)
        }
        .background(Color.spaceBlack.opacity(0.6))
    }
}

struct ClassifiedStampOverlay: View {
    var body: some View {
        Text("CLASSIFIED — EYES ONLY")
            .font(.system(size: 8, weight: .black, design: .monospaced))
            .foregroundStyle(Color.softRed.opacity(0.18))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .border(Color.softRed.opacity(0.18), width: 1)
            .rotationEffect(.degrees(-10))
    }
}
