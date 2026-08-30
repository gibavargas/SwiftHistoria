<h1 align="center">SwiftHistoria</h1>

<div align="center">
  <strong>A Swift-native, open-source geopolitical strategy sandbox for macOS and iOS.</strong>
</div>

<br />

<div align="center">
  <!-- Discord -->
  <a href="https://discord.gg/C3AVwHacZ4">
    <img src="https://img.shields.io/badge/discord-join-5865F2.svg?style=flat-square&logo=discord&logoColor=white"
      alt="Discord" />
  </a>
  <!-- License -->
  <a href="LICENSE">
    <img src="https://img.shields.io/badge/license-MIT-blue.svg?style=flat-square"
      alt="License: MIT" />
  </a>
  <!-- Status -->
  <a href="#">
    <img src="https://img.shields.io/badge/status-active%20development-blue.svg?style=flat-square"
      alt="Active Development" />
  </a>
  <!-- Platform -->
  <a href="#">
    <img src="https://img.shields.io/badge/platform-macOS%20%7C%20iOS-lightgrey.svg?style=flat-square"
      alt="Platform: macOS / iOS" />
  </a>
  <!-- Swift -->
  <a href="#">
    <img src="https://img.shields.io/badge/Swift-6-F05138.svg?style=flat-square&logo=swift&logoColor=white"
      alt="Swift 6" />
  </a>
</div>

<div align="center">
  <sub>Derived from the MIT-licensed Pax Historia project by <a href="https://github.com/Tommi-K">Tommi-K</a> and contributors.</sub>
</div>

<br />
<br />

## ✨ Features

- **Interactive world map:** watch territory, borders, and nations shift as history unfolds — conventional occupation stripes, guerrilla-control zones, nuclear fallout rings, stabilization corridors, and contested borders
- **AI-generated events:** dynamic events shaped by your decisions and the state of the world, presented as intelligence-briefing headlines
- **Diplomacy:** negotiate with AI-controlled nations through natural language chat
- **AI advisor:** consult your advisor for strategic guidance, economic analysis, and situation summaries
- **Six scenarios:** *Default*, *Fragmented Markets*, *Resilience Decade*, *Soviet Triumph*, *Pax Cybernetica*, *Solarpunk Dawn* — each with three canonical objectives
- **Objective-driven victory:** every scenario exposes three visible objectives evaluated after each turn; rival nations can also win by completing multi-turn strategic agendas
- **Game modes:** Sandbox (light consequences), Normal (standard campaign), Iron Man (doubled sovereign risks, no reloading)
- **Three save slots** with redundant local persistence and optional Turso cloud mirroring
- **Multilingual:** English, Português, and Español player-facing prose, with full localization strings
- **Self-hostable:** run your own instance with your own AI backend, completely offline

---

## 🤖 AI Routing

Players choose **exactly one** external route in campaign setup or Settings:

| Route | Models | Endpoint |
|-------|--------|----------|
| **NVIDIA NIM** | `minimaxai/minimax-m3`, `moonshotai/kimi-k2.6`, `deepseek-ai/deepseek-v4-flash` (round-robin) | `https://integrate.api.nvidia.com/v1/chat/completions` |
| **OpenRouter Free** | `openrouter/free` | OpenRouter |

Routing is **strict** across all AI surfaces — turns, the decision matrix, advisor answers, and diplomacy. A missing key or provider failure stays on the selected route and is shown to the player; there is no silent fallback or hedged-request race. Configure `NVIDIA_API_KEY` and `OPENROUTER_API_KEY` in the native app's Settings or campaign setup screen. **Never commit API keys.**

SwiftHistoria does not enforce a session token budget on either selectable route. Provider-side context, output, rate, and trial-service limits still apply.

Campaign turns use one fixed cadence: **every turn advances the game clock by three months**.

All AI prompt families use the same explicit mechanic-code protocol — `⟦ECO⟧` economic resilience, `⟦MKT⟧` market confidence, `⟦STB⟧` internal stability, `⟦SEC⟧` security anxiety, `⟦DIP⟧` diplomatic leverage, `⟦MIL⟧` military readiness, `⟦TNS⟧` world tension. Suggestions emit primary and secondary codes; consequence events emit one code that must belong to the linked order. The parser still reads legacy raw track names for save compatibility.

---

## 🎯 Victory System

Each scenario exposes three **canonical objectives** shown in the UI and evaluated after every deterministic turn mutation. A campaign is won when all three objectives are satisfied before the scenario deadline.

Rivals can also win. A canonical, mapped AI actor must satisfy the active scenario objectives while completing three real multi-turn strategic agendas — opening ledger strength alone is not enough. Earned rival progress and the eventual winning country are persisted with tolerant defaults for older saves.

Terminal states: `ongoing`, `won`, `lost-rival`, `lost-timeout`.

---

## 📊 Event Presentation

The simulation and save archive retain **every event** — history is intentionally uncapped. Presentation is quieter by design: turn reports promote at most **five** salient events, the intelligence timeline promotes at most **eight**, and remaining records stay available in compact expandable archives. `NativeEventBriefing` owns that deterministic presentation-only ranking.

---

## 🗺️ Map & Conflict Mechanics

SwiftHistoria models war, insurgency, public security, and nuclear fallout as high-level board-game state, not operational guidance.

`NativeCampaignState.regionConflicts` is the explanatory source of truth, with five modes:

- `contested-border` · `conventional-occupation` · `guerrilla-control` · `nuclear-fallout` · `stabilization`

The older `regionOccupations` and `nuclearFalloutRegions` fields remain as compact drawing indexes for fast rendering and legacy save compatibility.

The optional 8-character `hexLeverCode` lets generated events nudge the simulation without free-form map mutation: nibbles 1–6 are economic deltas, nibble 7 is public-security delta, nibble 8 is an abstract map-control nudge (border advance, guerrilla control, nuclear fallout, stabilization, etc.).

Every strategic country has a full `NativeEconomicLedger` with GDP, trade balance, fiscal space, public debt, inflation, unemployment, security index, rebel control, government type, public approval, election cycles, and dynamic resource reserves (oil, minerals, agriculture, rare earths).

---

## 💾 Persistence & Cloud Mirror

The native app writes a **redundant** local save: a versioned envelope, a last-good backup envelope, and a legacy state file, plus a `UserDefaults` mirror. Saves support **three slots**.

If `TURSO_DATABASE_URL` and `TURSO_AUTH_TOKEN` are configured in Settings or the process environment, saves are also mirrored to Turso (libSQL) via SQL-over-HTTP in the background. Local file persistence remains the fast launch path; Turso is used for recovery only when no local file or `UserDefaults` copy is available.

Campaign history is intentionally **uncapped** — timelines, world effects, action memory, advisor messages, diplomatic threads, and ledger entries are never trimmed on save.

---

## 🌍 Living World Mode (day-based, procedural)

At campaign setup you now choose a **simulation mode**:

| Mode | Engine | AI | Cadence |
|------|--------|----|---------|
| **Living World** | `NativeLivingWorldEngine` — deterministic day-tick world | An OOP **brain in every country** (`LWCountryBrain` subclasses: Balanced, Expansionist, Turtle, Opportunist) reacting to economy, threats, and relations | **Daily ticks** with Vic3-style speed control (⏩1–5, play/pause) |
| **Classic** | Quarterly 3-month turns | Your selected LLM route (strict NVIDIA NIM / OpenRouter Free) | **Quarterly** |

Living World is **fully procedural and offline**: no hardcoded events — a 1936
world is generated from the seed (10 core powers + 12 seeded minor nations),
with a Victoria 3-inspired simulation: goods market with bounded prices
(±75% of base) and **price-elastic pop demand**, buildings with input→output
chains, wages and treasuries, tax/spending sliders, interest groups,
radicals, standard of living, alliances, relations (−100…100), abstract
**fronts** (no unit control), war exhaustion and peace deals, infamy, and
common/rare procedural events.

**Localized generated prose:** every procedural string — events, war goals,
dispatch flavors, brain commentary, status lines — resolves through the
seeded `LWProse` pipeline in the save's language (English, Português, or
Español). Country names come from the world catalog; the save persists its
language, so history renders identically on any device. Commentary is
state-grounded: brains describe the actual war/fiscal/mobilization
situation with temperament-flavored outlooks, picked by a seeded daily die.

**Classic turn path is one request:** the whole turn — external, economic,
domestic, global-AI events plus one event per planned action and the
summary — arrives in a single JSON envelope per provider call (two only if
validation forces a repair retry).

**LLM hash bridge (optional, any provider):** Living World can export a JSON
world prompt to paste into any LLM (e.g. ChatGPT with its Python sandbox).
The model replies with `WORLDHASH:0x________` — 8 nibbles encoding economy,
tension, stability, and event probability — which the game interprets
deterministically and applies to the world.

Everything is **seed-deterministic**: same seed + same player decisions ⇒
identical world history (verified by `LivingWorldEngineTests`).

---

## ⌨️ Keyboard Shortcuts

| Action | Shortcut |
|--------|----------|
| Navigate panels (Advisor, Diplomacy, Map, Orders, Economy, Library, Settings…) | `⌘⌥1` – `⌘⌥8` |
| Next turn | `⌘]` |
| Cancel / stop generation | `⌘.` |
| Export campaign | `⇧⌘E` |
| Import campaign | `⇧⌘I` |

---

## 🚀 Installation

### Prerequisites

- [Git](https://git-scm.com/)
- Xcode 26 with the macOS and iOS Simulator SDKs

### Steps

```bash
git clone https://github.com/gibavargas/SwiftHistoria.git
cd SwiftHistoria
script/build_and_run.sh --verify
```

To build and launch the macOS app from the command line:

```bash
script/build_and_run.sh
```

---

## 🧪 Testing, Linting & CI

### One-command checks (mirrors CI)

```bash
script/lint.sh          # SwiftFormat (style) + SwiftLint (semantic), strict
script/lint.sh --fix    # auto-fix style with SwiftFormat, then re-check
```

Requires `swiftlint` and `swiftformat` — install once with Homebrew:

```bash
brew install swiftlint swiftformat
```

### Tooling split

| Concern            | Tool         | Config                           | CI gate                        |
| ------------------ | ------------ | -------------------------------- | ------------------------------ |
| Style / whitespace | SwiftFormat  | [`.swiftformat`](.swiftformat)   | `swiftformat --lint` (strict)  |
| Semantic issues    | SwiftLint    | [`.swiftlint.yml`](.swiftlint.yml) | `swiftlint lint --strict`    |
| Build + tests      | `xcodebuild` | —                                | macOS / iOS-sim / test jobs    |

### CI

GitHub Actions runs four jobs on every push and pull request (see [`.github/workflows/ci.yml`](.github/workflows/ci.yml)):

1. **Lint** — SwiftFormat + SwiftLint, both strict.
2. **Build (macOS)** — `PaxHistoriaMac` scheme.
3. **Build (iOS Simulator)** — `PaxHistoriaiOS` scheme.
4. **Test** — `PaxHistoriaMacTests` on the macOS host, with code coverage uploaded as an artifact.

Runs cancel superseded runs on the same ref to save macOS minutes. The latest Xcode (26) is selected via `maxim-lobanov/setup-xcode`.

---

## 📖 Documentation

- [**Architecture**](docs/ARCHITECTURE.md) — repository map, data flow, ownership rules, persistence contract, high-risk change checklist
- [**LLM Maintenance Guide**](docs/LLM_MAINTENANCE_GUIDE.md) — safe editing patterns, async safety, ownership rules for AI coding agents
- [**Native App Notes**](Apple/PaxHistoriaApple/README.md) — core file inventory, turn flow, conflict mechanics, AI notes
