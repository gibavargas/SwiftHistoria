#!/usr/bin/env bash
# Lint the Swift codebase WITHOUT modifying files. Mirrors what CI runs.
#
#   script/lint.sh          # check everything, fail on any violation
#   script/lint.sh --fix    # let SwiftFormat rewrite files, then re-check
#
# Requires: swiftlint, swiftformat (brew install swiftlint swiftformat)
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

MODE="${1:-check}"

need() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "error: '$1' not found. Install with: brew install $1" >&2
    exit 127
  }
}
need swiftlint
need swiftformat

if [[ "$MODE" == "--fix" ]]; then
  echo "==> SwiftFormat: rewriting files"
  swiftformat --swiftversion 6 Apple/
else
  echo "==> SwiftFormat: checking (no writes)"
  swiftformat --swiftversion 6 --lint Apple/
fi

echo "==> SwiftLint: checking (strict)"
swiftlint lint --strict --no-cache --config .swiftlint.yml Apple/

echo "==> All checks passed."
