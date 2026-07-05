import fs from "node:fs/promises";
import path from "node:path";
import { FileBlob, SpreadsheetFile } from "@oai/artifact-tool";

const repoRoot = "/Users/jvguidi/Ideia/pax-historia";
const inputPath = path.join(
  repoRoot,
  "outputs/019f1d8c-ec46-7fc3-b2f5-82a4115e82da/pax_historia_feature_inventory.xlsx",
);
const outputDir = path.join(
  repoRoot,
  "outputs/019f22b3-abad-7240-8925-99b7f6bbc08e",
);
const outputPath = path.join(outputDir, "pax_historia_feature_inventory.xlsx");
const qaDir = "/private/tmp/pax-audit-019f22b3-abad-7240-8925-99b7f6bbc08e";

await fs.mkdir(outputDir, { recursive: true });
await fs.mkdir(qaDir, { recursive: true });

const input = await FileBlob.load(inputPath);
const workbook = await SpreadsheetFile.importXlsx(input);

const before = await workbook.inspect({
  kind: "table",
  range: "Features!A1:N53",
  include: "values,formulas",
  tableMaxRows: 4,
  tableMaxCols: 14,
  maxChars: 7000,
});
console.log("BEFORE_FEATURES\n" + before.ndjson);

for (const [sheetName, range] of [
  ["Features", "A1:N53"],
  ["Summary", "A1:F8"],
]) {
  const preview = await workbook.render({ sheetName, range, scale: 1 });
  await fs.writeFile(
    path.join(qaDir, `before-${sheetName.toLowerCase()}.png`),
    new Uint8Array(await preview.arrayBuffer()),
  );
}

const features = workbook.worksheets.getItem("Features");
const summary = workbook.worksheets.getItem("Summary");

const regressionEvidence =
  "Passed in the current checkout on 2026-07-02: the Apple code was re-inventoried; lint passed across 53 Swift files; full macOS XCTest passed 136 tests with 2 credential-gated skips and 0 failures; the full iOS UI suite passed 29 of 29; the macOS build-and-launch path passed.";

features.getRange("E15").values = [[
  "During turn generation the overlay shows phase, progress, provider/model summary, console-style logs, and provider-exposed reasoning activity. OpenRouter reports WAITING, LIVE, ENCRYPTED, or NOT EXPOSED without inventing unavailable reasoning; previews are normalized and bounded, and reduce-motion settings avoid decorative animation.",
]];
features.getRange("F15").values = [[
  "Apple/PaxHistoriaApple/NativeGameShellShared.swift NativeTurnProgressPanel; Apple/PaxHistoriaApple/NativeCampaignStore.swift turnProgress; Apple/PaxHistoriaApple/NativeOpenRouterService.swift generateTurn; Apple/PaxHistoriaApple/NativeZAIService.swift reasoningDelta reasoningPreview; selectors native-turn-progress-panel native-turn-progress-bar native-turn-provider-summary native-turn-model-identifier native-turn-reasoning",
]];
features.getRange("G15").values = [[
  "Review provider/store/UI progress wiring; run OpenRouter routing/progress plus reasoning detail, alias, encrypted, whitespace and bounded-preview tests; run full macOS and iOS suites and launch verification.",
]];
features.getRange("H15").values = [[
  "The progress overlay exposes provider/model identity and bounded AI-activity state. Deterministic tests cover visible reasoning details, compatible aliases, encrypted payloads, unavailable reasoning, and whitespace-stable preview limits.",
]];
features.getRange("I2:I53").values = Array.from({ length: 52 }, () => ["Retest passed"]);
features.getRange("M2:M53").values = Array.from({ length: 52 }, () => [regressionEvidence]);
features.getRange("N2:N53").values = Array.from({ length: 52 }, () => ["Done"]);

summary.getRange("A2").values = [[
  "Current checkout audit · 2026-07-02 · Canonical feature and user-story ledger",
]];
summary.getRange("D4").values = [[
  "No new app-code, UX, accessibility, behavioral, or logistics defect was confirmed. F014 was reconciled to the new provider-exposed AI-activity states and their deterministic regression coverage.",
]];
summary.getRange("D5").values = [[
  "External limitations: credentialed live OpenRouter, Z.AI, and Turso calls were not sent; a complete human VoiceOver traversal remains manual. Deterministic routing, reasoning parsing, persistence, accessibility-tree, and reduced-motion paths passed.",
]];
summary.getRange("D6").values = [[
  "Primary evidence: script/lint.sh; full macOS XCTest (136 passed, 2 credential skips); full iOS UI suite (29 passed); build_and_run.sh --verify; exported-workbook formula, value, archive, and visual QA.",
]];

const checks = [];
for (const spec of [
  { kind: "table", range: "Features!A13:N16", include: "values,formulas", tableMaxRows: 6, tableMaxCols: 14, maxChars: 10000 },
  { kind: "table", range: "Summary!A1:F8", include: "values,formulas", tableMaxRows: 10, tableMaxCols: 6, maxChars: 10000 },
  { kind: "match", searchTerm: "#REF!|#DIV/0!|#VALUE!|#NAME\\?|#N/A", options: { useRegex: true, maxResults: 300 }, summary: "final formula error scan", maxChars: 6000 },
]) {
  const result = await workbook.inspect(spec);
  checks.push(result.ndjson);
}
console.log("UPDATED_CHECKS\n" + checks.join("\n"));

for (const [sheetName, range] of [
  ["Features", "A1:N53"],
  ["Summary", "A1:F8"],
]) {
  const preview = await workbook.render({ sheetName, range, scale: 1 });
  await fs.writeFile(
    path.join(qaDir, `final-${sheetName.toLowerCase()}.png`),
    new Uint8Array(await preview.arrayBuffer()),
  );
}

const output = await SpreadsheetFile.exportXlsx(workbook);
await output.save(outputPath);

const exported = await SpreadsheetFile.importXlsx(await FileBlob.load(outputPath));
const exportedChecks = [];
for (const spec of [
  { kind: "table", range: "Features!A14:N15", include: "values,formulas", tableMaxRows: 4, tableMaxCols: 14, maxChars: 10000 },
  { kind: "table", range: "Summary!A1:F8", include: "values,formulas", tableMaxRows: 10, tableMaxCols: 6, maxChars: 10000 },
  { kind: "match", searchTerm: "#REF!|#DIV/0!|#VALUE!|#NAME\\?|#N/A", options: { useRegex: true, maxResults: 300 }, summary: "exported formula error scan", maxChars: 6000 },
]) {
  const result = await exported.inspect(spec);
  exportedChecks.push(result.ndjson);
}
console.log("EXPORTED_CHECKS\n" + exportedChecks.join("\n"));
console.log(`OUTPUT=${outputPath}`);
