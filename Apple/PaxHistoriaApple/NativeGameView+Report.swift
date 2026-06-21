import MapKit
import SwiftUI

struct MetricCard: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.headline)
                .foregroundStyle(Color.glowingCyan)
                .frame(width: 40, height: 40)
                .background(Color.glowingCyan.opacity(0.12), in: Circle())
                .overlay {
                    Circle()
                        .stroke(Color.glowingCyan.opacity(0.24), lineWidth: 1)
                }

            VStack(alignment: .leading, spacing: 3) {
                Text(value)
                    .font(.title3.monospacedDigit())
                    .fontWeight(.bold)
                    .foregroundStyle(.primary)
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .glassmorphicCard(borderColor: .white.opacity(0.08), cornerRadius: 12)
        .hoverScale(1.02)
    }
}

struct ActionRow: View {
    let action: NativePlannedAction
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: action.status == .resolved ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(action.status == .resolved ? Color.neonTeal : Color.iceBlue.opacity(0.4))

            VStack(alignment: .leading, spacing: 4) {
                Text(action.title)
                    .font(.body.weight(.bold))
                    .foregroundStyle(.primary)
                Text(action.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.softRed.opacity(0.8))
                    .padding(8)
                    .background(Color.softRed.opacity(0.1), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete order \(action.title)")
            .accessibilityIdentifier("native-delete-order-\(action.id)")
        }
        .padding(12)
        .glassmorphicCard(borderColor: .white.opacity(0.08), cornerRadius: 10)
    }
}

struct EventCard: View {
    let event: NativeCampaignEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // High security dossier header
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "doc.text.fill")
                        .font(.caption)
                        .foregroundStyle(Color.alertGold)
                    Text("INTEL REPORT // CLASS-\(event.importance.rawValue.uppercased())")
                        .font(.system(.caption2, design: .monospaced).weight(.bold))
                        .foregroundStyle(Color.alertGold)
                }
                Spacer()
                Text(event.playerRelated ? "NATION" : "GLOBAL")
                    .font(.system(.caption2, design: .monospaced).weight(.bold))
                    .foregroundStyle(event.playerRelated ? Color.glowingCyan : Color.neonTeal)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        event.playerRelated ? Color.glowingCyan.opacity(0.12) : Color.neonTeal.opacity(0.12),
                        in: Capsule()
                    )
                    .overlay {
                        Capsule()
                            .stroke(event.playerRelated ? Color.glowingCyan.opacity(0.24) : Color.neonTeal.opacity(0.24), lineWidth: 1)
                    }
            }
            .padding(.bottom, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(event.title)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.primary)
                Text("\(event.date) · \(event.kind.displayName.uppercased())")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Text(event.description)
                .font(.body)
                .foregroundStyle(.primary.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)

            if !event.strategicEffects.isEmpty {
                Divider()
                    .background(Color.white.opacity(0.08))
                    .padding(.vertical, 4)

                Text("TACTICAL DELTAS")
                    .font(.system(.caption2, design: .monospaced).weight(.bold))
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(event.strategicEffects) { effect in
                        HStack(alignment: .center, spacing: 10) {
                            let isPositive = effect.magnitude >= 0
                            Text(isPositive ? "+\(effect.magnitude)" : "\(effect.magnitude)")
                                .font(.system(.caption, design: .monospaced).weight(.bold))
                                .foregroundStyle(isPositive ? Color.neonTeal : Color.softRed)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .frame(minWidth: 36)
                                .background(
                                    isPositive ? Color.neonTeal.opacity(0.12) : Color.softRed.opacity(0.12),
                                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                                )
                                .overlay {
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .stroke(isPositive ? Color.neonTeal.opacity(0.3) : Color.softRed.opacity(0.3), lineWidth: 1)
                                }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(effect.track.displayName.uppercased())
                                    .font(.system(.caption2, design: .monospaced).weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Text(effect.summary)
                                    .font(.caption)
                                    .foregroundStyle(.primary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
        }
        .padding(14)
        .glassmorphicCard(borderColor: .white.opacity(0.08), cornerRadius: 12)
    }
}

struct NativeTurnReportView: View {
    let report: NativeGeneratedTurn
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("GEOPOLITICAL PERIOD REPORT")
                        .font(.system(.caption, design: .monospaced).weight(.bold))
                        .foregroundStyle(Color.glowingCyan)
                        .tracking(2.0)
                    Text("Turn Resolution")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                }
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.body.weight(.bold))
                        .foregroundStyle(.secondary)
                        .padding(8)
                        .background(Color.white.opacity(0.08), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close report")
                .accessibilityIdentifier("native-report-close")
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 16)
            .background(Color.spaceBlack)

            Divider()
                .background(Color.white.opacity(0.12))

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Turn summary banner
                    VStack(alignment: .leading, spacing: 8) {
                        Text("SUMMARY ANALYSIS")
                            .font(.system(.caption2, design: .monospaced).weight(.bold))
                            .foregroundStyle(Color.alertGold)
                            .tracking(1.2)
                        Text(report.summary)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassmorphicCard(borderColor: Color.alertGold.opacity(0.25), cornerRadius: 12)

                    // Key metrics deltas
                    HStack(spacing: 16) {
                        // Stability card
                        HStack(spacing: 12) {
                            Image(systemName: "heart.text.square.fill")
                                .font(.title2)
                                .foregroundStyle(Color.neonTeal)
                                .padding(8)
                                .background(Color.neonTeal.opacity(0.12), in: Circle())

                            VStack(alignment: .leading, spacing: 2) {
                                let sign = report.stabilityDelta >= 0 ? "+" : ""
                                Text("\(sign)\(report.stabilityDelta)%")
                                    .font(.title3.monospacedDigit().weight(.bold))
                                    .foregroundStyle(report.stabilityDelta >= 0 ? Color.neonTeal : Color.softRed)
                                Text("Stability")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(12)
                        .glassmorphicCard(borderColor: Color.white.opacity(0.08), cornerRadius: 12)

                        // World Tension card
                        HStack(spacing: 12) {
                            Image(systemName: "globe.americas.fill")
                                .font(.title2)
                                .foregroundStyle(Color.softRed)
                                .padding(8)
                                .background(Color.softRed.opacity(0.12), in: Circle())

                            VStack(alignment: .leading, spacing: 2) {
                                let sign = report.worldTensionDelta >= 0 ? "+" : ""
                                Text("\(sign)\(report.worldTensionDelta)")
                                    .font(.title3.monospacedDigit().weight(.bold))
                                    .foregroundStyle(report.worldTensionDelta >= 0 ? Color.softRed : Color.neonTeal)
                                Text("World Tension")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(12)
                        .glassmorphicCard(borderColor: Color.white.opacity(0.08), cornerRadius: 12)
                    }

                    // Events List
                    VStack(alignment: .leading, spacing: 14) {
                        Text("CHRONOLOGICAL SIGNALS")
                            .font(.system(.subheadline, design: .monospaced).weight(.bold))
                            .foregroundStyle(Color.iceBlue)
                            .tracking(1.5)

                        if report.events.isEmpty {
                            Text("No specific signals logged this period.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            VStack(spacing: 14) {
                                ForEach(report.events) { event in
                                    EventCard(event: event)
                                }
                            }
                        }
                    }
                }
                .padding(24)
            }

            Divider()
                .background(Color.white.opacity(0.12))

            // Action Button bar
            VStack {
                Button(action: onDismiss) {
                    HStack {
                        Spacer()
                        Text("ACKNOWLEDGE & CLOSE DOSSIER")
                            .font(.system(.subheadline, design: .monospaced).weight(.bold))
                            .tracking(1.0)
                        Spacer()
                    }
                    .frame(minHeight: 44)
                    .background(Color.glowingCyan, in: Capsule())
                    .foregroundStyle(.black)
                    .shadow(color: Color.glowingCyan.opacity(0.3), radius: 8)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("native-report-dismiss")
            }
            .padding(16)
            .background(Color.spaceBlack)
        }
        .frame(minWidth: 500, minHeight: 600)
        .background(Color.spaceBlack.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }
}
