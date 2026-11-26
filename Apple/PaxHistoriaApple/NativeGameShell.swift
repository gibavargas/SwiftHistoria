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
        @State private var isExpandedDrawer = false

        private var activeDrawerDestination: NativeMacDestination? {
            guard let destination = appState.macDestination, destination != .overview else {
                return nil
            }
            return destination
        }

        private func preferredDrawerWidth(for destination: NativeMacDestination, availableWidth: CGFloat) -> CGFloat {
            if isExpandedDrawer {
                return availableWidth
            }
            let target: CGFloat = switch destination {
            case .orders, .worldEconomics:
                820
            case .advisor, .diplomacy, .events, .library, .settings:
                640
            case .overview:
                640
            }
            return min(availableWidth, max(540, target))
        }
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
                        .frame(width: 196)
                        .background(
                            LinearGradient(
                                colors: [NativeWarRoomTheme.graphite, NativeWarRoomTheme.blackboard],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    Rectangle()
                        .fill(NativeWarRoomTheme.brass.opacity(0.18))
                        .frame(width: 1)
                }

                // Detail area with persistent Living Atlas base layer + slide-over drawer
                VStack(spacing: 0) {
                    macTopBar
                    Rectangle()
                        .fill(NativeWarRoomTheme.brass.opacity(0.2))
                        .frame(height: 1)

                    GeometryReader { geometry in
                        ZStack(alignment: .trailing) {
                            NativeOverviewScreen(
                                store: store,
                                onShowEvents: { appState.macDestination = .events },
                                onShowOrders: { appState.macDestination = .orders }
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity)

                            if let dest = activeDrawerDestination {
                                let drawerWidth = preferredDrawerWidth(for: dest, availableWidth: geometry.size.width)

                                if !isExpandedDrawer, drawerWidth < geometry.size.width {
                                    NativeWarRoomTheme.blackboard.opacity(0.38)
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            appState.macDestination = .overview
                                        }
                                        .transition(.opacity)
                                }

                                warRoomDrawer(for: dest)
                                    .frame(width: drawerWidth)
                                    .frame(maxHeight: .infinity)
                                    .transition(reduceMotion ? .opacity : .move(edge: .trailing).combined(with: .opacity))
                                    .zIndex(2)
                            }
                        }
                        .animation(
                            reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.86),
                            value: appState.macDestination
                        )
                        .animation(
                            reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.86),
                            value: isExpandedDrawer
                        )
                    }
                }
            }
            .background(NativeWarRoomTheme.blackboard)
            .accessibilityIdentifier("native-mac-shell")
        }

        private func warRoomDrawer(for destination: NativeMacDestination) -> some View {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Image(systemName: destination.systemImage)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(NativeWarRoomTheme.brass)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(destination.title)
                            .font(NativeWarRoomTheme.displayFont(.headline, weight: .bold))
                            .foregroundStyle(NativeWarRoomTheme.ink)
                        Text("WAR ROOM DOSSIER  ·  ATLAS LIVE")
                            .font(NativeWarRoomTheme.labelFont(.caption2, weight: .semibold))
                            .foregroundStyle(NativeWarRoomTheme.brass.opacity(0.85))
                    }

                    Spacer(minLength: 8)

                    Button {
                        isExpandedDrawer.toggle()
                    } label: {
                        Label(
                            isExpandedDrawer ? "Split Over Map" : "Expanded Dossier",
                            systemImage: isExpandedDrawer ? "rectangle.righthalf.inset.filled" : "arrow.up.left.and.arrow.down.right"
                        )
                        .font(NativeWarRoomTheme.labelFont(.caption2, weight: .bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(NativeWarRoomTheme.olivePanel.opacity(0.85), in: Capsule())
                        .overlay {
                            Capsule()
                                .stroke(NativeWarRoomTheme.brass.opacity(0.32), lineWidth: 1)
                        }
                        .foregroundStyle(NativeWarRoomTheme.parchment)
                    }
                    .buttonStyle(.plain)
                    .help(isExpandedDrawer ? "Switch to Split Over Map drawer width" : "Expand dossier to full workspace width")
                    .accessibilityIdentifier("native-mac-drawer-width-toggle")

                    Button {
                        appState.macDestination = .overview
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "xmark")
                                .font(.system(size: 11, weight: .bold))
                            Text("Map")
                                .font(NativeWarRoomTheme.labelFont(.caption2, weight: .bold))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(NativeWarRoomTheme.threatRed.opacity(0.18), in: Capsule())
                        .overlay {
                            Capsule()
                                .stroke(NativeWarRoomTheme.brass.opacity(0.35), lineWidth: 1)
                        }
                        .foregroundStyle(NativeWarRoomTheme.ink)
                    }
                    .buttonStyle(.plain)
                    .help("Return to Strategic Map (Esc)")
                    .keyboardShortcut(.escape, modifiers: [])
                    .accessibilityLabel("Return to map")
                    .accessibilityIdentifier("native-mac-drawer-close")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    LinearGradient(
                        colors: [NativeWarRoomTheme.graphite, NativeWarRoomTheme.archiveShadow],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                Rectangle()
                    .fill(NativeWarRoomTheme.brass.opacity(0.24))
                    .frame(height: 1)

                NativeMacDetailScreen(
                    destination: destination,
                    store: store,
                    libraryMessage: libraryMessage,
                    onExportCampaign: onExportCampaign,
                    onImportCampaign: onImportCampaign,
                    onSelectDestination: { appState.macDestination = $0 }
                )
            }
            .background(NativeWarRoomTheme.blackboard)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(NativeWarRoomTheme.brass.opacity(0.34))
                    .frame(width: 1.5)
            }
            .shadow(color: Color.black.opacity(0.55), radius: 22, x: -8, y: 0)
            .accessibilityIdentifier("native-mac-war-room-drawer")
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

                Rectangle()
                    .fill(NativeWarRoomTheme.brass.opacity(0.2))
                    .frame(height: 1)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)

                // Navigation list
                List(selection: Binding(
                    get: { appState.macDestination },
                    set: { appState.macDestination = $0 }
                )) {
                    Section {
                        destinationButton(.overview)
                        destinationButton(.orders, badgeCount: queuedOrdersCount, badgeTint: NativeWarRoomTheme.brass)
                    } header: {
                        sidebarSectionHeader("Command Center")
                    }

                    Section {
                        destinationButton(.advisor)
                        destinationButton(.diplomacy, badgeCount: pendingOffersCount, badgeTint: NativeWarRoomTheme.signalCyan)
                        destinationButton(.events, badgeCount: timelineEventsCount, badgeTint: NativeWarRoomTheme.mutedInk)
                        destinationButton(.worldEconomics)
                    } header: {
                        sidebarSectionHeader("Intelligence")
                    }

                    Section {
                        destinationButton(.library)
                        destinationButton(.settings)
                    } header: {
                        sidebarSectionHeader("Campaign")
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

        private func sidebarSectionHeader(_ title: String) -> some View {
            VStack(alignment: .leading, spacing: 4) {
                Text(title.uppercased())
                    .font(NativeWarRoomTheme.labelFont(.caption2, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(NativeWarRoomTheme.oxidizedBrass)
                    .textCase(nil)
                Rectangle()
                    .fill(NativeWarRoomTheme.brass.opacity(0.16))
                    .frame(height: 1)
            }
            .padding(.top, 2)
        }

        private var queuedOrdersCount: Int {
            store.state?.plannedActions.filter { $0.status == .planned }.count ?? 0
        }

        private var pendingOffersCount: Int {
            store.state?.activeOffers.filter { $0.status == .pending && $0.isPlayerFacing }.count ?? 0
        }

        private var timelineEventsCount: Int {
            store.state?.timeline.count ?? 0
        }

        private func destinationButton(
            _ dest: NativeMacDestination,
            badgeCount: Int = 0,
            badgeTint: Color = NativeWarRoomTheme.brass
        ) -> some View {
            let isSelected = (appState.macDestination ?? .overview) == dest
            return Button {
                appState.macDestination = dest
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: dest.systemImage)
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 20)
                        .foregroundStyle(isSelected ? NativeWarRoomTheme.brass : NativeWarRoomTheme.mutedInk)
                    Text(dest.title)
                        .font(NativeWarRoomTheme.bodyFont(.subheadline, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? NativeWarRoomTheme.ink : NativeWarRoomTheme.mutedInk)
                    Spacer(minLength: 4)
                    if badgeCount > 0 {
                        Text("\(badgeCount)")
                            .font(NativeWarRoomTheme.labelFont(.caption2, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(badgeTint.opacity(isSelected ? 0.28 : 0.16), in: Capsule())
                            .overlay {
                                Capsule()
                                    .stroke(badgeTint.opacity(0.32), lineWidth: 0.75)
                            }
                            .foregroundStyle(isSelected ? NativeWarRoomTheme.ink : badgeTint)
                    }
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .listRowBackground(
                isSelected
                    ? NativeWarRoomTheme.brass.opacity(0.1)
                    : Color.clear
            )
            .accessibilityIdentifier(dest.accessibilityIdentifier)
        }

        /// Top toolbar: always visible across all destinations.
        /// Shows key game state and primary actions (advance, toggle sidebar).
        private var macTopBar: some View {
            HStack(spacing: 12) {
                // Toggle sidebar
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        showSidebar.toggle()
                    }
                } label: {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(NativeWarRoomTheme.mutedInk)
                        .frame(width: 26, height: 26)
                        .background(NativeWarRoomTheme.olivePanel.opacity(0.55), in: RoundedRectangle(cornerRadius: 5))
                        .overlay {
                            RoundedRectangle(cornerRadius: 5)
                                .stroke(NativeWarRoomTheme.brass.opacity(0.22), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Toggle sidebar")
                .keyboardShortcut("s", modifiers: [.command, .shift])

                if let state = store.state {
                    NativeCountryStandard(countryCode: state.country.code, size: 32)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(CountryNameResolver.name(forCode: state.country.code, in: state).uppercased())
                            .font(NativeWarRoomTheme.displayFont(.subheadline, weight: .bold))
                            .tracking(0.8)
                            .foregroundStyle(NativeWarRoomTheme.ink)
                            .lineLimit(1)
                        Text("\(state.scenarioName.uppercased())  ·  \(state.gameDate.uppercased())")
                            .font(NativeWarRoomTheme.labelFont(.caption2, weight: .semibold))
                            .foregroundStyle(NativeWarRoomTheme.brass)
                            .lineLimit(1)
                    }

                    Rectangle()
                        .fill(NativeWarRoomTheme.brass.opacity(0.22))
                        .frame(width: 1, height: 26)

                    // Strategic Telemetry Ribbon
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            let growth = state.economicLedger.realGrowthPercent
                            atlasGDPMetric(
                                value: "$\(state.economicLedger.nominalGDPTrillions.formatted(.number.precision(.fractionLength(1))))T",
                                growth: growth
                            )
                            atlasHeaderMetric(
                                label: "BUDGET",
                                value: nativeFormatSignedPercent(state.economicLedger.budgetBalancePercentGDP),
                                tint: state.economicLedger.budgetBalancePercentGDP >= 0 ? NativeWarRoomTheme.fieldGreen : NativeWarRoomTheme.threatRed
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
                                value: "\(state.administrativeCapacity)/100",
                                tint: nativeCapacityColor(for: state.administrativeCapacity)
                            )
                            atlasHeaderMetric(
                                label: "ERA",
                                value: state.techEraTyped.displayName.uppercased(),
                                tint: NativeWarRoomTheme.signalCyan
                            )
                            atlasHeaderMetric(
                                label: "ROUND",
                                value: "R\(state.round)",
                                tint: NativeWarRoomTheme.parchment
                            )
                        }
                    }
                } else {
                    Spacer(minLength: 0)
                }

                // Primary actions
                Button {
                    Task { await store.refreshSuggestedActions(force: true) }
                } label: {
                    Label("Matrix", systemImage: "arrow.clockwise")
                        .labelStyle(.iconOnly)
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 28, height: 28)
                        .background(NativeWarRoomTheme.olivePanel.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
                        .overlay {
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(NativeWarRoomTheme.brass.opacity(0.24), lineWidth: 1)
                        }
                        .foregroundStyle(NativeWarRoomTheme.parchment)
                }
                .buttonStyle(.plain)
                .help("Refresh decision matrix")
                .accessibilityLabel("Refresh decision matrix")
                .disabled(store.isLoadingSuggestions || store.isAdvancing)
                .accessibilityIdentifier("native-mac-toolbar-refresh")

                Button {
                    appState.macDestination = appState.macDestination == .orders ? .overview : .orders
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "checklist")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Orders")
                            .font(NativeWarRoomTheme.labelFont(.caption, weight: .bold))
                        if queuedOrdersCount > 0 {
                            Text("\(queuedOrdersCount)")
                                .font(NativeWarRoomTheme.labelFont(.caption2, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(NativeWarRoomTheme.brass, in: Capsule())
                                .foregroundStyle(NativeWarRoomTheme.blackboard)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        appState.macDestination == .orders ? NativeWarRoomTheme.brass.opacity(0.22) : NativeWarRoomTheme.olivePanel.opacity(0.7),
                        in: Capsule()
                    )
                    .overlay {
                        Capsule()
                            .stroke(NativeWarRoomTheme.brass.opacity(0.32), lineWidth: 1)
                    }
                    .foregroundStyle(NativeWarRoomTheme.ink)
                }
                .buttonStyle(.plain)
                .help("Go to Orders")
                .keyboardShortcut("o", modifiers: [.command])

                Button {
                    store.advance()
                } label: {
                    HStack(spacing: 6) {
                        if store.isAdvancing {
                            ProgressView()
                                .controlSize(.small)
                                .tint(NativeWarRoomTheme.ink)
                        } else {
                            Image(systemName: "calendar.badge.clock")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        Text(store.isAdvancing ? "Advancing…" : "Advance Turn")
                            .font(NativeWarRoomTheme.displayFont(.caption, weight: .bold))
                    }
                    .padding(.horizontal, 13)
                    .padding(.vertical, 6)
                    .background(
                        LinearGradient(
                            colors: store.isAdvancing
                                ? [Color.gray.opacity(0.25), Color.gray.opacity(0.18)]
                                : [NativeWarRoomTheme.threatRed.opacity(0.92), Color(hex: "#6d291f")],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        in: Capsule()
                    )
                    .overlay {
                        Capsule()
                            .stroke(store.isAdvancing ? Color.gray.opacity(0.3) : NativeWarRoomTheme.brass.opacity(0.55), lineWidth: 1)
                    }
                    .foregroundStyle(store.isAdvancing ? Color.secondary : NativeWarRoomTheme.ink)
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
            .background(
                LinearGradient(
                    colors: [NativeWarRoomTheme.graphite.opacity(0.98), NativeWarRoomTheme.archiveShadow],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }

        private func atlasGDPMetric(value: String, growth: Double) -> some View {
            VStack(alignment: .leading, spacing: 1) {
                Text("GDP")
                    .font(NativeWarRoomTheme.labelFont(.caption2, weight: .semibold))
                    .foregroundStyle(NativeWarRoomTheme.mutedInk)
                HStack(spacing: 4) {
                    Text(value)
                        .font(NativeWarRoomTheme.labelFont(.caption, weight: .bold))
                        .foregroundStyle(NativeWarRoomTheme.ink)
                    Text(nativeFormatSignedPercent(growth))
                        .font(NativeWarRoomTheme.labelFont(.caption2, weight: .bold))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(
                            (growth >= 0 ? NativeWarRoomTheme.fieldGreen : NativeWarRoomTheme.threatRed).opacity(0.18),
                            in: RoundedRectangle(cornerRadius: 3)
                        )
                        .foregroundStyle(growth >= 0 ? NativeWarRoomTheme.fieldGreen : NativeWarRoomTheme.threatRed)
                }
            }
            .fixedSize()
            .accessibilityElement(children: .combine)
            .accessibilityLabel("GDP: \(value), growth \(nativeFormatSignedPercent(growth))")
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
            .fixedSize()
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
