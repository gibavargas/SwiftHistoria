import SwiftUI

struct NativeSettingsPanel: View {
    @ObservedObject var store: NativeCampaignStore
    @AppStorage(NativeAIProviderPreference.storageKey) private var aiProviderPreferenceRaw: String = NativeAIProviderPreference.openRouter.rawValue
    @AppStorage("OPENROUTER_API_KEY") private var openRouterApiKey: String = ""
    @AppStorage("ZAI_API_KEY") private var zaiApiKey: String = ""
    @AppStorage("ZAI_USE_CODING_ENDPOINT") private var zaiUseCodingEndpoint: Bool = false
    @AppStorage(NativeCampaignStore.tursoDatabaseURLKey) private var tursoDatabaseURL: String = ""
    @AppStorage(NativeCampaignStore.tursoAuthTokenKey) private var tursoAuthToken: String = ""

    private var selectedAIProviderPreference: NativeAIProviderPreference {
        NativeAIProviderPreference(rawValue: aiProviderPreferenceRaw) ?? .openRouter
    }

    var body: some View {
        NativePanel(accessibilityIdentifier: "native-settings-panel") {
            Label("Settings", systemImage: "slider.horizontal.3")
                .font(NativeTypography.sectionTitle())
                .foregroundStyle(Color.iceBlue)
                .help("Adjust difficulty, language, and AI model settings.")

            if let state = store.state {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(state.country.name) · \(state.country.code) · ROUND \(state.round)")
                        .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                        .foregroundStyle(Color.glowingCyan)
                    Text(state.scenarioDescription)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider()
                    .background(Color.white.opacity(0.12))

                VStack(alignment: .leading, spacing: 8) {
                    Text("Difficulty")
                        .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                        .foregroundStyle(.secondary)
                    Picker(
                        "Difficulty",
                        selection: Binding(
                            get: { state.gameMode },
                            set: { store.setGameMode($0) }
                        )
                    ) {
                        ForEach(NativeGameMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("native-difficulty-picker")

                    Text(state.gameMode.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .italic()
                        .fixedSize(horizontal: false, vertical: true)
                }

                NativeLanguagePicker(store: store, state: state)
                NativeScenarioPicker(store: store)
                NativeSaveSlotPicker(store: store)
                NativeAIStatusPanel(readiness: state.aiReadiness, sessionTotalTokens: store.sessionTokenUsage.total)

                VStack(alignment: .leading, spacing: 8) {
                    Text("AI PROVIDER")
                        .font(.system(.caption, design: .monospaced).weight(.bold))
                        .foregroundStyle(Color.alertGold)

                    Picker("AI Provider", selection: $aiProviderPreferenceRaw) {
                        ForEach(NativeAIProviderPreference.allCases, id: \.rawValue) { provider in
                            Text(provider.title).tag(provider.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("native-ai-provider-picker")
                    .onChange(of: aiProviderPreferenceRaw) { _, _ in
                        Task {
                            await store.checkAIStatus()
                            await store.refreshSuggestedActions(force: true)
                        }
                    }

                    Text(selectedAIProviderPreference.subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if selectedAIProviderPreference == .openRouter, openRouterApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Label("OpenRouter is selected, but no API key is saved. Turn resolution, suggestions, advisor, and diplomacy requests will stay on OpenRouter and show a visible provider error until a key is saved.", systemImage: "exclamationmark.triangle")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.alertGold)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if selectedAIProviderPreference == .zai, zaiApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Label("Z.AI is selected, but no API key is saved. Turn resolution will fall back to Apple Foundation Models.", systemImage: "exclamationmark.triangle")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.alertGold)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 8)

                VStack(alignment: .leading, spacing: 8) {
                    Text("OPENROUTER (FREE) CONFIGURATION")
                        .font(.system(.caption, design: .monospaced).weight(.bold))
                        .foregroundStyle(Color.neonTeal)

                    SecureField("OpenRouter API Key", text: $openRouterApiKey)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("native-openrouter-api-key")

                    Text("Used when AI Provider is set to OpenRouter. Routes through OpenRouter's unified Free Models Router (openrouter/free).")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 8)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Z.AI (GLM-5.1) CONFIGURATION")
                        .font(.system(.caption, design: .monospaced).weight(.bold))
                        .foregroundStyle(Color.glowingCyan)

                    SecureField("Z.AI API Key", text: $zaiApiKey)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("native-zai-api-key")

                    Toggle("Use GLM Coding Endpoint", isOn: $zaiUseCodingEndpoint)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("Used when AI Provider is set to Z.AI. GLM lanes can run concurrently, with Apple Foundation Models as safety fallback if unavailable.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 8)

                VStack(alignment: .leading, spacing: 8) {
                    Text("TURSO SAVE MIRROR")
                        .font(.system(.caption, design: .monospaced).weight(.bold))
                        .foregroundStyle(Color.neonTeal)

                    TextField("libsql://database-org.turso.io", text: $tursoDatabaseURL)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.URL)
                        .disableAutocorrection(true)
                        .accessibilityIdentifier("native-turso-database-url")

                    SecureField("Turso database token", text: $tursoAuthToken)
                        .textFieldStyle(.roundedBorder)
                        .disableAutocorrection(true)
                        .accessibilityIdentifier("native-turso-auth-token")

                    Text("Optional. Campaign saves stay local for fast launches and are mirrored to Turso in the background when both fields are set.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 8)

                Button {
                    Task { await store.checkAIStatus() }
                } label: {
                    HStack {
                        Image(systemName: "cpu")
                        Text("POLL MODEL STATUS")
                            .font(.system(.subheadline, design: .monospaced).weight(.bold))
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("native-apple-status-check")

                if state.gameMode == .ironman {
                    HStack {
                        Image(systemName: "lock.shield.fill")
                            .foregroundStyle(Color.softRed)
                        Text("AUTO-SAVE ONLY (IRON MAN)")
                            .font(.system(.caption, design: .monospaced).weight(.bold))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Color.white.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    Button {
                        store.manualSaveCampaign()
                    } label: {
                        HStack {
                            Image(systemName: "square.and.arrow.down")
                            Text("SAVE CAMPAIGN")
                                .font(.system(.subheadline, design: .monospaced).weight(.bold))
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.neonTeal.opacity(0.3))
                    .accessibilityIdentifier("native-save-campaign")
                }

                Button {
                    store.exitToMainMenu()
                } label: {
                    HStack {
                        Image(systemName: "arrow.left.circle")
                        Text("EXIT TO MAIN MENU")
                            .font(.system(.subheadline, design: .monospaced).weight(.bold))
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("native-exit-to-menu")

                Button(role: .destructive) {
                    store.resetSelection()
                } label: {
                    HStack {
                        Image(systemName: "flag.fill")
                        Text("RESET & DELETE SAVE")
                            .font(.system(.subheadline, design: .monospaced).weight(.bold))
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .accessibilityIdentifier("native-change-country")
            }
        }
    }
}

struct NativeSaveSlotPicker: View {
    @ObservedObject var store: NativeCampaignStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SAVE SLOT")
                .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                .foregroundStyle(.secondary)

            Picker(
                "Save Slot",
                selection: Binding(
                    get: { store.saveSlot },
                    set: { store.switchSlot($0) }
                )
            ) {
                ForEach(1 ... 3, id: \.self) { slot in
                    Text("Slot \(slot)").tag(slot)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("native-save-slot-picker")

            VStack(alignment: .leading, spacing: 6) {
                ForEach(1 ... 3, id: \.self) { slot in
                    let summary = store.slotSummary(slot)
                    HStack {
                        Text("Slot \(slot)")
                            .font(.system(.caption, design: .monospaced).weight(.bold))
                            .foregroundStyle(slot == store.saveSlot ? Color.glowingCyan : .secondary)
                        Spacer()
                        Text(summary.map { "\($0.countryName) · Round \($0.round) · \($0.scenarioName)" } ?? "Empty")
                            .font(.caption)
                            .foregroundStyle(summary == nil ? .secondary : .primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                    }
                    .accessibilityIdentifier("native-save-slot-summary-\(slot)")
                }
            }

            Text("Changing slots loads that slot immediately. Empty slots return to campaign setup.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct NativeLanguagePicker: View {
    @ObservedObject var store: NativeCampaignStore
    let state: NativeCampaignState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("INTERFACE LANGUAGE")
                .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                .foregroundStyle(.secondary)
            Picker(
                "Language",
                selection: Binding(
                    get: { store.selectedLanguage },
                    set: { store.setLanguage($0) }
                )
            ) {
                ForEach(NativeGameLanguage.allCases) { language in
                    Text(language.label).tag(language)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("native-language-picker")

            if state.language != store.selectedLanguage {
                Text("Language will sync on the next app launch. Restart to apply UI changes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct NativeScenarioPicker: View {
    @ObservedObject var store: NativeCampaignStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SCENARIOS")
                .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("native-scenario-library")
            ForEach(NativeScenarioCatalog.all) { scenario in
                Button {
                    store.selectScenario(id: scenario.id)
                } label: {
                    HStack(alignment: .center, spacing: 10) {
                        Image(systemName: scenario.id == store.selectedScenarioID ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(scenario.id == store.selectedScenarioID ? Color.neonTeal : Color.iceBlue.opacity(0.4))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(scenario.name)
                                .font(.body.weight(.bold))
                            Text(scenario.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(scenario.name), \(scenario.subtitle)")
                .accessibilityAddTraits(scenario.id == store.selectedScenarioID ? [.isSelected] : [])
                .accessibilityIdentifier("native-scenario-option-\(scenario.id)")
            }
        }
    }
}

struct NativeAIStatusPanel: View {
    let readiness: NativeAIReadiness
    var sessionTotalTokens: Int = 0
    @State private var pulsing = false
    @AppStorage(NativeAIProviderPreference.storageKey) private var aiProviderPreferenceRaw: String = NativeAIProviderPreference.openRouter.rawValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var selectedProviderName: String {
        (NativeAIProviderPreference(rawValue: aiProviderPreferenceRaw) ?? .openRouter).providerName
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(readiness.ok ? Color.neonTeal : Color.softRed)
                    .frame(width: 8, height: 8)
                    .opacity(pulsing ? 0.4 : 1.0)
                    .scaleEffect(pulsing ? 1.2 : 1.0)
                    .onAppear {
                        guard !reduceMotion else { return }
                        withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                            pulsing = true
                        }
                    }

                Text("\(selectedProviderName.uppercased()) // STATUS")
                    .font(.system(.caption, design: .monospaced).weight(.bold))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("AVAILABILITY:")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text(nativeFormatAvailability(readiness.availability).uppercased())
                        .font(.system(.caption, design: .monospaced).weight(.bold))
                        .foregroundStyle(readiness.ok ? Color.neonTeal : Color.softRed)
                }

                HStack {
                    Text("LAST DIAGNOSTIC:")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text(readiness.checkedAt.isEmpty ? "NEVER" : readiness.checkedAt.uppercased())
                        .font(.system(.caption, design: .monospaced).weight(.bold))
                        .foregroundStyle(Color.iceBlue)
                }

                HStack {
                    Text("SESSION TOKENS:")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text(String(format: "%.1fk", Double(sessionTotalTokens) / 1000.0))
                        .font(.system(.caption, design: .monospaced).weight(.bold))
                        .foregroundStyle(sessionTotalTokens > 100_000 ? Color.softRed : Color.neonTeal)
                    if sessionTotalTokens > 100_000 {
                        Text("⚠ BUDGET WARNING")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.softRed)
                    }
                }
            }
            .padding(10)
            .background(Color.white.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            }

            if !readiness.recoverySuggestion.isEmpty {
                Text(readiness.recoverySuggestion)
                    .font(.caption)
                    .foregroundStyle(Color.alertGold)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(8)
                    .background(Color.alertGold.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.alertGold.opacity(0.24), lineWidth: 1)
                    }
            }
        }
        .accessibilityIdentifier("native-ai-status-panel")
    }
}

struct NativePanel<Content: View>: View {
    let accessibilityIdentifier: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassmorphicCard(borderColor: .white.opacity(0.08), cornerRadius: 14)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

struct NativeStatusChip: View {
    let text: String
    let systemImage: String
    var tintColor: Color?

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.system(.caption, design: .monospaced).weight(.bold))
            .foregroundStyle(tintColor ?? Color.iceBlue)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background((tintColor ?? Color.iceBlue).opacity(0.08), in: Capsule())
            .overlay {
                Capsule()
                    .stroke((tintColor ?? Color.iceBlue).opacity(0.24), lineWidth: 1)
            }
            .accessibilityElement(children: .combine)
    }
}

func nativeFormatAvailability(_ value: String) -> String {
    switch value {
    case "apple-intelligence-not-enabled": "Apple Intelligence off"
    case "apple-foundation-error": "AI route paused"
    case "available": "AI route ready"
    case "model-not-ready": "Model not ready"
    case "not-checked": "Not checked"
    case "unsupported-os": "Unsupported OS"
    default: value.isEmpty ? "Unknown" : value
    }
}

func nativeFormatHUDAvailability(_ value: String) -> String {
    switch value {
    case "available": "Simulation Link Online"
    default: "Simulation Link Offline"
    }
}

func nativeFormatPercent(_ value: Double) -> String {
    String(format: "%.1f%%", value)
}

func nativeFormatSignedPercent(_ value: Double) -> String {
    String(format: "%+.1f%%", value)
}
