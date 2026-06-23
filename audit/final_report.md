# Pax Historia Apple App Audit Report

Run completed: 2026-06-23T00:49:14Z

## Scope

Audited the active Apple-native app in `/Users/jvguidi/Ideia/pax-historia/Apple`.
Legacy web/server behavior was treated as reference-only unless visible in the active Apple surface. No service worker is implemented in the native app; offline behavior is local persistence plus visible provider failures when remote AI is unavailable.

Canonical spreadsheet source of truth: `/Users/jvguidi/Ideia/pax-historia/audit/feature_inventory.csv`

The canonical ledger is a standards-compliant CSV with all required columns.

## Totals

- Total features/user stories found: 40
- Total user stories tested or reviewed against code paths: 40
- Final status `Done`: 40
- Bugs/UX/logistical issues found: 6 confirmed issues in the full audit; 0 new issues in this refresh
- Issues fixed in this refresh: 0 app-code fixes; audit artifacts updated with current test evidence
- Remaining app issues blocking this audit: 0

## Confirmed Issues And Fixes

No new app-code bugs were confirmed in this refresh. The previously documented fixes remain verified:

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

Current refresh:

- `/Users/jvguidi/Ideia/pax-historia/audit/feature_inventory.csv`
- `/Users/jvguidi/Ideia/pax-historia/audit/final_report.md`

Earlier full-audit fix pass:

- `/Users/jvguidi/Ideia/pax-historia/Apple/PaxHistoriaApple/CountrySelectionView.swift`
- `/Users/jvguidi/Ideia/pax-historia/Apple/PaxHistoriaApple/NativeFoundationModelService.swift`
- `/Users/jvguidi/Ideia/pax-historia/Apple/PaxHistoriaApple/NativeSettingsComponents.swift`
- `/Users/jvguidi/Ideia/pax-historia/Apple/PaxHistoriaAppleTests/NativeBackendTests.swift`
- `/Users/jvguidi/Ideia/pax-historia/Apple/PaxHistoriaAppleUITests/PaxHistoriaiOSUITests.swift`

The worktree also contains a per-user Xcode UI state change that was not part of this audit and was not reverted.

## Validation Evidence

Passed:

- CSV ledger parse check: 40 rows, 40 final `Done`
- `script/lint.sh`
- Full macOS XCTest:
  `xcodebuild test -project Apple/PaxHistoriaApple.xcodeproj -scheme PaxHistoriaMac -configuration Debug -destination platform=macOS -derivedDataPath .build/xcode`
- `./script/build_and_run.sh --verify`
- iOS UI smoke test on booted `PaxHistoria-iPhone-SE` iOS 26.5 simulator:
  `xcodebuild test -project Apple/PaxHistoriaApple.xcodeproj -scheme PaxHistoriaiOS -configuration Debug -destination id=AEB9562A-23CA-4B40-84AB-7DB632B95AE7 -derivedDataPath .build/xcode-ios -only-testing:PaxHistoriaiOSUITests/PaxHistoriaiOSUITests/testCountrySelectionStartsNativeGameAndNavigatesCoreTabs`
- `git diff --check`

Notes:

- Two live-provider tests were skipped because live API environment variables were not configured.
- The dedicated iOS smoke run now covers the provider-first onboarding path, Brazil search, map, orders, advisor, diplomacy, diplomatic network, and events navigation.

## Remaining Known Issues

- No full manual VoiceOver pass was performed; accessibility was audited from labels/identifiers/reduced-motion code and compile/test evidence.
- Live OpenRouter/Z.AI/provider checks require real API environment configuration.

## Final Confidence

High for the audited Apple-native code paths covered by static inspection, lint, full macOS XCTest, macOS launch verification, and the dedicated iOS Simulator smoke test. Medium for live-provider and full manual VoiceOver coverage because those require external API keys and human assistive-tech validation.
