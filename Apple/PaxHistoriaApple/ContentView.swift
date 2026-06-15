import SwiftUI

struct ContentView: View {
    @StateObject private var campaignStore = NativeCampaignStore()
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
            campaignStore.resetSelection()
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
}
