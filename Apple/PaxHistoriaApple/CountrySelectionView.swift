import SwiftUI

struct CountrySelectionView: View {
    let countries: [PlayerCountry]
    let languages: [NativeGameLanguage]
    let onScenarioSelect: (String) -> Void
    let onLanguageSelect: (NativeGameLanguage) -> Void
    let scenarios: [NativeScenario]
    let selectedLanguage: NativeGameLanguage
    let selectedScenarioID: String
    let onSelect: (PlayerCountry) -> Void
    let activeCampaignState: NativeCampaignState?
    let onResumeCampaign: () -> Void

    @State private var query = ""
    @State private var selectedTheater: StrategicTheaterFilter = .all
    @State private var setupStep = 0 // 0: Scenario/Language; 1: AI Provider; 2: Choose Country
    @AppStorage(NativeSimulationMode.storageKey) private var simulationModeRaw: String = NativeSimulationMode.livingWorld.rawValue
    @AppStorage(NativeAIProviderPreference.storageKey) private var aiProviderRaw: String = NativeAIProviderPreference.nvidia.rawValue
    /// Keys are stored in the Keychain (NativeSecretStore), not UserDefaults.
    /// These draft fields keep the SecureField UX; every keystroke is mirrored
    /// to the Keychain on change.
    @State private var nvidiaKey = ""
    @State private var openRouterKey = ""

    private var simulationMode: NativeSimulationMode {
        NativeSimulationMode(rawValue: simulationModeRaw) ?? .livingWorld
    }

    private var isLivingWorldMode: Bool {
        simulationMode == .livingWorld
    }

    private var selectedProvider: NativeAIProviderPreference {
        NativeAIProviderPreference(rawValue: aiProviderRaw) ?? .nvidia
    }

    private var canProceedFromProviderStep: Bool {
        if isLivingWorldMode {
            return true
        }
        switch selectedProvider {
        case .nvidia:
            return !nvidiaKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .openRouter:
            return !openRouterKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private var filteredCountries: [PlayerCountry] {
        let mapped = countries.map { country -> PlayerCountry in
            if country.code == "RUS", selectedScenarioID == "soviet-triumph" {
                return PlayerCountry(code: "RUS", name: "Soviet Union")
            }
            return country
        }
        let theaterFiltered = mapped.filter { selectedTheater.matches(country: $0) }
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else {
            return theaterFiltered
        }

        return theaterFiltered.filter { country in
            country.name.localizedCaseInsensitiveContains(normalizedQuery) ||
                country.code.localizedCaseInsensitiveContains(normalizedQuery)
        }
    }

    private var flagshipCountries: [PlayerCountry] {
        filteredCountries.filter { NativeCountryEventsCatalog.isFlagshipCountry($0.code) }
    }

    private var nonFlagshipCountries: [PlayerCountry] {
        filteredCountries.filter { !NativeCountryEventsCatalog.isFlagshipCountry($0.code) }
    }

    private var selectedScenarioAccentColor: Color {
        if let scenario = scenarios.first(where: { $0.id == selectedScenarioID }) {
            return Color(hex: scenario.accentColor)
        }
        return .blue
    }

    var body: some View {
        ZStack {
            CountrySelectionBackground()

            #if os(macOS)
                HStack(spacing: 0) {
                    setupPanel
                        .frame(width: 460)
                        .background(NativeWarRoomTheme.blackboard.opacity(0.32))
                    Rectangle()
                        .fill(NativeWarRoomTheme.brass.opacity(0.24))
                        .frame(width: 1)
                    countryList
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(minWidth: 820, minHeight: 620)
            #else
                NavigationStack {
                    VStack(spacing: 0) {
                        if setupStep == 0 {
                            ScrollView {
                                VStack(alignment: .leading, spacing: 20) {
                                    header
                                    if isLivingWorldMode {
                                        LivingWorldMenuCommentary(slot: 1)
                                    }
                                    scenarioDeck
                                    languageDeck
                                    simulationGuide

                                    Button {
                                        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                            setupStep = 1
                                        }
                                    } label: {
                                        HStack {
                                            Text("Continue to AI Setup")
                                                .fontWeight(.bold)
                                            Image(systemName: "arrow.right")
                                        }
                                        .frame(maxWidth: .infinity, minHeight: 46)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(selectedScenarioAccentColor)
                                    .padding(.top, 10)
                                    .accessibilityIdentifier("native-country-continue")
                                }
                                .padding(20)
                                .frame(maxWidth: 520, alignment: .leading)
                            }
                        } else if setupStep == 1 {
                            // Step 1: AI Provider Setup
                            ScrollView {
                                VStack(alignment: .leading, spacing: 20) {
                                    HStack {
                                        Button {
                                            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                                setupStep = 0
                                            }
                                        } label: {
                                            HStack(spacing: 6) {
                                                Image(systemName: "chevron.left").fontWeight(.bold)
                                                Text("Scenario Setup").fontWeight(.semibold)
                                            }
                                            .font(.subheadline)
                                            .foregroundStyle(selectedScenarioAccentColor)
                                        }
                                        .accessibilityIdentifier("native-provider-back")
                                        Spacer()
                                    }

                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(isLivingWorldMode ? "AI Routing (Optional)" : "Configure AI Routing")
                                            .font(NativeTypography.mastheadTitle(.title2))
                                            .foregroundStyle(NativeWarRoomTheme.ink)
                                        Text(
                                            isLivingWorldMode
                                                ? "Living World operates fully offline. Optional keys below are saved for Classic AI turns."
                                                : "Choose NVIDIA API or OpenRouter Free. The game uses only the selected route and shows its failures instead of switching providers."
                                        )
                                        .font(.subheadline)
                                        .foregroundStyle(NativeWarRoomTheme.mutedInk)
                                    }

                                    if isLivingWorldMode {
                                        livingWorldOfflineBanner
                                    }

                                    VStack(spacing: 12) {
                                        ForEach(NativeAIProviderPreference.allCases, id: \.rawValue) { provider in
                                            providerCard(provider)
                                        }
                                    }

                                    apiKeyField(for: selectedProvider)

                                    Button {
                                        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                            setupStep = 2
                                        }
                                    } label: {
                                        HStack {
                                            Text("Continue to Choose Country")
                                                .fontWeight(.bold)
                                            Image(systemName: "arrow.right")
                                        }
                                        .frame(maxWidth: .infinity, minHeight: 46)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(selectedScenarioAccentColor)
                                    .disabled(!canProceedFromProviderStep)
                                    .opacity(canProceedFromProviderStep ? 1.0 : 0.5)
                                    .accessibilityIdentifier("native-provider-continue")
                                }
                                .padding(20)
                                .frame(maxWidth: 520, alignment: .leading)
                            }
                        } else {
                            // Step 2: Choose Country
                            VStack(spacing: 0) {
                                HStack {
                                    Button {
                                        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                            setupStep = 1
                                        }
                                    } label: {
                                        HStack(spacing: 6) {
                                            Image(systemName: "chevron.left")
                                                .fontWeight(.bold)
                                            Text("AI Provider Setup")
                                                .fontWeight(.semibold)
                                        }
                                        .font(.subheadline)
                                        .foregroundStyle(selectedScenarioAccentColor)
                                    }
                                    .accessibilityIdentifier("native-country-back")
                                    Spacer()
                                }
                                .padding(.horizontal, 20)
                                .padding(.top, 16)
                                .padding(.bottom, 12)

                                searchField
                                    .padding(.horizontal, 20)
                                    .padding(.bottom, 10)

                                theaterFilterBar
                                    .padding(.horizontal, 20)
                                    .padding(.bottom, 10)

                                countryList
                            }
                        }
                    }
                    .navigationTitle(setupStep == 0 ? "New Campaign" : setupStep == 1 ? "AI Provider" : "Choose Country")
                    .navigationBarTitleDisplayMode(.inline)
                }
            #endif
        }
        .onAppear {
            nvidiaKey = NativeSecretStore.string(forKey: "NVIDIA_API_KEY") ?? ""
            openRouterKey = NativeSecretStore.string(forKey: "OPENROUTER_API_KEY") ?? ""
        }
        .onChange(of: nvidiaKey) { _, newValue in
            NativeSecretStore.set(newValue, forKey: "NVIDIA_API_KEY")
        }
        .onChange(of: openRouterKey) { _, newValue in
            NativeSecretStore.set(newValue, forKey: "OPENROUTER_API_KEY")
        }
        .tint(selectedScenarioAccentColor)
        .preferredColorScheme(.dark)
    }

    // MARK: - AI Provider Setup Components

    @ViewBuilder
    private func providerCard(_ provider: NativeAIProviderPreference) -> some View {
        let isSelected = selectedProvider == provider
        Button {
            aiProviderRaw = provider.rawValue
        } label: {
            HStack(spacing: 12) {
                Image(systemName: provider == .nvidia ? "sparkles" : "network")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.white : selectedScenarioAccentColor)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 4) {
                    Text(provider.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(provider.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.white)
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? selectedScenarioAccentColor.opacity(0.85) : Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isSelected ? selectedScenarioAccentColor : Color.white.opacity(0.12), lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("native-provider-\(provider.rawValue)")
    }

    @ViewBuilder
    private func apiKeyField(for provider: NativeAIProviderPreference) -> some View {
        let key: Binding<String> = switch provider {
        case .nvidia: $nvidiaKey
        case .openRouter: $openRouterKey
        }
        let placeholder = switch provider {
        case .nvidia: "nvapi-..."
        case .openRouter: "sk-or-v1-..."
        }
        let helpText = switch provider {
        case .nvidia:
            "Strict NVIDIA API route (MiniMax-M3, Kimi-K2.6, and DeepSeek-V4-Flash)."
        case .openRouter:
            "Strict OpenRouter Free route. Get a key at openrouter.ai/keys."
        }

        VStack(alignment: .leading, spacing: 8) {
            Text("\(provider.title) API Key")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            SecureField(placeholder, text: key)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .accessibilityIdentifier("native-\(provider.rawValue)-key-field")

            Text(helpText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var setupPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                if isLivingWorldMode {
                    LivingWorldMenuCommentary(slot: 1)
                }
                scenarioDeck
                languageDeck
                providerSetupDeck
                searchField
            }
            .padding(20)
            .frame(maxWidth: 520, alignment: .leading)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if filteredCountries.isEmpty {
                EmptyView()
            } else {
                VStack(spacing: 0) {
                    Rectangle()
                        .fill(NativeWarRoomTheme.brass.opacity(0.24))
                        .frame(height: 1)
                    Text("\(filteredCountries.count) countries available")
                        .font(NativeTypography.cartographicLabel(.caption, weight: .semibold))
                        .foregroundStyle(NativeWarRoomTheme.mutedInk)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(NativeWarRoomTheme.archiveShadow.opacity(0.95))
                        .accessibilityIdentifier("native-country-count")
                }
            }
        }
        .accessibilityIdentifier("native-country-selection")
    }

    private var livingWorldOfflineBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.shield.fill")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(NativeWarRoomTheme.fieldGreen)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                Text("OFFLINE ENGINE ACTIVE")
                    .font(NativeTypography.cartographicLabel(.caption2, weight: .bold))
                    .foregroundStyle(NativeWarRoomTheme.fieldGreen)
                    .tracking(1.2)

                Text("Living World runs 100% offline with deterministic country brains — API keys are optional (used only if you switch to Classic mode).")
                    .font(.caption)
                    .foregroundStyle(NativeWarRoomTheme.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NativeWarRoomTheme.fieldGreen.opacity(0.11), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(NativeWarRoomTheme.fieldGreen.opacity(0.35), lineWidth: 1)
        }
        .accessibilityIdentifier("native-living-world-offline-banner")
    }

    private var theaterFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(StrategicTheaterFilter.allCases) { theater in
                    let isSelected = selectedTheater == theater
                    Button {
                        selectedTheater = theater
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: theater.icon)
                                .font(.caption2.weight(.bold))
                            Text(theater.title)
                                .font(NativeTypography.cartographicLabel(.caption2, weight: .bold))
                        }
                        .foregroundStyle(isSelected ? NativeWarRoomTheme.blackboard : NativeWarRoomTheme.ink)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(isSelected ? NativeWarRoomTheme.brass : NativeWarRoomTheme.graphite.opacity(0.82))
                        )
                        .overlay {
                            Capsule()
                                .stroke(
                                    isSelected ? NativeWarRoomTheme.parchment.opacity(0.45) : NativeWarRoomTheme.brass.opacity(0.22),
                                    lineWidth: 1
                                )
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("native-theater-filter-\(theater.rawValue)")
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var countryList: some View {
        VStack(spacing: 0) {
            #if os(macOS)
                theaterFilterBar
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(NativeWarRoomTheme.archiveShadow.opacity(0.65))
                Rectangle()
                    .fill(NativeWarRoomTheme.brass.opacity(0.16))
                    .frame(height: 1)
            #endif

            List {
                if filteredCountries.isEmpty {
                    Section {
                        ContentUnavailableView(
                            "No country matched that search.",
                            systemImage: "magnifyingglass",
                            description: Text("Try a country name, ISO code, or switch theater filter.")
                        )
                        .listRowBackground(Color.clear)
                        .accessibilityIdentifier("native-country-empty")
                    }
                } else if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedTheater != .all {
                    Section {
                        if !canProceedFromProviderStep {
                            providerWarning
                        }
                        ForEach(filteredCountries) { country in
                            countryButton(country)
                        }
                    } header: {
                        HStack {
                            Text(selectedTheater == .all ? "Matching Nations (\(filteredCountries.count))" : "\(selectedTheater.title) (\(filteredCountries.count))")
                                .font(NativeTypography.cartographicLabel(.caption2, weight: .bold))
                                .foregroundStyle(NativeWarRoomTheme.brass)
                            Spacer()
                        }
                    }
                } else {
                    Section {
                        if !canProceedFromProviderStep {
                            providerWarning
                        }
                        ForEach(flagshipCountries) { country in
                            countryButton(country)
                        }
                    } header: {
                        HStack {
                            Text("Flagship Complete Powers (12 Nations)")
                                .font(NativeTypography.cartographicLabel(.caption2, weight: .bold))
                                .foregroundStyle(NativeWarRoomTheme.ink)
                            Spacer()
                            Text("100 Bespoke Events Each")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Color.alertGold)
                        }
                    }

                    Section {
                        ForEach(nonFlagshipCountries) { country in
                            countryButton(country)
                        }
                    } header: {
                        HStack {
                            Text("All Sovereign Nations (\(nonFlagshipCountries.count) Nations)")
                                .font(NativeTypography.cartographicLabel(.caption2, weight: .bold))
                                .foregroundStyle(NativeWarRoomTheme.mutedInk)
                            Spacer()
                            Text("100 Events Each")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Color.glowingCyan)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.black.opacity(0.25))
            .accessibilityIdentifier("native-country-list")
        }
    }

    private var providerWarning: some View {
        Label(
            "Enter the selected provider API key before starting.",
            systemImage: "exclamationmark.triangle"
        )
        .font(.caption)
        .foregroundStyle(Color.alertGold)
        .fixedSize(horizontal: false, vertical: true)
        .listRowBackground(Color.clear)
        .accessibilityIdentifier("native-provider-start-warning")
    }

    private func countryButton(_ country: PlayerCountry) -> some View {
        Button {
            onSelect(country)
        } label: {
            CountryRow(country: country)
                .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
        }
        .buttonStyle(.plain)
        .disabled(!canProceedFromProviderStep)
        .listRowBackground(Color.clear)
        .listRowSeparatorTint(NativeWarRoomTheme.brass.opacity(0.12))
        .accessibilityLabel("\(country.name), ISO code \(country.code)")
        .accessibilityHint("Starts a campaign as \(country.name).")
        .accessibilityIdentifier("native-country-option-\(country.code)")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("PAX HISTORIA")
                .font(NativeWarRoomTheme.displayFont(.headline, weight: .bold))
                .foregroundStyle(NativeWarRoomTheme.brass)
                .textCase(.uppercase)
                .tracking(3.2)

            if let activeState = activeCampaignState {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: "play.circle.fill")
                            .font(.title3)
                            .foregroundStyle(Color.glowingCyan)
                        Text("RESUME SAVED CAMPAIGN")
                            .font(.system(.caption, design: .monospaced).weight(.bold))
                            .foregroundStyle(Color.glowingCyan)
                            .tracking(1.2)
                        Spacer()
                    }

                    let activeCountryName = activeState.country.code == "RUS" && activeState.scenarioID == "soviet-triumph" ? "Soviet Union" : activeState.country.name
                    Text("\(activeCountryName) (\(activeState.country.code))")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text("\(activeState.scenarioName) · Round \(activeState.round) · \(activeState.gameDate)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Button {
                        onResumeCampaign()
                    } label: {
                        HStack {
                            Image(systemName: "arrow.right.circle.fill")
                            Text("Resume Campaign")
                                .fontWeight(.bold)
                        }
                        .frame(maxWidth: .infinity, minHeight: 38)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.glowingCyan.opacity(0.3))
                    .foregroundStyle(Color.glowingCyan)
                    .accessibilityIdentifier("native-resume-campaign")
                }
                .padding(14)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.glowingCyan.opacity(0.3), lineWidth: 1)
                }
                .padding(.bottom, 6)
            }

            Text("Open the campaign dossier")
                .font(NativeWarRoomTheme.displayFont(.largeTitle, weight: .bold))
                .foregroundStyle(NativeWarRoomTheme.ink)
                .minimumScaleFactor(0.8)

            Text("Choose your scenario, language, and country to begin.")
                .font(NativeWarRoomTheme.bodyFont())
                .foregroundStyle(NativeWarRoomTheme.mutedInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var scenarioDeck: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Scenario archive", systemImage: "square.stack.3d.up")
                    .font(NativeWarRoomTheme.labelFont(.subheadline))
                    .foregroundStyle(NativeWarRoomTheme.brass)
                    .accessibilityIdentifier("native-scenario-library")
                Spacer()
                Text(NativeScenarioCatalog.scenario(for: selectedScenarioID).name)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(selectedScenarioAccentColor)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(scenarios) { scenario in
                        Button {
                            onScenarioSelect(scenario.id)
                        } label: {
                            ScenarioSelectionCard(
                                scenario: scenario,
                                selected: scenario.id == selectedScenarioID
                            )
                            .frame(width: 230)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(scenario.name), \(scenario.subtitle)")
                        .accessibilityHint(scenario.id == selectedScenarioID ? "Selected scenario" : "Selects this scenario.")
                        .accessibilityAddTraits(scenario.id == selectedScenarioID ? [.isSelected] : [])
                        .accessibilityIdentifier("native-scenario-option-\(scenario.id)")
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(14)
        .warRoomDossier(borderColor: NativeWarRoomTheme.brass.opacity(0.22), cornerRadius: 10)
    }

    private var languageDeck: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Language", systemImage: "character.bubble")
                    .font(NativeWarRoomTheme.labelFont(.subheadline))
                    .foregroundStyle(NativeWarRoomTheme.brass)
                Spacer()
                Text(selectedLanguage.label)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(selectedScenarioAccentColor)
            }

            Picker(
                "Language",
                selection: Binding(
                    get: { selectedLanguage },
                    set: { onLanguageSelect($0) }
                )
            ) {
                ForEach(languages) { language in
                    Text(language.label).tag(language)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("native-language-picker")
        }
        .padding(14)
        .warRoomDossier(borderColor: NativeWarRoomTheme.brass.opacity(0.18), cornerRadius: 10)
    }

    private var providerSetupDeck: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("AI Routing", systemImage: "cpu")
                    .font(NativeWarRoomTheme.labelFont(.subheadline))
                    .foregroundStyle(NativeWarRoomTheme.brass)
                Spacer()
                Text(selectedProvider.title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(selectedScenarioAccentColor)
            }

            Text("Choose one route. NVIDIA and OpenRouter Free never replace each other automatically.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if isLivingWorldMode {
                livingWorldOfflineBanner
            }

            VStack(spacing: 10) {
                ForEach(NativeAIProviderPreference.allCases, id: \.rawValue) { provider in
                    providerCard(provider)
                }
            }

            apiKeyField(for: selectedProvider)

            if !canProceedFromProviderStep {
                Label("Add a key for the selected route before starting the campaign.", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(Color.alertGold)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .warRoomDossier(borderColor: NativeWarRoomTheme.brass.opacity(0.18), cornerRadius: 10)
    }

    private var searchField: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Find your country", systemImage: "magnifyingglass")
                .font(NativeWarRoomTheme.labelFont(.subheadline))
                .foregroundStyle(NativeWarRoomTheme.brass)
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search country or ISO code", text: $query)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("native-country-search")
                #if os(iOS)
                    .textInputAutocapitalization(.never)
                #endif
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("Clear search")
                    .accessibilityIdentifier("native-country-clear-search")
                }
            }
            .padding(10)
            .background(NativeWarRoomTheme.graphite.opacity(0.72))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            }
            .accessibilityElement(children: .contain)
        }
        .padding(14)
        .warRoomDossier(borderColor: NativeWarRoomTheme.brass.opacity(0.18), cornerRadius: 10)
    }

    private var simulationGuide: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("How to play", systemImage: "info.circle")
                .font(NativeWarRoomTheme.labelFont(.subheadline))
                .foregroundStyle(NativeWarRoomTheme.brass)

            VStack(alignment: .leading, spacing: 8) {
                GuideStepRow(number: "01", text: "Pick a scenario from the options above.")
                GuideStepRow(number: "02", text: "Choose the nation you want to play.")
                GuideStepRow(number: "03", text: "Add policy orders — typed or quick-pick.")
                GuideStepRow(number: "04", text: "Press Advance to see what happens next.")
            }
        }
        .padding(14)
        .warRoomDossier(borderColor: NativeWarRoomTheme.brass.opacity(0.18), cornerRadius: 10)
    }
}

private struct GuideStepRow: View {
    let number: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number)
                .font(.system(.caption, design: .monospaced).weight(.bold))
                .foregroundStyle(Color.neonTeal)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.neonTeal.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))

            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct CountrySelectionBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    NativeWarRoomTheme.blackboard,
                    NativeWarRoomTheme.graphite,
                    NativeWarRoomTheme.archiveShadow
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Canvas { context, size in
                let gridSpacing: CGFloat = 40
                var path = Path()

                for x in stride(from: CGFloat(0), to: size.width, by: gridSpacing) {
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                }

                for y in stride(from: CGFloat(0), to: size.height, by: gridSpacing) {
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                }

                context.stroke(path, with: .color(NativeWarRoomTheme.mapPaper.opacity(0.035)), lineWidth: 0.75)
            }

            RadialGradient(
                colors: [NativeWarRoomTheme.brass.opacity(0.12), Color.clear],
                center: .topLeading,
                startRadius: 0,
                endRadius: 300
            )

            RadialGradient(
                colors: [NativeWarRoomTheme.signalCyan.opacity(0.05), Color.clear],
                center: .bottomTrailing,
                startRadius: 0,
                endRadius: 400
            )

            VStack {
                HStack {
                    Spacer()
                    OrbitRingsView()
                        .offset(x: 50, y: -50)
                        .opacity(0.7)
                }
                Spacer()
            }
        }
        .ignoresSafeArea()
    }
}

private enum StrategicTheaterFilter: String, CaseIterable, Identifiable {
    case all
    case greatPowers
    case americas
    case europe
    case asiaPacific
    case middleEastAfrica

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .all: "All Nations"
        case .greatPowers: "Great Powers"
        case .americas: "Americas"
        case .europe: "Europe"
        case .asiaPacific: "Asia-Pacific"
        case .middleEastAfrica: "Middle East & Africa"
        }
    }

    var icon: String {
        switch self {
        case .all: "globe"
        case .greatPowers: "crown.fill"
        case .americas: "globe.americas.fill"
        case .europe: "globe.europe.africa.fill"
        case .asiaPacific: "globe.asia.australia.fill"
        case .middleEastAfrica: "sun.max.fill"
        }
    }

    func matches(country: PlayerCountry) -> Bool {
        switch self {
        case .all:
            return true
        case .greatPowers:
            return NativeCountryEventsCatalog.isFlagshipCountry(country.code)
        case .americas:
            let coord = CountryCoordinate.center(for: country.code)
            return coord.longitude < -25
        case .europe:
            let coord = CountryCoordinate.center(for: country.code)
            return coord.latitude >= 34 && coord.longitude >= -25 && coord.longitude <= 46
        case .asiaPacific:
            let coord = CountryCoordinate.center(for: country.code)
            return coord.longitude > 62
        case .middleEastAfrica:
            let coord = CountryCoordinate.center(for: country.code)
            return coord.longitude >= -25 && coord.longitude <= 62 && coord.latitude < 36
        }
    }
}

private struct CountryRow: View {
    let country: PlayerCountry
    @State private var isHovered = false

    var body: some View {
        let profile = Native2010WorldModel.profile(for: country)
        let govType = NativeStrategyContextDatabase.startingGovernmentType(for: country.code).capitalized
        let isFlagship = NativeCountryEventsCatalog.isFlagshipCountry(country.code)
        let techTier = max(1, min(5, Int(profile.techLevel.rounded())))
        let stabilityColor = NativeWarRoomTheme.statusColor(for: profile.stability)

        HStack(spacing: 12) {
            NativeCountryStandard(countryCode: country.code, size: 32)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(country.name)
                        .font(NativeWarRoomTheme.bodyFont(.body, weight: .semibold))
                        .foregroundStyle(isHovered ? NativeWarRoomTheme.brass : NativeWarRoomTheme.ink)
                        .lineLimit(1)

                    if isFlagship {
                        Text("FLAGSHIP")
                            .font(.system(size: 8, weight: .black, design: .monospaced))
                            .foregroundStyle(NativeWarRoomTheme.blackboard)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(NativeWarRoomTheme.brass, in: Capsule())
                    }

                    Text(govType.uppercased())
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(NativeWarRoomTheme.mutedInk)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(NativeWarRoomTheme.olivePanel.opacity(0.9), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .stroke(NativeWarRoomTheme.brass.opacity(0.22), lineWidth: 0.75)
                        }
                }

                HStack(spacing: 10) {
                    Text(String(format: "$%.2fT GDP", profile.nominalGDPTrillions))
                        .font(NativeTypography.telemetryValue(.caption2, weight: .bold))
                        .foregroundStyle(NativeWarRoomTheme.parchment)

                    HStack(spacing: 4) {
                        Capsule()
                            .fill(NativeWarRoomTheme.graphite)
                            .frame(width: 28, height: 5)
                            .overlay(alignment: .leading) {
                                Capsule()
                                    .fill(stabilityColor)
                                    .frame(width: max(4, 28 * CGFloat(profile.stability) / 100.0), height: 5)
                            }
                        Text("\(profile.stability)% STB")
                            .font(NativeTypography.telemetryValue(.caption2, weight: .bold))
                            .foregroundStyle(stabilityColor)
                    }

                    HStack(spacing: 2) {
                        Text("T\(techTier)")
                            .font(NativeTypography.telemetryValue(.caption2, weight: .bold))
                            .foregroundStyle(NativeWarRoomTheme.signalCyan)
                        ForEach(1 ... 5, id: \.self) { pip in
                            RoundedRectangle(cornerRadius: 1)
                                .fill(pip <= techTier ? NativeWarRoomTheme.signalCyan : NativeWarRoomTheme.mutedInk.opacity(0.25))
                                .frame(width: 3, height: 7)
                        }
                    }

                    if isFlagship {
                        Text("100 Events")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(NativeWarRoomTheme.brass)
                    }
                }
            }

            Spacer(minLength: 8)

            Text(country.code)
                .font(NativeTypography.telemetryValue(.caption2, weight: .bold))
                .foregroundStyle(isHovered ? NativeWarRoomTheme.brass : NativeWarRoomTheme.mutedInk)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(NativeWarRoomTheme.archiveShadow.opacity(0.8), in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(isHovered ? NativeWarRoomTheme.brass.opacity(0.5) : NativeWarRoomTheme.brass.opacity(0.18), lineWidth: 1)
                }

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(isHovered ? NativeWarRoomTheme.brass : NativeWarRoomTheme.mutedInk.opacity(0.6))
        }
        .contentShape(Rectangle())
        .padding(.vertical, 7)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(isHovered ? NativeWarRoomTheme.olivePanel.opacity(0.7) : NativeWarRoomTheme.archiveShadow.opacity(0.45))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(isHovered ? NativeWarRoomTheme.brass.opacity(0.45) : NativeWarRoomTheme.brass.opacity(0.14), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

private struct ScenarioSelectionCard: View {
    let scenario: NativeScenario
    let selected: Bool

    private var openingYear: String {
        String(scenario.gameDate.prefix(4))
    }

    var body: some View {
        let accent = Color(hex: scenario.accentColor)
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                Image(scenario.assetImageName)
                    .resizable()
                    .aspectRatio(16 / 9, contentMode: .fill)
                    .frame(height: 108)
                    .clipped()

                RadialGradient(
                    colors: [Color.clear, NativeWarRoomTheme.blackboard.opacity(0.55)],
                    center: .center,
                    startRadius: 20,
                    endRadius: 140
                )

                LinearGradient(
                    colors: [Color.clear, NativeWarRoomTheme.blackboard.opacity(0.92)],
                    startPoint: .center,
                    endPoint: .bottom
                )

                VStack {
                    HStack {
                        Text(openingYear)
                            .font(NativeTypography.telemetryValue(.caption2, weight: .bold))
                            .foregroundStyle(NativeWarRoomTheme.parchment)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(NativeWarRoomTheme.blackboard.opacity(0.78), in: Capsule())
                            .overlay {
                                Capsule()
                                    .stroke(NativeWarRoomTheme.brass.opacity(0.35), lineWidth: 0.8)
                            }
                        Spacer()
                        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                            .font(.subheadline)
                            .foregroundStyle(selected ? accent : NativeWarRoomTheme.parchment.opacity(0.75))
                    }
                    Spacer()
                }
                .padding(8)

                HStack(alignment: .firstTextBaseline) {
                    Text(scenario.name)
                        .font(NativeWarRoomTheme.displayFont(.subheadline, weight: .bold))
                        .foregroundStyle(NativeWarRoomTheme.ink)
                        .lineLimit(1)
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
            }
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 10, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 10))

            VStack(alignment: .leading, spacing: 6) {
                Text(scenario.subtitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(selected ? accent : NativeWarRoomTheme.parchment)
                    .lineLimit(2)
                Text(scenario.heroSubtitle)
                    .font(.caption2)
                    .foregroundStyle(NativeWarRoomTheme.mutedInk)
                    .lineLimit(3)

                Spacer(minLength: 2)

                HStack(spacing: 8) {
                    Label("3 OBJECTIVES", systemImage: "flag.checkered")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(NativeWarRoomTheme.brass)
                    Spacer()
                    Text("TENSION \(scenario.baseWorldTension)%")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(NativeWarRoomTheme.mutedInk)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, minHeight: 214, alignment: .topLeading)
        .warRoomDossier(
            borderColor: selected ? accent.opacity(0.75) : NativeWarRoomTheme.brass.opacity(0.22),
            cornerRadius: 10
        )
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .hoverScale(1.02)
    }
}

// MARK: - Helper Extensions

extension Color {
    // Legacy semantic names are retained so existing gameplay views inherit the
    // Living Atlas palette without a risky, whole-product identifier migration.
    static let spaceBlack = Color(hex: "#090a08")
    static let deepSlate = Color(hex: "#181a15")
    static let iceBlue = Color(hex: "#d4c7a5")
    static let glowingCyan = Color(hex: "#c5a45f")
    static let neonTeal = Color(hex: "#81966a")
    static let alertGold = Color(hex: "#d3a55c")
    static let softRed = Color(hex: "#b95645")

    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

enum NativeWarRoomTheme {
    static let blackboard = Color(hex: "#090a08")
    static let archiveShadow = Color(hex: "#0f100d")
    static let graphite = Color(hex: "#181a15")
    static let olivePanel = Color(hex: "#24251d")
    static let mapPaper = Color(hex: "#d8c79b")
    static let parchment = Color(hex: "#e6d9b8")
    static let brass = Color(hex: "#c5a45f")
    static let oxidizedBrass = Color(hex: "#806b3f")
    static let ink = Color(hex: "#f2e8ce")
    static let mutedInk = Color(hex: "#b8ad91")
    static let signalCyan = Color(hex: "#9db4a2")
    static let fieldGreen = Color(hex: "#81966a")
    static let alertAmber = Color(hex: "#d3a55c")
    static let threatRed = Color(hex: "#b95645")

    static func statusColor(for score: Int, highIsGood: Bool = true) -> Color {
        if highIsGood {
            if score >= 70 {
                return fieldGreen
            }
            if score >= 40 {
                return alertAmber
            }
            return threatRed
        }
        if score >= 70 {
            return threatRed
        }
        if score >= 45 {
            return alertAmber
        }
        return fieldGreen
    }

    static func displayFont(_ style: Font.TextStyle, weight: Font.Weight = .semibold) -> Font {
        .system(style, design: .serif).weight(weight)
    }

    static func bodyFont(_ style: Font.TextStyle = .body, weight: Font.Weight = .regular) -> Font {
        .system(style, design: .serif).weight(weight)
    }

    static func labelFont(_ style: Font.TextStyle = .caption, weight: Font.Weight = .bold) -> Font {
        .system(style, design: .monospaced).weight(weight)
    }
}

struct GlassmorphicCardModifier: ViewModifier {
    var borderColor: Color
    var cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(
                LinearGradient(
                    colors: [
                        NativeWarRoomTheme.graphite.opacity(0.97),
                        NativeWarRoomTheme.archiveShadow.opacity(0.95)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(borderColor, lineWidth: 1)
            }
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(NativeWarRoomTheme.parchment.opacity(0.06))
                    .frame(height: 1)
                    .padding(.horizontal, cornerRadius)
            }
            .shadow(color: Color.black.opacity(0.34), radius: 8, x: 0, y: 4)
    }
}

struct WarRoomDossierModifier: ViewModifier {
    var borderColor: Color
    var cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(
                LinearGradient(
                    colors: [
                        NativeWarRoomTheme.olivePanel.opacity(0.92),
                        NativeWarRoomTheme.archiveShadow.opacity(0.96)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(NativeWarRoomTheme.mapPaper.opacity(0.08))
                    .frame(height: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(borderColor, lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.36), radius: 10, x: 0, y: 5)
    }
}

struct OrbitRingsView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var rotationLarge: Double = 0
    @State private var rotationSmall: Double = 0
    @State private var pulse: CGFloat = 0.85

    var body: some View {
        ZStack {
            Circle()
                .stroke(
                    NativeWarRoomTheme.brass.opacity(0.16),
                    style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [40, 150])
                )
                .frame(width: 200, height: 200)
                .rotationEffect(.degrees(rotationLarge))

            Circle()
                .stroke(
                    NativeWarRoomTheme.oxidizedBrass.opacity(0.22),
                    style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [20, 80])
                )
                .frame(width: 120, height: 120)
                .rotationEffect(.degrees(rotationSmall))

            Circle()
                .stroke(
                    NativeWarRoomTheme.mapPaper.opacity(0.08),
                    style: StrokeStyle(lineWidth: 4, lineCap: .butt, dash: [2, 8])
                )
                .frame(width: 160, height: 160)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.glowingCyan.opacity(0.35), Color.clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 30
                    )
                )
                .frame(width: 60, height: 60)
                .scaleEffect(pulse)
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 25).repeatForever(autoreverses: false)) {
                rotationLarge = 360
            }
            withAnimation(.linear(duration: 15).repeatForever(autoreverses: false)) {
                rotationSmall = -360
            }
            withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
                pulse = 1.15
            }
        }
    }
}

struct HoverScaleModifier: ViewModifier {
    @State private var isHovered = false
    let scale: CGFloat

    func body(content: Content) -> some View {
        content
            .scaleEffect(isHovered ? scale : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.65), value: isHovered)
            .onHover { hovering in
                isHovered = hovering
            }
    }
}

extension View {
    func hoverScale(_ scale: CGFloat = 1.02) -> some View {
        modifier(HoverScaleModifier(scale: scale))
    }

    func glassmorphicCard(borderColor: Color = .white.opacity(0.12), cornerRadius: CGFloat = 12) -> some View {
        modifier(GlassmorphicCardModifier(borderColor: borderColor, cornerRadius: cornerRadius))
    }

    func warRoomDossier(borderColor: Color = NativeWarRoomTheme.brass.opacity(0.22), cornerRadius: CGFloat = 10) -> some View {
        modifier(WarRoomDossierModifier(borderColor: borderColor, cornerRadius: cornerRadius))
    }
}
