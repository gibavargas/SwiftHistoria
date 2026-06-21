import SwiftUI

struct NativeMapScreen: View {
    @ObservedObject var store: NativeCampaignStore
    let onShowOrders: () -> Void
    let onShowAdvisor: () -> Void
    let onShowDiplomacy: () -> Void

    @Environment(\.colorSchemeContrast) private var contrast
    @State private var isConsoleExpanded = false

    var body: some View {
        Group {
            if let state = store.state {
                ZStack(alignment: .top) {
                    NativeGeopoliticalMap(state: state, store: store)
                        .ignoresSafeArea(edges: [.horizontal, .bottom])
                        .id(state.country.code)

                    Color.clear
                        .frame(width: 1, height: 1)
                        .accessibilityElement(children: .ignore)
                        .accessibilityIdentifier("native-map-screen")
                        .accessibilityLabel("Strategic map for \(state.country.name)")
                        .accessibilityHint("Shows the geopolitical map, current status, and command console.")
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                    // Top Floating HUD
                    VStack(spacing: 8) {
                        NativeCompactStatusBar(state: state, latestEvent: state.timeline.first)
                        if let progress = store.turnProgress {
                            NativeTurnProgressPanel(progress: progress)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    #if os(iOS)
                        .padding(.top, 66)
                    #else
                        .padding(.top, 12)
                    #endif

                    #if os(macOS)
                        VStack(spacing: 12) {
                            Spacer()
                            HStack {
                                Spacer()
                                NativeFloatingAdvanceButton(store: store)
                                    .padding(.trailing, 16)
                            }
                        }
                    #endif
                }
                #if os(iOS)
                .safeAreaInset(edge: .bottom, spacing: 8) {
                    VStack(spacing: 8) {
                        NativeMapCommandBar(
                            store: store,
                            highContrast: contrast == .increased,
                            onShowOrders: onShowOrders,
                            onShowAdvisor: onShowAdvisor,
                            onShowDiplomacy: onShowDiplomacy
                        )

                        CommandConsoleDrawer(store: store, isExpanded: $isConsoleExpanded)
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 8)
                }
                #endif
                .task(id: "\(state.country.code)-\(state.round)") {
                    await store.refreshSuggestedActionsIfNeeded()
                }
            } else {
                ContentUnavailableView("No campaign loaded", systemImage: "globe", description: Text("Choose a country to begin."))
                    .accessibilityIdentifier("native-empty-campaign")
            }
        }
        .background(.black)
    }
}

struct CommandConsoleDrawer: View {
    @ObservedObject var store: NativeCampaignStore
    @Binding var isExpanded: Bool
    @State private var selectedConsoleTab: ConsoleTab = .orders

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.up")
                        .font(.headline)
                        .foregroundStyle(Color.glowingCyan)

                    Text(isExpanded ? "Hide orders" : "Orders")
                        .font(.system(.subheadline, design: .monospaced).weight(.bold))
                        .foregroundStyle(.white)

                    if let state = store.state {
                        let plannedCount = state.plannedActions.filter { $0.status == .planned }.count
                        Text("// \(plannedCount) queued")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(plannedCount > 0 ? Color.neonTeal : .secondary)
                    }

                    Spacer()

                    Circle()
                        .fill(isExpanded ? Color.glowingCyan : Color.neonTeal)
                        .frame(width: 8, height: 8)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(Color.deepSlate.opacity(0.95))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isExpanded ? "Collapse directives console" : "Expand directives console")

            if isExpanded {
                Divider()
                    .background(Color.white.opacity(0.1))

                // Tab Selection Strip
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(ConsoleTab.allCases) { tab in
                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                    selectedConsoleTab = tab
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: tab.systemImage)
                                        .font(.caption)
                                    Text(tab.title.uppercased())
                                        .font(.system(.caption2, design: .monospaced).weight(.bold))
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    selectedConsoleTab == tab
                                        ? Color.glowingCyan.opacity(0.18)
                                        : Color.white.opacity(0.04),
                                    in: Capsule()
                                )
                                .overlay {
                                    Capsule()
                                        .stroke(
                                            selectedConsoleTab == tab
                                                ? Color.glowingCyan.opacity(0.4)
                                                : Color.white.opacity(0.08),
                                            lineWidth: 1
                                        )
                                }
                                .foregroundStyle(selectedConsoleTab == tab ? Color.glowingCyan : .secondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Select \(tab.title) operations")
                            .accessibilityIdentifier("console-tab-\(tab.rawValue)")
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
                .background(Color.spaceBlack.opacity(0.95))

                Divider()
                    .background(Color.white.opacity(0.06))

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        switch selectedConsoleTab {
                        case .orders:
                            NativeOrdersEditorPanel(store: store)
                        case .suggestions:
                            NativeSuggestedActionsPanel(store: store)
                        case .advisor:
                            NativeAdvisorPanel(store: store)
                        case .diplomacy:
                            NativeDiplomacyPanel(store: store)
                        case .events:
                            NativeEventsPanel(state: store.state)
                        }
                    }
                    .padding(16)
                }
                .frame(maxHeight: 280)
                .background(Color.spaceBlack.opacity(0.95))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.5), radius: 10, x: 0, y: -4)
    }
}

struct BattleRow: View {
    let name: String
    let intensity: String
    let color: Color

    var body: some View {
        HStack {
            Text(name)
                .font(.caption)
                .foregroundStyle(.primary)
            Spacer()
            Text(intensity.uppercased())
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(color.opacity(0.12), in: Capsule())
                .overlay {
                    Capsule().stroke(color.opacity(0.3), lineWidth: 1)
                }
        }
    }
}

struct TroopRow: View {
    let name: String
    let count: String
    let status: String
    let color: Color

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.primary)
                Text(count)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(status.uppercased())
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
        }
        .padding(.vertical, 2)
    }
}

struct EconomicRow: View {
    let name: String
    let value: String
    let direction: EconomicDirection
    let color: Color

    var body: some View {
        HStack {
            Text(name)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Image(systemName: direction == .up ? "arrow.up.right" : "arrow.down.right")
                .font(.caption)
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(.primary)
        }
        .padding(.vertical, 2)
    }
}

struct NativeTimelineFooter: View {
    @ObservedObject var store: NativeCampaignStore
    let currentYear: Int
    let baseYear: Int
    let onShowEvents: () -> Void

    private var actions: some View {
        HStack(spacing: 12) {
            Button {
                onShowEvents()
            } label: {
                Label("Events", systemImage: "clock")
                    .font(NativeWarRoomTheme.labelFont(.caption))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityIdentifier("native-timeline-events")

            NativeFloatingAdvanceButton(store: store)
        }
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                timelineRail(compact: false)
                    .frame(minWidth: 520, maxWidth: .infinity)
                actions
                    .fixedSize(horizontal: true, vertical: false)
            }

            VStack(alignment: .leading, spacing: 12) {
                timelineRail(compact: true)
                HStack {
                    Spacer()
                    actions
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
        }
        .padding(12)
        .warRoomDossier(borderColor: NativeWarRoomTheme.brass.opacity(0.2), cornerRadius: 10)
    }

    private func timelineRail(compact: Bool) -> some View {
        HStack(spacing: compact ? 8 : 16) {
            Text("TIMELINE")
                .font(.system(.caption, design: .monospaced).weight(.bold))
                .foregroundStyle(Color.glowingCyan)
                .fixedSize(horizontal: true, vertical: false)

            NativeAdaptiveYearRail(
                currentYear: currentYear,
                baseYear: baseYear,
                isEnabled: store.state != nil
            )
            .frame(maxWidth: .infinity, minHeight: 34)
        }
    }
}

private struct NativeAdaptiveYearRail: View {
    let currentYear: Int
    let baseYear: Int
    let isEnabled: Bool
    private let totalYears = 9
    private let minimumLabelSpacing: CGFloat = 54
    private var clampedStep: Int {
        max(0, min(totalYears - 1, currentYear - baseYear))
    }

    private func visibleYearIndexes(for width: CGFloat) -> Set<Int> {
        let maxLabels = max(2, Int(width / minimumLabelSpacing))
        let skip = max(1, Int(ceil(Double(totalYears) / Double(maxLabels))))
        var indexes = Set((0 ..< totalYears).filter { $0 % skip == 0 })
        indexes.insert(0)
        indexes.insert(totalYears - 1)
        indexes.insert(clampedStep)
        return indexes
    }

    var body: some View {
        GeometryReader { geo in
            let railWidth = max(1, geo.size.width - 4)
            let spacing = railWidth / CGFloat(totalYears - 1)
            let visibleIndexes = visibleYearIndexes(for: railWidth)
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.white.opacity(0.15))
                    .frame(height: 2)
                    .offset(y: 18)
                ForEach(0 ..< totalYears, id: \.self) { i in
                    let year = baseYear + i
                    let isCurrent = i == clampedStep
                    let x = CGFloat(i) * spacing + 2
                    VStack(spacing: 4) {
                        if visibleIndexes.contains(i) {
                            Text("\(year)")
                                .font(.system(size: isCurrent ? 11 : 10, design: .monospaced).weight(.bold))
                                .foregroundStyle(isCurrent ? Color.glowingCyan : .secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                                .fixedSize(horizontal: true, vertical: false)
                        } else {
                            Text(" ")
                                .font(.system(size: 10, design: .monospaced).weight(.bold))
                        }
                        Circle()
                            .fill(isCurrent ? Color.glowingCyan : Color.white.opacity(0.2))
                            .frame(width: isCurrent ? 7 : 4, height: isCurrent ? 7 : 4)
                            .shadow(color: isCurrent ? Color.glowingCyan.opacity(0.75) : .clear, radius: 4)
                    }
                    .frame(width: minimumLabelSpacing)
                    .position(x: x, y: 16)
                    .opacity(isEnabled ? 1 : 0.45)
                }
            }
        }
        .frame(height: 34)
    }
}

struct NativeMapHUD: View {
    let state: NativeCampaignState

    private var stabilityTint: Color {
        if state.stability >= 70 { return Color.neonTeal }
        if state.stability >= 40 { return Color.alertGold }
        return Color.softRed
    }

    private var tensionTint: Color {
        if state.worldTension >= 70 { return Color.softRed }
        if state.worldTension >= 45 { return Color.alertGold }
        return Color.neonTeal
    }

    private var aiTint: Color {
        state.aiReadiness.ok ? Color.glowingCyan : Color.softRed
    }

    var body: some View {
        let gdp = Native2010WorldModel.gdpMetric(for: state)
        let ledger = state.economicLedger
        let budgetTint = ledger.budgetBalancePercentGDP >= -3 ? Color.neonTeal : (ledger.budgetBalancePercentGDP >= -7 ? Color.alertGold : Color.softRed)
        let debtTint = ledger.publicDebtPercentGDP <= 70 ? Color.neonTeal : (ledger.publicDebtPercentGDP <= 110 ? Color.alertGold : Color.softRed)
        let inflationTint = ledger.inflationPercent <= 4 ? Color.neonTeal : (ledger.inflationPercent <= 8 ? Color.alertGold : Color.softRed)
        let securityTint = ledger.securityIndex >= 60 ? Color.neonTeal : (ledger.securityIndex >= 35 ? Color.alertGold : Color.softRed)

        VStack(alignment: .leading, spacing: 10) {
            // Nation Header with Date
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.country.name.uppercased())
                        .font(.system(.title3, design: .monospaced).weight(.black))
                        .foregroundStyle(Color.glowingCyan)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text("\(state.gameDate) · ROUND \(state.round)")
                        .font(.system(.caption2, design: .monospaced).weight(.semibold))
                        .foregroundStyle(Color.iceBlue.opacity(0.7))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Image(systemName: "satellite.fill")
                        .foregroundStyle(aiTint)
                        .font(.title3)
                    Text(nativeFormatHUDAvailability(state.aiReadiness.availability))
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(aiTint.opacity(0.8))
                }
            }

            // Critical Posture Bar — Stability + Tension side by side
            HStack(spacing: 10) {
                NativePostureIndicator(
                    label: "STABILITY",
                    value: state.stability,
                    icon: "building.columns",
                    tint: stabilityTint
                )
                NativePostureIndicator(
                    label: "TENSION",
                    value: state.worldTension,
                    icon: "waveform.path.ecg",
                    tint: tensionTint,
                    invertColor: true
                )
            }

            // Economic Vitals — scrollable row
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    NativeStatusChip(text: "Capacity \(state.administrativeCapacity)/100", systemImage: "sparkles", tintColor: state.administrativeCapacity >= 30 ? Color.glowingCyan : Color.softRed)
                    NativeStatusChip(text: "GDP \(gdp.value) (\(gdp.delta))", systemImage: "dollarsign.circle", tintColor: Color.neonTeal)
                    NativeStatusChip(text: "Budget \(nativeFormatSignedPercent(ledger.budgetBalancePercentGDP))", systemImage: "banknote", tintColor: budgetTint)
                    NativeStatusChip(text: "Debt \(nativeFormatPercent(ledger.publicDebtPercentGDP))", systemImage: "creditcard", tintColor: debtTint)
                    NativeStatusChip(text: "Inflation \(nativeFormatPercent(ledger.inflationPercent))", systemImage: "chart.line.uptrend.xyaxis", tintColor: inflationTint)
                    NativeStatusChip(text: "Security \(String(format: "%.0f", ledger.securityIndex))", systemImage: "shield.lefthalf.filled", tintColor: securityTint)
                    NativeStatusChip(text: "Fiscal \(ledger.fiscalSpaceIndex)/100", systemImage: "gauge.with.dots.needle.67percent", tintColor: Color.iceBlue)
                }
                .padding(.vertical, 2)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassmorphicCard(borderColor: .white.opacity(0.12), cornerRadius: 14)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("native-map-hud")
    }
}

struct NativePostureIndicator: View {
    let label: String
    let value: Int
    let icon: String
    let tint: Color
    var invertColor: Bool = false

    private var effectiveTint: Color {
        invertColor ? (value >= 70 ? Color.softRed : (value >= 45 ? Color.alertGold : Color.neonTeal)) : tint
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(effectiveTint)
                Text(label)
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(value)%")
                    .font(.system(size: 13, weight: .black, design: .monospaced))
                    .foregroundStyle(effectiveTint)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.08))
                    Capsule()
                        .fill(effectiveTint.opacity(0.7))
                        .frame(width: geo.size.width * CGFloat(value) / 100.0)
                        .shadow(color: effectiveTint.opacity(0.4), radius: 3)
                }
            }
            .frame(height: 5)
        }
        .padding(10)
        .background(effectiveTint.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(effectiveTint.opacity(0.15), lineWidth: 1)
        }
    }
}

struct NativeFloatingAdvanceButton: View {
    @ObservedObject var store: NativeCampaignStore
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var pendingDirectiveCount: Int {
        store.state?.plannedActions.filter { $0.status == .planned }.count ?? 0
    }

    var body: some View {
        Menu {
            Button("Advance 1 Month") { store.advance(months: 1) }
                .accessibilityIdentifier("native-advance-1")
            Button("Advance 3 Months") { store.advance(months: 3) }
                .accessibilityIdentifier("native-advance-3")
            Button("Advance 1 Year") { store.advance(months: 12) }
                .accessibilityIdentifier("native-advance-12")
        } label: {
            HStack(spacing: 8) {
                if store.isAdvancing {
                    ProgressView()
                        .tint(.white)
                        .controlSize(.small)
                    Text((store.turnProgress?.phase ?? "Advancing...").uppercased())
                        .font(.system(.subheadline, design: .monospaced).weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                } else {
                    Image(systemName: "calendar.badge.clock")
                        .font(.headline)
                        .foregroundStyle(pendingDirectiveCount > 0 ? Color.neonTeal : Color.glowingCyan)
                    Text(pendingDirectiveCount > 0 ? "ADVANCE (\(pendingDirectiveCount))" : "ADVANCE TURN")
                        .font(.system(.subheadline, design: .monospaced).weight(.bold))
                        .foregroundStyle(.white)
                    if pendingDirectiveCount > 0, !reduceMotion {
                        Circle()
                            .fill(Color.neonTeal)
                            .frame(width: 6, height: 6)
                            .scaleEffect(pulse ? 1.3 : 0.7)
                            .opacity(pulse ? 1.0 : 0.4)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.deepSlate.opacity(0.9))
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .stroke(
                        pendingDirectiveCount > 0 ? Color.neonTeal.opacity(0.5) : Color.glowingCyan.opacity(0.35),
                        lineWidth: pendingDirectiveCount > 0 ? 2 : 1.5
                    )
            }
            .shadow(
                color: pendingDirectiveCount > 0 ? Color.neonTeal.opacity(0.35) : Color.glowingCyan.opacity(0.25),
                radius: pendingDirectiveCount > 0 && pulse ? 14 : 10,
                x: 0, y: 0
            )
            .onAppear {
                guard !reduceMotion, pendingDirectiveCount > 0 else { return }
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
        }
        .disabled(store.isAdvancing)
        .accessibilityLabel("Advance time menu")
        .accessibilityIdentifier("native-advance-menu")
    }
}

struct NativeMapCommandBar: View {
    @ObservedObject var store: NativeCampaignStore
    let highContrast: Bool
    let onShowOrders: () -> Void
    let onShowAdvisor: () -> Void
    let onShowDiplomacy: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            NativeAdvanceMenu(store: store)
            NativeCommandButton(title: "Orders", systemImage: "checklist", accessibilityIdentifier: "native-map-command-orders", action: onShowOrders)
            NativeCommandButton(title: "Intel", systemImage: "brain.head.profile", accessibilityIdentifier: "native-map-command-advisor", action: onShowAdvisor)
            NativeCommandButton(title: "Talk", systemImage: "bubble.left.and.bubble.right", accessibilityIdentifier: "native-map-command-diplomacy", action: onShowDiplomacy)
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .background(highContrast ? Color.black.opacity(0.96) : Color.black.opacity(0.64), in: Capsule())
        .overlay {
            Capsule().stroke(.white.opacity(highContrast ? 0.36 : 0.16), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("native-mobile-command-bar")
    }
}

struct NativeCommandButton: View {
    let title: String
    let systemImage: String
    let accessibilityIdentifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.titleAndIcon)
                .font(.system(.caption, design: .monospaced).weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(minWidth: 62, minHeight: 42)
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .accessibilityLabel(title)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

struct NativeAdvanceMenu: View {
    @ObservedObject var store: NativeCampaignStore

    var body: some View {
        Menu {
            Button("1 month") { store.advance(months: 1) }
                .accessibilityIdentifier("native-advance-1")
            Button("3 months") { store.advance(months: 3) }
                .accessibilityIdentifier("native-advance-3")
            Button("1 year") { store.advance(months: 12) }
                .accessibilityIdentifier("native-advance-12")
        } label: {
            if store.isAdvancing {
                VStack(spacing: 2) {
                    ProgressView()
                    Text(store.turnProgress?.phase ?? "Advancing")
                        .font(.system(size: 11, design: .monospaced).weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(minWidth: 52, minHeight: 42)
            } else {
                Label("Advance", systemImage: "calendar.badge.clock")
                    .labelStyle(.titleAndIcon)
                    .font(.system(.caption, design: .monospaced).weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .frame(minWidth: 74, minHeight: 42)
            }
        }
        .buttonStyle(.borderedProminent)
        .disabled(store.isAdvancing)
        .accessibilityLabel("Advance time")
        .accessibilityIdentifier("native-advance-menu")
    }
}

struct TurnTransitionOverlay: View {
    @ObservedObject var store: NativeCampaignStore
    @State private var consoleLogs: [String] = []

    private var engineName: String {
        if let summary = store.turnProgress?.providerSummary {
            return summary.uppercased()
        }
        return store.selectedAIProviderPreference.providerName.uppercased()
    }

    var body: some View {
        ZStack {
            // Semi-transparent command overlay
            Color.black.opacity(0.4)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                // Telemetry Card
                VStack(spacing: 12) {
                    HStack {
                        Image(systemName: "cpu.fill")
                            .foregroundStyle(Color.glowingCyan)
                        Text("SIMULATION ACTIVE // \(engineName)")
                            .font(.system(.caption, design: .monospaced).weight(.bold))
                            .foregroundStyle(Color.glowingCyan)
                    }

                    if let progress = store.turnProgress {
                        Text(progress.phase.uppercased())
                            .font(.system(.title3, design: .monospaced).weight(.black))
                            .foregroundStyle(.white)
                            .padding(.top, 4)

                        ProgressView(value: progress.fraction)
                            .tint(Color.glowingCyan)
                            .frame(maxWidth: 320)
                            .padding(.vertical, 8)

                        Text("\(progress.completedLanes) / \(progress.totalLanes) COGNITIVE LANES RESOLVED")
                            .font(.system(.caption, design: .monospaced).weight(.semibold))
                            .foregroundStyle(Color.iceBlue)
                    } else {
                        Text("CALCULATING GEOPOLITICAL SHIFTS...")
                            .font(.system(.subheadline, design: .monospaced).weight(.bold))
                            .foregroundStyle(.white)
                        ProgressView()
                            .tint(Color.glowingCyan)
                            .padding(.vertical, 10)
                    }
                }
                .padding(20)
                .background(Color.spaceBlack.opacity(0.85))
                .cornerRadius(12)
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.glowingCyan.opacity(0.35), lineWidth: 1.5)
                }
                .shadow(color: Color.glowingCyan.opacity(0.18), radius: 12, x: 0, y: 0)

                // Terminal Drawer
                VStack(alignment: .leading, spacing: 4) {
                    Text("ACTIVE SIMULATION CHANNEL")
                        .font(.system(.caption2, design: .monospaced).weight(.bold))
                        .foregroundStyle(Color.alertGold)
                        .padding(.bottom, 4)

                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(Array(consoleLogs.enumerated()), id: \.offset) { _, log in
                                    Text(log)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(log.contains("lane completed") || log.contains("Resolved") ? Color.neonTeal : Color.white.opacity(0.75))
                                        .id(log)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(height: 120)
                        .onChange(of: consoleLogs) { _, _ in
                            if let last = consoleLogs.last {
                                withAnimation {
                                    proxy.scrollTo(last, anchor: .bottom)
                                }
                            }
                        }
                    }
                }
                .padding(16)
                .background(Color.spaceBlack.opacity(0.9))
                .cornerRadius(10)
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                }
                .frame(maxWidth: 480)
                .padding(.horizontal, 20)

                Spacer()
            }
            .padding(.bottom, 40)
        }
        .onAppear {
            consoleLogs = [
                "SYS // Initializing \(engineName) simulation route...",
                "SYS // Resolving global econ, defense, and advisor telemetry..."
            ]
        }
        .onChange(of: engineName) { _, newEngineName in
            let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
            withAnimation {
                consoleLogs.append("[\(timestamp)] SYS // Active AI route now \(newEngineName)")
            }
        }
        .onChange(of: store.turnProgress?.detail) { _, newDetail in
            if let detail = newDetail, !detail.isEmpty {
                let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
                withAnimation {
                    consoleLogs.append("[\(timestamp)] \(detail)")
                }
            }
        }
    }
}
