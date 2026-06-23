import Foundation
import SwiftData

enum NativeArmyKind: String, Codable, CaseIterable, Hashable, Identifiable {
    case infantry
    case armor
    case air
    case naval

    var id: String {
        rawValue
    }

    var mapGlyph: String {
        switch self {
        case .infantry: "person.3.fill"
        case .armor: "shield.lefthalf.filled"
        case .air: "airplane"
        case .naval: "ferry.fill"
        }
    }
}

struct NativeArmySnapshot: Codable, Hashable, Identifiable {
    var countryCode: String
    var currentRegionID: String
    var id: String
    var strength: Int
    var targetRegionID: String?
    var type: NativeArmyKind

    init(
        countryCode: String,
        currentRegionID: String,
        id: String = UUID().uuidString,
        strength: Int,
        targetRegionID: String? = nil,
        type: NativeArmyKind
    ) {
        self.countryCode = countryCode
        self.currentRegionID = currentRegionID
        self.id = id
        self.strength = max(1, strength)
        self.targetRegionID = targetRegionID
        self.type = type
    }
}

/// Representa um exército ativo no mapa, capaz de se mover e combater.
@Model
final class NativeArmyModel {
    @Attribute(.unique) var id: String
    var countryCode: String
    var type: String // ex: "infantry", "armor", "air", "naval"
    var strength: Int

    // Localização
    var currentRegionID: String?
    var targetRegionID: String?

    init(
        id: String = UUID().uuidString,
        countryCode: String,
        type: NativeArmyKind,
        strength: Int,
        currentRegionID: String? = nil,
        targetRegionID: String? = nil
    ) {
        self.id = id
        self.countryCode = countryCode
        self.type = type.rawValue
        self.strength = max(1, strength)
        self.currentRegionID = currentRegionID
        self.targetRegionID = targetRegionID
    }

    convenience init(snapshot: NativeArmySnapshot) {
        self.init(
            id: snapshot.id,
            countryCode: snapshot.countryCode,
            type: snapshot.type,
            strength: snapshot.strength,
            currentRegionID: snapshot.currentRegionID,
            targetRegionID: snapshot.targetRegionID
        )
    }

    var snapshot: NativeArmySnapshot? {
        guard let currentRegionID else { return nil }
        return NativeArmySnapshot(
            countryCode: countryCode,
            currentRegionID: currentRegionID,
            id: id,
            strength: strength,
            targetRegionID: targetRegionID,
            type: NativeArmyKind(rawValue: type) ?? .infantry
        )
    }
}
