import SwiftUI

struct ContentView: View {
    @StateObject private var campaignStore = NativeCampaignStore()
    @State private var didApplyScreenshotSeed = false

    var body: some View {
        Group {
            if campaignStore.selectedCountry != nil {
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
                    onSelect: campaignStore.choose
                )
            }
        }
        .onAppear(perform: applyScreenshotSeedIfNeeded)
        .background(Color.black)
        .preferredColorScheme(.dark)
    }

    private func applyScreenshotSeedIfNeeded() {
        #if DEBUG
        guard !didApplyScreenshotSeed else { return }
        didApplyScreenshotSeed = true

        let environment = ProcessInfo.processInfo.environment
        let arguments = ProcessInfo.processInfo.arguments
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
