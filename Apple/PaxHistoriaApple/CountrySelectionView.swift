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
    @State private var setupStep = 0 // 0: Scenario/Language; 1: AI Provider; 2: Choose Country
    @AppStorage(NativeAIProviderPreference.storageKey) private var aiProviderRaw: String = NativeAIProviderPreference.openRouter.rawValue
    @AppStorage("OPENROUTER_API_KEY") private var openRouterKey: String = ""
    @AppStorage("ZAI_API_KEY") private var zaiKey: String = ""

    private var selectedProvider: NativeAIProviderPreference {
        NativeAIProviderPreference(rawValue: aiProviderRaw) ?? .openRouter
    }

    private var canProceedFromProviderStep: Bool {
        switch selectedProvider {
        case .appleFoundation:
            true
        case .openRouter:
            !openRouterKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .zai:
            !zaiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private var filteredCountries: [PlayerCountry] {
        let mapped = countries.map { country -> PlayerCountry in
            if country.code == "RUS", selectedScenarioID == "soviet-triumph" {
                return PlayerCountry(code: "RUS", name: "Soviet Union")
            }
            return country
        }
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else {
            return mapped
        }

        return mapped.filter { country in
            country.name.localizedCaseInsensitiveContains(normalizedQuery) ||
                country.code.localizedCaseInsensitiveContains(normalizedQuery)
        }
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
                NavigationSplitView {
                    setupPanel
                        .navigationTitle("New Campaign")
                } detail: {
                    countryList
                        .navigationTitle("Choose Country")
                }
                .frame(minWidth: 820, minHeight: 620)
            #else
                NavigationStack {
                    VStack(spacing: 0) {
                        if setupStep == 0 {
                            ScrollView {
                                VStack(alignment: .leading, spacing: 20) {
                                    header
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
                                        Spacer()
                                    }

                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("Choose AI Provider")
                                            .font(.title2.weight(.bold))
                                        Text("Select how SwiftHistoria generates turns. You can change this later in Settings.")
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }

                                    VStack(spacing: 12) {
                                        ForEach(NativeAIProviderPreference.allCases, id: \.rawValue) { provider in
                                            providerCard(provider)
                                        }
                                    }

                                    if selectedProvider == .openRouter || selectedProvider == .zai {
                                        apiKeyField(for: selectedProvider)
                                    }

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
                                    Spacer()
                                }
                                .padding(.horizontal, 20)
                                .padding(.top, 16)
                                .padding(.bottom, 12)

                                searchField
                                    .padding(.horizontal, 20)
                                    .padding(.bottom, 12)

                                countryList
                            }
                        }
                    }
                    .navigationTitle(setupStep == 0 ? "New Campaign" : setupStep == 1 ? "AI Provider" : "Choose Country")
                    .navigationBarTitleDisplayMode(.inline)
                }
            #endif
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
                Image(systemName: provider == .appleFoundation ? "cpu" : provider == .openRouter ? "network" : "bolt.fill")
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
        let key: Binding<String> = provider == .openRouter ? $openRouterKey : $zaiKey
        let placeholder = provider == .openRouter ? "sk-or-v1-..." : "your-zai-key"

        VStack(alignment: .leading, spacing: 8) {
            Text("\(provider.title) API Key")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            SecureField(placeholder, text: key)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .accessibilityIdentifier("native-\(provider.rawValue)-key-field")

            Text(provider == .openRouter
                ? "Free tier: 20 requests/minute. Get a key at openrouter.ai/keys."
                : "Get a key at z.ai")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var setupPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                scenarioDeck
                languageDeck
                searchField
            }
            .padding(20)
            .frame(maxWidth: 520, alignment: .leading)
        }
        .safeAreaInset(edge: .bottom) {
            if filteredCountries.isEmpty {
                EmptyView()
            } else {
                Text("\(filteredCountries.count) countries available")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(.regularMaterial)
                    .accessibilityIdentifier("native-country-count")
            }
        }
        .accessibilityIdentifier("native-country-selection")
    }

    private var countryList: some View {
        List {
            Section {
                if filteredCountries.isEmpty {
                    ContentUnavailableView(
                        "No country matched that search.",
                        systemImage: "magnifyingglass",
                        description: Text("Try a country name or ISO code.")
                    )
                    .listRowBackground(Color.clear)
                    .accessibilityIdentifier("native-country-empty")
                } else {
                    ForEach(filteredCountries) { country in
                        Button {
                            onSelect(country)
                        } label: {
                            CountryRow(country: country)
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(country.name), ISO code \(country.code)")
                        .accessibilityHint("Starts a campaign as \(country.name).")
                        .accessibilityIdentifier("native-country-option-\(country.code)")
                    }
                }
            } header: {
                Text("Countries")
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.black.opacity(0.25))
        .accessibilityIdentifier("native-country-list")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("SwiftHistoria")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.glowingCyan)
                .textCase(.uppercase)
                .tracking(2.6)

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
                            .frame(width: 210)
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
                }
            }
            .padding(10)
            .background(NativeWarRoomTheme.graphite.opacity(0.72))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            }
            .accessibilityLabel("Search country or ISO code")
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

private struct CountryRow: View {
    let country: PlayerCountry
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(country.name)
                    .font(.body.weight(.bold))
                    .foregroundStyle(isHovered ? Color.accentColor : Color.primary)
            }

            Spacer()

            Text(country.code)
                .font(.system(.caption2, design: .monospaced).weight(.bold))
                .foregroundStyle(isHovered ? Color.accentColor : .secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.05), in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(isHovered ? Color.accentColor.opacity(0.3) : Color.white.opacity(0.06), lineWidth: 1)
                }

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(isHovered ? Color.accentColor : Color.secondary.opacity(0.5))
        }
        .contentShape(Rectangle())
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
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

    var body: some View {
        let accent = Color(hex: scenario.accentColor)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(scenario.name)
                    .font(NativeWarRoomTheme.labelFont(.subheadline))
                    .foregroundStyle(selected ? NativeWarRoomTheme.ink : NativeWarRoomTheme.mutedInk)
                    .lineLimit(1)
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.subheadline)
                    .foregroundStyle(selected ? accent : .secondary)
            }
            Text(scenario.subtitle)
                .font(.caption.weight(.medium))
                .foregroundStyle(selected ? accent.opacity(0.8) : .secondary)
                .lineLimit(2)
            Text(scenario.heroSubtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
        .warRoomDossier(
            borderColor: selected ? accent.opacity(0.7) : NativeWarRoomTheme.brass.opacity(0.18),
            cornerRadius: 10
        )
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .hoverScale(1.02)
    }
}

// MARK: - Helper Extensions

extension Color {
    static let spaceBlack = Color(hex: "#02050a")
    static let deepSlate = Color(hex: "#07111c")
    static let iceBlue = Color(hex: "#8abeff")
    static let glowingCyan = Color(hex: "#33c9ff")
    static let neonTeal = Color(hex: "#4ad4a0")
    static let alertGold = Color(hex: "#f4c96d")
    static let softRed = Color(hex: "#ff5777")

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
    static let blackboard = Color(hex: "#050706")
    static let archiveShadow = Color(hex: "#0d0c09")
    static let graphite = Color(hex: "#171a17")
    static let olivePanel = Color(hex: "#24251b")
    static let mapPaper = Color(hex: "#d8c79b")
    static let brass = Color(hex: "#c9a45b")
    static let oxidizedBrass = Color(hex: "#8d7742")
    static let ink = Color(hex: "#f1e6c8")
    static let mutedInk = Color(hex: "#b8ad8e")
    static let signalCyan = Color(hex: "#6ec7d5")
    static let fieldGreen = Color(hex: "#7fa66a")
    static let alertAmber = Color(hex: "#e0ae55")
    static let threatRed = Color(hex: "#c86454")

    static func statusColor(for score: Int, highIsGood: Bool = true) -> Color {
        if highIsGood {
            if score >= 70 { return fieldGreen }
            if score >= 40 { return alertAmber }
            return threatRed
        }
        if score >= 70 { return threatRed }
        if score >= 45 { return alertAmber }
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
            .background(.ultraThinMaterial)
            .background(Color.deepSlate.opacity(0.4))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(borderColor, lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.4), radius: 8, x: 0, y: 4)
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
