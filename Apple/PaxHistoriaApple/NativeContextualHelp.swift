import SwiftUI

/// First-run in-game contextual help overlay. Shows a brief 3-card walkthrough
/// of the main panels on the player's first time entering a campaign.
struct NativeContextualHelpOverlay: View {
    @Binding var isPresented: Bool
    @State private var page = 0

    private let cards: [(title: String, icon: String, body: String)] = [
        ("Map", "globe.europe.africa",
         "Tap any region to see terrain, stability, and conflict details. Your nation is highlighted in cyan."),
        ("Orders", "checklist",
         "Add policy orders by typing or using Quick Actions below the editor. Orders run when you advance the turn."),
        ("Advisor", "brain.head.profile",
         "Ask the AI advisor for assessments of threats, stability, or opportunities. Check Diplomacy to negotiate with other nations.")
    ]

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                ForEach(Array(cards.enumerated()), id: \.offset) { index, card in
                    VStack(spacing: 20) {
                        Image(systemName: card.icon)
                            .font(.system(size: 56))
                            .foregroundStyle(Color.glowingCyan)

                        Text(card.title)
                            .font(.title.weight(.bold))

                        Text(card.body)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 24)
                    }
                    .tag(index)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            #if os(iOS)
            .tabViewStyle(.page(indexDisplayMode: .always))
            #endif
            .frame(height: 320)

            HStack(spacing: 12) {
                Button("Skip") {
                    isPresented = false
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("native-onboarding-skip")

                Spacer()

                if page < cards.count - 1 {
                    Button("Next") {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            page += 1
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.glowingCyan)
                    .foregroundStyle(.black)
                    .accessibilityIdentifier("native-onboarding-next")
                } else {
                    Button("Got it") {
                        isPresented = false
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.glowingCyan)
                    .foregroundStyle(.black)
                    .accessibilityIdentifier("native-onboarding-got-it")
                }
            }
            .padding(20)
        }
    }
}
