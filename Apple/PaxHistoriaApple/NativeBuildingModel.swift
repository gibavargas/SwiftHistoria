import Foundation

enum NativeBuildingKind: String, Codable, CaseIterable, Hashable, Identifiable {
    case fortress
    case market
    case barracks
    case port

    var id: String {
        rawValue
    }

    var mapGlyph: String {
        switch self {
        case .fortress: "shield.fill"
        case .market: "chart.line.uptrend.xyaxis"
        case .barracks: "building.2.fill"
        case .port: "anchor"
        }
    }
}

struct NativeBuildingSnapshot: Codable, Hashable, Identifiable {
    var id: String
    var level: Int
    var ownerCountryCode: String
    var regionID: String
    var type: NativeBuildingKind

    init(
        id: String = UUID().uuidString,
        level: Int = 1,
        ownerCountryCode: String,
        regionID: String,
        type: NativeBuildingKind
    ) {
        self.id = id
        self.level = max(1, min(5, level))
        self.ownerCountryCode = ownerCountryCode
        self.regionID = regionID
        self.type = type
    }
}
