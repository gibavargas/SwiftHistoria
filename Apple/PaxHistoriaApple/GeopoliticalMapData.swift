import Foundation
import SwiftUI

struct MapRegion: Identifiable, Hashable {
    let id: String // e.g. "USA_WEST", "CHN_NORTH"
    let countryCode: String // e.g. "USA", "CHN"
    let name: String
    let paths: [[CGPoint]] // Supports multiple polygons/islands
    let center: CGPoint
    let terrain: NativeTerrainType
    let path: Path // Pre-built SwiftUI Path in 1000x600 space

    // ponytail: manual identity equality to bypass non-hashable SwiftUI Path
    static func == (lhs: MapRegion, rhs: MapRegion) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

struct LandmassOutline: Identifiable, Hashable {
    let id: String
    let paths: [[CGPoint]]
    let path: Path // Pre-built SwiftUI Path in 1000x600 space

    // ponytail: manual identity equality to bypass non-hashable SwiftUI Path
    static func == (lhs: LandmassOutline, rhs: LandmassOutline) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

struct PopulatedPlace: Identifiable, Hashable {
    let id: String
    let name: String
    let countryCode: String
    let coordinate: CGPoint
    let population: Int
    let isCapital: Bool
}

enum MapProjection {
    static func project(longitude: Double, latitude: Double) -> CGPoint {
        // Map longitude [-180, 180] to X [0, 1000]
        let x = (longitude + 180.0) * (1000.0 / 360.0)

        // Web Mercator mapping for latitude
        let clampedLat = max(-85.0511, min(85.0511, latitude))
        let latRad = clampedLat * .pi / 180.0
        let merc = log(tan(.pi / 4.0 + latRad / 2.0))

        // Map mercator range [-3.137, 3.137] to Y [0, 600]
        // Since Y increases downwards: Y = 300 - merc * (300.0 / 3.137)
        let y = 300.0 - merc * (300.0 / 3.137)

        return CGPoint(x: x, y: y)
    }
}

enum GeopoliticalMapData {
    static let landmasses: [LandmassOutline] = {
        loadData()
        return _landmasses
    }()

    static let regions: [MapRegion] = {
        loadData()
        return _regions
    }()

    static let states: [MapRegion] = {
        loadData()
        return _states
    }()

    static let cities: [PopulatedPlace] = {
        loadData()
        return _cities
    }()

    static let regionByID: [String: MapRegion] = {
        loadData()
        return Dictionary(uniqueKeysWithValues: _regions.map { ($0.id, $0) })
    }()

    static let regionsByCountry: [String: [MapRegion]] = {
        loadData()
        return Dictionary(grouping: _regions, by: \.countryCode)
    }()

    static let nonWaterRegions: [MapRegion] = {
        loadData()
        return _regions.filter { $0.countryCode != "WATER" }
    }()

    static func canonicalCountryCode(_ code: String) -> String {
        switch code.uppercased() {
        case "PSE":
            "PSX"
        case "XXK":
            "KOS"
        default:
            code.uppercased()
        }
    }

    static func regions(forCountryCode code: String) -> [MapRegion] {
        regionsByCountry[canonicalCountryCode(code), default: []]
    }

    static func cities(forCountryCode code: String) -> [PopulatedPlace] {
        let canonical = canonicalCountryCode(code)
        return cities.filter { canonicalCountryCode($0.countryCode) == canonical }
    }

    static func prewarm() {
        loadData()
    }

    private static let loadLock = NSLock()
    private nonisolated(unsafe) static var _landmasses: [LandmassOutline] = []
    private nonisolated(unsafe) static var _regions: [MapRegion] = []
    private nonisolated(unsafe) static var _states: [MapRegion] = []
    private nonisolated(unsafe) static var _cities: [PopulatedPlace] = []
    private nonisolated(unsafe) static var isLoaded = false

    private static func createPath(from paths: [[CGPoint]]) -> Path {
        var path = Path()
        for ring in paths {
            if !ring.isEmpty {
                path.addLines(ring)
                path.closeSubpath()
            }
        }
        return path
    }

    private static func loadData() {
        loadLock.lock()
        defer { loadLock.unlock() }
        guard !isLoaded else { return }

        let decoder = JSONDecoder()

        // 1. Load Landmasses
        if let landURL = Bundle.main.url(forResource: "land", withExtension: "geojson"),
           let landData = try? Data(contentsOf: landURL),
           let landCollection = try? decoder.decode(GeoJSONFeatureCollection.self, from: landData)
        {
            _landmasses = landCollection.features.compactMap { feature -> LandmassOutline? in
                let paths = extractPaths(from: feature.geometry)
                guard !paths.isEmpty else { return nil }
                let id = feature.properties.id ?? "lm_\(UUID().uuidString.prefix(6))"
                let path = createPath(from: paths)
                return LandmassOutline(id: id, paths: paths, path: path)
            }
        }

        // 2. Load States
        if let statesURL = Bundle.main.url(forResource: "states", withExtension: "geojson"),
           let statesData = try? Data(contentsOf: statesURL),
           let statesCollection = try? decoder.decode(GeoJSONFeatureCollection.self, from: statesData)
        {
            _states = statesCollection.features.compactMap { feature -> MapRegion? in
                let paths = extractPaths(from: feature.geometry)
                guard !paths.isEmpty else { return nil }

                let id = feature.properties.id ?? "STATE_\(UUID().uuidString.prefix(6))"
                let name = feature.properties.name ?? "Unknown State"
                let countryCode = feature.properties.country_id ?? "UNK"

                let center = computeCenter(for: paths)
                let terrain = determineTerrain(for: id, countryCode: countryCode, name: name)
                let path = createPath(from: paths)

                return MapRegion(
                    id: id,
                    countryCode: countryCode,
                    name: name,
                    paths: paths,
                    center: center,
                    terrain: terrain,
                    path: path
                )
            }
        }

        // 3. Load Countries
        var tempCountries: [MapRegion] = []
        if let countriesURL = Bundle.main.url(forResource: "countries", withExtension: "geojson"),
           let countriesData = try? Data(contentsOf: countriesURL),
           let countriesCollection = try? decoder.decode(GeoJSONFeatureCollection.self, from: countriesData)
        {
            tempCountries = countriesCollection.features.compactMap { feature -> MapRegion? in
                let paths = extractPaths(from: feature.geometry)
                guard !paths.isEmpty else { return nil }

                let id = feature.properties.id ?? "REG_\(UUID().uuidString.prefix(6))"
                let name = feature.properties.name ?? "Unknown Region"
                let countryCode = id // For countries, ADM0_A3 acts as both ID and countryCode

                let center = computeCenter(for: paths)
                let terrain = determineTerrain(for: id, countryCode: countryCode, name: name)
                let path = createPath(from: paths)

                return MapRegion(
                    id: id,
                    countryCode: countryCode,
                    name: name,
                    paths: paths,
                    center: center,
                    terrain: terrain,
                    path: path
                )
            }
        }

        // 4. Combine into primary _regions: all states + countries that are not subdivided
        let subdividedCountryCodes = Set(_states.map(\.countryCode))
        let nonSubdividedCountries = tempCountries.filter { !subdividedCountryCodes.contains($0.id) }
        _regions = _states + nonSubdividedCountries

        // 5. Load Cities (Populated Places)
        if let citiesURL = Bundle.main.url(forResource: "cities", withExtension: "geojson"),
           let citiesData = try? Data(contentsOf: citiesURL),
           let citiesCollection = try? decoder.decode(GeoJSONFeatureCollection.self, from: citiesData)
        {
            _cities = citiesCollection.features.compactMap { feature -> PopulatedPlace? in
                // Cities should be Point geometry
                guard case let .point(coords) = feature.geometry, coords.count >= 2 else { return nil }

                let name = feature.properties.name ?? "Unknown City"
                let countryCode = feature.properties.country_id ?? "UNK"
                let coordinate = MapProjection.project(longitude: coords[0], latitude: coords[1])
                let population = feature.properties.pop ?? 0
                let isCapital = feature.properties.is_capital ?? false
                let id = "\(countryCode)_\(name.replacingOccurrences(of: " ", with: "_"))"

                return PopulatedPlace(
                    id: id,
                    name: name,
                    countryCode: countryCode,
                    coordinate: coordinate,
                    population: population,
                    isCapital: isCapital
                )
            }
        }
        isLoaded = true
    }

    private static func extractPaths(from geometry: GeoJSONGeometry) -> [[CGPoint]] {
        var paths: [[CGPoint]] = []
        switch geometry {
        case let .point(coords):
            if coords.count >= 2 {
                let pt = MapProjection.project(longitude: coords[0], latitude: coords[1])
                paths.append([pt])
            }
        case let .polygon(rings):
            for ring in rings {
                var pts: [CGPoint] = []
                for coord in ring {
                    if coord.count >= 2 {
                        pts.append(MapProjection.project(longitude: coord[0], latitude: coord[1]))
                    }
                }
                if !pts.isEmpty {
                    paths.append(pts)
                }
            }
        case let .multiPolygon(polygons):
            for polygon in polygons {
                for ring in polygon {
                    var pts: [CGPoint] = []
                    for coord in ring {
                        if coord.count >= 2 {
                            pts.append(MapProjection.project(longitude: coord[0], latitude: coord[1]))
                        }
                    }
                    if !pts.isEmpty {
                        paths.append(pts)
                    }
                }
            }
        }
        return paths
    }

    private static func computeCenter(for paths: [[CGPoint]]) -> CGPoint {
        var totalX: CGFloat = 0
        var totalY: CGFloat = 0
        var count: CGFloat = 0

        for path in paths {
            for pt in path {
                totalX += pt.x
                totalY += pt.y
                count += 1
            }
        }

        if count > 0 {
            return CGPoint(x: totalX / count, y: totalY / count)
        }
        return .zero
    }

    private static func determineTerrain(for id: String, countryCode: String, name: String) -> NativeTerrainType {
        if countryCode == "WATER" {
            if id.contains("STRAIT") || id.contains("CANAL") || id.contains("GIBRALTAR") {
                return .strait
            }
            if id.contains("SEA") || id.contains("MEDITERRANEAN") {
                return .sea
            }
            return .ocean
        }

        // Geographical keyword-based terrain determination
        let upperName = name.uppercased()
        let upperID = id.uppercased()

        // Mountain ranges
        let mountainKeywords = [
            "ALPS", "HIMALAYA", "ANDES", "ROCKIES", "SICHUAN", "TIBET", "COLORADO", "SWITZERLAND",
            "NEPAL", "KASHMIR", "KILIMANJARO", "URALS", "CAUCASUS", "APPALACHIAN", "ANDORRA", "SIERRA"
        ]
        for kw in mountainKeywords {
            if upperName.contains(kw) || upperID.contains(kw) {
                return .mountain
            }
        }

        // Forests and Swamps
        let forestKeywords = ["AMAZON", "PARA", "CONGO", "GABON", "INDONESIA", "BORNEO", "SUMATRA"]
        for kw in forestKeywords {
            if upperName.contains(kw) || upperID.contains(kw) {
                return .forest
            }
        }

        let swampKeywords = ["SWAMP", "PANTANAL", "EVERGLADES", "BAYOU", "MISSISSIPPI"]
        for kw in swampKeywords {
            if upperName.contains(kw) || upperID.contains(kw) {
                return .swamp
            }
        }

        // Arid and Cerrado
        let cerradoKeywords = [
            "SAHARA", "GOBI", "ARABIA", "NEVADA", "ARIZONA", "XINJIANG", "UTAH", "CERRADO",
            "CALIFORNIA", "TEXAS", "OUTBACK", "KALAHARI", "NAMIBA", "SAHEL"
        ]
        for kw in cerradoKeywords {
            if upperName.contains(kw) || upperID.contains(kw) {
                return .cerrado
            }
        }

        // Deterministic land terrain assignment using a stable process-independent hash.
        let index = Int(stableHash("\(countryCode)|\(id)|\(name)") % 5)
        switch index {
        case 0: return .forest
        case 1: return .cerrado
        case 2: return .swamp
        case 3: return .mountain
        default: return .plains
        }
    }

    private static func stableHash(_ value: String) -> UInt64 {
        var hash: UInt64 = 1_469_598_103_934_665_603
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return hash
    }
}

// MARK: - GeoJSON Codable Decoders

struct GeoJSONFeatureCollection: Decodable {
    let type: String
    let features: [GeoJSONFeature]
}

struct GeoJSONFeature: Decodable {
    let type: String
    let geometry: GeoJSONGeometry
    let properties: GeoJSONProperties
}

struct GeoJSONProperties: Decodable {
    let id: String?
    let name: String?
    let continent: String?
    let country_id: String?
    let pop: Int?
    let is_capital: Bool?
}

enum GeoJSONGeometry: Decodable {
    case point([Double])
    case polygon([[[Double]]])
    case multiPolygon([[[[Double]]]])

    private enum CodingKeys: String, CodingKey {
        case type
        case coordinates
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "Point":
            let coords = try container.decode([Double].self, forKey: .coordinates)
            self = .point(coords)
        case "Polygon":
            let coords = try container.decode([[[Double]]].self, forKey: .coordinates)
            self = .polygon(coords)
        case "MultiPolygon":
            let coords = try container.decode([[[[Double]]]].self, forKey: .coordinates)
            self = .multiPolygon(coords)
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unsupported geometry type")
        }
    }
}
