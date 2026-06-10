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
                case .failure(let error):
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

struct GlobalSector: Identifiable {
    var id: String { code }
    let name: String
    let code: String
    let coordinate: CLLocationCoordinate2D
    let stability: Int
    let relation: SectorRelation
}

enum SectorRelation {
    case player
    case ally
    case neutral
    case rival
}

struct SectorAnnotationBadge: View {
    let sector: GlobalSector
    let playerCountryCode: String

    private var color: Color {
        switch sector.relation {
        case .player: return Color.glowingCyan
        case .ally: return Color.neonTeal
        case .neutral: return Color.alertGold
        case .rival: return Color.softRed
        }
    }

    var body: some View {
        VStack(spacing: 2) {
            Text(sector.name.uppercased())
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .shadow(radius: 1)

            HStack(spacing: 4) {
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)

                Text("\(sector.stability)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(color)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.deepSlate.opacity(0.85))
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .stroke(color.opacity(0.4), lineWidth: 1)
            }
        }
        .padding(6)
        .glassmorphicCard(borderColor: color.opacity(0.2), cornerRadius: 8)
        .shadow(color: color.opacity(0.15), radius: 6, x: 0, y: 3)
    }
}

struct LegendItem: View {
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(text)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }
}

struct NativeWorldMap: View {
    @EnvironmentObject var store: NativeCampaignStore
    let state: NativeCampaignState
    let minHeight: CGFloat

    @State private var selectedRegionID: String? = nil
    @State private var animationPhase: CGFloat = 0.0
    @State private var zoomScale: CGFloat = 1.0
    @State private var lastZoomScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    private let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    init(state: NativeCampaignState, minHeight: CGFloat = 300) {
        self.state = state
        self.minHeight = minHeight
    }

    private func clampOffset(_ offset: CGSize, size: CGSize, zoom: CGFloat) -> CGSize {
        guard zoom > 1.0 else { return .zero }
        let maxX = (zoom - 1.0) * size.width / 2.0 + 100.0
        let maxY = (zoom - 1.0) * size.height / 2.0 + 100.0
        return CGSize(
            width: max(-maxX, min(maxX, offset.width)),
            height: max(-maxY, min(maxY, offset.height))
        )
    }

    private func reverseTransform(_ location: CGPoint, size: CGSize, scaleX: CGFloat, scaleY: CGFloat) -> CGPoint {
        let pannedX = location.x - offset.width
        let pannedY = location.y - offset.height

        let centerX = size.width / 2.0
        let centerY = size.height / 2.0

        let unzoomedX = centerX + (pannedX - centerX) / zoomScale
        let unzoomedY = centerY + (pannedY - centerY) / zoomScale

        return CGPoint(
            x: unzoomedX / scaleX,
            y: unzoomedY / scaleY
        )
    }

    private func drawGridLines(context: GraphicsContext, size: CGSize) {
        let stepX: CGFloat = size.width / 12.0
        let stepY: CGFloat = size.height / 8.0
        var gridPath = Path()

        for x in stride(from: stepX, to: size.width, by: stepX) {
            gridPath.move(to: CGPoint(x: x, y: 0))
            gridPath.addLine(to: CGPoint(x: x, y: size.height))
        }

        for y in stride(from: stepY, to: size.height, by: stepY) {
            gridPath.move(to: CGPoint(x: 0, y: y))
            gridPath.addLine(to: CGPoint(x: size.width, y: y))
        }

        context.stroke(
            gridPath,
            with: .color(Color.iceBlue.opacity(0.06)),
            style: StrokeStyle(lineWidth: 1.0, dash: [4, 4])
        )
    }

    private func drawOceanWaves(context: GraphicsContext, scaleX: CGFloat, scaleY: CGFloat) {
        let waveCenters: [CGPoint] = [
            CGPoint(x: 300, y: 300),
            CGPoint(x: 100, y: 250),
            CGPoint(x: 150, y: 400),
            CGPoint(x: 880, y: 220),
            CGPoint(x: 910, y: 420),
            CGPoint(x: 650, y: 450)
        ]

        for center in waveCenters {
            let cx = center.x * scaleX
            let cy = center.y * scaleY
            let drift = sin(animationPhase * 0.05) * 4.0

            var wavePath = Path()
            wavePath.move(to: CGPoint(x: cx - 15 + drift, y: cy))
            wavePath.addQuadCurve(
                to: CGPoint(x: cx + drift, y: cy),
                control: CGPoint(x: cx - 7.5 + drift, y: cy - 4)
            )
            wavePath.addQuadCurve(
                to: CGPoint(x: cx + 15 + drift, y: cy),
                control: CGPoint(x: cx + 7.5 + drift, y: cy - 4)
            )

            context.stroke(
                wavePath,
                with: .color(Color.iceBlue.opacity(0.12)),
                style: StrokeStyle(lineWidth: 1.2, lineCap: .round)
            )
        }
    }

    private func drawTerrainIcon(context: GraphicsContext, terrain: NativeTerrainType, center: CGPoint, scaleX: CGFloat, scaleY: CGFloat) {
        let cx = center.x * scaleX
        let cy = center.y * scaleY
        var iconPath = Path()

        switch terrain {
        case .mountain:
            iconPath.move(to: CGPoint(x: cx, y: cy - 8))
            iconPath.addLine(to: CGPoint(x: cx - 8, y: cy + 6))
            iconPath.addLine(to: CGPoint(x: cx + 8, y: cy + 6))
            iconPath.closeSubpath()
            iconPath.move(to: CGPoint(x: cx - 3, y: cy - 2))
            iconPath.addLine(to: CGPoint(x: cx + 3, y: cy - 2))
            iconPath.addLine(to: CGPoint(x: cx, y: cy - 8))
            iconPath.closeSubpath()

        case .forest:
            iconPath.move(to: CGPoint(x: cx - 4, y: cy - 6))
            iconPath.addLine(to: CGPoint(x: cx - 8, y: cy + 2))
            iconPath.addLine(to: CGPoint(x: cx - 6, y: cy + 2))
            iconPath.addLine(to: CGPoint(x: cx - 6, y: cy + 5))
            iconPath.addLine(to: CGPoint(x: cx - 2, y: cy + 5))
            iconPath.addLine(to: CGPoint(x: cx - 2, y: cy + 2))
            iconPath.addLine(to: CGPoint(x: cx, y: cy + 2))
            iconPath.closeSubpath()

            iconPath.move(to: CGPoint(x: cx + 4, y: cy - 3))
            iconPath.addLine(to: CGPoint(x: cx, y: cy + 4))
            iconPath.addLine(to: CGPoint(x: cx + 2, y: cy + 4))
            iconPath.addLine(to: CGPoint(x: cx + 2, y: cy + 7))
            iconPath.addLine(to: CGPoint(x: cx + 6, y: cy + 7))
            iconPath.addLine(to: CGPoint(x: cx + 6, y: cy + 4))
            iconPath.addLine(to: CGPoint(x: cx + 8, y: cy + 4))
            iconPath.closeSubpath()

        case .city:
            iconPath.move(to: CGPoint(x: cx - 8, y: cy + 6))
            iconPath.addLine(to: CGPoint(x: cx - 8, y: cy - 2))
            iconPath.addLine(to: CGPoint(x: cx - 4, y: cy - 2))
            iconPath.addLine(to: CGPoint(x: cx - 4, y: cy - 6))
            iconPath.addLine(to: CGPoint(x: cx, y: cy - 6))
            iconPath.addLine(to: CGPoint(x: cx, y: cy + 1))
            iconPath.addLine(to: CGPoint(x: cx + 4, y: cy + 1))
            iconPath.addLine(to: CGPoint(x: cx + 4, y: cy - 4))
            iconPath.addLine(to: CGPoint(x: cx + 8, y: cy - 4))
            iconPath.addLine(to: CGPoint(x: cx + 8, y: cy + 6))
            iconPath.closeSubpath()

        case .swamp:
            iconPath.move(to: CGPoint(x: cx - 6, y: cy))
            iconPath.addQuadCurve(to: CGPoint(x: cx + 6, y: cy), control: CGPoint(x: cx, y: cy + 2))
            iconPath.move(to: CGPoint(x: cx - 4, y: cy + 4))
            iconPath.addQuadCurve(to: CGPoint(x: cx + 4, y: cy + 4), control: CGPoint(x: cx, y: cy + 6))
            iconPath.move(to: CGPoint(x: cx, y: cy + 2))
            iconPath.addLine(to: CGPoint(x: cx - 2, y: cy - 6))
            iconPath.move(to: CGPoint(x: cx, y: cy + 2))
            iconPath.addLine(to: CGPoint(x: cx + 2, y: cy - 4))

        case .cerrado:
            iconPath.move(to: CGPoint(x: cx - 4, y: cy + 5))
            iconPath.addQuadCurve(to: CGPoint(x: cx - 2, y: cy - 5), control: CGPoint(x: cx - 5, y: cy))
            iconPath.move(to: CGPoint(x: cx, y: cy + 5))
            iconPath.addQuadCurve(to: CGPoint(x: cx + 1, y: cy - 7), control: CGPoint(x: cx - 1, y: cy - 1))
            iconPath.move(to: CGPoint(x: cx + 4, y: cy + 5))
            iconPath.addQuadCurve(to: CGPoint(x: cx + 3, y: cy - 3), control: CGPoint(x: cx + 4, y: cy + 1))

        case .strait:
            iconPath.move(to: CGPoint(x: cx - 8, y: cy))
            iconPath.addLine(to: CGPoint(x: cx + 8, y: cy))
            iconPath.move(to: CGPoint(x: cx - 8, y: cy))
            iconPath.addLine(to: CGPoint(x: cx - 5, y: cy - 4))
            iconPath.move(to: CGPoint(x: cx - 8, y: cy))
            iconPath.addLine(to: CGPoint(x: cx - 5, y: cy + 4))
            iconPath.move(to: CGPoint(x: cx + 8, y: cy))
            iconPath.addLine(to: CGPoint(x: cx + 5, y: cy - 4))
            iconPath.move(to: CGPoint(x: cx + 8, y: cy))
            iconPath.addLine(to: CGPoint(x: cx + 5, y: cy + 4))

        default:
            return
        }

        context.stroke(iconPath, with: .color(Color.iceBlue.opacity(0.65)), lineWidth: 1.2)
    }

    private func sectorRelation(code: String, playerCode: String) -> SectorRelation {
        if code == playerCode { return .player }

        let sectors = Native2010WorldModel.mapSectors(for: state)
        if let sector = sectors.first(where: { $0.code == code }) {
            switch sector.relation {
            case .ally, .partner:
                return .ally
            case .rival:
                return .rival
            case .neutral, .watch:
                return .neutral
            }
        }
        return .neutral
    }

    private func relationColor(_ relation: SectorRelation) -> Color {
        switch relation {
        case .player: return Color.glowingCyan
        case .ally: return Color.neonTeal
        case .neutral: return Color.alertGold
        case .rival: return Color.softRed
        }
    }

    private func drawDiagonalStripes(context: GraphicsContext, path: Path, size: CGSize, occupierColor: Color, originalColor: Color) {
        var context = context
        context.fill(path, with: .color(occupierColor.opacity(0.35)))
        context.clip(to: path)

        let bounds = path.boundingRect
        let spacing: CGFloat = 12
        let strokeWidth: CGFloat = 2.5
        var stripePath = Path()

        for x in stride(from: bounds.minX - bounds.height, to: bounds.maxX, by: spacing) {
            stripePath.move(to: CGPoint(x: x, y: bounds.minY))
            stripePath.addLine(to: CGPoint(x: x + bounds.height, y: bounds.maxY))
        }

        context.stroke(stripePath, with: .color(originalColor.opacity(0.5)), lineWidth: strokeWidth)
    }

    private func drawNuclearHazardStripes(context: GraphicsContext, path: Path) {
        var context = context
        context.fill(path, with: .color(Color.alertGold.opacity(0.45)))
        context.clip(to: path)

        let bounds = path.boundingRect
        let spacing: CGFloat = 8
        let strokeWidth: CGFloat = 3.0
        var stripePath = Path()

        for x in stride(from: bounds.minX - bounds.height, to: bounds.maxX, by: spacing) {
            stripePath.move(to: CGPoint(x: x, y: bounds.minY))
            stripePath.addLine(to: CGPoint(x: x + bounds.height, y: bounds.maxY))
        }

        context.stroke(stripePath, with: .color(Color.black.opacity(0.75)), lineWidth: strokeWidth)
    }

    private func drawRebelStripes(context: GraphicsContext, path: Path) {
        var context = context
        context.fill(path, with: .color(Color.black.opacity(0.65)))
        context.clip(to: path)

        let bounds = path.boundingRect
        let spacing: CGFloat = 10
        let strokeWidth: CGFloat = 2.5
        var stripePath = Path()

        for x in stride(from: bounds.minX - bounds.height, to: bounds.maxX, by: spacing) {
            stripePath.move(to: CGPoint(x: x, y: bounds.minY))
            stripePath.addLine(to: CGPoint(x: x + bounds.height, y: bounds.maxY))
        }

        context.stroke(stripePath, with: .color(Color.orange.opacity(0.7)), lineWidth: strokeWidth)
    }

    private func drawContestedBorder(context: GraphicsContext, path: Path, color: Color, intensity: Int) {
        context.stroke(
            path,
            with: .color(color.opacity(0.95)),
            style: StrokeStyle(
                lineWidth: CGFloat(max(2, min(5, intensity))),
                lineCap: .round,
                lineJoin: .round,
                dash: [4, 3],
                dashPhase: animationPhase
            )
        )
    }

    private func drawStabilizationOverlay(context: GraphicsContext, path: Path) {
        var context = context
        context.fill(path, with: .color(Color.neonTeal.opacity(0.18)))
        context.clip(to: path)

        let bounds = path.boundingRect
        let spacing: CGFloat = 14
        var linePath = Path()
        for y in stride(from: bounds.minY, through: bounds.maxY, by: spacing) {
            linePath.move(to: CGPoint(x: bounds.minX, y: y))
            linePath.addLine(to: CGPoint(x: bounds.maxX, y: y))
        }
        context.stroke(linePath, with: .color(Color.neonTeal.opacity(0.45)), lineWidth: 1.5)
    }

    private func conflictColor(_ conflict: NativeRegionConflictState) -> Color {
        switch conflict.mode {
        case .contestedBorder:
            return Color.alertGold
        case .conventionalOccupation:
            return Color.softRed
        case .guerrillaControl:
            return Color.orange
        case .nuclearFallout:
            return Color.alertGold
        case .stabilization:
            return Color.neonTeal
        }
    }

    private func drawRegion(
        context: GraphicsContext,
        reg: MapRegion,
        size: CGSize,
        scaleX: CGFloat,
        scaleY: CGFloat,
        selectedCountryCode: String?
    ) {
        let scaledPoints = reg.points.map { (pt: CGPoint) -> CGPoint in
            CGPoint(x: pt.x * scaleX, y: pt.y * scaleY)
        }
        var path = Path()
        path.addLines(scaledPoints)
        path.closeSubpath()

        let occupierCode = state.regionOccupations[reg.id] ?? reg.countryCode
        let conflict = state.regionConflicts[reg.id]
        let isPlayerCountry = reg.countryCode == state.country.code
        let isPlayerOccupier = occupierCode == state.country.code
        let isSelectedCountry = selectedCountryCode != nil && selectedCountryCode == reg.countryCode

        let relation = sectorRelation(code: occupierCode, playerCode: state.country.code)
        let stanceColor = relationColor(relation)

        let isOccupied = occupierCode != reg.countryCode
        let isContested = conflict?.mode == .contestedBorder

        if reg.countryCode == "WATER" {
            let waterBaseColor = Color(hex: "#0c1520")
            if isOccupied {
                let originalColor = waterBaseColor
                drawDiagonalStripes(context: context, path: path, size: size, occupierColor: stanceColor, originalColor: originalColor)
            } else {
                context.fill(path, with: .color(waterBaseColor))
            }

            let strokeColor = reg.id == selectedRegionID ? Color.glowingCyan : Color.iceBlue.opacity(0.25)
            context.stroke(path, with: .color(strokeColor), lineWidth: reg.id == selectedRegionID ? 2.0 : 1.0)

            if let conflict, isContested {
                drawContestedBorder(context: context, path: path, color: conflictColor(conflict), intensity: conflict.intensity)
            }
            return
        }

        var fillOpacity: Double = 0.22
        if isPlayerOccupier { fillOpacity = 0.38 }
        else if isSelectedCountry { fillOpacity = 0.3 }
        if reg.id == selectedRegionID { fillOpacity += 0.15 }

        let isFallout = state.nuclearFalloutRegions.contains(reg.id) || conflict?.mode == .nuclearFallout
        let isRebel = occupierCode == "REB" || conflict?.mode == .guerrillaControl
        let isStabilizing = conflict?.mode == .stabilization

        if isFallout {
            drawNuclearHazardStripes(context: context, path: path)
        } else if isRebel {
            drawRebelStripes(context: context, path: path)
        } else if isStabilizing {
            drawStabilizationOverlay(context: context, path: path)
        } else if isOccupied {
            let originalRelation = sectorRelation(code: reg.countryCode, playerCode: state.country.code)
            let originalColor = relationColor(originalRelation)
            drawDiagonalStripes(context: context, path: path, size: size, occupierColor: stanceColor, originalColor: originalColor)
        } else {
            context.fill(path, with: .color(stanceColor.opacity(fillOpacity)))
        }

        if isPlayerCountry || isSelectedCountry {
            let strokeColor = isPlayerCountry ? Color.glowingCyan : stanceColor
            let dashStyle = StrokeStyle(
                lineWidth: 2.0,
                lineCap: .round,
                lineJoin: .round,
                dash: [6, 4],
                dashPhase: animationPhase
            )
            context.stroke(path, with: .color(strokeColor), style: dashStyle)
        } else {
            context.stroke(path, with: .color(stanceColor.opacity(0.4)), lineWidth: 1.0)
        }

        if let conflict, isContested {
            drawContestedBorder(context: context, path: path, color: conflictColor(conflict), intensity: conflict.intensity)
        }
    }

    private func drawConflictRoutes(context: GraphicsContext, scaleX: CGFloat, scaleY: CGFloat) {
        for conflict in state.regionConflicts.values {
            guard let target = GeopoliticalMapData.regions.first(where: { $0.id == conflict.regionID }) else {
                continue
            }

            let targetPoint = CGPoint(x: target.center.x * scaleX, y: target.center.y * scaleY)
            let color = conflictColor(conflict)
            let radius = CGFloat(5 + conflict.intensity * 2)

            if conflict.mode == .nuclearFallout {
                let falloutRect = CGRect(
                    x: targetPoint.x - radius * 2,
                    y: targetPoint.y - radius * 2,
                    width: radius * 4,
                    height: radius * 4
                )
                context.stroke(Path(ellipseIn: falloutRect), with: .color(color.opacity(0.8)), lineWidth: 2)
                continue
            }

            if let source = GeopoliticalMapData.regions.first(where: {
                $0.countryCode == conflict.controllerCode && $0.id != conflict.regionID
            }) {
                let sourcePoint = CGPoint(x: source.center.x * scaleX, y: source.center.y * scaleY)
                var route = Path()
                route.move(to: sourcePoint)
                route.addLine(to: targetPoint)
                context.stroke(
                    route,
                    with: .color(color.opacity(0.72)),
                    style: StrokeStyle(
                        lineWidth: CGFloat(max(1, min(4, conflict.intensity))),
                        lineCap: .round,
                        dash: conflict.mode == .contestedBorder ? [5, 4] : [8, 5],
                        dashPhase: animationPhase
                    )
                )
            }

            let markerRect = CGRect(
                x: targetPoint.x - radius,
                y: targetPoint.y - radius,
                width: radius * 2,
                height: radius * 2
            )
            context.fill(Path(ellipseIn: markerRect), with: .color(color.opacity(0.26)))
            context.stroke(Path(ellipseIn: markerRect), with: .color(color.opacity(0.8)), lineWidth: 1.5)
        }
    }

    private func drawMap(context: GraphicsContext, size: CGSize, scaleX: CGFloat, scaleY: CGFloat) {
        // Draw coordinate grid lines and animated waves in the background
        drawGridLines(context: context, size: size)
        drawOceanWaves(context: context, scaleX: scaleX, scaleY: scaleY)

        // Draw continents
        for lm in GeopoliticalMapData.landmasses {
            let scaledPoints = lm.points.map { (pt: CGPoint) -> CGPoint in
                CGPoint(x: pt.x * scaleX, y: pt.y * scaleY)
            }
            var path = Path()
            path.addLines(scaledPoints)
            path.closeSubpath()

            context.fill(path, with: .color(Color(hex: "#121b28")))
            context.stroke(path, with: .color(Color.iceBlue.opacity(0.12)), lineWidth: 1.0)
        }

        let selectedCountryCode = selectedRegionID.flatMap { selID in
            GeopoliticalMapData.regions.first(where: { $0.id == selID })?.countryCode
        }

        // Draw countries / partitions
        for reg in GeopoliticalMapData.regions {
            drawRegion(
                context: context,
                reg: reg,
                size: size,
                scaleX: scaleX,
                scaleY: scaleY,
                selectedCountryCode: selectedCountryCode
            )
        }

        // Dynamic Level of Detail (LOD) terrain icons
        if zoomScale >= 1.5 {
            for reg in GeopoliticalMapData.regions {
                drawTerrainIcon(context: context, terrain: reg.terrain, center: reg.center, scaleX: scaleX, scaleY: scaleY)
            }
        }

        drawConflictRoutes(context: context, scaleX: scaleX, scaleY: scaleY)
    }

    @ViewBuilder
    private var regionDetailsOverlay: some View {
        if let regionID = selectedRegionID,
           let region = GeopoliticalMapData.regions.first(where: { $0.id == regionID }) {
            RegionDetailsCard(
                region: region,
                state: state,
                store: store,
                selectedRegionID: $selectedRegionID
            )
        }
    }

    @ViewBuilder
    private var scenarioHeaderOverlay: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(state.scenarioName)
                .font(.caption)
                .fontWeight(.bold)
                .textCase(.uppercase)
                .tracking(1.6)
            Text("\(state.gameDate) · \(state.worldTension)/100 world tension")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(12)
    }

    @ViewBuilder
    private var legendOverlay: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                LegendItem(text: "PLAYER", color: Color.glowingCyan)
                LegendItem(text: "ALLY", color: Color.neonTeal)
                LegendItem(text: "NEUTRAL", color: Color.alertGold)
                LegendItem(text: "RIVAL", color: Color.softRed)
            }
            HStack(spacing: 12) {
                LegendItem(text: "OCCUPIED", color: Color.softRed)
                LegendItem(text: "INSURGENCY", color: Color.orange)
                LegendItem(text: "NUCLEAR", color: Color.alertGold)
                LegendItem(text: "STABILIZING", color: Color.neonTeal)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.deepSlate.opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        }
        .padding(12)
    }

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                let size = geo.size
                let scaleX = size.width / 1000.0
                let scaleY = size.height / 600.0

                ZStack {
                    let dragGesture = DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let proposedOffset = CGSize(
                                width: lastOffset.width + value.translation.width,
                                height: lastOffset.height + value.translation.height
                            )
                            offset = clampOffset(proposedOffset, size: size, zoom: zoomScale)
                        }
                        .onEnded { value in
                            let dragDistance = sqrt(pow(value.translation.width, 2) + pow(value.translation.height, 2))
                            if dragDistance < 10 {
                                let clickPt = reverseTransform(value.location, size: size, scaleX: scaleX, scaleY: scaleY)
                                if let hitRegion = GeopoliticalMapData.regions.first(where: { region in
                                    let path = Path { p in
                                        p.addLines(region.points)
                                        p.closeSubpath()
                                    }
                                    return path.contains(clickPt)
                                }) {
                                    selectedRegionID = hitRegion.id
                                } else {
                                    selectedRegionID = nil
                                }
                            } else {
                                lastOffset = offset
                            }
                        }

                    let magnificationGesture = MagnificationGesture()
                        .onChanged { value in
                            zoomScale = max(1.0, min(lastZoomScale * value, 5.0))
                        }
                        .onEnded { value in
                            zoomScale = max(1.0, min(zoomScale, 5.0))
                            lastZoomScale = zoomScale
                            withAnimation(.easeOut(duration: 0.2)) {
                                offset = clampOffset(offset, size: size, zoom: zoomScale)
                                lastOffset = offset
                            }
                        }

                    // Map view Canvas
                    Canvas { context, size in
                        context.drawLayer { ctx in
                            ctx.translateBy(x: size.width / 2 + offset.width, y: size.height / 2 + offset.height)
                            ctx.scaleBy(x: zoomScale, y: zoomScale)
                            ctx.translateBy(x: -size.width / 2, y: -size.height / 2)
                            drawMap(context: ctx, size: size, scaleX: scaleX, scaleY: scaleY)
                        }
                    }
                    .frame(width: size.width, height: size.height)
                    .contentShape(Rectangle())
                    .gesture(
                        SimultaneousGesture(dragGesture, magnificationGesture)
                    )

                    // Floating Glassmorphic Zoom Controls
                    VStack(spacing: 8) {
                        Button {
                            withAnimation(.easeOut(duration: 0.2)) {
                                zoomScale = min(zoomScale + 0.5, 5.0)
                                lastZoomScale = zoomScale
                            }
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 14, weight: .bold))
                                .frame(width: 32, height: 32)
                                .background(Color.deepSlate.opacity(0.85))
                                .foregroundStyle(Color.iceBlue)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.15), lineWidth: 1))
                        }
                        .buttonStyle(.plain)

                        Button {
                            withAnimation(.easeOut(duration: 0.2)) {
                                zoomScale = max(zoomScale - 0.5, 1.0)
                                lastZoomScale = zoomScale
                                if zoomScale == 1.0 {
                                    offset = .zero
                                    lastOffset = .zero
                                } else {
                                    offset = clampOffset(offset, size: size, zoom: zoomScale)
                                    lastOffset = offset
                                }
                            }
                        } label: {
                            Image(systemName: "minus")
                                .font(.system(size: 14, weight: .bold))
                                .frame(width: 32, height: 32)
                                .background(Color.deepSlate.opacity(0.85))
                                .foregroundStyle(Color.iceBlue)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.15), lineWidth: 1))
                        }
                        .buttonStyle(.plain)

                        Button {
                            withAnimation(.easeOut(duration: 0.25)) {
                                zoomScale = 1.0
                                lastZoomScale = 1.0
                                offset = .zero
                                lastOffset = .zero
                            }
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 12, weight: .bold))
                                .frame(width: 32, height: 32)
                                .background(Color.deepSlate.opacity(0.85))
                                .foregroundStyle(Color.iceBlue)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.15), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(8)
                    .background(Color.deepSlate.opacity(0.4).blur(radius: 0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.1), lineWidth: 1))
                    .padding(16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                }
            }
            .frame(minHeight: minHeight)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(alignment: .bottom) {
                regionDetailsOverlay
            }
        }
        .frame(minHeight: minHeight)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(alignment: .topLeading) {
            scenarioHeaderOverlay
        }
        .overlay(alignment: .bottomLeading) {
            legendOverlay
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        }
        .onReceive(timer) { _ in
            animationPhase -= 2.0
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Strategic map centered on \(state.country.name) from a 2010 political baseline")
        .accessibilityHint("Shows selected country focus, 2010 alignments, and current world tension.")
        .accessibilityIdentifier("native-strategic-map")
    }
}

struct StrategicMapGrid: View {
    @State private var pulsePhase: CGFloat = 0.0

    var body: some View {
        Canvas { context, size in
            // Draw coordinate grid lines
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
            context.stroke(grid, with: .color(Color.iceBlue.opacity(0.06)), lineWidth: 0.75)

            // Focus area marker / crosshairs
            let focus = CGPoint(x: size.width * 0.52, y: size.height * 0.45)
            let crosshairSize: CGFloat = 8
            var crosshair = Path()
            crosshair.move(to: CGPoint(x: focus.x - crosshairSize, y: focus.y))
            crosshair.addLine(to: CGPoint(x: focus.x + crosshairSize, y: focus.y))
            crosshair.move(to: CGPoint(x: focus.x, y: focus.y - crosshairSize))
            crosshair.addLine(to: CGPoint(x: focus.x, y: focus.y + crosshairSize))
            context.stroke(crosshair, with: .color(Color.glowingCyan.opacity(0.35)), lineWidth: 1.25)

            // Corner brackets
            let margin: CGFloat = 8
            let bracketLength: CGFloat = 12
            var brackets = Path()

            // Top-left
            brackets.move(to: CGPoint(x: margin, y: margin + bracketLength))
            brackets.addLine(to: CGPoint(x: margin, y: margin))
            brackets.addLine(to: CGPoint(x: margin + bracketLength, y: margin))

            // Top-right
            brackets.move(to: CGPoint(x: size.width - margin - bracketLength, y: margin))
            brackets.addLine(to: CGPoint(x: size.width - margin, y: margin))
            brackets.addLine(to: CGPoint(x: size.width - margin, y: margin + bracketLength))

            // Bottom-left
            brackets.move(to: CGPoint(x: margin, y: size.height - margin - bracketLength))
            brackets.addLine(to: CGPoint(x: margin, y: size.height - margin))
            brackets.addLine(to: CGPoint(x: margin + bracketLength, y: size.height - margin))

            // Bottom-right
            brackets.move(to: CGPoint(x: size.width - margin - bracketLength, y: size.height - margin))
            brackets.addLine(to: CGPoint(x: size.width - margin, y: size.height - margin))
            brackets.addLine(to: CGPoint(x: size.width - margin, y: size.height - margin - bracketLength))

            context.stroke(brackets, with: .color(Color.iceBlue.opacity(0.25)), lineWidth: 1.25)

            // Pulsing target circles
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
                context.stroke(Path(ellipseIn: rect), with: .color(Color.glowingCyan.opacity(max(0.02, baseOpacity))), lineWidth: 1)
            }
        }
        .background(
            LinearGradient(
                colors: [Color.glowingCyan.opacity(0.04), Color.clear, Color.iceBlue.opacity(0.04)],
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

struct SuggestedActionRow: View {
    let suggestion: NativeSuggestedAction
    let onUse: () -> Void

    private var urgencyColors: (bg: Color, border: Color, text: Color) {
        switch suggestion.urgency.lowercased() {
        case "immediate":
            return (Color.softRed.opacity(0.12), Color.softRed.opacity(0.4), Color.softRed)
        case "soon":
            return (Color.alertGold.opacity(0.12), Color.alertGold.opacity(0.4), Color.alertGold)
        case "opportunistic":
            return (Color.neonTeal.opacity(0.12), Color.neonTeal.opacity(0.4), Color.neonTeal)
        default:
            return (Color.iceBlue.opacity(0.12), Color.iceBlue.opacity(0.4), Color.iceBlue)
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

struct RegionDetailsCard: View {
    let region: MapRegion
    let state: NativeCampaignState
    let store: NativeCampaignStore
    @Binding var selectedRegionID: String?

    private func terrainModifiersText(for terrain: NativeTerrainType) -> String {
        switch terrain {
        case .mountain: return "Defense +30% (Invasion -30%)"
        case .strait: return "Amphibious barrier (Invasion -25%)"
        case .swamp: return "Attrition +20% (Invasion -20%)"
        case .forest: return "Concealment +15% (Invasion -15%)"
        case .city: return "Urban fortification (Invasion -15%)"
        case .cerrado: return "Maneuver penalty (Invasion -10%)"
        case .ocean, .sea: return "Deep water penalty (Invasion -40%)"
        case .plains: return "Open maneuver (Invasion +10%)"
        }
    }

    var body: some View {
        let occupierCode = state.regionOccupations[region.id] ?? region.countryCode
        let conflict = state.regionConflicts[region.id]
        let originalCountryName = region.countryCode == "WATER" ? "International Waters" : (region.countryCode == "RUS" && state.scenarioID == "soviet-triumph" ? "Soviet Union" : (CountryCatalog.all.first(where: { $0.code == region.countryCode })?.name ?? region.countryCode))
        let occupierCountryName = occupierCode == "WATER" ? "Uncontrolled" : (occupierCode == "RUS" && state.scenarioID == "soviet-triumph" ? "Soviet Union" : (CountryCatalog.all.first(where: { $0.code == occupierCode })?.name ?? (occupierCode == "REB" ? "Insurgents" : occupierCode)))

        let isOccupied = occupierCode != region.countryCode
        let isRebel = occupierCode == "REB" || conflict?.mode == .guerrillaControl
        let isFallout = state.nuclearFalloutRegions.contains(region.id) || conflict?.mode == .nuclearFallout
        let isContested = conflict?.mode == .contestedBorder
        let isStabilizing = conflict?.mode == .stabilization
        let ledger = state.economicLedgers[isRebel ? region.countryCode : occupierCode]

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(region.name.uppercased())
                        .font(.system(.subheadline, design: .monospaced).weight(.bold))
                        .foregroundStyle(Color.iceBlue)
                    Text(isFallout ? "☢️ NUCLEAR WASTELAND" : (isRebel ? "🚨 GUERRILLA CONTROL" : (isContested ? "CONTESTED BORDER" : (isStabilizing ? "STABILIZATION CORRIDOR" : (isOccupied ? "⚔️ OCCUPIED TERRITORY" : "Sovereign Territory")))))
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(isFallout ? Color.alertGold : (isRebel ? Color.orange : (isContested ? Color.alertGold : (isOccupied ? Color.softRed : Color.neonTeal))))
                }
                Spacer()
                Button {
                    selectedRegionID = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }

            Divider()
                .background(Color.white.opacity(0.1))

            VStack(alignment: .leading, spacing: 6) {
                Text("Terrain: \(region.terrain.displayName) (\(terrainModifiersText(for: region.terrain)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("Original Sovereign: \(originalCountryName) (\(region.countryCode))")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("Current Occupier: \(occupierCountryName) (\(occupierCode))")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let conflict {
                    Text("Conflict Mode: \(conflict.mode.displayName) · Intensity \(conflict.intensity)/5")
                        .font(.caption)
                        .foregroundStyle(.primary)
                    if !conflict.summary.isEmpty {
                        Text(conflict.summary)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                if let ledger {
                    Text("GDP: \(String(format: "$%.2fT", ledger.nominalGDPTrillions)) · Growth: \(String(format: "%+.1f%%", ledger.realGrowthPercent))")
                        .font(.caption)
                        .foregroundStyle(.primary)
                    Text("Public Security: \(String(format: "%.1f/100", ledger.securityIndex)) · Insurgency: \(String(format: "%.1f%%", ledger.rebelControlPercent))")
                        .font(.caption)
                        .foregroundStyle(.primary)
                }
            }

            HStack(spacing: 10) {
                if occupierCode != "REB" && occupierCode != state.country.code && CountryCatalog.all.contains(where: { $0.code == occupierCode }) {
                    Button {
                        if let country = CountryCatalog.all.first(where: { $0.code == occupierCode }) {
                            let pc = PlayerCountry(code: country.code, name: occupierCountryName)
                            store.switchCountry(to: pc)
                            selectedRegionID = nil
                        }
                    } label: {
                        Text("Control \(occupierCountryName)")
                            .font(.caption.weight(.bold))
                            .frame(maxWidth: .infinity, minHeight: 32)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.glowingCyan.opacity(0.3))
                }

                if isOccupied && region.countryCode != state.country.code && CountryCatalog.all.contains(where: { $0.code == region.countryCode }) {
                    Button {
                        if let country = CountryCatalog.all.first(where: { $0.code == region.countryCode }) {
                            let pc = PlayerCountry(code: country.code, name: originalCountryName)
                            store.switchCountry(to: pc)
                            selectedRegionID = nil
                        }
                    } label: {
                        Text("Control \(originalCountryName)")
                            .font(.caption.weight(.bold))
                            .frame(maxWidth: .infinity, minHeight: 32)
                    }
                    .buttonStyle(.bordered)
                }
            }

            if occupierCode != state.country.code {
                Button {
                    store.draftAction = "Invade \(region.name) (ID: \(region.id))"
                    store.addDraftAction()
                    selectedRegionID = nil
                } label: {
                    HStack {
                        Image(systemName: "shield.dashed")
                        Text("Order Invasion (Cost: 40)")
                            .fontWeight(.bold)
                    }
                    .frame(maxWidth: .infinity, minHeight: 32)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.softRed.opacity(0.85))
                .disabled(state.administrativeCapacity < 40)
            }
        }
        .padding(14)
        .background(Color.deepSlate.opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        }
        .padding(16)
        .frame(maxWidth: 420)
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
