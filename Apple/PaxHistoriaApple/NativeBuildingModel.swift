import Foundation
import SwiftData

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

/// Representa uma infraestrutura construída em uma região do mapa.
@Model
final class NativeBuildingModel {
    @Attribute(.unique) var id: String
    var regionID: String
    var type: String // ex: "fortress", "market", "barracks", "port"
    var ownerCountryCode: String
    var level: Int

    init(
        id: String = UUID().uuidString,
        regionID: String,
        type: NativeBuildingKind,
        ownerCountryCode: String,
        level: Int = 1
    ) {
        self.id = id
        self.regionID = regionID
        self.type = type.rawValue
        self.ownerCountryCode = ownerCountryCode
        self.level = max(1, min(5, level))
    }

    convenience init(snapshot: NativeBuildingSnapshot) {
        self.init(
            id: snapshot.id,
            regionID: snapshot.regionID,
            type: snapshot.type,
            ownerCountryCode: snapshot.ownerCountryCode,
            level: snapshot.level
        )
    }

    var snapshot: NativeBuildingSnapshot {
        NativeBuildingSnapshot(
            id: id,
            level: level,
            ownerCountryCode: ownerCountryCode,
            regionID: regionID,
            type: NativeBuildingKind(rawValue: type) ?? .barracks
        )
    }
}
