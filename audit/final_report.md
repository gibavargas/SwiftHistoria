# Pax Historia Apple App Audit Report

Run updated: 2026-07-04T14:14:38Z

Current run status: Apple-native code audit, fixes, and automated regression gates are complete. The canonical workbook export remains blocked because the approved spreadsheet runtime loader did not return.

## Scope

This run audited the active Apple-native product under `Apple/` from the current checkout. Legacy web/server material remained reference-only. The native app has no service worker; local campaign persistence remains available offline, while remote-provider failures are surfaced to the player.

Last completed canonical workbook: `outputs/019f1d8c-ec46-7fc3-b2f5-82a4115e82da/pax_historia_feature_inventory.xlsx`

Prepared replacement: `outputs/019f2d05-c794-71c0-9e4b-d542cef302eb/update_audit.mjs`

Pending replacement workbook: `outputs/019f2d05-c794-71c0-9e4b-d542cef302eb/pax_historia_feature_inventory.xlsx`

## Totals

- Features and user stories reconciled from live code: 58
- Existing canonical workbook rows: 52
- New stories prepared for the replacement workbook: 6
- Stories with current code/test/build evidence: 58
- Stories ready to mark Done after workbook export: 57
- Current-run confirmed defect groups: 13
- Current-run fixes: 13
- Remaining product-surface gaps: 0
- Remaining infrastructure test/artifact blockers: 2

## Current-Run Findings And Fixes

1. macOS test launch crashed because `Commands` did not inherit `AppState` from the view environment. `NativeCommandMenu` now receives the observed state explicitly.
2. The shared app target referenced the macOS-only `NativeMacDestination` type during an iOS build. Platform guards now keep macOS navigation types out of the iOS compile while retaining shared active-game state.
3. Dynamic countries were omitted from World Economics and their stored names were ignored. The panel now appends sorted dynamic codes and resolves their campaign names.
4. Crisis alerts used nonsemantic gesture activation and repeated decorative pulse under Reduce Motion. The alert is now a labeled button and skips motion when requested.
5. Event-filter selection always animated. Filter changes now respect Reduce Motion.
6. OpenRouter fallback formatting passed an integer through a floating-point format specifier. The value now uses safe interpolation.
7. The iOS provider-coverage test omitted the new NVIDIA route. Its provider inventory now covers all four selectable routes.
8. Dynamic-country creation lacked end-to-end and cross-surface regression coverage. Backend and iOS UI test cases now cover the intended flow.
9. The concurrent hedged-provider edit introduced strict-format/lint failures. The source is formatted and passes the repository's strict lint gate.
10. The hedged fallback test assumed a progress callback would win a timing race. It now asserts the actual OpenRouter fallback result and is stable in the full suite.
11. Technology era, research points, and the independent research allocation affected outcomes without any player disclosure or control. World Economics now shows era progress and exposes a clamped 5% research slider with a maximum-era lock.
12. Standing infantry, armor, air, and naval counts affected growth and combat without any player-visible explanation. World Economics now shows force composition, recruitment/attrition trend, monthly upkeep drag, and attack support.
13. Mid-game country switching existed only as an unguarded store method. Settings now exposes an explicit confirmation flow, preserves the shared world, clears stale drafts, reports success, rejects invalid/same targets, and blocks transfers in Iron Man.

## Inventory Reconciliation

The prior 52 stories still map to the current product. Six additional code-supported stories were found:

- F053: dynamic country creation across settings, diplomacy, AI state, economics, and persistence.
- F054: prioritized crisis detection and alerts.
- F055: count-bearing event filters and severity grouping.
- F056: technology-era research progression with visible progress and allocation control.
- F057: standing military-unit progression with force/upkeep/combat disclosure.
- F058: confirmed mid-game player-country switching with ironman protection.

NVIDIA routing and macOS command/menu navigation materially update existing stories F004, F007, F029, and F033 rather than adding duplicate stories. Event-filter behavior updates F026 and also receives its own interaction story because filtering is a distinct player flow.

## Validation Evidence

- `./script/lint.sh`: 56 Swift files, 0 formatting violations, 0 SwiftLint violations.
- Full macOS XCTest: 151 passed, 3 credential-gated skips, 0 failed (154 total).
- Focused NVIDIA/OpenRouter fallback retest: passed.
- Generic iOS build-for-testing: the app and all 32 UI tests compiled, including NVIDIA, dynamic-country, research/forces, and country-transfer coverage.
- iOS UI execution is pending because `xcrun simctl list devices` returned no configured device.
- `./script/build_and_run.sh --verify`: built and launched the macOS app.
- `git diff --check`: passed.
- Workbook dependency loading: two bounded attempts hung and were terminated before `@oai/artifact-tool` paths were returned.

## Remaining Known Issues

- The dedicated 32-test iOS UI suite could not run because this host currently has no configured Simulator device. The app and test runner compile.
- The canonical workbook could not be refreshed, recalculated, exported, or visually verified because the approved spreadsheet runtime loader remained unavailable. The prepared update script preserves the required `@oai/artifact-tool` workflow and does not use an alternate spreadsheet library.

Live OpenRouter, NVIDIA, Z.AI, and Turso calls remain credential-gated and were not sent. A complete human VoiceOver traversal also remains a manual release check.

## Files Changed By This Audit

- `Apple/PaxHistoriaApple/PaxHistoriaApp.swift`
- `Apple/PaxHistoriaApple/DynamicAIService.swift`
- `Apple/PaxHistoriaApple/NativeCrisisBanner.swift`
- `Apple/PaxHistoriaApple/NativeIntelComponents.swift`
- `Apple/PaxHistoriaApple/NativeOpenRouterService.swift`
- `Apple/PaxHistoriaApple/NativeWorldEconomicsPanel.swift`
- `Apple/PaxHistoriaAppleTests/NativeBackendTests.swift`
- `Apple/PaxHistoriaAppleUITests/PaxHistoriaiOSUITests.swift`
- `audit/final_report.md`
- `outputs/019f2d05-c794-71c0-9e4b-d542cef302eb/update_audit.mjs`

The pre-existing dirty worktree and concurrent user changes were preserved.

## Final Confidence

High for the current macOS app, deterministic mechanics, persistence, provider routing/fallback, dynamic countries, crisis detection, research/force disclosure, country transfer, and shared Apple compilation. Medium-high for iOS interaction behavior until a Simulator is configured and the 32-test suite runs. Audit-artifact confidence remains incomplete until the pending workbook is exported and passes formula, archive, and visual QA.
