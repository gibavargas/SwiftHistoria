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
                            .font(NativeWarRoomTheme.labelFont(.caption, weight: .semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(
                                section == selectedSection
                                    ? NativeWarRoomTheme.brass.opacity(0.2)
                                    : NativeWarRoomTheme.olivePanel.opacity(0.52),
                                in: RoundedRectangle(cornerRadius: 5)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 5)
                                    .stroke(
                                        section == selectedSection
                                            ? NativeWarRoomTheme.brass.opacity(0.55)
                                            : NativeWarRoomTheme.brass.opacity(0.12),
                                        lineWidth: 1
                                    )
                            }
                            .foregroundStyle(section == selectedSection ? NativeWarRoomTheme.ink : NativeWarRoomTheme.mutedInk)
                            .contentShape(RoundedRectangle(cornerRadius: 5))
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
                    NativeOverviewScreen(
                        store: store,
                        onShowEvents: { onSelectDestination(.events) },
                        onShowOrders: { onSelectDestination(.orders) }
                    )
                case .orders:
                    NativeOrdersScreen(store: store)
                case .advisor:
                    NativeDetailScroll(accessibilityIdentifier: "native-advisor-screen") {
                        NativeSectionHeader(
                            title: "Strategic Advisor",
                            subtitle: "Interrogate the live campaign state before committing national capacity.",
                            systemImage: "brain.head.profile"
                        )
                        NativeAdvisorPanel(store: store)
                    }
                case .diplomacy:
                    NativeDetailScroll(accessibilityIdentifier: "native-diplomacy-screen") {
                        NativeSectionHeader(
                            title: "Diplomatic Desk",
                            subtitle: "Open channels, review replies, and shape relationships without leaving the campaign record.",
                            systemImage: "bubble.left.and.bubble.right"
                        )
                        NativeDiplomacyPanel(store: store)
                    }
                case .events:
                    NativeDetailScroll(accessibilityIdentifier: "native-events-screen") {
                        NativeSectionHeader(
                            title: "Campaign Chronicle",
                            subtitle: "Read the turn-by-turn record of decisions, crises, and independent world events.",
                            systemImage: "clock"
                        )
                        NativeEventsPanel(state: store.state)
                    }
                case .worldEconomics:
                    NativeDetailScroll(accessibilityIdentifier: "native-world-economics-screen") {
                        NativeSectionHeader(
                            title: "World Ledger",
                            subtitle: "Compare fiscal position, growth, security, and strategic capacity across the simulation.",
                            systemImage: "chart.bar.xaxis"
                        )
                        if let state = store.state {
                            NativeWorldEconomicsPanel(store: store, state: state)
                        } else {
                            Text("No campaign loaded.")
                        }
                    }
                case .library:
                    NativeDetailScroll(accessibilityIdentifier: "native-library-screen") {
                        NativeSectionHeader(
                            title: "Campaign Archive",
                            subtitle: "Move complete campaign dossiers between devices or preserve a historical checkpoint.",
                            systemImage: "folder"
                        )
                        NativeLibraryPanel(
                            message: libraryMessage,
                            onExportCampaign: onExportCampaign,
                            onImportCampaign: onImportCampaign
                        )
                    }
                case .settings:
                    NativeDetailScroll(accessibilityIdentifier: "native-settings-screen") {
                        NativeSectionHeader(
                            title: "Campaign Configuration",
                            subtitle: "Control simulation rules, save slots, model routing, and campaign lifecycle.",
                            systemImage: "slider.horizontal.3"
                        )
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
        .background(NativeWarRoomTheme.blackboard)
        .scrollDismissesKeyboard(.interactively)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

struct NativeOrdersEditorPanel: View {
    @ObservedObject var store: NativeCampaignStore
    @State private var isShowingFullEditor = false

    var body: some View {
        NativePanel(accessibilityIdentifier: "native-orders-editor") {
            HStack {
                Text("New order")
                    .font(NativeTypography.sectionTitle())
                    .foregroundStyle(Color.iceBlue)
                    .help("Write a policy or action here, or use Quick Actions above.")
                Spacer()
                Button {
                    isShowingFullEditor = true
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.body)
                        .foregroundStyle(Color.iceBlue)
                        .padding(4)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Expand editor to full screen")
            }

            if let state = store.state {
                let preview = NativeGameEngine.previewDirective(store.draftAction, in: state)
                let exceedsCapacity = preview.cost > state.administrativeCapacity
                HStack {
                    Text("Capacity")
                        .font(.system(.caption, design: .monospaced).weight(.bold))
                        .foregroundStyle(Color.glowingCyan)

                    ProgressView(value: Double(state.administrativeCapacity), total: 100)
                        .tint(nativeCapacityColor(for: state.administrativeCapacity))
                        .frame(width: 80)

                    Text("\(state.administrativeCapacity)/100")
                        .font(.system(.caption, design: .monospaced).weight(.bold))
                        .foregroundStyle(nativeCapacityColor(for: state.administrativeCapacity))

                    Spacer()

                    Text("Cost: \(preview.cost > 0 ? "\(preview.cost)" : "30") Capacity")
                        .font(.system(.caption2, design: .monospaced).weight(.bold))
                        .foregroundStyle(exceedsCapacity ? Color.softRed : Color.iceBlue.opacity(0.8))
                }
                .padding(.vertical, 4)

                if exceedsCapacity {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Color.softRed)
                            .font(.caption2)
                        Text("Directive cost exceeds available capacity.")
                            .font(.system(.caption2, design: .monospaced).weight(.bold))
                            .foregroundStyle(Color.softRed)
                    }
                }

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

            let cost = NativeGameEngine.estimateDirectiveCost(for: store.draftAction)
            let capacity = store.state?.administrativeCapacity ?? 100
            let exceeds = cost > capacity
            let isTyping = !store.draftAction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let editorBorderColor: Color = exceeds ? Color.softRed : (isTyping ? Color.glowingCyan : Color.white.opacity(0.08))

            TextEditor(text: $store.draftAction)
                .font(.body)
                .frame(minHeight: 96)
                .padding(8)
                .scrollContentBackground(.hidden)
                .background(Color.deepSlate.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(editorBorderColor, lineWidth: exceeds ? 2 : 1)
                        .shadow(color: exceeds ? Color.softRed.opacity(0.4) : Color.clear, radius: exceeds ? 4 : 0)
                }
                .nativeKeyboardDismissButton()
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
            .sheet(isPresented: $isShowingFullEditor) {
                FullScreenOrderEditor(store: store, isPresented: $isShowingFullEditor)
            }

            if let actionError = store.lastError, !actionError.isEmpty {
                SuggestionWarning(message: actionError)
                    .padding(.top, 4)
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

            if store.draftAdvisorQuestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                NativePromptStarterStrip(
                    title: "Start with the live situation",
                    prompts: [
                        "What is the most urgent risk this turn?",
                        "Which action best improves stability?",
                        "Where should we spend limited capacity?"
                    ],
                    tint: Color.glowingCyan,
                    accessibilityPrefix: "native-advisor-starter"
                ) { prompt in
                    store.draftAdvisorQuestion = prompt
                }
            }

            TextEditor(text: $store.draftAdvisorQuestion)
                .font(.system(.body, design: .monospaced))
                .standardTextEditorStyle(minHeight: 88)
                .nativeKeyboardDismissButton()
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
                Label("Choose a prompt above or write your own briefing question.", systemImage: "text.bubble")
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
                            let offerCount = state.activeOffers.filter { $0.status == .pending && $0.proposerCode == country.code }.count
                            let badge = offerCount > 0 ? " (\(offerCount) proposed)" : ""
                            Text("\(country.name)\(badge)").tag(country.code)
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
                    .nativeKeyboardDismissButton()
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

                if store.draftDiplomaticMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    NativePromptStarterStrip(
                        title: "Open with a clear proposal",
                        prompts: [
                            "Propose a trade resilience compact.",
                            "Request a joint border-stability review.",
                            "Offer technology sharing for critical infrastructure."
                        ],
                        tint: Color.neonTeal,
                        accessibilityPrefix: "native-diplomacy-starter"
                    ) { prompt in
                        store.draftDiplomaticMessage = prompt
                    }
                }

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

                let partnerOffers = state.activeOffers.filter { $0.status == .pending && $0.proposerCode == store.selectedDiplomaticPartnerCode }

                if !partnerOffers.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("ACTIVE PROPOSALS")
                            .font(.system(.subheadline, design: .monospaced).weight(.bold))
                            .foregroundStyle(Color.neonTeal)
                            .tracking(1.2)
                            .padding(.top, 8)

                        ForEach(partnerOffers) { offer in
                            DiplomacyOfferRow(
                                offer: offer,
                                partnerName: CountryNameResolver.name(forCode: offer.proposerCode, in: state),
                                onAccept: { store.acceptDiplomaticOffer(id: offer.id) },
                                onCounter: { store.counterDiplomaticOffer(id: offer.id) },
                                onReject: { store.rejectDiplomaticOffer(id: offer.id) }
                            )
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
                    Label("Draft a proposal above to begin a diplomatic thread.", systemImage: "bubble.left.and.bubble.right")
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct NativePromptStarterStrip: View {
    let title: String
    let prompts: [String]
    let tint: Color
    let accessibilityPrefix: String
    let onSelect: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: "sparkles")
                .font(.system(.caption, design: .monospaced).weight(.bold))
                .foregroundStyle(tint)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(Array(prompts.enumerated()), id: \.offset) { index, prompt in
                    Button {
                        onSelect(prompt)
                    }
                    label: {
                        Text(prompt)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                    .tint(tint.opacity(0.75))
                    .font(.caption)
                    .accessibilityIdentifier("\(accessibilityPrefix)-\(index)")
                }
            }
        }
        .padding(10)
        .background(tint.opacity(0.055), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(tint.opacity(0.22), lineWidth: 1)
        }
        .accessibilityIdentifier("\(accessibilityPrefix)-strip")
    }
}

struct DiplomacyOfferRow: View {
    let offer: NativeDiplomaticOffer
    let partnerName: String
    let onAccept: () -> Void
    let onCounter: () -> Void
    let onReject: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "signature")
                        .font(.caption)
                        .foregroundStyle(Color.neonTeal)
                    Text("PROPOSAL FROM \(partnerName.uppercased())")
                        .font(.system(.caption2, design: .monospaced).weight(.bold))
                        .foregroundStyle(Color.neonTeal)
                    Spacer()
                }

                Text(offer.type.displayName.uppercased())
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)

                Text(offer.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Button(action: onAccept) {
                        Text("Accept")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.neonTeal.opacity(0.2), in: Capsule())
                            .foregroundStyle(Color.neonTeal)
                    }
                    .buttonStyle(.plain)

                    Button(action: onCounter) {
                        Text("Counter")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.alertGold.opacity(0.2), in: Capsule())
                            .foregroundStyle(Color.alertGold)
                    }
                    .buttonStyle(.plain)

                    Button(action: onReject) {
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
            .padding(12)
            .background(Color.neonTeal.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.neonTeal.opacity(0.35), lineWidth: 1.5)
            }
        }
        .accessibilityIdentifier("native-diplomacy-offer-\(offer.id)")
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
                            Text(CountryNameResolver.name(forCode: actor.countryCode, in: state))
                                .font(.system(.caption, design: .default).weight(.black))
                                .foregroundStyle(tint)
                                .lineLimit(1)
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
                        Text(CountryNameResolver.name(forCode: offer.proposerCode, in: state))
                            .font(.system(.caption, design: .default).weight(.black))
                            .foregroundStyle(Color.neonTeal)
                            .frame(width: 100, alignment: .leading)
                            .lineLimit(2)
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
    @State private var showsAdditionalEvents = false
    @State private var selectedFilter: NativeEventFilter = .all

    var body: some View {
        NativePanel(accessibilityIdentifier: "native-events-panel") {
            HStack {
                Label("Events", systemImage: "clock")
                    .font(NativeTypography.sectionTitle())
                    .foregroundStyle(Color.iceBlue)
                    .help("A timeline of everything that has happened in your campaign.")
                Spacer()
                if let state, !state.timeline.isEmpty {
                    Text("\(filteredEvents.count) of \(state.timeline.count)")
                        .font(.system(.caption2, design: .monospaced).weight(.bold))
                        .foregroundStyle(.secondary)
                }
            }

            if let state, !state.timeline.isEmpty {
                // Filter pills
                NativeEventFilterBar(selectedFilter: $selectedFilter, state: state)

                // Keep the archive complete while promoting only a small,
                // balanced set of signals to full-size cards.
                let filtered = state.timeline.filter { selectedFilter.matches($0) }
                let briefing = NativeEventBriefing.make(events: filtered, highlightLimit: 8)

                if filtered.isEmpty {
                    Text("No events match this filter.")
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(.secondary)
                } else {
                    NativeEventDigestStrip(
                        briefing: briefing,
                        accessibilityIdentifier: "native-timeline-event-digest"
                    )

                    VStack(alignment: .leading, spacing: 12) {
                        Label("Priority signals", systemImage: "scope")
                            .font(.system(.subheadline, design: .monospaced).weight(.bold))
                            .foregroundStyle(Color.iceBlue)

                        ForEach(briefing.highlights) { event in
                            EventCard(event: event)
                        }
                    }

                    if !briefing.additionalEvents.isEmpty {
                        DisclosureGroup(isExpanded: $showsAdditionalEvents) {
                            LazyVStack(spacing: 8) {
                                ForEach(briefing.additionalEvents) { event in
                                    NativeCompactEventRow(event: event)
                                }
                            }
                            .padding(.top, 10)
                        } label: {
                            Label(
                                "Additional timeline records (\(briefing.additionalEvents.count))",
                                systemImage: "archivebox"
                            )
                            .font(.system(.callout, design: .monospaced).weight(.semibold))
                            .foregroundStyle(.secondary)
                        }
                        .padding(12)
                        .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
                        .accessibilityIdentifier("native-timeline-additional-events")
                    }
                }
            } else {
                Text("No events yet.")
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .onChange(of: selectedFilter) { _, _ in
            showsAdditionalEvents = false
        }
    }

    private var filteredEvents: [NativeCampaignEvent] {
        guard let state else { return [] }
        return state.timeline.filter { event in
            selectedFilter.matches(event)
        }
    }
}

enum NativeEventFilter: String, CaseIterable, Hashable, Identifiable {
    case all
    case crisis
    case diplomacy
    case economy
    case world
    case player

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .all: "All"
        case .crisis: "Crises"
        case .diplomacy: "Diplomacy"
        case .economy: "Economy"
        case .world: "Global"
        case .player: "Nation"
        }
    }

    var systemImage: String {
        switch self {
        case .all: "list.bullet"
        case .crisis: "exclamationmark.triangle.fill"
        case .diplomacy: "bubble.left.and.bubble.right"
        case .economy: "chart.bar.xaxis"
        case .world: "globe.americas"
        case .player: "building.columns"
        }
    }

    func matches(_ event: NativeCampaignEvent) -> Bool {
        switch self {
        case .all: true
        case .crisis: event.kind == .crisis || event.importance == .severe
        case .diplomacy: event.kind == .diplomacy
        case .economy: event.kind == .economy
        case .world: event.kind == .world
        case .player: event.kind == .action || event.playerRelated
        }
    }

    func count(in events: [NativeCampaignEvent]) -> Int {
        events.filter { matches($0) }.count
    }
}

struct NativeEventFilterBar: View {
    @Binding var selectedFilter: NativeEventFilter
    let state: NativeCampaignState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(NativeEventFilter.allCases) { filter in
                    let count = filter.count(in: state.timeline)
                    Button {
                        select(filter)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: filter.systemImage)
                                .font(.system(size: 10))
                            Text(filter.title)
                                .font(.system(size: 11, weight: .bold))
                            Text("\(count)")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(
                            selectedFilter == filter
                                ? Color.iceBlue.opacity(0.22)
                                : Color.white.opacity(0.06),
                            in: Capsule()
                        )
                        .foregroundStyle(selectedFilter == filter ? Color.iceBlue : .secondary)
                        .overlay {
                            Capsule()
                                .stroke(selectedFilter == filter ? Color.iceBlue.opacity(0.4) : .clear, lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("native-event-filter-\(filter.rawValue)")
                }
            }
            .padding(.bottom, 4)
        }
    }

    private func select(_ filter: NativeEventFilter) {
        if reduceMotion {
            selectedFilter = filter
        } else {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                selectedFilter = filter
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

private struct NativeKeyboardDismissButton: ViewModifier {
    @FocusState private var isFocused: Bool

    func body(content: Content) -> some View {
        #if os(iOS)
            content
                .focused($isFocused)
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Done") {
                            isFocused = false
                        }
                        .accessibilityIdentifier("native-keyboard-done")
                    }
                }
        #else
            content
        #endif
    }
}

private extension View {
    func nativeKeyboardDismissButton() -> some View {
        modifier(NativeKeyboardDismissButton())
    }
}

struct FullScreenOrderEditor: View {
    @ObservedObject var store: NativeCampaignStore
    @Binding var isPresented: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Write a policy, strategic investment, or diplomatic directive. Describe the action clearly in natural language.")
                    .font(NativeWarRoomTheme.bodyFont(.subheadline))
                    .foregroundStyle(NativeWarRoomTheme.mutedInk)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                let cost = NativeGameEngine.estimateDirectiveCost(for: store.draftAction)
                let capacity = store.state?.administrativeCapacity ?? 100
                let exceeds = cost > capacity
                let isTyping = !store.draftAction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                let editorBorderColor: Color = exceeds ? Color.softRed : (isTyping ? Color.glowingCyan : Color.white.opacity(0.12))

                TextEditor(text: $store.draftAction)
                    .font(NativeWarRoomTheme.bodyFont())
                    .padding(12)
                    .scrollContentBackground(.hidden)
                    .background(Color.deepSlate.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(editorBorderColor, lineWidth: exceeds ? 2 : 1)
                            .shadow(color: exceeds ? Color.softRed.opacity(0.4) : Color.clear, radius: exceeds ? 6 : 0)
                    }
                    .padding(.horizontal, 16)
                    .frame(maxHeight: .infinity)

                if let state = store.state {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Estimated Cost:")
                                .font(NativeWarRoomTheme.labelFont(.caption))
                                .foregroundStyle(NativeWarRoomTheme.mutedInk)
                            Text("\(cost) Capacity")
                                .font(NativeWarRoomTheme.labelFont(.caption))
                                .foregroundStyle(exceeds ? Color.softRed : Color.neonTeal)
                            Spacer()
                            Text("Available: \(state.administrativeCapacity)/100")
                                .font(NativeWarRoomTheme.labelFont(.caption))
                                .foregroundStyle(nativeCapacityColor(for: state.administrativeCapacity))
                        }

                        if exceeds {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(Color.softRed)
                                    .font(.caption2)
                                Text("Cost exceeds available administrative capacity.")
                                    .font(NativeWarRoomTheme.labelFont(.caption2))
                                    .foregroundStyle(Color.softRed)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
                }

                Button {
                    store.addDraftAction()
                    isPresented = false
                } label: {
                    Text("Add Order")
                        .font(NativeWarRoomTheme.labelFont(.subheadline))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.iceBlue)
                .foregroundStyle(.black)
                .disabled(store.draftAction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || exceeds)
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
            .navigationTitle("Draft Order")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            isPresented = false
                        }
                        .foregroundStyle(Color.glowingCyan)
                    }
                }
                .background(NativeWarRoomTheme.blackboard)
        }
    }
}
