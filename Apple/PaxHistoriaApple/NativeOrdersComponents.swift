import SwiftUI

struct NativeOrdersScreen: View {
    @ObservedObject var store: NativeCampaignStore

    var body: some View {
        NativeDetailScroll(accessibilityIdentifier: "native-orders-screen") {
            NativeSectionHeader(
                title: "Orders",
                subtitle: "Plan concrete instruments, accept suggestions from the selected AI provider, and advance only when the queue is ready.",
                systemImage: "checklist"
            )
            NativeStateNotices(store: store)
            if let state = store.state {
                NativeCampaignObjectivesPanel(state: state)
                if let turn = store.lastTurnReport {
                    NativeAfterActionReportPanel(report: NativeGameEngine.afterActionReport(for: turn, state: state))
                }
            }
            NativeSuggestedActionsPanel(store: store)
            NativeOrdersEditorPanel(store: store)
        }
        .navigationTitle("Orders")
    }
}
