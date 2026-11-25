import SwiftUI

struct NativeOrdersScreen: View {
    @ObservedObject var store: NativeCampaignStore

    var body: some View {
        NativeDetailScroll(accessibilityIdentifier: "native-orders-screen") {
            NativeSectionHeader(
                title: "Orders",
                subtitle: "Choose from 25 state-valid decisions generated for this exact world state, then advance when the queue is ready.",
                systemImage: "checklist"
            )
            NativeQueuedDirectivesSummaryStrip(store: store)
            NativeStateNotices(store: store)
            NativeSuggestedActionsPanel(store: store)
            NativePlannedOrdersPanel(store: store)
            NativeOrdersEditorPanel(store: store)

            if let state = store.state {
                if let turn = store.lastTurnReport {
                    NativeAfterActionReportPanel(report: NativeGameEngine.afterActionReport(for: turn, state: state))
                }
                NativeCampaignObjectivesPanel(state: state)
            }
        }
        .navigationTitle("Orders")
    }
}

private struct NativeQueuedDirectivesSummaryStrip: View {
    @ObservedObject var store: NativeCampaignStore

    private var pending: [NativePlannedAction] {
        store.state?.plannedActions.filter { $0.status == .planned } ?? []
    }

    var body: some View {
        let capacity = store.state?.administrativeCapacity ?? 0
        let totalCommitted = pending.reduce(0) { $0 + max(0, $1.administrativeCost) }

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label("TURN QUEUE", systemImage: "tray.full")
                    .font(NativeWarRoomTheme.labelFont(.caption2, weight: .bold))
                    .foregroundStyle(NativeWarRoomTheme.brass)
                Text("\(pending.count)/\(NativeDecisionMatrixContract.maximumOrdersPerTurn) SLOTS")
                    .font(NativeWarRoomTheme.labelFont(.caption2, weight: .bold))
                    .foregroundStyle(NativeWarRoomTheme.ink)
                Spacer()
                Text("\(totalCommitted) COST · \(capacity) LEFT")
                    .font(NativeWarRoomTheme.labelFont(.caption2, weight: .bold))
                    .foregroundStyle(capacity > 0 ? NativeWarRoomTheme.fieldGreen : NativeWarRoomTheme.threatRed)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 8)], spacing: 8) {
                ForEach(0 ..< NativeDecisionMatrixContract.maximumOrdersPerTurn, id: \.self) { index in
                    let action = pending.indices.contains(index) ? pending[index] : nil
                    HStack(spacing: 8) {
                        Text("\(index + 1)")
                            .font(NativeWarRoomTheme.labelFont(.caption2, weight: .bold))
                            .frame(width: 20, height: 20)
                            .background(
                                (action != nil ? NativeWarRoomTheme.brass : NativeWarRoomTheme.olivePanel).opacity(0.85),
                                in: RoundedRectangle(cornerRadius: 4)
                            )
                            .foregroundStyle(action != nil ? NativeWarRoomTheme.blackboard : NativeWarRoomTheme.mutedInk)

                        if let action {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(action.title)
                                    .font(NativeWarRoomTheme.bodyFont(.caption, weight: .semibold))
                                    .foregroundStyle(NativeWarRoomTheme.ink)
                                    .lineLimit(1)
                                Text("COST \(action.administrativeCost)")
                                    .font(NativeWarRoomTheme.labelFont(.caption2))
                                    .foregroundStyle(NativeWarRoomTheme.brass)
                            }
                            Spacer(minLength: 4)
                            Button {
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                                    store.deleteAction(id: action.id)
                                }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(NativeWarRoomTheme.mutedInk)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove \(action.title) from queue")
                        } else {
                            Text("Empty order slot")
                                .font(NativeWarRoomTheme.labelFont(.caption2, weight: .regular))
                                .foregroundStyle(NativeWarRoomTheme.mutedInk)
                            Spacer(minLength: 0)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(minHeight: 42, alignment: .leading)
                    .background(
                        action != nil ? NativeWarRoomTheme.olivePanel.opacity(0.8) : NativeWarRoomTheme.archiveShadow.opacity(0.5),
                        in: RoundedRectangle(cornerRadius: 6)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(
                                action != nil ? NativeWarRoomTheme.brass.opacity(0.4) : NativeWarRoomTheme.brass.opacity(0.2),
                                style: action != nil ? StrokeStyle(lineWidth: 1) : StrokeStyle(lineWidth: 1, dash: [4, 3])
                            )
                    }
                }
            }
        }
        .padding(12)
        .warRoomDossier(borderColor: NativeWarRoomTheme.brass.opacity(0.2), cornerRadius: 8)
        .accessibilityIdentifier("native-orders-queue-summary-strip")
    }
}

private struct NativePlannedOrdersPanel: View {
    @ObservedObject var store: NativeCampaignStore

    private var queuedCapacity: Int {
        store.state?.plannedActions
            .filter { $0.status == .planned }
            .reduce(0) { $0 + $1.administrativeCost }
            ?? 0
    }

    var body: some View {
        NativePanel(accessibilityIdentifier: "native-planned-orders") {
            HStack {
                Text("Queued decisions")
                    .font(NativeTypography.sectionTitle())
                    .foregroundStyle(Color.iceBlue)
                Spacer()
                if let state = store.state {
                    let remaining = max(0, state.administrativeCapacity - queuedCapacity)
                    Text("\(queuedCapacity) queued · \(remaining) remaining")
                        .font(.system(.caption2, design: .monospaced).weight(.bold))
                        .foregroundStyle(remaining > 0 ? Color.neonTeal : Color.softRed)
                }
            }

            if let state = store.state, !state.plannedActions.isEmpty {
                LazyVStack(spacing: 10) {
                    ForEach(state.plannedActions) { action in
                        ActionRow(action: action) {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                store.deleteAction(id: action.id)
                            }
                        }
                    }
                }
            } else {
                ContentUnavailableView(
                    "No decisions queued",
                    systemImage: "square.grid.3x3.square",
                    description: Text("Select decisions from the matrix or write a custom order.")
                )
            }
        }
    }
}
