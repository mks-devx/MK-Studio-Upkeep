#!/bin/zsh
# SPDX-License-Identifier: MPL-2.0
set -euo pipefail
cd "${0:A:h:h}"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/swiftpm-module-cache"
mkdir -p "$CLANG_MODULE_CACHE_PATH" "$SWIFTPM_MODULECACHE_OVERRIDE"
python3 scripts/audit-public.py
python3 scripts/audit-licensing.py
python3 -m unittest discover -s scripts/tests -v
swift test --disable-sandbox
bash scripts/test-app-state.sh
APP_PATH="$(./scripts/build-app.sh release | tail -1)"
echo "$APP_PATH"
# Launch smoke test is opt-in: set STUDIO_UPKEEP_SMOKE=1 to run it after the build.
if [[ "${STUDIO_UPKEEP_SMOKE:-0}" == "1" ]]; then ./scripts/smoke-launch.sh "$APP_PATH"; fi
