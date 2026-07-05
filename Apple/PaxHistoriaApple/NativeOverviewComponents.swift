import Foundation
import SwiftUI

struct NativeOverviewScreen: View {
    @ObservedObject var store: NativeCampaignStore
    let onShowEvents: () -> Void
    let onShowOrders: () -> Void

    /// Cache the year regex to avoid recompiling on every body recomputation
    private static let yearRegex = try? NSRegularExpression(pattern: "\\b(19|20)\\d{2}\\b")

    private func year(in value: String, fallback: Int) -> Int {
        guard let regex = Self.yearRegex,
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
              let range = Range(match.range, in: value),
              let year = Int(value[range])
        else {
            return fallback
        }
        return year
    }

    var body: some View {
        Group {
            if let state = store.state {
                #if os(macOS)
                    GeometryReader { geometry in
                        atlasMapRoom(state: state, size: geometry.size)
                    }
                    .frame(minWidth: 700, minHeight: 560)
                #else
                    NativeDetailScroll(accessibilityIdentifier: "native-overview-screen") {
                        NativeHeroHeader(state: state)
                        NativeCrisisBanner(state: state)
                        if let progress = store.turnProgress {
                            NativeTurnProgressPanel(progress: progress)
                        }
                        NativeWorldMap(
                            state: state,
                            store: store,
                            minHeight: 360
                        )
                        .frame(minHeight: 360)
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
            // Only refresh if we don't have suggestions yet, not every round change.
            // The player can manually refresh via the toolbar or ⌘R.
            if store.state?.suggestedActions.isEmpty == true {
                await store.refreshSuggestedActionsIfNeeded()
            }
        }
    }

    #if os(macOS)
        private func atlasMapRoom(state: NativeCampaignState, size: CGSize) -> some View {
            VStack(spacing: 0) {
                NativeWorldMap(
                    state: state,
                    store: store,
                    minHeight: max(420, size.height - 104)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(12)

                atlasOrdersDeck(state: state)
            }
            .background(NativeWarRoomTheme.blackboard)
            .accessibilityIdentifier("native-atlas-map-room")
        }

        private func atlasOrdersDeck(state: NativeCampaignState) -> some View {
            let pending = state.plannedActions.filter { $0.status == .planned }

            return HStack(spacing: 12) {
                Button(action: onShowOrders) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(pending.count == 1 ? "1 ORDER READY" : "\(pending.count) ORDERS READY")
                            .font(NativeWarRoomTheme.displayFont(.headline, weight: .semibold))
                            .foregroundStyle(NativeWarRoomTheme.ink)
                        Text(pending.isEmpty ? "Build your next move in the decision matrix." : "Review the queue before advancing the calendar.")
                            .font(NativeWarRoomTheme.bodyFont(.caption))
                            .foregroundStyle(NativeWarRoomTheme.mutedInk)
                            .lineLimit(1)
                    }
                    .frame(minWidth: 210, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("native-atlas-open-orders")

                Rectangle()
                    .fill(NativeWarRoomTheme.brass.opacity(0.18))
                    .frame(width: 1, height: 44)

                ForEach(Array(pending.prefix(2))) { action in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(action.title)
                            .font(NativeWarRoomTheme.bodyFont(.caption, weight: .semibold))
                            .foregroundStyle(NativeWarRoomTheme.ink)
                            .lineLimit(1)
                        Text("COST \(action.administrativeCost)")
                            .font(NativeWarRoomTheme.labelFont(.caption2))
                            .foregroundStyle(NativeWarRoomTheme.brass)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .frame(minWidth: 150, maxWidth: 220, alignment: .leading)
                    .background(NativeWarRoomTheme.olivePanel.opacity(0.7), in: RoundedRectangle(cornerRadius: 5))
                    .overlay {
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(NativeWarRoomTheme.brass.opacity(0.18), lineWidth: 1)
                    }
                }

                if pending.count > 2 {
                    Text("+\(pending.count - 2)")
                        .font(NativeWarRoomTheme.labelFont(.caption))
                        .foregroundStyle(NativeWarRoomTheme.brass)
                }

                Spacer(minLength: 8)

                Button(action: onShowEvents) {
                    Label("Timeline", systemImage: "clock")
                        .font(NativeWarRoomTheme.labelFont(.caption))
                }
                .buttonStyle(.plain)
                .foregroundStyle(NativeWarRoomTheme.mutedInk)
                .accessibilityIdentifier("native-atlas-open-events")

                NativeFloatingAdvanceButton(store: store)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                LinearGradient(
                    colors: [NativeWarRoomTheme.graphite, NativeWarRoomTheme.archiveShadow],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(NativeWarRoomTheme.brass.opacity(0.24))
                    .frame(height: 1)
            }
        }

        private func commandDesk(state: NativeCampaignState) -> some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    NativeCrisisBanner(state: state)
                        .padding(.bottom, 4)

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
                NativeCrisisBanner(state: state)
                    .padding(.horizontal, 16)
                    .padding(.top, 10)

                NativeCompactStatusBar(state: state, latestEvent: state.timeline.first)
                    .padding(.horizontal, 16)
                    .padding(.top, 10)

                if let progress = store.turnProgress {
                    NativeTurnProgressPanel(progress: progress)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                }

                NativeCampaignObjectivesPanel(state: state)
                    .frame(minHeight: 160)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                NativeWorldMap(
                    state: state,
                    store: store,
                    minHeight: 320
                )
                .frame(minHeight: 320)
                .padding(16)

                NativeTimelineFooter(
                    store: store,
                    currentDate: state.gameDate,
                    startDate: state.startDate,
                    currentYear: currentYear,
                    baseYear: startYear,
                    onShowEvents: onShowEvents
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
            }
        }

        private func intelligenceDesk(state: NativeCampaignState) -> some View {
            IntelligenceDeskView(state: state)
        }
    #endif
}

/// Extracted as a standalone view so the intelligence desk sub-tree is
/// re-evaluated independently from the parent overview panel.
/// The `equatableKey` parameter lets SwiftUI skip re-computation of the 5
/// expensive model traversals (alignments, riskSignals, commitments, opinion,
/// economicPressures) when only unrelated @Published properties change.
struct IntelligenceDeskView: View {
    let state: NativeCampaignState
    let equatableKey: String

    init(state: NativeCampaignState) {
        self.state = state
        // Derive a stable key from round + AI country state hashes.
        // Only changes when turn advances or AI states mutate.
        var parts = [state.round.description]
        for code in state.aiCountryStates.keys.sorted() {
            if let ai = state.aiCountryStates[code] {
                parts.append("\(ai.hashValue)")
            }
        }
        self.equatableKey = parts.joined()
    }

    var body: some View {
        _IntelligenceDeskBody(state: state)
            .id(equatableKey)
    }
}

/// Inner body extracted so that `.id(equatableKey)` forces a full rebuild
/// only when the key changes, letting SwiftUI skip it otherwise.
private struct _IntelligenceDeskBody: View {
    let state: NativeCampaignState

    var body: some View {
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
            Text("PAX HISTORIA · THE LIVING ATLAS")
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
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(NativeWarRoomTheme.brass)
                Text(title)
                    .font(NativeWarRoomTheme.displayFont(.title2, weight: .bold))
                    .foregroundStyle(NativeWarRoomTheme.ink)
            }
            Text(subtitle)
                .font(NativeWarRoomTheme.bodyFont(.subheadline))
                .foregroundStyle(NativeWarRoomTheme.mutedInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

struct NativeMetricsGrid: View {
    let state: NativeCampaignState

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)], spacing: 12) {
            MetricCard(title: "Government", value: state.economicLedger.governmentType.capitalized, systemImage: "building.columns")
                .help(governmentReformHint)
            let approvalLabel = state.economicLedger.governmentType == "democracy" ? "Public Approval" : "Regime Support"
            MetricCard(title: approvalLabel, value: String(format: "%.1f%%", state.economicLedger.publicApprovalPercent), systemImage: "hand.thumbsup")
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

    private var governmentReformHint: String {
        let gov = state.economicLedger.governmentType
        let available = NativeQuickActionCatalog.politicalReformActions(state: state)
        let names = available.map(\.title).joined(separator: ", ")
        if available.isEmpty {
            return "No political reforms available for \(gov.capitalized)."
        }
        return "\(gov.capitalized) — available reforms: \(names)"
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

            #if os(macOS)
                HStack(alignment: .top, spacing: 10) {
                    ForEach(NativeGameEngine.campaignObjectives(for: state)) { objective in
                        NativeObjectiveRow(objective: objective)
                            .frame(maxWidth: .infinity)
                            .frame(height: 116, alignment: .topLeading)
                    }
                }
            #else
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 10)], spacing: 10) {
                    ForEach(NativeGameEngine.campaignObjectives(for: state)) { objective in
                        NativeObjectiveRow(objective: objective)
                    }
                }
            #endif
        }
        .transaction { transaction in
            transaction.animation = nil
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
                .lineLimit(2)
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
                    Label("Decision matrix", systemImage: "square.grid.3x3.square")
                        .font(NativeTypography.sectionTitle())
                        .foregroundStyle(Color.glowingCyan)
                        .help("A complete 5 by 5 board of actions that are legal in the current campaign state.")
                    Text("25 legal choices · Provider: \(suggestionProviderName)")
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
            let matrixSuggestions = suggestions.filter {
                (0 ..< 5).contains($0.matrixRow) && (0 ..< 5).contains($0.matrixColumn)
            }
            if matrixSuggestions.count == NativeDecisionMatrixContract.cellCount {
                NativeDecisionMatrixBoard(store: store, suggestions: matrixSuggestions)
            } else if !suggestions.isEmpty {
                SuggestionWarning(message: "This saved board predates the 5 x 5 matrix contract. Refresh it to regenerate 25 state-valid decisions.")
                ForEach(suggestions) { suggestion in
                    SuggestedActionRow(suggestion: suggestion) {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                            store.addSuggestedAction(suggestion)
                        }
                    }
                }
            } else if store.isLoadingSuggestions {
                Text("Building 25 state-valid decisions from the complete world snapshot...")
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.secondary)
            } else {
                Text("No decision matrix available.")
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var suggestionProviderName: String {
        let provider = store.lastAIProviderUsed
        if store.selectedAIProviderPreference == .nvidia, provider == "OpenRouter" {
            return "NVIDIA primary → OpenRouter fallback"
        }
        return provider == "None" || provider == "Unknown"
            ? store.selectedAIProviderPreference.providerName
            : provider
    }
}

private struct NativeDecisionMatrixBoard: View {
    @ObservedObject var store: NativeCampaignStore
    let suggestions: [NativeSuggestedAction]

    private let labelWidth: CGFloat = 104
    private let cellWidth: CGFloat = 176
    private let spacing: CGFloat = 8

    var body: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            LazyVGrid(columns: gridColumns, alignment: .leading, spacing: spacing) {
                Color.clear
                    .frame(width: labelWidth, height: 28)
                ForEach(NativeDecisionMatrixColumn.allCases) { column in
                    Text(column.title.uppercased())
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.alertGold)
                        .frame(width: cellWidth, alignment: .leading)
                }

                ForEach(NativeDecisionMatrixRow.allCases) { row in
                    Label(row.title, systemImage: row.systemImage)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.iceBlue)
                        .frame(width: labelWidth, alignment: .leading)

                    ForEach(NativeDecisionMatrixColumn.allCases) { column in
                        if let suggestion = suggestion(row: row, column: column) {
                            NativeDecisionMatrixCell(
                                suggestion: suggestion,
                                isQueued: isQueued(suggestion)
                            ) {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                                    store.addSuggestedAction(suggestion)
                                }
                            }
                            .frame(width: cellWidth)
                            .frame(minHeight: 154)
                        } else {
                            ContentUnavailableView("Missing", systemImage: "exclamationmark.triangle")
                                .frame(width: cellWidth)
                                .frame(minHeight: 154)
                        }
                    }
                }
            }
            .frame(width: labelWidth + cellWidth * 5 + spacing * 5)
            .padding(.vertical, 4)
        }
        .accessibilityIdentifier("native-decision-matrix")
    }

    private var gridColumns: [GridItem] {
        [GridItem(.fixed(labelWidth), spacing: spacing)] + Array(
            repeating: GridItem(.fixed(cellWidth), spacing: spacing),
            count: 5
        )
    }

    private func suggestion(
        row: NativeDecisionMatrixRow,
        column: NativeDecisionMatrixColumn
    ) -> NativeSuggestedAction? {
        suggestions.first { $0.matrixRow == row.rawValue && $0.matrixColumn == column.rawValue }
    }

    private func isQueued(_ suggestion: NativeSuggestedAction) -> Bool {
        store.state?.plannedActions.contains {
            $0.status == .planned && $0.title == suggestion.title && $0.detail == suggestion.detail
        } ?? false
    }
}

private struct NativeDecisionMatrixCell: View {
    let suggestion: NativeSuggestedAction
    let isQueued: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .top) {
                    Text(suggestion.title)
                        .font(.system(size: 12, weight: .semibold, design: .serif))
                        .foregroundStyle(.primary)
                        .lineLimit(3)
                    Spacer(minLength: 4)
                    if isQueued {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.neonTeal)
                    }
                }

                Text(suggestion.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)

                Spacer(minLength: 0)

                HStack {
                    Label("\(suggestion.administrativeCost)", systemImage: "bolt.fill")
                    Spacer()
                    Text(suggestion.actionKind.uppercased())
                }
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(isQueued ? Color.neonTeal : Color.glowingCyan)
            }
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.iceBlue.opacity(isQueued ? 0.12 : 0.055), in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isQueued ? Color.neonTeal.opacity(0.7) : Color.iceBlue.opacity(0.18), lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isQueued)
        .help("\(suggestion.rationale) Cost: \(suggestion.administrativeCost).")
        .accessibilityLabel("\(suggestion.title), costs \(suggestion.administrativeCost) capacity")
        .accessibilityHint(isQueued ? "Already queued" : "Adds this legal decision to the next turn")
        .accessibilityIdentifier("native-decision-cell-\(suggestion.matrixRow)-\(suggestion.matrixColumn)")
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
