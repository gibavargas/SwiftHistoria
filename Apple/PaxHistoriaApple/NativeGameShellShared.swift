import SwiftUI

enum NativeGameTab: Hashable {
    case map
    case orders
    case intel
}

enum NativeIntelSection: String, CaseIterable, Hashable, Identifiable {
    case advisor
    case diplomacy
    case events
    case worldEconomics
    case library
    case settings

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .advisor: "Advisor"
        case .diplomacy: "Diplomacy"
        case .events: "Events"
        case .worldEconomics: "Economics"
        case .library: "Library"
        case .settings: "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .advisor: "brain.head.profile"
        case .diplomacy: "bubble.left.and.bubble.right"
        case .events: "clock"
        case .worldEconomics: "chart.bar.xaxis"
        case .library: "folder"
        case .settings: "slider.horizontal.3"
        }
    }

    var accessibilityIdentifier: String {
        "native-intel-section-\(rawValue)"
    }
}

#if os(macOS)
    enum NativeMacDestination: String, CaseIterable, Hashable, Identifiable {
        case overview
        case orders
        case advisor
        case diplomacy
        case events
        case worldEconomics
        case library
        case settings

        var id: String {
            rawValue
        }

        var title: String {
            switch self {
            case .overview: "Overview"
            case .orders: "Orders"
            case .advisor: "Advisor"
            case .diplomacy: "Diplomacy"
            case .events: "Events"
            case .worldEconomics: "Economics"
            case .library: "Library"
            case .settings: "Settings"
            }
        }

        var systemImage: String {
            switch self {
            case .overview: "globe.europe.africa"
            case .orders: "checklist"
            case .advisor: "brain.head.profile"
            case .diplomacy: "bubble.left.and.bubble.right"
            case .events: "clock"
            case .worldEconomics: "chart.bar.xaxis"
            case .library: "folder"
            case .settings: "slider.horizontal.3"
            }
        }

        var accessibilityIdentifier: String {
            "native-mac-destination-\(rawValue)"
        }
    }
#endif
enum ConsoleTab: String, CaseIterable, Identifiable {
    case orders
    case suggestions
    case advisor
    case diplomacy
    case events

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .orders: "Orders"
        case .suggestions: "Suggestions"
        case .advisor: "Advisor"
        case .diplomacy: "Diplomacy"
        case .events: "Events"
        }
    }

    var systemImage: String {
        switch self {
        case .orders: "checklist"
        case .suggestions: "sparkles"
        case .advisor: "brain.head.profile"
        case .diplomacy: "bubble.left.and.bubble.right"
        case .events: "clock"
        }
    }
}

extension View {
    func standardTextEditorStyle(minHeight: CGFloat) -> some View {
        frame(minHeight: minHeight)
            .padding(8)
            .scrollContentBackground(.hidden)
            .background(Color.deepSlate.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            }
    }
}

func native2010RelationColor(_ relation: Native2010Relation) -> Color {
    switch relation {
    case .ally, .partner:
        Color.neonTeal
    case .neutral, .watch:
        Color.alertGold
    case .rival:
        Color.softRed
    }
}

func native2010SignalColor(_ level: Native2010SignalLevel) -> Color {
    switch level {
    case .low:
        Color.neonTeal
    case .medium, .watch:
        Color.alertGold
    case .high:
        Color.softRed
    }
}

func nativeCapacityColor(for capacity: Int) -> Color {
    if capacity >= 70 {
        Color.neonTeal
    } else if capacity >= 30 {
        Color.alertGold
    } else {
        Color.softRed
    }
}

struct NativeCompactStatusBar: View {
    let state: NativeCampaignState
    let latestEvent: NativeCampaignEvent?

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                NativeCountryStandard(countryCode: state.country.code, size: 36)

                VStack(alignment: .leading, spacing: 1) {
                    Text(CountryNameResolver.name(forCode: state.country.code, in: state).uppercased())
                        .font(NativeWarRoomTheme.displayFont(.headline, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(NativeWarRoomTheme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                    Text("\(state.gameDate.uppercased())  ·  ROUND \(state.round)")
                        .font(NativeWarRoomTheme.labelFont(.caption2, weight: .semibold))
                        .foregroundStyle(NativeWarRoomTheme.brass)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Image(systemName: state.aiReadiness.ok ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash")
                    .font(.caption)
                    .foregroundStyle(state.aiReadiness.ok ? NativeWarRoomTheme.fieldGreen : NativeWarRoomTheme.threatRed)
                    .accessibilityLabel(state.aiReadiness.ok ? "AI ready" : "AI unavailable")
            }

            Rectangle()
                .fill(NativeWarRoomTheme.brass.opacity(0.22))
                .frame(height: 1)

            HStack(spacing: 0) {
                NativeAtlasMetric(label: "STABILITY", value: "\(state.stability)%", tint: NativeWarRoomTheme.statusColor(for: state.stability))
                NativeAtlasMetric(label: "TENSION", value: "\(state.worldTension)%", tint: NativeWarRoomTheme.statusColor(for: state.worldTension, highIsGood: false))
                NativeAtlasMetric(label: "CAPACITY", value: "\(state.administrativeCapacity)", tint: nativeCapacityColor(for: state.administrativeCapacity))
            }

            #if os(macOS)
                if let event = latestEvent {
                    HStack(spacing: 7) {
                        Rectangle()
                            .fill(event.importance == .severe ? NativeWarRoomTheme.threatRed : NativeWarRoomTheme.alertAmber)
                            .frame(width: 3, height: 13)
                        Text("LATEST")
                            .font(NativeWarRoomTheme.labelFont(.caption2))
                            .foregroundStyle(NativeWarRoomTheme.mutedInk)
                        Text(event.title)
                            .font(NativeWarRoomTheme.bodyFont(.caption, weight: .semibold))
                            .foregroundStyle(NativeWarRoomTheme.ink)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                }
            #endif
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .glassmorphicCard(borderColor: NativeWarRoomTheme.brass.opacity(0.32), cornerRadius: 8)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("native-compact-status-bar")
    }
}

struct NativeCountryStandard: View {
    let countryCode: String
    var size: CGFloat = 34

    var body: some View {
        Group {
            if let flag = CountryCatalog.flagEmoji(forAlpha3: countryCode) {
                Text(flag)
                    .font(.system(size: size * 0.62))
            } else {
                Text(String(countryCode.prefix(3)).uppercased())
                    .font(.system(size: size * 0.27, weight: .black, design: .monospaced))
                    .foregroundStyle(NativeWarRoomTheme.brass)
            }
        }
        .frame(width: size * 1.3, height: size)
        .background(NativeWarRoomTheme.archiveShadow.opacity(0.94))
        .overlay {
            Rectangle()
                .stroke(NativeWarRoomTheme.brass.opacity(0.42), lineWidth: 1)
        }
        .accessibilityLabel("Country standard for \(countryCode)")
    }
}

private struct NativeAtlasMetric: View {
    let label: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(NativeWarRoomTheme.labelFont(.caption2, weight: .semibold))
                .foregroundStyle(NativeWarRoomTheme.mutedInk)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(value)
                .font(NativeWarRoomTheme.labelFont(.caption, weight: .bold))
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(NativeWarRoomTheme.brass.opacity(0.14))
                .frame(width: 1, height: 28)
                .padding(.trailing, 8)
        }
    }
}

struct NativeLatestIntelTicker: View {
    let latestEvent: NativeCampaignEvent?
    @State private var pulse = false

    var body: some View {
        Group {
            if let event = latestEvent {
                HStack(spacing: 8) {
                    Circle()
                        .fill(event.importance == .severe ? Color.softRed : Color.alertGold)
                        .frame(width: 6, height: 6)
                        .opacity(pulse ? 0.3 : 1.0)
                        .scaleEffect(pulse ? 1.2 : 1.0)
                        .onAppear {
                            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                                pulse = true
                            }
                        }

                    Text("Latest event")
                        .font(.system(.caption2, design: .monospaced).weight(.bold))
                        .foregroundStyle(Color.glowingCyan)

                    Text(event.title.uppercased())
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Spacer()

                    if let firstEffect = event.strategicEffects.first {
                        let isPos = firstEffect.magnitude >= 0
                        Text("\(isPos ? "+" : "")\(firstEffect.magnitude) \(firstEffect.track.displayName.uppercased())")
                            .font(.system(.caption2, design: .monospaced).weight(.bold))
                            .foregroundStyle(isPos ? Color.neonTeal : Color.softRed)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .glassmorphicCard(borderColor: Color.white.opacity(0.1), cornerRadius: 8)
            } else {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.iceBlue.opacity(0.4))
                        .frame(width: 6, height: 6)
                    Text("No events yet")
                        .font(.system(.caption2, design: .monospaced).weight(.bold))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .glassmorphicCard(borderColor: Color.white.opacity(0.08), cornerRadius: 8)
            }
        }
    }
}

struct NativeTurnProgressPanel: View {
    let progress: NativeTurnProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                    .tint(Color.glowingCyan)
                Text(progress.phase.uppercased())
                    .font(.system(.caption, design: .monospaced).weight(.bold))
                    .foregroundStyle(Color.glowingCyan)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                Spacer()
                Text("\(progress.completedLanes)/\(progress.totalLanes)")
                    .font(.system(.caption2, design: .monospaced).weight(.bold))
                    .foregroundStyle(Color.iceBlue)
            }
            if let providerSummary = progress.providerSummary {
                HStack(spacing: 6) {
                    Image(systemName: "cpu")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color.alertGold)
                    Text(providerSummary)
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .foregroundStyle(Color.alertGold)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }
                .accessibilityIdentifier("native-turn-provider-summary")

                if let modelIdentifier = progress.modelIdentifier, modelIdentifier != progress.modelName {
                    Text(modelIdentifier)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .accessibilityIdentifier("native-turn-model-identifier")
                }
            }

            Text(progress.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            if let reasoningStatus = progress.reasoningStatus {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Image(systemName: reasoningStatus == .live ? "waveform.path.ecg" : "brain.head.profile")
                            .font(.caption2.weight(.bold))
                        Text("AI ACTIVITY")
                            .font(.system(.caption2, design: .monospaced).weight(.bold))
                        Spacer()
                        Text(reasoningStatus.label)
                            .font(.system(.caption2, design: .monospaced).weight(.bold))
                    }
                    .foregroundStyle(reasoningStatus == .live ? Color.neonTeal : Color.iceBlue)

                    Text(progress.reasoningText ?? "Waiting for reasoning activity.")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 7)
                .frame(height: 66, alignment: .topLeading)
                .background(Color.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color.iceBlue.opacity(0.16), lineWidth: 1)
                }
                .transaction { transaction in
                    transaction.animation = nil
                }
                .accessibilityIdentifier("native-turn-reasoning")
            }

            ProgressView(value: progress.fraction)
                .tint(Color.glowingCyan)
                .accessibilityIdentifier("native-turn-progress-bar")
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.spaceBlack.opacity(0.86), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.glowingCyan.opacity(0.28), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("native-turn-progress-panel")
    }
}
