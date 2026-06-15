import SwiftUI

enum NativeGameTab: Hashable {
    case map
    case orders
    case intel
}

enum NativeIntelSection: String, CaseIterable, Hashable, Identifiable {
    case advisor
    case diplomacy
    case events
    case worldEconomics
    case library
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .advisor: "Advisor"
        case .diplomacy: "Diplomacy"
        case .events: "Events"
        case .worldEconomics: "Economics"
        case .library: "Library"
        case .settings: "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .advisor: "brain.head.profile"
        case .diplomacy: "bubble.left.and.bubble.right"
        case .events: "clock"
        case .worldEconomics: "chart.bar.xaxis"
        case .library: "folder"
        case .settings: "slider.horizontal.3"
        }
    }

    var accessibilityIdentifier: String {
        "native-intel-section-\(rawValue)"
    }
}

#if os(macOS)
enum NativeMacDestination: String, CaseIterable, Hashable, Identifiable {
    case overview
    case orders
    case advisor
    case diplomacy
    case events
    case worldEconomics
    case library
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .orders: "Orders"
        case .advisor: "Advisor"
        case .diplomacy: "Diplomacy"
        case .events: "Events"
        case .worldEconomics: "Economics"
        case .library: "Library"
        case .settings: "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .overview: "globe.europe.africa"
        case .orders: "checklist"
        case .advisor: "brain.head.profile"
        case .diplomacy: "bubble.left.and.bubble.right"
        case .events: "clock"
        case .worldEconomics: "chart.bar.xaxis"
        case .library: "folder"
        case .settings: "slider.horizontal.3"
        }
    }

    var accessibilityIdentifier: String {
        "native-mac-destination-\(rawValue)"
    }
}
#endif

enum ConsoleTab: String, CaseIterable, Identifiable {
    case orders = "orders"
    case suggestions = "suggestions"
    case advisor = "advisor"
    case diplomacy = "diplomacy"
    case events = "events"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .orders: "Directives"
        case .suggestions: "Suggestions"
        case .advisor: "Advisor"
        case .diplomacy: "Diplomacy"
        case .events: "Events"
        }
    }

    var systemImage: String {
        switch self {
        case .orders: "checklist"
        case .suggestions: "sparkles"
        case .advisor: "brain.head.profile"
        case .diplomacy: "bubble.left.and.bubble.right"
        case .events: "clock"
        }
    }
}

func getGDP(state: NativeCampaignState) -> (value: String, delta: String) {
    Native2010WorldModel.gdpMetric(for: state)
}

func getInfluence(state: NativeCampaignState) -> (value: String, delta: String) {
    Native2010WorldModel.influenceMetric(for: state)
}

func getTechLevel(state: NativeCampaignState) -> (value: String, delta: String) {
    Native2010WorldModel.techMetric(for: state)
}

func getEnergySecurity(state: NativeCampaignState) -> String {
    Native2010WorldModel.energyMetric(for: state)
}

func getFoodSecurity(state: NativeCampaignState) -> String {
    Native2010WorldModel.foodMetric(for: state)
}

func getNuclearStatus(state: NativeCampaignState) -> String {
    Native2010WorldModel.nuclearMetric(for: state)
}

func native2010RelationColor(_ relation: Native2010Relation) -> Color {
    switch relation {
    case .ally, .partner:
        return Color.neonTeal
    case .neutral, .watch:
        return Color.alertGold
    case .rival:
        return Color.softRed
    }
}

func native2010SignalColor(_ level: Native2010SignalLevel) -> Color {
    switch level {
    case .low:
        return Color.neonTeal
    case .medium, .watch:
        return Color.alertGold
    case .high:
        return Color.softRed
    }
}

struct NativeLatestIntelTicker: View {
    let latestEvent: NativeCampaignEvent?
    @State private var pulse = false

    var body: some View {
        Group {
            if let event = latestEvent {
                HStack(spacing: 8) {
                    Circle()
                        .fill(event.importance == .severe ? Color.softRed : Color.alertGold)
                        .frame(width: 6, height: 6)
                        .opacity(pulse ? 0.3 : 1.0)
                        .scaleEffect(pulse ? 1.2 : 1.0)
                        .onAppear {
                            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                                pulse = true
                            }
                        }

                    Text("LATEST SIGNAL //")
                        .font(.system(.caption2, design: .monospaced).weight(.bold))
                        .foregroundStyle(Color.glowingCyan)

                    Text(event.title.uppercased())
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Spacer()

                    if let firstEffect = event.strategicEffects.first {
                        let isPos = firstEffect.magnitude >= 0
                        Text("\(isPos ? "+" : "")\(firstEffect.magnitude) \(firstEffect.track.displayName.uppercased())")
                            .font(.system(.caption2, design: .monospaced).weight(.bold))
                            .foregroundStyle(isPos ? Color.neonTeal : Color.softRed)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .glassmorphicCard(borderColor: Color.white.opacity(0.1), cornerRadius: 8)
            } else {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.iceBlue.opacity(0.4))
                        .frame(width: 6, height: 6)
                    Text("NO GEOPOLITICAL SIGNALS LOGGED YET")
                        .font(.system(.caption2, design: .monospaced).weight(.bold))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .glassmorphicCard(borderColor: Color.white.opacity(0.08), cornerRadius: 8)
            }
        }
    }
}

struct NativeTurnProgressPanel: View {
    let progress: NativeTurnProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                    .tint(Color.glowingCyan)
                Text(progress.phase.uppercased())
                    .font(.system(.caption, design: .monospaced).weight(.bold))
                    .foregroundStyle(Color.glowingCyan)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                Spacer()
                Text("\(progress.completedLanes)/\(progress.totalLanes)")
                    .font(.system(.caption2, design: .monospaced).weight(.bold))
                    .foregroundStyle(Color.iceBlue)
            }
            Text(progress.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            ProgressView(value: progress.fraction)
                .tint(Color.glowingCyan)
                .accessibilityIdentifier("native-turn-progress-bar")
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.spaceBlack.opacity(0.86), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.glowingCyan.opacity(0.28), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("native-turn-progress-panel")
    }
}

struct NativeGameShell: View {
    @ObservedObject var store: NativeCampaignStore
    let libraryMessage: String?
    let onExportCampaign: () -> Void
    let onImportCampaign: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedTab: NativeGameTab = .map
    @State private var selectedIntelSection: NativeIntelSection = .advisor
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
                        .accessibilityIdentifier("native-map-tab")
                }

                NativeOrdersScreen(store: store)
                    .tag(NativeGameTab.orders)
                    .tabItem {
                        Label("Orders", systemImage: "checklist")
                            .accessibilityIdentifier("native-orders-tab")
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
                        .accessibilityIdentifier("native-intel-tab")
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
    }
}

struct NativeMapScreen: View {
    @ObservedObject var store: NativeCampaignStore
    let onShowOrders: () -> Void
    let onShowAdvisor: () -> Void
    let onShowDiplomacy: () -> Void

    @Environment(\.colorSchemeContrast) private var contrast
    @State private var isConsoleExpanded = true

    var body: some View {
        Group {
            if let state = store.state {
                ZStack(alignment: .top) {
                    NativeWorldMap(state: state, minHeight: 360)
                        .ignoresSafeArea()
                        .id(state.country.code)

                    // Top Floating HUD
                    VStack(spacing: 8) {
                        NativeMapHUD(state: state)
                        NativeLatestIntelTicker(latestEvent: state.timeline.first)
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

                    // Bottom Floating Console Drawer & Advance Button
                    VStack(spacing: 12) {
                        Spacer()

                        HStack {
                            Spacer()
                            NativeFloatingAdvanceButton(store: store)
                                .padding(.trailing, 16)
                        }

                        CommandConsoleDrawer(store: store, isExpanded: $isConsoleExpanded)
                            .padding(.horizontal, 14)
                            .padding(.bottom, 10)
                    }
                }
                .task(id: "\(state.country.code)-\(state.round)") {
                    await store.refreshSuggestedActionsIfNeeded()
                }
                .accessibilityIdentifier("native-map-screen")
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

                    Text(isExpanded ? "COLLAPSE DIRECTIVES" : "COMMAND CONSOLE")
                        .font(.system(.subheadline, design: .monospaced).weight(.bold))
                        .foregroundStyle(.white)

                    if let state = store.state {
                        let plannedCount = state.plannedActions.filter { $0.status == .planned }.count
                        Text("// \(plannedCount) DIRECTIVES")
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
                .font(.system(size: 8, weight: .bold, design: .monospaced))
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
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(status.uppercased())
                .font(.system(size: 9, weight: .bold, design: .monospaced))
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
                .font(.system(size: 10, weight: .bold, design: .monospaced))
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

    var body: some View {
        HStack(spacing: 16) {
            Text("TIMELINE")
                .font(.system(.caption, design: .monospaced).weight(.bold))
                .foregroundStyle(Color.glowingCyan)

            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.white.opacity(0.15))
                    .frame(height: 2)

                if store.state != nil {
                    let totalYears = 9
                    let step = (currentYear - baseYear)
                    let clampStep = max(0, min(totalYears - 1, step))

                    GeometryReader { geo in
                        let yearWidth = geo.size.width / CGFloat(totalYears - 1)
                        let offset = CGFloat(clampStep) * yearWidth

                        Circle()
                            .fill(Color.glowingCyan)
                            .frame(width: 8, height: 8)
                            .position(x: offset, y: geo.size.height / 2)
                            .shadow(color: Color.glowingCyan, radius: 4)
                    }
                    .frame(height: 10)
                }

                HStack {
                    ForEach(0..<9) { i in
                        let year = baseYear + i
                        VStack(spacing: 4) {
                            Text("\(year)")
                                .font(.system(size: 9, design: .monospaced).weight(.bold))
                                .foregroundStyle(currentYear == year ? Color.glowingCyan : .secondary)
                            Circle()
                                .fill(currentYear == year ? Color.glowingCyan : Color.white.opacity(0.2))
                                .frame(width: 4, height: 4)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .frame(maxWidth: .infinity)

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
        .padding(12)
        .warRoomDossier(borderColor: NativeWarRoomTheme.brass.opacity(0.2), cornerRadius: 10)
    }
}

struct NativeOverviewScreen: View {
    @ObservedObject var store: NativeCampaignStore
    let onShowEvents: () -> Void
    @State private var showInspector = true

    private func year(in value: String, fallback: Int) -> Int {
        let pattern = "\\b(19|20)\\d{2}\\b"
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
           let range = Range(match.range, in: value),
           let year = Int(value[range]) {
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
                    NativeLatestIntelTicker(latestEvent: state.timeline.first)
                    if let progress = store.turnProgress {
                        NativeTurnProgressPanel(progress: progress)
                    }
                    NativeWorldMap(state: state, minHeight: 360)
                        .id(state.country.code)
                    NativeMetricsGrid(state: state)
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
                    Text("AI COMMAND")
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
                            Text("FILE DIRECTIVE")
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
                    Text("COMMAND HISTORY")
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
            NativeMapHUD(state: state)
                .padding(.horizontal, 16)
                .padding(.top, 14)

            NativeLatestIntelTicker(latestEvent: state.timeline.first)
                .padding(.horizontal, 16)
                .padding(.top, 8)

            if let progress = store.turnProgress {
                NativeTurnProgressPanel(progress: progress)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
            }

            NativeWorldMap(state: state, minHeight: 320)
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
                                    .font(.system(size: 10, design: .monospaced).weight(.bold))
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
            .font(.system(size: 8))
            .foregroundStyle(NativeWarRoomTheme.mutedInk)
        }
    }
}

struct NativeOrdersScreen: View {
    @ObservedObject var store: NativeCampaignStore

    var body: some View {
        NativeDetailScroll(accessibilityIdentifier: "native-orders-screen") {
            NativeSectionHeader(
                title: "Orders",
                subtitle: "Plan concrete instruments, accept Apple suggestions, and advance only when the queue is ready.",
                systemImage: "checklist"
            )
            NativeStateNotices(store: store)
            NativeSuggestedActionsPanel(store: store)
            NativeOrdersEditorPanel(store: store)
        }
        .navigationTitle("Orders")
    }
}

struct NativeIntelScreen: View {
    @ObservedObject var store: NativeCampaignStore
    @Binding var selectedSection: NativeIntelSection
    let libraryMessage: String?
    let onExportCampaign: () -> Void
    let onImportCampaign: () -> Void

    var body: some View {
        NativeDetailScroll(accessibilityIdentifier: "native-intel-screen") {
            NativeSectionHeader(
                title: "Intel",
                subtitle: "Advisor, diplomacy, events, and campaign library are grouped away from the map for mobile clarity.",
                systemImage: "person.text.rectangle"
            )
            NativeIntelSectionSelector(selectedSection: $selectedSection)

            switch selectedSection {
            case .advisor:
                NativeAdvisorPanel(store: store)
            case .diplomacy:
                NativeDiplomacyPanel(store: store)
            case .events:
                NativeEventsPanel(state: store.state)
            case .worldEconomics:
                if let state = store.state {
                    NativeWorldEconomicsPanel(store: store, state: state)
                } else {
                    Text("No campaign loaded.")
                }
            case .library:
                NativeLibraryPanel(
                    message: libraryMessage,
                    onExportCampaign: onExportCampaign,
                    onImportCampaign: onImportCampaign
                )
            case .settings:
                NativeSettingsPanel(store: store)
            }
        }
        .navigationTitle("Intel")
    }
}

struct NativeIntelSectionSelector: View {
    @Binding var selectedSection: NativeIntelSection

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(NativeIntelSection.allCases) { section in
                    Button {
                        selectedSection = section
                    } label: {
                        Label(section.title, systemImage: section.systemImage)
                            .font(.callout.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(section == selectedSection ? Color.accentColor.opacity(0.22) : Color.white.opacity(0.07), in: Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(section == selectedSection ? [.isSelected] : [])
                    .accessibilityIdentifier(section.accessibilityIdentifier)
                }
            }
            .padding(.vertical, 2)
        }
        .accessibilityIdentifier("native-intel-section-selector")
    }
}

#if os(macOS)
struct NativeMacDetailScreen: View {
    let destination: NativeMacDestination
    @ObservedObject var store: NativeCampaignStore
    let libraryMessage: String?
    let onExportCampaign: () -> Void
    let onImportCampaign: () -> Void
    let onSelectDestination: (NativeMacDestination) -> Void

    var body: some View {
        Group {
            switch destination {
            case .overview:
                NativeOverviewScreen(store: store) {
                    onSelectDestination(.events)
                }
            case .orders:
                NativeOrdersScreen(store: store)
            case .advisor:
                NativeDetailScroll(accessibilityIdentifier: "native-advisor-screen") {
                    NativeAdvisorPanel(store: store)
                }
            case .diplomacy:
                NativeDetailScroll(accessibilityIdentifier: "native-diplomacy-screen") {
                    NativeDiplomacyPanel(store: store)
                }
            case .events:
                NativeDetailScroll(accessibilityIdentifier: "native-events-screen") {
                    NativeEventsPanel(state: store.state)
                }
            case .worldEconomics:
                NativeDetailScroll(accessibilityIdentifier: "native-world-economics-screen") {
                    if let state = store.state {
                        NativeWorldEconomicsPanel(store: store, state: state)
                    } else {
                        Text("No campaign loaded.")
                    }
                }
            case .library:
                NativeDetailScroll(accessibilityIdentifier: "native-library-screen") {
                    NativeLibraryPanel(
                        message: libraryMessage,
                        onExportCampaign: onExportCampaign,
                        onImportCampaign: onImportCampaign
                    )
                }
            case .settings:
                NativeDetailScroll(accessibilityIdentifier: "native-settings-screen") {
                    NativeSettingsPanel(store: store)
                }
            }
        }
        .navigationTitle(destination.title)
    }
}
#endif

struct NativeDetailScroll<Content: View>: View {
    let accessibilityIdentifier: String
    let content: Content

    init(accessibilityIdentifier: String, @ViewBuilder content: () -> Content) {
        self.accessibilityIdentifier = accessibilityIdentifier
        self.content = content()
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                content
            }
            .padding(20)
            .frame(maxWidth: 1080, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(.black.opacity(0.94))
        .accessibilityIdentifier(accessibilityIdentifier)
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
        return state.aiReadiness.ok ? Color.glowingCyan : Color.softRed
    }

    var body: some View {
        let gdp = getGDP(state: state)
        let influence = getInfluence(state: state)
        let tech = getTechLevel(state: state)
        let energy = getEnergySecurity(state: state)
        let food = getFoodSecurity(state: state)
        let nuclear = getNuclearStatus(state: state)
        let ledger = state.economicLedger
        let budgetTint = ledger.budgetBalancePercentGDP >= -3 ? Color.neonTeal : (ledger.budgetBalancePercentGDP >= -7 ? Color.alertGold : Color.softRed)
        let debtTint = ledger.publicDebtPercentGDP <= 70 ? Color.neonTeal : (ledger.publicDebtPercentGDP <= 110 ? Color.alertGold : Color.softRed)
        let inflationTint = ledger.inflationPercent <= 4 ? Color.neonTeal : (ledger.inflationPercent <= 8 ? Color.alertGold : Color.softRed)

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(state.country.name.uppercased())
                    .font(.system(.title3, design: .monospaced).weight(.bold))
                    .foregroundStyle(Color.glowingCyan)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                Spacer()
                Image(systemName: "satellite.fill")
                    .foregroundStyle(Color.iceBlue)
                    .font(.caption)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    NativeStatusChip(text: "Capacity \(state.administrativeCapacity)/100", systemImage: "sparkles", tintColor: state.administrativeCapacity >= 30 ? Color.glowingCyan : Color.softRed)
                    NativeStatusChip(text: "Round \(state.round)", systemImage: "number", tintColor: Color.iceBlue)
                    NativeStatusChip(text: state.gameDate, systemImage: "calendar", tintColor: Color.iceBlue)
                    NativeStatusChip(text: "GDP \(gdp.value) (\(gdp.delta))", systemImage: "dollarsign.circle", tintColor: Color.neonTeal)
                    NativeStatusChip(text: "Budget \(nativeFormatSignedPercent(ledger.budgetBalancePercentGDP))", systemImage: "banknote", tintColor: budgetTint)
                    NativeStatusChip(text: "Debt \(nativeFormatPercent(ledger.publicDebtPercentGDP))", systemImage: "creditcard", tintColor: debtTint)
                    NativeStatusChip(text: "Inflation \(nativeFormatPercent(ledger.inflationPercent))", systemImage: "chart.line.uptrend.xyaxis", tintColor: inflationTint)
                    NativeStatusChip(text: "Stability \(state.stability)%", systemImage: "building.columns", tintColor: stabilityTint)
                    NativeStatusChip(text: "Influence \(influence.value) (\(influence.delta))", systemImage: "person.line.dotted.person", tintColor: Color.iceBlue)
                    NativeStatusChip(text: "Tech Lvl \(tech.value)", systemImage: "cpu", tintColor: Color.glowingCyan)
                    NativeStatusChip(text: "Energy \(energy)", systemImage: "bolt.circle", tintColor: Color.alertGold)
                    NativeStatusChip(text: "Food \(food)", systemImage: "leaf.circle", tintColor: Color.neonTeal)
                    NativeStatusChip(text: "Nuclear \(nuclear)", systemImage: "atom", tintColor: Color.iceBlue)
                    NativeStatusChip(text: "Tension \(state.worldTension)%", systemImage: "waveform.path.ecg", tintColor: tensionTint)
                    NativeStatusChip(text: nativeFormatHUDAvailability(state.aiReadiness.availability), systemImage: "brain", tintColor: aiTint)
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

struct NativeFloatingAdvanceButton: View {
    @ObservedObject var store: NativeCampaignStore

    var body: some View {
        Menu {
            Button("Advance 1 Month") { Task { await store.advance(months: 1) } }
                .accessibilityIdentifier("native-advance-1")
            Button("Advance 3 Months") { Task { await store.advance(months: 3) } }
                .accessibilityIdentifier("native-advance-3")
            Button("Advance 1 Year") { Task { await store.advance(months: 12) } }
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
                        .foregroundStyle(Color.glowingCyan)
                    Text("ADVANCE TURN")
                        .font(.system(.subheadline, design: .monospaced).weight(.bold))
                        .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.deepSlate.opacity(0.85))
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .stroke(Color.glowingCyan.opacity(0.35), lineWidth: 1.5)
            }
            .shadow(color: Color.glowingCyan.opacity(0.25), radius: 10, x: 0, y: 0)
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
        HStack(spacing: 10) {
            NativeAdvanceMenu(store: store)
            NativeCommandButton(title: "Orders", systemImage: "checklist", accessibilityIdentifier: "native-map-command-orders", action: onShowOrders)
            NativeCommandButton(title: "Advisor", systemImage: "brain.head.profile", accessibilityIdentifier: "native-map-command-advisor", action: onShowAdvisor)
            NativeCommandButton(title: "Talk", systemImage: "bubble.left.and.bubble.right", accessibilityIdentifier: "native-map-command-diplomacy", action: onShowDiplomacy)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(highContrast ? Color.black.opacity(0.96) : Color.black.opacity(0.64), in: Capsule())
        .overlay {
            Capsule().stroke(.white.opacity(highContrast ? 0.36 : 0.16), lineWidth: 1)
        }
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
                .frame(minWidth: 72, minHeight: 44)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .accessibilityLabel(title)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

struct NativeAdvanceMenu: View {
    @ObservedObject var store: NativeCampaignStore

    var body: some View {
        Menu {
            Button("1 month") { Task { await store.advance(months: 1) } }
                .accessibilityIdentifier("native-advance-1")
            Button("3 months") { Task { await store.advance(months: 3) } }
                .accessibilityIdentifier("native-advance-3")
            Button("1 year") { Task { await store.advance(months: 12) } }
                .accessibilityIdentifier("native-advance-12")
        } label: {
            if store.isAdvancing {
                VStack(spacing: 2) {
                    ProgressView()
                    Text(store.turnProgress?.phase ?? "Advancing")
                        .font(.system(size: 8, design: .monospaced).weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(minWidth: 52, minHeight: 44)
            } else {
                Label("Advance", systemImage: "calendar.badge.clock")
                    .labelStyle(.titleAndIcon)
                    .font(.system(.caption, design: .monospaced).weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .frame(minWidth: 82, minHeight: 44)
            }
        }
        .buttonStyle(.borderedProminent)
        .disabled(store.isAdvancing)
        .accessibilityLabel("Advance time")
        .accessibilityIdentifier("native-advance-menu")
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
                Label("Suggested actions", systemImage: "sparkles")
                    .font(.system(.headline, design: .monospaced).weight(.bold))
                    .foregroundStyle(Color.glowingCyan)
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

struct NativeOrdersEditorPanel: View {
    @ObservedObject var store: NativeCampaignStore

    var body: some View {
        NativePanel(accessibilityIdentifier: "native-orders-editor") {
            Text("ORDER COMPOSER")
                .font(.system(.headline, design: .monospaced).weight(.bold))
                .foregroundStyle(Color.iceBlue)

            if let state = store.state {
                HStack {
                    Text("CIVIC CAPACITY //")
                        .font(.system(.caption, design: .monospaced).weight(.bold))
                        .foregroundStyle(Color.glowingCyan)

                    ProgressView(value: Double(state.administrativeCapacity), total: 100)
                        .tint(state.administrativeCapacity >= 30 ? Color.neonTeal : Color.softRed)
                        .frame(width: 80)

                    Text("\(state.administrativeCapacity)/100")
                        .font(.system(.caption, design: .monospaced).weight(.bold))
                        .foregroundStyle(state.administrativeCapacity >= 30 ? Color.neonTeal : Color.softRed)

                    Spacer()

                    let currentCost = NativeGameEngine.estimateDirectiveCost(for: store.draftAction)
                    Text("Cost: \(currentCost > 0 ? "\(currentCost)" : "30") Capacity")
                        .font(.system(.caption2, design: .monospaced).weight(.bold))
                        .foregroundStyle(currentCost > state.administrativeCapacity ? Color.softRed : Color.iceBlue.opacity(0.8))
                }
                .padding(.vertical, 4)
            }
            Text("Draft precise geopolitical directives. They will execute upon the next turn leap.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 4) {
                Text("Directives should describe concrete policy, investment, or diplomatic initiatives.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("e.g., \"Fund grid modernization\" or \"Establish logistics buffers with neighboring states.\"")
                    .font(.caption.italic())
                    .foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)

            TextEditor(text: $store.draftAction)
                .font(.body)
                .frame(minHeight: 96)
                .padding(8)
                .scrollContentBackground(.hidden)
                .background(Color.deepSlate.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                }
                .accessibilityLabel("Draft order")
                .accessibilityHint("Describe a concrete policy, investment, or diplomatic action.")
                .accessibilityIdentifier("native-action-editor")

            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                    store.addDraftAction()
                }
            } label: {
                HStack {
                    Image(systemName: "plus")
                    Text("ENQUEUE DIRECTIVE")
                        .font(.system(.subheadline, design: .monospaced).weight(.bold))
                }
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.iceBlue)
            .foregroundStyle(.black)
            .disabled(store.draftAction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .keyboardShortcut("n", modifiers: [.command])
            .accessibilityIdentifier("native-add-order")

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
                Text("No directives enqueued.")
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct NativeAdvisorPanel: View {
    @ObservedObject var store: NativeCampaignStore

    var body: some View {
        NativePanel(accessibilityIdentifier: "native-advisor-panel") {
            HStack {
                Label("STRATEGIC ADVISOR", systemImage: "brain.head.profile")
                    .font(.system(.headline, design: .monospaced).weight(.bold))
                    .foregroundStyle(Color.glowingCyan)
                Spacer()
                if store.isLoadingAdvisor {
                    ProgressView().controlSize(.small)
                }
            }

            Text("Request an assessment of the current geopolitical environment.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 4) {
                Text("Inquiries can focus on stability, tension, threat levels, or advisor recommendations.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("e.g., \"What economic threats should we prioritize?\" or \"Is world tension stable?\"")
                    .font(.caption.italic())
                    .foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)

            TextEditor(text: $store.draftAdvisorQuestion)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 88)
                .padding(8)
                .scrollContentBackground(.hidden)
                .background(Color.deepSlate.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                }
                .accessibilityLabel("Advisor question")
                .accessibilityIdentifier("native-advisor-question")

            Button {
                Task { await store.askAdvisor() }
            } label: {
                HStack {
                    Image(systemName: "brain.head.profile")
                    Text("TRANSMIT INQUIRY")
                        .font(.system(.subheadline, design: .monospaced).weight(.bold))
                }
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.glowingCyan)
            .foregroundStyle(.black)
            .disabled(store.isLoadingAdvisor || store.draftAdvisorQuestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .keyboardShortcut("a", modifiers: [.command, .shift])
            .accessibilityIdentifier("native-ask-advisor")

            if let advisorError = store.lastAdvisorError, !advisorError.isEmpty {
                SuggestionWarning(message: advisorError)
            }

            if let state = store.state, !state.advisorMessages.isEmpty {
                LazyVStack(spacing: 12) {
                    ForEach(Array(state.advisorMessages.prefix(8))) { message in
                        AdvisorMessageRow(message: message)
                    }
                }
            } else {
                Text("No communications logged.")
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct NativeDiplomacyPanel: View {
    @ObservedObject var store: NativeCampaignStore

    var body: some View {
        NativePanel(accessibilityIdentifier: "native-diplomacy-panel") {
            HStack {
                Label("DIPLOMATIC CHANNELS", systemImage: "bubble.left.and.bubble.right")
                    .font(.system(.headline, design: .monospaced).weight(.bold))
                    .foregroundStyle(Color.neonTeal)
                Spacer()
                if store.isLoadingDiplomacy {
                    ProgressView().controlSize(.small)
                }
            }

            if let state = store.state {
                let partners = CountryCatalog.all.filter { $0.code != state.country.code }

                VStack(alignment: .leading, spacing: 6) {
                    Text("SELECT RECIPIENT NATION")
                        .font(.system(.caption2, design: .monospaced).weight(.bold))
                        .foregroundStyle(.secondary)

                    Picker("Counterparty", selection: $store.selectedDiplomaticPartnerCode) {
                        ForEach(partners) { country in
                            Text(country.name).tag(country.code)
                        }
                    }
                    .pickerStyle(.menu)
                    .accessibilityIdentifier("native-diplomacy-partner")
                }

                TextEditor(text: $store.draftDiplomaticMessage)
                    .font(.body)
                    .frame(minHeight: 88)
                    .padding(8)
                    .scrollContentBackground(.hidden)
                    .background(Color.deepSlate.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    }
                    .accessibilityLabel("Diplomatic message")
                    .accessibilityIdentifier("native-diplomacy-message")

                VStack(alignment: .leading, spacing: 4) {
                    Text("Diplomatic directives can coordinate resources, trade corridors, or border stability.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("e.g., \"Propose a technology sharing treaty\" or \"Request naval cooperation.\"")
                        .font(.caption.italic())
                        .foregroundStyle(.secondary)
                }
                .fixedSize(horizontal: false, vertical: true)

                Button {
                    Task { await store.sendDiplomaticMessage() }
                } label: {
                    HStack {
                        Image(systemName: "paperplane.fill")
                        Text("INITIATE TRANSMISSION")
                            .font(.system(.subheadline, design: .monospaced).weight(.bold))
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.neonTeal)
                .foregroundStyle(.black)
                .disabled(store.isLoadingDiplomacy || store.draftDiplomaticMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut("d", modifiers: [.command, .shift])
                .accessibilityIdentifier("native-send-diplomacy")

                if let diplomacyError = store.lastDiplomacyError, !diplomacyError.isEmpty {
                    SuggestionWarning(message: diplomacyError)
                }

                if !state.activeOffers.isEmpty {
                    let pendingOffers = state.activeOffers.filter { $0.status == .pending }
                    if !pendingOffers.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("INCOMING TREATIES & PROPOSALS")
                                .font(.system(.subheadline, design: .monospaced).weight(.bold))
                                .foregroundStyle(Color.neonTeal)
                                .tracking(1.2)
                                .padding(.top, 8)

                            ForEach(pendingOffers) { offer in
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text(offer.proposerCode)
                                            .font(.system(.caption, design: .monospaced).weight(.bold))
                                            .foregroundStyle(Color.neonTeal)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.neonTeal.opacity(0.12), in: Capsule())

                                        Text(offer.type.displayName.uppercased())
                                            .font(.system(.caption2, design: .monospaced).weight(.bold))
                                            .foregroundStyle(.white)

                                        Spacer()
                                    }

                                    Text(offer.description)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)

                                    HStack(spacing: 8) {
                                        Button {
                                            store.acceptDiplomaticOffer(id: offer.id)
                                        } label: {
                                            Text("Accept")
                                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 4)
                                                .background(Color.neonTeal.opacity(0.2), in: Capsule())
                                                .foregroundStyle(Color.neonTeal)
                                        }
                                        .buttonStyle(.plain)

                                        Button {
                                            store.counterDiplomaticOffer(id: offer.id)
                                        } label: {
                                            Text("Counter")
                                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 4)
                                                .background(Color.alertGold.opacity(0.2), in: Capsule())
                                                .foregroundStyle(Color.alertGold)
                                        }
                                        .buttonStyle(.plain)

                                        Button {
                                            store.rejectDiplomaticOffer(id: offer.id)
                                        } label: {
                                            Text("Reject")
                                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 4)
                                                .background(Color.softRed.opacity(0.2), in: Capsule())
                                                .foregroundStyle(Color.softRed)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(10)
                                .glassmorphicCard(borderColor: Color.white.opacity(0.08), cornerRadius: 8)
                            }
                        }
                    }
                }

                if let thread = state.diplomaticThreads.first(where: { $0.participant.code == store.selectedDiplomaticPartnerCode }),
                   !thread.messages.isEmpty {
                    LazyVStack(spacing: 12) {
                        ForEach(Array(thread.messages.reversed().prefix(8))) { message in
                            DiplomacyMessageRow(
                                message: message,
                                isPlayer: message.speaker == state.country.name
                            )
                        }
                    }
                } else {
                    Text("No transmission logs found.")
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct NativeEventsPanel: View {
    let state: NativeCampaignState?

    var body: some View {
        NativePanel(accessibilityIdentifier: "native-events-panel") {
            Label("TRANSMISSION HISTORY", systemImage: "clock")
                .font(.system(.headline, design: .monospaced).weight(.bold))
                .foregroundStyle(Color.iceBlue)
            if let state, !state.timeline.isEmpty {
                LazyVStack(spacing: 12) {
                    ForEach(state.timeline) { event in
                        EventCard(event: event)
                    }
                }
            } else {
                Text("No signals logged yet.")
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct NativeLibraryPanel: View {
    let message: String?
    let onExportCampaign: () -> Void
    let onImportCampaign: () -> Void

    var body: some View {
        NativePanel(accessibilityIdentifier: "native-campaign-library") {
            Label("CAMPAIGN ARCHIVE", systemImage: "folder")
                .font(.system(.headline, design: .monospaced).weight(.bold))
                .foregroundStyle(Color.iceBlue)
            HStack(spacing: 12) {
                Button(action: onExportCampaign) {
                    HStack {
                        Image(systemName: "square.and.arrow.up")
                        Text("EXPORT CAMPAIGN")
                            .font(.system(.subheadline, design: .monospaced).weight(.bold))
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .accessibilityIdentifier("native-export-campaign")

                Button(action: onImportCampaign) {
                    HStack {
                        Image(systemName: "square.and.arrow.down")
                        Text("IMPORT CAMPAIGN")
                            .font(.system(.subheadline, design: .monospaced).weight(.bold))
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .keyboardShortcut("i", modifiers: [.command, .shift])
                .accessibilityIdentifier("native-import-campaign")
            }

            if let message, !message.isEmpty {
                Text(message)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Color.alertGold)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("native-library-message")
            }
        }
    }
}

struct NativeSettingsPanel: View {
    @ObservedObject var store: NativeCampaignStore
    @AppStorage("ZAI_API_KEY") private var zaiApiKey: String = ""
    @AppStorage("ZAI_USE_CODING_ENDPOINT") private var zaiUseCodingEndpoint: Bool = false

    var body: some View {
        NativePanel(accessibilityIdentifier: "native-settings-panel") {
            Label("SYSTEM DIAGNOSTICS", systemImage: "slider.horizontal.3")
                .font(.system(.headline, design: .monospaced).weight(.bold))
                .foregroundStyle(Color.iceBlue)

            if let state = store.state {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(state.country.name) · \(state.country.code) · ROUND \(state.round)")
                        .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                        .foregroundStyle(Color.glowingCyan)
                    Text(state.scenarioDescription)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider()
                    .background(Color.white.opacity(0.12))

                VStack(alignment: .leading, spacing: 8) {
                    Text("CAMPAIGN DIFFICULTY")
                        .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                        .foregroundStyle(.secondary)
                    Picker(
                        "Difficulty",
                        selection: Binding(
                            get: { state.gameMode },
                            set: { store.setGameMode($0) }
                        )
                    ) {
                        ForEach(NativeGameMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("native-difficulty-picker")

                    Text(state.gameMode.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .italic()
                        .fixedSize(horizontal: false, vertical: true)
                }

                NativeLanguagePicker(store: store, state: state)
                NativeScenarioPicker(store: store)
                NativeAIStatusPanel(readiness: state.aiReadiness)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Z.AI (GLM-5.1) CONFIGURATION")
                        .font(.system(.caption, design: .monospaced).weight(.bold))
                        .foregroundStyle(Color.glowingCyan)
                    
                    SecureField("Z.AI API Key", text: $zaiApiKey)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("native-zai-api-key")
                    
                    Toggle("Use GLM Coding Endpoint", isOn: $zaiUseCodingEndpoint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Text("If a Z.AI API key is provided, the turn simulation will use Z.AI's GLM-5.1 model (up to 5 concurrent calls) instead of local Apple Foundation Models.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 8)

                Button {
                    Task { await store.checkAppleStatus() }
                } label: {
                    HStack {
                        Image(systemName: "cpu")
                        Text("POLL MODEL STATUS")
                            .font(.system(.subheadline, design: .monospaced).weight(.bold))
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("native-apple-status-check")

                if state.gameMode == .ironman {
                    HStack {
                        Image(systemName: "lock.shield.fill")
                            .foregroundStyle(Color.softRed)
                        Text("AUTO-SAVE ONLY (IRON MAN)")
                            .font(.system(.caption, design: .monospaced).weight(.bold))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Color.white.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    Button {
                        store.manualSaveCampaign()
                    } label: {
                        HStack {
                            Image(systemName: "square.and.arrow.down")
                            Text("SAVE CAMPAIGN")
                                .font(.system(.subheadline, design: .monospaced).weight(.bold))
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.neonTeal.opacity(0.3))
                    .accessibilityIdentifier("native-save-campaign")
                }

                Button {
                    store.exitToMainMenu()
                } label: {
                    HStack {
                        Image(systemName: "arrow.left.circle")
                        Text("EXIT TO MAIN MENU")
                            .font(.system(.subheadline, design: .monospaced).weight(.bold))
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("native-exit-to-menu")

                Button(role: .destructive) {
                    store.resetSelection()
                } label: {
                    HStack {
                        Image(systemName: "flag.fill")
                        Text("RESET & DELETE SAVE")
                            .font(.system(.subheadline, design: .monospaced).weight(.bold))
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .accessibilityIdentifier("native-change-country")
            }
        }
    }
}

struct NativeLanguagePicker: View {
    @ObservedObject var store: NativeCampaignStore
    let state: NativeCampaignState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("INTERFACE LANGUAGE")
                .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                .foregroundStyle(.secondary)
            Picker(
                "Language",
                selection: Binding(
                    get: { store.selectedLanguage },
                    set: { store.setLanguage($0) }
                )
            ) {
                ForEach(NativeGameLanguage.allCases) { language in
                    Text(language.label).tag(language)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("native-language-picker")

            if state.language != store.selectedLanguage {
                Text("Language will sync on the next campaign save.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct NativeScenarioPicker: View {
    @ObservedObject var store: NativeCampaignStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SCENARIOS")
                .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("native-scenario-library")
            ForEach(NativeScenarioCatalog.all) { scenario in
                Button {
                    store.selectScenario(id: scenario.id)
                } label: {
                    HStack(alignment: .center, spacing: 10) {
                        Image(systemName: scenario.id == store.selectedScenarioID ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(scenario.id == store.selectedScenarioID ? Color.neonTeal : Color.iceBlue.opacity(0.4))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(scenario.name)
                                .font(.body.weight(.bold))
                            Text(scenario.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(scenario.name), \(scenario.subtitle)")
                .accessibilityAddTraits(scenario.id == store.selectedScenarioID ? [.isSelected] : [])
                .accessibilityIdentifier("native-scenario-option-\(scenario.id)")
            }
        }
    }
}

struct NativeAIStatusPanel: View {
    let readiness: NativeAIReadiness
    @State private var pulsing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(readiness.ok ? Color.neonTeal : Color.softRed)
                    .frame(width: 8, height: 8)
                    .opacity(pulsing ? 0.4 : 1.0)
                    .scaleEffect(pulsing ? 1.2 : 1.0)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                            pulsing = true
                        }
                    }

                Text("APPLE FM ENGINE // STATUS")
                    .font(.system(.caption, design: .monospaced).weight(.bold))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("AVAILABILITY:")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text(nativeFormatAvailability(readiness.availability).uppercased())
                        .font(.system(.caption, design: .monospaced).weight(.bold))
                        .foregroundStyle(readiness.ok ? Color.neonTeal : Color.softRed)
                }

                HStack {
                    Text("LAST DIAGNOSTIC:")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text(readiness.checkedAt.isEmpty ? "NEVER" : readiness.checkedAt.uppercased())
                        .font(.system(.caption, design: .monospaced).weight(.bold))
                        .foregroundStyle(Color.iceBlue)
                }
            }
            .padding(10)
            .background(Color.white.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            }

            if !readiness.recoverySuggestion.isEmpty {
                Text(readiness.recoverySuggestion)
                    .font(.caption)
                    .foregroundStyle(Color.alertGold)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(8)
                    .background(Color.alertGold.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.alertGold.opacity(0.24), lineWidth: 1)
                    }
            }
        }
        .accessibilityIdentifier("native-ai-status-panel")
    }
}

struct NativePanel<Content: View>: View {
    let accessibilityIdentifier: String
    let content: Content

    init(accessibilityIdentifier: String, @ViewBuilder content: () -> Content) {
        self.accessibilityIdentifier = accessibilityIdentifier
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassmorphicCard(borderColor: .white.opacity(0.08), cornerRadius: 14)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

struct NativeStatusChip: View {
    let text: String
    let systemImage: String
    var tintColor: Color? = nil

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.system(.caption, design: .monospaced).weight(.bold))
            .foregroundStyle(tintColor ?? Color.iceBlue)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background((tintColor ?? Color.iceBlue).opacity(0.08), in: Capsule())
            .overlay {
                Capsule()
                    .stroke((tintColor ?? Color.iceBlue).opacity(0.24), lineWidth: 1)
            }
            .accessibilityElement(children: .combine)
    }
}

func nativeFormatAvailability(_ value: String) -> String {
    switch value {
    case "apple-intelligence-not-enabled": "Apple Intelligence off"
    case "apple-foundation-error": "Apple FM paused"
    case "available": "Apple FM ready"
    case "model-not-ready": "Model not ready"
    case "not-checked": "Not checked"
    case "unsupported-os": "Unsupported OS"
    default: value.isEmpty ? "Unknown" : value
    }
}

func nativeFormatHUDAvailability(_ value: String) -> String {
    switch value {
    case "available": "Simulation Link Online"
    default: "Simulation Link Offline"
    }
}

func nativeFormatPercent(_ value: Double) -> String {
    String(format: "%.1f%%", value)
}

func nativeFormatSignedPercent(_ value: Double) -> String {
    String(format: "%+.1f%%", value)
}

struct TurnTransitionOverlay: View {
    @ObservedObject var store: NativeCampaignStore
    @State private var consoleLogs: [String] = []
    
    private var engineName: String {
        let key = UserDefaults.standard.string(forKey: "ZAI_API_KEY") ?? ""
        return key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "LOCAL APPLE FOUNDATION" : "Z.AI GLM-5.1"
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
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(log.contains("lane completed") || log.contains("Resolved") ? Color.neonTeal : Color.white.opacity(0.75))
                                        .id(log)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(height: 120)
                        .onChange(of: consoleLogs) { _ in
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
            let initialMsg = engineName.contains("Z.AI")
                ? "SYS // Initializing Z.AI Core Engine (GLM-5.1) parallel lanes..."
                : "SYS // Initializing Local Apple Foundation Models..."
            consoleLogs = [
                initialMsg,
                "SYS // Resolving global econ, defense, and advisor telemetry..."
            ]
        }
        .onChange(of: store.turnProgress?.detail) { newDetail in
            if let detail = newDetail, !detail.isEmpty {
                let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
                withAnimation {
                    consoleLogs.append("[\(timestamp)] \(detail)")
                }
            }
        }
    }
}
