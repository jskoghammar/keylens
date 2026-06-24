#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP_ROOT="${TMPDIR:-/tmp}"
OUT="$TMP_ROOT/keylens-behavior-tests"
CACHE="$TMP_ROOT/keylens-swift-module-cache"

mkdir -p "$CACHE"

swiftc \
  -module-cache-path "$CACHE" \
  -parse-as-library \
  "$ROOT/keylens/HotkeyShortcut.swift" \
  "$ROOT/keylens/KeyboardSemantics.swift" \
  "$ROOT/keylens/ShortcutPressState.swift" \
  "$ROOT/keylens/HIDShortcutPressState.swift" \
  "$ROOT/keylens/OverlayAssetRenderer.swift" \
  "$ROOT/keylens/OverlayStateReconciler.swift" \
  "$ROOT/keylens/SVGRepositorySyncService.swift" \
  "$ROOT/keylens/AppConfiguration.swift" \
  "$ROOT/Tests/KeylensBehaviorTests/ValidationMain.swift" \
  -o "$OUT"

"$OUT"
