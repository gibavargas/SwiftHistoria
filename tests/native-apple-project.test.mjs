import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const project = readFileSync("Apple/PaxHistoriaApple.xcodeproj/project.pbxproj", "utf8");
const contentView = readFileSync("Apple/PaxHistoriaApple/ContentView.swift", "utf8");
const nativeService = readFileSync("Apple/PaxHistoriaApple/NativeFoundationModelService.swift", "utf8");
const nativeEngine = readFileSync("Apple/PaxHistoriaApple/NativeGameEngine.swift", "utf8");
const nativeModels = readFileSync("Apple/PaxHistoriaApple/NativeCampaignModels.swift", "utf8");
const nativeStore = readFileSync("Apple/PaxHistoriaApple/NativeCampaignStore.swift", "utf8");
const nativeTests = readFileSync("Apple/PaxHistoriaAppleTests/NativeBackendTests.swift", "utf8");
const nativeView = readFileSync("Apple/PaxHistoriaApple/NativeGameView.swift", "utf8");
const nativeShell = readFileSync("Apple/PaxHistoriaApple/NativeGameShell.swift", "utf8");
const nativeCoordinates = readFileSync("Apple/PaxHistoriaApple/NativeCountryCoordinates.swift", "utf8");
const playerCountry = readFileSync("Apple/PaxHistoriaApple/PlayerCountry.swift", "utf8");
const buildAppleScript = readFileSync("script/build_apple.sh", "utf8");
const buildAndRunScript = readFileSync("script/build_and_run.sh", "utf8");
const nativeSources = [
  contentView,
  nativeService,
  nativeEngine,
  nativeModels,
  nativeStore,
  nativeView,
  nativeShell,
  nativeCoordinates,
].join("\n");

test("Apple targets are SwiftUI-native and no longer build the WebView shell", () => {
  assert.doesNotMatch(project, /WebGameView\.swift in Sources/);
  assert.doesNotMatch(project, /FoundationModelBridge\.swift in Sources/);
  assert.doesNotMatch(project, /dist in Resources/);
  assert.doesNotMatch(project, /\.(?:js|jsx|ts|tsx|html)\b|node_modules|server\/server|public\/|src\//);
  assert.doesNotMatch(contentView, /NativeWebGameView|WKWebView|WebKit/);
  assert.doesNotMatch(nativeSources, /WKWebView|WebKit|JavaScriptCore|evaluateJavaScript/);
  assert.doesNotMatch(buildAppleScript, /npm run build|vite build|dist/);
  assert.doesNotMatch(buildAndRunScript, /npm run build|vite build|dist/);
  assert.match(contentView, /NativeGameView/);
  assert.match(project, /NativeGameShell\.swift in Sources/);
  assert.match(project, /NativeCountryCoordinates\.swift in Sources/);
});

test("native Apple game calls Foundation Models directly without responder fallback", () => {
  assert.doesNotMatch(project, /AppleAIModels\.swift in Sources|AppleFoundationModelResponder\.swift in Sources/);
  assert.doesNotMatch(nativeService, /AppleFoundationModelResponder|fallbackResponse|fallbackText|fallbackUsed/);
  assert.doesNotMatch(nativeModels, /fallbackUsed/);
  assert.doesNotMatch(nativeEngine, /fallbackTurn|generatedTurn\(from rawText/);
  assert.match(nativeService, /generateTurn\(for state: NativeCampaignState, months: Int\) async throws/);
  assert.match(nativeService, /SystemLanguageModel\.default/);
});

test("native Apple game uses strict JSON generation inside the Apple context window", () => {
  assert.match(nativeService, /protocol NativeAIService/);
  assert.match(nativeService, /final class NativeFoundationModelService: NativeAIService/);
  assert.match(nativeService, /generateSlicedTurn/);
  assert.match(nativeService, /generateStructuredJSON/);
  assert.match(nativeService, /@Generable\(description: "A single concrete SwiftHistoria event draft/);
  assert.match(nativeService, /generating: T\.self/);
  assert.match(nativeService, /includeSchemaInPrompt: true/);
  assert.match(nativeService, /retrying text JSON fallback/);
  assert.match(nativeService, /appleDraftStrategicTrack/);
  assert.match(nativeService, /fallbackDraftDescription/);
  assert.match(nativeService, /fallbackDraftEffectSummary/);
  assert.match(nativeService, /decodeFoundationJSON/);
  assert.match(nativeService, /foundationJSONCandidates/);
  assert.match(nativeService, /AppleNativeGeneratedEventDraft: Decodable/);
  assert.match(nativeService, /AppleNativeTurnSummary: Decodable/);
  assert.match(nativeService, /AppleNativeSuggestedAction: Decodable/);
  assert.match(nativeService, /AppleNativeGeneratedEventDraft\.schemaInstructions/);
  assert.match(nativeService, /AppleNativeTurnSummary\.schemaInstructions/);
  assert.match(nativeService, /makeSuggestionPrompt/);
  assert.match(nativeService, /AppleNativeSuggestedAction\.schemaInstructions/);
  assert.match(nativeService, /Return one strict JSON object only/);
  assert.match(nativeService, /session\.respond\(/);
  assert.match(nativeService, /context=4096/);
  assert.match(nativeService, /maximumResponseTokens: 260/);
  assert.match(nativeService, /maximumResponseTokens: 180/);
  assert.doesNotMatch(nativeService, /AppleNativeSuggestedActionSet/);
  assert.doesNotMatch(nativeService, /weapons|cyber|coercion|surveillance|military-readiness|security-anxiety/);
  assert.match(nativeService, /sanitizeFoundationModelText/);
  assert.match(nativeService, /Do not return field names, schema labels, placeholders/);
  assert.match(nativeService, /globalFrictionDelta/);
  assert.match(nativeService, /suggestionPrompt/);
  assert.match(nativeService, /hasConcreteContent/);
  assert.match(nativeService, /clampedFoundationPrompt/);
  assert.match(nativeService, /summaryPrompt/);
  assert.match(nativeService, /suggestionFailures/);
  assert.match(nativeService, /Do not provide real-world operational instructions/);
  assert.match(nativeService, /generateAdvisorBrief/);
  assert.match(nativeService, /generateDiplomaticReply/);
  assert.match(nativeService, /makeAdvisorPrompt/);
  assert.match(nativeService, /makeDiplomacyPrompt/);
  assert.match(nativeService, /generateTextResponse/);
  assert.match(nativeModels, /collapseRepeatedSentences/);
  assert.match(nativeModels, /collapseRepeatedLines/);
  assert.match(nativeModels, /hasConcreteFoundationText/);
  assert.match(nativeModels, /normalizedFoundationUrgency/);
  assert.match(nativeModels, /suggestionFailure/);
  assert.match(nativeModels, /lorem ipsum/);
  assert.match(nativeModels, /Global Coordination Forum/);
});

test("native event engine enforces world events and strategic consequences", () => {
  assert.match(nativeEngine, /let candidateEvents = Array\(turn\.events\.prefix\(6\)\)/);
  assert.match(nativeEngine, /candidateEvents\.contains\(where: \{ !\$0\.playerRelated \}\)/);
  assert.match(nativeEngine, /isValidDate\(state\.gameDate\)/);
  assert.match(nativeEngine, /seenEventIDs/);
  assert.match(nativeEngine, /seenEffectIDs/);
  assert.match(nativeEngine, /plannedActionIDs/);
  assert.match(nativeEngine, /unknown or already resolved action/);
  assert.match(nativeEngine, /unsafe strategic track/);
  assert.match(nativeEngine, /throw NativeGameEngineError\.invalidTurn/);
  assert.match(nativeEngine, /strategicEffects/);
  assert.match(nativeEngine, /containsFoundationPlaceholderText/);
  assert.match(nativeEngine, /hasConcreteFoundationText\(summary/);
  assert.match(nativeEngine, /foundationVisibleTrack/);
  assert.match(nativeEngine, /guard linkedActionIDs\.contains\(action\.id\), action\.status == \.planned/);
  assert.doesNotMatch(nativeEngine, /\|\| action\.status == \.planned/);
  assert.match(nativeModels, /containsFoundationPlaceholderText/);
  assert.match(nativeEngine, /worldTension/);
  assert.match(nativeEngine, /internalStability/);
});

test("native Swift hardens edge cases without JavaScript fallback", () => {
  const staleGuards = [...nativeStore.matchAll(/guard isCurrentStateVersion\(requestVersion\) else \{ return \}/g)];

  assert.match(project, /PaxHistoriaMacTests/);
  assert.match(project, /NativeBackendTests\.swift in Sources/);
  assert.match(nativeStore, /private let aiService: any NativeAIService/);
  assert.match(nativeStore, /private var stateVersion = 0/);
  assert.match(nativeStore, /invalidateInFlightWork\(\)/);
  assert.ok(staleGuards.length >= 6);
  assert.match(nativeStore, /guard months > 0/);
  assert.match(nativeStore, /Choose a positive time jump/);
  assert.match(nativeStore, /CampaignStateEnvelope: Codable/);
  assert.match(nativeStore, /campaign-state-envelope\.v2/);
  assert.match(nativeStore, /campaign-state-backup\.v2/);
  assert.match(nativeStore, /campaign-state-envelope-v2\.json/);
  assert.match(nativeStore, /applicationSupportDirectory/);
  assert.match(nativeStore, /writePersistenceData/);
  assert.match(nativeStore, /options: \[\.atomic\]/);
  assert.match(nativeStore, /lastRecoveryNotice/);
  assert.match(nativeStore, /maxImportedCampaignBytes/);
  assert.match(nativeStore, /importTooLarge/);
  assert.match(nativeStore, /NativeGameEngine\.validated\(generated/);
  assert.match(nativeStore, /if state\.timeline\.isEmpty/);
  assert.match(nativeStore, /state\.lastSummary = initialState\.lastSummary/);
  assert.match(nativeStore, /guard maxLength > 0 else \{ return "" \}/);
  assert.match(nativeModels, /decodeIfPresent\(NativeAIReadiness\.self/);
  assert.match(nativeModels, /decodeIfPresent\(\[NativePlannedAction\]\.self/);
  assert.match(nativeModels, /decodeIfPresent\(\[NativeCampaignEvent\]\.self/);
  assert.match(nativeStore, /Logger\(subsystem: "com\.gibavargas\.SwiftHistoria", category: "NativeCampaignStore"\)/);
  assert.match(nativeService, /Logger\(subsystem: "com\.gibavargas\.SwiftHistoria", category: "NativeFoundationModelService"\)/);
  assert.match(nativeService, /readiness available/);
  assert.match(nativeService, /turn generation validated/);
  assert.match(nativeTests, /testLiveFoundationModelsGenerateValidNativeTurnWhenEnabled/);
  assert.match(nativeTests, /PAX_HISTORIA_RUN_LIVE_FOUNDATION_MODELS/);
  assert.match(nativeTests, /#if PAX_HISTORIA_RUN_LIVE_FOUNDATION_MODELS/);
  assert.match(nativeTests, /campaign-state-envelope-v2\.json/);
  assert.doesNotMatch(nativeStore, /WebView|WKWebView|JavaScript|node|npm|server\.js/);
});

test("native Apple game renders a map and Apple-generated action suggestions", () => {
  assert.match(nativeView, /import MapKit/);
  assert.match(nativeView, /NativeGameShell/);
  assert.match(nativeView, /Map\(position:/);
  assert.match(nativeView, /native-strategic-map/);
  assert.match(nativeView, /StrategicMapGrid/);
  assert.match(nativeShell, /enum NativeGameTab/);
  assert.match(nativeShell, /case map/);
  assert.match(nativeShell, /case orders/);
  assert.match(nativeShell, /case intel/);
  assert.match(nativeShell, /enum NativeIntelSection/);
  assert.match(nativeShell, /selectedIntelSection = \.advisor/);
  assert.match(nativeShell, /selectedIntelSection = \.diplomacy/);
  assert.match(nativeShell, /NativeIntelSectionSelector/);
  assert.match(nativeShell, /native-intel-section-selector/);
  assert.match(nativeShell, /enum NativeMacDestination/);
  assert.match(nativeShell, /NavigationSplitView/);
  assert.match(nativeShell, /NativeMapScreen/);
  assert.match(nativeShell, /NativeOrdersScreen/);
  assert.match(nativeShell, /NativeIntelScreen/);
  assert.match(nativeShell, /NativeMapCommandBar/);
  assert.match(nativeShell, /native-mobile-command-bar/);
  assert.match(nativeShell, /Apple-suggested actions/);
  assert.match(nativeShell, /refreshSuggestedActions/);
  assert.match(nativeView, /native-apple-suggestion-warning/);
  assert.match(nativeShell, /native-refresh-suggestions/);
  assert.match(nativeShell, /native-add-order/);
  assert.match(nativeView, /native-use-suggestion-/);
  assert.match(nativeView, /native-delete-order-/);
  assert.match(nativeShell, /native-advisor-panel/);
  assert.match(nativeShell, /native-advisor-question/);
  assert.match(nativeShell, /native-ask-advisor/);
  assert.match(nativeShell, /native-diplomacy-panel/);
  assert.match(nativeShell, /native-diplomacy-partner/);
  assert.match(nativeShell, /native-diplomacy-message/);
  assert.match(nativeShell, /native-send-diplomacy/);
  assert.match(nativeShell, /native-scenario-library/);
  assert.match(nativeShell, /native-campaign-library/);
  assert.match(nativeShell, /native-export-campaign/);
  assert.match(nativeShell, /native-import-campaign/);
  assert.match(nativeShell, /lastRecoveryNotice/);
  assert.match(nativeShell, /navigationSplitViewColumnWidth\(min: 220, ideal: 260, max: 320\)/);
  assert.match(nativeShell, /\.disabled\(store\.isAdvancing\)/);
  assert.match(nativeShell, /keyboardShortcut/);
  assert.match(nativeShell, /accessibilityReduceMotion/);
  assert.match(nativeShell, /colorSchemeContrast/);
  assert.match(nativeStore, /lastSuggestionError/);
  assert.match(nativeStore, /manual civic proposals remain available/);
  assert.match(nativeStore, /\.suggestionFailure\(error\)/);
  assert.match(nativeStore, /func deleteAction\(id: String\)/);
});

test("native Swift state now carries advisor and diplomacy parity surfaces", () => {
  assert.match(nativeModels, /NativeAdvisorMessage/);
  assert.match(nativeModels, /NativeDiplomaticThread/);
  assert.match(nativeModels, /advisorMessages = \(try\? container\.decodeIfPresent/);
  assert.match(nativeModels, /diplomaticThreads = \(try\? container\.decodeIfPresent/);
  assert.match(nativeStore, /func askAdvisor\(\) async/);
  assert.match(nativeStore, /func sendDiplomaticMessage\(\) async/);
  assert.match(nativeStore, /upsertDiplomaticThread/);
  assert.match(nativeEngine, /advisorMessages: state\.advisorMessages/);
  assert.match(nativeEngine, /diplomaticThreads: state\.diplomaticThreads/);
});

test("native Swift carries language selection through state, UI, and Foundation prompts", () => {
  const countrySelectionView = readFileSync("Apple/PaxHistoriaApple/CountrySelectionView.swift", "utf8");

  assert.match(nativeModels, /enum NativeGameLanguage/);
  assert.match(nativeModels, /case english = "English"/);
  assert.match(nativeModels, /case portuguese = "Portuguese"/);
  assert.match(nativeModels, /case spanish = "Spanish"/);
  assert.match(nativeModels, /NativeGameLanguage\.normalized/);
  assert.match(nativeModels, /Response language:/);
  assert.match(nativeModels, /Keep schema field names/);
  assert.match(nativeModels, /language = NativeGameLanguage\.normalized/);
  assert.match(nativeEngine, /language: NativeGameLanguage = \.english/);
  assert.match(nativeEngine, /openingSummary\(for: country, scenario: scenario, language: language\)/);
  assert.match(nativeEngine, /language: state\.language/);
  assert.match(nativeStore, /selectedLanguageKey/);
  assert.match(nativeStore, /func setLanguage\(_ language: NativeGameLanguage\)/);
  assert.match(nativeStore, /defaults\.set\(selectedLanguage\.rawValue, forKey: Self\.selectedLanguageKey\)/);
  assert.match(nativeShell, /native-language-picker/);
  assert.match(nativeShell, /store\.setLanguage/);
  assert.match(countrySelectionView, /native-language-picker/);
  assert.match(contentView, /selectedLanguage: campaignStore\.selectedLanguage/);
  assert.match(nativeService, /languageInstruction\(for state: NativeCampaignState\)/);
  assert.match(nativeService, /state\.language\.promptInstruction/);
  assert.match(nativeService, /Follow the request's response-language instruction/);
});

test("native Swift has scenario selection plus portable campaign import and export", () => {
  const countrySelectionView = readFileSync("Apple/PaxHistoriaApple/CountrySelectionView.swift", "utf8");

  assert.match(nativeModels, /struct NativeScenario/);
  assert.match(nativeModels, /enum NativeScenarioCatalog/);
  assert.match(nativeModels, /fragmented-markets/);
  assert.match(nativeModels, /resilience-decade/);
  assert.match(nativeModels, /scenarioID = \(try\? container\.decodeIfPresent/);
  assert.match(nativeEngine, /initialState\(\n        for country: PlayerCountry,\n        scenario: NativeScenario = NativeScenarioCatalog\.defaultScenario/);
  assert.match(nativeEngine, /scenarioDescription: scenario\.heroSubtitle/);
  assert.match(nativeEngine, /scenarioName: state\.scenarioName/);
  assert.match(nativeStore, /selectedScenarioKey/);
  assert.match(nativeStore, /func selectScenario\(id: String\)/);
  assert.match(nativeStore, /func exportCampaignData\(\) throws -> Data/);
  assert.match(nativeStore, /func importCampaignData\(_ data: Data\) throws/);
  assert.match(nativeStore, /JSONEncoder\(\)/);
  assert.match(nativeView, /fileExporter/);
  assert.match(nativeView, /fileImporter/);
  assert.match(nativeView, /NativeCampaignDocument: FileDocument/);
  assert.match(nativeShell, /NativeLibraryPanel/);
  assert.match(countrySelectionView, /native-scenario-library/);
  assert.match(countrySelectionView, /native-scenario-option-/);
  assert.match(countrySelectionView, /NavigationSplitView/);
  assert.match(countrySelectionView, /NavigationStack/);
  assert.match(countrySelectionView, /native-country-list/);
  assert.match(countrySelectionView, /native-country-empty/);
});

test("native strategic map has coordinate coverage for every selectable country", () => {
  const selectableCodes = [...playerCountry.matchAll(/alpha3: "([A-Z0-9]{3})"/g)].map((match) => match[1]);
  const mappedCodes = new Set([...nativeCoordinates.matchAll(/"([A-Z0-9]{3})": \(/g)].map((match) => match[1]));
  const missing = selectableCodes.filter((code) => !mappedCodes.has(code));

  assert.deepEqual(missing, []);
  assert.doesNotMatch(nativeCoordinates, /\?\? \(20\.0, 0\.0\)/);
  assert.match(nativeCoordinates, /distributedFallback/);
});
