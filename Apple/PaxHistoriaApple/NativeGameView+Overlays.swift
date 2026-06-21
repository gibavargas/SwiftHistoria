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
    let onExit: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.85)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Image(systemName: status == .won ? "trophy.fill" : "exclamationmark.octagon.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(status == .won ? Color.neonTeal : Color.softRed)
                    .shadow(color: status == .won ? Color.neonTeal.opacity(0.4) : Color.softRed.opacity(0.4), radius: 10)

                VStack(spacing: 8) {
                    Text(status == .won ? "CAMPAIGN VICTORY ACHIEVED" : (status == .lostCollapse ? "NATION COLLAPSED" : "CAMPAIGN DEFEAT"))
                        .font(.system(.title2, design: .monospaced).weight(.bold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)

                    Text("Scenario: \(scenarioName)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Text(status == .won
                    ? "Congratulations, Leader! Your administration has successfully met all scenario conditions and navigated the complex geopolitical landscape to achieve total victory."
                    : (status == .lostCollapse
                        ? "Sovereign Collapse: Civil order has broken down, and stability has hit zero. Your administration has been terminated."
                        : "Campaign Defeat: The timeline has expired before you could meet all strategic scenario criteria."))
                    .font(.body)
                    .foregroundStyle(.primary.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .fixedSize(horizontal: false, vertical: true)

                Button(action: onExit) {
                    HStack {
                        Spacer()
                        Image(systemName: "arrow.left.circle.fill")
                        Text("EXIT TO MAIN MENU")
                            .font(.system(.body, design: .monospaced).weight(.bold))
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(status == .won ? Color.neonTeal.opacity(0.2) : Color.softRed.opacity(0.2))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(status == .won ? Color.neonTeal : Color.softRed, lineWidth: 1.5)
                }
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 32)
            }
            .padding(30)
            .glassmorphicCard(borderColor: status == .won ? Color.neonTeal.opacity(0.3) : Color.softRed.opacity(0.3), cornerRadius: 20)
            .frame(maxWidth: 450)
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
