#!/bin/bash
# SPDX-License-Identifier: BUSL-1.1
set -euo pipefail
cd "$(dirname "$0")/.."
scratch="${APP_STATE_SCRATCH:-/tmp/studio-upkeep-app-state-build}"
export CLANG_MODULE_CACHE_PATH="$scratch/ModuleCache"
swift build --disable-sandbox --scratch-path "$scratch" --target ProducerUpToDateCore
bin="$(swift build --disable-sandbox --scratch-path "$scratch" --show-bin-path)"
temp="$(mktemp -d)"
trap 'rm -rf "$temp"' EXIT
app_source_dir="${APP_STATE_SOURCE_DIR:-Sources/ProducerUpToDateApp}"
# Keep the production colour bridge while replacing only the executable entry point.
sed -n '/^enum BrandColor/,$p' "$app_source_dir/ProducerUpToDateApp.swift" > "$temp/BrandColor-body.swift"
{ echo 'import SwiftUI'; cat "$temp/BrandColor-body.swift"; } > "$temp/BrandColor.swift"
app_sources=()
for source in "$app_source_dir"/*.swift; do
    case "$source" in */ProducerUpToDateApp.swift|*/OfficialUpdatesView.swift) continue ;; esac
    app_sources+=("$source")
done
swiftc -swift-version 6 -target "$(uname -m)-apple-macosx13.0" -parse-as-library -I "$bin/Modules" \
    "${app_sources[@]}" "$temp/BrandColor.swift" scripts/tests/check-app-state.swift \
    "$bin"/ProducerUpToDateCore.build/*.o -o "$temp/check-app-state"
"$temp/check-app-state"
