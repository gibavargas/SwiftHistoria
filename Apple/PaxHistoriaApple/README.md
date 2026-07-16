# Native Apple App Notes

`Apple/PaxHistoriaApple/` is the active Swift-native implementation of SwiftHistoria. It should remain SwiftUI-first and independent of the legacy React/Vite runtime.

## Core Files

`ContentView.swift`

Creates the top-level native view and hands control to `NativeGameView`.

`NativeGameView.swift`

Owns file import/export presentation and the generated turn report sheet.

`NativeGameShell.swift`

Owns the main SwiftUI layout: map, orders, intel, advisor, diplomacy, economics, library, and settings surfaces.

`NativeCampaignStore.swift`

Owns mutable campaign state, user drafts, async loading flags, persistence, backup recovery, import/export, and stale async request guards.

`NativeCampaignModels.swift`

Defines persisted campaign models, language normalization, generated turn/event schemas, sanitizers, and model-output quality helpers.

`NativeGameEngine.swift`

Creates initial state, validates generated turns, applies accepted turns, resolves planned actions, clamps metrics, and preserves full history.

`NativeFoundationModelService.swift`

Calls Apple Foundation Models on supported systems. It slices turn generation into small structured prompts, decodes JSON drafts, retries repairable failures, and refuses to invent silent replacement content.

`DynamicAIService.swift`, `NativeNVIDIAService.swift`, and `NativeOpenRouterService.swift`

Own strict external-provider routing. The player selects NVIDIA NIM (hosting `minimaxai/minimax-m3`, `moonshotai/kimi-k2.6`, and `deepseek-ai/deepseek-v4-flash` in round-robin) or OpenRouter Free. Every AI surface stays on that selected route and exposes failures without switching providers.

`NativeStrategyContextDatabase.swift`

Provides local facts, consequence rules, action memory, economic ledger updates, and prompt packets used as evidence for generation.

`Native2010WorldModel.swift`

Defines the real 2010 opening baseline, country profiles, alignments, risk signals, map sectors, and dashboard metrics.

## State Flow

Most user interactions should follow this route:

```text
View button/input
  -> NativeCampaignStore method
  -> NativeGameEngine or NativeAIService
  -> validated state mutation
  -> persistState
  -> @Published update back to SwiftUI
```

Views should not patch `NativeCampaignState` directly. If a UI needs a new action, create a store method and centralize validation/persistence there.

## Generated Turn Flow

1. `NativeCampaignStore.advance()` captures the current `stateVersion` and applies the fixed three-month cadence.
2. `DynamicAIService` calls only the NVIDIA or OpenRouter Free route selected by the player.
3. `NativeGameEngine.validated` rejects incoherent drafts.
4. `NativeGameEngine.apply` mutates deterministic state.
5. The store persists and then refreshes suggestions.

The validation and application steps are separate by design. Validation explains why a generated turn cannot be used; application assumes a turn has already been accepted and focuses on deterministic state transitions.

## Victory And Event Presentation

`NativeGameEngine.campaignObjectives` is the canonical player-victory contract shown in the UI and evaluated after every deterministic turn mutation. Rival strength at campaign creation is not an automatic win: a canonical, mapped AI actor must satisfy the active scenario objectives while completing three real multi-turn strategic agendas. Earned rival progress and the eventual winning country are persisted with tolerant defaults for older saves.

The simulation and save archive retain every event. Presentation is intentionally quieter: turn reports promote at most five salient events, the intelligence timeline promotes at most eight, and the remaining records stay available in compact expandable archives. `NativeEventBriefing` owns that deterministic presentation-only ranking.

## Conflict And Map Mechanics

Public security and insurgency pressure live in each country's `NativeEconomicLedger`, so the system can model domestic stability for all strategic countries rather than a small hard-coded set. Region-level consequences live in `NativeCampaignState.regionConflicts`.

`regionConflicts` explains the map state with one of five modes:

- `contested-border`
- `conventional-occupation`
- `guerrilla-control`
- `nuclear-fallout`
- `stabilization`

The older `regionOccupations` and `nuclearFalloutRegions` fields still exist as compact drawing indexes and legacy save compatibility. Keep them synchronized with `regionConflicts` whenever the engine changes map control.

The optional 8-character `hexLeverCode` lets generated events nudge the simulation without free-form map mutation. Nibbles 1-6 are economic deltas, nibble 7 is public-security delta, and nibble 8 is an abstract map nudge. `NativeStrategyContextDatabase` decodes it, `NativeGameEngine` applies it, and `NativeGameView` draws the result as border emphasis, route strokes, occupation stripes, insurgency stripes, nuclear fallout markers, or stabilization overlays.

## Persistence Notes

The native app writes a versioned envelope, a last-good envelope backup, and a legacy state file. It also mirrors key data in `UserDefaults`.

If `TURSO_DATABASE_URL` and `TURSO_AUTH_TOKEN` are configured in Settings or the process environment, saves are also mirrored through Turso SQL-over-HTTP into `native_campaign_saves`. Turso writes run in the background so local file persistence remains the fast launch path; Turso is used for recovery only when no local file or `UserDefaults` copy is available.

When changing persisted models, keep old saves readable:

- Use `decodeIfPresent` for new fields.
- Supply scenario-aware defaults.
- Normalize out-of-range values after loading.
- Keep `campaign-state-envelope.v2` semantics unless adding an explicit migration.

Persistent campaign history is intentionally uncapped. Do not trim timelines, world effects, action memory, advisor messages, diplomatic threads, or ledger entries when saving or loading. Keep UI lists and AI prompt packets sliced separately so very large campaigns stay usable.

## AI Notes

The NVIDIA choice calls `https://integrate.api.nvidia.com/v1/chat/completions`, balancing requests between `minimaxai/minimax-m3`, `moonshotai/kimi-k2.6`, and `deepseek-ai/deepseek-v4-flash` via round-robin, with temperature `1.0` (for DeepSeek) or `0.6` (for others) and top-p `0.95`/`0.90`. The OpenRouter Free choice uses `openrouter/free`. The app adds no session token budget; provider-side technical and account limits still apply.

Apple Foundation Models have a small local context window compared with remote providers. The shared prompt harness keeps prompts compact, evidence-based, and schema-oriented. The strategy context database is the source of grounded facts and consequence ranges; avoid adding large free-form prompt context without trimming or summarizing it.

All prompt families use the same explicit mechanic-code protocol: `⟦ECO⟧` economic resilience, `⟦MKT⟧` market confidence, `⟦STB⟧` internal stability, `⟦SEC⟧` security anxiety, `⟦DIP⟧` diplomatic leverage, `⟦MIL⟧` military readiness, and `⟦TNS⟧` world tension. Suggestions output primary and secondary codes; consequence events output one code that must belong to the linked order. Narrative prose never executes mechanics. The parser still reads legacy raw track names for save compatibility. `hexLeverCode` remains the separate bounded protocol for economic, security, and map-control deltas.

Never treat generated content as authoritative until `NativeGameEngine.validated` accepts it.
