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

    @State private var query = ""

    private var filteredCountries: [PlayerCountry] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else {
            return countries
        }

        return countries.filter { country in
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
                    setupPanel
                    countryList
                }
                .navigationTitle("New Campaign")
                .navigationBarTitleDisplayMode(.inline)
            }
            #endif
        }
        .tint(selectedScenarioAccentColor)
        .preferredColorScheme(.dark)
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
                                .frame(minHeight: 44)
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
        .background(Color.black.opacity(0.35))
        .accessibilityIdentifier("native-country-list")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SwiftHistoria")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(2.6)

            Text("Choose your country")
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(.primary)
                .minimumScaleFactor(0.8)

            Text("Pick the scenario, language, and player nation before the first turn. Nothing starts until you choose explicitly.")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var scenarioDeck: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Scenario", systemImage: "square.stack.3d.up")
                    .font(.headline)
                    .accessibilityIdentifier("native-scenario-library")
                Spacer()
                Text(NativeScenarioCatalog.scenario(for: selectedScenarioID).name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(scenarios) { scenario in
                        Button {
                            onScenarioSelect(scenario.id)
                        } label: {
                            ScenarioSelectionCard(
                                scenario: scenario,
                                selected: scenario.id == selectedScenarioID
                            )
                            .frame(width: 220)
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
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var languageDeck: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Language", systemImage: "character.bubble")
                    .font(.headline)
                Spacer()
                Text(selectedLanguage.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var searchField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Find a country", systemImage: "magnifyingglass")
                .font(.headline)
            TextField("Search country or ISO code", text: $query)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Search country or ISO code")
                .accessibilityIdentifier("native-country-search")
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct CountrySelectionBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(red: 0.02, green: 0.018, blue: 0.015),
                Color(red: 0.08, green: 0.06, blue: 0.035),
                Color.black,
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

private struct CountryRow: View {
    let country: PlayerCountry
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(country.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(isHovered ? Color.accentColor : Color.primary)

                Text(country.code)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(isHovered ? Color.accentColor : Color.secondary)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 8)
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
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? accent : .secondary)
            }
            Text(scenario.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Text(scenario.heroSubtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
        .background(selected ? accent.opacity(0.12) : .white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(selected ? accent.opacity(0.8) : .white.opacity(0.12), lineWidth: selected ? 2 : 1)
        }
        .hoverScale(1.02)
    }
}

// MARK: - Helper Extensions

extension Color {
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
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
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
        self.modifier(HoverScaleModifier(scale: scale))
    }
}
