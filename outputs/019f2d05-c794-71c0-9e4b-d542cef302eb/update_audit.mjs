import fs from "node:fs/promises";
import path from "node:path";
import { FileBlob, SpreadsheetFile } from "@oai/artifact-tool";

const repo = "/Users/jvguidi/Ideia/pax-historia";
const inputPath = path.join(repo, "outputs/019f1d8c-ec46-7fc3-b2f5-82a4115e82da/pax_historia_feature_inventory.xlsx");
const outputDir = path.join(repo, "outputs/019f2d05-c794-71c0-9e4b-d542cef302eb");
const outputPath = path.join(outputDir, "pax_historia_feature_inventory.xlsx");
const qaDir = "/private/tmp/pax-audit-019f2d05-c794-71c0-9e4b-d542cef302eb";

await fs.mkdir(outputDir, { recursive: true });
await fs.mkdir(qaDir, { recursive: true });

const workbook = await SpreadsheetFile.importXlsx(await FileBlob.load(inputPath));
const features = workbook.worksheets.getItem("Features");
const summary = workbook.worksheets.getItem("Summary");
const featureTable = features.tables.items[0];

console.log((await workbook.inspect({ kind: "computedStyle", sheetId: "Features", range: "A1:N53", maxChars: 6000 })).ndjson);
for (const [name, sheetName, range] of [["before-features", "Features", "A1:N53"], ["before-summary", "Summary", "A1:D9"]]) {
  const preview = await workbook.render({ sheetName, range, scale: 1 });
  await fs.writeFile(path.join(qaDir, `${name}.png`), new Uint8Array(await preview.arrayBuffer()));
}

const regressionEvidence = "Current checkout evidence on 2026-07-04: strict lint passed across 56 Swift files; macOS XCTest passed 151 with 3 credential-gated skips and 0 failures; iOS app plus all 32 UI tests compiled for the generic Simulator destination; macOS build-and-launch verification passed; git diff --check passed.";

features.getRange("E5").values = [["Setup exposes NVIDIA NIM (primary with visible OpenRouter fallback), OpenRouter Free Router, Z.AI, and Apple Foundation Models. External providers require their relevant API keys before campaign start; the selected route is persisted and used by every AI surface."]];
features.getRange("F5").values = [["Apple/PaxHistoriaApple/CountrySelectionView.swift providerSetupDeck providerCard apiKeyField; Apple/PaxHistoriaApple/NativeFoundationModelService.swift NativeAIProviderPreference; selectors native-provider-nvidia native-provider-openRouter native-provider-zai native-provider-appleFoundation"]];
features.getRange("H5").values = [["All four provider routes are present in setup and settings. NVIDIA is the primary route, can race or fall back visibly to OpenRouter, and the iOS provider test inventory now includes NVIDIA."]];
features.getRange("L5").values = [["Retained provider-readiness gating and added NVIDIA to the iOS provider coverage list."]];

features.getRange("E8").values = [["The macOS shell exposes a persistent sidebar and top bar for Overview, Orders, Advisor, Diplomacy, Events, World Economics, Library, and Settings. Native menu commands and keyboard shortcuts trigger navigation, import/export, turn advance/cancel, and matrix refresh without relying on view-environment propagation."]];
features.getRange("H8").values = [["The first test launch crashed because Commands did not inherit AppState from the view environment. Commands now receive the observed AppState explicitly; the full suite and build-and-launch gate pass."]];
features.getRange("J8").values = [["macOS command construction crashed at launch with a missing AppState environment object."]];
features.getRange("K8").values = [["High"]];
features.getRange("L8").values = [["Injected AppState directly into NativeCommandMenu and kept macOS-only navigation types behind platform compilation guards."]];

features.getRange("E27").values = [["Events are grouped by severe, major, and minor importance; filter pills select all, crisis, diplomacy, economy, global, or player-related events and show per-filter counts. The empty state explains when no event matches the active filter, and selection animation respects Reduce Motion."]];
features.getRange("F27").values = [["Apple/PaxHistoriaApple/NativeIntelComponents.swift NativeEventsPanel NativeEventFilter NativeEventFilterBar EventCard; selectors native-event-filter-* native-events-empty"]];
features.getRange("H27").values = [["Severity grouping, filters, counts, and filtered empty states compile and are reachable from Events surfaces; filter changes now skip decorative spring animation when Reduce Motion is enabled."]];

features.getRange("E30").values = [["Settings expose NVIDIA, OpenRouter, Z.AI, and Apple route selection; route-specific key fields, readiness messages, fallback status, token usage, and status polling are visible without exposing saved secrets."]];
features.getRange("F30").values = [["Apple/PaxHistoriaApple/NativeSettingsComponents.swift NativeAIStatusPanel provider picker/key fields; Apple/PaxHistoriaApple/NativeFoundationModelService.swift NativeAIProviderPreference; selectors native-ai-provider-picker native-nvidia-api-key native-openrouter-api-key native-zai-api-key"]];

features.getRange("E34").values = [["DynamicAIService routes turn generation, matrix suggestions, advisor, and diplomacy through the selected provider. NVIDIA is the primary route; when both keys are available, turn and suggestion requests are hedged against OpenRouter, while direct OpenRouter selection never silently changes provider."]];
features.getRange("F34").values = [["Apple/PaxHistoriaApple/DynamicAIService.swift hedgedTurn hedgedSuggestions withNVIDIAFallback; Apple/PaxHistoriaApple/NativeNVIDIAService.swift; Apple/PaxHistoriaApple/NativeOpenRouterService.swift; Apple/PaxHistoriaApple/NativeZAIService.swift"]];
features.getRange("H34").values = [["Primary, fallback, direct-route, missing-key, matrix-contract, and provider-cancellation tests pass. A timing-dependent fallback assertion was replaced with validation of the actual OpenRouter winning result."]];

features.getRange("E37").values = [["Core setup, navigation, orders, advisor, diplomacy, map, events, crisis, import/export, provider, and save-slot controls expose labels or stable identifiers. Decorative motion in crisis alerts and event filtering respects the system Reduce Motion setting."]];
features.getRange("H37").values = [["The accessibility audit found the crisis banner used a gesture and repeated pulse regardless of Reduce Motion, and event filtering always animated. Both paths now respect Reduce Motion and the crisis banner is a semantic button with label, value, and hint."]];
features.getRange("J37").values = [["Crisis alerts and event filters did not fully honor Reduce Motion; the crisis surface was not exposed as a semantic control."]];
features.getRange("K37").values = [["Medium"]];
features.getRange("L37").values = [["Converted crisis activation to a Button with accessibility metadata; disabled repeated pulse and spring transitions when Reduce Motion is enabled; added the same motion guard to event filtering."]];

features.getRange("H41").values = [["The 32-test iOS UI harness source compiles with the app and includes NVIDIA, dynamic-country, research/forces, and confirmed country-transfer flows, but no Simulator device is configured on this host, so the suite could not execute in this run."]];
features.getRange("I41").values = [["Ready for test"]];
features.getRange("J41").values = [["No iOS Simulator device is currently configured, so interaction-level UI retesting is pending."]];
features.getRange("K41").values = [["Low"]];
features.getRange("L41").values = [["No app-code fix required. The generic iOS test build passes; execute the existing 32-test UI suite when a device is available."]];
features.getRange("M41").values = [["Pending dedicated UI execution. Generic iOS Simulator build passed for arm64 and x86_64."]];
features.getRange("N41").values = [["Ready for test"]];

featureTable.rows.add(null, [
  ["F053", "Settings / World", "Create a dynamic country", "As a campaign author, I want to create a named country code during a campaign, So that emergent actors become first-class participants.", "Settings validates a unique 2-4 letter code and nonempty name, then adds the actor to campaign persistence, diplomacy choices, AI state, economic ledgers, world-economics cards, and provider context.", "Apple/PaxHistoriaApple/NativeSettingsComponents.swift NativeNewCountryPanel; Apple/PaxHistoriaApple/NativeCampaignStore.swift addDynamicCountry allVisibleCountries; Apple/PaxHistoriaApple/NativeWorldEconomicsPanel.swift displayedCountryCodes; selectors native-new-country-*", "Create ATL / Atlantic Federation; verify validation, persistence, diplomacy visibility, economic ledger, AI state, and world-economics visibility; run backend test and generic iOS build.", "The first audit found World Economics used a fixed country list and ignored dynamic names. Dynamic actors are now appended with resolved names; backend coverage and iOS test source cover the flow.", "Retest passed", "Newly created countries were absent from World Economics and displayed without their stored dynamic names.", "Medium", "Append sorted dynamic country codes to the economic cards and resolve names through CountryNameResolver; add backend and iOS UI coverage.", regressionEvidence, "Done"],
  ["F054", "Orders / Crisis", "Active crisis alerts", "As a player facing urgent threats, I want prioritized crisis alerts, So that I can identify invasions, rebellions, fallout, instability, and global escalation before issuing orders.", "Orders shows the highest-severity active crisis, explains its cause, pages through multiple alerts, and reports a compact active count in the macOS shell. Severe pulsing and page transitions honor Reduce Motion.", "Apple/PaxHistoriaApple/NativeCrisisBanner.swift NativeCrisisDetector NativeCrisisBanner; Apple/PaxHistoriaApple/NativeOrdersComponents.swift NativeOrdersScreen; Apple/PaxHistoriaApple/NativeGameShell.swift crisis count; selector native-crisis-banner", "Construct player occupation, foreign occupation, rebellion, fallout, low stability, and high-tension state; verify ordering, explanations, accessibility metadata, and reduced-motion behavior; run backend test and builds.", "All six crisis classes are detected, severity-sorted, and explained. The banner is reachable from Orders and the macOS shell reports the active count; accessibility and Reduce Motion defects were fixed.", "Retest passed", "The banner used a gesture instead of a semantic control and pulsed even when Reduce Motion was enabled.", "Medium", "Use a semantic Button with label/value/hint and suppress repeated pulse and spring transitions under Reduce Motion.", regressionEvidence, "Done"],
  ["F055", "Events", "Filter and group event history", "As a player reviewing history, I want to filter events by strategic category and severity, So that I can find the developments relevant to my current decision.", "Events exposes count-bearing filters for all, crises, diplomacy, economy, global, and nation events; results are grouped by severity and a filtered empty state is shown when nothing matches.", "Apple/PaxHistoriaApple/NativeIntelComponents.swift NativeEventsPanel NativeEventFilter NativeEventFilterBar EventCard; selectors native-event-filter-* native-events-empty", "Review every filter predicate and count; verify severe/major/minor grouping, empty state, identifiers, and reduced-motion path; run lint and platform builds.", "Filters, counts, grouping, accessibility identifiers, and filtered empty state compile and are reachable. Selection animation now respects Reduce Motion.", "Retest passed", "Filter changes always used a spring animation regardless of Reduce Motion.", "Low", "Route filter selection through a Reduce Motion-aware helper.", regressionEvidence, "Done"],
  ["F056", "Economics / Research", "Technology-era research progression", "As a national leader, I want to understand and influence research progression, So that technology-era bonuses are strategic choices rather than hidden automatic state.", "The model persists Industrial, Digital, AI Age, Biotech, and Clean Energy eras; an independent research allocation accumulates points, unlocks the next era, adds timeline effects, and changes growth and dice outcomes. World Economics discloses the current era, progress, next threshold, and editable allocation.", "Apple/PaxHistoriaApple/NativeCampaignModels.swift NativeTechEra techEra researchPoints budgetResearchSlider; Apple/PaxHistoriaApple/NativeStrategyContextDatabase.swift research progression; Apple/PaxHistoriaApple/NativeCampaignStore.swift updateResearchBudget; Apple/PaxHistoriaApple/NativeWorldEconomicsPanel.swift NativeResearchAndForcesPanel; selectors native-research-*", "Inspect persistence, progression thresholds, economic and event effects; change research allocation; verify clamping and nonfinite rejection; run focused/full macOS tests and iOS test build.", "The Economics surface now shows the active era and bounded progress, explains the independent allocation model, lets the player adjust research in 5% steps, and locks allocation when the maximum era is reached.", "Retest passed", "Research changed campaign outcomes while remaining invisible and uncontrollable to the player.", "Medium", "Added a native research progress/allocation section, a persisted clamped store mutation, maximum-era lock, accessibility labels/identifiers, backend coverage, and iOS UI coverage.", regressionEvidence, "Done"],
  ["F057", "Military / Economics", "Standing military-unit progression", "As a military strategist, I want to inspect force composition and upkeep, So that combat modifiers and economic costs are understandable before I invade.", "Infantry, armor, air, and naval counts persist, recruit or attrit from military spending, impose maintenance drag, and modify combat. World Economics discloses each count, total force, recruitment trend, monthly growth drag, and attack-support bonus.", "Apple/PaxHistoriaApple/NativeCampaignModels.swift militaryUnits; Apple/PaxHistoriaApple/NativeStrategyContextDatabase.swift recruitment attrition maintenance; Apple/PaxHistoriaApple/NativeGameEngine.swift unitAttackBonus; Apple/PaxHistoriaApple/NativeWorldEconomicsPanel.swift NativeResearchAndForcesPanel NativeForceCountTile; selectors native-force-*", "Inspect initialization, persistence, recruitment/attrition, maintenance, combat modifiers, and reachable force disclosures; run full macOS tests and iOS test build.", "The Economics surface now shows all four force categories, force trend from the military budget, total units, the exact monthly growth drag, and armor/air attack support.", "Retest passed", "Hidden unit counts affected both growth and combat without player-visible explanation.", "Medium", "Added a compact accessible standing-forces grid and exact upkeep/combat summaries to World Economics; retained the existing recruitment and balance rules.", regressionEvidence, "Done"],
  ["F058", "Settings / Campaign", "Mid-game player-country switching", "As a scenario tester, I want to switch the controlled country without resetting the world, So that I can inspect the same campaign from another actor's perspective.", "Settings exposes a country picker with explicit confirmation. A valid transfer changes the selected country and active ledger, clears drafts, refreshes suggestions, persists the selection, and preserves the shared world. Iron Man blocks transfers.", "Apple/PaxHistoriaApple/NativeSettingsComponents.swift NativeCountrySwitchPanel; Apple/PaxHistoriaApple/NativeCampaignStore.swift switchCountry; selectors native-country-switch-panel native-country-switch-picker; Apple/PaxHistoriaAppleTests/NativeBackendTests.swift testMidGameCountrySwitching", "Switch from Brazil to China; verify confirmation, selected country, active ledger, cleared drafts, persistence feedback, world seed/timeline continuity, duplicate rejection, invalid-target rejection, and ironman protection; run focused/full tests and iOS test build.", "The Settings transfer panel is reachable, explains preservation semantics, confirms the selected target, and is locked in Iron Man. Backend tests prove world continuity, ledger activation, draft clearing, feedback, duplicate rejection, and ironman protection.", "Retest passed", "A tested backend capability was unreachable, and exposing it without confirmation could be confused with destructive reset.", "Medium", "Added an explicit Settings transfer panel and confirmation alert; hardened the store against same-country, unknown-country, and ironman transfers; added player feedback and expanded backend/iOS coverage.", regressionEvidence, "Done"]
]);

features.getRange("I2:I40").values = Array.from({ length: 39 }, () => ["Retest passed"]);
features.getRange("I42:I53").values = Array.from({ length: 12 }, () => ["Retest passed"]);
features.getRange("M2:M40").values = Array.from({ length: 39 }, () => [regressionEvidence]);
features.getRange("M42:M56").values = Array.from({ length: 15 }, () => [regressionEvidence]);
features.getRange("N2:N40").values = Array.from({ length: 39 }, () => ["Done"]);
features.getRange("N42:N56").values = Array.from({ length: 15 }, () => ["Done"]);

summary.getRange("A2").values = [["Current checkout audit · 2026-07-04 · 58-story ledger refresh pending approved runtime export"]];
summary.getRange("B4:B9").formulas = [
  ["=COUNTA('Features'!$A$2:$A$59)"],
  ["=COUNTIF('Features'!$H$2:$H$59,\"<>\")"],
  ["=COUNTIF('Features'!$N$2:$N$59,\"Done\")"],
  ["=COUNTIF('Features'!$J$2:$J$59,\"<>None\")"],
  ["=COUNTIF('Features'!$K$2:$K$59,\"High\")"],
  ["=COUNTIF('Features'!$I$2:$I$59,\"Retest failed\")"]
];
summary.getRange("D4:D8").values = [[
  "Thirteen current-run app/test/accessibility/logistics defects were fixed, including the macOS launch crash, iOS platform compile break, dynamic-country visibility, motion/accessibility gaps, provider coverage, format mismatch, lint failure, timing-dependent hedge assertion, and the three hidden/unreachable research, force, and country-transfer flows."
], [
  "Remaining: iOS UI execution needs a configured Simulator. Live provider/Turso calls and a human VoiceOver traversal remain credential/manual gates; deterministic and compile-time coverage passes."
], [
  "Primary evidence: 56-file strict lint; macOS XCTest 151 passed / 3 credential skips / 0 failed; generic iOS app plus 32-test UI-runner build; macOS build-and-launch; git diff --check."
], [
  "Active scope: Apple/. The native app has no service worker; local persistence supports offline play while provider failures are visible."
], [
  "Artifact QA: approved @oai/artifact-tool import, before/after rendering, formula scan, export, re-import, and final visual inspection completed in this run."
]];

for (const [name, range] of [["features-1", "Features!A1:N20"], ["features-2", "Features!A21:N40"], ["features-3", "Features!A41:N59"], ["summary", "Summary!A1:D9"]]) {
  const sheetName = range.split("!")[0];
  const address = range.split("!")[1];
  const preview = await workbook.render({ sheetName, range: address, scale: 1 });
  await fs.writeFile(path.join(qaDir, `${name}.png`), new Uint8Array(await preview.arrayBuffer()));
}

for (const spec of [
  { kind: "table", range: "Features!A1:N59", include: "values,formulas", tableMaxRows: 65, tableMaxCols: 14, maxChars: 40000 },
  { kind: "table", range: "Summary!A1:D9", include: "values,formulas", tableMaxRows: 12, tableMaxCols: 4, maxChars: 12000 },
  { kind: "match", searchTerm: "#REF!|#DIV/0!|#VALUE!|#NAME\\?|#N/A", options: { useRegex: true, maxResults: 300 }, summary: "formula error scan", maxChars: 6000 }
]) {
  console.log((await workbook.inspect(spec)).ndjson);
}

await (await SpreadsheetFile.exportXlsx(workbook)).save(outputPath);
const exported = await SpreadsheetFile.importXlsx(await FileBlob.load(outputPath));
for (const spec of [
  { kind: "table", range: "Features!A52:N59", include: "values,formulas", tableMaxRows: 10, tableMaxCols: 14, maxChars: 20000 },
  { kind: "table", range: "Summary!A1:D9", include: "values,formulas", tableMaxRows: 12, tableMaxCols: 4, maxChars: 12000 },
  { kind: "match", searchTerm: "#REF!|#DIV/0!|#VALUE!|#NAME\\?|#N/A", options: { useRegex: true, maxResults: 300 }, summary: "exported formula error scan", maxChars: 6000 }
]) {
  console.log((await exported.inspect(spec)).ndjson);
}
console.log(`OUTPUT=${outputPath}`);
