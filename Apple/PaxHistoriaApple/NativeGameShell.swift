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
        @EnvironmentObject var appState: AppState
        @State private var showSidebar = true
    #endif

    var body: some View {
        ZStack {
            #if os(iOS)
                iOSBody
            #else
                macBody
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
        .onAppear {
            #if os(macOS)
                appState.isGameActive = store.state != nil
            #endif
        }
        .onReceive(NotificationCenter.default.publisher(for: .exportCampaign)) { _ in
            onExportCampaign()
        }
        .onReceive(NotificationCenter.default.publisher(for: .importCampaign)) { _ in
            onImportCampaign()
        }
        .onReceive(NotificationCenter.default.publisher(for: .advanceTurn)) { _ in
            store.advance()
        }
        .onReceive(NotificationCenter.default.publisher(for: .cancelTurn)) { _ in
            store.cancelInFlightTurn()
        }
        .onReceive(NotificationCenter.default.publisher(for: .refreshSuggestions)) { _ in
            Task { await store.refreshSuggestedActions(force: true) }
        }
    }

    // MARK: - macOS Body

    #if os(macOS)
        private var macBody: some View {
            HStack(spacing: 0) {
                if showSidebar {
                    sidebar
                        .frame(width: 184)
                        .background(
                            LinearGradient(
                                colors: [NativeWarRoomTheme.graphite, NativeWarRoomTheme.blackboard],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    Divider()
                        .background(NativeWarRoomTheme.brass.opacity(0.12))
                }

                // Detail area with toolbar
                VStack(spacing: 0) {
                    macTopBar
                    Divider().background(NativeWarRoomTheme.brass.opacity(0.12))

                    NativeMacDetailScreen(
                        destination: appState.macDestination ?? .overview,
                        store: store,
                        libraryMessage: libraryMessage,
                        onExportCampaign: onExportCampaign,
                        onImportCampaign: onImportCampaign,
                        onSelectDestination: { appState.macDestination = $0 }
                    )
                }
            }
            .background(NativeWarRoomTheme.blackboard)
            .accessibilityIdentifier("native-mac-shell")
        }

        /// Left sidebar: slim navigation list with all destinations.
        private var sidebar: some View {
            VStack(spacing: 0) {
                // App identity header
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 9) {
                        Image(systemName: "location.north.circle.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(NativeWarRoomTheme.brass)
                        Text("PAX HISTORIA")
                            .font(NativeWarRoomTheme.displayFont(.headline, weight: .bold))
                            .tracking(1.1)
                            .foregroundStyle(NativeWarRoomTheme.ink)
                    }
                    .padding(.top, 16)
                    .padding(.bottom, 4)

                    Text("THE LIVING ATLAS")
                        .font(NativeWarRoomTheme.labelFont(.caption2, weight: .semibold))
                        .foregroundStyle(NativeWarRoomTheme.mutedInk)
                        .padding(.leading, 30)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)

                Divider().background(NativeWarRoomTheme.brass.opacity(0.12))
                    .padding(.vertical, 8)

                // Navigation list
                List(selection: Binding(
                    get: { appState.macDestination },
                    set: { appState.macDestination = $0 }
                )) {
                    Section {
                        destinationButton(.overview)
                        destinationButton(.orders)
                    } header: {
                        Text("Command Center")
                            .font(NativeWarRoomTheme.labelFont(.caption2))
                            .foregroundStyle(NativeWarRoomTheme.mutedInk)
                            .textCase(nil)
                    }

                    Section {
                        destinationButton(.advisor)
                        destinationButton(.diplomacy)
                        destinationButton(.events)
                        destinationButton(.worldEconomics)
                    } header: {
                        Text("Intelligence")
                            .font(NativeWarRoomTheme.labelFont(.caption2))
                            .foregroundStyle(NativeWarRoomTheme.mutedInk)
                            .textCase(nil)
                    }

                    Section {
                        destinationButton(.library)
                        destinationButton(.settings)
                    } header: {
                        Text("Campaign")
                            .font(NativeWarRoomTheme.labelFont(.caption2))
                            .foregroundStyle(NativeWarRoomTheme.mutedInk)
                            .textCase(nil)
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
                .background(Color.clear)

                // Bottom: compact crisis dossier, kept off the map itself.
                if let state = store.state {
                    let crises = NativeCrisisDetector.activeCrises(for: state)
                    if let topCrisis = crises.first {
                        Button {
                            appState.macDestination = .overview
                        } label: {
                            VStack(alignment: .leading, spacing: 7) {
                                HStack(spacing: 6) {
                                    Image(systemName: topCrisis.kind.systemImage)
                                        .font(.caption.weight(.bold))
                                    Text("CRISIS DOSSIER")
                                        .font(NativeWarRoomTheme.labelFont(.caption2))
                                    Spacer()
                                    Text("\(crises.count)")
                                        .font(NativeWarRoomTheme.labelFont(.caption2))
                                }

                                Text(topCrisis.kind.displayName.uppercased())
                                    .font(NativeWarRoomTheme.labelFont(.caption2))
                                    .foregroundStyle(topCrisis.accentColor)
                                    .lineLimit(1)

                                Text(topCrisis.title)
                                    .font(NativeWarRoomTheme.displayFont(.caption, weight: .semibold))
                                    .foregroundStyle(NativeWarRoomTheme.ink)
                                    .lineLimit(2)
                            }
                            .padding(11)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(topCrisis.accentColor.opacity(0.11), in: RoundedRectangle(cornerRadius: 6))
                            .overlay {
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(topCrisis.accentColor.opacity(0.38), lineWidth: 1)
                            }
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(topCrisis.accentColor)
                        .help("View active crises on the Overview")
                        .accessibilityLabel("\(crises.count) active crises. \(topCrisis.title)")
                        .padding(.horizontal, 10)
                        .padding(.bottom, 10)
                    }
                }
            }
        }

        private func destinationButton(_ dest: NativeMacDestination) -> some View {
            let isSelected = appState.macDestination == dest
            return Button {
                appState.macDestination = dest
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: dest.systemImage)
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 20)
                        .foregroundStyle(isSelected ? NativeWarRoomTheme.brass : .secondary)
                    Text(dest.title)
                        .font(NativeWarRoomTheme.bodyFont(.subheadline, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? NativeWarRoomTheme.ink : NativeWarRoomTheme.mutedInk)
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .listRowBackground(
                isSelected
                    ? NativeWarRoomTheme.brass.opacity(0.08)
                    : Color.clear
            )
            .accessibilityIdentifier(dest.accessibilityIdentifier)
        }

        /// Top toolbar: always visible across all destinations.
        /// Shows key game state and primary actions (advance, toggle sidebar).
        private var macTopBar: some View {
            HStack(spacing: 14) {
                // Toggle sidebar
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        showSidebar.toggle()
                    }
                } label: {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Toggle sidebar")
                .keyboardShortcut("s", modifiers: [.command, .shift])

                if let state = store.state {
                    NativeCountryStandard(countryCode: state.country.code, size: 30)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(CountryNameResolver.name(forCode: state.country.code, in: state).uppercased())
                            .font(NativeWarRoomTheme.displayFont(.subheadline, weight: .bold))
                            .tracking(0.7)
                            .foregroundStyle(NativeWarRoomTheme.ink)
                            .lineLimit(1)
                        Text(state.gameDate.uppercased())
                            .font(NativeWarRoomTheme.labelFont(.caption2, weight: .semibold))
                            .foregroundStyle(NativeWarRoomTheme.brass)
                    }

                    Divider().frame(height: 24)
                }

                // Current destination title
                if let dest = appState.macDestination {
                    Label(dest.title, systemImage: dest.systemImage)
                        .font(NativeWarRoomTheme.labelFont(.caption, weight: .semibold))
                        .foregroundStyle(NativeWarRoomTheme.mutedInk)
                }

                Divider().frame(height: 20)

                // Game state summary (compact)
                if let state = store.state {
                    HStack(spacing: 14) {
                        atlasHeaderMetric(
                            label: "GDP",
                            value: "$\(state.economicLedger.nominalGDPTrillions.formatted(.number.precision(.fractionLength(1))))T",
                            tint: NativeWarRoomTheme.ink
                        )
                        atlasHeaderMetric(
                            label: "STABILITY",
                            value: "\(state.stability)%",
                            tint: NativeWarRoomTheme.statusColor(for: state.stability)
                        )
                        atlasHeaderMetric(
                            label: "TENSION",
                            value: "\(state.worldTension)%",
                            tint: NativeWarRoomTheme.statusColor(for: state.worldTension, highIsGood: false)
                        )
                        atlasHeaderMetric(
                            label: "CAPACITY",
                            value: "\(state.administrativeCapacity)",
                            tint: nativeCapacityColor(for: state.administrativeCapacity)
                        )

                        Text("R\(state.round)")
                            .font(NativeWarRoomTheme.labelFont(.caption2))
                            .foregroundStyle(NativeWarRoomTheme.mutedInk)
                    }
                }

                Spacer()

                // Primary actions
                Button {
                    Task { await store.refreshSuggestedActions(force: true) }
                } label: {
                    Label("Matrix", systemImage: "arrow.clockwise")
                        .labelStyle(.iconOnly)
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
                .help("Refresh decision matrix")
                .accessibilityLabel("Refresh decision matrix")
                .disabled(store.isLoadingSuggestions || store.isAdvancing)
                .accessibilityIdentifier("native-mac-toolbar-refresh")

                Button {
                    appState.macDestination = .orders
                } label: {
                    Label("Orders", systemImage: "checklist")
                        .labelStyle(.titleAndIcon)
                        .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.plain)
                .help("Go to Orders")
                .keyboardShortcut("o", modifiers: [.command])

                Button {
                    store.advance()
                } label: {
                    HStack(spacing: 4) {
                        if store.isAdvancing {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "calendar.badge.clock")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        Text(store.isAdvancing ? "Advancing…" : "Advance")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(store.isAdvancing ? Color.gray.opacity(0.15) : NativeWarRoomTheme.brass.opacity(0.18), in: Capsule())
                    .foregroundStyle(store.isAdvancing ? .secondary : NativeWarRoomTheme.brass)
                }
                .buttonStyle(.plain)
                .disabled(store.isAdvancing)
                .help("Advance one 3-month turn")
                .keyboardShortcut("]", modifiers: [.command])
                .accessibilityIdentifier("native-mac-toolbar-advance")

                if store.isAdvancing {
                    Button {
                        store.cancelInFlightTurn()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(Color.softRed)
                    }
                    .buttonStyle(.plain)
                    .help("Cancel turn")
                    .accessibilityLabel("Cancel turn in flight")
                    .keyboardShortcut(".", modifiers: [.command])
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(NativeWarRoomTheme.archiveShadow.opacity(0.96))
        }

        private func atlasHeaderMetric(label: String, value: String, tint: Color) -> some View {
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(NativeWarRoomTheme.labelFont(.caption2, weight: .semibold))
                    .foregroundStyle(NativeWarRoomTheme.mutedInk)
                Text(value)
                    .font(NativeWarRoomTheme.labelFont(.caption, weight: .bold))
                    .foregroundStyle(tint)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(label): \(value)")
        }
    #endif

    // MARK: - iOS Body

    #if os(iOS)
        private var iOSBody: some View {
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
            .background(NativeWarRoomTheme.blackboard)
            .tint(NativeWarRoomTheme.brass)
            .toolbarBackground(NativeWarRoomTheme.blackboard, for: .tabBar)
            .toolbarBackground(.visible, for: .tabBar)
            .transaction { transaction in
                if reduceMotion {
                    transaction.animation = nil
                }
            }
            .accessibilityIdentifier("native-ios-tab-shell")
        }
    #endif
}
