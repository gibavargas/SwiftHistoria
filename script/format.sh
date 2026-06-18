#!/usr/bin/env bash
# Convenience wrapper around `swiftformat` for local use.
# Rewrites files in place to match the project's style (see .swiftformat).
#
#   script/format.sh          # format all sources under Apple/
#   script/format.sh --check  # exit non-zero if anything is unformatted (CI mode)
#
# Requires: swiftformat (brew install swiftformat)
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

command -v swiftformat >/dev/null 2>&1 || {
  echo "error: swiftformat not found. Install with: brew install swiftformat" >&2
  exit 127
}

if [[ "${1:-}" == "--check" || "${CI:-}" == "true" ]]; then
  swiftformat --swiftversion 6 --lint Apple/
else
  swiftformat --swiftversion 6 Apple/
fi
