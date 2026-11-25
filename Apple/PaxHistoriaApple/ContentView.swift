import SwiftUI

struct ContentView: View {
    @StateObject private var campaignStore = Self.makeCampaignStore()
    @EnvironmentObject var appState: AppState
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(NativeSimulationMode.storageKey) private var simulationModeRaw: String = NativeSimulationMode.livingWorld.rawValue
    @State private var livingWorldCountry: PlayerCountry?
    @State private var didApplyLaunchConfiguration = false
    @State private var didPrewarmMapData = false
    @State private var didInstallTerminationHook = false

    @State private var hasLivingWorldSave = false

    private var simulationMode: NativeSimulationMode {
        NativeSimulationMode(rawValue: simulationModeRaw) ?? .livingWorld
    }

    var body: some View {
        Group {
            if let lwCountry = livingWorldCountry {
                LivingWorldGameView(playerCountryCode: lwCountry.code) {
                    livingWorldCountry = nil
                    refreshLivingWorldSaveStatus()
                }
            } else if campaignStore.selectedCountry != nil {
                NativeGameView(store: campaignStore)
            } else {
                CountrySelectionView(
                    countries: CountryCatalog.all,
                    languages: NativeGameLanguage.allCases,
                    onScenarioSelect: campaignStore.selectScenario,
                    onLanguageSelect: campaignStore.setLanguage,
                    scenarios: NativeScenarioCatalog.all,
                    selectedLanguage: campaignStore.selectedLanguage,
                    selectedScenarioID: campaignStore.selectedScenarioID,
                    onSelect: { country in
                        // Living World starts the day-tick session directly;
                        // Classic keeps the LLM quarterly-turn store.
                        if simulationMode == .livingWorld {
                            livingWorldCountry = country
                        } else {
                            campaignStore.choose(country)
                        }
                    },
                    activeCampaignState: campaignStore.state,
                    onResumeCampaign: campaignStore.resumeActiveCampaign
                )
            }
        }
        .onAppear {
            applyLaunchConfigurationIfNeeded()
            refreshLivingWorldSaveStatus()
            appState.isGameActive = campaignStore.selectedCountry != nil || livingWorldCountry != nil
            // Move any pre-Keychain plaintext keys into the Keychain once.
            NativeSecretStore.migrateIfNeeded(defaults: campaignStore.defaults)
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("LivingWorldDidRequestExit"))) { _ in
            livingWorldCountry = nil
            refreshLivingWorldSaveStatus()
        }
        #if os(macOS)
        .onExitCommand {
            if livingWorldCountry != nil {
                livingWorldCountry = nil
                refreshLivingWorldSaveStatus()
            }
        }
        #endif
        .onChange(of: scenePhase) { _, phase in
            // Close the debounce persistence window on background/inactive:
            // iOS backgrounding and macOS app-hide both land here.
            if phase != .active {
                campaignStore.flushPendingPersistence()
            }
        }
        #if os(macOS)
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.willTerminateNotification
        )) { _ in
            // macOS Cmd+Q lands here. The notification is synchronous and the
            // process may exit before any awaited task resumes, so this flush
            // must be synchronous — hence flushPendingPersistence() rather
            // than await waitForPersistence().
            campaignStore.flushPendingPersistence()
        }
        .onAppear {
            if !didInstallTerminationHook {
                didInstallTerminationHook = true
                NotificationCenter.default.addObserver(
                    forName: NSApplication.willTerminateNotification,
                    object: nil,
                    queue: .main
                ) { _ in
                    campaignStore.flushPendingPersistence()
                }
            }
        }
        #endif
        .onChange(of: campaignStore.selectedCountry) { _, newValue in
            appState.isGameActive = newValue != nil || livingWorldCountry != nil
            if newValue == nil {
                refreshLivingWorldSaveStatus()
            }
        }
        .onChange(of: livingWorldCountry) { _, newValue in
            appState.isGameActive = newValue != nil || campaignStore.selectedCountry != nil
            if newValue == nil {
                refreshLivingWorldSaveStatus()
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if campaignStore.selectedCountry == nil, livingWorldCountry == nil {
                simulationCommandBar
            }
        }
        .background(Color.black)
        .preferredColorScheme(.dark)
    }

    private var simulationCommandBar: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(NativeWarRoomTheme.brass.opacity(0.32))
                .frame(height: 1)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) {
                    simulationEngineIdentity
                    Spacer(minLength: 8)
                    simulationModeSelector
                    if hasLivingWorldSave, simulationMode == .livingWorld {
                        livingWorldSaveBadge
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        simulationEngineIdentity
                        Spacer()
                        if hasLivingWorldSave, simulationMode == .livingWorld {
                            livingWorldSaveBadge
                        }
                    }
                    simulationModeSelector
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(
            LinearGradient(
                colors: [
                    NativeWarRoomTheme.archiveShadow.opacity(0.98),
                    NativeWarRoomTheme.blackboard
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var simulationEngineIdentity: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(NativeWarRoomTheme.brass.opacity(0.14))
                    .frame(width: 28, height: 28)
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(NativeWarRoomTheme.brass.opacity(0.35), lineWidth: 1)
                    }

                Image(systemName: simulationMode == .livingWorld ? "safari.fill" : "cpu.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(NativeWarRoomTheme.brass)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("SIMULATION ENGINE")
                        .font(NativeTypography.cartographicLabel(.caption2, weight: .bold))
                        .foregroundStyle(NativeWarRoomTheme.brass)
                        .tracking(1.3)

                    Text(simulationMode == .livingWorld ? "OFFLINE" : "AI ROUTED")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(simulationMode == .livingWorld ? NativeWarRoomTheme.fieldGreen : NativeWarRoomTheme.signalCyan)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(
                            (simulationMode == .livingWorld ? NativeWarRoomTheme.fieldGreen : NativeWarRoomTheme.signalCyan).opacity(0.14),
                            in: Capsule()
                        )
                }

                Text(simulationModeSubtitle)
                    .font(.caption2)
                    .foregroundStyle(NativeWarRoomTheme.mutedInk)
                    .lineLimit(1)
            }
        }
    }

    private var simulationModeSelector: some View {
        HStack(spacing: 6) {
            ForEach(NativeSimulationMode.allCases) { mode in
                let selected = simulationMode == mode
                Button {
                    simulationModeRaw = mode.rawValue
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: mode == .livingWorld ? "clock.arrow.circlepath" : "sparkles")
                            .font(.caption2.weight(.bold))
                        Text(mode == .livingWorld ? "Living World" : "Classic AI")
                            .font(NativeTypography.cartographicLabel(.caption, weight: .bold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(selected ? NativeWarRoomTheme.blackboard : NativeWarRoomTheme.ink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(selected ? NativeWarRoomTheme.brass : NativeWarRoomTheme.graphite.opacity(0.85))
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(
                                selected ? NativeWarRoomTheme.parchment.opacity(0.5) : NativeWarRoomTheme.brass.opacity(0.24),
                                lineWidth: 1
                            )
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("native-bottom-mode-\(mode.rawValue)")
            }
        }
    }

    private var livingWorldSaveBadge: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(NativeWarRoomTheme.fieldGreen)
                .frame(width: 6, height: 6)
            Text("SAVE SLOT 1 READY")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(NativeWarRoomTheme.fieldGreen)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(NativeWarRoomTheme.fieldGreen.opacity(0.12), in: Capsule())
        .overlay {
            Capsule()
                .stroke(NativeWarRoomTheme.fieldGreen.opacity(0.32), lineWidth: 1)
        }
    }

    private var simulationModeSubtitle: String {
        switch simulationMode {
        case .livingWorld:
            "1936 Daily Victoria-Style Offline Simulation"
        case .classic:
            "2010 Quarterly AI-Routed Geopolitics"
        }
    }

    private func refreshLivingWorldSaveStatus() {
        hasLivingWorldSave = LivingWorldSession.hasSave(slot: 1, directory: LivingWorldMenuCommentary.defaultDirectory)
    }

    private func applyLaunchConfigurationIfNeeded() {
        if !didPrewarmMapData {
            didPrewarmMapData = true
            Task.detached(priority: .utility) {
                GeopoliticalMapData.prewarm()
            }
        }

        #if DEBUG
            guard !didApplyLaunchConfiguration else { return }
            didApplyLaunchConfiguration = true

            let environment = ProcessInfo.processInfo.environment
            let arguments = ProcessInfo.processInfo.arguments
            if environment["PAX_HISTORIA_UI_TEST_RESET"] == "1" || arguments.contains("--pax-historia-ui-test-reset") {
                UserDefaults.standard.set(false, forKey: "hasSeenInGameOnboarding")
                campaignStore.resetSelection()
            }

            if environment["PAX_HISTORIA_SKIP_ONBOARDING"] == "1" || arguments.contains("--pax-historia-skip-onboarding") {
                UserDefaults.standard.set(true, forKey: "hasSeenInGameOnboarding")
            }

            let isFakeAI = environment["PAX_HISTORIA_UI_TEST_FAKE_AI"] == "1" || arguments.contains("--pax-historia-ui-test-fake-ai")
            let isScreenshotSeed = environment["PAX_HISTORIA_SCREENSHOT_SEED"] == "1" || arguments.contains("--pax-historia-screenshot-seed")
            if isFakeAI || isScreenshotSeed {
                simulationModeRaw = NativeSimulationMode.classic.rawValue
                UserDefaults.standard.set(NativeSimulationMode.classic.rawValue, forKey: NativeSimulationMode.storageKey)
            }

            guard isScreenshotSeed else {
                return
            }

            let scenarioID = environment["PAX_HISTORIA_SCENARIO"] ?? NativeScenarioCatalog.defaultScenario.id
            let language = NativeGameLanguage.normalized(environment["PAX_HISTORIA_LANGUAGE"])
            let countryCode = (environment["PAX_HISTORIA_COUNTRY"] ?? "BRA").uppercased()
            let country = CountryCatalog.all.first { $0.code == countryCode } ?? CountryCatalog.all.first

            campaignStore.selectScenario(id: scenarioID)
            campaignStore.setLanguage(language)
            if let country {
                campaignStore.choose(country)
            }
        #endif
    }

    private static func makeCampaignStore() -> NativeCampaignStore {
        #if DEBUG
            let environment = ProcessInfo.processInfo.environment
            let arguments = ProcessInfo.processInfo.arguments
            if environment["PAX_HISTORIA_UI_TEST_FAKE_AI"] == "1" || arguments.contains("--pax-historia-ui-test-fake-ai") {
                let defaults = UserDefaults.standard
                defaults.set(NativeAIProviderPreference.nvidia.rawValue, forKey: NativeAIProviderPreference.storageKey)
                defaults.set("ui-test-nvidia-key", forKey: "NVIDIA_API_KEY")
                return NativeCampaignStore(defaults: defaults, aiService: NativeUITestAIService())
            }
        #endif

        return NativeCampaignStore()
    }
}

#if DEBUG
    @MainActor
    private final class NativeUITestAIService: NativeAIService {
        func checkReadiness() async -> NativeAIReadiness {
            .available(tokenBudget: "ui-test")
        }

        func generateTurn(for state: NativeCampaignState, months _: Int) async throws -> NativeGeneratedTurn {
            NativeGeneratedTurn(
                events: [
                    NativeCampaignEvent(
                        date: state.gameDate,
                        description: "UI test command flow completed with visible domestic infrastructure gains.",
                        id: "ui-test-player-event-\(state.round)",
                        importance: .major,
                        kind: .action,
                        linkedActionIDs: state.plannedActions.map(\.id),
                        notable: true,
                        playerRelated: true,
                        strategicEffects: [
                            NativeStrategicEffect(
                                date: state.gameDate,
                                eventId: "ui-test-player-event-\(state.round)",
                                id: "ui-test-player-effect-\(state.round)",
                                magnitude: 2,
                                summary: "The queued order improved economic resilience.",
                                target: state.country.name,
                                track: .economicResilience
                            )
                        ],
                        title: "UI Test Order Resolved"
                    ),
                    NativeCampaignEvent(
                        date: state.gameDate,
                        description: "Global markets adjusted around the player's latest policy cycle.",
                        id: "ui-test-world-event-\(state.round)",
                        importance: .minor,
                        kind: .world,
                        linkedActionIDs: [],
                        notable: false,
                        playerRelated: false,
                        strategicEffects: [
                            NativeStrategicEffect(
                                date: state.gameDate,
                                eventId: "ui-test-world-event-\(state.round)",
                                id: "ui-test-world-effect-\(state.round)",
                                magnitude: 1,
                                summary: "Market confidence shifted slightly after regional coordination.",
                                target: "International system",
                                track: .marketConfidence
                            )
                        ],
                        title: "UI Test Market Readjustment"
                    )
                ],
                stabilityDelta: 1,
                summary: "UI test generated turn completed with validated consequences.",
                worldTensionDelta: -1
            )
        }

        func generateSuggestedActions(for state: NativeCampaignState) async throws -> [NativeSuggestedAction] {
            NativeDecisionMatrixRow.allCases.flatMap { row in
                NativeDecisionMatrixColumn.allCases.map { column in
                    NativeSuggestedAction(
                        detail: "Implement the \(row.title) \(column.title) campaign policy through existing institutions.",
                        id: "ui-test-matrix-\(row.rawValue)-\(column.rawValue)",
                        rationale: "This legal state action keeps UI automation deterministic and repeatable.",
                        title: "UI Test \(row.title) \(column.title)",
                        urgency: "soon",
                        primaryMechanic: "internal-stability",
                        secondaryMechanic: "market-confidence",
                        actionKind: "policy",
                        administrativeCost: 5,
                        matrixRow: row.rawValue,
                        matrixColumn: column.rawValue,
                        matrixStateFingerprint: NativeDecisionMatrixContract.stateFingerprint(for: state)
                    )
                }
            }
        }

        func generateAdvisorBrief(for _: NativeCampaignState, question _: String) async throws -> String {
            "UI Test Advisor Response: continue funding infrastructure and diplomatic coordination."
        }

        func generateDiplomaticReply(for _: NativeCampaignState, thread: NativeDiplomaticThread, message _: String) async throws -> String {
            "UI Test Diplomatic Response: \(thread.participant.name) agrees to continue coordination."
        }
    }
#endif
