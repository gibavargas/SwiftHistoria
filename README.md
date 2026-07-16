<h1 align="center">SwiftHistoria</h1>

<div align="center">
  <strong>A Swift-native, open-source historical strategy sandbox for macOS and iOS.</strong>
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
</div>

<div align="center">
  <sub>Derived from the MIT-licensed Pax Historia project by <a href="https://github.com/Tommi-K">Tommi-K</a> and contributors.</sub>
</div>

<br />
<br />

## Development Direction

SwiftHistoria is a Swift-native Apple app in [`Apple/`](Apple/). The legacy React/Vite web app and Express server have been removed; all product work lands in the Swift-native implementation.

For architectural orientation, see [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md). For future AI coding agents, see [`docs/LLM_MAINTENANCE_GUIDE.md`](docs/LLM_MAINTENANCE_GUIDE.md).

---

## ✨ Features

- **Interactive world map:** watch territory, borders, and nations shift as history unfolds
- **AI-generated events:** dynamic events shaped by your decisions and the state of the world
- **Diplomacy:** negotiate with AI-controlled nations through natural language chat
- **AI advisor:** consult your advisor for strategic guidance, economic analysis, and situation summaries
- **Six scenarios:** choose from historical and future starting points — *Default*, *Fragmented Markets*, *Resilience Decade*, *Soviet Triumph*, *Pax Cybernetica*, *Solarpunk Dawn* — each with three canonical objectives
- **Objective-driven victory:** every scenario exposes three visible objectives evaluated after each turn; rival nations can also win by completing multi-turn strategic agendas
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

Campaign turns use one fixed cadence: **every turn advances the game clock by three months.**

---

## 🎯 Victory System

Each scenario exposes three **canonical objectives** shown in the UI and evaluated after every deterministic turn mutation. A campaign is won when all three objectives are satisfied before the scenario deadline.

Rivals can also win. A canonical, mapped AI actor must satisfy the active scenario objectives while completing three real multi-turn strategic agendas — opening ledger strength alone is not enough. Earned rival progress and the eventual winning country are persisted with tolerant defaults for older saves.

Terminal states: `ongoing`, `won`, `lost-rival`, `lost-timeout`.

---

## 📊 Event Presentation

The simulation and save archive retain **every event** — history is intentionally uncapped. Presentation is quieter by design: turn reports promote at most **five** salient events, the intelligence timeline promotes at most **eight**, and remaining records stay available in compact expandable archives. `NativeEventBriefing` owns that deterministic presentation-only ranking.

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

| Concern            | Tool         | Config                        | CI gate                        |
| ------------------ | ------------ | ----------------------------- | ------------------------------ |
| Style / whitespace | SwiftFormat  | [`.swiftformat`](.swiftformat)   | `swiftformat --lint` (strict)  |
| Semantic issues    | SwiftLint    | [`.swiftlint.yml`](.swiftlint.yml) | `swiftlint lint --strict`      |
| Build + tests      | `xcodebuild` | —                             | macOS / iOS-sim / test jobs    |

### CI

GitHub Actions runs four jobs on every push and pull request (see [`.github/workflows/ci.yml`](.github/workflows/ci.yml)):

1. **Lint** — SwiftFormat + SwiftLint, both strict.
2. **Build (macOS)** — `PaxHistoriaMac` scheme.
3. **Build (iOS Simulator)** — `PaxHistoriaiOS` scheme.
4. **Test** — `PaxHistoriaMacTests` on the macOS host, with code coverage uploaded as an artifact.

Runs cancel superseded runs on the same ref to save macOS minutes. The latest Xcode (26) is selected via `maxim-lobanov/setup-xcode`.
