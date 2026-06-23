import SwiftUI

struct ContentView: View {
    @StateObject private var campaignStore = Self.makeCampaignStore()
    @State private var didApplyLaunchConfiguration = false
    @State private var didPrewarmMapData = false

    var body: some View {
        Group {
            if campaignStore.selectedCountry != nil {
                NativeGameView(store: campaignStore)
                    .environmentObject(campaignStore)
            } else {
                CountrySelectionView(
                    countries: CountryCatalog.all,
                    languages: NativeGameLanguage.allCases,
                    onScenarioSelect: campaignStore.selectScenario,
                    onLanguageSelect: campaignStore.setLanguage,
                    scenarios: NativeScenarioCatalog.all,
                    selectedLanguage: campaignStore.selectedLanguage,
                    selectedScenarioID: campaignStore.selectedScenarioID,
                    onSelect: campaignStore.choose,
                    activeCampaignState: campaignStore.state,
                    onResumeCampaign: campaignStore.resumeActiveCampaign
                )
            }
        }
        .onAppear(perform: applyLaunchConfigurationIfNeeded)
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
                return NativeCampaignStore(aiService: NativeUITestAIService())
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

        func generateSuggestedActions(for _: NativeCampaignState) async throws -> [NativeSuggestedAction] {
            [
                NativeSuggestedAction(
                    detail: "Run a deterministic UI test infrastructure action.",
                    id: "ui-test-suggestion",
                    rationale: "Keeps UI test suggestions stable.",
                    title: "UI Test Suggested Action",
                    urgency: "soon"
                )
            ]
        }

        func generateAdvisorBrief(for _: NativeCampaignState, question _: String) async throws -> String {
            "UI Test Advisor Response: continue funding infrastructure and diplomatic coordination."
        }

        func generateDiplomaticReply(for _: NativeCampaignState, thread: NativeDiplomaticThread, message _: String) async throws -> String {
            "UI Test Diplomatic Response: \(thread.participant.name) agrees to continue coordination."
        }
    }
#endif
