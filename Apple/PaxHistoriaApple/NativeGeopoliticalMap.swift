import MapKit
import SwiftUI

/// Reverse-projection from the 1000×600 Web Mercator canvas space used by
/// `MapProjection.project` back to real geographic coordinates.
enum MapProjectionInverse {
    /// Converts a CGPoint in 1000×600 projected space to a lat/lon coordinate.
    static func toCoordinate(_ point: CGPoint) -> CLLocationCoordinate2D {
        let lon = Double(point.x) * (360.0 / 1000.0) - 180.0
        let merc = (300.0 - Double(point.y)) * (.pi / 300.0)
        let lat = (2.0 * atan(exp(merc)) - .pi / 2.0) * (180.0 / .pi)
        let clampedLat = max(-85.0511, min(85.0511, lat))
        return CLLocationCoordinate2D(latitude: clampedLat, longitude: lon)
    }

    static func toCoordinates(_ points: [CGPoint]) -> [CLLocationCoordinate2D] {
        points.map { toCoordinate($0) }
    }
}

/// MapKit-based geopolitical map with tappable country annotations.
/// Replaces the hand-drawn Canvas with a real world map. Tapping a country
/// shows the region details card with terrain, occupation, and invasion.
struct NativeGeopoliticalMap: View {
    let state: NativeCampaignState
    var store: NativeCampaignStore?

    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var selectedRegionID: String? = nil

    private var playerCountryCode: String {
        state.country.code
    }

    private var overlayTopPadding: CGFloat {
        #if os(iOS)
            56
        #else
            12
        #endif
    }

    /// Build polygon coordinates from GeopoliticalMapData region paths once.
    ///
    /// This was previously a computed property, which rebuilt every coordinate
    /// array whenever SwiftUI recomputed the map body. MapKit owns GPU rendering
    /// after the polygons are submitted, so the best CPU win here is to stop
    /// re-projecting static geopolitical geometry on every state/UI refresh.
    private static let regionPolygons: [(id: String, region: MapRegion, coords: [CLLocationCoordinate2D])] =
        GeopoliticalMapData.nonWaterRegions.flatMap { region in
            region.paths.enumerated().compactMap { index, ring in
                guard ring.count >= 3 else {
                    return nil
                }
                let coords = MapProjectionInverse.toCoordinates(ring)
                guard coords.count >= 3 else { return nil }
                return ("\(region.id)-ring-\(index)", region, coords)
            }
        }

    /// Relation-based fill color for a region.
    private func fillColor(for region: MapRegion) -> Color {
        if GeopoliticalMapData.canonicalCountryCode(region.countryCode) == GeopoliticalMapData.canonicalCountryCode(playerCountryCode) {
            return Color.glowingCyan.opacity(0.35)
        }
        if let conflict = state.regionConflicts[region.id] {
            switch conflict.mode {
            case .conventionalOccupation, .contestedBorder:
                return Color.softRed.opacity(0.3)
            default:
                return Color.alertGold.opacity(0.2)
            }
        }
        return Color.gray.opacity(0.15)
    }

    private func annotationDotSize(isPlayer: Bool) -> CGFloat {
        #if os(iOS)
            isPlayer ? 14 : 10
        #else
            12
        #endif
    }

    @ViewBuilder
    private func annotationCaption(name: String, isPlayer: Bool) -> some View {
        #if os(iOS)
            if isPlayer {
                annotationLabel(name: name, isPlayer: true)
            }
        #else
            annotationLabel(name: name, isPlayer: isPlayer)
        #endif
    }

    private func annotationLabel(name: String, isPlayer: Bool) -> some View {
        Text(name)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                isPlayer
                    ? Color.glowingCyan.opacity(0.35)
                    : Color.black.opacity(0.6),
                in: Capsule()
            )
            .overlay {
                Capsule().stroke(.white.opacity(0.15), lineWidth: 0.5)
            }
    }

    /// One annotation per selectable country, using real coordinates from CountryCoordinate.
    /// Tapping selects the nearest region to the country center when detailed geometry exists.
    private static let countryAnnotations: [(code: String, name: String, coord: CLLocationCoordinate2D, regionID: String?)] = {
        var result: [(String, String, CLLocationCoordinate2D, String?)] = []
        for country in CountryCatalog.all {
            let coord = CountryCoordinate.center(for: country.code)
            let regions = GeopoliticalMapData.regions(forCountryCode: country.code)
            let hasCityFallback = !GeopoliticalMapData.cities(forCountryCode: country.code).isEmpty
            guard !regions.isEmpty || hasCityFallback else { continue }
            result.append((country.code, country.name, coord, representativeRegionID(in: regions, near: coord)))
        }
        return result
    }()

    private static func representativeRegionID(in regions: [MapRegion], near coordinate: CLLocationCoordinate2D) -> String? {
        guard !regions.isEmpty else { return nil }
        let projected = MapProjection.project(longitude: coordinate.longitude, latitude: coordinate.latitude)
        return regions.min { left, right in
            distanceSquared(left.center, projected) < distanceSquared(right.center, projected)
        }?.id
    }

    private static func distanceSquared(_ lhs: CGPoint, _ rhs: CGPoint) -> CGFloat {
        let dx = lhs.x - rhs.x
        let dy = lhs.y - rhs.y
        return dx * dx + dy * dy
    }

    var body: some View {
        ZStack {
            Map(position: $cameraPosition) {
                ForEach(Self.regionPolygons, id: \.id) { item in
                    MapPolygon(coordinates: item.coords)
                        .foregroundStyle(fillColor(for: item.region))
                }

                ForEach(Self.countryAnnotations, id: \.code) { entry in
                    Annotation(entry.name, coordinate: entry.coord) {
                        Button {
                            if let regionID = entry.regionID {
                                selectedRegionID = regionID
                            }
                        } label: {
                            VStack(spacing: 2) {
                                let isPlayer = entry.code == playerCountryCode
                                Circle()
                                    .fill(isPlayer ? Color.glowingCyan : Color.white.opacity(0.7))
                                    .frame(width: annotationDotSize(isPlayer: isPlayer), height: annotationDotSize(isPlayer: isPlayer))
                                    .shadow(color: isPlayer ? Color.glowingCyan.opacity(0.6) : .clear, radius: 6)
                                    .overlay {
                                        Circle()
                                            .stroke(.white.opacity(0.3), lineWidth: 1)
                                    }

                                annotationCaption(name: entry.name, isPlayer: isPlayer)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(entry.name), \(relationWord(for: entry.code)), \(stabilityWord(for: entry.code))")
                        .accessibilityHint(entry.regionID == nil ? "Country appears as a city marker on the strategic map." : "Select country on the strategic map.")
                        .accessibilityIdentifier("native-map-country-\(entry.code)")
                    }
                    .annotationTitles(.hidden)
                    .annotationSubtitles(.hidden)
                }
            }
            .mapStyle(.standard(elevation: .flat))
            .mapControls {
                MapCompass()
                MapScaleView()
            }
            .background(Color.spaceBlack)
            .onAppear {
                let center = CountryCoordinate.center(for: playerCountryCode)
                cameraPosition = .region(MKCoordinateRegion(
                    center: center,
                    latitudinalMeters: 4_000_000,
                    longitudinalMeters: 4_000_000
                ))
            }

            #if os(macOS)
                // Legend overlay — color key for relations and conflict states
                VStack {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Circle().fill(Color.glowingCyan).frame(width: 7, height: 7)
                                Text("Player").font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundStyle(.white)
                            }
                            HStack(spacing: 6) {
                                Circle().fill(Color.softRed.opacity(0.7)).frame(width: 7, height: 7)
                                Text("Conflict").font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundStyle(.white)
                            }
                            HStack(spacing: 6) {
                                Circle().fill(Color.alertGold.opacity(0.7)).frame(width: 7, height: 7)
                                Text("Tension").font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundStyle(.white)
                            }
                            HStack(spacing: 6) {
                                Circle().fill(Color.gray.opacity(0.5)).frame(width: 7, height: 7)
                                Text("Neutral").font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundStyle(.white)
                            }
                        }
                        Spacer()
                    }
                    .padding(10)
                    .background(Color.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.12), lineWidth: 1)
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, overlayTopPadding)
                    .allowsHitTesting(false)
                    Spacer()
                }

                // Scenario header overlay (top-right)
                VStack {
                    HStack {
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(state.scenarioName)
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                            Text("\(state.gameDate) · \(state.worldTension)/100")
                                .font(.system(size: 11, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                        .padding(10)
                        .background(Color.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 8))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.12), lineWidth: 1)
                        }
                        .padding(.horizontal, 12)
                        .padding(.top, overlayTopPadding)
                        .allowsHitTesting(false)
                    }
                    Spacer()
                }
            #endif

            // Region details overlay — same card the Canvas map used
            if let regionID = selectedRegionID,
               let region = GeopoliticalMapData.regionByID[regionID],
               let store
            {
                VStack {
                    Spacer()
                    RegionDetailsCard(
                        region: region,
                        state: state,
                        store: store,
                        selectedRegionID: $selectedRegionID
                    )
                    .padding(12)
                }
            }
        }
    }

    // MARK: - Accessibility helpers

    private func relationWord(for code: String) -> String {
        if code == playerCountryCode { return "your nation" }
        if let relations = state.aiCountryStates[code]?.relationshipScores[playerCountryCode] {
            if relations > 50 { return "ally" }
            if relations < -30 { return "rival" }
            return "neutral"
        }
        return "neutral"
    }

    private func stabilityWord(for code: String) -> String {
        if let ledger = state.economicLedgers[code] {
            if ledger.securityIndex >= 80 { return "stable" }
            if ledger.securityIndex < 40 { return "unstable" }
            return "moderate stability"
        }
        return "unknown stability"
    }
}

#if DEBUG
    struct NativeWorldMapCanvas: View {
        let state: NativeCampaignState
        let minHeight: CGFloat

        init(state: NativeCampaignState, minHeight: CGFloat = 300) {
            self.state = state
            self.minHeight = minHeight
        }

        var body: some View {
            NativeWorldMap(state: state, minHeight: minHeight)
        }
    }
#endif
