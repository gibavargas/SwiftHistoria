import Foundation
import MapKit
import SwiftUI
import UniformTypeIdentifiers

struct NativeGameView: View {
    @ObservedObject var store: NativeCampaignStore
    @State private var campaignDocument = NativeCampaignDocument()
    @State private var isExportingCampaign = false
    @State private var isImportingCampaign = false
    @State private var libraryMessage: String?

    var body: some View {
        NativeGameShell(
            store: store,
            libraryMessage: libraryMessage,
            onExportCampaign: prepareCampaignExport,
            onImportCampaign: { isImportingCampaign = true }
        )
            .fileExporter(
                isPresented: $isExportingCampaign,
                document: campaignDocument,
                contentType: .json,
                defaultFilename: store.campaignExportFilename
            ) { result in
                switch result {
                case .success:
                    libraryMessage = "Campaign exported."
                case .failure(let error):
                    libraryMessage = error.localizedDescription
                }
            }
            .fileImporter(isPresented: $isImportingCampaign, allowedContentTypes: [.json]) { result in
                importCampaign(from: result)
            }
    }

    private func prepareCampaignExport() {
        do {
            campaignDocument = NativeCampaignDocument(data: try store.exportCampaignData())
            libraryMessage = nil
            isExportingCampaign = true
        } catch {
            libraryMessage = error.localizedDescription
        }
    }

    private func importCampaign(from result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let didAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            try store.importCampaignData(Data(contentsOf: url))
            libraryMessage = "Imported \(store.state?.scenarioName ?? "campaign") for \(store.state?.country.name ?? "player")."
        } catch {
            libraryMessage = error.localizedDescription
        }
    }

}

private struct NativeCampaignDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var data: Data

    init(data: Data = Data("{}".utf8)) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct NativeWorldMap: View {
    let state: NativeCampaignState
    let minHeight: CGFloat

    private let coordinate: CLLocationCoordinate2D
    private let region: MKCoordinateRegion
    @State private var cameraPosition: MapCameraPosition

    init(state: NativeCampaignState, minHeight: CGFloat = 300) {
        self.state = state
        self.minHeight = minHeight
        coordinate = CountryCoordinate.center(for: state.country.code)
        let span = state.country.code == "ATA"
            ? MKCoordinateSpan(latitudeDelta: 80, longitudeDelta: 160)
            : MKCoordinateSpan(latitudeDelta: 34, longitudeDelta: 48)
        region = MKCoordinateRegion(center: coordinate, span: span)
        _cameraPosition = State(initialValue: .region(region))
    }

    var body: some View {
        Map(position: $cameraPosition) {
            Marker(state.country.name, systemImage: "flag.fill", coordinate: coordinate)
        }
        .mapStyle(.standard(elevation: .realistic))
        .frame(minHeight: minHeight)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            StrategicMapGrid()
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .overlay(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Strategic Map")
                    .font(.caption)
                    .fontWeight(.bold)
                    .textCase(.uppercase)
                    .tracking(1.6)
                Text("\(state.country.name) focus · \(state.worldTension)/100 world tension")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .padding(12)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        }
        .accessibilityIdentifier("native-strategic-map")
        .accessibilityLabel("Strategic map centered on \(state.country.name)")
        .accessibilityHint("Shows the selected country focus area and current world tension.")
    }
}

struct StrategicMapGrid: View {
    @State private var pulsePhase: CGFloat = 0.0

    var body: some View {
        Canvas { context, size in
            var grid = Path()
            for index in 1..<6 {
                let x = size.width * CGFloat(index) / 6
                grid.move(to: CGPoint(x: x, y: 0))
                grid.addLine(to: CGPoint(x: x, y: size.height))
            }
            for index in 1..<4 {
                let y = size.height * CGFloat(index) / 4
                grid.move(to: CGPoint(x: 0, y: y))
                grid.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(grid, with: .color(.white.opacity(0.08)), lineWidth: 1)

            let focus = CGPoint(x: size.width * 0.52, y: size.height * 0.45)
            let baseScales = [0.12, 0.22, 0.34]
            for radiusScale in baseScales {
                let animatedScale = radiusScale + (pulsePhase * 0.06)
                let radius = min(size.width, size.height) * animatedScale
                let rect = CGRect(
                    x: focus.x - radius,
                    y: focus.y - radius,
                    width: radius * 2,
                    height: radius * 2
                )
                let baseOpacity = 0.18 - (animatedScale * 0.22)
                context.stroke(Path(ellipseIn: rect), with: .color(.cyan.opacity(max(0.02, baseOpacity))), lineWidth: 1)
            }
        }
        .background(
            LinearGradient(
                colors: [.cyan.opacity(0.06), .clear, .blue.opacity(0.07)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .blendMode(.screen)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            withAnimation(.linear(duration: 5.0).repeatForever(autoreverses: false)) {
                pulsePhase = 1.0
            }
        }
    }
}

struct ErrorBanner: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.callout)
            .foregroundStyle(.red)
            .fixedSize(horizontal: false, vertical: true)
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .accessibilityIdentifier("native-apple-error")
    }
}

struct SuggestionWarning: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle")
            .font(.caption)
            .foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .accessibilityIdentifier("native-apple-suggestion-warning")
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.title3)
                    .fontWeight(.bold)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct SuggestedActionRow: View {
    let suggestion: NativeSuggestedAction
    let onUse: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(suggestion.title)
                        .fontWeight(.semibold)
                    Text(suggestion.urgency.capitalized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    onUse()
                } label: {
                    Label("Use", systemImage: "plus.circle")
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("native-use-suggestion-\(suggestion.id)")
            }

            Text(suggestion.detail)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)

            Text(suggestion.rationale)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct AdvisorMessageRow: View {
    let message: NativeAdvisorMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(message.role == .advisor ? "Advisor" : "Leader")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(message.role == .advisor ? .blue : .secondary)
            Text(message.text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Text(message.date)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityIdentifier("native-advisor-message-\(message.id)")
    }
}

struct DiplomacyMessageRow: View {
    let message: NativeDiplomaticMessage
    let isPlayer: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(message.speaker)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(isPlayer ? .green : .purple)
            Text(message.text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Text(message.date)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isPlayer ? .green.opacity(0.10) : .purple.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityIdentifier("native-diplomacy-message-\(message.id)")
    }
}

struct ActionRow: View {
    let action: NativePlannedAction
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: action.status == .resolved ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(action.status == .resolved ? .green : .secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(action.title)
                    .fontWeight(.semibold)
                Text(action.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            Button(role: .destructive) {
                onDelete()
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Delete order \(action.title)")
            .accessibilityIdentifier("native-delete-order-\(action.id)")
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct EventCard: View {
    let event: NativeCampaignEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(event.title)
                        .font(.headline)
                    Text("\(event.date) · \(event.kind.rawValue) · \(event.importance.rawValue)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(event.playerRelated ? "Player" : "World")
                    .font(.caption)
                    .fontWeight(.bold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(event.playerRelated ? .blue.opacity(0.22) : .purple.opacity(0.22), in: Capsule())
            }

            Text(event.description)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            if !event.strategicEffects.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(event.strategicEffects) { effect in
                        HStack(alignment: .top, spacing: 8) {
                            Text(effect.magnitude > 0 ? "+\(effect.magnitude)" : "\(effect.magnitude)")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundStyle(effect.magnitude >= 0 ? .green : .red)
                                .frame(width: 34, alignment: .trailing)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(effect.track.rawValue)
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                Text(effect.summary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
