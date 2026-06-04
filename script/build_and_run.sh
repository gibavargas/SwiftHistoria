#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA="$ROOT_DIR/.build/xcode"
PROJECT="$ROOT_DIR/Apple/PaxHistoriaApple.xcodeproj"
APP_PATH="$DERIVED_DATA/Build/Products/Debug/SwiftHistoria.app"

cd "$ROOT_DIR"

if pgrep -x "SwiftHistoria" >/dev/null 2>&1; then
  pkill -x "SwiftHistoria" || true
fi

xcodebuild \
  -project "$PROJECT" \
  -scheme PaxHistoriaMac \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA" \
  build

if [[ "${1:-}" == "--verify" ]]; then
  /usr/bin/open -n "$APP_PATH"
  sleep 2
  pgrep -x "SwiftHistoria" >/dev/null
  echo "SwiftHistoria launched from $APP_PATH"
  exit 0
fi

/usr/bin/open -n "$APP_PATH"
