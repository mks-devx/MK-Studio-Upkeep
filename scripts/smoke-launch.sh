#!/bin/zsh
# SPDX-License-Identifier: MPL-2.0
# Launch smoke test: the packaged app must start, stay alive and register a window.
# Opt-in (STUDIO_UPKEEP_SMOKE=1): launches the normal app with existing preferences.
# Saved settings can trigger a local scan; normal app startup can update its own
# preferences/cache/scan history. This is not an isolated or write-free test.
set -euo pipefail
APP="${1:?Usage: smoke-launch.sh PATH_TO_APP}"
EXECUTABLE="$APP/Contents/MacOS/ProducerUpToDate"
[[ -x "$EXECUTABLE" ]] || { echo "Smoke: executable missing at $EXECUTABLE" >&2; exit 1; }
# -n forces a fresh instance even if another build with the same bundle identity is running.
open -n "$APP"
PID=""
for _ in {1..30}; do
    PID="$(pgrep -n -x -f -- "${EXECUTABLE//./\\.}" || true)"
    [[ -n "$PID" ]] && break
    sleep 0.5
done
[[ -n "$PID" ]] || { echo "Smoke: process did not start" >&2; exit 1; }
sleep 4
kill -0 "$PID" 2>/dev/null || { echo "Smoke: process exited within 4 seconds" >&2; exit 1; }
WINDOWS="$(osascript -e 'tell application "System Events" to count windows of (first process whose unix id is '"$PID"')' 2>/dev/null || echo "unavailable")"
kill -TERM "$PID" 2>/dev/null || true
if [[ "$WINDOWS" == "unavailable" ]]; then
    echo "Smoke: process alive after launch; window count not verified (Accessibility permission not granted to this shell)."
elif [[ "$WINDOWS" -ge 1 ]]; then
    echo "Smoke: process alive with $WINDOWS window(s)."
else
    echo "Smoke: process alive but registered no window" >&2; exit 1
fi
