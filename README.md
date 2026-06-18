<h1 align="center">SwiftHistoria</h1>

<div align="center">
  <strong>A Swift-first, open-source historical strategy sandbox inspired by Pax Historia.</strong>
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
    <img src="https://img.shields.io/badge/status-early%20development-orange.svg?style=flat-square"
      alt="Early Development" />
  </a>
</div>

<div align="center">
  <sub>Derived from the MIT-licensed Pax Historia project by <a href="https://github.com/Tommi-K">Tommi-K</a> and contributors.</sub>
</div>

<br />
<br />

## Development Direction

SwiftHistoria is being developed as a Swift-native Apple app in [`Apple/`](Apple/). The legacy React/Vite web app and Express server have been removed; new product work should land in the Swift-native implementation unless a task explicitly says otherwise.

For architectural orientation, see [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md). For future AI coding agents, see [`docs/LLM_MAINTENANCE_GUIDE.md`](docs/LLM_MAINTENANCE_GUIDE.md).

---

## ✨ Features

- __interactive world map:__ watch territory, borders, and nations shift as history unfolds
- __ai-generated events:__ dynamic events shaped by your decisions and the state of the world
- __diplomacy:__ negotiate with AI-controlled nations through natural language chat
- __ai advisor:__ consult your advisor for strategic guidance, economic analysis, and situation summaries
- __scenarios:__ choose from a range of historical starting points and play as any nation
- __self-hostable:__ run your own instance with your own AI backend completely offline

---

## 🚀 Installation

### Prerequisites

- [Git](https://git-scm.com/)
- Xcode with the macOS and iOS Simulator SDKs

### Steps

```bash
git clone https://github.com/gibavargas/SwiftHistoria.git
cd SwiftHistoria
script/build_apple.sh
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
script/format.sh        # auto-fix style with SwiftFormat
```

Requires `swiftlint` and `swiftformat` — install once with Homebrew:

```bash
brew install swiftlint swiftformat
```

### Tooling split

| Concern               | Tool         | Config           | CI gate               |
| --------------------- | ------------ | ---------------- | --------------------- |
| Style / whitespace    | SwiftFormat  | [`.swiftformat`](.swiftformat)   | `swiftformat --lint` (strict) |
| Semantic issues       | SwiftLint    | [`.swiftlint.yml`](.swiftlint.yml) | `swiftlint lint --strict`     |
| Build + tests         | `xcodebuild` | —                | macOS / iOS-sim / test jobs    |

### CI

GitHub Actions runs four jobs on every push and pull request (see [`.github/workflows/ci.yml`](.github/workflows/ci.yml)):

1. **Lint** — SwiftFormat + SwiftLint, both strict.
2. **Build (macOS)** — `PaxHistoriaMac` scheme.
3. **Build (iOS Simulator)** — `PaxHistoriaiOS` scheme.
4. **Test** — `PaxHistoriaMacTests` on the macOS host, with code coverage uploaded as an artifact.

Runs cancel superseded runs on the same ref to save macOS minutes. The latest Xcode (26) is selected via `maxim-lobanov/setup-xcode`.
