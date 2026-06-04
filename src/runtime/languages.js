export const GAME_LANGUAGE_OPTIONS = [
  { label: "English", value: "English" },
  { label: "Português", value: "Portuguese" },
  { label: "Español", value: "Spanish" },
];

const LANGUAGE_ALIASES = new Map([
  ["en", "English"],
  ["english", "English"],
  ["ingles", "English"],
  ["inglés", "English"],
  ["inglês", "English"],
  ["pt", "Portuguese"],
  ["pt-br", "Portuguese"],
  ["portugues", "Portuguese"],
  ["português", "Portuguese"],
  ["portuguese", "Portuguese"],
  ["portuguese brazilian", "Portuguese"],
  ["brazilian portuguese", "Portuguese"],
  ["portugues brasileiro", "Portuguese"],
  ["português brasileiro", "Portuguese"],
  ["portugues brasil", "Portuguese"],
  ["es", "Spanish"],
  ["espanhol", "Spanish"],
  ["espanol", "Spanish"],
  ["español", "Spanish"],
  ["spanish", "Spanish"],
  ["castellano", "Spanish"],
]);

const normalizeKey = (value) =>
  String(value ?? "")
    .trim()
    .toLowerCase()
    .normalize("NFD")
    .replace(/\p{Diacritic}/gu, "")
    .replace(/_/g, "-")
    .replace(/[()]/g, " ")
    .replace(/\s+/g, " ");

export const normalizeGameLanguage = (value) => {
  const rawValue = String(value ?? "").trim();
  if (!rawValue) return "English";

  const exact = GAME_LANGUAGE_OPTIONS.find((option) => option.value === rawValue || option.label === rawValue);
  if (exact) return exact.value;

  return LANGUAGE_ALIASES.get(normalizeKey(rawValue)) ?? "English";
};

export const gameLanguageInstruction = (value) => {
  const language = normalizeGameLanguage(value);
  return `Response language: ${language}. Write all player-facing prose in ${language}. Keep JSON keys, schema enum values, identifiers, and game tokens exactly as requested.`;
};

export const extractPromptLanguage = (value) => {
  const match = String(value ?? "").match(/(?:^|\n)\s*Language:\s*([^\n]+)/i);
  return match ? normalizeGameLanguage(match[1]) : "";
};
