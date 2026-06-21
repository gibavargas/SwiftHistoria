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
        // This view owns document presentation only. Campaign semantics stay in
        // `NativeCampaignStore`, which keeps import/export, validation, and
        // persistence behavior consistent across iOS and macOS.
        ZStack {
            NativeGameShell(
                store: store,
                libraryMessage: libraryMessage,
                onExportCampaign: prepareCampaignExport,
                onImportCampaign: { isImportingCampaign = true }
            )

            if let state = store.state, state.victoryStatus != .ongoing {
                VictoryDefeatOverlay(
                    status: state.victoryStatus,
                    scenarioName: state.scenarioName,
                    onExit: { store.exitToMainMenu() }
                )
                .transition(.opacity)
            }
        }
        .fileExporter(
            isPresented: $isExportingCampaign,
            document: campaignDocument,
            contentType: .json,
            defaultFilename: store.campaignExportFilename
        ) { result in
            switch result {
            case .success:
                libraryMessage = "Campaign exported."
            case let .failure(error):
                libraryMessage = error.localizedDescription
            }
        }
        .fileImporter(isPresented: $isImportingCampaign, allowedContentTypes: [.json]) { result in
            importCampaign(from: result)
        }
        .sheet(isPresented: Binding<Bool>(
            get: { store.lastTurnReport != nil },
            set: { show in
                if !show {
                    store.lastTurnReport = nil
                }
            }
        )) {
            if let report = store.lastTurnReport {
                NativeTurnReportView(report: report) {
                    store.lastTurnReport = nil
                }
            }
        }
    }

    private func prepareCampaignExport() {
        do {
            campaignDocument = try NativeCampaignDocument(data: store.exportCampaignData())
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

            if let byteCount = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
               byteCount > NativeCampaignStore.maximumCampaignImportBytes
            {
                throw NativeCampaignStoreError.campaignImportTooLarge(
                    actualBytes: byteCount,
                    maximumBytes: NativeCampaignStore.maximumCampaignImportBytes
                )
            }
            try store.importCampaignData(Data(contentsOf: url))
            libraryMessage = "Imported \(store.state?.scenarioName ?? "campaign") for \(store.state?.country.name ?? "player")."
        } catch {
            libraryMessage = error.localizedDescription
        }
    }
}

private struct NativeCampaignDocument: FileDocument {
    static var readableContentTypes: [UTType] {
        [.json]
    }

    var data: Data

    init(data: Data = Data("{}".utf8)) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration _: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

enum SectorRelation {
    case player
    case ally
    case neutral
    case rival
}

enum NativeWarRoomMapLayer: String, CaseIterable, Identifiable {
    case relations
    case conflicts
    case economy
    case fallout

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .relations: "Relations"
        case .conflicts: "Conflicts"
        case .economy: "Economy"
        case .fallout: "Fallout"
        }
    }
}
