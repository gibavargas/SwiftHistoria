import MapKit
import SwiftUI

struct SuggestedActionRow: View {
    let suggestion: NativeSuggestedAction
    let onUse: () -> Void

    private var urgencyColors: (bg: Color, border: Color, text: Color) {
        switch suggestion.urgency.lowercased() {
        case "immediate":
            (Color.softRed.opacity(0.12), Color.softRed.opacity(0.4), Color.softRed)
        case "soon":
            (Color.alertGold.opacity(0.12), Color.alertGold.opacity(0.4), Color.alertGold)
        case "opportunistic":
            (Color.neonTeal.opacity(0.12), Color.neonTeal.opacity(0.4), Color.neonTeal)
        default:
            (Color.iceBlue.opacity(0.12), Color.iceBlue.opacity(0.4), Color.iceBlue)
        }
    }

    var body: some View {
        let colors = urgencyColors
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                Text(suggestion.title)
                    .font(.body.weight(.bold))
                    .foregroundStyle(.primary)

                Spacer()

                Text(suggestion.urgency.uppercased())
                    .font(.system(.caption2, design: .monospaced).weight(.bold))
                    .foregroundStyle(colors.text)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(colors.bg, in: Capsule())
                    .overlay {
                        Capsule()
                            .stroke(colors.border, lineWidth: 1)
                    }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(suggestion.detail)
                    .font(.subheadline)
                    .foregroundStyle(.primary.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)

                Text(suggestion.rationale)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button {
                    onUse()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.caption.weight(.bold))
                        Text("Apply Suggestion")
                            .font(.caption.weight(.bold))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.accentColor, in: Capsule())
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("native-use-suggestion-\(suggestion.id)")
            }
        }
        .padding(14)
        .glassmorphicCard(borderColor: .white.opacity(0.08), cornerRadius: 12)
    }
}

struct AdvisorMessageRow: View {
    let message: NativeAdvisorMessage

    var body: some View {
        let isAdvisor = message.role == .advisor
        HStack {
            if !isAdvisor { Spacer(minLength: 40) }

            VStack(alignment: isAdvisor ? .leading : .trailing, spacing: 6) {
                HStack(spacing: 6) {
                    if isAdvisor {
                        Image(systemName: "brain.head.profile")
                            .font(.caption)
                            .foregroundStyle(Color.glowingCyan)
                        Text("ADVISOR BRIEF")
                            .font(.system(.caption2, design: .monospaced).weight(.bold))
                            .foregroundStyle(Color.glowingCyan)
                    } else {
                        Text("SECURE TRANSMISSION")
                            .font(.system(.caption2, design: .monospaced).weight(.bold))
                            .foregroundStyle(Color.iceBlue)
                        Image(systemName: "lock.shield")
                            .font(.caption)
                            .foregroundStyle(Color.iceBlue)
                    }
                }

                Text(message.text)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(isAdvisor ? .leading : .trailing)
                    .fixedSize(horizontal: false, vertical: true)

                Text(message.date)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(
                isAdvisor ? Color.iceBlue.opacity(0.12) : Color.deepSlate.opacity(0.6)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isAdvisor ? Color.iceBlue.opacity(0.24) : Color.white.opacity(0.08), lineWidth: 1)
            }

            if isAdvisor { Spacer(minLength: 40) }
        }
        .accessibilityIdentifier("native-advisor-message-\(message.id)")
    }
}

struct DiplomacyMessageRow: View {
    let message: NativeDiplomaticMessage
    let isPlayer: Bool

    var body: some View {
        HStack {
            if isPlayer { Spacer(minLength: 40) }

            VStack(alignment: isPlayer ? .trailing : .leading, spacing: 6) {
                HStack(spacing: 6) {
                    if !isPlayer {
                        Image(systemName: "globe.europe.africa")
                            .font(.caption)
                            .foregroundStyle(Color.neonTeal)
                        Text(message.speaker.uppercased())
                            .font(.system(.caption2, design: .monospaced).weight(.bold))
                            .foregroundStyle(Color.neonTeal)
                    } else {
                        Text("PLAYER TRANSMISSION")
                            .font(.system(.caption2, design: .monospaced).weight(.bold))
                            .foregroundStyle(Color.glowingCyan)
                        Image(systemName: "flag.fill")
                            .font(.caption)
                            .foregroundStyle(Color.glowingCyan)
                    }
                }

                Text(message.text)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(isPlayer ? .trailing : .leading)
                    .fixedSize(horizontal: false, vertical: true)

                Text(message.date)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(
                isPlayer ? Color.glowingCyan.opacity(0.08) : Color.neonTeal.opacity(0.08)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isPlayer ? Color.glowingCyan.opacity(0.2) : Color.neonTeal.opacity(0.2), lineWidth: 1)
            }

            if !isPlayer { Spacer(minLength: 40) }
        }
        .accessibilityIdentifier("native-diplomacy-message-\(message.id)")
    }
}
