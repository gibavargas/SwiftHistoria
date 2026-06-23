import Foundation
import SwiftData

/// Central database context for new map features (Armies, Buildings).
@MainActor
final class NativeDatabaseContext {
    static let shared: NativeDatabaseContext = {
        do {
            return try NativeDatabaseContext()
        } catch {
            fatalError("Could not create NativeDatabaseContext: \(error)")
        }
    }()

    let container: ModelContainer

    var context: ModelContext {
        container.mainContext
    }

    init(inMemory: Bool = false) throws {
        let schema = Schema([
            NativeArmyModel.self,
            NativeBuildingModel.self
        ])

        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        container = try ModelContainer(for: schema, configurations: [modelConfiguration])
    }

    func replaceStrategicMapState(
        armies: [NativeArmySnapshot],
        buildings: [NativeBuildingSnapshot]
    ) throws {
        try deleteAll(NativeArmyModel.self)
        try deleteAll(NativeBuildingModel.self)

        for army in armies {
            context.insert(NativeArmyModel(snapshot: army))
        }
        for building in buildings {
            context.insert(NativeBuildingModel(snapshot: building))
        }
        try context.save()
    }

    func armies(in regionID: String) throws -> [NativeArmySnapshot] {
        let descriptor = FetchDescriptor<NativeArmyModel>(
            predicate: #Predicate { $0.currentRegionID == regionID },
            sortBy: [SortDescriptor(\.strength, order: .reverse)]
        )
        return try context.fetch(descriptor).compactMap(\.snapshot)
    }

    func buildings(in regionID: String) throws -> [NativeBuildingSnapshot] {
        let descriptor = FetchDescriptor<NativeBuildingModel>(
            predicate: #Predicate { $0.regionID == regionID },
            sortBy: [SortDescriptor(\.level, order: .reverse)]
        )
        return try context.fetch(descriptor).map(\.snapshot)
    }

    func allArmies() throws -> [NativeArmySnapshot] {
        try context.fetch(FetchDescriptor<NativeArmyModel>()).compactMap(\.snapshot)
    }

    func allBuildings() throws -> [NativeBuildingSnapshot] {
        try context.fetch(FetchDescriptor<NativeBuildingModel>()).map(\.snapshot)
    }

    private func deleteAll<Model: PersistentModel>(_: Model.Type) throws {
        for model in try context.fetch(FetchDescriptor<Model>()) {
            context.delete(model)
        }
    }
}
