import Foundation

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

    static func militaryUnits(
        from armies: [NativeArmySnapshot],
        countryCode: String,
        fallback: [String: Int] = [:]
    ) -> [String: Int] {
        let countryArmies = armies.filter { $0.countryCode == countryCode }
        guard !countryArmies.isEmpty else { return fallback }
        var counts = fallback
        for kind in NativeArmyKind.allCases {
            let matching = countryArmies.filter { $0.type == kind }
            if !matching.isEmpty {
                counts[kind.rawValue] = matching.reduce(0) { $0 + max(0, $1.strength) }
            }
        }
        return counts
    }

    static func synchronizingArmies(
        _ armies: [NativeArmySnapshot],
        with units: [String: Int],
        countryCode: String,
        homeRegionID: String
    ) -> [NativeArmySnapshot] {
        let totalUnits = max(1, units.values.reduce(0, +))
        let dominantType: NativeArmyKind = (units["armor"] ?? 0) > (units["infantry"] ?? 0) ? .armor : .infantry
        var updated = armies
        if let index = updated.firstIndex(where: { $0.countryCode == countryCode }) {
            updated[index].strength = max(1, min(999, totalUnits))
            updated[index].type = dominantType
        } else {
            updated.append(
                NativeArmySnapshot(
                    countryCode: countryCode,
                    currentRegionID: homeRegionID,
                    id: "army-\(countryCode)-\(homeRegionID)",
                    strength: max(1, min(999, totalUnits)),
                    type: dominantType
                )
            )
        }
        return updated
    }
}
