import MapKit
import SwiftUI

struct GlobalSector: Identifiable {
    var id: String {
        code
    }

    let name: String
    let code: String
    let coordinate: CLLocationCoordinate2D
    let stability: Int
    let relation: SectorRelation
}

struct SectorAnnotationBadge: View {
    let sector: GlobalSector
    let playerCountryCode: String

    private var color: Color {
        switch sector.relation {
        case .player: Color.glowingCyan
        case .ally: Color.neonTeal
        case .neutral: Color.alertGold
        case .rival: Color.softRed
        }
    }

    var body: some View {
        VStack(spacing: 2) {
            Text(sector.name.uppercased())
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .shadow(radius: 1)

            HStack(spacing: 4) {
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)

                Text("\(sector.stability)")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
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
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }
}

struct NativeWorldMap: View {
    let state: NativeCampaignState
    let store: NativeCampaignStore
    let minHeight: CGFloat
    private let sectorsByCode: [String: Native2010MapSector]

    @State private var selectedRegionID: String? = nil
    @State private var hoveredRegionID: String? = nil
    @State private var hoverLocation: CGPoint = .zero
    @State private var selectedLayer: NativeWarRoomMapLayer = .relations
    @State private var zoomScale: CGFloat = 1.0
    @State private var lastZoomScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var isMinimapVisible = true

    init(
        state: NativeCampaignState,
        store: NativeCampaignStore,
        minHeight: CGFloat = 300
    ) {
        self.state = state
        self.store = store
        self.minHeight = minHeight
        sectorsByCode = Dictionary(uniqueKeysWithValues: Native2010WorldModel.mapSectors(for: state).map { ($0.code, $0) })
    }

    /// Keep semantic geometry stable. Conflict borders and routes are intentionally
    /// static so the full Canvas is redrawn only when campaign or viewport state
    /// changes, eliminating idle animation invalidations and presentation flicker.
    private let animationPhase: CGFloat = 0

    private static let majorPowerCodes: Set<String> = [
        "USA", "CAN", "BRA", "ARG", "GBR", "FRA", "DEU", "ITA", "ESP", "POL",
        "UKR", "RUS", "TUR", "EGY", "NGA", "ZAF", "SAU", "IRN", "IND", "CHN",
        "JPN", "IDN", "AUS", "MEX"
    ]

    private static let oceanInscriptions: [(name: String, point: CGPoint)] = [
        ("NORTH ATLANTIC OCEAN", CGPoint(x: 389, y: 244)),
        ("SOUTH ATLANTIC OCEAN", CGPoint(x: 450, y: 345)),
        ("NORTH PACIFIC OCEAN", CGPoint(x: 84, y: 255)),
        ("SOUTH PACIFIC OCEAN", CGPoint(x: 132, y: 342)),
        ("INDIAN OCEAN", CGPoint(x: 717, y: 338)),
        ("ARCTIC OCEAN", CGPoint(x: 528, y: 92))
    ]

    /// Pre-computed world-space label anchor (largest region by bounding-box area)
    /// for each non-water country so subdivided nations like USA/RUS/BRA/CHN label cleanly at 1.0x.
    private static let countryLabelAnchors: [String: CGPoint] = {
        var anchors: [String: CGPoint] = [:]
        for (code, regions) in GeopoliticalMapData.regionsByCountry where code != "WATER" && !regions.isEmpty {
            let bestRegion = regions.max { lhs, rhs in
                let lb = lhs.path.boundingRect
                let rb = rhs.path.boundingRect
                return (lb.width * lb.height) < (rb.width * rb.height)
            }
            if let bestRegion {
                anchors[code] = bestRegion.center
            }
        }
        return anchors
    }()

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
            with: .color(NativeWarRoomTheme.graphite.opacity(0.10)),
            style: StrokeStyle(lineWidth: 1.0 / zoomScale, dash: [4, 4].map { $0 / zoomScale })
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
                with: .color(NativeWarRoomTheme.graphite.opacity(0.17)),
                style: StrokeStyle(lineWidth: 1.2 / zoomScale, lineCap: .round)
            )
        }
    }

    private func drawOceanLabels(context: GraphicsContext, visibleRect: CGRect, scaleX: CGFloat, scaleY: CGFloat) {
        guard zoomScale < 3.0 else { return }
        let opacity = zoomScale < 2.0 ? 0.26 : max(0.0, 0.26 * (3.0 - zoomScale))
        for ocean in Self.oceanInscriptions where visibleRect.contains(ocean.point) {
            let pt = CGPoint(x: ocean.point.x * scaleX, y: ocean.point.y * scaleY)
            let tracked = ocean.name.map(String.init).joined(separator: " ")
            let label = Text(tracked)
                .font(.system(size: 7.5 / zoomScale, weight: .semibold, design: .serif))
                .italic()
                .foregroundColor(NativeWarRoomTheme.graphite.opacity(opacity))
            context.draw(label, at: pt, anchor: .center)
        }
    }

    private func drawCompassRose(context: GraphicsContext, visibleRect: CGRect, scaleX: CGFloat, scaleY: CGFloat) {
        let worldCenter = CGPoint(x: 88, y: 372)
        guard visibleRect.contains(worldCenter) else { return }
        let cx = worldCenter.x * scaleX
        let cy = worldCenter.y * scaleY
        let outerR = 24.0 / zoomScale
        let innerR = 6.5 / zoomScale
        let midR = 14.5 / zoomScale

        let ringColor = NativeWarRoomTheme.graphite.opacity(0.28)
        let brassColor = NativeWarRoomTheme.oxidizedBrass.opacity(0.45)

        // Concentric cartographic rings
        let outerRect = CGRect(x: cx - outerR * 0.85, y: cy - outerR * 0.85, width: outerR * 1.7, height: outerR * 1.7)
        let innerRect = CGRect(x: cx - innerR, y: cy - innerR, width: innerR * 2, height: innerR * 2)
        context.stroke(Path(ellipseIn: outerRect), with: .color(ringColor), lineWidth: 0.9 / zoomScale)
        context.stroke(Path(ellipseIn: innerRect), with: .color(brassColor), lineWidth: 0.8 / zoomScale)

        // 8-point star geometry
        var starPath = Path()
        for i in 0 ..< 8 {
            let angle = Double(i) * (.pi / 4.0) - (.pi / 2.0)
            let tipRadius = i.isMultiple(of: 2) ? outerR : midR
            let tip = CGPoint(x: cx + cos(angle) * tipRadius, y: cy + sin(angle) * tipRadius)
            let leftAngle = angle - (.pi / 8.0)
            let rightAngle = angle + (.pi / 8.0)
            let leftPt = CGPoint(x: cx + cos(leftAngle) * innerR, y: cy + sin(leftAngle) * innerR)
            let rightPt = CGPoint(x: cx + cos(rightAngle) * innerR, y: cy + sin(rightAngle) * innerR)

            starPath.move(to: CGPoint(x: cx, y: cy))
            starPath.addLine(to: leftPt)
            starPath.addLine(to: tip)
            starPath.addLine(to: rightPt)
            starPath.closeSubpath()
        }

        context.fill(starPath, with: .color(NativeWarRoomTheme.oxidizedBrass.opacity(0.16)))
        context.stroke(starPath, with: .color(ringColor), lineWidth: 0.85 / zoomScale)

        // North cardinal mark
        let northLabel = Text("N")
            .font(.system(size: 7.5 / zoomScale, weight: .bold, design: .serif))
            .foregroundColor(NativeWarRoomTheme.graphite.opacity(0.48))
        context.draw(northLabel, at: CGPoint(x: cx, y: cy - outerR - 4.5 / zoomScale), anchor: .bottom)
    }

    private func drawTerrainIcon(context: GraphicsContext, terrain: NativeTerrainType, center: CGPoint, scaleX: CGFloat, scaleY: CGFloat) {
        let cx = center.x * scaleX
        let cy = center.y * scaleY
        var iconPath = Path()

        let o8 = 8.0 / zoomScale
        let o6 = 6.0 / zoomScale
        let o5 = 5.0 / zoomScale
        let o4 = 4.0 / zoomScale
        let o3 = 3.0 / zoomScale
        let o2 = 2.0 / zoomScale
        let o1 = 1.0 / zoomScale
        let o7 = 7.0 / zoomScale

        switch terrain {
        case .mountain:
            iconPath.move(to: CGPoint(x: cx, y: cy - o8))
            iconPath.addLine(to: CGPoint(x: cx - o8, y: cy + o6))
            iconPath.addLine(to: CGPoint(x: cx + o8, y: cy + o6))
            iconPath.closeSubpath()
            iconPath.move(to: CGPoint(x: cx - o3, y: cy - o2))
            iconPath.addLine(to: CGPoint(x: cx + o3, y: cy - o2))
            iconPath.addLine(to: CGPoint(x: cx, y: cy - o8))
            iconPath.closeSubpath()

        case .forest:
            iconPath.move(to: CGPoint(x: cx - o4, y: cy - o6))
            iconPath.addLine(to: CGPoint(x: cx - o8, y: cy + o2))
            iconPath.addLine(to: CGPoint(x: cx - o6, y: cy + o2))
            iconPath.addLine(to: CGPoint(x: cx - o6, y: cy + o5))
            iconPath.addLine(to: CGPoint(x: cx - o2, y: cy + o5))
            iconPath.addLine(to: CGPoint(x: cx - o2, y: cy + o2))
            iconPath.addLine(to: CGPoint(x: cx, y: cy + o2))
            iconPath.closeSubpath()

            iconPath.move(to: CGPoint(x: cx + o4, y: cy - o3))
            iconPath.addLine(to: CGPoint(x: cx, y: cy + o4))
            iconPath.addLine(to: CGPoint(x: cx + o2, y: cy + o4))
            iconPath.addLine(to: CGPoint(x: cx + o2, y: cy + o7))
            iconPath.addLine(to: CGPoint(x: cx + o6, y: cy + o7))
            iconPath.addLine(to: CGPoint(x: cx + o6, y: cy + o4))
            iconPath.addLine(to: CGPoint(x: cx + o8, y: cy + o4))
            iconPath.closeSubpath()

        case .city:
            iconPath.move(to: CGPoint(x: cx - o8, y: cy + o6))
            iconPath.addLine(to: CGPoint(x: cx - o8, y: cy - o2))
            iconPath.addLine(to: CGPoint(x: cx - o4, y: cy - o2))
            iconPath.addLine(to: CGPoint(x: cx - o4, y: cy - o6))
            iconPath.addLine(to: CGPoint(x: cx, y: cy - o6))
            iconPath.addLine(to: CGPoint(x: cx, y: cy + o1))
            iconPath.addLine(to: CGPoint(x: cx + o4, y: cy + o1))
            iconPath.addLine(to: CGPoint(x: cx + o4, y: cy - o4))
            iconPath.addLine(to: CGPoint(x: cx + o8, y: cy - o4))
            iconPath.addLine(to: CGPoint(x: cx + o8, y: cy + o6))
            iconPath.closeSubpath()

        case .swamp:
            iconPath.move(to: CGPoint(x: cx - o6, y: cy))
            iconPath.addQuadCurve(to: CGPoint(x: cx + o6, y: cy), control: CGPoint(x: cx, y: cy + o2))
            iconPath.move(to: CGPoint(x: cx - o4, y: cy + o4))
            iconPath.addQuadCurve(to: CGPoint(x: cx + o4, y: cy + o4), control: CGPoint(x: cx, y: cy + o6))
            iconPath.move(to: CGPoint(x: cx, y: cy + o2))
            iconPath.addLine(to: CGPoint(x: cx - o2, y: cy - o6))
            iconPath.move(to: CGPoint(x: cx, y: cy + o2))
            iconPath.addLine(to: CGPoint(x: cx + o2, y: cy - o4))

        case .cerrado:
            iconPath.move(to: CGPoint(x: cx - o4, y: cy + o5))
            iconPath.addQuadCurve(to: CGPoint(x: cx - o2, y: cy - o5), control: CGPoint(x: cx - o5, y: cy))
            iconPath.move(to: CGPoint(x: cx, y: cy + o5))
            iconPath.addQuadCurve(to: CGPoint(x: cx + o1, y: cy - o7), control: CGPoint(x: cx - o1, y: cy - o1))
            iconPath.move(to: CGPoint(x: cx + o4, y: cy + o5))
            iconPath.addQuadCurve(to: CGPoint(x: cx + o3, y: cy - o3), control: CGPoint(x: cx + o4, y: cy + o1))

        case .strait:
            iconPath.move(to: CGPoint(x: cx - o8, y: cy))
            iconPath.addLine(to: CGPoint(x: cx + o8, y: cy))
            iconPath.move(to: CGPoint(x: cx - o8, y: cy))
            iconPath.addLine(to: CGPoint(x: cx - o5, y: cy - o4))
            iconPath.move(to: CGPoint(x: cx - o8, y: cy))
            iconPath.addLine(to: CGPoint(x: cx - o5, y: cy + o4))
            iconPath.move(to: CGPoint(x: cx + o8, y: cy))
            iconPath.addLine(to: CGPoint(x: cx + o5, y: cy - o4))
            iconPath.move(to: CGPoint(x: cx + o8, y: cy))
            iconPath.addLine(to: CGPoint(x: cx + o5, y: cy + o4))

        default:
            return
        }

        context.stroke(iconPath, with: .color(NativeWarRoomTheme.graphite.opacity(0.58)), lineWidth: 1.2 / zoomScale)
    }

    private func sectorRelation(code: String, playerCode: String, sectorsByCode: [String: Native2010MapSector]) -> SectorRelation {
        if code == playerCode {
            return .player
        }

        if let sector = sectorsByCode[code] {
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
        case .player: Color.glowingCyan
        case .ally: Color.neonTeal
        case .neutral: Color.alertGold
        case .rival: Color.softRed
        }
    }

    private func economyColor(for ledger: NativeEconomicLedger?) -> Color {
        guard let ledger else { return NativeWarRoomTheme.mutedInk.opacity(0.45) }
        if ledger.realGrowthPercent >= 3.0, ledger.fiscalSpaceIndex >= 55 {
            return NativeWarRoomTheme.fieldGreen
        }
        if ledger.realGrowthPercent <= -1.0 || ledger.publicDebtPercentGDP >= 110 {
            return NativeWarRoomTheme.threatRed
        }
        return NativeWarRoomTheme.alertAmber
    }

    private func drawDiagonalStripes(context: GraphicsContext, path: Path, size _: CGSize, occupierColor: Color, originalColor: Color) {
        var context = context
        context.fill(path, with: .color(occupierColor.opacity(0.35)))
        context.clip(to: path)

        let bounds = path.boundingRect
        let spacing: CGFloat = 12 / zoomScale
        let strokeWidth: CGFloat = 2.5 / zoomScale
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
        let spacing: CGFloat = 8 / zoomScale
        let strokeWidth: CGFloat = 3.0 / zoomScale
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
        let spacing: CGFloat = 10 / zoomScale
        let strokeWidth: CGFloat = 2.5 / zoomScale
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
                lineWidth: CGFloat(max(2, min(5, intensity))) / zoomScale,
                lineCap: .round,
                lineJoin: .round,
                dash: [4, 3].map { $0 / zoomScale },
                dashPhase: animationPhase / zoomScale
            )
        )
    }

    private func drawStabilizationOverlay(context: GraphicsContext, path: Path) {
        var context = context
        context.fill(path, with: .color(Color.neonTeal.opacity(0.18)))
        context.clip(to: path)

        let bounds = path.boundingRect
        let spacing: CGFloat = 14 / zoomScale
        var linePath = Path()
        for y in stride(from: bounds.minY, through: bounds.maxY, by: spacing) {
            linePath.move(to: CGPoint(x: bounds.minX, y: y))
            linePath.addLine(to: CGPoint(x: bounds.maxX, y: y))
        }
        context.stroke(linePath, with: .color(Color.neonTeal.opacity(0.45)), lineWidth: 1.5 / zoomScale)
    }

    private func drawDotGrid(context: GraphicsContext, path: Path, color: Color) {
        var context = context
        context.clip(to: path)
        let bounds = path.boundingRect
        let spacing: CGFloat = 16 / zoomScale
        let dotSize: CGFloat = 2.0 / zoomScale

        for y in stride(from: bounds.minY, to: bounds.maxY, by: spacing) {
            for x in stride(from: bounds.minX, to: bounds.maxX, by: spacing) {
                let dotRect = CGRect(x: x - dotSize / 2, y: y - dotSize / 2, width: dotSize, height: dotSize)
                let dotPath = Path(ellipseIn: dotRect)
                context.fill(dotPath, with: .color(color))
            }
        }
    }

    private func drawRivalHashedLines(context: GraphicsContext, path: Path, color: Color) {
        var context = context
        context.fill(path, with: .color(Color.softRed.opacity(0.10)))
        context.clip(to: path)
        let bounds = path.boundingRect
        let spacing: CGFloat = 14 / zoomScale
        let strokeWidth: CGFloat = 1.5 / zoomScale
        var stripePath = Path()

        for x in stride(from: bounds.minX - bounds.height, to: bounds.maxX, by: spacing) {
            stripePath.move(to: CGPoint(x: x, y: bounds.minY))
            stripePath.addLine(to: CGPoint(x: x + bounds.height, y: bounds.maxY))
        }

        context.stroke(stripePath, with: .color(color), lineWidth: strokeWidth)
    }

    private func conflictColor(_ conflict: NativeRegionConflictState) -> Color {
        switch conflict.mode {
        case .contestedBorder:
            Color.alertGold
        case .conventionalOccupation:
            Color.softRed
        case .guerrillaControl:
            Color.orange
        case .nuclearFallout:
            Color.alertGold
        case .stabilization:
            Color.neonTeal
        }
    }

    private func drawRegion(
        context: GraphicsContext,
        reg: MapRegion,
        size: CGSize,
        scaleX: CGFloat,
        scaleY: CGFloat,
        selectedCountryCode: String?,
        sectorsByCode: [String: Native2010MapSector],
        strategicRegionIDs: Set<String>
    ) {
        let occupierCode = state.regionOccupations[reg.id] ?? reg.countryCode
        let conflict = state.regionConflicts[reg.id]
        let isPlayerCountry = reg.countryCode == state.country.code
        let isPlayerOccupier = occupierCode == state.country.code
        let isSelectedCountry = selectedCountryCode != nil && selectedCountryCode == reg.countryCode
        let isHovered = reg.id == hoveredRegionID && reg.countryCode != "WATER"
        let isOccupied = occupierCode != reg.countryCode
        let isContested = conflict?.mode == .contestedBorder

        var path = Path()

        if isContested, let conflict {
            // Find closest region of the opponent/controller if contested
            var targetCenter: CGPoint? = nil
            let targetCode = conflict.controllerCode
            let otherRegions = GeopoliticalMapData.regions(forCountryCode: targetCode).filter { $0.id != reg.id }
            if let closest = otherRegions.min(by: {
                let d1 = pow($0.center.x - reg.center.x, 2) + pow($0.center.y - reg.center.y, 2)
                let d2 = pow($1.center.x - reg.center.x, 2) + pow($1.center.y - reg.center.y, 2)
                return d1 < d2
            }) {
                targetCenter = closest.center
            }

            for ring in reg.paths {
                let scaledPoints = ring.map { (pt: CGPoint) -> CGPoint in
                    var finalPt = pt
                    if let tc = targetCenter {
                        let dx = tc.x - reg.center.x
                        let dy = tc.y - reg.center.y
                        let dist = sqrt(dx * dx + dy * dy)
                        let ux = dx / max(1.0, dist)
                        let uy = dy / max(1.0, dist)

                        let midX = (reg.center.x + tc.x) / 2.0
                        let midY = (reg.center.y + tc.y) / 2.0
                        let d = sqrt(pow(pt.x - midX, 2) + pow(pt.y - midY, 2))
                        let threshold = max(20.0, dist * 0.6)

                        if d < threshold {
                            let factor = (1.0 - d / threshold)
                            let wave = sin(animationPhase * 0.08 + pt.x * 0.3 + pt.y * 0.3)
                            let intensity = CGFloat(conflict.intensity) * 3.5
                            let displacement = (intensity + wave * 2.5) * factor
                            finalPt = CGPoint(x: pt.x + ux * displacement, y: pt.y + uy * displacement)
                        }
                    }
                    return CGPoint(x: finalPt.x * scaleX, y: finalPt.y * scaleY)
                }
                if !scaledPoints.isEmpty {
                    path.addLines(scaledPoints)
                    path.closeSubpath()
                }
            }
        } else {
            // ponytail: use static pre-built path for huge speedup when not contested
            path = reg.path.applying(CGAffineTransform(scaleX: scaleX, y: scaleY))
        }

        let relation = sectorRelation(code: occupierCode, playerCode: state.country.code, sectorsByCode: sectorsByCode)
        let relationStanceColor = relationColor(relation)
        let conflictLayerColor = conflict.map(conflictColor) ?? relationStanceColor.opacity(0.75)
        let strategyLayerColor = strategicRegionIDs.contains(reg.id)
            ? Color.glowingCyan
            : relationStanceColor.opacity(0.45)
        let economyLayerColor = economyColor(for: state.economicLedgers[occupierCode])
        let falloutLayerColor = state.nuclearFalloutRegions.contains(reg.id) || conflict?.mode == .nuclearFallout
            ? NativeWarRoomTheme.alertAmber
            : NativeWarRoomTheme.mutedInk.opacity(0.28)
        var stanceColor: Color = switch selectedLayer {
        case .relations:
            relationStanceColor
        case .conflicts:
            conflictLayerColor
        case .strategy:
            strategyLayerColor
        case .economy:
            economyLayerColor
        case .fallout:
            falloutLayerColor
        }

        // Dynamic GDP / Economic Highlights
        let occupierLedger = state.economicLedgers[occupierCode]
        let hasHighGrowth = (occupierLedger?.realGrowthPercent ?? 0.0) > 0.03

        // Stability-based desaturation
        if state.stability < 40 {
            let fraction = Double(40 - state.stability) / 40.0
            stanceColor = Color.lerp(from: stanceColor, to: Color(hex: "#343126"), fraction: fraction)
        }

        // World Tension Red-shift
        if state.worldTension > 60 {
            let shiftFactor = Double(state.worldTension - 60) / 40.0
            stanceColor = Color.lerp(from: stanceColor, to: Color.red, fraction: shiftFactor * 0.15)
        }

        if reg.countryCode == "WATER" {
            let waterBaseColor = Color(hex: "#b3b49a")
            if isOccupied {
                let originalColor = waterBaseColor
                drawDiagonalStripes(context: context, path: path, size: size, occupierColor: stanceColor, originalColor: originalColor)
            } else {
                context.fill(path, with: .color(waterBaseColor))
            }

            let strokeColor = reg.id == selectedRegionID
                ? NativeWarRoomTheme.oxidizedBrass
                : NativeWarRoomTheme.graphite.opacity(0.22)
            context.stroke(path, with: .color(strokeColor), lineWidth: (reg.id == selectedRegionID ? 2.0 : 1.0) / zoomScale)

            if let conflict, isContested {
                drawContestedBorder(context: context, path: path, color: conflictColor(conflict), intensity: conflict.intensity)
            }
            return
        }

        var fillOpacity = 0.22
        if isPlayerOccupier {
            fillOpacity = 0.38
        } else if isSelectedCountry {
            fillOpacity = 0.3
        }
        if reg.id == selectedRegionID {
            fillOpacity += 0.15
        } else if isHovered {
            fillOpacity += 0.10
        }

        let isFallout = state.nuclearFalloutRegions.contains(reg.id) || conflict?.mode == .nuclearFallout
        let isRebel = occupierCode == "REB" || conflict?.mode == .guerrillaControl
        let isStabilizing = conflict?.mode == .stabilization

        if isFallout {
            drawNuclearHazardStripes(context: context, path: path)
            drawDevastationCrosses(context: context, path: path)
        } else if isRebel {
            drawRebelStripes(context: context, path: path)
            drawDevastationCrosses(context: context, path: path)
        } else if isStabilizing {
            drawStabilizationOverlay(context: context, path: path)
        } else if isOccupied {
            let originalRelation = sectorRelation(code: reg.countryCode, playerCode: state.country.code, sectorsByCode: sectorsByCode)
            let originalColor = relationColor(originalRelation)
            drawDiagonalStripes(context: context, path: path, size: size, occupierColor: stanceColor, originalColor: originalColor)
        } else if selectedLayer == .relations {
            switch relation {
            case .ally:
                context.fill(path, with: .color(Color.neonTeal.opacity(0.32)))
                drawDotGrid(context: context, path: path, color: NativeWarRoomTheme.graphite.opacity(0.22))
            case .rival:
                drawRivalHashedLines(context: context, path: path, color: Color.softRed.opacity(0.42))
            case .neutral:
                context.fill(path, with: .color(Color(hex: "#b9a97d").opacity(0.36)))
            case .player:
                context.fill(path, with: .color(Color.glowingCyan.opacity(0.52)))
            }
        } else {
            context.fill(path, with: .color(stanceColor.opacity(fillOpacity)))
        }

        // Draw economic growth highlight
        if hasHighGrowth {
            let glowColor = Color.neonTeal.opacity(0.4)
            context.stroke(path, with: .color(glowColor), lineWidth: 4.0 / zoomScale)
        }

        if isPlayerCountry || isSelectedCountry {
            let strokeColor = isPlayerCountry ? Color.glowingCyan : stanceColor
            let dashStyle = StrokeStyle(
                lineWidth: 2.0 / zoomScale,
                lineCap: .round,
                lineJoin: .round,
                dash: [6, 4].map { $0 / zoomScale },
                dashPhase: animationPhase / zoomScale
            )
            context.stroke(path, with: .color(strokeColor), style: dashStyle)
        } else {
            context.stroke(path, with: .color(NativeWarRoomTheme.graphite.opacity(0.38)), lineWidth: 1.0 / zoomScale)
        }

        if isHovered {
            context.fill(path, with: .color(NativeWarRoomTheme.brass.opacity(0.14)))
            context.stroke(path, with: .color(NativeWarRoomTheme.brass.opacity(0.85)), lineWidth: 2.0 / zoomScale)
        }

        if let conflict {
            drawContestedBorder(context: context, path: path, color: conflictColor(conflict), intensity: conflict.intensity)
        }
    }

    private func drawConflictRoutes(context: GraphicsContext, scaleX: CGFloat, scaleY: CGFloat) {
        for conflict in state.regionConflicts.values {
            guard let target = GeopoliticalMapData.regionByID[conflict.regionID] else {
                continue
            }

            let targetPoint = CGPoint(x: target.center.x * scaleX, y: target.center.y * scaleY)
            let color = conflictColor(conflict)
            let radius = CGFloat(5 + conflict.intensity * 2) / zoomScale

            if conflict.mode == .nuclearFallout {
                let falloutRect = CGRect(
                    x: targetPoint.x - radius * 2,
                    y: targetPoint.y - radius * 2,
                    width: radius * 4,
                    height: radius * 4
                )
                context.stroke(Path(ellipseIn: falloutRect), with: .color(color.opacity(0.8)), lineWidth: 2 / zoomScale)
                continue
            }

            if let source = GeopoliticalMapData.regions(forCountryCode: conflict.controllerCode).first(where: { $0.id != conflict.regionID }) {
                let sourcePoint = CGPoint(x: source.center.x * scaleX, y: source.center.y * scaleY)
                var route = Path()
                route.move(to: sourcePoint)
                route.addLine(to: targetPoint)
                context.stroke(
                    route,
                    with: .color(color.opacity(0.72)),
                    style: StrokeStyle(
                        lineWidth: CGFloat(max(1, min(4, conflict.intensity))) / zoomScale,
                        lineCap: .round,
                        dash: conflict.mode == .contestedBorder ? [5, 4].map { $0 / zoomScale } : [8, 5].map { $0 / zoomScale },
                        dashPhase: animationPhase / zoomScale
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
            context.stroke(Path(ellipseIn: markerRect), with: .color(color.opacity(0.8)), lineWidth: 1.5 / zoomScale)
        }
    }

    private func drawStrategicMarkers(context: GraphicsContext, visibleRect: CGRect, scaleX: CGFloat, scaleY: CGFloat) {
        let armiesByRegion = Dictionary(grouping: state.mapArmies, by: \.currentRegionID)
        let buildingsByRegion = Dictionary(grouping: state.mapBuildings, by: \.regionID)
        let markerRegionIDs = Set(armiesByRegion.keys).union(buildingsByRegion.keys)
        let showsFullStrategicPicture = selectedLayer == .strategy

        for regionID in markerRegionIDs.sorted() {
            guard let region = GeopoliticalMapData.regionByID[regionID],
                  visibleRect.contains(region.center)
            else { continue }

            let armies = armiesByRegion[regionID, default: []]
            let buildings = buildingsByRegion[regionID, default: []]
            let isPlayerAsset = armies.contains { $0.countryCode == state.country.code }
                || buildings.contains { $0.ownerCountryCode == state.country.code }
            let isActiveConflict = state.regionConflicts[regionID] != nil

            // The relationship map is an orientation view. Showing every asset
            // there quickly turns dense regions into an unreadable field of dots.
            // Full asset detail is available deliberately on the Strategy layer;
            // otherwise, reveal only the player's and active-conflict markers once
            // the player has zoomed in far enough to act on them.
            guard showsFullStrategicPicture || (zoomScale >= 1.75 && (isPlayerAsset || isActiveConflict)) else {
                continue
            }

            let center = CGPoint(x: region.center.x * scaleX, y: region.center.y * scaleY)

            if !buildings.isEmpty {
                drawBuildingMarker(context: context, center: CGPoint(x: center.x - 7 / zoomScale, y: center.y + 7 / zoomScale), buildings: buildings)
            }

            if !armies.isEmpty {
                drawArmyMarker(context: context, center: CGPoint(x: center.x + 8 / zoomScale, y: center.y - 8 / zoomScale), armies: armies)
            }

            for army in armies where army.targetRegionID != nil && army.targetRegionID != regionID {
                guard let targetID = army.targetRegionID,
                      let target = GeopoliticalMapData.regionByID[targetID]
                else { continue }
                var route = Path()
                route.move(to: center)
                route.addLine(to: CGPoint(x: target.center.x * scaleX, y: target.center.y * scaleY))
                context.stroke(
                    route,
                    with: .color(Color.glowingCyan.opacity(0.55)),
                    style: StrokeStyle(lineWidth: 1.2 / zoomScale, dash: [4, 3].map { $0 / zoomScale }, dashPhase: animationPhase / zoomScale)
                )
            }
        }
    }

    private func drawArmyMarker(context: GraphicsContext, center: CGPoint, armies: [NativeArmySnapshot]) {
        let strongest = armies.max { $0.strength < $1.strength }
        let totalStrength = armies.map(\.strength).reduce(0, +)
        let owner = strongest?.countryCode ?? "AI"
        let radius = max(6, min(13, CGFloat(totalStrength) / 7)) / zoomScale
        let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        let isPlayer = armies.contains { $0.countryCode == state.country.code }
        let color = isPlayer ? Color.glowingCyan : Color.softRed

        context.fill(Path(ellipseIn: rect), with: .color(Color.deepSlate.opacity(0.88)))
        context.stroke(Path(ellipseIn: rect), with: .color(color.opacity(0.92)), lineWidth: 1.6 / zoomScale)

        let label = Text(String(owner.prefix(3)).uppercased())
            .font(.system(size: 6.5 / zoomScale, weight: .black, design: .monospaced))
            .foregroundColor(color)
        context.draw(label, at: center, anchor: .center)
    }

    private func drawBuildingMarker(context: GraphicsContext, center: CGPoint, buildings: [NativeBuildingSnapshot]) {
        let maxLevel = buildings.map(\.level).max() ?? 1
        let size = CGFloat(9 + maxLevel) / zoomScale
        let rect = CGRect(x: center.x - size / 2, y: center.y - size / 2, width: size, height: size)
        let path = Path(roundedRect: rect, cornerRadius: 2 / zoomScale)
        context.fill(path, with: .color(Color.deepSlate.opacity(0.85)))
        context.stroke(path, with: .color(Color.alertGold.opacity(0.9)), lineWidth: 1.4 / zoomScale)

        let label = Text("\(buildings.count)")
            .font(.system(size: 6 / zoomScale, weight: .black, design: .monospaced))
            .foregroundColor(Color.alertGold)
        context.draw(label, at: center, anchor: .center)
    }

    private func drawMap(context: GraphicsContext, size: CGSize, scaleX: CGFloat, scaleY: CGFloat) {
        // Calculate visible bounding box for culling
        let minLocalX = (-size.width / 2.0 - offset.width) / zoomScale + size.width / 2.0
        let maxLocalX = (size.width / 2.0 - offset.width) / zoomScale + size.width / 2.0
        let minLocalY = (-size.height / 2.0 - offset.height) / zoomScale + size.height / 2.0
        let maxLocalY = (size.height / 2.0 - offset.height) / zoomScale + size.height / 2.0

        let minX = minLocalX / scaleX - 150.0
        let maxX = maxLocalX / scaleX + 150.0
        let minY = minLocalY / scaleY - 150.0
        let maxY = maxLocalY / scaleY + 150.0
        let visibleRect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)

        drawOceanLabels(context: context, visibleRect: visibleRect, scaleX: scaleX, scaleY: scaleY)
        drawCompassRose(context: context, visibleRect: visibleRect, scaleX: scaleX, scaleY: scaleY)

        // Draw continents (skip off-screen landmasses)
        let transform = CGAffineTransform(scaleX: scaleX, y: scaleY)
        for lm in GeopoliticalMapData.landmasses {
            let bounds = lm.path.boundingRect
            let center = CGPoint(x: bounds.midX, y: bounds.midY)
            if !visibleRect.contains(center) {
                continue
            }
            let path = lm.path.applying(transform)
            context.fill(path, with: .color(Color(hex: "#c9bc92")))
            context.stroke(path, with: .color(NativeWarRoomTheme.graphite.opacity(0.28)), lineWidth: 1.0 / zoomScale)
        }

        let selectedCountryCode = selectedRegionID.flatMap { GeopoliticalMapData.regionByID[$0]?.countryCode }
        let strategicRegionIDs = Set(state.mapArmies.map(\.currentRegionID)).union(state.mapBuildings.map(\.regionID))

        // Draw countries / partitions
        for reg in GeopoliticalMapData.regions {
            if !visibleRect.contains(reg.center) {
                continue
            }
            drawRegion(
                context: context,
                reg: reg,
                size: size,
                scaleX: scaleX,
                scaleY: scaleY,
                selectedCountryCode: selectedCountryCode,
                sectorsByCode: sectorsByCode,
                strategicRegionIDs: strategicRegionIDs
            )
        }

        // Draw country & sub-national labels across world and regional LODs
        drawMapLabels(context: context, visibleRect: visibleRect, scaleX: scaleX, scaleY: scaleY)

        if selectedLayer == .strategy || zoomScale >= 1.75 {
            drawStrategicMarkers(context: context, visibleRect: visibleRect, scaleX: scaleX, scaleY: scaleY)
        }

        // Draw state borders when zoomed in (LOD)
        if zoomScale >= 1.5 {
            let stateTransform = CGAffineTransform(scaleX: scaleX, y: scaleY)
            for stateReg in GeopoliticalMapData.states {
                if !visibleRect.contains(stateReg.center) {
                    continue
                }
                let path = stateReg.path.applying(stateTransform)
                context.stroke(path, with: .color(NativeWarRoomTheme.graphite.opacity(0.22)), lineWidth: 0.8 / zoomScale)
            }
        }

        // Draw populated places (cities) with LOD
        let cityPopulationThreshold = if zoomScale >= 4.0 {
            100_000
        } else if zoomScale >= 3.0 {
            300_000
        } else if zoomScale >= 2.0 {
            700_000
        } else if zoomScale >= 1.5 {
            1_500_000
        } else {
            4_000_000
        }

        for city in GeopoliticalMapData.cities {
            if !visibleRect.contains(city.coordinate) {
                continue
            }
            let isPlayerCapital = city.isCapital &&
                GeopoliticalMapData.canonicalCountryCode(city.countryCode) == GeopoliticalMapData.canonicalCountryCode(state.country.code)
            let isVisibleAtWorldScale = isPlayerCapital || city.population >= cityPopulationThreshold
            guard isVisibleAtWorldScale else { continue }

            let scaledPt = CGPoint(x: city.coordinate.x * scaleX, y: city.coordinate.y * scaleY)
            let radius: CGFloat = (city.isCapital ? 4.0 : 2.5) / zoomScale
            let markerRect = CGRect(
                x: scaledPt.x - radius,
                y: scaledPt.y - radius,
                width: radius * 2,
                height: radius * 2
            )

            let markerColor = city.isCapital ? NativeWarRoomTheme.threatRed : NativeWarRoomTheme.graphite
            context.fill(Path(ellipseIn: markerRect), with: .color(markerColor))
            context.stroke(Path(ellipseIn: markerRect), with: .color(NativeWarRoomTheme.parchment.opacity(0.8)), lineWidth: 0.6 / zoomScale)

            if zoomScale >= 1.4 || isPlayerCapital || city.population >= 5_000_000 {
                let text = Text(city.name)
                    .font(.system(size: (city.isCapital ? 7 : 6) / zoomScale, weight: city.isCapital ? .bold : .regular, design: .monospaced))
                    .foregroundColor(city.isCapital ? NativeWarRoomTheme.threatRed : NativeWarRoomTheme.graphite.opacity(0.84))

                context.draw(text, at: CGPoint(x: scaledPt.x, y: scaledPt.y - radius - 3 / zoomScale), anchor: .bottom)
            }
        }

        // Dynamic Level of Detail (LOD) terrain icons
        if zoomScale >= 1.5 {
            for reg in GeopoliticalMapData.nonWaterRegions {
                if !visibleRect.contains(reg.center) {
                    continue
                }
                drawTerrainIcon(context: context, terrain: reg.terrain, center: reg.center, scaleX: scaleX, scaleY: scaleY)
            }
        }

        drawConflictRoutes(context: context, scaleX: scaleX, scaleY: scaleY)
        drawArmiesAndPolice(context: context, scaleX: scaleX, scaleY: scaleY, visibleRect: visibleRect)
    }

    private func drawMapLabels(context: GraphicsContext, visibleRect: CGRect, scaleX: CGFloat, scaleY: CGFloat) {
        let playerCanonical = GeopoliticalMapData.canonicalCountryCode(state.country.code)

        if zoomScale < 1.5 {
            // 1.0x world-scale major powers + player nation
            var featuredCodes = Self.majorPowerCodes
            featuredCodes.insert(playerCanonical)
            featuredCodes.insert(state.country.code.uppercased())

            for code in featuredCodes.sorted() {
                guard let anchor = Self.countryLabelAnchors[code],
                      visibleRect.contains(anchor)
                else { continue }
                let resolved = CountryNameResolver.name(forCode: code, in: state).uppercased()
                guard !resolved.isEmpty else { continue }
                let isPlayer = GeopoliticalMapData.canonicalCountryCode(code) == playerCanonical
                drawAtlasLabel(
                    context: context,
                    text: resolved,
                    at: CGPoint(x: anchor.x * scaleX, y: anchor.y * scaleY),
                    fontSize: (isPlayer ? 9.5 : 8.5) / zoomScale,
                    design: .serif,
                    weight: isPlayer ? .black : .bold,
                    foreground: isPlayer ? NativeWarRoomTheme.blackboard : NativeWarRoomTheme.archiveShadow.opacity(0.88),
                    haloOpacity: isPlayer ? 0.85 : 0.75
                )
            }
            return
        }

        // >= 1.5x: all country anchors, plus sub-national state labels when zoomed in >= 2.8x
        if zoomScale < 2.8 {
            for (code, anchor) in Self.countryLabelAnchors where visibleRect.contains(anchor) {
                let resolved = CountryNameResolver.name(forCode: code, in: state).uppercased()
                guard !resolved.isEmpty else { continue }
                let isPlayer = GeopoliticalMapData.canonicalCountryCode(code) == playerCanonical
                drawAtlasLabel(
                    context: context,
                    text: resolved,
                    at: CGPoint(x: anchor.x * scaleX, y: anchor.y * scaleY),
                    fontSize: (isPlayer ? 8.5 : 7.2) / zoomScale,
                    design: .serif,
                    weight: .bold,
                    foreground: NativeWarRoomTheme.archiveShadow.opacity(0.90),
                    haloOpacity: 0.78
                )
            }
            return
        }

        // >= 2.8x: full regional and sub-national state labels
        for reg in GeopoliticalMapData.nonWaterRegions where visibleRect.contains(reg.center) {
            let isState = reg.id.contains("_") || reg.id.count > 3
            let scaledCenter = CGPoint(x: reg.center.x * scaleX, y: reg.center.y * scaleY)
            drawAtlasLabel(
                context: context,
                text: reg.name.uppercased(),
                at: scaledCenter,
                fontSize: (isState ? 5.8 : 7.0) / zoomScale,
                design: isState ? .monospaced : .serif,
                weight: isState ? .semibold : .black,
                foreground: isState
                    ? NativeWarRoomTheme.graphite.opacity(0.76)
                    : NativeWarRoomTheme.archiveShadow.opacity(0.90),
                haloOpacity: 0.72
            )
        }
    }

    private func drawAtlasLabel(
        context: GraphicsContext,
        text: String,
        at point: CGPoint,
        fontSize: CGFloat,
        design: Font.Design,
        weight: Font.Weight,
        foreground: Color,
        haloOpacity: Double
    ) {
        let shadowOffset = 0.65 / zoomScale
        let haloText = Text(text)
            .font(.system(size: fontSize, weight: weight, design: design))
            .foregroundColor(NativeWarRoomTheme.parchment.opacity(haloOpacity))
        let mainText = Text(text)
            .font(.system(size: fontSize, weight: weight, design: design))
            .foregroundColor(foreground)

        context.draw(haloText, at: CGPoint(x: point.x + shadowOffset, y: point.y + shadowOffset), anchor: .center)
        context.draw(mainText, at: point, anchor: .center)
    }

    private func drawDevastationCrosses(context: GraphicsContext, path: Path) {
        var context = context
        context.clip(to: path)
        let bounds = path.boundingRect
        let step: CGFloat = 16.0 / zoomScale
        var x = bounds.minX
        while x < bounds.maxX {
            var y = bounds.minY
            while y < bounds.maxY {
                context.stroke(
                    Path { p in
                        p.move(to: CGPoint(x: x - 1.5 / zoomScale, y: y - 1.5 / zoomScale))
                        p.addLine(to: CGPoint(x: x + 1.5 / zoomScale, y: y + 1.5 / zoomScale))
                        p.move(to: CGPoint(x: x + 1.5 / zoomScale, y: y - 1.5 / zoomScale))
                        p.addLine(to: CGPoint(x: x - 1.5 / zoomScale, y: y + 1.5 / zoomScale))
                    },
                    with: .color(Color.black.opacity(0.45)),
                    lineWidth: 0.8 / zoomScale
                )
                y += step
            }
            x += step
        }
    }

    private func drawArmiesAndPolice(context: GraphicsContext, scaleX: CGFloat, scaleY: CGFloat, visibleRect: CGRect) {
        // Only derive abstract military markers from real conflict/control state.
        // Army snapshots are rendered separately by drawStrategicMarkers; treating
        // every military-budget country as an army made the world view unreadable.
        var militaryRegionIDs = Set<String>()
        militaryRegionIDs.formUnion(state.regionConflicts.keys.filter { id in
            state.regionConflicts[id]?.mode == .contestedBorder || state.regionConflicts[id]?.mode == .conventionalOccupation
        })
        for (regionID, occupierCode) in state.regionOccupations {
            // Only add if actually occupied (different from original owner)
            if let region = GeopoliticalMapData.regionByID[regionID], occupierCode != region.countryCode {
                militaryRegionIDs.insert(regionID)
            }
        }
        for reg in GeopoliticalMapData.nonWaterRegions {
            if !visibleRect.contains(reg.center) {
                continue
            }
            let occupierCode = state.regionOccupations[reg.id] ?? reg.countryCode
            let ledger = state.economicLedgers[occupierCode]
            let conflict = state.regionConflicts[reg.id]

            let securityIndex = ledger?.securityIndex ?? 80.0
            let centerPt = CGPoint(x: reg.center.x * scaleX, y: reg.center.y * scaleY)

            let shouldDrawPolice = selectedLayer == .strategy &&
                zoomScale >= 2.5 &&
                (reg.countryCode == state.country.code || securityIndex < 50.0 || conflict != nil)
            if !militaryRegionIDs.contains(reg.id) && !shouldDrawPolice {
                continue
            }

            let isOccupied = occupierCode != reg.countryCode
            let isMilitaryConflict = conflict?.mode == .contestedBorder || conflict?.mode == .conventionalOccupation

            if isOccupied || isMilitaryConflict {
                let armyColor = occupierCode == state.country.code ? Color.glowingCyan : Color.softRed
                let scale: CGFloat = (1.2 / zoomScale)
                let armyPt = CGPoint(x: centerPt.x - 10 / zoomScale, y: centerPt.y + 4 / zoomScale)

                var tank = Path()
                tank.addRect(CGRect(x: -5 * scale, y: -2 * scale, width: 10 * scale, height: 4 * scale))
                tank.addRect(CGRect(x: -2.5 * scale, y: -4 * scale, width: 5 * scale, height: 2 * scale))
                tank.move(to: CGPoint(x: 0, y: -3 * scale))
                tank.addLine(to: CGPoint(x: 7 * scale, y: -3 * scale))

                let transformedTank = tank.applying(CGAffineTransform(translationX: armyPt.x, y: armyPt.y))
                context.fill(transformedTank, with: .color(armyColor))
                context.stroke(transformedTank, with: .color(Color.black.opacity(0.85)), lineWidth: 0.8 / zoomScale)

                if let intensity = conflict?.intensity, intensity > 2 {
                    let secondPt = CGPoint(x: armyPt.x - 4 / zoomScale, y: armyPt.y - 4 / zoomScale)
                    let secondTank = tank.applying(CGAffineTransform(translationX: secondPt.x, y: secondPt.y))
                    context.fill(secondTank, with: .color(armyColor.opacity(0.7)))
                    context.stroke(secondTank, with: .color(Color.black.opacity(0.7)), lineWidth: 0.6 / zoomScale)
                }
            }

            if shouldDrawPolice, securityIndex > 10.0 {
                let policeColor = securityIndex >= 50.0 ? Color.neonTeal : Color.alertGold
                let scale: CGFloat = (1.2 / zoomScale)
                let policePt = CGPoint(x: centerPt.x + 10 / zoomScale, y: centerPt.y + 4 / zoomScale)

                var shield = Path()
                shield.move(to: CGPoint(x: 0, y: -5 * scale))
                shield.addLine(to: CGPoint(x: 4 * scale, y: -3 * scale))
                shield.addLine(to: CGPoint(x: 4 * scale, y: 1 * scale))
                shield.addQuadCurve(to: CGPoint(x: 0, y: 5 * scale), control: CGPoint(x: 3.5 * scale, y: 4.5 * scale))
                shield.addQuadCurve(to: CGPoint(x: -4 * scale, y: 1 * scale), control: CGPoint(x: -3.5 * scale, y: 4.5 * scale))
                shield.addLine(to: CGPoint(x: -4 * scale, y: -3 * scale))
                shield.closeSubpath()

                let transformedShield = shield.applying(CGAffineTransform(translationX: policePt.x, y: policePt.y))
                context.fill(transformedShield, with: .color(policeColor))
                context.stroke(transformedShield, with: .color(Color.black.opacity(0.85)), lineWidth: 0.8 / zoomScale)
            }
        }
    }

    private var layerSelectorOverlay: some View {
        Picker("Map layer", selection: $selectedLayer) {
            ForEach(NativeWarRoomMapLayer.allCases) { layer in
                Text(layer.title).tag(layer)
            }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .controlSize(.small)
        #if os(iOS)
            .padding(5)
            .background(NativeWarRoomTheme.archiveShadow.opacity(0.92), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(NativeWarRoomTheme.brass.opacity(0.26), lineWidth: 1)
            }
            .frame(maxWidth: 286)
            .padding(.leading, 10)
            .padding(.bottom, 16)
        #else
            .padding(8)
            .background(NativeWarRoomTheme.archiveShadow.opacity(0.86), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(NativeWarRoomTheme.brass.opacity(0.18), lineWidth: 1)
            }
            .frame(maxWidth: 360)
            .padding(12)
        #endif
            .accessibilityIdentifier("native-map-layer-picker")
    }

    @ViewBuilder
    private var regionDetailsOverlay: some View {
        if let regionID = selectedRegionID,
           let region = GeopoliticalMapData.regionByID[regionID]
        {
            RegionDetailsCard(
                region: region,
                state: state,
                store: store,
                selectedRegionID: $selectedRegionID
            )
        }
    }

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
        .foregroundStyle(NativeWarRoomTheme.ink)
        .background(NativeWarRoomTheme.archiveShadow.opacity(0.92), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(NativeWarRoomTheme.brass.opacity(0.30), lineWidth: 1)
        }
        .padding(12)
    }

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

    #if os(macOS)
        @ViewBuilder
        private func hoverTooltipOverlay(in size: CGSize) -> some View {
            if selectedRegionID == nil,
               let hoveredID = hoveredRegionID,
               let region = GeopoliticalMapData.regionByID[hoveredID],
               region.countryCode != "WATER"
            {
                let occupierCode = state.regionOccupations[region.id] ?? region.countryCode
                let relation = sectorRelation(code: occupierCode, playerCode: state.country.code, sectorsByCode: sectorsByCode)
                let badgeColor = relationColor(relation)
                let relationTitle = switch relation {
                case .player: "PLAYER"
                case .ally: "ALLY"
                case .neutral: "NEUTRAL"
                case .rival: "RIVAL"
                }
                let flag = CountryCatalog.flagEmoji(forAlpha3: region.countryCode) ?? "🌐"
                let sovereignName = CountryNameResolver.name(forCode: region.countryCode, in: state)
                let occupierName = occupierCode == "REB"
                    ? "Insurgents"
                    : CountryNameResolver.name(forCode: occupierCode, in: state)
                let ledger = state.economicLedgers[occupierCode == "REB" ? region.countryCode : occupierCode]
                let cardWidth: CGFloat = 246
                let cardHeight: CGFloat = 104
                let x = max(cardWidth / 2 + 12, min(size.width - cardWidth / 2 - 12, hoverLocation.x + 14 + cardWidth / 2))
                let y = max(cardHeight / 2 + 68, min(size.height - cardHeight / 2 - 16, hoverLocation.y - 14 - cardHeight / 2))

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text(flag)
                            .font(.subheadline)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(region.name)
                                .font(NativeWarRoomTheme.displayFont(.caption, weight: .bold))
                                .foregroundStyle(NativeWarRoomTheme.ink)
                                .lineLimit(1)
                            Text(sovereignName.uppercased())
                                .font(NativeWarRoomTheme.labelFont(.caption2, weight: .semibold))
                                .foregroundStyle(NativeWarRoomTheme.mutedInk)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        Text(relationTitle)
                            .font(.system(size: 9, weight: .black, design: .monospaced))
                            .foregroundStyle(badgeColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(badgeColor.opacity(0.14), in: Capsule())
                            .overlay {
                                Capsule().stroke(badgeColor.opacity(0.42), lineWidth: 0.8)
                            }
                    }

                    if occupierCode != region.countryCode {
                        Text("CONTROLLER: \(occupierName.uppercased())")
                            .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(NativeWarRoomTheme.threatRed)
                            .lineLimit(1)
                    }

                    Rectangle()
                        .fill(NativeWarRoomTheme.brass.opacity(0.2))
                        .frame(height: 1)

                    HStack(spacing: 8) {
                        if let ledger {
                            Text(String(format: "GDP $%.1fT (%+.1f%%)", ledger.nominalGDPTrillions, ledger.realGrowthPercent))
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundStyle(NativeWarRoomTheme.parchment)
                            Text("SEC \(Int(ledger.securityIndex.rounded()))")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(NativeWarRoomTheme.statusColor(for: Int(ledger.securityIndex.rounded())))
                        }
                        Spacer(minLength: 2)
                        Text("\(region.terrain.displayName.uppercased()) \(shortCombatModifier(for: region.terrain))")
                            .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(NativeWarRoomTheme.brass)
                    }
                }
                .padding(10)
                .frame(width: cardWidth, alignment: .leading)
                .warRoomDossier(borderColor: NativeWarRoomTheme.brass.opacity(0.45), cornerRadius: 8)
                .position(x: x, y: y)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
    #endif

    private func minimapNavigatorOverlay(mapSize: CGSize) -> some View {
        VStack(alignment: .trailing, spacing: 6) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isMinimapVisible.toggle()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: isMinimapVisible ? "map.fill" : "map")
                        .font(.system(size: 10, weight: .bold))
                    Text(isMinimapVisible ? "ATLAS" : "MINIMAP")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                }
                .foregroundStyle(NativeWarRoomTheme.brass)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(NativeWarRoomTheme.archiveShadow.opacity(0.92), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(NativeWarRoomTheme.brass.opacity(0.32), lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isMinimapVisible ? "Hide world minimap" : "Show world minimap")

            if isMinimapVisible {
                let miniSize = CGSize(width: 132, height: 78)
                let playerCode = GeopoliticalMapData.canonicalCountryCode(state.country.code)
                let playerRegions = GeopoliticalMapData.regions(forCountryCode: playerCode)

                Canvas { ctx, canvasSize in
                    let sx = canvasSize.width / 1000.0
                    let sy = canvasSize.height / 600.0
                    let tf = CGAffineTransform(scaleX: sx, y: sy)

                    ctx.fill(Path(CGRect(origin: .zero, size: canvasSize)), with: .color(NativeWarRoomTheme.archiveShadow))
                    for lm in GeopoliticalMapData.landmasses {
                        ctx.fill(lm.path.applying(tf), with: .color(NativeWarRoomTheme.mapPaper.opacity(0.55)))
                    }
                    for reg in playerRegions {
                        ctx.fill(reg.path.applying(tf), with: .color(NativeWarRoomTheme.brass))
                    }

                    // Viewport indicator rectangle mapped from current zoomScale & offset
                    if mapSize.width > 0, mapSize.height > 0 {
                        let minLocalX = (-mapSize.width / 2.0 - offset.width) / zoomScale + mapSize.width / 2.0
                        let maxLocalX = (mapSize.width / 2.0 - offset.width) / zoomScale + mapSize.width / 2.0
                        let minLocalY = (-mapSize.height / 2.0 - offset.height) / zoomScale + mapSize.height / 2.0
                        let maxLocalY = (mapSize.height / 2.0 - offset.height) / zoomScale + mapSize.height / 2.0

                        let vx = max(0, min(canvasSize.width, (minLocalX / mapSize.width) * canvasSize.width))
                        let vy = max(0, min(canvasSize.height, (minLocalY / mapSize.height) * canvasSize.height))
                        let vMaxX = max(0, min(canvasSize.width, (maxLocalX / mapSize.width) * canvasSize.width))
                        let vMaxY = max(0, min(canvasSize.height, (maxLocalY / mapSize.height) * canvasSize.height))
                        let viewportRect = CGRect(
                            x: vx,
                            y: vy,
                            width: max(6, vMaxX - vx),
                            height: max(6, vMaxY - vy)
                        )
                        ctx.fill(Path(viewportRect), with: .color(NativeWarRoomTheme.brass.opacity(0.14)))
                        ctx.stroke(Path(viewportRect), with: .color(NativeWarRoomTheme.brass), lineWidth: 1.2)
                    }
                }
                .frame(width: miniSize.width, height: miniSize.height)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(NativeWarRoomTheme.brass.opacity(0.42), lineWidth: 1)
                }
                .shadow(color: Color.black.opacity(0.4), radius: 6, x: 0, y: 2)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard zoomScale > 1.0, mapSize.width > 0, mapSize.height > 0 else { return }
                            let normX = max(0, min(1, value.location.x / miniSize.width))
                            let normY = max(0, min(1, value.location.y / miniSize.height))
                            let targetOffset = CGSize(
                                width: (0.5 - normX) * mapSize.width * zoomScale,
                                height: (0.5 - normY) * mapSize.height * zoomScale
                            )
                            offset = clampOffset(targetOffset, size: mapSize, zoom: zoomScale)
                            lastOffset = offset
                        }
                )
            }
        }
        .padding(.top, 64)
        .padding(.trailing, 12)
    }

    private func shortCombatModifier(for terrain: NativeTerrainType) -> String {
        switch terrain {
        case .mountain: "-30%"
        case .strait: "-25%"
        case .swamp: "-20%"
        case .forest, .city: "-15%"
        case .cerrado: "-10%"
        case .ocean, .sea: "-40%"
        case .plains: "+10%"
        }
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
                                if let hitRegion = GeopoliticalMapData.nonWaterRegions.first(where: { region in
                                    // ponytail: check static pre-built path instead of rebuilding on every click
                                    region.path.contains(clickPt)
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
                            zoomScale = max(1.0, min(lastZoomScale * value, 12.0))
                        }
                        .onEnded { _ in
                            zoomScale = max(1.0, min(zoomScale, 12.0))
                            lastZoomScale = zoomScale
                            withAnimation(.easeOut(duration: 0.2)) {
                                offset = clampOffset(offset, size: size, zoom: zoomScale)
                                lastOffset = offset
                            }
                        }

                    let doubleTapGesture = TapGesture(count: 2)
                        .onEnded {
                            withAnimation(.easeOut(duration: 0.25)) {
                                zoomScale = min(zoomScale + 2.0, 12.0)
                                lastZoomScale = zoomScale
                                offset = clampOffset(offset, size: size, zoom: zoomScale)
                                lastOffset = offset
                            }
                        }

                    // Keep the expensive geography pass off the main actor. The
                    // map has no idle animation, so asynchronous Canvas rendering
                    // cannot create a stream of invalidations while the campaign
                    // store is processing a turn.
                    Canvas(opaque: true, colorMode: .nonLinear, rendersAsynchronously: true) { context, size in
                        context.fill(
                            Path(CGRect(origin: .zero, size: size)),
                            with: .color(Color(hex: "#b3b49a"))
                        )
                        drawGridLines(context: context, size: size)

                        context.drawLayer { ctx in
                            ctx.translateBy(x: size.width / 2 + offset.width, y: size.height / 2 + offset.height)
                            ctx.scaleBy(x: zoomScale, y: zoomScale)
                            ctx.translateBy(x: -size.width / 2, y: -size.height / 2)
                            drawOceanWaves(context: ctx, scaleX: scaleX, scaleY: scaleY)
                            drawMap(context: ctx, size: size, scaleX: scaleX, scaleY: scaleY)
                        }
                    }
                    .frame(width: size.width, height: size.height)
                    .contentShape(Rectangle())
                    .gesture(
                        SimultaneousGesture(
                            SimultaneousGesture(dragGesture, magnificationGesture),
                            doubleTapGesture
                        )
                    )
                    #if os(macOS)
                    .onContinuousHover { phase in
                        switch phase {
                        case let .active(location):
                            hoverLocation = location
                            let worldPt = reverseTransform(location, size: size, scaleX: scaleX, scaleY: scaleY)
                            let hit = GeopoliticalMapData.nonWaterRegions.first { $0.path.contains(worldPt) }
                            if hoveredRegionID != hit?.id {
                                hoveredRegionID = hit?.id
                            }
                        case .ended:
                            hoveredRegionID = nil
                        }
                    }
                    #endif

                    #if os(macOS)
                        hoverTooltipOverlay(in: size)
                        minimapNavigatorOverlay(mapSize: size)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    #endif

                    // Floating Glassmorphic Zoom Controls
                    VStack(spacing: 8) {
                        Button {
                            withAnimation(.easeOut(duration: 0.2)) {
                                zoomScale = min(zoomScale + 0.5, 12.0)
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
                .onChange(of: selectedRegionID) { _, newID in
                    guard let newID,
                          let region = GeopoliticalMapData.regionByID[newID]
                    else {
                        return
                    }

                    withAnimation(.easeOut(duration: 0.4)) {
                        if zoomScale < 2.5 {
                            zoomScale = 2.5
                            lastZoomScale = zoomScale
                        }

                        let targetOffset = CGSize(
                            width: (size.width / 2.0 - region.center.x * scaleX) * zoomScale,
                            height: (size.height / 2.0 - region.center.y * scaleY) * zoomScale
                        )
                        offset = clampOffset(targetOffset, size: size, zoom: zoomScale)
                        lastOffset = offset
                    }
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
            #if os(macOS)
                scenarioHeaderOverlay
            #endif
        }
        .overlay(alignment: .topTrailing) {
            #if os(macOS)
                layerSelectorOverlay
            #endif
        }
        .overlay(alignment: .bottomLeading) {
            #if os(macOS)
                legendOverlay
            #else
                if selectedRegionID == nil {
                    layerSelectorOverlay
                }
            #endif
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(NativeWarRoomTheme.brass.opacity(0.35), lineWidth: 1)
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
            for index in 1 ..< 6 {
                let x = size.width * CGFloat(index) / 6
                grid.move(to: CGPoint(x: x, y: 0))
                grid.addLine(to: CGPoint(x: x, y: size.height))
            }
            for index in 1 ..< 4 {
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

struct RegionDetailsCard: View {
    let region: MapRegion
    let state: NativeCampaignState
    let store: NativeCampaignStore
    @Binding var selectedRegionID: String?
    @State private var selectedDiplomaticTarget = false

    private func terrainModifiersText(for terrain: NativeTerrainType) -> String {
        switch terrain {
        case .mountain: "Defense +30%"
        case .strait: "Amphibious -25%"
        case .swamp: "Attrition +20%"
        case .forest: "Concealment +15%"
        case .city: "Urban Fort +15%"
        case .cerrado: "Maneuver -10%"
        case .ocean, .sea: "Naval -40%"
        case .plains: "Open +10%"
        }
    }

    var body: some View {
        let occupierCode = state.regionOccupations[region.id] ?? region.countryCode
        let conflict = state.regionConflicts[region.id]
        let originalCountryName = region.countryCode == "WATER"
            ? "International Waters"
            : (region.countryCode == "RUS" && state.scenarioID == "soviet-triumph"
                ? "Soviet Union"
                : CountryNameResolver.name(forCode: region.countryCode, in: state))
        let occupierCountryName = occupierCode == "WATER"
            ? "Uncontrolled"
            : (occupierCode == "RUS" && state.scenarioID == "soviet-triumph"
                ? "Soviet Union"
                : (occupierCode == "REB"
                    ? "Insurgents"
                    : CountryNameResolver.name(forCode: occupierCode, in: state)))

        let isOccupied = occupierCode != region.countryCode
        let isRebel = occupierCode == "REB" || conflict?.mode == .guerrillaControl
        let isFallout = state.nuclearFalloutRegions.contains(region.id) || conflict?.mode == .nuclearFallout
        let isContested = conflict?.mode == .contestedBorder
        let isStabilizing = conflict?.mode == .stabilization
        let ledger = state.economicLedgers[isRebel ? region.countryCode : occupierCode]
        let statusBadge: (label: String, tint: Color) = if isFallout {
            ("FALLOUT", NativeWarRoomTheme.alertAmber)
        } else if isRebel {
            ("GUERRILLA", .orange)
        } else if isContested {
            ("CONTESTED", NativeWarRoomTheme.alertAmber)
        } else if isStabilizing {
            ("STABILIZING", NativeWarRoomTheme.signalCyan)
        } else if isOccupied {
            ("OCCUPIED", NativeWarRoomTheme.threatRed)
        } else {
            ("SOVEREIGN", NativeWarRoomTheme.fieldGreen)
        }
        let standardCode = occupierCode == "WATER" || occupierCode == "REB" ? region.countryCode : occupierCode
        let canSelectDiplomacy = occupierCode != state.country.code && occupierCode != "WATER" && occupierCode != "REB"

        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                NativeCountryStandard(countryCode: standardCode, size: 30)

                VStack(alignment: .leading, spacing: 3) {
                    Text(region.name.uppercased())
                        .font(NativeWarRoomTheme.displayFont(.subheadline, weight: .bold))
                        .foregroundStyle(NativeWarRoomTheme.ink)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(statusBadge.label)
                            .font(.system(size: 9.5, weight: .black, design: .monospaced))
                            .foregroundStyle(statusBadge.tint)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(statusBadge.tint.opacity(0.14), in: Capsule())
                            .overlay {
                                Capsule().stroke(statusBadge.tint.opacity(0.45), lineWidth: 0.8)
                            }
                        Text(occupierCountryName)
                            .font(NativeWarRoomTheme.labelFont(.caption2, weight: .semibold))
                            .foregroundStyle(NativeWarRoomTheme.mutedInk)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 6)

                Button {
                    selectedRegionID = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(NativeWarRoomTheme.mutedInk)
                        .frame(width: 24, height: 24)
                        .background(NativeWarRoomTheme.archiveShadow.opacity(0.8), in: Circle())
                        .overlay {
                            Circle().stroke(NativeWarRoomTheme.brass.opacity(0.24), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close region dossier")
            }

            Rectangle()
                .fill(NativeWarRoomTheme.brass.opacity(0.22))
                .frame(height: 1)

            // Tactical 2-column telemetry grid
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], alignment: .leading, spacing: 8) {
                dossierStatCell(
                    label: "TERRAIN",
                    value: region.terrain.displayName,
                    badge: terrainModifiersText(for: region.terrain),
                    badgeTint: NativeWarRoomTheme.brass
                )

                dossierStatCell(
                    label: isOccupied ? "OCCUPIER / SOVEREIGN" : "SOVEREIGNTY",
                    value: isOccupied ? "\(occupierCountryName) (\(occupierCode))" : "\(originalCountryName) (\(region.countryCode))",
                    badge: isOccupied ? "Origin: \(region.countryCode)" : "Core",
                    badgeTint: isOccupied ? NativeWarRoomTheme.threatRed : NativeWarRoomTheme.fieldGreen
                )

                if let ledger {
                    dossierStatCell(
                        label: "GDP & GROWTH",
                        value: String(format: "$%.2fT", ledger.nominalGDPTrillions),
                        badge: String(format: "%+.1f%%", ledger.realGrowthPercent),
                        badgeTint: ledger.realGrowthPercent >= 0 ? NativeWarRoomTheme.fieldGreen : NativeWarRoomTheme.threatRed
                    )

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("SECURITY")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(NativeWarRoomTheme.mutedInk)
                            Spacer()
                            Text("\(Int(ledger.securityIndex.rounded()))/100")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(NativeWarRoomTheme.statusColor(for: Int(ledger.securityIndex.rounded())))
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(NativeWarRoomTheme.archiveShadow)
                                Capsule()
                                    .fill(NativeWarRoomTheme.statusColor(for: Int(ledger.securityIndex.rounded())))
                                    .frame(width: geo.size.width * max(0, min(1, ledger.securityIndex / 100.0)))
                            }
                        }
                        .frame(height: 4)
                        Text(String(format: "Insurgency %.1f%%", ledger.rebelControlPercent))
                            .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                            .foregroundStyle(ledger.rebelControlPercent >= 15 ? NativeWarRoomTheme.alertAmber : NativeWarRoomTheme.mutedInk)
                    }
                    .padding(7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(NativeWarRoomTheme.archiveShadow.opacity(0.65), in: RoundedRectangle(cornerRadius: 6))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(NativeWarRoomTheme.brass.opacity(0.14), lineWidth: 1)
                    }
                }
            }

            if let conflict {
                VStack(alignment: .leading, spacing: 3) {
                    Text("CONFLICT // \(conflict.mode.displayName.uppercased()) · INTENSITY \(conflict.intensity)/5")
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(NativeWarRoomTheme.alertAmber)
                    if !conflict.summary.isEmpty {
                        Text(conflict.summary)
                            .font(NativeWarRoomTheme.bodyFont(.caption2))
                            .foregroundStyle(NativeWarRoomTheme.mutedInk)
                            .lineLimit(2)
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(NativeWarRoomTheme.threatRed.opacity(0.10), in: RoundedRectangle(cornerRadius: 6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(NativeWarRoomTheme.threatRed.opacity(0.28), lineWidth: 1)
                }
            }

            let regionalActions = NativeQuickActionCatalog.regionalActions(for: region, state: state)
            if canSelectDiplomacy || !regionalActions.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text("REGIONAL ORDERS")
                            .font(NativeWarRoomTheme.labelFont(.caption2))
                            .foregroundStyle(NativeWarRoomTheme.brass)
                        Spacer()
                        if canSelectDiplomacy {
                            Button {
                                store.selectedDiplomaticPartnerCode = occupierCode
                                selectedDiplomaticTarget = true
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: selectedDiplomaticTarget ? "checkmark.circle.fill" : "bubble.left.and.bubble.right")
                                        .font(.caption2)
                                    Text(selectedDiplomaticTarget ? "Selected: \(occupierCode)" : "Select in Diplomacy")
                                        .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                                }
                                .foregroundStyle(selectedDiplomaticTarget ? NativeWarRoomTheme.fieldGreen : NativeWarRoomTheme.brass)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    (selectedDiplomaticTarget ? NativeWarRoomTheme.fieldGreen : NativeWarRoomTheme.brass).opacity(0.14),
                                    in: Capsule()
                                )
                                .overlay {
                                    Capsule()
                                        .stroke(
                                            (selectedDiplomaticTarget ? NativeWarRoomTheme.fieldGreen : NativeWarRoomTheme.brass).opacity(0.42),
                                            lineWidth: 1
                                        )
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    ForEach(regionalActions) { action in
                        Button {
                            store.draftAction = action.directiveTemplate
                            store.addDraftAction()
                            selectedRegionID = nil
                        } label: {
                            HStack {
                                Image(systemName: action.category.systemImage)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(action.title)
                                        .font(.caption.weight(.bold))
                                    Text(action.primaryEffects.joined(separator: " · "))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("\(action.cost)")
                                    .font(.system(.caption, design: .monospaced).weight(.black))
                            }
                            .frame(maxWidth: .infinity, minHeight: 34)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(action.category == .military ? Color.softRed.opacity(0.85) : Color.glowingCyan.opacity(0.8))
                        .disabled(state.administrativeCapacity < action.cost)
                        .accessibilityIdentifier("native-region-action-\(action.id)")
                    }
                }
            }
        }
        .padding(13)
        .warRoomDossier(borderColor: NativeWarRoomTheme.brass.opacity(0.32), cornerRadius: 10)
        .padding(14)
        .frame(maxWidth: 440)
        .onChange(of: region.id) { _, _ in
            selectedDiplomaticTarget = false
        }
        .accessibilityIdentifier("native-region-dossier")
    }

    private func dossierStatCell(label: String, value: String, badge: String, badgeTint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(NativeWarRoomTheme.mutedInk)
                .lineLimit(1)
            Text(value)
                .font(NativeWarRoomTheme.bodyFont(.caption, weight: .semibold))
                .foregroundStyle(NativeWarRoomTheme.ink)
                .lineLimit(1)
            Text(badge)
                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                .foregroundStyle(badgeTint)
                .lineLimit(1)
        }
        .padding(7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NativeWarRoomTheme.archiveShadow.opacity(0.65), in: RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(NativeWarRoomTheme.brass.opacity(0.14), lineWidth: 1)
        }
    }
}
