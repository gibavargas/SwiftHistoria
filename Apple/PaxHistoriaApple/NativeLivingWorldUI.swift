import SwiftUI

// MARK: - Living World UI: mode picker, day HUD, actions, hash bridge, menu commentary

/// Vic3-style main-menu commentary: reads the saved world (read-only) and
/// renders one line per notable country plus a world situation line.
struct LivingWorldMenuCommentary: View {
    let slot: Int

    private var savedWorld: LivingWorldState? {
        LivingWorldSession.load(slot: slot, directory: Self.defaultDirectory)
    }

    static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SwiftHistoria", isDirectory: true)
            .appendingPathComponent("living-world", isDirectory: true)
    }

    var body: some View {
        if let world = savedWorld {
            VStack(alignment: .leading, spacing: 6) {
                Label(worldSituation(world), systemImage: world.wars.isEmpty ? "globe.europe.africa" : "flame")
                    .font(.system(.caption, design: .monospaced).weight(.bold))
                    .foregroundStyle(world.wars.isEmpty ? Color.neonTeal : Color.softRed)

                ForEach(notableLines(world), id: \.self) { line in
                    Text(line)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(10)
            .background(Color.spaceBlack.opacity(0.6))
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.neonTeal.opacity(0.2), lineWidth: 1))
        }
    }

    private func worldSituation(_ world: LivingWorldState) -> String {
        let wars = world.wars.count
        let key: LWProseKey = wars > 0 ? .uiSituationWar : .uiSituationPeace
        return LWProse.string(key, language: world.language, ["date": world.today.stamp, "wars": "\(wars)"])
    }

    private func notableLines(_ world: LivingWorldState) -> [String] {
        let countries = world.countries.values
            .sorted { $0.gdpEstimate > $1.gdpEstimate }
            .prefix(5)
        let rng = LWRNG(worldSeed: world.worldSeed, dayIndex: world.dayIndex)
        return countries.map { country in
            LWBrainFactory.brain(for: country).commentary(world: world, country: country, language: world.language, rng: rng)
        }
    }
}

/// Mode picker shown when starting a new match: Living World (day-based,
/// offline) vs Classic (LLM quarterly turns via the hash bridge).
struct LivingWorldModePicker: View {
    @Binding var selectedMode: NativeSimulationMode
    let onStartLivingWorld: () -> Void
    @State private var hasExistingSave = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SIMULATION MODE")
                .font(.system(.caption, design: .monospaced).weight(.bold))
                .foregroundStyle(Color.neonTeal)

            ForEach(NativeSimulationMode.allCases) { mode in
                Button {
                    selectedMode = mode
                } label: {
                    HStack {
                        Image(systemName: selectedMode == mode ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(selectedMode == mode ? Color.neonTeal : Color.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(mode.title).fontWeight(.semibold)
                            Text(mode.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer()
                    }
                    .padding(10)
                    .background(Color.spaceBlack.opacity(0.5))
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(selectedMode == mode ? Color.neonTeal.opacity(0.5) : Color.clear, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("native-mode-\(mode.rawValue)")
            }

            if hasExistingSave {
                Label("A Living World save exists — starting a new match will replace it.", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(Color.alertGold)
            }
        }
        .onAppear {
            hasExistingSave = LivingWorldSession.hasSave(slot: 1, directory: LivingWorldMenuCommentary.defaultDirectory)
        }
    }
}

/// The Living World game screen: HUD + commentary + actions + event feed.
struct LivingWorldGameView: View {
    @StateObject private var session: LivingWorldSession
    @Environment(\.dismiss) private var dismiss
    @State private var hashInput = ""
    @State private var hashResult: String?
    @State private var showWarPicker = false
    @State private var showAlliancePicker = false
    @State private var showHashBridge = false

    init(playerCountryCode: String, slot: Int = 1) {
        _session = StateObject(wrappedValue: LivingWorldSession(playerCountryCode: playerCountryCode, slot: slot))
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                hud
                Divider()
                HStack(spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            commentaryCard
                            actionsCard
                            if showHashBridge {
                                HashBridgeCard(session: session)
                            }
                        }
                        .padding(14)
                    }
                    .frame(maxWidth: 380)
                    Divider()
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            worldCard
                            eventFeed
                        }
                        .padding(14)
                    }
                }
            }
            .background(Color.black)
            .accessibilityIdentifier("living-world-game")

            if let pending = session.world.pendingDecision {
                LivingWorldDecisionModalView(decision: pending) { option in
                    session.chooseDecisionOption(option)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
    }

    // MARK: HUD

    private var hud: some View {
        HStack(spacing: 14) {
            Button {
                session.togglePlay()
            } label: {
                Image(systemName: session.isRunning ? "pause.fill" : "play.fill")
                    .frame(width: 34, height: 28)
            }
            .buttonStyle(.bordered)
            .disabled(session.world.pendingDecision != nil)
            .accessibilityIdentifier("lw-play-pause")

            if session.world.pendingDecision != nil {
                Text("DECISION REQUIRED")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.softRed)
                    .cornerRadius(4)
            }

            Text(session.today.stamp)
                .font(.system(.title3, design: .monospaced).weight(.black))
                .foregroundStyle(Color.glowingCyan)

            Picker("Speed", selection: $session.speed) {
                ForEach(0 ..< LivingWorldSession.speedLevels.count, id: \.self) { index in
                    Text("⏩\(index + 1)").tag(index)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 180)

            Spacer()

            hudStat("£", String(format: "%.0fM", session.playerCountry?.treasury ?? 0))
            hudStat("SOL", String(format: "%.1f", session.playerCountry?.standardOfLiving ?? 0))
            hudStat("RAD", String(format: "%.0f%%", (session.playerCountry?.radicals ?? 0) * 100))
            hudStat("WAR", session.world.wars.isEmpty ? "peace" : "\(session.world.wars.count)")

            Button {
                session.pause()
                dismiss()
            } label: {
                Image(systemName: "xmark.circle")
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("lw-exit")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.spaceBlack)
    }

    private func hudStat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 0) {
            Text(label).font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
            Text(value).font(.system(.caption, design: .monospaced).weight(.bold)).foregroundStyle(Color.iceBlue)
        }
    }

    // MARK: Cards

    private var commentaryCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("STATE OF THE NATION", icon: "building.columns")
            Text(session.menuCommentary())
                .font(.subheadline)
                .foregroundStyle(.primary)
            Text(session.worldSituationLine())
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.spaceBlack.opacity(0.6))
        .cornerRadius(10)
    }

    private var actionsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("DIRECTIVES", icon: "slider.horizontal.3")

            if let country = session.playerCountry {
                LWSliderRow(label: "Taxes", value: country.taxLevel, range: 0.05 ... 0.6) {
                    session.setTaxLevel($0)
                }
                LWSliderRow(label: "Spending", value: country.spendingLevel, range: 0.1 ... 1) {
                    session.setSpendingLevel($0)
                }

                HStack(spacing: 8) {
                    Button(country.mobilized ? "Demobilize" : "Mobilize") {
                        session.toggleMobilization()
                    }
                    .buttonStyle(.bordered)
                    .tint(country.mobilized ? .red : .blue)
                    .accessibilityIdentifier("lw-mobilize")

                    Menu("Build") {
                        ForEach([LWBuildingType.commercialFarms, .mines, .lumberCamps, .textileMills, .steelMills, .toolingWorks, .consumerFactories, .armsIndustry, .constructionSector], id: \.self) { type in
                            Button(type.rawValue.replacingOccurrences(of: "([A-Z])", with: " $1", options: .regularExpression).capitalized) {
                                session.build(type)
                            }
                        }
                    }
                    .accessibilityIdentifier("lw-build")

                    Menu("Diplomacy") {
                        Button("Propose alliance…") { showAlliancePicker = true }
                        Button("Declare war…") { showWarPicker = true }
                        Button("LLM world hash…") { showHashBridge.toggle() }
                    }
                    .accessibilityIdentifier("lw-diplomacy")
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.spaceBlack.opacity(0.6))
        .cornerRadius(10)
        .confirmationDialog("Declare war on whom?", isPresented: $showWarPicker, titleVisibility: .visible) {
            ForEach(warTargets, id: \.self) { target in
                Button(target, role: .destructive) { session.declareWar(on: target) }
            }
        }
        .confirmationDialog("Propose alliance with whom?", isPresented: $showAlliancePicker, titleVisibility: .visible) {
            ForEach(allianceTargets, id: \.self) { target in
                Button(target) { session.proposeAlliance(with: target) }
            }
        }
    }

    private var warTargets: [String] {
        session.world.sortedCountryCodes().filter { $0 != session.playerCountryCode }
    }

    private var allianceTargets: [String] {
        session.world.sortedCountryCodes().filter { code in
            code != session.playerCountryCode &&
                !session.world.pacts.contains { $0.kind == .alliance && ($0.a == code || $0.b == code) && ($0.a == session.playerCountryCode || $0.b == session.playerCountryCode) }
        }
    }

    private var worldCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("POWERS OF THE WORLD", icon: "globe")
            ForEach(session.notableCountries, id: \.code) { country in
                let atWar = session.world.wars.contains { $0.attacker == country.code || $0.defender == country.code }
                HStack(spacing: 10) {
                    Text(country.code)
                        .font(.system(.caption, design: .monospaced).weight(.bold))
                        .foregroundStyle(country.code == session.playerCountryCode ? Color.glowingCyan : Color.iceBlue)
                        .frame(width: 42, alignment: .leading)
                    Text(country.name)
                        .font(.caption)
                        .lineLimit(1)
                    Spacer()
                    if country.isGreatPower {
                        Text("GP").font(.system(size: 8, design: .monospaced).weight(.black)).foregroundStyle(Color.alertGold)
                    }
                    if atWar {
                        Image(systemName: "flame").font(.caption2).foregroundStyle(Color.softRed)
                    }
                    Text(String(format: "SOL %.1f", country.standardOfLiving))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.spaceBlack.opacity(0.6))
        .cornerRadius(10)
    }

    private var eventFeed: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("DISPATCHES", icon: "newspaper")
            ForEach(session.recentEvents, id: \.id) { event in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(LWDate.from(dayIndex: event.day).stamp)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.secondary)
                        severityDot(event.severity)
                        if let decision = event.decisionChosen {
                            Spacer()
                            Text(decision)
                                .font(.system(size: 8, design: .monospaced).weight(.semibold))
                                .foregroundStyle(Color.neonTeal)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.neonTeal.opacity(0.15))
                                .cornerRadius(3)
                        }
                    }
                    Text(event.title).font(.caption.weight(.semibold))
                    Text(event.summary).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                .padding(.vertical, 3)
                Divider()
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.spaceBlack.opacity(0.6))
        .cornerRadius(10)
    }

    private func severityDot(_ severity: Double) -> some View {
        Circle()
            .fill(severity > 0.6 ? Color.softRed : (severity > 0.25 ? Color.alertGold : Color.neonTeal))
            .frame(width: 6, height: 6)
    }

    private func sectionHeader(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.system(.caption, design: .monospaced).weight(.bold))
            .foregroundStyle(Color.neonTeal)
    }
}

private struct LWSliderRow: View {
    let label: String
    let value: Double
    let range: ClosedRange<Double>
    let onChange: (Double) -> Void

    var body: some View {
        HStack {
            Text(label).font(.caption.weight(.semibold)).frame(width: 70, alignment: .leading)
            Slider(value: Binding(get: { value }, set: onChange), in: range)
            Text(String(format: "%.0f%%", value * 100))
                .font(.system(.caption, design: .monospaced))
                .frame(width: 42, alignment: .trailing)
        }
    }
}

/// Classic-mode hand-off: export the world prompt, paste back WORLDHASH.
struct HashBridgeCard: View {
    @ObservedObject var session: LivingWorldSession
    @State private var pastedHash = ""
    @State private var result: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("LLM WORLD BRIDGE", icon: "brain.fusion")

            Text("Copy the world prompt into any LLM (e.g. ChatGPT with Python). It replies with a WORLDHASH that this game interprets deterministically.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("Copy world prompt") {
                #if os(macOS)
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(LivingWorldHashBridge.makeWorldPrompt(for: session.world), forType: .string)
                    result = "Prompt copied to clipboard."
                #else
                    UIPasteboard.general.string = LivingWorldHashBridge.makeWorldPrompt(for: session.world)
                    result = "Prompt copied to clipboard."
                #endif
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("lw-copy-prompt")

            TextField("Paste WORLDHASH:0x… here", text: $pastedHash)
                .textFieldStyle(.roundedBorder)
                .disableAutocorrection(true)
                .accessibilityIdentifier("lw-hash-field")

            Button("Interpret hash") {
                if let interpretation = LivingWorldHashBridge.interpret(hash: pastedHash, world: session.world) {
                    session.applyHashInterpretation(interpretation)
                    result = interpretation.summary
                } else {
                    result = "Could not read that hash. Expected WORLDHASH:0x followed by 8 hex digits."
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(pastedHash.isEmpty)
            .accessibilityIdentifier("lw-interpret-hash")

            if let result {
                Text(result)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.alertGold)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.spaceBlack.opacity(0.6))
        .cornerRadius(10)
    }

    private func sectionHeader(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.system(.caption, design: .monospaced).weight(.bold))
            .foregroundStyle(Color.neonTeal)
    }
}

// MARK: - Decision Interruption Modal

struct LivingWorldDecisionModalView: View {
    let decision: LWDecisionEvent
    let onChoose: (LWDecisionOption) -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.85)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label("EXECUTIVE DECISION REQUIRED", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(.caption, design: .monospaced).weight(.bold))
                        .foregroundStyle(Color.softRed)
                    Spacer()
                    Text(LWDate.from(dayIndex: decision.day).stamp)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                if let asset = decision.imageAssetName {
                    EventImageView(imageName: asset, height: 180)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(decision.title)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Color.iceBlue)

                    Text(decision.summary)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider()

                Text("POLICY DIRECTIVES")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.neonTeal)

                VStack(spacing: 10) {
                    ForEach(decision.options) { option in
                        Button {
                            onChoose(option)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(option.text)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(Color.iceBlue)
                                    Spacer()
                                    Image(systemName: "chevron.right.circle.fill")
                                        .foregroundStyle(Color.neonTeal)
                                }
                                Text(option.consequenceSummary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                HStack(spacing: 8) {
                                    if option.treasuryDelta != 0 {
                                        effectPill(
                                            "£ \(option.treasuryDelta >= 0 ? "+" : "")\(String(format: "%.0fM", option.treasuryDelta))",
                                            positive: option.treasuryDelta > 0
                                        )
                                    }
                                    if option.stabilityDelta != 0 {
                                        effectPill(
                                            "STB \(option.stabilityDelta >= 0 ? "+" : "")\(String(format: "%.0f%%", option.stabilityDelta * 100))",
                                            positive: option.stabilityDelta > 0
                                        )
                                    }
                                    if option.radicalDelta != 0 {
                                        effectPill(
                                            "RAD \(option.radicalDelta <= 0 ? "" : "+")\(String(format: "%.0f%%", option.radicalDelta * 100))",
                                            positive: option.radicalDelta < 0
                                        )
                                    }
                                }
                            }
                            .padding(12)
                            .background(Color.spaceBlack)
                            .cornerRadius(8)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.neonTeal.opacity(0.3), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("lw-decision-\(option.id)")
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: 540)
            .background(Color.deepSlate.opacity(0.95))
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.softRed.opacity(0.6), lineWidth: 1.5))
            .shadow(color: Color.black.opacity(0.8), radius: 20, x: 0, y: 10)
            .padding(24)
        }
    }

    private func effectPill(_ text: String, positive: Bool) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundStyle(positive ? Color.neonTeal : Color.softRed)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background((positive ? Color.neonTeal : Color.softRed).opacity(0.15))
            .cornerRadius(4)
    }
}

