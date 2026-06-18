import SwiftUI

struct NativeGameShell: View {
    @ObservedObject var store: NativeCampaignStore
    let libraryMessage: String?
    let onExportCampaign: () -> Void
    let onImportCampaign: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedTab: NativeGameTab = .map
    @State private var selectedIntelSection: NativeIntelSection = .advisor
    @AppStorage("hasSeenInGameOnboarding") private var hasSeenOnboarding = false
    @State private var showHelpOverlay = false
    #if os(macOS)
        @State private var selectedDestination: NativeMacDestination? = .overview
    #endif

    var body: some View {
        ZStack {
            #if os(iOS)
                TabView(selection: $selectedTab) {
                    NativeMapScreen(
                        store: store,
                        onShowOrders: { selectedTab = .orders },
                        onShowAdvisor: {
                            selectedIntelSection = .advisor
                            selectedTab = .intel
                        },
                        onShowDiplomacy: {
                            selectedIntelSection = .diplomacy
                            selectedTab = .intel
                        }
                    )
                    .tag(NativeGameTab.map)
                    .tabItem {
                        Label("Map", systemImage: "globe.europe.africa")
                    }

                    NativeOrdersScreen(store: store)
                        .tag(NativeGameTab.orders)
                        .tabItem {
                            Label("Orders", systemImage: "checklist")
                        }

                    NativeIntelScreen(
                        store: store,
                        selectedSection: $selectedIntelSection,
                        libraryMessage: libraryMessage,
                        onExportCampaign: onExportCampaign,
                        onImportCampaign: onImportCampaign
                    )
                    .tag(NativeGameTab.intel)
                    .tabItem {
                        Label("Intel", systemImage: "person.text.rectangle")
                    }
                }
                .background(.black)
                .transaction { transaction in
                    if reduceMotion {
                        transaction.animation = nil
                    }
                }
                .accessibilityIdentifier("native-ios-tab-shell")
            #else
                NavigationSplitView {
                    List(selection: $selectedDestination) {
                        Section("Campaign") {
                            ForEach(NativeMacDestination.allCases) { destination in
                                Label(destination.title, systemImage: destination.systemImage)
                                    .tag(destination)
                                    .accessibilityIdentifier(destination.accessibilityIdentifier)
                            }
                        }
                    }
                    .listStyle(.sidebar)
                    .navigationTitle("SwiftHistoria")
                    .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
                } detail: {
                    NativeMacDetailScreen(
                        destination: selectedDestination ?? .overview,
                        store: store,
                        libraryMessage: libraryMessage,
                        onExportCampaign: onExportCampaign,
                        onImportCampaign: onImportCampaign,
                        onSelectDestination: { selectedDestination = $0 }
                    )
                    .toolbar {
                        ToolbarItemGroup {
                            Button {
                                selectedDestination = .orders
                            } label: {
                                Label("Orders", systemImage: "checklist")
                                    .labelStyle(.titleAndIcon)
                            }
                            .keyboardShortcut("o", modifiers: [.command])

                            Button {
                                Task { await store.advance(months: 1) }
                            } label: {
                                Label("Advance", systemImage: "calendar.badge.clock")
                                    .labelStyle(.titleAndIcon)
                            }
                            .disabled(store.isAdvancing)
                            .keyboardShortcut("]", modifiers: [.command])
                            .accessibilityIdentifier("native-mac-toolbar-advance")

                            Button {
                                selectedDestination = .advisor
                            } label: {
                                Label("Advisor", systemImage: "brain.head.profile")
                                    .labelStyle(.titleAndIcon)
                            }
                            .keyboardShortcut("a", modifiers: [.command, .shift])
                        }
                    }
                }
                .background(.black)
                .accessibilityIdentifier("native-mac-split-shell")
            #endif

            if store.isAdvancing {
                TurnTransitionOverlay(store: store)
                    .transition(.opacity)
                    .zIndex(99)
            }
        }
        .animation(.easeInOut, value: store.isAdvancing)
        .sheet(isPresented: Binding(
            get: { !hasSeenOnboarding && store.state != nil },
            set: { hasSeenOnboarding = !$0 }
        )) {
            NativeContextualHelpOverlay(isPresented: Binding(
                get: { !hasSeenOnboarding },
                set: { hasSeenOnboarding = !$0 }
            ))
        }
    }
}
