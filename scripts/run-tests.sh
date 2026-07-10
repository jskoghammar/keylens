#!/usr/bin/env bash
set -euo pipefail

DEVELOPER_DIR="$(xcode-select -p)"
FRAMEWORKS="$DEVELOPER_DIR/Library/Developer/Frameworks"
TESTING_LIB="$DEVELOPER_DIR/Library/Developer/usr/lib"
TMP_ROOT="${TMPDIR:-/tmp}"
ARGS=(--scratch-path "$TMP_ROOT/keylens-swiftpm-build")

if [[ -d "$FRAMEWORKS/Testing.framework" ]]; then
  ARGS+=(
    -Xswiftc -F -Xswiftc "$FRAMEWORKS"
    -Xlinker "-F$FRAMEWORKS"
    -Xlinker -rpath -Xlinker "$FRAMEWORKS"
    -Xlinker -rpath -Xlinker "$TESTING_LIB"
  )
fi

CLANG_MODULE_CACHE_PATH="$TMP_ROOT/keylens-clang-cache" \
SWIFTPM_MODULECACHE_OVERRIDE="$TMP_ROOT/keylens-swiftpm-module-cache" \
swift test "${ARGS[@]}" "$@"
