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
    case library
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .advisor: "Advisor"
        case .diplomacy: "Diplomacy"
        case .events: "Events"
        case .library: "Library"
        case .settings: "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .advisor: "brain.head.profile"
        case .diplomacy: "bubble.left.and.bubble.right"
        case .events: "clock"
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
        case .library: "folder"
        case .settings: "slider.horizontal.3"
        }
    }

    var accessibilityIdentifier: String {
        "native-mac-destination-\(rawValue)"
    }
}
#endif

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
            .tabItem { Label("Map", systemImage: "globe.europe.africa") }
            .accessibilityIdentifier("native-map-tab")

            NativeOrdersScreen(store: store)
                .tag(NativeGameTab.orders)
                .tabItem { Label("Orders", systemImage: "checklist") }
                .accessibilityIdentifier("native-orders-tab")

            NativeIntelScreen(
                store: store,
                selectedSection: $selectedIntelSection,
                libraryMessage: libraryMessage,
                onExportCampaign: onExportCampaign,
                onImportCampaign: onImportCampaign
            )
            .tag(NativeGameTab.intel)
            .tabItem { Label("Intel", systemImage: "person.text.rectangle") }
            .accessibilityIdentifier("native-intel-tab")
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
                            .tag(destination as NativeMacDestination?)
                            .accessibilityIdentifier(destination.accessibilityIdentifier)
                    }
                }
            }
            .navigationTitle("SwiftHistoria")
            .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
        } detail: {
            NativeMacDetailScreen(
                destination: selectedDestination ?? .overview,
                store: store,
                libraryMessage: libraryMessage,
                onExportCampaign: onExportCampaign,
                onImportCampaign: onImportCampaign
            )
            .toolbar {
                ToolbarItemGroup {
                    Button {
                        selectedDestination = .orders
                    } label: {
                        Label("Orders", systemImage: "checklist")
                    }
                    .keyboardShortcut("o", modifiers: [.command])

                    Button {
                        Task { await store.advance(months: 1) }
                    } label: {
                        Label("Advance", systemImage: "calendar.badge.clock")
                    }
                    .disabled(store.isAdvancing)
                    .keyboardShortcut("]", modifiers: [.command])
                    .accessibilityIdentifier("native-mac-toolbar-advance")

                    Button {
                        selectedDestination = .advisor
                    } label: {
                        Label("Advisor", systemImage: "brain.head.profile")
                    }
                    .keyboardShortcut("a", modifiers: [.command, .shift])
                }
            }
        }
        .background(.black)
        .accessibilityIdentifier("native-mac-split-shell")
        #endif
    }
}

struct NativeMapScreen: View {
    @ObservedObject var store: NativeCampaignStore
    let onShowOrders: () -> Void
    let onShowAdvisor: () -> Void
    let onShowDiplomacy: () -> Void

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Group {
            if let state = store.state {
                GeometryReader { proxy in
                    ZStack(alignment: .bottom) {
                        NativeWorldMap(state: state, minHeight: max(360, proxy.size.height))
                            .ignoresSafeArea()
                            .id(state.country.code)

                        VStack(spacing: 0) {
                            NativeMapHUD(state: state)
                                .padding(.horizontal, 14)
                                .padding(.top, 12)
                            Spacer(minLength: 12)
                            NativeMapCommandBar(
                                store: store,
                                highContrast: contrast == .increased,
                                onShowOrders: onShowOrders,
                                onShowAdvisor: onShowAdvisor,
                                onShowDiplomacy: onShowDiplomacy
                            )
                            .padding(.horizontal, 12)
                            .padding(.bottom, 10)
                        }
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

struct NativeOverviewScreen: View {
    @ObservedObject var store: NativeCampaignStore

    var body: some View {
        NativeDetailScroll(accessibilityIdentifier: "native-overview-screen") {
            if let state = store.state {
                NativeHeroHeader(state: state)
                NativeWorldMap(state: state, minHeight: 360)
                    .id(state.country.code)
                NativeMetricsGrid(state: state)
                NativeStateNotices(store: store)
            } else {
                ContentUnavailableView("No campaign loaded", systemImage: "globe", description: Text("Choose a country to begin."))
            }
        }
        .task(id: store.state?.round ?? 0) {
            await store.refreshSuggestedActionsIfNeeded()
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

    var body: some View {
        Group {
            switch destination {
            case .overview:
                NativeOverviewScreen(store: store)
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
        if state.stability >= 70 { return .green }
        if state.stability >= 40 { return .orange }
        return .red
    }

    private var tensionTint: Color {
        if state.worldTension >= 70 { return .red }
        if state.worldTension >= 45 { return .orange }
        return .green
    }

    private var aiTint: Color {
        return state.aiReadiness.ok ? .blue : .red
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(state.country.name)
                .font(.title2.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    NativeStatusChip(text: "Round \(state.round)", systemImage: "number")
                    NativeStatusChip(text: state.gameDate, systemImage: "calendar")
                    NativeStatusChip(text: "Stability \(state.stability)", systemImage: "building.columns", tintColor: stabilityTint)
                    NativeStatusChip(text: "Tension \(state.worldTension)", systemImage: "waveform.path.ecg", tintColor: tensionTint)
                    NativeStatusChip(text: nativeFormatAvailability(state.aiReadiness.availability), systemImage: "brain", tintColor: aiTint)
                }
                .padding(.vertical, 2)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("native-map-hud")
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
            NativeCommandButton(title: "Order", systemImage: "plus.circle", accessibilityIdentifier: "native-map-command-orders", action: onShowOrders)
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
                .labelStyle(.iconOnly)
                .frame(minWidth: 52, minHeight: 44)
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
                ProgressView()
                    .frame(minWidth: 52, minHeight: 44)
            } else {
                Label("Advance", systemImage: "calendar.badge.clock")
                    .labelStyle(.iconOnly)
                    .frame(minWidth: 52, minHeight: 44)
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
            Text("Native Strategy Room")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(2)
            Text(state.lastSummary)
                .font(.title2.weight(.semibold))
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
            Label(title, systemImage: systemImage)
                .font(.title2.weight(.bold))
            Text(subtitle)
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
                Label("Apple-suggested actions", systemImage: "sparkles")
                    .font(.headline)
                Spacer()
                if store.isLoadingSuggestions {
                    ProgressView().controlSize(.small)
                } else {
                    Button {
                        Task { await store.refreshSuggestedActions(force: true) }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("native-refresh-suggestions")
                }
            }

            if let suggestionError = store.lastSuggestionError, !suggestionError.isEmpty {
                SuggestionWarning(message: suggestionError)
            }

            if let state = store.state, !state.suggestedActions.isEmpty {
                ForEach(state.suggestedActions) { suggestion in
                    SuggestedActionRow(suggestion: suggestion) {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                            store.addSuggestedAction(suggestion)
                        }
                    }
                }
            } else if store.isLoadingSuggestions {
                Text("Asking Apple Foundation Models for concrete orders...")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Text("No suggestions yet. Manual orders remain available.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct NativeOrdersEditorPanel: View {
    @ObservedObject var store: NativeCampaignStore

    var body: some View {
        NativePanel(accessibilityIdentifier: "native-orders-editor") {
            Text("Order composer")
                .font(.headline)
            Text("Write concrete instruments, not vague wishes. The next time jump turns them into consequences.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            TextEditor(text: $store.draftAction)
                .frame(minHeight: 96)
                .padding(8)
                .scrollContentBackground(.hidden)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityLabel("Draft order")
                .accessibilityHint("Describe a concrete policy, investment, or diplomatic action.")
                .accessibilityIdentifier("native-action-editor")

            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                    store.addDraftAction()
                }
            } label: {
                Label("Add order", systemImage: "plus")
                    .frame(minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .disabled(store.draftAction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .keyboardShortcut("n", modifiers: [.command])
            .accessibilityIdentifier("native-add-order")

            if let state = store.state, !state.plannedActions.isEmpty {
                LazyVStack(spacing: 8) {
                    ForEach(state.plannedActions) { action in
                        ActionRow(action: action) {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                store.deleteAction(id: action.id)
                            }
                        }
                    }
                }
            } else {
                Text("No planned orders yet.")
                    .font(.callout)
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
                Label("Advisor", systemImage: "person.text.rectangle")
                    .font(.headline)
                Spacer()
                if store.isLoadingAdvisor {
                    ProgressView().controlSize(.small)
                }
            }

            Text("Ask for a blunt strategic read on the current campaign state.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            TextEditor(text: $store.draftAdvisorQuestion)
                .frame(minHeight: 88)
                .padding(8)
                .scrollContentBackground(.hidden)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityLabel("Advisor question")
                .accessibilityIdentifier("native-advisor-question")

            Button {
                Task { await store.askAdvisor() }
            } label: {
                Label("Ask advisor", systemImage: "brain.head.profile")
                    .frame(minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .disabled(store.isLoadingAdvisor || store.draftAdvisorQuestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .keyboardShortcut("a", modifiers: [.command, .shift])
            .accessibilityIdentifier("native-ask-advisor")

            if let advisorError = store.lastAdvisorError, !advisorError.isEmpty {
                SuggestionWarning(message: advisorError)
            }

            if let state = store.state, !state.advisorMessages.isEmpty {
                LazyVStack(spacing: 8) {
                    ForEach(Array(state.advisorMessages.prefix(8))) { message in
                        AdvisorMessageRow(message: message)
                    }
                }
            } else {
                Text("No advisor briefings yet.")
                    .font(.callout)
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
                Label("Diplomacy", systemImage: "bubble.left.and.bubble.right")
                    .font(.headline)
                Spacer()
                if store.isLoadingDiplomacy {
                    ProgressView().controlSize(.small)
                }
            }

            if let state = store.state {
                let partners = CountryCatalog.all.filter { $0.code != state.country.code }
                Picker("Counterparty", selection: $store.selectedDiplomaticPartnerCode) {
                    ForEach(partners) { country in
                        Text(country.name).tag(country.code)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("native-diplomacy-partner")

                TextEditor(text: $store.draftDiplomaticMessage)
                    .frame(minHeight: 88)
                    .padding(8)
                    .scrollContentBackground(.hidden)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .accessibilityLabel("Diplomatic message")
                    .accessibilityIdentifier("native-diplomacy-message")

                Button {
                    Task { await store.sendDiplomaticMessage() }
                } label: {
                    Label("Send message", systemImage: "paperplane")
                        .frame(minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.isLoadingDiplomacy || store.draftDiplomaticMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut("d", modifiers: [.command, .shift])
                .accessibilityIdentifier("native-send-diplomacy")

                if let diplomacyError = store.lastDiplomacyError, !diplomacyError.isEmpty {
                    SuggestionWarning(message: diplomacyError)
                }

                if let thread = state.diplomaticThreads.first(where: { $0.participant.code == store.selectedDiplomaticPartnerCode }),
                   !thread.messages.isEmpty {
                    LazyVStack(spacing: 8) {
                        ForEach(Array(thread.messages.reversed().prefix(8))) { message in
                            DiplomacyMessageRow(
                                message: message,
                                isPlayer: message.speaker == state.country.name
                            )
                        }
                    }
                } else {
                    Text("No messages with this counterparty yet.")
                        .font(.callout)
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
            Label("Events", systemImage: "clock")
                .font(.headline)
            if let state, !state.timeline.isEmpty {
                LazyVStack(spacing: 10) {
                    ForEach(state.timeline) { event in
                        EventCard(event: event)
                    }
                }
            } else {
                Text("No events recorded yet.")
                    .font(.callout)
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
            Label("Library", systemImage: "folder")
                .font(.headline)
            HStack {
                Button {
                    onExportCampaign()
                } label: {
                    Label("Export campaign", systemImage: "square.and.arrow.up")
                        .frame(minHeight: 44)
                }
                .buttonStyle(.bordered)
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .accessibilityIdentifier("native-export-campaign")

                Button {
                    onImportCampaign()
                } label: {
                    Label("Import campaign", systemImage: "square.and.arrow.down")
                        .frame(minHeight: 44)
                }
                .buttonStyle(.bordered)
                .keyboardShortcut("i", modifiers: [.command, .shift])
                .accessibilityIdentifier("native-import-campaign")
            }

            if let message, !message.isEmpty {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("native-library-message")
            }
        }
    }
}

struct NativeSettingsPanel: View {
    @ObservedObject var store: NativeCampaignStore

    var body: some View {
        NativePanel(accessibilityIdentifier: "native-settings-panel") {
            Label("Campaign settings", systemImage: "slider.horizontal.3")
                .font(.headline)

            if let state = store.state {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(state.country.name) · \(state.country.code) · Round \(state.round)")
                        .font(.subheadline.weight(.semibold))
                    Text(state.scenarioDescription)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                NativeLanguagePicker(store: store, state: state)
                NativeScenarioPicker(store: store)
                NativeAIStatusPanel(readiness: state.aiReadiness)

                Button {
                    Task { await store.checkAppleStatus() }
                } label: {
                    Label("Check Apple status", systemImage: "cpu")
                        .frame(minHeight: 44)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("native-apple-status-check")

                Button(role: .destructive) {
                    store.resetSelection()
                } label: {
                    Label("Change country", systemImage: "flag")
                        .frame(minHeight: 44)
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
            Text("Language")
                .font(.subheadline.weight(.semibold))
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
        VStack(alignment: .leading, spacing: 8) {
            Text("Scenarios")
                .font(.subheadline.weight(.semibold))
                .accessibilityIdentifier("native-scenario-library")
            ForEach(NativeScenarioCatalog.all) { scenario in
                Button {
                    store.selectScenario(id: scenario.id)
                } label: {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: scenario.id == store.selectedScenarioID ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(scenario.id == store.selectedScenarioID ? .green : .secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(scenario.name).fontWeight(.semibold)
                            Text(scenario.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .frame(minHeight: 44)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(nativeFormatAvailability(readiness.availability), systemImage: readiness.ok ? "checkmark.seal" : "exclamationmark.triangle")
                .font(.subheadline.weight(.semibold))
            Text(readiness.checkedAt.isEmpty ? "Not checked yet" : "Checked \(readiness.checkedAt)")
                .foregroundStyle(.secondary)
            if !readiness.recoverySuggestion.isEmpty {
                Text(readiness.recoverySuggestion)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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
        VStack(alignment: .leading, spacing: 12) {
            content
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

struct NativeStatusChip: View {
    let text: String
    let systemImage: String
    var tintColor: Color? = nil

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tintColor ?? .primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background((tintColor?.opacity(0.12) ?? .clear), in: Capsule())
            .background(.thinMaterial, in: Capsule())
            .overlay {
                if let tintColor {
                    Capsule().stroke(tintColor.opacity(0.24), lineWidth: 1)
                }
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
