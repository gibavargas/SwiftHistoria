import SwiftUI

/// First-run in-game contextual help overlay. Shows a brief 4-card War Room
/// Field Manual walkthrough of the main panels on the player's first campaign entry.
struct NativeContextualHelpOverlay: View {
    @Binding var isPresented: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page = 0

    private struct FieldManualCard: Identifiable {
        let id: Int
        let code: String
        let title: String
        let subtitle: String
        let icon: String
        let body: String
        let accent: Color
    }

    private let cards: [FieldManualCard] = [
        FieldManualCard(
            id: 0,
            code: "BRIEFING 01",
            title: "Atlas & Strategic Lenses",
            subtitle: "Cartographic Theatre",
            icon: "map.fill",
            body: "Inspect any sovereign territory to review terrain, stability, and flashpoint status. Your nation is framed in brass gold across map layers—switch lenses to track GDP mass, diplomatic posture, and conflict corridors.",
            accent: NativeWarRoomTheme.brass
        ),
        FieldManualCard(
            id: 1,
            code: "BRIEFING 02",
            title: "5×5 Decision Matrix & Orders",
            subtitle: "Executive Command",
            icon: "square.grid.3x3.topleft.filled",
            body: "Draft bespoke cabinet directives or select calibrated doctrines from the 5×5 Decision Matrix. Queued orders consume administrative capacity and execute together when the turn advances.",
            accent: NativeWarRoomTheme.fieldGreen
        ),
        FieldManualCard(
            id: 2,
            code: "BRIEFING 03",
            title: "Chancellery, Diplomacy & Advisor",
            subtitle: "Intelligence Directorate",
            icon: "building.columns.fill",
            body: "Consult your Strategic Advisor for threat assessments and domestic trade-offs, then open the Diplomacy dossier to negotiate accords, monitor alliances, and respond to sovereign crises.",
            accent: NativeWarRoomTheme.signalCyan
        ),
        FieldManualCard(
            id: 3,
            code: "BRIEFING 04",
            title: "Advancing History",
            subtitle: "Simulation Resolution",
            icon: "calendar.badge.clock",
            body: "Press Advance to resolve the next 3-month quarter—or run daily ticks in Living World mode. Every resolved turn updates the historical ledger, world tension, and any provider status stays visible.",
            accent: NativeWarRoomTheme.alertAmber
        )
    ]

    private var currentCard: FieldManualCard {
        cards[min(max(page, 0), cards.count - 1)]
    }

    var body: some View {
        VStack(spacing: 0) {
            manualHeader

            Rectangle()
                .fill(NativeWarRoomTheme.brass.opacity(0.22))
                .frame(height: 1)

            #if os(iOS)
                TabView(selection: $page) {
                    ForEach(cards) { card in
                        cardBody(card)
                            .tag(card.id)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(minHeight: 280, maxHeight: 330)
            #else
                cardBody(currentCard)
                    .id(currentCard.id)
                    .frame(minHeight: 280, maxHeight: 330)
            #endif

            progressPips
                .padding(.bottom, 14)

            Rectangle()
                .fill(NativeWarRoomTheme.brass.opacity(0.18))
                .frame(height: 1)

            footerControls
                .padding(18)
        }
        .background(
            LinearGradient(
                colors: [
                    NativeWarRoomTheme.blackboard,
                    NativeWarRoomTheme.graphite,
                    NativeWarRoomTheme.archiveShadow
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(NativeWarRoomTheme.brass.opacity(0.28), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .preferredColorScheme(.dark)
    }

    private var manualHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "book.closed.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(NativeWarRoomTheme.brass)

            Text("FIELD MANUAL // \(currentCard.code) OF 0\(cards.count)")
                .font(NativeTypography.cartographicLabel(.caption2, weight: .bold))
                .foregroundStyle(NativeWarRoomTheme.brass)
                .tracking(1.4)

            Spacer()

            Text("CLASSIFIED")
                .font(NativeTypography.cartographicLabel(.caption2, weight: .bold))
                .foregroundStyle(NativeWarRoomTheme.mutedInk)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(NativeWarRoomTheme.olivePanel.opacity(0.8), in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(NativeWarRoomTheme.brass.opacity(0.24), lineWidth: 1)
                }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(NativeWarRoomTheme.archiveShadow.opacity(0.95))
    }

    private func cardBody(_ card: FieldManualCard) -> some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(card.accent.opacity(0.14))
                    .frame(width: 84, height: 84)
                Circle()
                    .stroke(card.accent.opacity(0.45), lineWidth: 1.2)
                    .frame(width: 84, height: 84)
                Circle()
                    .stroke(NativeWarRoomTheme.brass.opacity(0.22), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                    .frame(width: 98, height: 98)

                Image(systemName: card.icon)
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(card.accent)
            }

            VStack(spacing: 6) {
                Text(card.subtitle.uppercased())
                    .font(NativeTypography.cartographicLabel(.caption2, weight: .bold))
                    .foregroundStyle(card.accent)
                    .tracking(1.3)

                Text(card.title)
                    .font(NativeTypography.mastheadTitle(.title2))
                    .foregroundStyle(NativeWarRoomTheme.ink)
                    .multilineTextAlignment(.center)
            }

            Text(card.body)
                .font(NativeTypography.body(.callout))
                .foregroundStyle(NativeWarRoomTheme.mutedInk)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 24)
        }
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var progressPips: some View {
        HStack(spacing: 8) {
            ForEach(cards) { card in
                Button {
                    if reduceMotion {
                        page = card.id
                    } else {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            page = card.id
                        }
                    }
                } label: {
                    Capsule()
                        .fill(page == card.id ? NativeWarRoomTheme.brass : NativeWarRoomTheme.mutedInk.opacity(0.28))
                        .frame(width: page == card.id ? 26 : 8, height: 6)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Briefing \(card.id + 1)")
            }
        }
    }

    private var footerControls: some View {
        HStack(spacing: 12) {
            Button("Skip") {
                isPresented = false
            }
            .font(NativeTypography.cartographicLabel(.caption, weight: .bold))
            .foregroundStyle(NativeWarRoomTheme.mutedInk)
            .buttonStyle(.bordered)
            .tint(NativeWarRoomTheme.brass.opacity(0.35))
            .accessibilityIdentifier("native-onboarding-skip")

            Spacer()

            if page > 0 {
                Button {
                    if reduceMotion {
                        page -= 1
                    } else {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            page -= 1
                        }
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.caption.weight(.bold))
                }
                .buttonStyle(.bordered)
                .tint(NativeWarRoomTheme.brass.opacity(0.45))
                .accessibilityLabel("Previous briefing")
            }

            if page < cards.count - 1 {
                Button {
                    if reduceMotion {
                        page += 1
                    } else {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            page += 1
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text("Next")
                        Image(systemName: "arrow.right")
                    }
                    .font(NativeTypography.cartographicLabel(.caption, weight: .bold))
                }
                .buttonStyle(.borderedProminent)
                .tint(NativeWarRoomTheme.brass)
                .foregroundStyle(NativeWarRoomTheme.blackboard)
                .accessibilityIdentifier("native-onboarding-next")
            } else {
                Button {
                    isPresented = false
                } label: {
                    HStack(spacing: 6) {
                        Text("Got it")
                        Image(systemName: "checkmark")
                    }
                    .font(NativeTypography.cartographicLabel(.caption, weight: .bold))
                }
                .buttonStyle(.borderedProminent)
                .tint(NativeWarRoomTheme.brass)
                .foregroundStyle(NativeWarRoomTheme.blackboard)
                .accessibilityIdentifier("native-onboarding-got-it")
            }
        }
    }
}
