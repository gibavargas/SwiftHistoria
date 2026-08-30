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

                    // Living Atlas masthead: nation state first, urgent briefing second.
                    VStack(spacing: 8) {
                        NativeCompactStatusBar(state: state, latestEvent: state.timeline.first)
                        NativeCrisisBanner(state: state, compact: true)
                        if let progress = store.turnProgress {
                            NativeTurnProgressPanel(progress: progress)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    #if os(iOS)
                        .padding(.top, 52)
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
        .background(NativeWarRoomTheme.blackboard)
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
                HStack(spacing: 10) {
                    Image(systemName: "list.number")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(NativeWarRoomTheme.brass)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("ORDERS DECK")
                            .font(NativeWarRoomTheme.labelFont(.caption2))
                            .foregroundStyle(NativeWarRoomTheme.mutedInk)
                        if let state = store.state {
                            let plannedCount = state.plannedActions.filter { $0.status == .planned }.count
                            Text(plannedCount == 1 ? "1 ORDER READY" : "\(plannedCount) ORDERS READY")
                                .font(NativeWarRoomTheme.displayFont(.subheadline, weight: .semibold))
                                .foregroundStyle(plannedCount > 0 ? NativeWarRoomTheme.ink : NativeWarRoomTheme.mutedInk)
                        }
                    }

                    Spacer()

                    Text(isExpanded ? "CLOSE" : "VIEW")
                        .font(NativeWarRoomTheme.labelFont(.caption2))
                        .foregroundStyle(NativeWarRoomTheme.brass)
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.up")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(NativeWarRoomTheme.brass)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .background(NativeWarRoomTheme.graphite.opacity(0.98))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isExpanded ? "Collapse directives console" : "Expand directives console")
            .accessibilityIdentifier("native-console-toggle")

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
                .background(NativeWarRoomTheme.archiveShadow.opacity(0.98))

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
                .scrollDismissesKeyboard(.interactively)
                .frame(maxHeight: 280)
                .background(NativeWarRoomTheme.archiveShadow.opacity(0.98))
                .accessibilityIdentifier("native-console-content")
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(NativeWarRoomTheme.brass.opacity(0.3), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.5), radius: 10, x: 0, y: -3)
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
    let currentDate: String
    let startDate: String
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
                currentDate: currentDate,
                startDate: startDate,
                currentYear: currentYear,
                baseYear: baseYear,
                isEnabled: store.state != nil
            )
            .frame(maxWidth: .infinity, minHeight: 48)
        }
    }
}

private struct NativeAdaptiveYearRail: View {
    let currentDate: String
    let startDate: String
    let currentYear: Int
    let baseYear: Int
    let isEnabled: Bool
    private let totalYears = 9
    private let minimumLabelSpacing: CGFloat = 86
    private var clampedStep: Int {
        max(0, min(totalYears - 1, currentYear - baseYear))
    }

    private func dateLabel(for index: Int) -> String {
        if index == clampedStep {
            return currentDate
        }
        let steppedDate = NativeGameEngine.advance(date: startDate, months: index * 12)
        return steppedDate == startDate || NativeGameEngine.isValidDate(steppedDate) ? steppedDate : String(baseYear + index)
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
                            VStack(spacing: 1) {
                                Text(String(year))
                                    .font(.system(size: isCurrent ? 11 : 10, design: .monospaced).weight(.bold))
                                    .foregroundStyle(isCurrent ? Color.glowingCyan : .secondary)
                                Text(dateLabel(for: i))
                                    .font(.system(size: isCurrent ? 8 : 7, design: .monospaced).weight(.semibold))
                                    .foregroundStyle(isCurrent ? Color.glowingCyan.opacity(0.9) : .secondary.opacity(0.72))
                            }
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
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
                    .position(x: x, y: 21)
                    .opacity(isEnabled ? 1 : 0.45)
                    .accessibilityLabel("Timeline \(String(year)), \(dateLabel(for: i))")
                }
            }
        }
        .frame(height: 48)
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
                    NativeStatusChip(text: "Capacity \(state.administrativeCapacity)/100", systemImage: "sparkles", tintColor: nativeCapacityColor(for: state.administrativeCapacity))
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

    private func advanceTitle(months: Int, title: String) -> String {
        guard let date = store.state?.gameDate else { return title }
        return "\(title) (\(NativeGameEngine.advance(date: date, months: months)))"
    }

    var body: some View {
        Button {
            store.advance()
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
                        .foregroundStyle(NativeWarRoomTheme.ink)
                    Text(pendingDirectiveCount > 0 ? "ADVANCE 3 MONTHS (\(pendingDirectiveCount))" : "ADVANCE 3 MONTHS")
                        .font(NativeWarRoomTheme.displayFont(.subheadline, weight: .semibold))
                        .foregroundStyle(NativeWarRoomTheme.ink)
                    if pendingDirectiveCount > 0, !reduceMotion {
                        Circle()
                            .fill(NativeWarRoomTheme.alertAmber)
                            .frame(width: 6, height: 6)
                            .scaleEffect(pulse ? 1.3 : 0.7)
                            .opacity(pulse ? 1.0 : 0.4)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 11)
            .background(
                LinearGradient(
                    colors: [
                        NativeWarRoomTheme.threatRed.opacity(0.88),
                        Color(hex: "#6f2f26")
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(NativeWarRoomTheme.alertAmber.opacity(0.72), lineWidth: 1)
                    .padding(2)
            }
            .shadow(color: Color.black.opacity(0.34), radius: 6, x: 0, y: 3)
            .onAppear {
                guard !reduceMotion, pendingDirectiveCount > 0 else { return }
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
        }
        .disabled(store.isAdvancing)
        .accessibilityLabel(advanceTitle(months: NativeCampaignStore.monthsPerTurn, title: "Advance 3 months"))
        .accessibilityIdentifier("native-advance-3")
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
            NativeCommandButton(title: "Orders", systemImage: "checklist", accessibilityIdentifier: "native-map-command-orders", action: onShowOrders)
            NativeCommandButton(title: "Intel", systemImage: "brain.head.profile", accessibilityIdentifier: "native-map-command-advisor", action: onShowAdvisor)
            NativeCommandButton(title: "Talk", systemImage: "bubble.left.and.bubble.right", accessibilityIdentifier: "native-map-command-diplomacy", action: onShowDiplomacy)
            NativeAdvanceMenu(store: store)
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .background(
            highContrast ? NativeWarRoomTheme.blackboard : NativeWarRoomTheme.archiveShadow.opacity(0.96),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(NativeWarRoomTheme.brass.opacity(highContrast ? 0.55 : 0.28), lineWidth: 1)
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
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                Text(title.uppercased())
                    .font(NativeWarRoomTheme.labelFont(.caption2, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundStyle(NativeWarRoomTheme.ink)
            .frame(minWidth: 52, minHeight: 42)
            .background(NativeWarRoomTheme.olivePanel.opacity(0.52), in: RoundedRectangle(cornerRadius: 5))
            .overlay {
                RoundedRectangle(cornerRadius: 5)
                    .stroke(NativeWarRoomTheme.brass.opacity(0.14), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

struct NativeAdvanceMenu: View {
    @ObservedObject var store: NativeCampaignStore

    private func advanceTitle(months: Int, title: String) -> String {
        guard let date = store.state?.gameDate else { return title }
        return "\(title) (\(NativeGameEngine.advance(date: date, months: months)))"
    }

    var body: some View {
        Button {
            store.advance()
        } label: {
            if store.isAdvancing {
                VStack(spacing: 2) {
                    ProgressView()
                    Text(store.turnProgress?.phase ?? "Advancing")
                        .font(.system(size: 11, design: .monospaced).weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(minWidth: 82, minHeight: 42)
            } else {
                VStack(spacing: 3) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 13, weight: .semibold))
                    Text("3 MONTHS")
                        .font(NativeWarRoomTheme.labelFont(.caption2))
                        .lineLimit(1)
                }
                .foregroundStyle(NativeWarRoomTheme.ink)
                .frame(minWidth: 82, minHeight: 42)
            }
        }
        .buttonStyle(.plain)
        .background(NativeWarRoomTheme.threatRed.opacity(0.82), in: RoundedRectangle(cornerRadius: 5))
        .overlay {
            RoundedRectangle(cornerRadius: 5)
                .stroke(NativeWarRoomTheme.alertAmber.opacity(0.65), lineWidth: 1)
                .padding(1)
        }
        .disabled(store.isAdvancing)
        .accessibilityLabel(advanceTitle(months: NativeCampaignStore.monthsPerTurn, title: "Advance 3 months"))
        .accessibilityIdentifier("native-advance-3")
    }
}

struct TurnTransitionOverlay: View {
    @ObservedObject var store: NativeCampaignStore
    @State private var consoleLogs: [String] = []
    @State private var currentTickerIndex = 0
    @State private var timer = Timer.publish(every: 2.8, on: .main, in: .common).autoconnect()
    @State private var shuffledQuotes: [String] = []
    @State private var backgroundHue = Double.random(in: 0.0 ... 0.15)
    @State private var pulsePhase = false
    @State private var gridRotation = Double.random(in: -15 ... 15)
    @State private var appearOffset: CGFloat = 30

    private var engineName: String {
        if let summary = store.turnProgress?.providerSummary {
            return summary.uppercased()
        }
        return store.selectedAIProviderPreference.providerName.uppercased()
    }

    /// Dynamic accent color based on campaign tension — shifts from teal (calm) to red (crisis)
    private var dynamicAccent: Color {
        guard let state = store.state else { return Color.glowingCyan }
        let tension = Double(state.worldTension) / 100.0
        let stability = Double(state.stability) / 100.0
        let crisis = tension * (1.0 - stability)
        if crisis > 0.6 { return Color.softRed }
        if crisis > 0.4 { return Color.alertGold }
        return Color.glowingCyan
    }

    var body: some View {
        ZStack {
            // Animated gradient background that shifts hue every turn
            LinearGradient(
                colors: [
                    Color.black.opacity(0.75),
                    dynamicAccent.opacity(0.04 * backgroundHue),
                    Color.black.opacity(0.85)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            .blur(radius: 20)

            // Rotating geometric pattern behind everything
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let count = 12
                for i in 0 ..< count {
                    let angle = (Double(i) / Double(count)) * .pi * 2
                    let radius = min(size.width, size.height) * 0.35
                    let pulseOffset = pulsePhase ? Double.pi : 0.0
                    let x = center.x + cos(angle + pulseOffset) * radius
                    let y = center.y + sin(angle) * radius
                    let circleSize = 3.0 + (pulsePhase ? 2.0 : 0.0)
                    context.fill(
                        Path(ellipseIn: CGRect(x: x - circleSize, y: y - circleSize, width: circleSize * 2, height: circleSize * 2)),
                        with: .color(dynamicAccent.opacity(0.12))
                    )
                }
            }
            .rotationEffect(.degrees(gridRotation))
            .opacity(0.5)
            .ignoresSafeArea()
            .accessibilityHidden(true)
            .onAppear {
                withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) {
                    pulsePhase = true
                    gridRotation += 30
                }
            }

            VStack(spacing: 24) {
                Spacer()

                // Telemetry Card
                VStack(spacing: 12) {
                    HStack {
                        Image(systemName: "cpu.fill")
                            .foregroundStyle(dynamicAccent)
                        Text("SIMULATION ACTIVE // \(engineName)")
                            .font(.system(.caption, design: .monospaced).weight(.bold))
                            .foregroundStyle(dynamicAccent)
                    }

                    if let progress = store.turnProgress {
                        HStack(spacing: 4) {
                            Text(progress.phase.uppercased())
                                .font(.system(.title3, design: .monospaced).weight(.black))
                                .foregroundStyle(.white)
                            Text("...")
                                .font(.system(.title3, design: .monospaced).weight(.black))
                                .foregroundStyle(dynamicAccent)
                        }
                        .padding(.top, 4)

                        ProgressView(value: progress.fraction)
                            .tint(dynamicAccent)
                            .frame(maxWidth: 320)
                            .padding(.vertical, 8)

                        Text("\(progress.completedLanes) / \(progress.totalLanes) COGNITIVE LANES RESOLVED")
                            .font(.system(.caption, design: .monospaced).weight(.semibold))
                            .foregroundStyle(Color.iceBlue)

                        // Skeleton shimmer with dynamic count
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(0 ..< (2 + (progress.completedLanes % 3)), id: \.self) { i in
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.white.opacity(0.04 + Double(i) * 0.02))
                                    .frame(height: 12 + CGFloat(i) * 3)
                                    .scaleEffect(x: pulsePhase ? 0.97 : 1.0, anchor: .leading)
                            }
                        }
                        .padding(.top, 8)
                        .accessibilityHidden(true)

                        if !shuffledQuotes.isEmpty {
                            Text(shuffledQuotes[currentTickerIndex % shuffledQuotes.count])
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(Color.alertGold.opacity(0.85))
                                .padding(.top, 6)
                                .transition(.asymmetric(
                                    insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .move(edge: .leading).combined(with: .opacity)
                                ))
                                .id(currentTickerIndex)
                                .accessibilityHidden(true)
                                .onReceive(timer) { _ in
                                    withAnimation(.easeInOut(duration: 0.4)) {
                                        currentTickerIndex = (currentTickerIndex + 1) % max(1, shuffledQuotes.count)
                                    }
                                }
                        }
                    } else {
                        Text("CALCULATING GEOPOLITICAL SHIFTS...")
                            .font(.system(.subheadline, design: .monospaced).weight(.bold))
                            .foregroundStyle(.white)
                        ProgressView()
                            .tint(dynamicAccent)
                            .padding(.vertical, 10)
                    }
                }
                .padding(20)
                .background(Color.spaceBlack.opacity(0.88))
                .cornerRadius(12)
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(dynamicAccent.opacity(0.35), lineWidth: 1.5)
                }
                .shadow(color: dynamicAccent.opacity(0.18), radius: 12, x: 0, y: 0)
                .offset(y: appearOffset)
                .opacity(appearOffset == 0 ? 1 : 0)

                // Terminal Drawer
                VStack(alignment: .leading, spacing: 4) {
                    Text("ACTIVE SIMULATION CHANNEL")
                        .font(.system(.caption2, design: .monospaced).weight(.bold))
                        .foregroundStyle(Color.alertGold)
                        .padding(.bottom, 4)

                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(Array(consoleLogs.enumerated()), id: \.offset) { idx, log in
                                    Text(log)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(log.contains("lane completed") || log.contains("Resolved") || log.contains("won") ? Color.neonTeal : Color.white.opacity(0.75))
                                        .id("\(idx)-\(log)")
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(height: 120)
                        .onChange(of: consoleLogs) { _, _ in
                            if !consoleLogs.isEmpty {
                                let lastIndex = consoleLogs.count - 1
                                let lastId = "\(lastIndex)-\(consoleLogs[lastIndex])"
                                withAnimation {
                                    proxy.scrollTo(lastId, anchor: .bottom)
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
                .accessibilityHidden(true)

                Spacer()
            }
            .padding(.bottom, 40)
        }
        .onAppear {
            // Shuffle quotes and pick a random subset for variety each turn.
            // Ticker follows the campaign save's language (see TurnTickerProse).
            let language = store.state?.language ?? store.selectedLanguage
            shuffledQuotes = Array(TurnTickerProse.quotes(for: language).shuffled().prefix(8))
            currentTickerIndex = 0
            backgroundHue = Double.random(in: 0.5 ... 2.5)
            gridRotation = Double.random(in: -20 ... 20)

            consoleLogs = [
                "SYS // Initializing \(engineName) simulation route...",
                "SYS // Seed=\(store.state?.round ?? 0) tension=\(store.state?.worldTension ?? 0) stability=\(store.state?.stability ?? 0)"
            ]

            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                appearOffset = 0
            }
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
