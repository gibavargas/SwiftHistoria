import SwiftUI

/// Identifies active crisis situations from the campaign state.
/// Used to drive the crisis alert banner system.
enum NativeCrisisDetector {
    /// Represents a single detected crisis requiring player attention.
    struct CrisisAlert: Identifiable, Hashable {
        enum Severity: Int, Comparable {
            case low = 0
            case moderate = 1
            case severe = 2
            case critical = 3

            static func < (lhs: Self, rhs: Self) -> Bool {
                lhs.rawValue < rhs.rawValue
            }
        }

        enum Kind: String, Hashable {
            case invasionIncoming = "invasion-incoming"
            case invasionOutgoing = "invasion-outgoing"
            case attack
            case defense
            case stability = "stability-collapse"
            case nuclearFallout = "nuclear-fallout"
            case rebellion
            case worldWar = "world-war"

            var displayName: String {
                switch self {
                case .invasionIncoming: String(localized: "Invasion Threat")
                case .invasionOutgoing: String(localized: "Active Offensive")
                case .attack: String(localized: "Under Attack")
                case .defense: String(localized: "Defense Alert")
                case .stability: String(localized: "Stability Collapse Risk")
                case .nuclearFallout: String(localized: "Nuclear Fallout")
                case .rebellion: String(localized: "Armed Rebellion")
                case .worldWar: String(localized: "Global Conflict Escalation")
                }
            }

            var systemImage: String {
                switch self {
                case .invasionIncoming: "scope"
                case .invasionOutgoing: "target" // was "crosshair" — not available on macOS
                case .attack: "exclamationmark.octagon.fill"
                case .defense: "shield.lefthalf.filled.badge.checkmark"
                case .stability: "building.columns"
                case .nuclearFallout: "radiowaves.right"
                case .rebellion: "flame.fill"
                case .worldWar: "globe.americas.fill"
                }
            }

            var assetImageName: String {
                switch self {
                case .invasionIncoming, .invasionOutgoing, .attack, .defense:
                    "CrisisNavalPatrol"
                case .rebellion, .stability:
                    "CrisisCivilUnrest"
                case .nuclearFallout:
                    "CrisisNuclearFallout"
                case .worldWar:
                    "CrisisWorldWar"
                }
            }
        }

        let id: String
        let kind: Kind
        let severity: Severity
        let title: String
        let detail: String
        let date: String

        var accentColor: Color {
            switch severity {
            case .low: Color.alertGold
            case .moderate: Color.alertGold.opacity(0.9)
            case .severe: Color.softRed.opacity(0.9)
            case .critical: Color.softRed
            }
        }
    }

    /// Scans the campaign state and returns active crisis alerts, sorted by severity (highest first).
    static func activeCrises(for state: NativeCampaignState) -> [CrisisAlert] {
        var alerts: [CrisisAlert] = []
        let playerCode = state.country.code
        let playerCodeCanonical = GeopoliticalMapData.canonicalCountryCode(playerCode)

        // 1. Active invasions — player occupying foreign territory
        let playerOccupations = state.regionConflicts.filter { _, conflict in
            conflict.controllerCode == playerCode &&
                conflict.originalCountryCode != playerCode &&
                (conflict.mode == .conventionalOccupation || conflict.mode == .guerrillaControl)
        }
        for (regionID, conflict) in playerOccupations {
            let regionName = GeopoliticalMapData.regionByID[regionID]?.name ?? regionID
            let originalName = CountryNameResolver.name(forCode: conflict.originalCountryCode, in: state)
            let severity: CrisisAlert.Severity = conflict.intensity >= 4 ? .severe : .moderate
            alerts.append(CrisisAlert(
                id: "offensive-\(regionID)",
                kind: .invasionOutgoing,
                severity: severity,
                title: "Offensive in \(regionName) (\(originalName))",
                detail: "Your forces control \(regionName). Intensity: \(conflict.intensity)/5. \(sanitizeFoundationModelText(conflict.summary))",
                date: conflict.updatedAt
            ))
        }

        // 2. Player territory under foreign control
        let playerUnderAttack = state.regionConflicts.filter { _, conflict in
            conflict.originalCountryCode == playerCodeCanonical &&
                conflict.controllerCode != playerCode &&
                conflict.controllerCode != "REB"
        }
        for (regionID, conflict) in playerUnderAttack {
            let regionName = GeopoliticalMapData.regionByID[regionID]?.name ?? regionID
            let controllerName = CountryNameResolver.name(forCode: conflict.controllerCode, in: state)
            let severity: CrisisAlert.Severity = conflict.intensity >= 4 ? .critical : .severe
            alerts.append(CrisisAlert(
                id: "incoming-\(regionID)",
                kind: .invasionIncoming,
                severity: severity,
                title: "\(controllerName) holds \(regionName)",
                detail: "Foreign forces control your territory in \(regionName). Intensity: \(conflict.intensity)/5. \(sanitizeFoundationModelText(conflict.summary))",
                date: conflict.updatedAt
            ))
        }

        // 3. Rebellion on player territory
        let playerRebellions = state.regionConflicts.filter { _, conflict in
            conflict.originalCountryCode == playerCodeCanonical &&
                conflict.controllerCode == "REB"
        }
        for (regionID, conflict) in playerRebellions {
            let regionName = GeopoliticalMapData.regionByID[regionID]?.name ?? regionID
            let severity: CrisisAlert.Severity = conflict.intensity >= 4 ? .severe : .moderate
            alerts.append(CrisisAlert(
                id: "rebel-\(regionID)",
                kind: .rebellion,
                severity: severity,
                title: "Rebellion in \(regionName)",
                detail: "Armed insurgents control \(regionName). Intensity: \(conflict.intensity)/5. \(sanitizeFoundationModelText(conflict.summary))",
                date: conflict.updatedAt
            ))
        }

        // 4. Nuclear fallout on player territory
        for regionID in state.nuclearFalloutRegions {
            let originalCode = NativeRegionConflictState.countryCode(fromLegacyRegionID: regionID)
            if originalCode == playerCode || originalCode == playerCodeCanonical {
                let regionName = GeopoliticalMapData.regionByID[regionID]?.name ?? regionID
                alerts.append(CrisisAlert(
                    id: "fallout-\(regionID)",
                    kind: .nuclearFallout,
                    severity: .critical,
                    title: "Nuclear Fallout: \(regionName)",
                    detail: "Devastating nuclear fallout in \(regionName). Immediate reconstruction required.",
                    date: state.gameDate
                ))
            }
        }

        // 5. Stability collapse risk
        if state.stability <= 25 {
            let severity: CrisisAlert.Severity = state.stability <= 15 ? .critical : .severe
            alerts.append(CrisisAlert(
                id: "stability-collapse",
                kind: .stability,
                severity: severity,
                title: "Stability Critical: \(state.stability)/100",
                detail: "Internal stability is dangerously low. Without intervention, the government may collapse.",
                date: state.gameDate
            ))
        }

        // 6. World war / extreme global tension
        if state.worldTension >= 80 {
            let severity: CrisisAlert.Severity = state.worldTension >= 90 ? .critical : .severe
            alerts.append(CrisisAlert(
                id: "world-war",
                kind: .worldWar,
                severity: severity,
                title: "Global Tension Critical: \(state.worldTension)/100",
                detail: "International relations are at a breaking point. Major conflict escalation imminent.",
                date: state.gameDate
            ))
        }

        return alerts.sorted { lhs, rhs in
            lhs.severity == rhs.severity
                ? lhs.kind.displayName < rhs.kind.displayName
                : lhs.severity > rhs.severity
        }
    }
}

/// A dynamic, severity-aware crisis alert banner.
/// Shows the most urgent active crisis with animation, or a compact summary
/// if multiple crises exist.
struct NativeCrisisBanner: View {
    let state: NativeCampaignState
    var onTapOpenMap: (() -> Void)?
    var compact = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false
    @State private var currentIndex = 0

    private var crises: [NativeCrisisDetector.CrisisAlert] {
        NativeCrisisDetector.activeCrises(for: state)
    }

    var body: some View {
        if crises.isEmpty {
            EmptyView()
        } else {
            let topCrisis = crises[currentIndex % crises.count]
            Button {
                activateBanner()
            } label: {
                VStack(alignment: .leading, spacing: 0) {
                    crisisHeader(for: topCrisis)
                    crisisDetail(for: topCrisis)
                    if crises.count > 1 {
                        crisisPager
                    }
                }
            }
            .buttonStyle(.plain)
            .background(backgroundColor(for: topCrisis.severity))
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(topCrisis.accentColor)
                    .frame(width: 4)
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(topCrisis.accentColor.opacity(pulse ? 0.6 : 0.2), lineWidth: pulse ? 2 : 1)
            }
            .onAppear { startPulse(for: topCrisis.severity) }
            .accessibilityIdentifier("native-crisis-banner")
            .accessibilityLabel("Crisis alert: \(topCrisis.title)")
            .accessibilityValue("\(currentIndex % crises.count + 1) of \(crises.count). \(topCrisis.detail)")
            .accessibilityHint(onTapOpenMap == nil && crises.count > 1 ? "Shows the next crisis." : "Opens the strategic map.")
        }
    }

    // MARK: – Sub-views

    private func crisisHeader(for crisis: NativeCrisisDetector.CrisisAlert) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(crisis.kind.assetImageName)
                .resizable()
                .aspectRatio(3 / 2, contentMode: .fill)
                .frame(width: compact ? 48 : 64, height: compact ? 32 : 42)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(crisis.accentColor.opacity(pulse ? 0.8 : 0.35), lineWidth: 1)
                }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: crisis.kind.systemImage)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(crisis.accentColor)
                        .scaleEffect(pulse && crisis.severity >= .severe ? 1.15 : 1.0)
                    Text(crisis.kind.displayName.uppercased())
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                        .foregroundStyle(crisis.accentColor)
                        .tracking(1.2)
                }
                Text(crisis.title)
                    .font(.system(.subheadline, design: .default).weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
            }

            Spacer()

            if onTapOpenMap != nil {
                Image(systemName: "map.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(crisis.accentColor)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, compact ? 9 : 12)
        .padding(.bottom, 4)
    }

    private func crisisDetail(for crisis: NativeCrisisDetector.CrisisAlert) -> some View {
        Text(crisis.detail)
            .font(.system(.caption, design: .default))
            .foregroundStyle(.white.opacity(0.85))
            .fixedSize(horizontal: false, vertical: true)
            .lineLimit(compact ? 2 : nil)
            .padding(.horizontal, 12)
            .padding(.bottom, compact ? 8 : 10)
    }

    private var crisisPager: some View {
        HStack(spacing: 6) {
            ForEach(Array(crises.prefix(5).enumerated()), id: \.element.id) { index, crisis in
                Circle()
                    .fill(index == currentIndex % crises.count ? crisis.accentColor : Color.white.opacity(0.2))
                    .frame(width: 6, height: 6)
            }
            Spacer()
            Text("+\(crises.count - 1) more")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.6))
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }

    // MARK: – Helpers

    private func backgroundColor(for severity: NativeCrisisDetector.CrisisAlert.Severity) -> Color {
        switch severity {
        case .low:
            Color.alertGold.opacity(0.1)
        case .moderate:
            Color.alertGold.opacity(0.12)
        case .severe:
            Color.softRed.opacity(0.13)
        case .critical:
            Color.softRed.opacity(0.18)
        }
    }

    private func startPulse(for severity: NativeCrisisDetector.CrisisAlert.Severity) {
        guard severity >= .severe, !reduceMotion else { return }
        withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
            pulse = true
        }
    }

    private func activateBanner() {
        if let onTapOpenMap {
            onTapOpenMap()
        } else if crises.count > 1 {
            if reduceMotion {
                currentIndex += 1
            } else {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    currentIndex += 1
                }
            }
        }
    }
}
