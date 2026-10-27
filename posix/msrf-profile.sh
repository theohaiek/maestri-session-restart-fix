# shellcheck shell=sh
# Sourced from ~/.zshrc and ~/.bashrc by the line the installer adds. Active only inside Maestri tabs.
if [ -n "${MAESTRI_TERMINAL_ID:-}" ] && [ -n "${MSRF_BIN:-}" ]; then
    claude() { "$MSRF_BIN/msrf-claude-tab.sh" "$@"; }
fi
