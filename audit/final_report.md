# Pax Historia Apple App Audit Report

Run completed: 2026-06-22T00:02:05Z

## Scope

Audited the active Apple-native app in `/Users/jvguidi/Ideia/pax-historia/Apple`.
Legacy web/server behavior was treated as reference-only unless visible in the active Apple surface. No service worker is implemented in the native app; offline behavior is local persistence plus visible provider failures when remote AI is unavailable.

Canonical spreadsheet source of truth: `/Users/jvguidi/Ideia/pax-historia/audit/feature_inventory.csv`

The requested `.xlsx` export could not be produced because the artifact spreadsheet runtime (`@oai/artifact-tool`) was unavailable in this environment. The canonical ledger is therefore a standards-compliant CSV with all required columns.

## Totals

- Total features/user stories found: 40
- Total user stories tested or reviewed against code paths: 40
- Final status `Done`: 40
- Bugs/UX/logistical issues found: 6 confirmed issues
- Issues fixed in this run: 6
- Remaining app issues blocking this audit: 0

## Confirmed Issues And Fixes

1. macOS setup skipped the AI provider configuration step.
   - Fix: added provider setup to the macOS setup panel and blocked country start until selected provider configuration is usable.

2. Country start controls could be reached with incomplete external-provider configuration.
   - Fix: added a provider warning row and disabled country rows until the provider can run.

3. OpenRouter settings copy implied fallback behavior instead of selected-provider correctness.
   - Fix: updated OpenRouter copy to state that the Free Models Router requires an OpenRouter API key.

4. Save-slot persistence existed without visible player controls in settings.
   - Fix: added `NativeSaveSlotPicker` with slot summaries and stable accessibility identifiers.

5. OpenRouter provider-routing test fixture emitted an invalid linked action when no planned action existed.
   - Fix: changed the fixture to emit `null` for `linkedActionID` when there is no planned action.

6. iOS UI smoke test followed the old country-first onboarding path.
   - Fix: updated the UI test to select the provider and continue before searching for a country.

## Files Changed By This Audit

- `/Users/jvguidi/Ideia/pax-historia/Apple/PaxHistoriaApple/CountrySelectionView.swift`
- `/Users/jvguidi/Ideia/pax-historia/Apple/PaxHistoriaApple/NativeFoundationModelService.swift`
- `/Users/jvguidi/Ideia/pax-historia/Apple/PaxHistoriaApple/NativeSettingsComponents.swift`
- `/Users/jvguidi/Ideia/pax-historia/Apple/PaxHistoriaAppleTests/NativeBackendTests.swift`
- `/Users/jvguidi/Ideia/pax-historia/Apple/PaxHistoriaAppleUITests/PaxHistoriaiOSUITests.swift`
- `/Users/jvguidi/Ideia/pax-historia/audit/feature_inventory.csv`
- `/Users/jvguidi/Ideia/pax-historia/audit/final_report.md`

The worktree also contained unrelated pre-existing modifications before this audit; those were not reverted.

## Validation Evidence

Passed:

- `script/lint.sh`
- Focused macOS XCTest for OpenRouter routing:
  `xcodebuild test -project Apple/PaxHistoriaApple.xcodeproj -scheme PaxHistoriaMac -configuration Debug -destination platform=macOS -derivedDataPath .build/xcode -only-testing:PaxHistoriaMacTests/NativeBackendTests/testDynamicAIServiceRoutesEveryGameAISurfaceThroughOpenRouterFree`
- Full macOS XCTest:
  `xcodebuild test -project Apple/PaxHistoriaApple.xcodeproj -scheme PaxHistoriaMac -configuration Debug -destination platform=macOS -derivedDataPath .build/xcode`
- `./script/build_and_run.sh --verify`

Notes:

- Two live-provider tests were skipped because live API environment variables were not configured.
- The iOS UI test source was corrected, but a dedicated iOS Simulator UI run was not executed in this pass.
- SwiftFormat printed a cache-directory warning for `/Users/jvguidi/Library/Caches/com.charcoaldesign.swiftformat`; formatting and lint still completed successfully.

## Remaining Known Issues

- `.xlsx` export is blocked by missing local spreadsheet artifact tooling; the CSV ledger is the canonical spreadsheet for this run.
- No full manual VoiceOver pass was performed; accessibility was audited from labels/identifiers/reduced-motion code and compile/test evidence.
- Live OpenRouter/Z.AI/provider checks require real API environment configuration.

## Final Confidence

High for the audited Apple-native code paths covered by static inspection, lint, full macOS XCTest, and launch verification. Medium for iOS-specific runtime behavior until the corrected UI test is executed on an iOS Simulator.
