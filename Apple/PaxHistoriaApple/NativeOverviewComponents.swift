import Foundation
import SwiftUI

struct NativeOverviewScreen: View {
    @ObservedObject var store: NativeCampaignStore
    let onShowEvents: () -> Void
    @State private var showInspector = true

    private func year(in value: String, fallback: Int) -> Int {
        let pattern = "\\b(19|20)\\d{2}\\b"
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
           let range = Range(match.range, in: value),
           let year = Int(value[range])
        {
            return year
        }
        return fallback
    }

    var body: some View {
        Group {
            if let state = store.state {
                #if os(macOS)
                    GeometryReader { geometry in
                        let width = geometry.size.width
                        let sideWidth = max(280, min(340, width * 0.24))
                        let isWide = width >= 1280
                        let isMedium = width >= 940 && width < 1280

                        HStack(alignment: .top, spacing: 0) {
                            if isWide {
                                commandDesk(state: state)
                                    .frame(width: sideWidth)

                                Divider()
                                    .background(NativeWarRoomTheme.brass.opacity(0.18))
                            }

                            mapDesk(
                                state: state,
                                currentYear: year(in: state.gameDate, fallback: 2028),
                                startYear: year(in: state.startDate, fallback: 2024)
                            )
                            .frame(maxWidth: .infinity)

                            if isWide || (isMedium && showInspector) {
                                Divider()
                                    .background(NativeWarRoomTheme.brass.opacity(0.18))

                                intelligenceDesk(state: state)
                                    .frame(width: isWide ? sideWidth : min(360, width * 0.34))
                            }
                        }
                        .overlay(alignment: .topTrailing) {
                            if isMedium {
                                Button {
                                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                        showInspector.toggle()
                                    }
                                } label: {
                                    Label(showInspector ? "Hide dossier" : "Show dossier", systemImage: showInspector ? "sidebar.right" : "sidebar.right")
                                        .font(NativeWarRoomTheme.labelFont(.caption))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 7)
                                }
                                .buttonStyle(.plain)
                                .background(NativeWarRoomTheme.archiveShadow.opacity(0.82), in: Capsule())
                                .overlay {
                                    Capsule().stroke(NativeWarRoomTheme.brass.opacity(0.24), lineWidth: 1)
                                }
                                .padding(14)
                                .accessibilityIdentifier("native-mac-inspector-toggle")
                            }
                        }
                        .background(NativeWarRoomTheme.blackboard.opacity(0.97))
                    }
                    .frame(minWidth: 700, minHeight: 560)
                #else
                    NativeDetailScroll(accessibilityIdentifier: "native-overview-screen") {
                        NativeHeroHeader(state: state)
                        if let progress = store.turnProgress {
                            NativeTurnProgressPanel(progress: progress)
                        }
                        NativeGeopoliticalMap(state: state, store: store)
                            .frame(minHeight: 360)
                            .id(state.country.code)
                        NativeMetricsGrid(state: state)
                        NativeCampaignObjectivesPanel(state: state)
                        if let turn = store.lastTurnReport {
                            NativeAfterActionReportPanel(report: NativeGameEngine.afterActionReport(for: turn, state: state))
                        }
                        NativeStateNotices(store: store)
                    }
                #endif
            } else {
                ContentUnavailableView("No campaign loaded", systemImage: "globe", description: Text("Choose a country to begin."))
            }
        }
        .task(id: store.state?.round ?? 0) {
            await store.refreshSuggestedActionsIfNeeded()
        }
    }

    #if os(macOS)
        private func commandDesk(state: NativeCampaignState) -> some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Text("Actions")
                            .font(NativeWarRoomTheme.labelFont(.headline))
                            .foregroundStyle(NativeWarRoomTheme.brass)
                        Spacer()
                        Text("DESK")
                            .font(NativeWarRoomTheme.labelFont(.caption2))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(NativeWarRoomTheme.brass.opacity(0.14), in: RoundedRectangle(cornerRadius: 3))
                            .foregroundStyle(NativeWarRoomTheme.brass)
                    }
                    .padding(.bottom, 2)

                    // Text Field to Conduct the Game
                    VStack(alignment: .leading, spacing: 10) {
                        TextEditor(text: $store.draftAction)
                            .font(NativeWarRoomTheme.bodyFont())
                            .frame(height: 72)
                            .padding(8)
                            .scrollContentBackground(.hidden)
                            .background(NativeWarRoomTheme.graphite.opacity(0.72))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay {
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(NativeWarRoomTheme.brass.opacity(0.16), lineWidth: 1)
                            }

                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                store.addDraftAction()
                            }
                        } label: {
                            HStack {
                                Spacer()
                                Image(systemName: "paperplane.fill")
                                Text("Submit")
                                    .font(NativeWarRoomTheme.labelFont(.caption))
                                Spacer()
                            }
                            .frame(minHeight: 32)
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 6)
                        .background(NativeWarRoomTheme.brass)
                        .foregroundStyle(NativeWarRoomTheme.blackboard)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .disabled(store.draftAction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }

                    NativeSuggestedActionsPanel(store: store)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Recent orders")
                            .font(NativeWarRoomTheme.labelFont(.subheadline))
                            .foregroundStyle(NativeWarRoomTheme.mapPaper)

                        let resolved = state.plannedActions.filter { $0.status == .resolved }
                        if resolved.isEmpty {
                            Text("No historical directives logged.")
                                .font(NativeWarRoomTheme.labelFont(.caption))
                                .foregroundStyle(NativeWarRoomTheme.mutedInk)
                        } else {
                            VStack(spacing: 8) {
                                ForEach(resolved.suffix(4)) { action in
                                    HStack {
                                        Image(systemName: "checkmark.seal.fill")
                                            .foregroundStyle(NativeWarRoomTheme.fieldGreen)
                                            .font(.caption)
                                        Text(action.title)
                                            .font(.caption)
                                            .foregroundStyle(NativeWarRoomTheme.ink)
                                            .lineLimit(1)
                                        Spacer()
                                        Text("Filed")
                                            .font(NativeWarRoomTheme.labelFont(.caption2, weight: .regular))
                                            .foregroundStyle(NativeWarRoomTheme.mutedInk)
                                    }
                                    .padding(8)
                                    .warRoomDossier(borderColor: NativeWarRoomTheme.brass.opacity(0.12), cornerRadius: 6)
                                }
                            }
                        }
                    }
                }
                .padding(16)
            }
            .background(NativeWarRoomTheme.archiveShadow.opacity(0.95))
        }

        private func mapDesk(state: NativeCampaignState, currentYear: Int, startYear: Int) -> some View {
            VStack(spacing: 0) {
                NativeCompactStatusBar(state: state, latestEvent: state.timeline.first)
                    .padding(.horizontal, 16)
                    .padding(.top, 14)

                if let progress = store.turnProgress {
                    NativeTurnProgressPanel(progress: progress)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                }

                NativeCampaignObjectivesPanel(state: state)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                NativeGeopoliticalMap(state: state, store: store)
                    .frame(minHeight: 320)
                    .padding(16)
                    .id(state.country.code)

                Spacer()

                NativeTimelineFooter(
                    store: store,
                    currentYear: currentYear,
                    baseYear: startYear,
                    onShowEvents: onShowEvents
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
            }
        }

        private func intelligenceDesk(state: NativeCampaignState) -> some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Text("CONSEQUENCES")
                            .font(NativeWarRoomTheme.labelFont(.headline))
                            .foregroundStyle(NativeWarRoomTheme.threatRed)
                        Spacer()
                        Image(systemName: "chart.bar.xaxis")
                            .font(.subheadline)
                            .foregroundStyle(NativeWarRoomTheme.threatRed)
                    }
                    .padding(.bottom, 2)

                    let alignments = Native2010WorldModel.alignments(for: state)
                    let riskSignals = Native2010WorldModel.riskSignals(for: state)
                    let commitments = Native2010WorldModel.commitments(for: state)
                    let opinion = Native2010WorldModel.publicOpinion(for: state)
                    let pressures = Native2010WorldModel.economicPressures(for: state)

                    VStack(alignment: .leading, spacing: 10) {
                        Label("2010 DIPLOMATIC ALIGNMENT", systemImage: "bubble.left.and.bubble.right")
                            .font(NativeWarRoomTheme.labelFont(.caption))
                            .foregroundStyle(NativeWarRoomTheme.fieldGreen)

                        VStack(spacing: 6) {
                            ForEach(alignments) { item in
                                let color = native2010RelationColor(item.relation)
                                HStack {
                                    Circle()
                                        .fill(color)
                                        .frame(width: 6, height: 6)
                                    Text(item.name)
                                        .font(.caption)
                                        .foregroundStyle(NativeWarRoomTheme.ink)
                                    Spacer()
                                    Text(item.stance)
                                        .font(NativeWarRoomTheme.labelFont(.caption2))
                                        .foregroundStyle(color)
                                    Text("\(item.score)")
                                        .font(.system(size: 11, design: .monospaced).weight(.bold))
                                        .foregroundStyle(NativeWarRoomTheme.mutedInk)
                                }
                                .padding(8)
                                .warRoomDossier(borderColor: NativeWarRoomTheme.brass.opacity(0.1), cornerRadius: 6)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Label("2010 TENSION SIGNALS", systemImage: "flame")
                            .font(NativeWarRoomTheme.labelFont(.caption))
                            .foregroundStyle(NativeWarRoomTheme.threatRed)

                        VStack(spacing: 6) {
                            ForEach(riskSignals) { signal in
                                BattleRow(name: signal.name, intensity: signal.intensity, color: native2010SignalColor(signal.level))
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Label("2010 COMMITMENTS", systemImage: "shield.fill")
                            .font(NativeWarRoomTheme.labelFont(.caption))
                            .foregroundStyle(NativeWarRoomTheme.mapPaper)

                        VStack(spacing: 6) {
                            ForEach(commitments) { commitment in
                                TroopRow(
                                    name: commitment.name,
                                    count: commitment.countLabel,
                                    status: commitment.status,
                                    color: native2010SignalColor(commitment.level)
                                )
                            }
                        }
                    }

                    NativePublicOpinionSparkline(opinion: opinion, events: state.timeline)

                    VStack(alignment: .leading, spacing: 10) {
                        Label("ECONOMIC LEDGER", systemImage: "chart.line.uptrend.xyaxis")
                            .font(NativeWarRoomTheme.labelFont(.caption))
                            .foregroundStyle(NativeWarRoomTheme.alertAmber)

                        VStack(spacing: 6) {
                            ForEach(pressures) { pressure in
                                EconomicRow(
                                    name: pressure.name,
                                    value: pressure.value,
                                    direction: pressure.direction,
                                    color: native2010SignalColor(pressure.level)
                                )
                            }
                        }
                    }
                }
                .padding(16)
            }
            .background(NativeWarRoomTheme.archiveShadow.opacity(0.95))
        }
    #endif
}

struct NativePublicOpinionSparkline: View {
    let opinion: Native2010PublicOpinion
    let events: [NativeCampaignEvent]

    private var supportSeries: [Int] {
        let recentPressure = events.prefix(5).reversed().map { event in
            event.strategicEffects.reduce(0) { partial, effect in
                partial + effect.magnitude
            }
        }
        guard !recentPressure.isEmpty else {
            return [
                max(0, min(100, opinion.support - 4)),
                max(0, min(100, opinion.support - 2)),
                opinion.support
            ]
        }

        var running = opinion.support
        var values = [running]
        for pressure in recentPressure {
            running = max(0, min(100, running + max(-6, min(6, pressure / 2))))
            values.append(running)
        }
        return values
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("PUBLIC OPINION", systemImage: "person.3.sequence.fill")
                    .font(NativeWarRoomTheme.labelFont(.caption))
                    .foregroundStyle(NativeWarRoomTheme.signalCyan)
                Spacer()
                Text("\(opinion.support)%")
                    .font(NativeWarRoomTheme.labelFont(.caption))
                    .foregroundStyle(NativeWarRoomTheme.fieldGreen)
            }

            GeometryReader { geometry in
                let values = supportSeries
                let width = geometry.size.width
                let height = geometry.size.height
                let step = values.count > 1 ? width / CGFloat(values.count - 1) : width
                let points = values.enumerated().map { index, value in
                    CGPoint(
                        x: CGFloat(index) * step,
                        y: height * (1.0 - CGFloat(value) / 100.0)
                    )
                }

                ZStack {
                    Rectangle()
                        .fill(NativeWarRoomTheme.mapPaper.opacity(0.035))

                    Path { path in
                        guard let first = points.first else { return }
                        path.move(to: first)
                        for point in points.dropFirst() {
                            path.addLine(to: point)
                        }
                    }
                    .stroke(NativeWarRoomTheme.signalCyan, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))

                    ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                        Circle()
                            .fill(NativeWarRoomTheme.signalCyan)
                            .frame(width: 4, height: 4)
                            .position(point)
                    }
                }
            }
            .frame(height: 38)
            .warRoomDossier(borderColor: NativeWarRoomTheme.signalCyan.opacity(0.18), cornerRadius: 6)

            HStack {
                Text("Support \(opinion.support)%")
                Spacer()
                Text("Neutral \(opinion.neutral)%")
                Spacer()
                Text("Oppose \(opinion.oppose)%")
            }
            .font(.system(size: 11))
            .foregroundStyle(NativeWarRoomTheme.mutedInk)
        }
    }
}

struct NativeHeroHeader: View {
    let state: NativeCampaignState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SWIFT HISTORIA COMMAND CENTER")
                .font(.system(.caption, design: .monospaced).weight(.bold))
                .foregroundStyle(Color.glowingCyan)
                .textCase(.uppercase)
                .tracking(2)
            Text(state.lastSummary)
                .font(.title2.weight(.bold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("native-overview-header")
    }
}

struct NativeSectionHeader: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title.uppercased(), systemImage: systemImage)
                .font(.system(.title2, design: .monospaced).weight(.bold))
                .foregroundStyle(Color.iceBlue)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

struct NativeMetricsGrid: View {
    let state: NativeCampaignState

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)], spacing: 12) {
            MetricCard(title: "Planned Actions", value: "\(state.plannedActions.filter { $0.status == .planned }.count)", systemImage: "checklist")
            MetricCard(title: "Budget Balance", value: nativeFormatSignedPercent(state.economicLedger.budgetBalancePercentGDP), systemImage: "banknote")
            MetricCard(title: "Public Debt", value: nativeFormatPercent(state.economicLedger.publicDebtPercentGDP), systemImage: "creditcard")
            MetricCard(title: "Fiscal Space", value: "\(state.economicLedger.fiscalSpaceIndex)/100", systemImage: "gauge.with.dots.needle.67percent")
            MetricCard(title: "Inflation", value: nativeFormatPercent(state.economicLedger.inflationPercent), systemImage: "chart.line.uptrend.xyaxis")
            MetricCard(title: "Strategic Effects", value: "\(state.worldEffects.count)", systemImage: "chart.line.uptrend.xyaxis")
            MetricCard(title: "Independent Events", value: "\(state.timeline.filter { !$0.playerRelated }.count)", systemImage: "globe.europe.africa")
            MetricCard(title: "AI Status", value: nativeFormatAvailability(state.aiReadiness.availability), systemImage: "brain")
        }
        .accessibilityIdentifier("native-metrics-grid")
    }
}

struct NativeCampaignObjectivesPanel: View {
    let state: NativeCampaignState

    var body: some View {
        NativePanel(accessibilityIdentifier: "native-campaign-objectives-panel") {
            HStack {
                Label("Campaign Objectives", systemImage: "target")
                    .font(NativeTypography.sectionTitle())
                    .foregroundStyle(Color.neonTeal)
                Spacer()
                Text(state.victoryStatus.rawValue.uppercased())
                    .font(.system(.caption2, design: .monospaced).weight(.bold))
                    .foregroundStyle(state.victoryStatus == .ongoing ? Color.alertGold : Color.neonTeal)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 10)], spacing: 10) {
                ForEach(NativeGameEngine.campaignObjectives(for: state)) { objective in
                    NativeObjectiveRow(objective: objective)
                }
            }
        }
    }
}

struct NativeObjectiveRow: View {
    let objective: NativeCampaignObjective

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: objective.isComplete ? "checkmark.seal.fill" : "circle.dashed")
                    .foregroundStyle(objective.isComplete ? Color.neonTeal : Color.alertGold)
                Text(objective.title)
                    .font(.callout.weight(.bold))
                    .foregroundStyle(.primary)
                Spacer()
                Text(objective.deadline)
                    .font(.system(.caption2, design: .monospaced).weight(.bold))
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: objective.progress)
                .tint(objective.isComplete ? Color.neonTeal : Color.glowingCyan)

            Text("\(objective.currentValue) / \(objective.targetValue)")
                .font(.system(.caption, design: .monospaced).weight(.semibold))
                .foregroundStyle(objective.isComplete ? Color.neonTeal : Color.iceBlue)

            Text(objective.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke((objective.isComplete ? Color.neonTeal : Color.white).opacity(0.14), lineWidth: 1)
        }
    }
}

struct NativeAfterActionReportPanel: View {
    let report: NativeAfterActionReport

    var body: some View {
        NativePanel(accessibilityIdentifier: "native-after-action-report-panel") {
            HStack {
                Label("After Action Report", systemImage: "doc.text.magnifyingglass")
                    .font(NativeTypography.sectionTitle())
                    .foregroundStyle(Color.alertGold)
                Spacer()
                Text("\(report.resolvedOrderCount) ORDERS")
                    .font(.system(.caption2, design: .monospaced).weight(.bold))
                    .foregroundStyle(Color.iceBlue)
            }

            Text(report.summary)
                .font(.callout)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 8)], spacing: 8) {
                ForEach(report.metrics) { metric in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(metric.label)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(metric.value)
                                .font(.system(.caption, design: .monospaced).weight(.bold))
                                .foregroundStyle(.primary)
                        }
                        Spacer()
                        Text(metric.delta)
                            .font(.system(.caption, design: .monospaced).weight(.black))
                            .foregroundStyle(metric.delta.hasPrefix("-") ? Color.softRed : Color.neonTeal)
                    }
                    .padding(8)
                    .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
                }
            }

            ForEach(report.events) { event in
                HStack(alignment: .top, spacing: 8) {
                    Circle()
                        .fill(event.playerRelated ? Color.glowingCyan : Color.alertGold)
                        .frame(width: 7, height: 7)
                        .padding(.top, 5)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.title)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.primary)
                        Text(event.description)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }
        }
    }
}

struct NativeStateNotices: View {
    @ObservedObject var store: NativeCampaignStore

    var body: some View {
        VStack(spacing: 10) {
            if let recoveryNotice = store.lastRecoveryNotice, !recoveryNotice.isEmpty {
                SuggestionWarning(message: recoveryNotice)
            }
            if let error = store.lastError, !error.isEmpty {
                ErrorBanner(message: error)
            }
        }
    }
}

struct NativeSuggestedActionsPanel: View {
    @ObservedObject var store: NativeCampaignStore

    var body: some View {
        NativePanel(accessibilityIdentifier: "native-suggested-actions-panel") {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Suggested actions", systemImage: "sparkles")
                        .font(NativeTypography.sectionTitle())
                        .foregroundStyle(Color.glowingCyan)
                        .help("AI-generated recommendations based on your current situation.")
                    Text("Provider: \(store.selectedAIProviderPreference.providerName)")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.alertGold)
                        .accessibilityIdentifier("native-suggestions-provider-label")
                }
                Spacer()
                if store.isLoadingSuggestions {
                    ProgressView().controlSize(.small)
                } else {
                    Button {
                        Task { await store.refreshSuggestedActions(force: true) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.subheadline)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Refresh suggestions")
                    .accessibilityIdentifier("native-refresh-suggestions")
                }
            }

            if let suggestionError = store.lastSuggestionError, !suggestionError.isEmpty {
                SuggestionWarning(message: suggestionError)
            }

            let suggestions = store.state?.suggestedActions ?? []
            if !suggestions.isEmpty {
                ForEach(suggestions) { suggestion in
                    SuggestedActionRow(suggestion: suggestion) {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                            store.addSuggestedAction(suggestion)
                        }
                    }
                }
            } else if store.isLoadingSuggestions {
                Text("Analyzing campaign tracks...")
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.secondary)
            } else {
                Text("No advisory suggestions available.")
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct NativeQuickActionPicker: View {
    let onPick: (String) -> Void
    @State private var expandedCategory: NativeQuickActionCategory?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Quick actions")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(NativeQuickActionCategory.allCases.filter { category in
                !NativeQuickActionCatalog.actions.filter { $0.category == category }.isEmpty
            }) { category in
                DisclosureGroup(
                    isExpanded: Binding(
                        get: { expandedCategory == category },
                        set: { expandedCategory = $0 ? category : nil }
                    )
                ) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(NativeQuickActionCatalog.actions.filter { $0.category == category }) { action in
                            Button {
                                onPick(action.directiveTemplate)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(action.title)
                                            .font(.callout.weight(.medium))
                                            .foregroundStyle(.primary)
                                        Spacer()
                                        Text("\(action.cost)")
                                            .font(.system(.caption2, design: .monospaced).weight(.bold))
                                            .foregroundStyle(Color.glowingCyan)
                                    }
                                    Text(action.primaryEffects.joined(separator: " · "))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 4)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("native-quick-action-\(action.id)")
                        }
                    }
                    .padding(.leading, 4)
                } label: {
                    Label(category.title, systemImage: category.systemImage)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                }
            }
        }
    }
}

struct NativeDirectivePreviewPanel: View {
    let preview: NativeDirectivePreview

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Order Preview", systemImage: "scope")
                    .font(.system(.caption, design: .monospaced).weight(.bold))
                    .foregroundStyle(Color.glowingCyan)
                Spacer()
                Text(preview.riskLabel.uppercased())
                    .font(.system(.caption2, design: .monospaced).weight(.bold))
                    .foregroundStyle(preview.warning == nil ? Color.alertGold : Color.softRed)
            }

            HStack {
                Text("Cost \(preview.cost)")
                Spacer()
                Text("Capacity after \(preview.capacityAfter)")
                    .foregroundStyle(preview.capacityAfter >= 0 ? Color.neonTeal : Color.softRed)
            }
            .font(.system(.caption, design: .monospaced).weight(.semibold))

            ForEach(preview.expectedEffects, id: \.self) { effect in
                HStack(alignment: .top, spacing: 6) {
                    Circle()
                        .fill(Color.iceBlue)
                        .frame(width: 5, height: 5)
                        .padding(.top, 5)
                    Text(effect)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let warning = preview.warning {
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(Color.softRed)
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke((preview.warning == nil ? Color.glowingCyan : Color.softRed).opacity(0.18), lineWidth: 1)
        }
        .accessibilityIdentifier("native-directive-preview")
    }
}
