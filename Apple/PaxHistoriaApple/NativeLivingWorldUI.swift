import SwiftUI

// MARK: - Living World UI: War Room Atlas, Command Drawers, Telemetry & Decisions

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
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: world.wars.isEmpty ? "globe.europe.africa" : "flame.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(world.wars.isEmpty ? NativeWarRoomTheme.fieldGreen : NativeWarRoomTheme.threatRed)
                    Text(worldSituation(world).uppercased())
                        .font(NativeWarRoomTheme.labelFont(.caption, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(world.wars.isEmpty ? NativeWarRoomTheme.brass : NativeWarRoomTheme.threatRed)
                    Spacer()
                    Text("SLOT \(slot)")
                        .font(NativeWarRoomTheme.labelFont(.caption2, weight: .semibold))
                        .foregroundStyle(NativeWarRoomTheme.mutedInk)
                }

                Rectangle()
                    .fill(NativeWarRoomTheme.brass.opacity(0.2))
                    .frame(height: 1)

                VStack(alignment: .leading, spacing: 5) {
                    ForEach(notableLines(world), id: \.self) { line in
                        HStack(alignment: .top, spacing: 6) {
                            Circle()
                                .fill(NativeWarRoomTheme.brass.opacity(0.65))
                                .frame(width: 4, height: 4)
                                .padding(.top, 5)
                            Text(line)
                                .font(NativeWarRoomTheme.bodyFont(.caption, weight: .regular))
                                .foregroundStyle(NativeWarRoomTheme.mutedInk)
                                .lineLimit(2)
                        }
                    }
                }
            }
            .padding(12)
            .warRoomDossier(
                borderColor: world.wars.isEmpty ? NativeWarRoomTheme.brass.opacity(0.32) : NativeWarRoomTheme.threatRed.opacity(0.45),
                cornerRadius: 10
            )
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
            HStack {
                Label("SIMULATION MODE", systemImage: "dial.medium.fill")
                    .font(NativeWarRoomTheme.labelFont(.caption, weight: .bold))
                    .tracking(1.1)
                    .foregroundStyle(NativeWarRoomTheme.brass)
                Spacer()
                Text(selectedMode == .livingWorld ? "DAILY ENGINE" : "TURN-BASED AI")
                    .font(NativeWarRoomTheme.labelFont(.caption2, weight: .semibold))
                    .foregroundStyle(NativeWarRoomTheme.signalCyan)
            }

            ForEach(NativeSimulationMode.allCases) { mode in
                let isSelected = selectedMode == mode
                Button {
                    selectedMode = mode
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(isSelected ? NativeWarRoomTheme.brass : NativeWarRoomTheme.mutedInk)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(mode.title)
                                .font(NativeWarRoomTheme.displayFont(.subheadline, weight: .bold))
                                .foregroundStyle(NativeWarRoomTheme.ink)
                            Text(mode.subtitle)
                                .font(NativeWarRoomTheme.bodyFont(.caption, weight: .regular))
                                .foregroundStyle(NativeWarRoomTheme.mutedInk)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer()
                    }
                    .padding(11)
                    .background(
                        isSelected
                            ? NativeWarRoomTheme.olivePanel.opacity(0.95)
                            : NativeWarRoomTheme.archiveShadow.opacity(0.75)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(
                                isSelected ? NativeWarRoomTheme.brass.opacity(0.65) : NativeWarRoomTheme.brass.opacity(0.16),
                                lineWidth: isSelected ? 1.5 : 1
                            )
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("native-mode-\(mode.rawValue)")
            }

            if selectedMode == .livingWorld {
                Button {
                    onStartLivingWorld()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "play.fill")
                        Text("LAUNCH LIVING WORLD")
                            .font(NativeWarRoomTheme.labelFont(.caption, weight: .bold))
                            .tracking(0.8)
                    }
                    .frame(maxWidth: .infinity, minHeight: 34)
                }
                .buttonStyle(.borderedProminent)
                .tint(NativeWarRoomTheme.brass.opacity(0.85))
                .foregroundStyle(NativeWarRoomTheme.blackboard)
            }

            if hasExistingSave {
                Label("A Living World save exists — starting a new match will replace it.", systemImage: "exclamationmark.triangle.fill")
                    .font(NativeWarRoomTheme.bodyFont(.caption, weight: .medium))
                    .foregroundStyle(NativeWarRoomTheme.alertAmber)
            }
        }
        .padding(14)
        .warRoomDossier(borderColor: NativeWarRoomTheme.brass.opacity(0.24), cornerRadius: 10)
        .onAppear {
            hasExistingSave = LivingWorldSession.hasSave(slot: 1, directory: LivingWorldMenuCommentary.defaultDirectory)
        }
    }
}

// MARK: - ISO <-> Living World Code Bridge

private enum LWMapCodeBridge {
    private static let lwToISO: [String: String] = [
        "JAP": "JPN",
        "CHI": "CHN"
    ]

    private static let isoToLW: [String: String] = [
        "JPN": "JAP",
        "CHN": "CHI",
        "PSX": "PSE",
        "KOS": "XXK"
    ]

    static func toISO(_ lwCode: String) -> String {
        let upper = lwCode.uppercased()
        if let mapped = lwToISO[upper] {
            return mapped
        }
        return GeopoliticalMapData.canonicalCountryCode(upper)
    }

    static func flagAlpha3(for lwCode: String) -> String {
        switch lwCode.uppercased() {
        case "JAP": "JPN"
        case "CHI": "CHN"
        case "PSX": "PSE"
        case "KOS": "XXK"
        default: lwCode.uppercased()
        }
    }

    static func toLWCode(_ isoCode: String, in world: LivingWorldState) -> String? {
        let upper = isoCode.uppercased()
        if world.countries[upper] != nil {
            return upper
        }
        if let mapped = isoToLW[upper], world.countries[mapped] != nil {
            return mapped
        }
        let canonical = GeopoliticalMapData.canonicalCountryCode(upper)
        if world.countries[canonical] != nil {
            return canonical
        }
        if let mappedCanonical = isoToLW[canonical], world.countries[mappedCanonical] != nil {
            return mappedCanonical
        }
        return nil
    }
}

// MARK: - Map Lenses & Command Drawer Tabs

private enum LWMapLens: String, CaseIterable, Identifiable {
    case diplomacy
    case livingStandard
    case warsAndFronts
    case industryAndGDP

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .diplomacy: "Diplomacy"
        case .livingStandard: "SOL"
        case .warsAndFronts: "Wars"
        case .industryAndGDP: "Industry"
        }
    }

    var systemImage: String {
        switch self {
        case .diplomacy: "handshake.fill"
        case .livingStandard: "heart.text.square.fill"
        case .warsAndFronts: "flame.fill"
        case .industryAndGDP: "gearshape.2.fill"
        }
    }
}

private enum LWCommandTab: String, CaseIterable, Identifiable {
    case cabinet
    case market
    case powers
    case chronicle

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .cabinet: "Cabinet"
        case .market: "Market"
        case .powers: "Powers"
        case .chronicle: "Chronicle"
        }
    }

    var systemImage: String {
        switch self {
        case .cabinet: "building.columns.fill"
        case .market: "chart.line.uptrend.xyaxis"
        case .powers: "globe.europe.africa.fill"
        case .chronicle: "newspaper.fill"
        }
    }
}

// MARK: - Atlas Geometry Cache

private enum LWAtlasGeometryCache {
    static let capitalByISO: [String: PopulatedPlace] = {
        var result: [String: PopulatedPlace] = [:]
        for city in GeopoliticalMapData.cities {
            let iso = GeopoliticalMapData.canonicalCountryCode(city.countryCode)
            if let existing = result[iso] {
                if city.isCapital, !existing.isCapital {
                    result[iso] = city
                } else if city.isCapital == existing.isCapital, city.population > existing.population {
                    result[iso] = city
                }
            } else {
                result[iso] = city
            }
        }
        return result
    }()

    static let centerByISO: [String: CGPoint] = {
        var result: [String: CGPoint] = [:]
        for (iso, regions) in GeopoliticalMapData.regionsByCountry {
            let canonical = GeopoliticalMapData.canonicalCountryCode(iso)
            if let cap = capitalByISO[canonical] {
                result[canonical] = cap.coordinate
            } else if let largest = regions.max(by: {
                ($0.path.boundingRect.width * $0.path.boundingRect.height) < ($1.path.boundingRect.width * $1.path.boundingRect.height)
            }) {
                result[canonical] = largest.center
            }
        }
        for (iso, city) in capitalByISO where result[iso] == nil {
            result[iso] = city.coordinate
        }
        return result
    }()

    static func mapCenter(forLWCode lwCode: String) -> CGPoint? {
        let iso = LWMapCodeBridge.toISO(lwCode)
        return centerByISO[iso] ?? capitalByISO[iso]?.coordinate
    }

    static func hasMapGeometry(forLWCode lwCode: String) -> Bool {
        let iso = LWMapCodeBridge.toISO(lwCode)
        return !GeopoliticalMapData.regions(forCountryCode: iso).isEmpty
    }
}

// MARK: - Main Living World War Room Screen

/// The Living World game screen: Grand Strategy Masthead + Interactive Living Atlas Map
/// + Country Dossier Overlay + Collapsible Command Drawer.
struct LivingWorldGameView: View {
    @StateObject private var session: LivingWorldSession
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let onExit: (() -> Void)?

    @State private var showWarPicker = false
    @State private var showAlliancePicker = false
    @State private var showHashBridge = false
    @State private var activeTab: LWCommandTab = .cabinet
    @State private var activeLens: LWMapLens = .diplomacy
    @State private var selectedCountryCode: String?
    @State private var isDrawerCollapsed = false
    @State private var alertPulse = false

    init(playerCountryCode: String, slot: Int = 1, onExit: (() -> Void)? = nil) {
        _session = StateObject(wrappedValue: LivingWorldSession(playerCountryCode: playerCountryCode, slot: slot))
        self.onExit = onExit
    }

    var body: some View {
        ZStack {
            NativeWarRoomTheme.blackboard
                .ignoresSafeArea()

            VStack(spacing: 0) {
                hud

                Rectangle()
                    .fill(NativeWarRoomTheme.brass.opacity(0.32))
                    .frame(height: 1)

                GeometryReader { geo in
                    let isWide = geo.size.width >= 900
                    if isWide {
                        HStack(spacing: 0) {
                            mapWorkspace(isWide: true)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)

                            if !isDrawerCollapsed {
                                Rectangle()
                                    .fill(NativeWarRoomTheme.brass.opacity(0.26))
                                    .frame(width: 1)

                                commandDrawer(isWide: true)
                                    .frame(width: min(430, max(360, geo.size.width * 0.34)))
                                    .transition(.move(edge: .trailing).combined(with: .opacity))
                            }
                        }
                    } else {
                        VStack(spacing: 0) {
                            mapWorkspace(isWide: false)
                                .frame(height: max(250, geo.size.height * 0.46))

                            Rectangle()
                                .fill(NativeWarRoomTheme.brass.opacity(0.28))
                                .frame(height: 1)

                            commandDrawer(isWide: false)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                }
            }
            .accessibilityIdentifier("living-world-game")

            if let pending = session.world.pendingDecision {
                LivingWorldDecisionModalView(decision: pending, language: session.world.language) { option in
                    session.chooseDecisionOption(option)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                alertPulse = true
            }
        }
    }

    // MARK: Map Workspace + Country Dossier Overlay

    private func mapWorkspace(isWide: Bool) -> some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                LivingWorldAtlasMap(
                    world: session.world,
                    playerCountryCode: session.playerCountryCode,
                    activeLens: $activeLens,
                    selectedCountryCode: $selectedCountryCode,
                    isDrawerCollapsed: isWide ? $isDrawerCollapsed : nil
                )

                if !emergentPolities.isEmpty {
                    emergentPolitiesStrip
                }
            }

            if let code = selectedCountryCode,
               let inspected = session.world.countries[code]
            {
                if isWide {
                    LWCountryDossierCard(
                        country: inspected,
                        world: session.world,
                        playerCountryCode: session.playerCountryCode,
                        onClose: { selectedCountryCode = nil },
                        onDeclareWar: { session.declareWar(on: inspected.code) },
                        onProposeAlliance: { session.proposeAlliance(with: inspected.code) }
                    )
                    .frame(maxWidth: 380, maxHeight: 490)
                    .padding(14)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .topLeading)))
                } else {
                    ZStack {
                        Color.black.opacity(0.55)
                            .ignoresSafeArea()
                            .onTapGesture {
                                selectedCountryCode = nil
                            }
                        LWCountryDossierCard(
                            country: inspected,
                            world: session.world,
                            playerCountryCode: session.playerCountryCode,
                            onClose: { selectedCountryCode = nil },
                            onDeclareWar: { session.declareWar(on: inspected.code) },
                            onProposeAlliance: { session.proposeAlliance(with: inspected.code) }
                        )
                        .padding(12)
                    }
                    .transition(.opacity)
                }
            }
        }
    }

    private var emergentPolities: [LWCountry] {
        session.world.countries.values
            .filter { !LWAtlasGeometryCache.hasMapGeometry(forLWCode: $0.code) }
            .sorted { lhs, rhs in
                if lhs.code == session.playerCountryCode {
                    return true
                }
                if rhs.code == session.playerCountryCode {
                    return false
                }
                if lhs.gdpEstimate != rhs.gdpEstimate {
                    return lhs.gdpEstimate > rhs.gdpEstimate
                }
                return lhs.code < rhs.code
            }
    }

    private var emergentPolitiesStrip: some View {
        HStack(spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(NativeWarRoomTheme.brass)
                Text("EMERGENT POLITIES")
                    .font(NativeWarRoomTheme.labelFont(.caption2, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(NativeWarRoomTheme.brass)
            }
            .padding(.leading, 10)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(emergentPolities, id: \.code) { polity in
                        let isSelected = selectedCountryCode == polity.code
                        let atWar = session.world.wars.contains { $0.attacker == polity.code || $0.defender == polity.code }
                        Button {
                            selectedCountryCode = (selectedCountryCode == polity.code) ? nil : polity.code
                        } label: {
                            HStack(spacing: 5) {
                                Text(polity.code)
                                    .font(NativeWarRoomTheme.labelFont(.caption2, weight: .black))
                                    .foregroundStyle(isSelected ? NativeWarRoomTheme.blackboard : NativeWarRoomTheme.brass)
                                Text(polity.name)
                                    .font(NativeWarRoomTheme.bodyFont(.caption2, weight: .semibold))
                                    .foregroundStyle(isSelected ? NativeWarRoomTheme.blackboard : NativeWarRoomTheme.ink)
                                    .lineLimit(1)
                                if atWar {
                                    Image(systemName: "flame.fill")
                                        .font(.system(size: 9))
                                        .foregroundStyle(isSelected ? NativeWarRoomTheme.blackboard : NativeWarRoomTheme.threatRed)
                                }
                                Text(String(format: "%.1f", polity.standardOfLiving))
                                    .font(NativeWarRoomTheme.labelFont(.caption2, weight: .bold))
                                    .foregroundStyle(
                                        isSelected
                                            ? NativeWarRoomTheme.blackboard.opacity(0.85)
                                            : NativeWarRoomTheme.mutedInk
                                    )
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                isSelected
                                    ? NativeWarRoomTheme.brass
                                    : NativeWarRoomTheme.graphite.opacity(0.9)
                            )
                            .clipShape(Capsule())
                            .overlay {
                                Capsule()
                                    .stroke(
                                        atWar
                                            ? NativeWarRoomTheme.threatRed.opacity(0.75)
                                            : NativeWarRoomTheme.brass.opacity(isSelected ? 0.9 : 0.25),
                                        lineWidth: 1
                                    )
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 6)
                .padding(.trailing, 10)
            }
        }
        .background(NativeWarRoomTheme.archiveShadow)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(NativeWarRoomTheme.brass.opacity(0.24))
                .frame(height: 1)
        }
    }

    // MARK: Grand-Strategy Top Masthead (HUD)

    private var hud: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                if let player = session.playerCountry {
                    HStack(spacing: 9) {
                        NativeCountryStandard(
                            countryCode: LWMapCodeBridge.flagAlpha3(for: player.code),
                            size: 32
                        )
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 6) {
                                Text(player.name.uppercased())
                                    .font(NativeWarRoomTheme.displayFont(.subheadline, weight: .bold))
                                    .tracking(0.8)
                                    .foregroundStyle(NativeWarRoomTheme.ink)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.75)
                                if player.isGreatPower {
                                    Text("GP")
                                        .font(NativeWarRoomTheme.labelFont(.caption2, weight: .black))
                                        .foregroundStyle(NativeWarRoomTheme.blackboard)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1)
                                        .background(NativeWarRoomTheme.brass, in: RoundedRectangle(cornerRadius: 3))
                                }
                            }
                            Text("\(session.today.stamp)  ·  \(strategyTitle(player.strategy).uppercased())")
                                .font(NativeWarRoomTheme.labelFont(.caption2, weight: .semibold))
                                .foregroundStyle(NativeWarRoomTheme.brass)
                                .lineLimit(1)
                        }
                    }
                }

                // Paradox-style time controls
                HStack(spacing: 6) {
                    Button {
                        session.togglePlay()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: session.isRunning ? "pause.fill" : "play.fill")
                                .font(.caption.weight(.bold))
                            Text(session.isRunning ? "LIVE" : "PAUSED")
                                .font(NativeWarRoomTheme.labelFont(.caption2, weight: .bold))
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .background(
                            session.isRunning
                                ? NativeWarRoomTheme.fieldGreen.opacity(0.28)
                                : NativeWarRoomTheme.olivePanel
                        )
                        .foregroundStyle(
                            session.isRunning
                                ? NativeWarRoomTheme.fieldGreen
                                : NativeWarRoomTheme.brass
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(
                                    (session.isRunning ? NativeWarRoomTheme.fieldGreen : NativeWarRoomTheme.brass).opacity(0.55),
                                    lineWidth: 1
                                )
                        }
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.space, modifiers: [])
                    .disabled(session.world.pendingDecision != nil)
                    .accessibilityIdentifier("lw-play-pause")

                    Button {
                        session.stepDay()
                    } label: {
                        Image(systemName: "forward.frame.fill")
                            .font(.caption.weight(.bold))
                            .frame(width: 28, height: 28)
                            .background(NativeWarRoomTheme.olivePanel)
                            .foregroundStyle(NativeWarRoomTheme.ink)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .stroke(NativeWarRoomTheme.brass.opacity(0.28), lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                    .disabled(session.isRunning || session.world.pendingDecision != nil)
                    .help("Advance 1 Day")

                    // 5-speed pip selector
                    HStack(spacing: 2) {
                        ForEach(0 ..< LivingWorldSession.speedLevels.count, id: \.self) { index in
                            let isSelected = session.speed == index
                            let isLit = index <= session.speed
                            Button {
                                session.speed = index
                            } label: {
                                VStack(spacing: 1) {
                                    Text("\(index + 1)×")
                                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                                        .foregroundStyle(isSelected ? NativeWarRoomTheme.blackboard : (isLit ? NativeWarRoomTheme.brass : NativeWarRoomTheme.mutedInk))
                                }
                                .frame(width: 24, height: 26)
                                .background(
                                    isSelected
                                        ? NativeWarRoomTheme.brass
                                        : (isLit ? NativeWarRoomTheme.brass.opacity(0.18) : NativeWarRoomTheme.graphite)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(2)
                    .background(NativeWarRoomTheme.blackboard.opacity(0.85))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(NativeWarRoomTheme.brass.opacity(0.24), lineWidth: 1)
                    }
                }

                if session.world.pendingDecision != nil {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(NativeWarRoomTheme.threatRed)
                            .frame(width: 6, height: 6)
                            .opacity(alertPulse ? 0.35 : 1.0)
                        Text(LWProse.string(.uiDecisionRequiredBadge, language: session.world.language))
                            .font(NativeWarRoomTheme.labelFont(.caption2, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(NativeWarRoomTheme.threatRed.opacity(0.88))
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                }

                Spacer(minLength: 8)

                // KPI Telemetry Strip (scrolls horizontally if window is narrow)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        if let player = session.playerCountry {
                            let balance = dailyFiscalBalance(for: player)
                            hudStat(
                                "£",
                                String(format: "%.0fM", player.treasury),
                                subtitle: String(format: "%+.1f/d", balance),
                                tint: balance >= 0 ? NativeWarRoomTheme.fieldGreen : NativeWarRoomTheme.threatRed
                            )
                            hudStat(
                                "SOL",
                                String(format: "%.1f", player.standardOfLiving),
                                tint: solColor(player.standardOfLiving)
                            )
                            hudStat(
                                "LEG",
                                String(format: "%.0f%%", player.government.legitimacy),
                                tint: NativeWarRoomTheme.statusColor(for: Int(player.government.legitimacy))
                            )
                            hudStat(
                                "RAD",
                                String(format: "%.0f%%", player.radicals * 100),
                                tint: player.radicals > 0.2 ? NativeWarRoomTheme.threatRed : (player.radicals > 0.1 ? NativeWarRoomTheme.alertAmber : NativeWarRoomTheme.fieldGreen)
                            )
                            hudStat(
                                "MIL",
                                String(format: "%.0f", player.armyPower),
                                subtitle: player.mobilized ? "MOB" : nil,
                                tint: player.mobilized ? NativeWarRoomTheme.alertAmber : NativeWarRoomTheme.ink
                            )
                            hudStat(
                                "INF",
                                String(format: "%.0f", player.infamy),
                                tint: player.infamy > 40 ? NativeWarRoomTheme.threatRed : (player.infamy > 15 ? NativeWarRoomTheme.alertAmber : NativeWarRoomTheme.mutedInk)
                            )
                            hudStat(
                                "WAR",
                                session.world.wars.isEmpty ? "PEACE" : "\(session.world.wars.count)",
                                tint: session.world.wars.isEmpty ? NativeWarRoomTheme.fieldGreen : NativeWarRoomTheme.threatRed
                            )
                        }
                    }
                }
                .frame(maxWidth: 460)

                Button {
                    session.pause()
                    session.persistNow()
                    onExit?()
                    NotificationCenter.default.post(name: Notification.Name("LivingWorldDidRequestExit"), object: nil)
                    dismiss()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark")
                            .font(.caption.weight(.bold))
                    }
                    .frame(width: 28, height: 28)
                    .background(NativeWarRoomTheme.olivePanel)
                    .foregroundStyle(NativeWarRoomTheme.ink)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(NativeWarRoomTheme.brass.opacity(0.32), lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Exit Living World")
                .accessibilityIdentifier("lw-exit")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
        }
        .background(
            LinearGradient(
                colors: [NativeWarRoomTheme.archiveShadow, NativeWarRoomTheme.graphite],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private func hudStat(_ label: String, _ value: String, subtitle: String? = nil, tint: Color = NativeWarRoomTheme.ink) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(NativeWarRoomTheme.mutedInk)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(.caption, design: .monospaced).weight(.bold))
                    .foregroundStyle(tint)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(tint.opacity(0.82))
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(NativeWarRoomTheme.blackboard.opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .stroke(NativeWarRoomTheme.brass.opacity(0.16), lineWidth: 1)
        }
    }

    // MARK: Command Drawer

    private func commandDrawer(isWide: Bool) -> some View {
        VStack(spacing: 0) {
            // Drawer tab strip
            HStack(spacing: 4) {
                ForEach(LWCommandTab.allCases) { tab in
                    let isSelected = activeTab == tab
                    Button {
                        withAnimation(.easeOut(duration: 0.16)) {
                            activeTab = tab
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: tab.systemImage)
                                .font(.caption2.weight(.bold))
                            Text(tab.title.uppercased())
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(isSelected ? NativeWarRoomTheme.olivePanel : Color.clear)
                        .foregroundStyle(isSelected ? NativeWarRoomTheme.brass : NativeWarRoomTheme.mutedInk)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .stroke(NativeWarRoomTheme.brass.opacity(0.42), lineWidth: 1)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }

                if isWide {
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) {
                            isDrawerCollapsed = true
                        }
                    } label: {
                        Image(systemName: "sidebar.right")
                            .font(.caption.weight(.bold))
                            .frame(width: 28, height: 28)
                            .foregroundStyle(NativeWarRoomTheme.mutedInk)
                    }
                    .buttonStyle(.plain)
                    .help("Collapse Command Drawer")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(NativeWarRoomTheme.archiveShadow)

            Rectangle()
                .fill(NativeWarRoomTheme.brass.opacity(0.2))
                .frame(height: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    switch activeTab {
                    case .cabinet:
                        commentaryCard
                        actionsCard
                        if showHashBridge {
                            HashBridgeCard(session: session)
                        }
                        industryBuildingsCard
                    case .market:
                        worldMarketLedgerCard
                    case .powers:
                        activeWarsCard
                        powersLeaderboardCard
                    case .chronicle:
                        eventFeed
                        if showHashBridge {
                            HashBridgeCard(session: session)
                        }
                        Button {
                            showHashBridge.toggle()
                        } label: {
                            Label(
                                showHashBridge ? "Hide LLM Hash Bridge" : "Open LLM Hash Bridge",
                                systemImage: "cpu"
                            )
                            .font(NativeWarRoomTheme.labelFont(.caption, weight: .bold))
                            .frame(maxWidth: .infinity, minHeight: 34)
                        }
                        .buttonStyle(.bordered)
                        .tint(NativeWarRoomTheme.brass)
                    }
                }
                .padding(14)
            }
            .background(NativeWarRoomTheme.blackboard.opacity(0.95))
        }
    }

    // MARK: Cabinet Cards

    private var commentaryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionHeader("STATE OF THE NATION", icon: "building.columns")
                Spacer()
                if let player = session.playerCountry {
                    Text(String(format: "%.1fM POPS", player.pops.total))
                        .font(NativeWarRoomTheme.labelFont(.caption2, weight: .bold))
                        .foregroundStyle(NativeWarRoomTheme.mutedInk)
                }
            }
            Text(session.menuCommentary())
                .font(NativeWarRoomTheme.bodyFont(.subheadline, weight: .medium))
                .foregroundStyle(NativeWarRoomTheme.ink)
                .fixedSize(horizontal: false, vertical: true)

            Rectangle()
                .fill(NativeWarRoomTheme.brass.opacity(0.16))
                .frame(height: 1)

            Text(session.worldSituationLine())
                .font(NativeWarRoomTheme.labelFont(.caption2, weight: .semibold))
                .foregroundStyle(NativeWarRoomTheme.mutedInk)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .warRoomDossier(borderColor: NativeWarRoomTheme.brass.opacity(0.28), cornerRadius: 10)
    }

    private var actionsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("CABINET DIRECTIVES", icon: "slider.horizontal.3")

            if let country = session.playerCountry {
                let dailyBalance = dailyFiscalBalance(for: country)
                let solTarget = estimatedSOLTarget(for: country)
                let solDelta = solTarget - country.standardOfLiving

                VStack(alignment: .leading, spacing: 8) {
                    LWSliderRow(label: "Taxes", value: country.taxLevel, range: 0.05 ... 0.6) {
                        session.setTaxLevel($0)
                    }
                    LWSliderRow(label: "Spending", value: country.spendingLevel, range: 0.1 ... 1) {
                        session.setSpendingLevel($0)
                    }

                    HStack(spacing: 8) {
                        telemetryChip(
                            title: "DAILY NET",
                            value: String(format: "%+.2fM £", dailyBalance),
                            color: dailyBalance >= 0 ? NativeWarRoomTheme.fieldGreen : NativeWarRoomTheme.threatRed
                        )
                        telemetryChip(
                            title: "SOL DRIFT",
                            value: String(format: "%+.1f → %.1f", solDelta, solTarget),
                            color: solDelta >= 0 ? NativeWarRoomTheme.fieldGreen : NativeWarRoomTheme.alertAmber
                        )
                        telemetryChip(
                            title: "UNREST",
                            value: String(format: "%.0f%%", country.radicals * 100),
                            color: country.radicals > 0.2 ? NativeWarRoomTheme.threatRed : NativeWarRoomTheme.mutedInk
                        )
                    }
                }

                Rectangle()
                    .fill(NativeWarRoomTheme.brass.opacity(0.16))
                    .frame(height: 1)

                HStack(spacing: 8) {
                    Button {
                        session.toggleMobilization()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: country.mobilized ? "shield.slash.fill" : "shield.lefthalf.filled")
                            Text(country.mobilized ? "Demobilize" : "Mobilize")
                                .font(NativeWarRoomTheme.labelFont(.caption, weight: .bold))
                        }
                        .frame(maxWidth: .infinity, minHeight: 32)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(country.mobilized ? NativeWarRoomTheme.threatRed : NativeWarRoomTheme.olivePanel)
                    .foregroundStyle(country.mobilized ? .white : NativeWarRoomTheme.ink)
                    .accessibilityIdentifier("lw-mobilize")

                    Menu {
                        ForEach(
                            [LWBuildingType.commercialFarms, .mines, .lumberCamps, .textileMills, .steelMills, .toolingWorks, .consumerFactories, .armsIndustry, .constructionSector],
                            id: \.self
                        ) { type in
                            Button("\(buildingTitle(type)) (−8M £)") {
                                session.build(type)
                            }
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "hammer.fill")
                            Text("Build")
                                .font(NativeWarRoomTheme.labelFont(.caption, weight: .bold))
                        }
                        .frame(maxWidth: .infinity, minHeight: 32)
                    }
                    .buttonStyle(.bordered)
                    .tint(NativeWarRoomTheme.brass)
                    .accessibilityIdentifier("lw-build")

                    Menu {
                        Button("Propose alliance…") { showAlliancePicker = true }
                        Button("Declare war…") { showWarPicker = true }
                        Button("LLM world hash…") { showHashBridge.toggle() }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "envelope.badge.shield.half.filled")
                            Text("Diplomacy")
                                .font(NativeWarRoomTheme.labelFont(.caption, weight: .bold))
                        }
                        .frame(maxWidth: .infinity, minHeight: 32)
                    }
                    .buttonStyle(.bordered)
                    .tint(NativeWarRoomTheme.signalCyan)
                    .accessibilityIdentifier("lw-diplomacy")
                }
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassmorphicCard(borderColor: NativeWarRoomTheme.brass.opacity(0.24), cornerRadius: 10)
        .confirmationDialog("Declare war on whom?", isPresented: $showWarPicker, titleVisibility: .visible) {
            ForEach(warTargets, id: \.self) { target in
                let name = session.world.countries[target]?.name ?? target
                Button("\(name) (\(target))", role: .destructive) { session.declareWar(on: target) }
            }
        }
        .confirmationDialog("Propose alliance with whom?", isPresented: $showAlliancePicker, titleVisibility: .visible) {
            ForEach(allianceTargets, id: \.self) { target in
                let name = session.world.countries[target]?.name ?? target
                Button("\(name) (\(target))") { session.proposeAlliance(with: target) }
            }
        }
    }

    private var industryBuildingsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionHeader("INDUSTRIAL SECTORS", icon: "building.2.fill")
                Spacer()
                if let player = session.playerCountry {
                    Text(String(format: "INFRA %.0f%%", player.infrastructure))
                        .font(NativeWarRoomTheme.labelFont(.caption2, weight: .bold))
                        .foregroundStyle(NativeWarRoomTheme.signalCyan)
                }
            }

            if let player = session.playerCountry {
                let sortedBuildings = player.buildings.sorted { $0.levels > $1.levels }
                ForEach(sortedBuildings, id: \.type) { building in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: buildingIcon(building.type))
                                .font(.caption.weight(.bold))
                                .foregroundStyle(NativeWarRoomTheme.brass)
                                .frame(width: 18)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(buildingTitle(building.type))
                                    .font(NativeWarRoomTheme.bodyFont(.caption, weight: .bold))
                                    .foregroundStyle(NativeWarRoomTheme.ink)
                                Text(buildingChainSummary(building.type))
                                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                                    .foregroundStyle(NativeWarRoomTheme.mutedInk)
                            }

                            Spacer()

                            Text("LVL \(building.levels)")
                                .font(NativeWarRoomTheme.labelFont(.caption2, weight: .black))
                                .foregroundStyle(NativeWarRoomTheme.brass)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(NativeWarRoomTheme.brass.opacity(0.14), in: RoundedRectangle(cornerRadius: 4))

                            Text(String(format: "%+.1f", building.lastProfit))
                                .font(NativeWarRoomTheme.labelFont(.caption2, weight: .bold))
                                .foregroundStyle(building.lastProfit >= 0 ? NativeWarRoomTheme.fieldGreen : NativeWarRoomTheme.threatRed)
                                .frame(width: 44, alignment: .trailing)

                            Button {
                                session.build(building.type)
                            } label: {
                                Image(systemName: "plus")
                                    .font(.system(size: 10, weight: .black))
                                    .frame(width: 22, height: 22)
                                    .background(NativeWarRoomTheme.olivePanel)
                                    .foregroundStyle(NativeWarRoomTheme.brass)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 4)
                                            .stroke(NativeWarRoomTheme.brass.opacity(0.4), lineWidth: 1)
                                    }
                            }
                            .buttonStyle(.plain)
                            .help("Expand \(buildingTitle(building.type)) (−8M £)")
                        }

                        // Staffing progress bar
                        GeometryReader { barGeo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(NativeWarRoomTheme.blackboard)
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(building.staffing >= 0.7 ? NativeWarRoomTheme.fieldGreen : NativeWarRoomTheme.alertAmber)
                                    .frame(width: max(4, barGeo.size.width * min(1, max(0, building.staffing))))
                            }
                        }
                        .frame(height: 4)
                    }
                    .padding(9)
                    .background(NativeWarRoomTheme.archiveShadow.opacity(0.85))
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(NativeWarRoomTheme.brass.opacity(0.16), lineWidth: 1)
                    }
                }
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassmorphicCard(borderColor: NativeWarRoomTheme.brass.opacity(0.22), cornerRadius: 10)
    }

    // MARK: World Market Ledger Card

    private var worldMarketLedgerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionHeader("WORLD GOODS MARKET", icon: "chart.bar.xaxis")
                Spacer()
                Text("±75% BANDS")
                    .font(NativeWarRoomTheme.labelFont(.caption2, weight: .semibold))
                    .foregroundStyle(NativeWarRoomTheme.mutedInk)
            }

            ForEach(session.world.goods, id: \.id) { good in
                let livePrice = session.world.market.price(for: good.id)
                let basePrice = good.basePrice
                let ratio = (livePrice - basePrice) / max(0.01, basePrice) // -0.75 ... +0.75
                let supply = session.world.market.supply[good.id] ?? 0
                let demand = session.world.market.demand[good.id] ?? 0
                let balance = supply - demand
                let isExpensive = ratio > 0.08
                let isCheap = ratio < -0.08
                let priceTint = isExpensive ? NativeWarRoomTheme.threatRed : (isCheap ? NativeWarRoomTheme.fieldGreen : NativeWarRoomTheme.brass)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: goodIcon(good.category))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(NativeWarRoomTheme.brass)
                            .frame(width: 18)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(goodDisplayName(good.id))
                                .font(NativeWarRoomTheme.bodyFont(.caption, weight: .bold))
                                .foregroundStyle(NativeWarRoomTheme.ink)
                            Text("BASE £\(String(format: "%.0f", basePrice))  ·  SUP \(String(format: "%.0f", supply)) / DEM \(String(format: "%.0f", demand))")
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundStyle(NativeWarRoomTheme.mutedInk)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 1) {
                            Text("£\(String(format: "%.1f", livePrice))")
                                .font(NativeWarRoomTheme.labelFont(.caption, weight: .black))
                                .foregroundStyle(NativeWarRoomTheme.ink)
                            Text(String(format: "%+.0f%%", ratio * 100))
                                .font(.system(size: 9, weight: .black, design: .monospaced))
                                .foregroundStyle(priceTint)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(priceTint.opacity(0.16), in: RoundedRectangle(cornerRadius: 3))
                        }
                    }

                    // Price discovery -75% .. Base .. +75% gauge
                    GeometryReader { gaugeGeo in
                        let normalized = min(1, max(0, (ratio + 0.75) / 1.5))
                        let markerX = gaugeGeo.size.width * normalized
                        let midX = gaugeGeo.size.width * 0.5
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(NativeWarRoomTheme.blackboard)

                            // Fill from center base line to marker
                            let fillStart = min(midX, markerX)
                            let fillWidth = abs(markerX - midX)
                            Rectangle()
                                .fill(priceTint.opacity(0.65))
                                .frame(width: max(2, fillWidth), height: 6)
                                .offset(x: fillStart)

                            // Base price center tick
                            Rectangle()
                                .fill(NativeWarRoomTheme.parchment.opacity(0.55))
                                .frame(width: 1.5, height: 10)
                                .offset(x: midX - 0.75)

                            // Live price diamond/pip
                            Circle()
                                .fill(priceTint)
                                .frame(width: 8, height: 8)
                                .offset(x: max(0, min(gaugeGeo.size.width - 8, markerX - 4)))
                        }
                    }
                    .frame(height: 10)

                    HStack {
                        Text(balance >= 0 ? "Surplus" : "Shortage")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(balance >= 0 ? NativeWarRoomTheme.fieldGreen : NativeWarRoomTheme.alertAmber)
                        Spacer()
                        Text(String(format: "%+.0f units", balance))
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(NativeWarRoomTheme.mutedInk)
                    }
                }
                .padding(10)
                .background(NativeWarRoomTheme.archiveShadow.opacity(0.88))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(NativeWarRoomTheme.brass.opacity(0.16), lineWidth: 1)
                }
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassmorphicCard(borderColor: NativeWarRoomTheme.brass.opacity(0.24), cornerRadius: 10)
    }

    // MARK: Powers & Active Wars Cards

    private var activeWarsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionHeader("ACTIVE THEATERS & FRONTS", icon: "flame.fill")
                Spacer()
                Text("\(session.world.wars.count) ACTIVE")
                    .font(NativeWarRoomTheme.labelFont(.caption2, weight: .bold))
                    .foregroundStyle(session.world.wars.isEmpty ? NativeWarRoomTheme.fieldGreen : NativeWarRoomTheme.threatRed)
            }

            if session.world.wars.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "dove")
                        .foregroundStyle(NativeWarRoomTheme.fieldGreen)
                    Text("The Concert of Powers holds — no active wars across the globe.")
                        .font(NativeWarRoomTheme.bodyFont(.caption, weight: .regular))
                        .foregroundStyle(NativeWarRoomTheme.mutedInk)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(NativeWarRoomTheme.archiveShadow.opacity(0.7))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                ForEach(session.world.wars, id: \.id) { war in
                    let attackerName = session.world.countries[war.attacker]?.name ?? war.attacker
                    let defenderName = session.world.countries[war.defender]?.name ?? war.defender
                    let frontProgress = war.fronts.first?.progress ?? 0

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Button {
                                selectedCountryCode = war.attacker
                            } label: {
                                HStack(spacing: 4) {
                                    NativeCountryStandard(countryCode: LWMapCodeBridge.flagAlpha3(for: war.attacker), size: 18)
                                    Text(attackerName)
                                        .font(NativeWarRoomTheme.bodyFont(.caption, weight: .bold))
                                        .foregroundStyle(NativeWarRoomTheme.ink)
                                        .lineLimit(1)
                                }
                            }
                            .buttonStyle(.plain)

                            Text("VS")
                                .font(NativeWarRoomTheme.labelFont(.caption2, weight: .black))
                                .foregroundStyle(NativeWarRoomTheme.threatRed)

                            Button {
                                selectedCountryCode = war.defender
                            } label: {
                                HStack(spacing: 4) {
                                    Text(defenderName)
                                        .font(NativeWarRoomTheme.bodyFont(.caption, weight: .bold))
                                        .foregroundStyle(NativeWarRoomTheme.ink)
                                        .lineLimit(1)
                                    NativeCountryStandard(countryCode: LWMapCodeBridge.flagAlpha3(for: war.defender), size: 18)
                                }
                            }
                            .buttonStyle(.plain)

                            Spacer()
                        }

                        Text(war.warGoal)
                            .font(.system(size: 10, weight: .medium, design: .serif))
                            .foregroundStyle(NativeWarRoomTheme.mutedInk)

                        // Tug-of-war progress bar (-100..+100)
                        VStack(spacing: 3) {
                            GeometryReader { barGeo in
                                let pct = min(1, max(0, (frontProgress + 100) / 200))
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(NativeWarRoomTheme.signalCyan.opacity(0.35))
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(NativeWarRoomTheme.threatRed.opacity(0.8))
                                        .frame(width: max(4, barGeo.size.width * pct))
                                    Rectangle()
                                        .fill(NativeWarRoomTheme.parchment)
                                        .frame(width: 2)
                                        .offset(x: barGeo.size.width * 0.5 - 1)
                                }
                            }
                            .frame(height: 8)

                            HStack {
                                Text("ATK EXH \(String(format: "%.0f%%", war.exhaustionAttacker))")
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundStyle(NativeWarRoomTheme.threatRed)
                                Spacer()
                                Text(String(format: "FRONT %+.0f", frontProgress))
                                    .font(.system(size: 9, weight: .black, design: .monospaced))
                                    .foregroundStyle(NativeWarRoomTheme.brass)
                                Spacer()
                                Text("DEF EXH \(String(format: "%.0f%%", war.exhaustionDefender))")
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundStyle(NativeWarRoomTheme.signalCyan)
                            }
                        }
                    }
                    .padding(10)
                    .background(NativeWarRoomTheme.archiveShadow.opacity(0.9))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(NativeWarRoomTheme.threatRed.opacity(0.35), lineWidth: 1)
                    }
                }
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassmorphicCard(borderColor: NativeWarRoomTheme.brass.opacity(0.24), cornerRadius: 10)
    }

    private var powersLeaderboardCard: some View {
        let ranked = session.world.countries.values.sorted { lhs, rhs in
            if lhs.code == session.playerCountryCode {
                return true
            }
            if rhs.code == session.playerCountryCode {
                return false
            }
            if lhs.isGreatPower != rhs.isGreatPower {
                return lhs.isGreatPower
            }
            return lhs.gdpEstimate > rhs.gdpEstimate
        }

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionHeader("POWERS & POLITIES", icon: "globe")
                Spacer()
                Text("\(ranked.count) NATIONS")
                    .font(NativeWarRoomTheme.labelFont(.caption2, weight: .semibold))
                    .foregroundStyle(NativeWarRoomTheme.mutedInk)
            }

            ForEach(ranked, id: \.code) { country in
                let atWar = session.world.wars.contains { $0.attacker == country.code || $0.defender == country.code }
                let isPlayer = country.code == session.playerCountryCode
                let isSelected = selectedCountryCode == country.code
                let relation = isPlayer ? 100.0 : session.world.relation(from: session.playerCountryCode, to: country.code)

                Button {
                    selectedCountryCode = (selectedCountryCode == country.code) ? nil : country.code
                } label: {
                    HStack(spacing: 8) {
                        NativeCountryStandard(countryCode: LWMapCodeBridge.flagAlpha3(for: country.code), size: 22)

                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 5) {
                                Text(country.name)
                                    .font(NativeWarRoomTheme.bodyFont(.caption, weight: isPlayer ? .bold : .semibold))
                                    .foregroundStyle(isPlayer ? NativeWarRoomTheme.brass : NativeWarRoomTheme.ink)
                                    .lineLimit(1)
                                if country.isGreatPower {
                                    Text("GP")
                                        .font(.system(size: 8, weight: .black, design: .monospaced))
                                        .foregroundStyle(NativeWarRoomTheme.blackboard)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(NativeWarRoomTheme.brass, in: RoundedRectangle(cornerRadius: 2))
                                }
                                if atWar {
                                    Image(systemName: "flame.fill")
                                        .font(.caption2)
                                        .foregroundStyle(NativeWarRoomTheme.threatRed)
                                }
                            }

                            Text(
                                isPlayer
                                    ? "Player Nation  ·  MIL \(String(format: "%.0f", country.armyPower))"
                                    : "REL \(String(format: "%+.0f", relation))  ·  MIL \(String(format: "%.0f", country.armyPower))"
                            )
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(NativeWarRoomTheme.mutedInk)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 1) {
                            Text(String(format: "SOL %.1f", country.standardOfLiving))
                                .font(NativeWarRoomTheme.labelFont(.caption2, weight: .bold))
                                .foregroundStyle(solColor(country.standardOfLiving))
                            Text(String(format: "GDP %.0f", country.gdpEstimate))
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundStyle(NativeWarRoomTheme.mutedInk)
                        }
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(
                        isSelected
                            ? NativeWarRoomTheme.olivePanel
                            : NativeWarRoomTheme.archiveShadow.opacity(0.72)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(
                                isSelected ? NativeWarRoomTheme.brass.opacity(0.65) : NativeWarRoomTheme.brass.opacity(0.14),
                                lineWidth: 1
                            )
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassmorphicCard(borderColor: NativeWarRoomTheme.brass.opacity(0.24), cornerRadius: 10)
    }

    // MARK: Chronicle Dispatches Card

    private var eventFeed: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("WAR ROOM DISPATCHES", icon: "newspaper")

            if session.recentEvents.isEmpty {
                Text("No dispatches recorded yet. Unpause the clock or step a day to begin the chronicle.")
                    .font(NativeWarRoomTheme.bodyFont(.caption, weight: .regular))
                    .foregroundStyle(NativeWarRoomTheme.mutedInk)
                    .padding(.vertical, 8)
            } else {
                ForEach(session.recentEvents, id: \.id) { event in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 6) {
                            NativeCountryStandard(countryCode: LWMapCodeBridge.flagAlpha3(for: event.countryCode), size: 16)
                            Text(LWDate.from(dayIndex: event.day).stamp)
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(NativeWarRoomTheme.brass)
                            severityDot(event.severity)
                            Spacer()
                            if let decision = event.decisionChosen {
                                Text(decision)
                                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                                    .foregroundStyle(NativeWarRoomTheme.fieldGreen)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(NativeWarRoomTheme.fieldGreen.opacity(0.16), in: RoundedRectangle(cornerRadius: 3))
                            }
                        }
                        Text(event.title)
                            .font(NativeWarRoomTheme.displayFont(.caption, weight: .bold))
                            .foregroundStyle(NativeWarRoomTheme.ink)
                        Text(event.summary)
                            .font(NativeWarRoomTheme.bodyFont(.caption, weight: .regular))
                            .foregroundStyle(NativeWarRoomTheme.mutedInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(NativeWarRoomTheme.archiveShadow.opacity(0.85))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(
                                event.severity > 0.6 ? NativeWarRoomTheme.threatRed.opacity(0.35) : NativeWarRoomTheme.brass.opacity(0.16),
                                lineWidth: 1
                            )
                    }
                }
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassmorphicCard(borderColor: NativeWarRoomTheme.brass.opacity(0.24), cornerRadius: 10)
    }

    // MARK: Telemetry Helpers

    private var warTargets: [String] {
        session.world.sortedCountryCodes().filter { $0 != session.playerCountryCode }
    }

    private var allianceTargets: [String] {
        session.world.sortedCountryCodes().filter { code in
            code != session.playerCountryCode &&
                !session.world.pacts.contains { $0.kind == .alliance && ($0.a == code || $0.b == code) && ($0.a == session.playerCountryCode || $0.b == session.playerCountryCode) }
        }
    }

    private func dailyFiscalBalance(for country: LWCountry) -> Double {
        country.pops.total * (country.taxLevel * 0.02 - (0.008 + country.spendingLevel * 0.012))
    }

    private func estimatedSOLTarget(for country: LWCountry) -> Double {
        8.0 + country.spendingLevel * 6 + min(10, country.gdpEstimate * 0.02) - country.radicals * 4
    }

    private func solColor(_ sol: Double) -> Color {
        if sol >= 14 {
            return NativeWarRoomTheme.fieldGreen
        }
        if sol >= 9 {
            return NativeWarRoomTheme.alertAmber
        }
        return NativeWarRoomTheme.threatRed
    }

    private func strategyTitle(_ strategy: LWCountryStrategy) -> String {
        switch strategy {
        case .balanced: "Balanced"
        case .expansionist: "Expansionist"
        case .economicTurtle: "Economic Turtle"
        case .opportunist: "Opportunist"
        }
    }

    private func buildingTitle(_ type: LWBuildingType) -> String {
        switch type {
        case .subsistenceFarms: "Subsistence Farms"
        case .commercialFarms: "Commercial Farms"
        case .mines: "Mineral Mines"
        case .lumberCamps: "Lumber Camps"
        case .textileMills: "Textile Mills"
        case .steelMills: "Steel Mills"
        case .toolingWorks: "Tooling Works"
        case .consumerFactories: "Consumer Factories"
        case .armsIndustry: "Arms Industry"
        case .constructionSector: "Construction Sector"
        }
    }

    private func buildingIcon(_ type: LWBuildingType) -> String {
        switch type {
        case .subsistenceFarms, .commercialFarms: "leaf.fill"
        case .mines: "hammer.fill"
        case .lumberCamps: "tree.fill"
        case .textileMills: "scissors"
        case .steelMills: "flame.fill"
        case .toolingWorks: "wrench.and.screwdriver.fill"
        case .consumerFactories: "shippingbox.fill"
        case .armsIndustry: "shield.fill"
        case .constructionSector: "building.fill"
        }
    }

    private func buildingChainSummary(_ type: LWBuildingType) -> String {
        let out = goodDisplayName(type.outputGood).uppercased()
        if type.inputGoods.isEmpty {
            return "OUTPUT → \(out)"
        }
        let inputs = type.inputGoods.map { "\(goodDisplayName($0.id)) (\(String(format: "%.1f", $0.amount)))" }.joined(separator: " + ")
        return "\(inputs) → \(out)"
    }

    private func goodDisplayName(_ id: String) -> String {
        switch id {
        case "grain": "Grain"
        case "luxury_food": "Luxury Food"
        case "minerals": "Minerals"
        case "lumber": "Lumber"
        case "textiles": "Textiles"
        case "steel": "Steel"
        case "machinery": "Machinery"
        case "consumer_goods": "Consumer Goods"
        case "materiel": "Materiel"
        case "construction": "Construction"
        default: id.capitalized
        }
    }

    private func goodIcon(_ category: LWGoodCategory) -> String {
        switch category {
        case .stapleFood: "leaf.fill"
        case .luxuryFood: "cup.and.saucer.fill"
        case .textiles: "tshirt.fill"
        case .minerals: "mountain.2.fill"
        case .lumber: "tree.fill"
        case .steel: "square.stack.3d.up.fill"
        case .machinery: "gearshape.fill"
        case .consumerGoods: "bag.fill"
        case .militaryMateriel: "scope"
        }
    }

    private func telemetryChip(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(NativeWarRoomTheme.mutedInk)
            Text(value)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(NativeWarRoomTheme.blackboard.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
    }

    private func severityDot(_ severity: Double) -> some View {
        Circle()
            .fill(severity > 0.6 ? NativeWarRoomTheme.threatRed : (severity > 0.25 ? NativeWarRoomTheme.alertAmber : NativeWarRoomTheme.fieldGreen))
            .frame(width: 6, height: 6)
    }

    private func sectionHeader(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(NativeWarRoomTheme.labelFont(.caption, weight: .bold))
            .tracking(0.8)
            .foregroundStyle(NativeWarRoomTheme.brass)
    }
}

// MARK: - Interactive Vector Strategic Map

private struct LivingWorldAtlasMap: View {
    let world: LivingWorldState
    let playerCountryCode: String
    @Binding var activeLens: LWMapLens
    @Binding var selectedCountryCode: String?
    var isDrawerCollapsed: Binding<Bool>?

    @State private var zoomScale: CGFloat = 1.0
    @State private var lastZoomScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var hoveredCountryCode: String?
    @State private var hoverScreenLocation: CGPoint = .zero

    private var maxWorldGDP: Double {
        max(10.0, world.countries.values.map(\.gdpEstimate).max() ?? 50.0)
    }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let scaleX = max(0.01, size.width / 1000.0)
            let scaleY = max(0.01, size.height / 600.0)

            ZStack {
                let dragGesture = DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let proposed = CGSize(
                            width: lastOffset.width + value.translation.width,
                            height: lastOffset.height + value.translation.height
                        )
                        offset = clampOffset(proposed, size: size, zoom: zoomScale)
                    }
                    .onEnded { value in
                        let distance = hypot(value.translation.width, value.translation.height)
                        if distance < 10 {
                            let mapPt = reverseTransform(value.location, size: size, scaleX: scaleX, scaleY: scaleY)
                            if let hit = GeopoliticalMapData.nonWaterRegions.first(where: {
                                $0.path.boundingRect.contains(mapPt) && $0.path.contains(mapPt)
                            }), let lwCode = LWMapCodeBridge.toLWCode(hit.countryCode, in: world) {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    selectedCountryCode = (selectedCountryCode == lwCode) ? nil : lwCode
                                }
                            } else {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    selectedCountryCode = nil
                                }
                            }
                        } else {
                            lastOffset = offset
                        }
                    }

                let magnificationGesture = MagnificationGesture()
                    .onChanged { value in
                        zoomScale = max(1.0, min(lastZoomScale * value, 10.0))
                    }
                    .onEnded { _ in
                        zoomScale = max(1.0, min(zoomScale, 10.0))
                        lastZoomScale = zoomScale
                        withAnimation(.easeOut(duration: 0.2)) {
                            offset = clampOffset(offset, size: size, zoom: zoomScale)
                            lastOffset = offset
                        }
                    }

                let doubleTapGesture = TapGesture(count: 2)
                    .onEnded {
                        withAnimation(.easeOut(duration: 0.25)) {
                            zoomScale = min(zoomScale + 1.8, 10.0)
                            lastZoomScale = zoomScale
                            offset = clampOffset(offset, size: size, zoom: zoomScale)
                            lastOffset = offset
                        }
                    }

                Canvas(opaque: true, colorMode: .nonLinear, rendersAsynchronously: true) { context, canvasSize in
                    context.fill(
                        Path(CGRect(origin: .zero, size: canvasSize)),
                        with: .color(Color(hex: "#b3b49a"))
                    )
                    drawGridLines(context: context, size: canvasSize)

                    context.drawLayer { ctx in
                        ctx.translateBy(x: canvasSize.width / 2 + offset.width, y: canvasSize.height / 2 + offset.height)
                        ctx.scaleBy(x: zoomScale, y: zoomScale)
                        ctx.translateBy(x: -canvasSize.width / 2, y: -canvasSize.height / 2)
                        drawOceanWaves(context: ctx, scaleX: scaleX, scaleY: scaleY)
                        drawCompassRose(context: ctx, scaleX: scaleX, scaleY: scaleY)
                        drawAtlasWorld(context: ctx, size: canvasSize, scaleX: scaleX, scaleY: scaleY)
                    }
                }
                .frame(width: size.width, height: size.height)
                .contentShape(Rectangle())
                .gesture(
                    SimultaneousGesture(
                        SimultaneousGesture(dragGesture, magnificationGesture),
                        doubleTapGesture
                    )
                )
                .onContinuousHover { phase in
                    switch phase {
                    case let .active(location):
                        hoverScreenLocation = location
                        let mapPt = reverseTransform(location, size: size, scaleX: scaleX, scaleY: scaleY)
                        if let hit = GeopoliticalMapData.nonWaterRegions.first(where: {
                            $0.path.boundingRect.contains(mapPt) && $0.path.contains(mapPt)
                        }) {
                            hoveredCountryCode = LWMapCodeBridge.toLWCode(hit.countryCode, in: world)
                        } else {
                            hoveredCountryCode = nil
                        }
                    case .ended:
                        hoveredCountryCode = nil
                    }
                }

                // Active War Front Progress Pills overlay (sharp SwiftUI vectors)
                if activeLens == .warsAndFronts || activeLens == .diplomacy {
                    ForEach(world.wars, id: \.id) { war in
                        if let ptA = LWAtlasGeometryCache.mapCenter(forLWCode: war.attacker),
                           let ptB = LWAtlasGeometryCache.mapCenter(forLWCode: war.defender)
                        {
                            let midMap = CGPoint(x: (ptA.x + ptB.x) * 0.5, y: (ptA.y + ptB.y) * 0.5 - 14)
                            let screenPt = screenPoint(forMapPoint: midMap, size: size, scaleX: scaleX, scaleY: scaleY)
                            if screenPt.x > 40, screenPt.x < size.width - 40, screenPt.y > 40, screenPt.y < size.height - 40 {
                                let progress = war.fronts.first?.progress ?? 0
                                HStack(spacing: 4) {
                                    Image(systemName: "flame.fill")
                                        .font(.system(size: 8))
                                        .foregroundStyle(NativeWarRoomTheme.threatRed)
                                    Text("\(war.attacker) vs \(war.defender)")
                                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                                        .foregroundStyle(NativeWarRoomTheme.ink)
                                    Text(String(format: "%+.0f", progress))
                                        .font(.system(size: 8, weight: .black, design: .monospaced))
                                        .foregroundStyle(progress >= 0 ? NativeWarRoomTheme.threatRed : NativeWarRoomTheme.signalCyan)
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(NativeWarRoomTheme.archiveShadow.opacity(0.94), in: Capsule())
                                .overlay {
                                    Capsule().stroke(NativeWarRoomTheme.threatRed.opacity(0.65), lineWidth: 1)
                                }
                                .position(screenPt)
                                .allowsHitTesting(false)
                            }
                        }
                    }
                }

                // Top-right Lens Pill Bar + optional Drawer Expand button
                VStack(alignment: .trailing, spacing: 8) {
                    HStack(spacing: 6) {
                        HStack(spacing: 3) {
                            ForEach(LWMapLens.allCases) { lens in
                                let isSelected = activeLens == lens
                                Button {
                                    withAnimation(.easeOut(duration: 0.16)) {
                                        activeLens = lens
                                    }
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: lens.systemImage)
                                            .font(.system(size: 10, weight: .bold))
                                        Text(lens.title.uppercased())
                                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 5)
                                    .background(isSelected ? NativeWarRoomTheme.brass : Color.clear)
                                    .foregroundStyle(isSelected ? NativeWarRoomTheme.blackboard : NativeWarRoomTheme.ink)
                                    .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(4)
                        .background(NativeWarRoomTheme.archiveShadow.opacity(0.92), in: Capsule())
                        .overlay {
                            Capsule().stroke(NativeWarRoomTheme.brass.opacity(0.4), lineWidth: 1)
                        }

                        if let collapsedBinding = isDrawerCollapsed, collapsedBinding.wrappedValue {
                            Button {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    collapsedBinding.wrappedValue = false
                                }
                            } label: {
                                Image(systemName: "sidebar.left")
                                    .font(.caption.weight(.bold))
                                    .frame(width: 30, height: 30)
                                    .background(NativeWarRoomTheme.archiveShadow.opacity(0.92))
                                    .foregroundStyle(NativeWarRoomTheme.brass)
                                    .clipShape(Circle())
                                    .overlay {
                                        Circle().stroke(NativeWarRoomTheme.brass.opacity(0.4), lineWidth: 1)
                                    }
                            }
                            .buttonStyle(.plain)
                            .help("Expand Command Drawer")
                        }
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)

                // Bottom-left Minimap Viewport Indicator + Lens Legend
                HStack(alignment: .bottom, spacing: 10) {
                    minimapIndicator(size: size, scaleX: scaleX, scaleY: scaleY)
                    lensLegendOverlay
                }
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)

                // Bottom-right Floating Brass Zoom Controls
                VStack(spacing: 6) {
                    zoomButton(icon: "plus") {
                        withAnimation(.easeOut(duration: 0.2)) {
                            zoomScale = min(zoomScale + 0.65, 10.0)
                            lastZoomScale = zoomScale
                        }
                    }
                    zoomButton(icon: "minus") {
                        withAnimation(.easeOut(duration: 0.2)) {
                            zoomScale = max(zoomScale - 0.65, 1.0)
                            lastZoomScale = zoomScale
                            if zoomScale == 1.0 {
                                offset = .zero
                                lastOffset = .zero
                            } else {
                                offset = clampOffset(offset, size: size, zoom: zoomScale)
                                lastOffset = offset
                            }
                        }
                    }
                    zoomButton(icon: "arrow.counterclockwise") {
                        withAnimation(.easeOut(duration: 0.25)) {
                            zoomScale = 1.0
                            lastZoomScale = 1.0
                            offset = .zero
                            lastOffset = .zero
                        }
                    }
                }
                .padding(6)
                .background(NativeWarRoomTheme.archiveShadow.opacity(0.88), in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8).stroke(NativeWarRoomTheme.brass.opacity(0.32), lineWidth: 1)
                }
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)

                // Cartographic Hover Tooltip
                if let hoveredCode = hoveredCountryCode,
                   let hoveredCountry = world.countries[hoveredCode]
                {
                    hoverTooltip(for: hoveredCountry)
                        .position(
                            x: min(max(130, hoverScreenLocation.x + 135), max(130, size.width - 135)),
                            y: min(max(72, hoverScreenLocation.y - 54), max(72, size.height - 90))
                        )
                        .allowsHitTesting(false)
                }
            }
        }
    }

    private func zoomButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .frame(width: 28, height: 28)
                .background(NativeWarRoomTheme.olivePanel.opacity(0.95))
                .foregroundStyle(NativeWarRoomTheme.brass)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay {
                    RoundedRectangle(cornerRadius: 5).stroke(NativeWarRoomTheme.brass.opacity(0.28), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }

    private func hoverTooltip(for country: LWCountry) -> some View {
        let relation = country.code == playerCountryCode ? nil : world.relation(from: playerCountryCode, to: country.code)
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 7) {
                NativeCountryStandard(countryCode: LWMapCodeBridge.flagAlpha3(for: country.code), size: 22)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text(country.name)
                            .font(NativeWarRoomTheme.displayFont(.caption, weight: .bold))
                            .foregroundStyle(NativeWarRoomTheme.ink)
                            .lineLimit(1)
                        if country.isGreatPower {
                            Text("GP")
                                .font(.system(size: 8, weight: .black, design: .monospaced))
                                .foregroundStyle(NativeWarRoomTheme.blackboard)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(NativeWarRoomTheme.brass, in: RoundedRectangle(cornerRadius: 2))
                        }
                    }
                    Text(strategyLabel(country.strategy))
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(NativeWarRoomTheme.brass)
                }
            }

            Rectangle()
                .fill(NativeWarRoomTheme.brass.opacity(0.2))
                .frame(height: 1)

            HStack(spacing: 10) {
                Text(String(format: "SOL %.1f", country.standardOfLiving))
                    .foregroundStyle(country.standardOfLiving > 14 ? NativeWarRoomTheme.fieldGreen : (country.standardOfLiving < 9 ? NativeWarRoomTheme.threatRed : NativeWarRoomTheme.alertAmber))
                Text(String(format: "£%.0fM", country.treasury))
                    .foregroundStyle(NativeWarRoomTheme.ink)
                if let relation {
                    Text(String(format: "REL %+.0f", relation))
                        .foregroundStyle(relation >= 15 ? NativeWarRoomTheme.fieldGreen : (relation <= -15 ? NativeWarRoomTheme.threatRed : NativeWarRoomTheme.mutedInk))
                } else {
                    Text("PLAYER")
                        .foregroundStyle(NativeWarRoomTheme.brass)
                }
            }
            .font(.system(size: 9, weight: .bold, design: .monospaced))
        }
        .padding(9)
        .frame(width: 220, alignment: .leading)
        .background(NativeWarRoomTheme.archiveShadow.opacity(0.96), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8).stroke(NativeWarRoomTheme.brass.opacity(0.55), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.45), radius: 8, x: 0, y: 4)
    }

    private func minimapIndicator(size: CGSize, scaleX: CGFloat, scaleY: CGFloat) -> some View {
        let miniSize = CGSize(width: 104, height: 62)
        let topLeft = reverseTransform(.zero, size: size, scaleX: scaleX, scaleY: scaleY)
        let bottomRight = reverseTransform(CGPoint(x: size.width, y: size.height), size: size, scaleX: scaleX, scaleY: scaleY)
        let normX = max(0, min(1, topLeft.x / 1000.0))
        let normY = max(0, min(1, topLeft.y / 600.0))
        let normW = max(0.06, min(1.0 - normX, (bottomRight.x - topLeft.x) / 1000.0))
        let normH = max(0.06, min(1.0 - normY, (bottomRight.y - topLeft.y) / 600.0))

        return ZStack(alignment: .topLeading) {
            Canvas(opaque: true) { ctx, mSize in
                ctx.fill(Path(CGRect(origin: .zero, size: mSize)), with: .color(Color(hex: "#23261d")))
                let t = CGAffineTransform(scaleX: mSize.width / 1000.0, y: mSize.height / 600.0)
                for lm in GeopoliticalMapData.landmasses {
                    ctx.fill(lm.path.applying(t), with: .color(NativeWarRoomTheme.mapPaper.opacity(0.45)))
                }
            }
            .frame(width: miniSize.width, height: miniSize.height)

            Rectangle()
                .stroke(NativeWarRoomTheme.brass, lineWidth: 1.5)
                .background(NativeWarRoomTheme.brass.opacity(0.14))
                .frame(width: miniSize.width * normW, height: miniSize.height * normH)
                .offset(x: miniSize.width * normX, y: miniSize.height * normY)
        }
        .frame(width: miniSize.width, height: miniSize.height)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(NativeWarRoomTheme.brass.opacity(0.42), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.35), radius: 4, x: 0, y: 2)
        .allowsHitTesting(false)
    }

    private var lensLegendOverlay: some View {
        HStack(spacing: 8) {
            switch activeLens {
            case .diplomacy:
                legendDot("YOU", NativeWarRoomTheme.brass)
                legendDot("ALLY", NativeWarRoomTheme.fieldGreen)
                legendDot("WAR", NativeWarRoomTheme.threatRed)
                legendDot("POWER", NativeWarRoomTheme.alertAmber)
            case .livingStandard:
                legendDot("SOL <9", NativeWarRoomTheme.threatRed)
                legendDot("9–14", NativeWarRoomTheme.alertAmber)
                legendDot(">14", NativeWarRoomTheme.fieldGreen)
            case .warsAndFronts:
                legendDot("BELLIGERENT", NativeWarRoomTheme.threatRed)
                legendDot("ALLY", NativeWarRoomTheme.alertAmber)
                legendDot("PEACE", NativeWarRoomTheme.olivePanel)
            case .industryAndGDP:
                legendDot("AGRARIAN", NativeWarRoomTheme.mapPaper)
                legendDot("INDUSTRIAL", NativeWarRoomTheme.brass)
                legendDot("CORE GP", NativeWarRoomTheme.fieldGreen)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(NativeWarRoomTheme.archiveShadow.opacity(0.9), in: RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6).stroke(NativeWarRoomTheme.brass.opacity(0.26), lineWidth: 1)
        }
        .allowsHitTesting(false)
    }

    private func legendDot(_ title: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(title)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(NativeWarRoomTheme.ink)
        }
    }

    // MARK: Coordinate Math

    private func clampOffset(_ proposed: CGSize, size: CGSize, zoom: CGFloat) -> CGSize {
        guard zoom > 1.0 else { return .zero }
        let maxX = (zoom - 1.0) * size.width / 2.0 + 100.0
        let maxY = (zoom - 1.0) * size.height / 2.0 + 100.0
        return CGSize(
            width: max(-maxX, min(maxX, proposed.width)),
            height: max(-maxY, min(maxY, proposed.height))
        )
    }

    private func reverseTransform(_ location: CGPoint, size: CGSize, scaleX: CGFloat, scaleY: CGFloat) -> CGPoint {
        let baseX = size.width / 2.0 + (location.x - offset.width - size.width / 2.0) / zoomScale
        let baseY = size.height / 2.0 + (location.y - offset.height - size.height / 2.0) / zoomScale
        return CGPoint(x: baseX / scaleX, y: baseY / scaleY)
    }

    private func screenPoint(forMapPoint pt: CGPoint, size: CGSize, scaleX: CGFloat, scaleY: CGFloat) -> CGPoint {
        let baseX = pt.x * scaleX
        let baseY = pt.y * scaleY
        return CGPoint(
            x: size.width / 2.0 + offset.width + (baseX - size.width / 2.0) * zoomScale,
            y: size.height / 2.0 + offset.height + (baseY - size.height / 2.0) * zoomScale
        )
    }

    // MARK: Canvas Drawing Passes

    private func drawGridLines(context: GraphicsContext, size: CGSize) {
        let stepX = size.width / 12.0
        let stepY = size.height / 8.0
        var gridPath = Path()
        for x in stride(from: stepX, to: size.width, by: stepX) {
            gridPath.move(to: CGPoint(x: x, y: 0))
            gridPath.addLine(to: CGPoint(x: x, y: size.height))
        }
        for y in stride(from: stepY, to: size.height, by: stepY) {
            gridPath.move(to: CGPoint(x: 0, y: y))
            gridPath.addLine(to: CGPoint(x: size.width, y: y))
        }
        context.stroke(
            gridPath,
            with: .color(NativeWarRoomTheme.graphite.opacity(0.11)),
            style: StrokeStyle(lineWidth: 0.9, dash: [4, 4])
        )
    }

    private func drawOceanWaves(context: GraphicsContext, scaleX: CGFloat, scaleY: CGFloat) {
        let centers: [CGPoint] = [
            CGPoint(x: 310, y: 295),
            CGPoint(x: 115, y: 255),
            CGPoint(x: 165, y: 405),
            CGPoint(x: 880, y: 225),
            CGPoint(x: 905, y: 415),
            CGPoint(x: 640, y: 445)
        ]
        for center in centers {
            let cx = center.x * scaleX
            let cy = center.y * scaleY
            var wave = Path()
            wave.move(to: CGPoint(x: cx - 14 / zoomScale, y: cy))
            wave.addQuadCurve(
                to: CGPoint(x: cx, y: cy),
                control: CGPoint(x: cx - 7 / zoomScale, y: cy - 3.5 / zoomScale)
            )
            wave.addQuadCurve(
                to: CGPoint(x: cx + 14 / zoomScale, y: cy),
                control: CGPoint(x: cx + 7 / zoomScale, y: cy - 3.5 / zoomScale)
            )
            context.stroke(wave, with: .color(NativeWarRoomTheme.graphite.opacity(0.18)), style: StrokeStyle(lineWidth: 1.1 / zoomScale, lineCap: .round))
        }
    }

    private func drawCompassRose(context: GraphicsContext, scaleX: CGFloat, scaleY: CGFloat) {
        let center = CGPoint(x: 92 * scaleX, y: 495 * scaleY)
        let r = 22.0 / zoomScale
        let innerR = 5.5 / zoomScale

        let outerRect = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
        context.stroke(Path(ellipseIn: outerRect), with: .color(NativeWarRoomTheme.graphite.opacity(0.28)), lineWidth: 1.0 / zoomScale)

        let innerRect = CGRect(x: center.x - r * 0.72, y: center.y - r * 0.72, width: r * 1.44, height: r * 1.44)
        context.stroke(Path(ellipseIn: innerRect), with: .color(NativeWarRoomTheme.oxidizedBrass.opacity(0.32)), style: StrokeStyle(lineWidth: 0.7 / zoomScale, dash: [2, 2].map { $0 / zoomScale }))

        var star = Path()
        for i in 0 ..< 4 {
            let angle = Double(i) * .pi / 2.0
            let tip = CGPoint(x: center.x + CGFloat(cos(angle)) * r, y: center.y + CGFloat(sin(angle)) * r)
            let left = CGPoint(x: center.x + CGFloat(cos(angle - .pi / 4.0)) * innerR, y: center.y + CGFloat(sin(angle - .pi / 4.0)) * innerR)
            let right = CGPoint(x: center.x + CGFloat(cos(angle + .pi / 4.0)) * innerR, y: center.y + CGFloat(sin(angle + .pi / 4.0)) * innerR)
            star.move(to: center)
            star.addLine(to: left)
            star.addLine(to: tip)
            star.addLine(to: right)
            star.closeSubpath()
        }
        context.fill(star, with: .color(NativeWarRoomTheme.oxidizedBrass.opacity(0.24)))
        context.stroke(star, with: .color(NativeWarRoomTheme.graphite.opacity(0.38)), lineWidth: 0.8 / zoomScale)

        let nText = Text("N")
            .font(.system(size: 7 / zoomScale, weight: .black, design: .serif))
            .foregroundColor(NativeWarRoomTheme.graphite.opacity(0.55))
        context.draw(nText, at: CGPoint(x: center.x, y: center.y - r - 5 / zoomScale), anchor: .center)
    }

    private func drawAtlasWorld(context: GraphicsContext, size: CGSize, scaleX: CGFloat, scaleY: CGFloat) {
        let minLocalX = (-size.width / 2.0 - offset.width) / zoomScale + size.width / 2.0
        let maxLocalX = (size.width / 2.0 - offset.width) / zoomScale + size.width / 2.0
        let minLocalY = (-size.height / 2.0 - offset.height) / zoomScale + size.height / 2.0
        let maxLocalY = (size.height / 2.0 - offset.height) / zoomScale + size.height / 2.0

        let visibleRect = CGRect(
            x: minLocalX / scaleX - 150.0,
            y: minLocalY / scaleY - 150.0,
            width: (maxLocalX - minLocalX) / scaleX + 300.0,
            height: (maxLocalY - minLocalY) / scaleY + 300.0
        )

        let transform = CGAffineTransform(scaleX: scaleX, y: scaleY)

        // 1. Landmasses base
        for lm in GeopoliticalMapData.landmasses {
            guard visibleRect.intersects(lm.path.boundingRect) else { continue }
            let path = lm.path.applying(transform)
            context.fill(path, with: .color(Color(hex: "#c9bc92")))
            context.stroke(path, with: .color(NativeWarRoomTheme.graphite.opacity(0.28)), lineWidth: 1.0 / zoomScale)
        }

        // Precompute player allies & war enemies for fast region styling
        let playerAllies = Set(LivingWorldTick.allies(of: playerCountryCode, world: world))
        var playerEnemies = Set<String>()
        var allBelligerents = Set<String>()
        var allWarAllies = Set<String>()
        for war in world.wars {
            allBelligerents.insert(war.attacker)
            allBelligerents.insert(war.defender)
            allWarAllies.formUnion(war.attackerAllies)
            allWarAllies.formUnion(war.defenderAllies)
            if war.attacker == playerCountryCode || war.attackerAllies.contains(playerCountryCode) {
                playerEnemies.insert(war.defender)
                playerEnemies.formUnion(war.defenderAllies)
            }
            if war.defender == playerCountryCode || war.defenderAllies.contains(playerCountryCode) {
                playerEnemies.insert(war.attacker)
                playerEnemies.formUnion(war.attackerAllies)
            }
        }

        // 2. Geopolitical Regions
        for reg in GeopoliticalMapData.nonWaterRegions {
            guard visibleRect.intersects(reg.path.boundingRect) else { continue }
            let path = reg.path.applying(transform)
            let lwCode = LWMapCodeBridge.toLWCode(reg.countryCode, in: world)
            let lwCountry = lwCode.flatMap { world.countries[$0] }
            let isSelected = lwCode != nil && lwCode == selectedCountryCode
            let isHovered = lwCode != nil && lwCode == hoveredCountryCode

            drawRegionFill(
                context: context,
                path: path,
                lwCode: lwCode,
                lwCountry: lwCountry,
                playerAllies: playerAllies,
                playerEnemies: playerEnemies,
                allBelligerents: allBelligerents,
                allWarAllies: allWarAllies
            )

            // Exhaustion crimson halo in Wars lens
            if activeLens == .warsAndFronts, let lwCountry, lwCountry.warExhaustion > 15 {
                let glowAlpha = min(0.75, lwCountry.warExhaustion / 100.0)
                context.stroke(path, with: .color(NativeWarRoomTheme.threatRed.opacity(glowAlpha)), lineWidth: 3.0 / zoomScale)
            }

            // Border styling
            if isSelected {
                context.stroke(path, with: .color(NativeWarRoomTheme.ink), lineWidth: 2.8 / zoomScale)
                context.stroke(path, with: .color(NativeWarRoomTheme.brass), lineWidth: 1.5 / zoomScale)
            } else if isHovered {
                context.stroke(path, with: .color(NativeWarRoomTheme.parchment.opacity(0.9)), lineWidth: 1.8 / zoomScale)
            } else if lwCode == playerCountryCode {
                context.stroke(path, with: .color(NativeWarRoomTheme.brass.opacity(0.9)), lineWidth: 1.6 / zoomScale)
            } else {
                context.stroke(path, with: .color(NativeWarRoomTheme.graphite.opacity(0.36)), lineWidth: 0.85 / zoomScale)
            }
        }

        // 3. State borders when zoomed in
        if zoomScale >= 1.8 {
            for stateReg in GeopoliticalMapData.states {
                guard visibleRect.intersects(stateReg.path.boundingRect) else { continue }
                let path = stateReg.path.applying(transform)
                context.stroke(path, with: .color(NativeWarRoomTheme.graphite.opacity(0.2)), lineWidth: 0.7 / zoomScale)
            }
        }

        // 4. Active War Front Vectors (dashed crimson arcs between capitals)
        if activeLens == .warsAndFronts || activeLens == .diplomacy {
            for war in world.wars {
                guard let ptA = LWAtlasGeometryCache.mapCenter(forLWCode: war.attacker),
                      let ptB = LWAtlasGeometryCache.mapCenter(forLWCode: war.defender)
                else { continue }

                let p1 = CGPoint(x: ptA.x * scaleX, y: ptA.y * scaleY)
                let p2 = CGPoint(x: ptB.x * scaleX, y: ptB.y * scaleY)
                let mid = CGPoint(
                    x: (p1.x + p2.x) * 0.5,
                    y: (p1.y + p2.y) * 0.5 - max(12, hypot(p2.x - p1.x, p2.y - p1.y) * 0.14)
                )

                var arc = Path()
                arc.move(to: p1)
                arc.addQuadCurve(to: p2, control: mid)

                context.stroke(
                    arc,
                    with: .color(NativeWarRoomTheme.threatRed.opacity(activeLens == .warsAndFronts ? 0.92 : 0.65)),
                    style: StrokeStyle(
                        lineWidth: (activeLens == .warsAndFronts ? 2.4 : 1.6) / zoomScale,
                        lineCap: .round,
                        dash: [6, 4].map { $0 / zoomScale }
                    )
                )
            }
        }

        // 5. Simulated Nation Capital & Great Power Badges
        for code in world.sortedCountryCodes() {
            guard let country = world.countries[code],
                  let mapCenter = LWAtlasGeometryCache.mapCenter(forLWCode: code),
                  visibleRect.contains(mapCenter)
            else { continue }

            let pt = CGPoint(x: mapCenter.x * scaleX, y: mapCenter.y * scaleY)
            let isPlayer = code == playerCountryCode
            let radius = (isPlayer || country.isGreatPower ? 4.2 : 2.8) / zoomScale
            let dotRect = CGRect(x: pt.x - radius, y: pt.y - radius, width: radius * 2, height: radius * 2)
            let dotColor = isPlayer ? NativeWarRoomTheme.brass : (country.isGreatPower ? NativeWarRoomTheme.threatRed : NativeWarRoomTheme.graphite)

            context.fill(Path(ellipseIn: dotRect), with: .color(dotColor))
            context.stroke(Path(ellipseIn: dotRect), with: .color(NativeWarRoomTheme.parchment), lineWidth: 0.9 / zoomScale)

            if country.isGreatPower || isPlayer || zoomScale >= 1.4 {
                let tag = (country.isGreatPower && activeLens == .industryAndGDP) ? "\(country.code) ★" : country.code
                let label = Text(tag)
                    .font(.system(size: (isPlayer || country.isGreatPower ? 7.5 : 6.2) / zoomScale, weight: .black, design: .monospaced))
                    .foregroundColor(NativeWarRoomTheme.archiveShadow)
                let halo = Text(tag)
                    .font(.system(size: (isPlayer || country.isGreatPower ? 7.5 : 6.2) / zoomScale, weight: .black, design: .monospaced))
                    .foregroundColor(NativeWarRoomTheme.parchment.opacity(0.85))
                let off = 0.6 / zoomScale
                let labelPt = CGPoint(x: pt.x, y: pt.y - radius - 2.5 / zoomScale)
                context.draw(halo, at: CGPoint(x: labelPt.x + off, y: labelPt.y + off), anchor: .bottom)
                context.draw(label, at: labelPt, anchor: .bottom)
            }
        }
    }

    private func drawRegionFill(
        context: GraphicsContext,
        path: Path,
        lwCode: String?,
        lwCountry: LWCountry?,
        playerAllies: Set<String>,
        playerEnemies: Set<String>,
        allBelligerents: Set<String>,
        allWarAllies: Set<String>
    ) {
        switch activeLens {
        case .diplomacy:
            guard let lwCode, lwCountry != nil else {
                context.fill(path, with: .color(NativeWarRoomTheme.mapPaper.opacity(0.32)))
                return
            }
            if lwCode == playerCountryCode {
                context.fill(path, with: .color(NativeWarRoomTheme.brass.opacity(0.62)))
            } else if playerEnemies.contains(lwCode) {
                drawDiagonalStripes(context: context, path: path, baseColor: NativeWarRoomTheme.threatRed.opacity(0.45), stripeColor: NativeWarRoomTheme.threatRed.opacity(0.75))
            } else if playerAllies.contains(lwCode) {
                context.fill(path, with: .color(NativeWarRoomTheme.fieldGreen.opacity(0.48)))
            } else {
                context.fill(path, with: .color(NativeWarRoomTheme.alertAmber.opacity(0.32)))
            }

        case .livingStandard:
            guard let lwCountry else {
                context.fill(path, with: .color(NativeWarRoomTheme.mapPaper.opacity(0.26)))
                return
            }
            let sol = lwCountry.standardOfLiving
            let fill: Color = if sol < 9.0 {
                NativeWarRoomTheme.threatRed
            } else if sol <= 14.0 {
                Color.lerp(from: NativeWarRoomTheme.alertAmber, to: NativeWarRoomTheme.fieldGreen, fraction: (sol - 9.0) / 5.0)
            } else {
                NativeWarRoomTheme.fieldGreen
            }
            context.fill(path, with: .color(fill.opacity(0.58)))

        case .warsAndFronts:
            guard let lwCode, lwCountry != nil else {
                context.fill(path, with: .color(NativeWarRoomTheme.mapPaper.opacity(0.24)))
                return
            }
            if allBelligerents.contains(lwCode) {
                drawDiagonalStripes(context: context, path: path, baseColor: NativeWarRoomTheme.threatRed.opacity(0.5), stripeColor: NativeWarRoomTheme.threatRed.opacity(0.8))
            } else if allWarAllies.contains(lwCode) {
                context.fill(path, with: .color(NativeWarRoomTheme.alertAmber.opacity(0.46)))
            } else {
                context.fill(path, with: .color(NativeWarRoomTheme.olivePanel.opacity(0.22)))
            }

        case .industryAndGDP:
            guard let lwCountry else {
                context.fill(path, with: .color(NativeWarRoomTheme.mapPaper.opacity(0.25)))
                return
            }
            let norm = min(1.0, max(0.0, lwCountry.gdpEstimate / maxWorldGDP))
            let fill = norm < 0.5
                ? Color.lerp(from: NativeWarRoomTheme.mapPaper, to: NativeWarRoomTheme.brass, fraction: norm * 2.0)
                : Color.lerp(from: NativeWarRoomTheme.brass, to: NativeWarRoomTheme.fieldGreen, fraction: (norm - 0.5) * 2.0)
            context.fill(path, with: .color(fill.opacity(0.62)))
        }
    }

    private func drawDiagonalStripes(context: GraphicsContext, path: Path, baseColor: Color, stripeColor: Color) {
        var ctx = context
        ctx.fill(path, with: .color(baseColor))
        ctx.clip(to: path)
        let bounds = path.boundingRect
        let spacing = 9.0 / zoomScale
        var stripePath = Path()
        for x in stride(from: bounds.minX - bounds.height, to: bounds.maxX, by: spacing) {
            stripePath.move(to: CGPoint(x: x, y: bounds.minY))
            stripePath.addLine(to: CGPoint(x: x + bounds.height, y: bounds.maxY))
        }
        ctx.stroke(stripePath, with: .color(stripeColor), lineWidth: 2.0 / zoomScale)
    }

    private func strategyLabel(_ strategy: LWCountryStrategy) -> String {
        switch strategy {
        case .balanced: "BALANCED"
        case .expansionist: "EXPANSIONIST"
        case .economicTurtle: "ECONOMIC TURTLE"
        case .opportunist: "OPPORTUNIST"
        }
    }
}

// MARK: - Click-on-Country Dossier Overlay

private struct LWCountryDossierCard: View {
    let country: LWCountry
    let world: LivingWorldState
    let playerCountryCode: String
    let onClose: () -> Void
    let onDeclareWar: () -> Void
    let onProposeAlliance: () -> Void

    private var isPlayer: Bool {
        country.code == playerCountryCode
    }

    private var playerCountry: LWCountry? {
        world.countries[playerCountryCode]
    }

    private var activePactsWithPlayer: [LWPact] {
        world.pacts.filter {
            ($0.a == playerCountryCode && $0.b == country.code) ||
                ($0.b == playerCountryCode && $0.a == country.code)
        }
    }

    private var isAlliedWithPlayer: Bool {
        activePactsWithPlayer.contains { $0.kind == .alliance }
    }

    private var isAtWarWithPlayer: Bool {
        world.wars.contains {
            ($0.attacker == playerCountryCode && $0.defender == country.code) ||
                ($0.defender == playerCountryCode && $0.attacker == country.code)
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                // Header
                HStack(alignment: .top, spacing: 10) {
                    NativeCountryStandard(countryCode: LWMapCodeBridge.flagAlpha3(for: country.code), size: 36)

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(country.name)
                                .font(NativeWarRoomTheme.displayFont(.headline, weight: .bold))
                                .foregroundStyle(NativeWarRoomTheme.ink)
                                .lineLimit(1)
                            Text(country.isGreatPower ? "GP" : "MINOR")
                                .font(.system(size: 9, weight: .black, design: .monospaced))
                                .foregroundStyle(country.isGreatPower ? NativeWarRoomTheme.blackboard : NativeWarRoomTheme.ink)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(
                                    country.isGreatPower ? NativeWarRoomTheme.brass : NativeWarRoomTheme.olivePanel,
                                    in: RoundedRectangle(cornerRadius: 3)
                                )
                        }

                        HStack(spacing: 6) {
                            Text(strategyLabel(country.strategy))
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(NativeWarRoomTheme.signalCyan)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(NativeWarRoomTheme.signalCyan.opacity(0.14), in: Capsule())

                            if country.mobilized {
                                Text("MOBILIZED")
                                    .font(.system(size: 9, weight: .black, design: .monospaced))
                                    .foregroundStyle(NativeWarRoomTheme.threatRed)
                            }
                        }
                    }

                    Spacer()

                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.caption.weight(.bold))
                            .frame(width: 24, height: 24)
                            .background(NativeWarRoomTheme.blackboard.opacity(0.6))
                            .foregroundStyle(NativeWarRoomTheme.mutedInk)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }

                // Quick Telemetry Row
                HStack(spacing: 8) {
                    dossierStat("SOL", String(format: "%.1f", country.standardOfLiving), NativeWarRoomTheme.brass)
                    dossierStat("TREASURY", String(format: "£%.0fM", country.treasury), NativeWarRoomTheme.ink)
                    dossierStat("GDP EST", String(format: "%.1f", country.gdpEstimate), NativeWarRoomTheme.fieldGreen)
                    dossierStat("INFAMY", String(format: "%.0f", country.infamy), country.infamy > 40 ? NativeWarRoomTheme.threatRed : NativeWarRoomTheme.mutedInk)
                }

                Rectangle()
                    .fill(NativeWarRoomTheme.brass.opacity(0.2))
                    .frame(height: 1)

                // Pops Strata Bar
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("POPULATION STRATA")
                            .font(NativeWarRoomTheme.labelFont(.caption2, weight: .bold))
                            .foregroundStyle(NativeWarRoomTheme.brass)
                        Spacer()
                        Text(String(format: "%.1fM TOTAL", country.pops.total))
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(NativeWarRoomTheme.mutedInk)
                    }

                    GeometryReader { geo in
                        let total = max(0.01, country.pops.total)
                        HStack(spacing: 1) {
                            Rectangle()
                                .fill(NativeWarRoomTheme.mutedInk.opacity(0.65))
                                .frame(width: geo.size.width * (country.pops.lower / total))
                            Rectangle()
                                .fill(NativeWarRoomTheme.signalCyan.opacity(0.85))
                                .frame(width: geo.size.width * (country.pops.middle / total))
                            Rectangle()
                                .fill(NativeWarRoomTheme.brass)
                                .frame(width: max(2, geo.size.width * (country.pops.upper / total)))
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                    .frame(height: 8)

                    HStack(spacing: 8) {
                        Text("L \(String(format: "%.1fM", country.pops.lower))")
                            .foregroundStyle(NativeWarRoomTheme.mutedInk)
                        Text("M \(String(format: "%.1fM", country.pops.middle))")
                            .foregroundStyle(NativeWarRoomTheme.signalCyan)
                        Text("U \(String(format: "%.1fM", country.pops.upper))")
                            .foregroundStyle(NativeWarRoomTheme.brass)
                        Spacer()
                        Text("LIT \(String(format: "%.0f%%", country.literacy * 100))")
                            .foregroundStyle(NativeWarRoomTheme.ink)
                        Text("RAD \(String(format: "%.0f%%", country.radicals * 100))")
                            .foregroundStyle(country.radicals > 0.2 ? NativeWarRoomTheme.threatRed : NativeWarRoomTheme.mutedInk)
                    }
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                }

                Rectangle()
                    .fill(NativeWarRoomTheme.brass.opacity(0.2))
                    .frame(height: 1)

                // Government & Interest Groups
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("GOVERNMENT & FACTIONS")
                            .font(NativeWarRoomTheme.labelFont(.caption2, weight: .bold))
                            .foregroundStyle(NativeWarRoomTheme.brass)
                        Spacer()
                        Text("LEGITIMACY \(String(format: "%.0f", country.government.legitimacy))/100")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(NativeWarRoomTheme.statusColor(for: Int(country.government.legitimacy)))
                    }

                    ProgressView(value: min(100, max(0, country.government.legitimacy)), total: 100)
                        .tint(NativeWarRoomTheme.statusColor(for: Int(country.government.legitimacy)))

                    ForEach(country.interestGroups.sorted { $0.clout > $1.clout }, id: \.id) { ig in
                        HStack(spacing: 6) {
                            Text(ig.name)
                                .font(NativeWarRoomTheme.bodyFont(.caption2, weight: .semibold))
                                .foregroundStyle(NativeWarRoomTheme.ink)
                                .frame(width: 96, alignment: .leading)
                                .lineLimit(1)

                            GeometryReader { barGeo in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(NativeWarRoomTheme.blackboard)
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(ig.inGovernment ? NativeWarRoomTheme.brass : NativeWarRoomTheme.mutedInk.opacity(0.55))
                                        .frame(width: max(3, barGeo.size.width * min(1, max(0, ig.clout))))
                                }
                            }
                            .frame(height: 5)

                            Text(String(format: "%.0f%%", ig.clout * 100))
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(NativeWarRoomTheme.mutedInk)
                                .frame(width: 28, alignment: .trailing)

                            Text(String(format: "%+.1f", ig.approval))
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(ig.approval >= 0.05 ? NativeWarRoomTheme.fieldGreen : (ig.approval <= -0.05 ? NativeWarRoomTheme.threatRed : NativeWarRoomTheme.mutedInk))
                                .frame(width: 30, alignment: .trailing)

                            if ig.inGovernment {
                                Text("IN GOV")
                                    .font(.system(size: 7, weight: .black, design: .monospaced))
                                    .foregroundStyle(NativeWarRoomTheme.blackboard)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(NativeWarRoomTheme.brass, in: RoundedRectangle(cornerRadius: 2))
                            }
                        }
                    }
                }

                // Diplomatic & Military Posture (foreign nations only)
                if !isPlayer {
                    let relation = world.relation(from: playerCountryCode, to: country.code)
                    let playerArmy = playerCountry?.armyPower ?? 1
                    let maxArmy = max(1.0, max(playerArmy, country.armyPower))

                    Rectangle()
                        .fill(NativeWarRoomTheme.brass.opacity(0.2))
                        .frame(height: 1)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("DIPLOMATIC & MILITARY POSTURE")
                                .font(NativeWarRoomTheme.labelFont(.caption2, weight: .bold))
                                .foregroundStyle(NativeWarRoomTheme.brass)
                            Spacer()
                            Text(String(format: "REL %+.0f", relation))
                                .font(.system(size: 9, weight: .black, design: .monospaced))
                                .foregroundStyle(relation >= 15 ? NativeWarRoomTheme.fieldGreen : (relation <= -15 ? NativeWarRoomTheme.threatRed : NativeWarRoomTheme.alertAmber))
                        }

                        // Relation -100..+100 bar
                        GeometryReader { geo in
                            let pct = min(1, max(0, (relation + 100) / 200))
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(NativeWarRoomTheme.blackboard)
                                Rectangle()
                                    .fill(relation >= 0 ? NativeWarRoomTheme.fieldGreen : NativeWarRoomTheme.threatRed)
                                    .frame(width: max(3, geo.size.width * pct))
                                    .clipShape(RoundedRectangle(cornerRadius: 3))
                                Rectangle()
                                    .fill(NativeWarRoomTheme.parchment.opacity(0.6))
                                    .frame(width: 1.5, height: 8)
                                    .offset(x: geo.size.width * 0.5 - 0.75)
                            }
                        }
                        .frame(height: 6)

                        if !activePactsWithPlayer.isEmpty {
                            HStack(spacing: 6) {
                                ForEach(Array(activePactsWithPlayer.enumerated()), id: \.offset) { _, pact in
                                    Text(pactTitle(pact.kind).uppercased())
                                        .font(.system(size: 8, weight: .black, design: .monospaced))
                                        .foregroundStyle(NativeWarRoomTheme.fieldGreen)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(NativeWarRoomTheme.fieldGreen.opacity(0.15), in: RoundedRectangle(cornerRadius: 3))
                                }
                            }
                        }

                        // Army comparison
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("YOU \(String(format: "%.0f", playerArmy))")
                                    .foregroundStyle(NativeWarRoomTheme.brass)
                                Spacer()
                                Text("ARMY POWER")
                                    .foregroundStyle(NativeWarRoomTheme.mutedInk)
                                Spacer()
                                Text("\(country.code) \(String(format: "%.0f", country.armyPower))")
                                    .foregroundStyle(NativeWarRoomTheme.signalCyan)
                            }
                            .font(.system(size: 9, weight: .bold, design: .monospaced))

                            HStack(spacing: 6) {
                                ProgressView(value: playerArmy, total: maxArmy)
                                    .tint(NativeWarRoomTheme.brass)
                                ProgressView(value: country.armyPower, total: maxArmy)
                                    .tint(NativeWarRoomTheme.signalCyan)
                            }
                        }

                        HStack(spacing: 8) {
                            Button {
                                onProposeAlliance()
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "handshake.fill")
                                    Text(isAlliedWithPlayer ? "Allied" : "Propose Alliance")
                                }
                                .font(NativeWarRoomTheme.labelFont(.caption2, weight: .bold))
                                .frame(maxWidth: .infinity, minHeight: 30)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(NativeWarRoomTheme.fieldGreen.opacity(0.85))
                            .disabled(isAlliedWithPlayer || isAtWarWithPlayer)

                            Button(role: .destructive) {
                                onDeclareWar()
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "flame.fill")
                                    Text(isAtWarWithPlayer ? "At War" : "Declare War")
                                }
                                .font(NativeWarRoomTheme.labelFont(.caption2, weight: .bold))
                                .frame(maxWidth: .infinity, minHeight: 30)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(NativeWarRoomTheme.threatRed)
                            .disabled(isAtWarWithPlayer)
                        }
                    }
                }
            }
            .padding(14)
        }
        .warRoomDossier(borderColor: NativeWarRoomTheme.brass.opacity(0.58), cornerRadius: 12)
    }

    private func dossierStat(_ title: String, _ value: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(NativeWarRoomTheme.mutedInk)
            Text(value)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .background(NativeWarRoomTheme.blackboard.opacity(0.55), in: RoundedRectangle(cornerRadius: 5))
    }

    private func strategyLabel(_ strategy: LWCountryStrategy) -> String {
        switch strategy {
        case .balanced: "BALANCED"
        case .expansionist: "EXPANSIONIST"
        case .economicTurtle: "ECONOMIC TURTLE"
        case .opportunist: "OPPORTUNIST"
        }
    }

    private func pactTitle(_ kind: LWPactKind) -> String {
        switch kind {
        case .alliance: "Alliance"
        case .defensivePact: "Defensive Pact"
        case .tradeAgreement: "Trade Pact"
        case .nonaggression: "Non-Aggression"
        }
    }
}

// MARK: - Controls & Hash Bridge

private struct LWSliderRow: View {
    let label: String
    let value: Double
    let range: ClosedRange<Double>
    let onChange: (Double) -> Void

    var body: some View {
        HStack {
            Text(label.uppercased())
                .font(NativeWarRoomTheme.labelFont(.caption2, weight: .bold))
                .foregroundStyle(NativeWarRoomTheme.ink)
                .frame(width: 70, alignment: .leading)
            Slider(value: Binding(get: { value }, set: onChange), in: range)
                .tint(NativeWarRoomTheme.brass)
            Text(String(format: "%.0f%%", value * 100))
                .font(NativeWarRoomTheme.labelFont(.caption, weight: .bold))
                .foregroundStyle(NativeWarRoomTheme.brass)
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
            Label("LLM WORLD BRIDGE", systemImage: "cpu")
                .font(NativeWarRoomTheme.labelFont(.caption, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(NativeWarRoomTheme.brass)

            Text("Copy the world prompt into any LLM (e.g. ChatGPT with Python). It replies with a WORLDHASH that this game interprets deterministically.")
                .font(NativeWarRoomTheme.bodyFont(.caption, weight: .regular))
                .foregroundStyle(NativeWarRoomTheme.mutedInk)

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
            .tint(NativeWarRoomTheme.brass)
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
            .tint(NativeWarRoomTheme.brass)
            .foregroundStyle(NativeWarRoomTheme.blackboard)
            .disabled(pastedHash.isEmpty)
            .accessibilityIdentifier("lw-interpret-hash")

            if let result {
                Text(result)
                    .font(NativeWarRoomTheme.bodyFont(.caption, weight: .semibold))
                    .foregroundStyle(NativeWarRoomTheme.alertAmber)
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .warRoomDossier(borderColor: NativeWarRoomTheme.brass.opacity(0.32), cornerRadius: 10)
    }
}

// MARK: - Decision Interruption Modal

struct LivingWorldDecisionModalView: View {
    let decision: LWDecisionEvent
    var language: NativeGameLanguage = .english
    let onChoose: (LWDecisionOption) -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.84)
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Label(LWProse.string(.uiExecutiveDecisionHeader, language: language), systemImage: "exclamationmark.triangle.fill")
                            .font(NativeWarRoomTheme.labelFont(.caption, weight: .bold))
                            .tracking(0.8)
                            .foregroundStyle(NativeWarRoomTheme.threatRed)
                        Spacer()
                        Text(LWDate.from(dayIndex: decision.day).stamp)
                            .font(NativeWarRoomTheme.labelFont(.caption, weight: .semibold))
                            .foregroundStyle(NativeWarRoomTheme.brass)
                    }

                    if let asset = decision.imageAssetName {
                        EventImageView(imageName: asset, height: 180)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(decision.title)
                            .font(NativeWarRoomTheme.displayFont(.title2, weight: .bold))
                            .foregroundStyle(NativeWarRoomTheme.ink)

                        Text(decision.summary)
                            .font(NativeWarRoomTheme.bodyFont(.body, weight: .regular))
                            .foregroundStyle(NativeWarRoomTheme.parchment)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Rectangle()
                        .fill(NativeWarRoomTheme.brass.opacity(0.24))
                        .frame(height: 1)

                    Text(LWProse.string(.uiPolicyDirectivesHeader, language: language))
                        .font(NativeWarRoomTheme.labelFont(.caption2, weight: .bold))
                        .tracking(1.0)
                        .foregroundStyle(NativeWarRoomTheme.brass)

                    VStack(spacing: 10) {
                        ForEach(decision.options) { option in
                            Button {
                                onChoose(option)
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text(option.label)
                                            .font(NativeWarRoomTheme.displayFont(.subheadline, weight: .bold))
                                            .foregroundStyle(NativeWarRoomTheme.ink)
                                        Spacer()
                                        if let code = option.mechanicCode {
                                            Text(code)
                                                .font(NativeWarRoomTheme.labelFont(.caption2, weight: .bold))
                                                .foregroundStyle(NativeWarRoomTheme.brass)
                                        }
                                        Image(systemName: "chevron.right.circle.fill")
                                            .foregroundStyle(NativeWarRoomTheme.brass)
                                    }
                                    Text(option.detail)
                                        .font(NativeWarRoomTheme.bodyFont(.caption, weight: .regular))
                                        .foregroundStyle(NativeWarRoomTheme.mutedInk)
                                        .multilineTextAlignment(.leading)

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
                                        if option.radicalsDelta != 0 {
                                            effectPill(
                                                "RAD \(option.radicalsDelta <= 0 ? "" : "+")\(String(format: "%.0f%%", option.radicalsDelta * 100))",
                                                positive: option.radicalsDelta < 0
                                            )
                                        }
                                        if option.worldTensionDelta != 0 {
                                            effectPill(
                                                "TNS \(option.worldTensionDelta >= 0 ? "+" : "")\(String(format: "%.0f", option.worldTensionDelta))",
                                                positive: option.worldTensionDelta < 0
                                            )
                                        }
                                        if option.nextChainedEventID != nil {
                                            Text(LWProse.string(.uiChainTag, language: language))
                                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                                .foregroundStyle(NativeWarRoomTheme.alertAmber)
                                        }
                                    }
                                }
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(NativeWarRoomTheme.archiveShadow)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(NativeWarRoomTheme.brass.opacity(0.32), lineWidth: 1)
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("lw-decision-\(option.id)")
                        }
                    }
                }
                .padding(20)
            }
            .frame(maxWidth: 540, maxHeight: 680)
            .warRoomDossier(borderColor: NativeWarRoomTheme.threatRed.opacity(0.62), cornerRadius: 12)
            .padding(24)
        }
    }

    private func effectPill(_ text: String, positive: Bool) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundStyle(positive ? NativeWarRoomTheme.fieldGreen : NativeWarRoomTheme.threatRed)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background((positive ? NativeWarRoomTheme.fieldGreen : NativeWarRoomTheme.threatRed).opacity(0.16))
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}
