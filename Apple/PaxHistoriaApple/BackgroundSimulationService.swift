import CoreGraphics
import Foundation
import OSLog

/// Serviço responsável por rodar a simulação não-verbal de background para os países IA.
/// Usa o Neural Engine para inferência rápida das políticas de IA (onde mover exércitos, etc).
final class BackgroundSimulationService: Sendable {
    static let shared = BackgroundSimulationService()

    private let logger = Logger(subsystem: "SwiftHistoria", category: "BackgroundSimulation")

    private init() {}

    /// Roda um passo da simulação para todos os países não-jogadores.
    func simulateTurn(currentState: NativeCampaignState) async -> NativeCampaignState {
        simulatedTurn(currentState)
    }

    /// Deterministic fallback policy. The feature extraction mirrors the shape
    /// expected by a future CoreML policy model, so the call site does not need
    /// to change when `CountryPolicyAgent.mlmodel` is added to the app bundle.
    func simulatedTurn(_ currentState: NativeCampaignState) -> NativeCampaignState {
        var nextState = currentState
        let seedDate = currentState.gameDate
        let aiStates = currentState.aiCountryStates.isEmpty
            ? NativeStrategyContextDatabase.initialAICountryStates(for: currentState.scenarioID)
            : currentState.aiCountryStates
        let actorCodes = Array(aiStates.keys.sorted().prefix(24))
        guard !actorCodes.isEmpty else { return nextState }

        var armiesByCountry = Dictionary(grouping: nextState.mapArmies, by: \.countryCode)
        var buildings = nextState.mapBuildings
        var generatedEvents: [NativeCampaignEvent] = []

        for code in actorCodes where code != currentState.country.code {
            guard let aiState = aiStates[code],
                  let homeRegion = preferredRegion(for: code)
            else { continue }

            if armiesByCountry[code, default: []].isEmpty {
                armiesByCountry[code, default: []].append(startingArmy(for: code, regionID: homeRegion.id, state: currentState))
            }

            let featureVector = policyFeatures(for: code, aiState: aiState, state: currentState)
            let policy = policyAction(for: code, features: featureVector, aiState: aiState, state: currentState)

            switch policy {
            case .fortify:
                if !buildings.contains(where: { $0.regionID == homeRegion.id && $0.ownerCountryCode == code && $0.type == .fortress }) {
                    buildings.append(NativeBuildingSnapshot(ownerCountryCode: code, regionID: homeRegion.id, type: .fortress))
                    generatedEvents.append(simulationEvent(
                        code: code,
                        date: seedDate,
                        idSuffix: "fortify-\(homeRegion.id)",
                        summary: "\(code) hardens defensive logistics in \(homeRegion.name).",
                        tensionDelta: 1,
                        title: "\(code) fortifies \(homeRegion.name)"
                    ))
                }
            case .invest:
                if !buildings.contains(where: { $0.regionID == homeRegion.id && $0.ownerCountryCode == code && $0.type == .market }) {
                    buildings.append(NativeBuildingSnapshot(ownerCountryCode: code, regionID: homeRegion.id, type: .market))
                    generatedEvents.append(simulationEvent(
                        code: code,
                        date: seedDate,
                        idSuffix: "market-\(homeRegion.id)",
                        summary: "\(code) expands civil infrastructure around \(homeRegion.name).",
                        tensionDelta: -1,
                        title: "\(code) funds regional infrastructure"
                    ))
                }
            case .moveToBorder:
                guard let targetRegion = borderRegion(for: code, excluding: currentState.country.code) else { continue }
                var armies = armiesByCountry[code, default: []]
                guard var army = armies.first else { continue }
                army.targetRegionID = targetRegion.id
                army.currentRegionID = targetRegion.id
                armies[0] = army
                armiesByCountry[code] = armies
                generatedEvents.append(simulationEvent(
                    code: code,
                    date: seedDate,
                    idSuffix: "move-\(targetRegion.id)",
                    summary: "\(code) repositions forces toward \(targetRegion.name), making the move visible to diplomatic observers.",
                    tensionDelta: 2,
                    title: "\(code) moves forces near \(targetRegion.name)"
                ))
            }
        }

        nextState.mapArmies = armiesByCountry.values.flatMap(\.self).sorted { $0.id < $1.id }
        nextState.mapBuildings = buildings.sorted { $0.id < $1.id }

        if !generatedEvents.isEmpty {
            nextState.lastSummary = "\(nextState.lastSummary) Background simulation added \(generatedEvents.count) visible strategic movement\(generatedEvents.count == 1 ? "" : "s")."
        }

        logger.debug("Background simulation generated \(generatedEvents.count) map actions.")
        return nextState
    }

    /// Inicia um loop contínuo (real-time mode) caso o jogo use turnos dinâmicos.
    func startContinuousSimulation() {
        Task(priority: .background) {
            // The product currently advances simulation on turns. A continuous
            // tick can call `simulateTurn(currentState:)` once real-time mode is enabled.
        }
    }
}

private enum BackgroundPolicyAction {
    case fortify
    case invest
    case moveToBorder
}

private extension BackgroundSimulationService {
    func policyFeatures(for code: String, aiState: NativeAICountryState, state: NativeCampaignState) -> [Double] {
        let ledger = state.economicLedgers[code]
        let relation = Double(aiState.relationshipScores[state.country.code] ?? 0) / 100.0
        return [
            ledger?.nominalGDPTrillions ?? 0.1,
            ledger?.realGrowthPercent ?? 0.0,
            ledger?.securityIndex ?? 50.0,
            Double(state.worldTension) / 100.0,
            relation,
            Double(state.round % 12) / 12.0
        ]
    }

    func policyAction(
        for code: String,
        features: [Double],
        aiState: NativeAICountryState,
        state: NativeCampaignState
    ) -> BackgroundPolicyAction {
        let security = features[safe: 2] ?? 50.0
        let tension = features[safe: 3] ?? 0.0
        let relation = features[safe: 4] ?? 0.0
        let roll = deterministicPercent(key: "\(code)|\(state.gameDate)|\(state.round)")

        if aiState.budgetPriority == .military || relation < -0.35 || tension > 0.68 {
            return roll > 20 ? .moveToBorder : .fortify
        }
        if security < 45 || aiState.doctrine == .defensive {
            return .fortify
        }
        return .invest
    }

    func startingArmy(for code: String, regionID: String, state: NativeCampaignState) -> NativeArmySnapshot {
        let ledger = state.economicLedgers[code]
        let strength = Int(((ledger?.nominalGDPTrillions ?? 0.5) * 8.0).rounded()) + 20
        let type: NativeArmyKind = state.aiCountryStates[code]?.budgetPriority == .military ? .armor : .infantry
        return NativeArmySnapshot(
            countryCode: code,
            currentRegionID: regionID,
            id: "army-\(code)-\(regionID)",
            strength: min(100, max(12, strength)),
            type: type
        )
    }

    func preferredRegion(for code: String) -> MapRegion? {
        GeopoliticalMapData.regions(forCountryCode: code).first { $0.countryCode != "WATER" } ??
            GeopoliticalMapData.regionByID[code]
    }

    func borderRegion(for code: String, excluding playerCode: String) -> MapRegion? {
        let regions = GeopoliticalMapData.regions(forCountryCode: code).filter { $0.countryCode != "WATER" }
        guard let playerRegion = GeopoliticalMapData.regions(forCountryCode: playerCode).first else {
            return regions.first
        }
        return regions.max { left, right in
            distanceSquared(left.center, playerRegion.center) < distanceSquared(right.center, playerRegion.center)
        }
    }

    func distanceSquared(_ left: CGPoint, _ right: CGPoint) -> CGFloat {
        let dx = left.x - right.x
        let dy = left.y - right.y
        return dx * dx + dy * dy
    }

    func deterministicPercent(key: String) -> Int {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in key.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return Int(hash % 100)
    }

    func simulationEvent(
        code: String,
        date: String,
        idSuffix: String,
        summary: String,
        tensionDelta: Int,
        title: String
    ) -> NativeCampaignEvent {
        let eventID = "background-\(code)-\(date)-\(idSuffix)"
        return NativeCampaignEvent(
            date: date,
            description: summary,
            id: eventID,
            importance: abs(tensionDelta) >= 2 ? .major : .minor,
            kind: tensionDelta > 0 ? .crisis : .world,
            linkedActionIDs: [],
            notable: tensionDelta > 0,
            playerRelated: false,
            strategicEffects: [
                NativeStrategicEffect(
                    date: date,
                    eventId: eventID,
                    id: "\(eventID)-tension",
                    magnitude: tensionDelta,
                    summary: summary,
                    target: code,
                    track: tensionDelta > 0 ? .securityAnxiety : .worldTension
                )
            ],
            title: title
        )
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
