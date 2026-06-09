import SwiftUI
import Foundation

struct NativeWorldEconomicsPanel: View {
    @ObservedObject var store: NativeCampaignStore
    let state: NativeCampaignState

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PlayerBudgetPanel(store: store, state: state)
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

            let countryCodes = ["GLOBAL", "USA", "CHN", "BRA", "DEU", "JPN", "GBR", "FRA", "IND", "RUS", "ZAF", "AUS"]
            VStack(spacing: 12) {
                ForEach(countryCodes, id: \.self) { code in
                    let ledger = state.economicLedgers[code] ?? NativeEconomicLedger.starting(for: PlayerCountry(code: code, name: code), scenario: NativeScenarioCatalog.scenario(for: state.scenarioID))
                    let resolvedName = (code == "RUS" && state.scenarioID == "soviet-triumph") ? "Soviet Union" : (CountryCatalog.all.first(where: { $0.code == code })?.name ?? (code == "GLOBAL" ? "Global System" : code))

                    ExpansionEconomicCard(
                        code: code,
                        name: resolvedName,
                        ledger: ledger,
                        isPlayer: code == state.country.code,
                        scenarioID: state.scenarioID
                    )
                }
            }
        }
        .padding(.vertical, 8)
        .accessibilityIdentifier("native-world-economics-panel")
    }
}

struct ExpansionEconomicCard: View {
    let code: String
    let name: String
    let ledger: NativeEconomicLedger
    let isPlayer: Bool
    let scenarioID: String

    @State private var isExpanded = false

    private var isGlobal: Bool {
        code == "GLOBAL"
    }

    private var themeColor: Color {
        if isPlayer { return Color.glowingCyan }
        if isGlobal { return Color(hex: "#b862ff") }
        return Color.iceBlue
    }

    private var tagBackground: Color {
        if isPlayer { return Color.glowingCyan.opacity(0.15) }
        if isGlobal { return Color(hex: "#b862ff").opacity(0.15) }
        return Color.white.opacity(0.06)
    }

    private var tagStroke: Color {
        if isPlayer { return Color.glowingCyan.opacity(0.4) }
        if isGlobal { return Color(hex: "#b862ff").opacity(0.4) }
        return Color.white.opacity(0.1)
    }

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isExpanded.toggle()
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
                                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Color.glowingCyan.opacity(0.2), in: RoundedRectangle(cornerRadius: 3))
                                    .foregroundStyle(Color.glowingCyan)
                            } else if isGlobal {
                                Text("SYSTEM")
                                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Color(hex: "#b862ff").opacity(0.2), in: RoundedRectangle(cornerRadius: 3))
                                    .foregroundStyle(Color(hex: "#b862ff"))
                            }
                        }

                        Text("GDP \(String(format: "$%.2fT", ledger.nominalGDPTrillions)) · Growth \(ledger.realGrowthPercent >= 0 ? "+" : "")\(String(format: "%.1f%%", ledger.realGrowthPercent))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    HStack(spacing: 8) {
                        MiniMetricIndicator(title: "BUDGET", value: String(format: "%+.1f%%", ledger.budgetBalancePercentGDP), isPositive: ledger.budgetBalancePercentGDP >= -3)
                        MiniMetricIndicator(title: "DEBT", value: String(format: "%.0f%%", ledger.publicDebtPercentGDP), isPositive: ledger.publicDebtPercentGDP <= 90)
                    }

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .background(isPlayer ? Color.deepSlate.opacity(0.6) : Color.spaceBlack.opacity(0.4))
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider().background(Color.white.opacity(0.08))

                VStack(spacing: 12) {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        DetailMetricRow(title: "Inflation", value: String(format: "%.1f%%", ledger.inflationPercent), systemImage: "chart.line.uptrend.xyaxis", tintColor: themeColor)
                        DetailMetricRow(title: "Unemployment", value: String(format: "%.1f%%", ledger.unemploymentPercent), systemImage: "person.3", tintColor: themeColor)
                        DetailMetricRow(title: "Trade Balance", value: String(format: "%+.1f%%", ledger.tradeBalancePercentGDP), systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right", tintColor: themeColor)
                        DetailMetricRow(title: "Fiscal Space Index", value: "\(ledger.fiscalSpaceIndex)/100", systemImage: "gauge.with.needle", tintColor: themeColor)
                        if !isGlobal {
                            DetailMetricRow(title: "Public Security", value: String(format: "%.1f/100", ledger.securityIndex), systemImage: "shield.fill", tintColor: ledger.securityIndex >= 70.0 ? Color.neonTeal : (ledger.securityIndex >= 45.0 ? Color.alertGold : Color.softRed))
                            DetailMetricRow(title: "Insurgency Pressure", value: String(format: "%.1f%%", ledger.rebelControlPercent), systemImage: "flag.fill", tintColor: ledger.rebelControlPercent == 0.0 ? Color.neonTeal : (ledger.rebelControlPercent < 25.0 ? Color.alertGold : Color.softRed))
                        }
                    }

                    if !ledger.entries.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("RECENT FISCAL ENTRIES")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color.iceBlue)

                            ForEach(ledger.entries.prefix(3)) { entry in
                                HStack {
                                    Text(entry.turnDate)
                                        .font(.system(size: 8, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                    Text(entry.summary)
                                        .font(.system(size: 9))
                                        .foregroundStyle(.white)
                                        .lineLimit(1)
                                    Spacer()
                                    let growthVal = entry.growthDelta >= 0 ? "+\(String(format: "%.2f", entry.growthDelta))" : String(format: "%.2f", entry.growthDelta)
                                    Text("Growth \(growthVal)%")
                                        .font(.system(size: 8, design: .monospaced).weight(.bold))
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
        .glassmorphicCard(borderColor: isPlayer ? Color.glowingCyan.opacity(0.3) : (isGlobal ? Color(hex: "#b862ff").opacity(0.3) : Color.white.opacity(0.08)), cornerRadius: 10)
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
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(isPositive ? Color.neonTeal : Color.softRed)
        }
    }
}

struct DetailMetricRow: View {
    let title: String
    let value: String
    let systemImage: String
    var tintColor: Color = Color.glowingCyan

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.caption)
                .foregroundStyle(tintColor)
                .frame(width: 20, height: 20)
                .background(tintColor.opacity(0.1), in: Circle())

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
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
                    ), in: 0...1)
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
                    ), in: 0...1)
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
                    ), in: 0...1)
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
