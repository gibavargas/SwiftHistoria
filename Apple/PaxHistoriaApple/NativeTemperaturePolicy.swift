import Foundation

/// Single source of truth for generation temperatures across every AI route.
///
/// Design contract: creative game content stays in the 0.6–0.85 band so both
/// selectable routes (NVIDIA NIM and OpenRouter Free) produce comparable
/// narrative variety and event texture for the same campaign state. Repair
/// passes are allowed to cool below the band (more deterministic re-emission),
/// but never below 0.2, and the ladder must stay identical across providers.
///
/// Previously the OpenRouter route ran its consequence/world passes at 0.1
/// while NVIDIA ran the same surfaces at 0.6–0.85 — visibly different output
/// for the same world. This policy removes that asymmetry.
enum NativeTemperaturePolicy {
    /// Consequence/world event passes (first attempt).
    static let consequencePass: Double = 0.8

    /// Consequence/world event passes (repair re-emission).
    static let consequenceRepair: Double = 0.6

    /// Decision-matrix first attempt.
    static let matrixFirst: Double = 0.7

    /// Decision-matrix repair attempts.
    static let matrixRepair: Double = 0.5

    /// Unified single-prompt turn generation (first attempt).
    static let unifiedTurn: Double = 0.8

    /// Unified turn generation repair pass.
    static let unifiedRepair: Double = 0.5

    /// Advisor prose.
    static let advisor: Double = 0.7

    /// Diplomacy prose.
    static let diplomacy: Double = 0.7

    /// Sliced event lanes ladder (attempt 1, 2, 3) shared by ZAI-based routes.
    static let eventLaneLadder: [Double] = [0.85, 0.65, 0.4]

    /// Turn-summary generation.
    static let turnSummary: Double = 0.7
}
