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

    private var simulationMode: NativeSimulationMode {
        NativeSimulationMode(rawValue: simulationModeRaw) ?? .livingWorld
    }

    var body: some View {
        Group {
            if let lwCountry = livingWorldCountry {
                LivingWorldGameView(playerCountryCode: lwCountry.code)
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
            appState.isGameActive = campaignStore.selectedCountry != nil
            // Move any pre-Keychain plaintext keys into the Keychain once.
            NativeSecretStore.migrateIfNeeded(defaults: campaignStore.defaults)
        }
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
            appState.isGameActive = newValue != nil
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if campaignStore.selectedCountry == nil, livingWorldCountry == nil {
                HStack {
                    Text("SIMULATION MODE")
                        .font(.system(.caption2, design: .monospaced).weight(.bold))
                        .foregroundStyle(Color.neonTeal)
                    Picker("", selection: $simulationModeRaw) {
                        ForEach(NativeSimulationMode.allCases) { mode in
                            Text(mode.title).tag(mode.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 460)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.spaceBlack)
            }
        }
        .background(Color.black)
        .preferredColorScheme(.dark)
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

            guard environment["PAX_HISTORIA_SCREENSHOT_SEED"] == "1" || arguments.contains("--pax-historia-screenshot-seed") else {
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
