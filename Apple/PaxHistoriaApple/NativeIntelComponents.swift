import SwiftUI

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
    @ViewBuilder let content: Content

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
        .scrollDismissesKeyboard(.interactively)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

struct NativeOrdersEditorPanel: View {
    @ObservedObject var store: NativeCampaignStore

    var body: some View {
        NativePanel(accessibilityIdentifier: "native-orders-editor") {
            Text("New order")
                .font(NativeTypography.sectionTitle())
                .foregroundStyle(Color.iceBlue)
                .help("Write a policy or action here, or use Quick Actions above.")

            if let state = store.state {
                let preview = NativeGameEngine.previewDirective(store.draftAction, in: state)
                HStack {
                    Text("Capacity")
                        .font(.system(.caption, design: .monospaced).weight(.bold))
                        .foregroundStyle(Color.glowingCyan)

                    ProgressView(value: Double(state.administrativeCapacity), total: 100)
                        .tint(state.administrativeCapacity >= 30 ? Color.neonTeal : Color.softRed)
                        .frame(width: 80)

                    Text("\(state.administrativeCapacity)/100")
                        .font(.system(.caption, design: .monospaced).weight(.bold))
                        .foregroundStyle(state.administrativeCapacity >= 30 ? Color.neonTeal : Color.softRed)

                    Spacer()

                    Text("Cost: \(preview.cost > 0 ? "\(preview.cost)" : "30") Capacity")
                        .font(.system(.caption2, design: .monospaced).weight(.bold))
                        .foregroundStyle(preview.cost > state.administrativeCapacity ? Color.softRed : Color.iceBlue.opacity(0.8))
                }
                .padding(.vertical, 4)

                if !store.draftAction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    NativeDirectivePreviewPanel(preview: preview)
                }
            }

            NativeQuickActionPicker { directive in
                store.draftAction = directive
                store.addDraftAction()
            }
            .accessibilityIdentifier("native-quick-actions")

            Text("Describe a policy, investment, or diplomatic move. It runs when you advance the turn.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 4) {
                Text("e.g., \"Fund grid modernization\" or \"Establish logistics buffers with neighboring states.\"")
                    .font(.caption.italic())
                    .foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)

            TextEditor(text: $store.draftAction)
                .font(.body)
                .standardTextEditorStyle(minHeight: 96)
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
                    Text("Add order")
                        .font(.system(.subheadline, design: .monospaced).weight(.bold))
                }
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.iceBlue)
            .foregroundStyle(.black)
            .disabled({
                let trimmed = store.draftAction.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let state = store.state else { return trimmed.isEmpty }
                return trimmed.isEmpty || NativeGameEngine.estimateDirectiveCost(for: trimmed) > state.administrativeCapacity
            }())
            .keyboardShortcut("n", modifiers: [.command])
            .accessibilityIdentifier("native-add-order")

            if let actionError = store.lastError, !actionError.isEmpty {
                SuggestionWarning(message: actionError)
                    .padding(.top, 4)
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
                Text("No orders queued.")
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
                Label("Advisor", systemImage: "brain.head.profile")
                    .font(NativeTypography.sectionTitle())
                    .foregroundStyle(Color.glowingCyan)
                    .help("Ask for an assessment of threats, stability, or opportunities.")
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
                .standardTextEditorStyle(minHeight: 88)
                .accessibilityLabel("Advisor question")
                .accessibilityIdentifier("native-advisor-question")

            Button {
                Task { await store.askAdvisor() }
            } label: {
                HStack {
                    Image(systemName: "brain.head.profile")
                    Text("Ask")
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
                Text("No messages yet.")
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
                Label("Diplomacy", systemImage: "bubble.left.and.bubble.right")
                    .font(NativeTypography.sectionTitle())
                    .foregroundStyle(Color.neonTeal)
                    .help("Negotiate trade, alliances, and border agreements with other nations.")
                Spacer()
                if store.isLoadingDiplomacy {
                    ProgressView().controlSize(.small)
                }
            }

            if let state = store.state {
                let partners = CountryCatalog.all.filter { $0.code != state.country.code }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Choose a nation")
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

                NativeDiplomaticNetworkPanel(state: state)
                NativeTreatyStackPanel(state: state)

                TextEditor(text: $store.draftDiplomaticMessage)
                    .font(.body)
                    .standardTextEditorStyle(minHeight: 88)
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
                        Text("Send")
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
                            Text("Proposals from other nations")
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
                                                .font(.system(size: 11, weight: .bold, design: .monospaced))
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
                                                .font(.system(size: 11, weight: .bold, design: .monospaced))
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
                                                .font(.system(size: 11, weight: .bold, design: .monospaced))
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
                   !thread.messages.isEmpty
                {
                    LazyVStack(spacing: 12) {
                        ForEach(Array(thread.messages.reversed().prefix(8))) { message in
                            DiplomacyMessageRow(
                                message: message,
                                isPlayer: message.speaker == state.country.name
                            )
                        }
                    }
                } else {
                    Text("No messages yet.")
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct NativeDiplomaticNetworkPanel: View {
    let state: NativeCampaignState

    private var topActors: [NativeAICountryState] {
        state.aiCountryStates.values
            .filter { $0.countryCode != state.country.code }
            .sorted {
                let lhs = abs($0.relationshipScores[state.country.code] ?? 0)
                let rhs = abs($1.relationshipScores[state.country.code] ?? 0)
                return lhs == rhs ? $0.countryCode < $1.countryCode : lhs > rhs
            }
            .prefix(6)
            .map(\.self)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Diplomatic Network", systemImage: "point.3.connected.trianglepath.dotted")
                .font(.system(.subheadline, design: .monospaced).weight(.bold))
                .foregroundStyle(Color.neonTeal)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 8)], spacing: 8) {
                ForEach(topActors) { actor in
                    let relation = actor.relationshipScores[state.country.code] ?? 0
                    let tint: Color = relation >= 25 ? Color.neonTeal : (relation <= -25 ? Color.softRed : Color.alertGold)
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Text(actor.countryCode)
                                .font(.system(.caption, design: .monospaced).weight(.black))
                                .foregroundStyle(tint)
                            Spacer()
                            Text("\(relation)")
                                .font(.system(.caption, design: .monospaced).weight(.bold))
                                .foregroundStyle(tint)
                        }
                        ProgressView(value: Double(actor.agendaProgress), total: 100)
                            .tint(tint)
                        Text(actor.doctrine.displayName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(actor.multiTurnAgenda)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                    .padding(9)
                    .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(tint.opacity(0.2), lineWidth: 1)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("native-diplomatic-network")
    }
}

struct NativeTreatyStackPanel: View {
    let state: NativeCampaignState

    private var acceptedOffers: [NativeDiplomaticOffer] {
        state.activeOffers.filter { $0.status == .accepted }
    }

    var body: some View {
        if !acceptedOffers.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Label("Active Treaties", systemImage: "signature")
                    .font(.system(.subheadline, design: .monospaced).weight(.bold))
                    .foregroundStyle(Color.iceBlue)

                ForEach(acceptedOffers) { offer in
                    HStack(alignment: .top, spacing: 8) {
                        Text(offer.proposerCode)
                            .font(.system(.caption, design: .monospaced).weight(.black))
                            .foregroundStyle(Color.neonTeal)
                            .frame(width: 44, alignment: .leading)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(offer.type.displayName)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.primary)
                            Text(offer.description)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        Text("+\(offer.relationshipEffect)")
                            .font(.system(.caption2, design: .monospaced).weight(.bold))
                            .foregroundStyle(Color.neonTeal)
                    }
                    .padding(8)
                    .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .accessibilityIdentifier("native-active-treaties")
        }
    }
}

struct NativeEventsPanel: View {
    let state: NativeCampaignState?

    var body: some View {
        NativePanel(accessibilityIdentifier: "native-events-panel") {
            Label("Events", systemImage: "clock")
                .font(NativeTypography.sectionTitle())
                .foregroundStyle(Color.iceBlue)
                .help("A timeline of everything that has happened in your campaign.")
            if let state, !state.timeline.isEmpty {
                LazyVStack(spacing: 12) {
                    ForEach(state.timeline) { event in
                        EventCard(event: event)
                    }
                }
            } else {
                Text("No events yet.")
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
            Label("Save data", systemImage: "folder")
                .font(NativeTypography.sectionTitle())
                .foregroundStyle(Color.iceBlue)
                .help("Export or import your campaign save file.")
            HStack(spacing: 12) {
                Button(action: onExportCampaign) {
                    HStack {
                        Image(systemName: "square.and.arrow.up")
                        Text("Export save")
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
                        Text("Import save")
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
