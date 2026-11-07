import SwiftUI

struct NativeSettingsPanel: View {
    @ObservedObject var store: NativeCampaignStore
    /// API keys and the Turso token live in the Keychain (NativeSecretStore).
    /// These drafts keep the SecureField bindings; changes persist on change.
    @State private var nvidiaApiKey = ""
    @State private var openRouterApiKey = ""
    @State private var tursoAuthToken = ""
    @AppStorage(NativeCampaignStore.tursoDatabaseURLKey) private var tursoDatabaseURL: String = ""
    @State private var showAIConfiguration = false
    @State private var showCloudMirror = false
    @State private var showCampaignManagement = false
    @State private var showScenarioLibrary = false

    private var aiProviderSelection: Binding<NativeAIProviderPreference> {
        Binding(
            get: { store.selectedAIProviderPreference },
            set: { provider in
                guard store.setAIProvider(provider) else { return }

                Task {
                    await store.checkAIStatus()
                    guard store.selectedAIProviderPreference == provider else { return }
                    await store.refreshSuggestedActions(force: true)
                }
            }
        )
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
                DisclosureGroup(isExpanded: $showScenarioLibrary) {
                    NativeScenarioPicker(store: store)
                        .padding(.top, 8)
                } label: {
                    SettingsDisclosureLabel(
                        title: "Scenario",
                        detail: state.scenarioName,
                        systemImage: "map",
                        tint: Color.alertGold
                    )
                }
                .accessibilityIdentifier("native-scenario-section")
                NativeSaveSlotPicker(store: store)
                NativeAIStatusPanel(readiness: state.aiReadiness, sessionTotalTokens: store.sessionTokenUsage.total)

                NativeSettingsSection(title: "Quick actions", systemImage: "bolt.fill", tint: Color.alertGold) {
                    Button {
                        Task { await store.checkAIStatus() }
                    } label: {
                        Label("Poll model status", systemImage: "cpu")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("native-apple-status-check")

                    if state.gameMode == .ironman {
                        Label("Auto-save only (Iron Man)", systemImage: "lock.shield.fill")
                            .font(.system(.caption, design: .monospaced).weight(.bold))
                            .foregroundStyle(Color.softRed)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(Color.softRed.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                    } else {
                        Button {
                            store.manualSaveCampaign()
                        } label: {
                            Label("Save campaign", systemImage: "square.and.arrow.down")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.neonTeal.opacity(0.3))
                        .accessibilityIdentifier("native-save-campaign")
                    }
                }

                SettingsExpandableSection(
                    isExpanded: $showAIConfiguration,
                    accessibilityIdentifier: "native-ai-connection-section",
                    title: "AI and connection",
                    detail: "Strict NVIDIA or OpenRouter Free selection",
                    systemImage: "cpu",
                    tint: Color.glowingCyan
                ) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("AI ROUTING")
                            .font(.system(.caption, design: .monospaced).weight(.bold))
                            .foregroundStyle(Color.alertGold)

                        Picker("AI provider", selection: aiProviderSelection) {
                            ForEach(NativeAIProviderPreference.allCases, id: \.rawValue) { provider in
                                Text(provider.title).tag(provider)
                            }
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("native-ai-provider-picker")

                        Text(store.selectedAIProviderPreference.subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        if store.selectedAIProviderPreference == .nvidia,
                           nvidiaApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        {
                            Label("NVIDIA is selected, but no NVIDIA API key is saved. Requests will stay on NVIDIA and show a provider error.", systemImage: "exclamationmark.triangle")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.alertGold)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        if store.selectedAIProviderPreference == .openRouter, openRouterApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Label("OpenRouter Free is selected, but no API key is saved. Requests will stay on OpenRouter and show a provider error.", systemImage: "exclamationmark.triangle")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.alertGold)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.vertical, 8)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("NVIDIA API")
                            .font(.system(.caption, design: .monospaced).weight(.bold))
                            .foregroundStyle(Color.glowingCyan)

                        SecureField("NVIDIA API Key (nvapi-...)", text: $nvidiaApiKey)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier("native-nvidia-api-key")

                        Text("Used only when NVIDIA is selected. MiniMax-M3, Kimi-K2.6, and DeepSeek-V4-Flash requests stay on NVIDIA.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 8)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("OPENROUTER FREE API")
                            .font(.system(.caption, design: .monospaced).weight(.bold))
                            .foregroundStyle(Color.neonTeal)

                        SecureField("OpenRouter API Key", text: $openRouterApiKey)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier("native-openrouter-api-key")

                        Text("Used only when OpenRouter Free is selected. Requests use openrouter/free without an app-imposed completion-token cap.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 8)
                }

                DisclosureGroup(isExpanded: $showCloudMirror) {
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
                    .padding(.top, 8)
                } label: {
                    SettingsDisclosureLabel(
                        title: "Cloud save mirror",
                        detail: "Optional Turso recovery copy",
                        systemImage: "externaldrive.badge.icloud",
                        tint: Color.neonTeal
                    )
                }
                .accessibilityIdentifier("native-cloud-mirror-section")

                DisclosureGroup(isExpanded: $showCampaignManagement) {
                    VStack(alignment: .leading, spacing: 14) {
                        NativeCountrySwitchPanel(store: store, state: state)
                        NativeNewCountryPanel(store: store)

                        Divider().background(Color.softRed.opacity(0.24))

                        Text("Leaving or deleting changes the active campaign. Saves remain available unless you reset them.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Button {
                            store.exitToMainMenu()
                        } label: {
                            Label("Exit to main menu", systemImage: "arrow.left.circle")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("native-exit-to-menu")

                        Button(role: .destructive) {
                            store.resetSelection()
                        } label: {
                            Label("Reset and delete save", systemImage: "trash")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .accessibilityIdentifier("native-change-country")
                    }
                    .padding(.top, 8)
                } label: {
                    SettingsDisclosureLabel(
                        title: "Campaign management",
                        detail: "Country control, exit, and destructive actions",
                        systemImage: "exclamationmark.shield",
                        tint: Color.softRed
                    )
                }
                .accessibilityIdentifier("native-campaign-management-section")
            }
        }
        .onAppear {
            nvidiaApiKey = NativeSecretStore.string(forKey: "NVIDIA_API_KEY") ?? ""
            openRouterApiKey = NativeSecretStore.string(forKey: "OPENROUTER_API_KEY") ?? ""
            tursoAuthToken = NativeSecretStore.string(forKey: NativeCampaignStore.tursoAuthTokenKey) ?? ""
        }
        .onChange(of: nvidiaApiKey) { _, newValue in
            NativeSecretStore.set(newValue, forKey: "NVIDIA_API_KEY")
        }
        .onChange(of: openRouterApiKey) { _, newValue in
            NativeSecretStore.set(newValue, forKey: "OPENROUTER_API_KEY")
        }
        .onChange(of: tursoAuthToken) { _, newValue in
            NativeSecretStore.set(newValue, forKey: NativeCampaignStore.tursoAuthTokenKey)
        }
    }
}

private struct NativeSettingsSection<Content: View>: View {
    let title: String
    let systemImage: String
    let tint: Color
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title.uppercased(), systemImage: systemImage)
                .font(.system(.caption, design: .monospaced).weight(.bold))
                .foregroundStyle(tint)
            content
        }
        .padding(12)
        .background(tint.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(tint.opacity(0.16), lineWidth: 1)
        }
    }
}

private struct SettingsDisclosureLabel: View {
    let title: String
    let detail: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.subheadline, design: .monospaced).weight(.bold))
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 8)
    }
}

private struct SettingsExpandableSection<Content: View>: View {
    @Binding var isExpanded: Bool
    let accessibilityIdentifier: String
    let title: String
    let detail: String
    let systemImage: String
    let tint: Color
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.16)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    SettingsDisclosureLabel(
                        title: title,
                        detail: detail,
                        systemImage: systemImage,
                        tint: tint
                    )
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(accessibilityIdentifier)
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")

            if isExpanded {
                content
                    .padding(.leading, 22)
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

struct NativeCountrySwitchPanel: View {
    @ObservedObject var store: NativeCampaignStore
    let state: NativeCampaignState
    @State private var pendingCountry: PlayerCountry?

    private var isLocked: Bool {
        state.gameMode == .ironman
    }

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 10) {
                Picker(
                    "Controlled country",
                    selection: Binding(
                        get: { state.country.code },
                        set: { code in
                            guard code != state.country.code else { return }
                            pendingCountry = store.allVisibleCountries().first { $0.code == code }
                        }
                    )
                ) {
                    ForEach(store.allVisibleCountries()) { country in
                        Text("\(country.name) · \(country.code)").tag(country.code)
                    }
                }
                .pickerStyle(.menu)
                .disabled(isLocked)
                .accessibilityIdentifier("native-country-switch-picker")

                Text(isLocked
                    ? "Iron Man locks the controlled country for the life of this save."
                    : "Transfer control without resetting the shared timeline, conflicts, diplomacy, or economic history. Drafts clear and the decision matrix refreshes for the new country.")
                    .font(.caption2)
                    .foregroundStyle(isLocked ? Color.alertGold : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 6)
        } label: {
            Label {
                Text("Transfer Player Control")
                    .font(.system(.subheadline, design: .monospaced).weight(.bold))
            } icon: {
                Image(systemName: isLocked ? "lock.shield.fill" : "arrow.triangle.2.circlepath.circle.fill")
                    .foregroundStyle(isLocked ? Color.alertGold : Color.glowingCyan)
            }
            .foregroundStyle(isLocked ? Color.alertGold : Color.glowingCyan)
        }
        .padding(.vertical, 8)
        .accessibilityIdentifier("native-country-switch-panel")
        .alert(item: $pendingCountry) { country in
            Alert(
                title: Text("Assume control of \(country.name)?"),
                message: Text("The campaign world stays intact. Current drafts clear, the active economic ledger changes to \(country.name), and AI suggestions refresh for the new government."),
                primaryButton: .default(Text("Switch country")) {
                    store.switchCountry(to: country)
                },
                secondaryButton: .cancel()
            )
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
                    HStack(alignment: .center, spacing: 12) {
                        Image(systemName: scenario.id == store.selectedScenarioID ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(scenario.id == store.selectedScenarioID ? Color.neonTeal : Color.iceBlue.opacity(0.4))

                        Image(scenario.assetImageName)
                            .resizable()
                            .aspectRatio(16 / 9, contentMode: .fill)
                            .frame(width: 52, height: 32)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay {
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(scenario.id == store.selectedScenarioID ? Color.neonTeal.opacity(0.5) : Color.white.opacity(0.12), lineWidth: 1)
                            }

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
    @AppStorage(NativeAIProviderPreference.storageKey) private var aiProviderPreferenceRaw: String = NativeAIProviderPreference.nvidia.rawValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var selectedProviderName: String {
        (NativeAIProviderPreference(rawValue: aiProviderPreferenceRaw) ?? .nvidia).providerName
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
                        .foregroundStyle(Color.neonTeal)
                    Text("NO APP CAP")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.iceBlue)
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
        .warRoomDossier(borderColor: NativeWarRoomTheme.brass.opacity(0.16), cornerRadius: 8)
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

/// Panel for creating new countries mid-campaign.
/// Adds entries to `dynamicCountries` with a starter economic ledger and AI state
/// so the new nation is immediately interactive in diplomacy and world economics.
struct NativeNewCountryPanel: View {
    @ObservedObject var store: NativeCampaignStore
    @State private var isExpanded = false
    @State private var countryCode = ""
    @State private var countryName = ""
    @State private var feedback: String?

    private var isValid: Bool {
        let cleanCode = countryCode.uppercased().filter { $0 >= "A" && $0 <= "Z" }
        let cleanName = countryName.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleanCode.count >= 3 && cleanCode.count <= 6 && cleanName.count >= 4
    }

    var body: some View {
        DisclosureGroup(
            isExpanded: $isExpanded,
            content: {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Add a new sovereign state to the world. It will appear in diplomacy, world economics, and AI decisions.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("CODE (3-6 letters)")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color.alertGold)
                            TextField("e.g. ATL", text: $countryCode)
                                .textFieldStyle(.roundedBorder)
                                .autocorrectionDisabled()
                                .newCountryCodeFormatting(text: $countryCode)
                                .accessibilityIdentifier("native-new-country-code")
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("FULL NAME")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color.alertGold)
                            TextField("e.g. Atlantic Federation", text: $countryName)
                                .textFieldStyle(.roundedBorder)
                                .accessibilityIdentifier("native-new-country-name")
                        }
                    }

                    if let feedback {
                        Text(feedback)
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(feedback.hasPrefix("✅") ? Color.neonTeal : Color.softRed)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Button {
                        let success = store.addDynamicCountry(code: countryCode, name: countryName)
                        if success {
                            feedback = "✅ \(countryName) (\(countryCode.uppercased())) added to the world."
                            countryCode = ""
                            countryName = ""
                        } else {
                            let cleanCode = countryCode.uppercased().filter { $0 >= "A" && $0 <= "Z" }
                            if cleanCode.count < 3 {
                                feedback = "Code must be 3-6 letters."
                            } else if let state = store.state {
                                let existing = Set(NativeStrategyContextDatabase.strategicCountryCodes(for: state))
                                feedback = existing.contains(cleanCode)
                                    ? "Code \(cleanCode) already exists."
                                    : "Name must be at least 4 characters."
                            } else {
                                feedback = "No campaign loaded."
                            }
                        }
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                            Text("ADD COUNTRY")
                                .font(.system(.subheadline, design: .monospaced).weight(.bold))
                        }
                        .frame(maxWidth: .infinity, minHeight: 36)
                    }
                    .buttonStyle(.bordered)
                    .tint(Color.neonTeal)
                    .disabled(!isValid)
                    .accessibilityIdentifier("native-add-country-button")

                    // Show existing dynamic countries
                    if let state = store.state, !state.dynamicCountries.isEmpty {
                        Divider().background(Color.white.opacity(0.08))
                        Text("CUSTOM NATIONS (\(state.dynamicCountries.count))")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.iceBlue)
                        ForEach(state.dynamicCountries.sorted(by: { $0.key < $1.key }), id: \.key) { code, name in
                            HStack {
                                Text(code)
                                    .font(.system(.caption, design: .monospaced).weight(.bold))
                                    .foregroundStyle(Color.alertGold)
                                Text(name)
                                    .font(.caption)
                                    .foregroundStyle(.primary)
                                Spacer()
                            }
                        }
                    }
                }
                .padding(.top, 4)
            },
            label: {
                Label {
                    Text("Create New Country")
                        .font(.system(.subheadline, design: .monospaced).weight(.bold))
                } icon: {
                    Image(systemName: "flag.badge.plus")
                        .foregroundStyle(Color.neonTeal)
                }
                .foregroundStyle(Color.neonTeal)
            }
        )
        .padding(.vertical, 8)
        .accessibilityIdentifier("native-new-country-panel")
    }
}

/// Cross-platform modifier for the country code field.
/// Applies iOS autocapitalization where available, plus uppercase A-Z filtering
/// and 6-character clamping via onChange (works on both macOS and iOS).
private struct NewCountryCodeFormatting: ViewModifier {
    @Binding var text: String

    func body(content: Content) -> some View {
        #if os(iOS)
            content
                .textInputAutocapitalization(.characters)
                .onChange(of: text) { _, newValue in
                    applyFilter(newValue)
                }
        #else
            content
                .onChange(of: text) { _, newValue in
                    applyFilter(newValue)
                }
        #endif
    }

    private func applyFilter(_ newValue: String) {
        let filtered = newValue.uppercased().filter { $0 >= "A" && $0 <= "Z" }
        text = String(filtered.prefix(6))
    }
}

private extension View {
    func newCountryCodeFormatting(text: Binding<String>) -> some View {
        modifier(NewCountryCodeFormatting(text: text))
    }
}
