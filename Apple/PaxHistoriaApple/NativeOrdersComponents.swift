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
