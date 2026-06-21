# LLM Maintenance Guide

This guide is written for future AI coding agents and maintainers. Its goal is to reduce accidental breakage by making the codebase's intent explicit.

## Fast Orientation

SwiftHistoria is a native Apple implementation.

```text
Apple/PaxHistoriaApple/
```

If a task says "Swift native", "Mac native", "iOS", "Apple", "Foundation Models", or "no web", stay in the active product path.

## Read These First

1. `docs/ARCHITECTURE.md`
2. `Apple/PaxHistoriaApple/NativeCampaignStore.swift`
3. `Apple/PaxHistoriaApple/NativeGameEngine.swift`
4. `Apple/PaxHistoriaApple/NativeFoundationModelService.swift`
5. `Apple/PaxHistoriaApple/NativeStrategyContextDatabase.swift`

These files define the state, generation, persistence, and native-boundary contracts.

## Mental Model

The app is a turn-based strategy sandbox.

The player creates planned actions. The AI proposes events and summaries. The deterministic engine validates and applies those drafts. The store persists the result and drives the SwiftUI interface.

The core loop is:

```text
SwiftUI controls
  -> NativeCampaignStore intent method
  -> NativeAIService for generated drafts when needed
  -> NativeGameEngine.validated
  -> NativeGameEngine.apply
  -> NativeCampaignStore.persistState
  -> SwiftUI updates through @Published state
```

Never skip the engine validation step for generated turns.

## Ownership Rules

`NativeCampaignStore`

Owns mutable campaign state, async loading flags, draft fields, error surfaces, progress, persistence, import/export, and stale async protection.

`NativeGameEngine`

Owns deterministic state creation, generated-turn validation, turn application, metric clamps, date advancement, action resolution, and event/effect normalization.

`NativeFoundationModelService`

Owns Apple Foundation Models prompts, structured JSON decoding, prompt clamping, generation retries, and text-generation tasks for advisor/diplomacy.

`NativeStrategyContextDatabase`

Owns local facts, consequence rules, action memory, economic ledger math, and prompt evidence packets.

`NativeCampaignModels`

Owns persisted schemas and tolerant decoding.

`NativeGameShell` and `NativeGameView`

Own SwiftUI presentation. They should delegate meaningful state changes to `NativeCampaignStore`.

## Safe Editing Pattern

When adding a feature:

1. Find the state owner and add fields to the smallest stable model.
2. Add backward-compatible decoding defaults for persisted state.
3. Add a store method for mutations instead of mutating state directly in views.
4. If AI output is involved, update prompts and validation together.
5. Add or update tests that assert the contract, not incidental UI text.
6. Run focused tests.

## Async Safety Pattern

Use this pattern when awaiting AI work from `NativeCampaignStore`:

```swift
invalidateInFlightWork()
let requestVersion = stateVersion
state = currentState
persistState()

do {
    let result = try await aiService.someGeneration(...)
    guard isCurrentStateVersion(requestVersion) else { return }
    guard var nextState = state else { return }
    // Apply result.
    invalidateInFlightWork()
    state = nextState
    persistState()
} catch {
    guard isCurrentStateVersion(requestVersion) else { return }
    // Preserve user state and surface the error.
}
```

The important detail is not the exact shape of the method. The important detail is that an older model response must not overwrite a newer user choice, import, reset, language change, or scenario change.

## Persistence Safety Pattern

When adding persisted fields to `NativeCampaignState`:

- Add the field to the struct and initializer.
- Add the field to `CodingKeys`.
- Decode with `decodeIfPresent` or a safe fallback.
- Normalize loaded values if they can be out of range.
- Avoid removing old keys without a migration path.

The app loads primary envelope, backup envelope, then legacy state. That order is intentional.

## AI Output Safety Pattern

Generated content should pass through three filters:

1. Prompt constraints in `NativeFoundationModelService`.
2. Structured decoding and sanitization in service/model helpers.
3. `NativeGameEngine.validated` before state application.

Do not trust generated IDs, dates, links, tracks, text quality, or metric ranges until validation has accepted them.

## Common Pitfalls

Do not:

- Put web code back into Apple targets.
- Mutate `NativeCampaignState` from SwiftUI views directly.
- Add a new stored field without tolerant decode behavior.
- Apply generated turns without `NativeGameEngine.validated`.
- Add fake replacement model content when generation fails.
- Remove backup persistence because primary saves "should" work.
- Assume the web reference runtime is the active product.
- Rename schema keys casually; save files depend on them.

## Useful Searches

```bash
rg "stateVersion|invalidateInFlightWork|isCurrentStateVersion" Apple/PaxHistoriaApple
rg "CampaignStateEnvelope|campaign-state-envelope" Apple/PaxHistoriaApple
rg "validated\\(|apply\\(" Apple/PaxHistoriaApple/NativeGameEngine.swift
rg "generateSlicedTurn|generateStructuredJSON|clampedFoundationPrompt" Apple/PaxHistoriaApple
rg "NativeStrategyContextDatabase" Apple/PaxHistoriaApple
```

## Verification Choices

Small docs-only change:

```bash
script/lint.sh
```

Native state, AI, or project-boundary change:

```bash
script/build_and_run.sh --verify
```

If Xcode or simulator tooling fails because of local machine state, report that separately from code failures.
