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
        let accent = isAdvisor ? NativeWarRoomTheme.brass : NativeWarRoomTheme.signalCyan

        HStack {
            if !isAdvisor {
                Spacer(minLength: 28)
            }

            VStack(alignment: isAdvisor ? .leading : .trailing, spacing: 8) {
                HStack(spacing: 6) {
                    if isAdvisor {
                        Image(systemName: "shield.checkered")
                            .font(.caption)
                            .foregroundStyle(accent)
                        Text("CABINET INTELLIGENCE BRIEF")
                            .font(NativeWarRoomTheme.labelFont(.caption2, weight: .bold))
                            .foregroundStyle(accent)
                            .tracking(1.1)
                        Spacer(minLength: 8)
                        Text(message.date)
                            .font(NativeWarRoomTheme.labelFont(.caption2, weight: .regular))
                            .foregroundStyle(NativeWarRoomTheme.mutedInk)
                    } else {
                        Text(message.date)
                            .font(NativeWarRoomTheme.labelFont(.caption2, weight: .regular))
                            .foregroundStyle(NativeWarRoomTheme.mutedInk)
                        Spacer(minLength: 8)
                        Text("EXECUTIVE INQUIRY // SECURE")
                            .font(NativeWarRoomTheme.labelFont(.caption2, weight: .bold))
                            .foregroundStyle(accent)
                            .tracking(1.0)
                        Image(systemName: "lock.shield")
                            .font(.caption)
                            .foregroundStyle(accent)
                    }
                }

                Rectangle()
                    .fill(accent.opacity(0.22))
                    .frame(height: 1)

                Text(message.text)
                    .font(NativeWarRoomTheme.bodyFont(.body))
                    .foregroundStyle(NativeWarRoomTheme.ink)
                    .multilineTextAlignment(isAdvisor ? .leading : .trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(13)
            .background(
                LinearGradient(
                    colors: isAdvisor
                        ? [NativeWarRoomTheme.olivePanel.opacity(0.92), NativeWarRoomTheme.archiveShadow.opacity(0.96)]
                        : [NativeWarRoomTheme.graphite.opacity(0.94), NativeWarRoomTheme.blackboard.opacity(0.96)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(accent.opacity(isAdvisor ? 0.34 : 0.24), lineWidth: 1)
            }
            .overlay(alignment: isAdvisor ? .leading : .trailing) {
                Rectangle()
                    .fill(accent.opacity(0.65))
                    .frame(width: 3)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
                    .padding(.vertical, 8)
            }

            if isAdvisor {
                Spacer(minLength: 28)
            }
        }
        .accessibilityIdentifier("native-advisor-message-\(message.id)")
    }
}

struct DiplomacyMessageRow: View {
    let message: NativeDiplomaticMessage
    let isPlayer: Bool

    var body: some View {
        let accent = isPlayer ? NativeWarRoomTheme.brass : NativeWarRoomTheme.fieldGreen

        HStack {
            if isPlayer {
                Spacer(minLength: 28)
            }

            VStack(alignment: isPlayer ? .trailing : .leading, spacing: 8) {
                HStack(spacing: 6) {
                    if !isPlayer {
                        Image(systemName: "envelope.badge.shield.half.filled")
                            .font(.caption)
                            .foregroundStyle(accent)
                        Text("EMBASSY DISPATCH // \(message.speaker.uppercased())")
                            .font(NativeWarRoomTheme.labelFont(.caption2, weight: .bold))
                            .foregroundStyle(accent)
                            .tracking(0.9)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(message.date)
                            .font(NativeWarRoomTheme.labelFont(.caption2, weight: .regular))
                            .foregroundStyle(NativeWarRoomTheme.mutedInk)
                    } else {
                        Text(message.date)
                            .font(NativeWarRoomTheme.labelFont(.caption2, weight: .regular))
                            .foregroundStyle(NativeWarRoomTheme.mutedInk)
                        Spacer(minLength: 8)
                        Text("FOREIGN MINISTRY CABLE")
                            .font(NativeWarRoomTheme.labelFont(.caption2, weight: .bold))
                            .foregroundStyle(accent)
                            .tracking(0.9)
                        Image(systemName: "flag.fill")
                            .font(.caption)
                            .foregroundStyle(accent)
                    }
                }

                Rectangle()
                    .fill(accent.opacity(0.22))
                    .frame(height: 1)

                Text(message.text)
                    .font(NativeWarRoomTheme.bodyFont(.body))
                    .foregroundStyle(NativeWarRoomTheme.ink)
                    .multilineTextAlignment(isPlayer ? .trailing : .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(13)
            .background(
                LinearGradient(
                    colors: isPlayer
                        ? [NativeWarRoomTheme.graphite.opacity(0.94), NativeWarRoomTheme.archiveShadow.opacity(0.96)]
                        : [NativeWarRoomTheme.olivePanel.opacity(0.9), NativeWarRoomTheme.archiveShadow.opacity(0.96)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(accent.opacity(0.3), lineWidth: 1)
            }
            .overlay(alignment: isPlayer ? .trailing : .leading) {
                Rectangle()
                    .fill(accent.opacity(0.6))
                    .frame(width: 3)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
                    .padding(.vertical, 8)
            }

            if !isPlayer {
                Spacer(minLength: 28)
            }
        }
        .accessibilityIdentifier("native-diplomacy-message-\(message.id)")
    }
}
