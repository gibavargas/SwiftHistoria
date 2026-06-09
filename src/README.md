# Legacy Web Reference Notes

`src/` contains the older React/Vite implementation. It remains useful for reference behavior, map asset loading, save normalization, provider settings, and tests, but the active product direction is the Swift-native Apple app under `Apple/`.

## Important Folders

`runtime/`

Shared browser-side utilities for JSON assets, save-state normalization, startup preload, language normalization, native-host detection, and library catalog access.

`Game/AI/`

Legacy AI orchestration for remote providers, the old Apple host bridge, prompt templates, deterministic fallbacks, and health tracking.

`Game/GameUI/`

Legacy browser UI panels: settings, actions, chat, advisor, library, search, time controls, and country chooser.

`Game/Map/`

MapLibre/PMTiles world rendering for the browser reference app.

## Save-State Contract

`runtime/gameState.js` is the key file for understanding old JSON shapes. It normalizes actions, chats, events, world state, game data, and event impacts so older saves can keep loading even when generated AI content is partial or malformed.

If you touch web state, preserve tolerant input handling. Many functions accept strings, partial objects, legacy property names, and missing arrays on purpose.

## AI Reference Contract

The web AI code can talk to Gemini, OpenAI, Anthropic, OpenAI-compatible endpoints, and the old Apple bridge. It is reference material for provider settings and prompt shape, not the active native Foundation Models path.

The native app's authoritative Apple generation code lives in `Apple/PaxHistoriaApple/NativeFoundationModelService.swift`.

## Development Note

Do not use this directory as evidence that the Apple app may include web rendering. The native boundary is guarded by tests in `tests/native-apple-project.test.mjs`.
