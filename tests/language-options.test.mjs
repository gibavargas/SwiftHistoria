import assert from "node:assert/strict";
import test from "node:test";
import { buildApplePromptEnvelope } from "../src/Game/AI/harness.js";
import { normalizePromptPack } from "../src/Game/AI/gameplayPrompts.js";
import { normalizeGameData, normalizeWorldState } from "../src/runtime/gameState.js";
import {
  GAME_LANGUAGE_OPTIONS,
  extractPromptLanguage,
  gameLanguageInstruction,
  normalizeGameLanguage,
} from "../src/runtime/languages.js";

test("language selection is constrained to English, Portuguese, and Spanish", () => {
  assert.deepEqual(GAME_LANGUAGE_OPTIONS.map((option) => option.value), [
    "English",
    "Portuguese",
    "Spanish",
  ]);
  assert.equal(normalizeGameLanguage("inglês"), "English");
  assert.equal(normalizeGameLanguage("pt_BR"), "Portuguese");
  assert.equal(normalizeGameLanguage("português"), "Portuguese");
  assert.equal(normalizeGameLanguage("español"), "Spanish");
  assert.equal(normalizeGameLanguage("castellano"), "Spanish");
  assert.equal(normalizeGameLanguage("Italian"), "English");
});

test("game and world state normalize language values before prompt assembly", () => {
  assert.equal(normalizeGameData({ language: "pt-BR" }).language, "Portuguese");
  assert.equal(normalizeWorldState({ language: "espanhol" }).language, "Spanish");
  assert.equal(normalizeGameData({ language: "" }).language, "English");
  assert.equal(normalizeWorldState({ language: "unknown" }).language, "English");
});

test("prompt templates and Apple harness carry explicit response language instructions", () => {
  const pack = normalizePromptPack({});
  const templates = [pack.advisor, pack.leader, ...Object.values(pack.tasks)];

  for (const template of templates) {
    assert.match(template, /Language: \$\{language\}/);
    assert.match(template, /Write all player-facing prose in \$\{language\}/);
    assert.match(template, /Keep JSON keys, schema enum values/);
  }

  assert.equal(extractPromptLanguage("Language: Português\nRequest"), "Portuguese");
  assert.match(gameLanguageInstruction("Spanish"), /Response language: Spanish/);

  const envelope = buildApplePromptEnvelope({
    responseFormat: "json",
    systemPrompt: "Language: Español\nSimulate the next turn.",
    taskKey: "jumpForward",
    userMessage: "Advance one month.",
  });

  assert.match(envelope, /Response language: Spanish/);
  assert.match(envelope, /Write all player-facing prose in Spanish/);
  assert.match(envelope, /Keep JSON keys, schema enum values/);
});
