import MapKit
import SwiftUI

struct ErrorBanner: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.callout)
            .foregroundStyle(Color.softRed)
            .fixedSize(horizontal: false, vertical: true)
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.softRed.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.softRed.opacity(0.24), lineWidth: 1)
            }
            .accessibilityIdentifier("native-apple-error")
    }
}

struct SuggestionWarning: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle")
            .font(.caption)
            .foregroundStyle(Color.alertGold)
            .fixedSize(horizontal: false, vertical: true)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.alertGold.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.alertGold.opacity(0.24), lineWidth: 1)
            }
            .accessibilityIdentifier("native-apple-suggestion-warning")
    }
}

struct VictoryDefeatOverlay: View {
    let status: NativeVictoryStatus
    let scenarioName: String
    let rivalName: String?
    let onExit: () -> Void

    private var resolvedRivalName: String {
        rivalName ?? "A rival power"
    }

    private var statusAccent: Color {
        status == .won ? NativeWarRoomTheme.fieldGreen : NativeWarRoomTheme.threatRed
    }

    var body: some View {
        ZStack {
            NativeWarRoomTheme.blackboard.opacity(0.88)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Image(status == .won ? "VictoryTriumph" : "DefeatCollapse")
                    .resizable()
                    .aspectRatio(16 / 9, contentMode: .fill)
                    .frame(height: 168)
                    .overlay {
                        LinearGradient(
                            colors: [
                                NativeWarRoomTheme.blackboard.opacity(0.14),
                                NativeWarRoomTheme.brass.opacity(0.08),
                                NativeWarRoomTheme.blackboard.opacity(0.72)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(NativeWarRoomTheme.brass.opacity(0.42), lineWidth: 1.5)
                    }
                    .shadow(color: statusAccent.opacity(0.28), radius: 10)

                HStack(spacing: 8) {
                    Image(systemName: status == .won ? "trophy.fill" : "exclamationmark.octagon.fill")
                        .font(.headline)
                        .foregroundStyle(statusAccent)
                    Text(status == .won ? "STRATEGIC TRIUMPH" : "CRISIS CONCLUSION")
                        .font(NativeWarRoomTheme.labelFont(.caption, weight: .bold))
                        .foregroundStyle(statusAccent)
                        .tracking(1.5)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(statusAccent.opacity(0.14), in: Capsule())
                .overlay {
                    Capsule().stroke(statusAccent.opacity(0.32), lineWidth: 1)
                }

                VStack(spacing: 6) {
                    Text(status == .won
                        ? "CAMPAIGN VICTORY ACHIEVED"
                        : (status == .lostCollapse
                            ? "NATION COLLAPSED"
                            : (status == .lostRival ? "RIVAL VICTORY: \(resolvedRivalName.uppercased())" : "CAMPAIGN DEFEAT")))
                        .font(NativeWarRoomTheme.displayFont(.title2, weight: .bold))
                        .foregroundStyle(NativeWarRoomTheme.ink)
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier("native-terminal-title")

                    Text("Scenario: \(scenarioName)")
                        .font(NativeWarRoomTheme.labelFont(.caption, weight: .semibold))
                        .foregroundStyle(NativeWarRoomTheme.brass)
                }

                Rectangle()
                    .fill(NativeWarRoomTheme.brass.opacity(0.22))
                    .frame(height: 1)
                    .padding(.horizontal, 16)

                Text(status == .won
                    ? "Congratulations, Leader! Your administration has successfully met all scenario conditions and navigated the complex geopolitical landscape to achieve total victory."
                    : (status == .lostCollapse
                        ? "Sovereign Collapse: Civil order has broken down, and stability has hit zero. Your administration has been terminated."
                        : (status == .lostRival
                            ? "Campaign Defeat: \(resolvedRivalName) completed the active scenario objectives before your administration secured its own victory."
                            : "Campaign Defeat: The timeline has expired before you could meet all strategic scenario criteria.")))
                    .font(NativeWarRoomTheme.bodyFont(.body))
                    .foregroundStyle(NativeWarRoomTheme.parchment.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 18)
                    .fixedSize(horizontal: false, vertical: true)

                Button(action: onExit) {
                    HStack {
                        Spacer()
                        Image(systemName: "arrow.left.circle.fill")
                        Text("EXIT TO MAIN MENU")
                            .font(NativeWarRoomTheme.labelFont(.body, weight: .bold))
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(statusAccent.opacity(0.2))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(statusAccent, lineWidth: 1.5)
                }
                .foregroundStyle(NativeWarRoomTheme.ink)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 28)
                .accessibilityIdentifier("native-victory-exit")
            }
            .padding(28)
            .warRoomDossier(borderColor: statusAccent.opacity(0.4), cornerRadius: 18)
            .frame(maxWidth: 460)
            .padding(16)
        }
    }
}

extension Color {
    static func lerp(from: Color, to: Color, fraction: Double) -> Color {
        let f = max(0.0, min(1.0, fraction))
        let fromC = from.components
        let toC = to.components
        return Color(
            red: fromC.red * (1.0 - f) + toC.red * f,
            green: fromC.green * (1.0 - f) + toC.green * f,
            blue: fromC.blue * (1.0 - f) + toC.blue * f,
            opacity: fromC.opacity * (1.0 - f) + toC.opacity * f
        )
    }

    var components: (red: Double, green: Double, blue: Double, opacity: Double) {
        #if canImport(UIKit)
            typealias NativeColor = UIColor
        #elseif canImport(AppKit)
            typealias NativeColor = NSColor
        #endif

        let native = NativeColor(self)
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0

        #if canImport(UIKit)
            native.getRed(&r, green: &g, blue: &b, alpha: &a)
        #elseif canImport(AppKit)
            if let rgbColor = native.usingColorSpace(.sRGB) {
                rgbColor.getRed(&r, green: &g, blue: &b, alpha: &a)
            } else {
                r = 0.5; g = 0.5; b = 0.5; a = 1.0
            }
        #endif

        return (Double(r), Double(g), Double(b), Double(a))
    }
}
