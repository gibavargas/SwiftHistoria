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

struct NativeCompactStatusBar: View {
    let state: NativeCampaignState
    let latestEvent: NativeCampaignEvent?
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 12) {
            // Country + round badge
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.glowingCyan)
                    .frame(width: 8, height: 8)
                Text(state.country.code)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.glowingCyan)
                Text("·")
                    .foregroundStyle(.secondary)
                Text("Round \(state.round)")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Divider().frame(height: 16)

            // Capacity
            HStack(spacing: 4) {
                Image(systemName: "bolt.horizontal")
                    .font(.caption2)
                    .foregroundStyle(state.administrativeCapacity >= 30 ? Color.neonTeal : Color.softRed)
                Text("\(state.administrativeCapacity)")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(state.administrativeCapacity >= 30 ? Color.neonTeal : Color.softRed)
            }

            Spacer()

            // Latest event (truncated)
            if let event = latestEvent {
                Circle()
                    .fill(event.importance == .severe ? Color.softRed : Color.alertGold)
                    .frame(width: 6, height: 6)
                    .opacity(pulse ? 0.4 : 1.0)
                    .scaleEffect(pulse ? 1.3 : 1.0)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                            pulse = true
                        }
                    }
                Text(event.title)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .glassmorphicCard(borderColor: Color.white.opacity(0.1), cornerRadius: 10)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("native-compact-status-bar")
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
