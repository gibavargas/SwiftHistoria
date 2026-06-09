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

1. `NativeCampaignStore.advance(months:)` captures the current `stateVersion`.
2. `NativeFoundationModelService.generateTurn` builds structured generation lanes.
3. `NativeGameEngine.validated` rejects incoherent drafts.
4. `NativeGameEngine.apply` mutates deterministic state.
5. The store persists and then refreshes suggestions.

The validation and application steps are separate by design. Validation explains why a generated turn cannot be used; application assumes a turn has already been accepted and focuses on deterministic state transitions.

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

When changing persisted models, keep old saves readable:

- Use `decodeIfPresent` for new fields.
- Supply scenario-aware defaults.
- Normalize out-of-range values after loading.
- Keep `campaign-state-envelope.v2` semantics unless adding an explicit migration.

Persistent campaign history is intentionally uncapped. Do not trim timelines, world effects, action memory, advisor messages, diplomatic threads, or ledger entries when saving or loading. Keep UI lists and AI prompt packets sliced separately so very large campaigns stay usable.

## AI Notes

Apple Foundation Models have a small local context window compared with remote providers. The service keeps prompts compact, evidence-based, and schema-oriented. The strategy context database is the source of grounded facts and consequence ranges; avoid adding large free-form prompt context without trimming or summarizing it.

All prompt families should stay connected to the same mechanics contract: economy, public security, insurgency pressure, map conflict, diplomacy/global friction, action memory, scenario canon, language, and bounded `hexLeverCode` map nudges. Suggestions are part of the game loop, so each generated suggestion should name the primary mechanic it intends to move and one secondary mechanic that benefits or trades off.

Never treat generated content as authoritative until `NativeGameEngine.validated` accepts it.
