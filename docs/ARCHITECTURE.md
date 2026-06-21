# SwiftHistoria Codebase Architecture

This document is the first stop for humans and LLM agents trying to work safely in SwiftHistoria. It describes what each part of the repository owns, where state flows, and which invariants should be preserved when changing the code.

## Product Boundary

SwiftHistoria is developed as a Swift-native Apple app under `Apple/`. New product features should land in the Swift-native implementation.

That boundary matters because the Apple app must remain native SwiftUI. Do not reintroduce `WKWebView`, JavaScript bridges, bundled `dist` assets, or Node server dependencies into the Apple targets.

## Repository Map

`Apple/PaxHistoriaApple/`

The active native Apple product. It contains the SwiftUI UI, campaign state store, local world model, deterministic game engine, and Apple Foundation Models integration.

`Apple/PaxHistoriaAppleTests/`

Native backend and end-to-end tests for state restoration, generated turn validation, persistence recovery, and Swift-native product boundaries.

`script/`

Build and verification helpers. `script/build_and_run.sh --verify` is the broad native validation path when Xcode tooling is available.

## Native Apple Runtime

The Swift-native app is organized around four core layers:

1. UI shell

`NativeGameView.swift` owns file import/export presentation and opens the turn report sheet. `NativeGameShell.swift` owns the app's visible navigation, panels, controls, and screen layout. UI components should call intent-like methods on `NativeCampaignStore` instead of mutating campaign state directly.

2. State store

`NativeCampaignStore.swift` is the only long-lived owner of mutable campaign state. It publishes selected country/language/scenario, drafts, loading flags, error messages, progress, and the current `NativeCampaignState`. It also owns persistence, backup recovery, stale async request rejection, and import/export.

3. Game engine

`NativeGameEngine.swift` is the deterministic boundary between generated model output and campaign state mutation. It creates initial state, normalizes planned actions, validates generated turns, advances dates, resolves linked actions, clamps metrics, applies economic effects, and preserves full campaign history.

4. AI service and strategy context

`NativeFoundationModelService.swift` talks to Apple Foundation Models when the OS supports it. It intentionally slices turn generation into small lanes so prompts stay inside the local model's context window. `NativeStrategyContextDatabase.swift` supplies grounded fact packets, consequence rules, action memory, deterministic economic ledger updates, and prompt evidence.

## Native Data Flow

The normal turn flow is:

1. The player chooses a country, language, and scenario through SwiftUI.
2. `NativeCampaignStore.choose(_:)` creates a `NativeCampaignState` by calling `NativeGameEngine.initialState`.
3. The player adds planned actions or accepts suggested actions. The store records them and updates action memory through `NativeStrategyContextDatabase.remember`.
4. The player advances time through `NativeCampaignStore.advance(months:)`.
5. The store captures `stateVersion`, then asks `NativeAIService.generateTurn`.
6. `NativeFoundationModelService` creates independent, economic, domestic, action-consequence, and summary lanes.
7. `NativeGameEngine.validated` rejects placeholder text, invalid dates, duplicate IDs, missing independent events, unsafe hidden tracks, and links to unknown actions.
8. `NativeGameEngine.apply` resolves planned actions, updates economic ledgers, appends events, clamps metrics, preserves full history, and returns the next state.
9. The store persists the new state as both a versioned envelope and a legacy state backup.
10. Suggested actions refresh for the new turn.

The important ownership rule: generated content is never trusted until the game engine validates it, and no async response may mutate state after `stateVersion` changes.

## Conflict, Security, And Map Contract

SwiftHistoria models war, insurgency, public security, and nuclear fallout as high-level board-game state, not as operational guidance. The deterministic contract is:

- `NativeEconomicLedger.securityIndex` tracks public-security capacity from 0 to 100 for every strategic country ledger.
- `NativeEconomicLedger.rebelControlPercent` tracks insurgency pressure from 0 to 100 for every strategic country ledger.
- `NativeCampaignState.regionOccupations` remains the compact legacy index used to answer who controls a map region.
- `NativeCampaignState.nuclearFalloutRegions` remains the compact legacy index for devastated regions.
- `NativeCampaignState.regionConflicts` is the explanatory source of truth for map conflict semantics: contested border, conventional occupation, guerrilla control, nuclear fallout, and stabilization corridor.

When changing conflict mechanics, keep those indexes synchronized. The UI may draw from the compact indexes for speed, but prompts, details panels, save recovery, and future LLM agents should rely on `NativeRegionConflictState` to understand why the border or fill changed.

The optional `hexLeverCode` is the model's small numeric way to nudge this system. Six nibbles alter economic deltas. Eight nibbles add public-security delta and map nudge. The eighth nibble maps to abstract simulation outcomes only: no change, conventional border advance, guerrilla control, nuclear fallout, domestic stabilization, contested border, public-security recovery, conquest occupation, or de-escalation. `NativeStrategyContextDatabase.decodeHexLever` decodes the value, `NativeGameEngine.processTacticalNudges` applies it, and `NativeGameView` renders it through borders, occupation stripes, insurgency stripes, fallout rings, route strokes, and stabilization overlays.

## Persistence Contract

Native campaign persistence is intentionally redundant:

`campaign-state-envelope-v2.json`

The primary versioned file save. It stores `schemaVersion`, `savedAt`, and the `NativeCampaignState`.

`campaign-state-backup-v2.json`

The last-good versioned save. It is written before replacing the primary save so corrupted primary data can be recovered.

`campaign-state-legacy-v1.json`

A direct state encoding kept for older save compatibility.

`UserDefaults`

Stores selected country/language/scenario and mirrors the campaign save blobs for additional recovery.

When changing `NativeCampaignState`, keep decoding tolerant. New fields should have reasonable defaults in `init(from:)`, and `NativeCampaignStore.normalizedLoadedState` should repair old or partially corrupt values.

SwiftHistoria intentionally does not cap persistent campaign complexity. Timeline events, world effects, action memory, ledger entries, advisor messages, and diplomatic threads should remain complete in saved state. Prompt builders and views may still take recent slices for readability and local model context windows, but those slices must not delete stored history.

## AI Generation Contract

Apple Foundation Models output is treated as an untrusted draft. The service is responsible for making prompts small and schema-oriented; the engine is responsible for validation and application.

Preserve these guardrails:

- Keep prompts anchored to `NativeStrategyContextDatabase.promptPacket`.
- Keep every AI prompt family connected to the shared mechanics checklist in `NativeFoundationModelService.mechanicsContract`: turn events, suggestions, advisor answers, diplomacy replies, and summaries should all see economy, public security, insurgency, map conflict, diplomacy, action memory, timeline effects, scenario canon, language, and bounded hex-map nudges.
- Keep player-facing prose in `state.language`, while identifiers, enum values, dates, and schema keys remain stable.
- Keep generated events concrete: titles, descriptions, effects, dates, IDs, and linked action IDs must be usable.
- Keep at least one generated event independent of the player country so the world does not feel player-only.
- Keep metric deltas clamped before storing state.
- Do not silently insert fake model output after an AI failure. Surface the error and preserve player-entered context.

## Tests And Verification

Useful commands:

```bash
script/build_and_run.sh --verify
```

Runs the native Apple verification path when Xcode tooling is available.

When a change touches native state, AI generation, persistence, or Apple target wiring, prefer the native verification script if the host can run it.

## High-Risk Change Checklist

Before editing `NativeCampaignStore.swift`:

- Identify whether the change mutates campaign state.
- Preserve `invalidateInFlightWork()` before any mutation that makes pending async responses stale.
- Capture `requestVersion` before awaiting AI work.
- Check `isCurrentStateVersion(_:)` after every await before writing state.
- Persist after successful state mutation.

Before editing `NativeFoundationModelService.swift`:

- Keep prompts within `clampedFoundationPrompt`.
- Keep schema examples and decoder fallbacks synchronized.
- Keep generated text sanitized.
- Keep failures explicit; do not hide them behind invented content.

Before editing `NativeGameEngine.swift`:

- Keep `validated` stricter than `apply`.
- Normalize incomplete event fields before applying, but reject fields that would make the game state incoherent.
- Update tests when adding new tracks, event kinds, or state fields.

Before editing `NativeCampaignModels.swift`:

- Add backward-compatible defaults for new stored fields.
- Keep Codable field names stable unless a migration is added.
- Keep language normalization tolerant of user-facing labels.

## LLM Orientation Notes

If you are an LLM agent:

- Start with `README.md`, this file, and `docs/LLM_MAINTENANCE_GUIDE.md`.
- Prefer Swift-native files under `Apple/PaxHistoriaApple/` for active product changes.
- Do not delete or rewrite user edits just because the worktree is dirty.
- Search before editing: `rg "NativeCampaignStore|NativeGameEngine|NativeFoundationModelService|NativeStrategyContextDatabase"`.
- Make comments explain contracts and invariants, not obvious syntax.
- Keep secret-like values out of logs, docs, commits, and final responses.
