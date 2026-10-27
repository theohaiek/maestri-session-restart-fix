#!/usr/bin/env bash
# Removes maestri-session-restart-fix on macOS or Linux. Usage: ./uninstall.sh [--remove-data]
set -u
ROOT="$(cd "$(dirname "$0")" && pwd)"
. "$ROOT/posix/msrf-lib.sh"

SETTINGS="$MSRF_CLAUDE_DIR/settings.json"
if [ -f "$SETTINGS" ]; then
    cp "$SETTINGS" "$SETTINGS.msrf-backup-$(date +%Y%m%d-%H%M%S)"
    if command -v python3 > /dev/null 2>&1; then
        python3 "$ROOT/posix/msrf_settings.py" "$SETTINGS" "" --remove
    else
        osascript -l JavaScript "$ROOT/posix/msrf-settings.js" "$SETTINGS" "" --remove > /dev/null
    fi
    echo "OK    Hooks removed from $SETTINGS"
fi
for rc in "$HOME/.zshrc" "$HOME/.bashrc"; do
    [ -f "$rc" ] || continue
    grep -v "# $MSRF_NAME\$" "$rc" > "$rc.msrf-tmp" || true
    cat "$rc.msrf-tmp" > "$rc" && rm -f "$rc.msrf-tmp"
    echo "OK    Line removed from $rc"
done
rm -rf "${MSRF_HOME:?}/bin"
echo "OK    Removed $MSRF_HOME/bin"
if [ "${1:-}" = "--remove-data" ]; then rm -rf "${MSRF_HOME:?}"; echo "OK    Removed $MSRF_HOME"; fi
echo "Uninstalled. Open terminals keep the claude function until they are closed."
