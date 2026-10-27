#!/usr/bin/env bash
# Installs maestri-session-restart-fix on macOS or Linux. Usage: ./install.sh [--effort LEVEL] [--ultracode on|off] [--no-seed]
set -u
ROOT="$(cd "$(dirname "$0")" && pwd)"
. "$ROOT/posix/msrf-lib.sh"

ok() { printf 'OK    %s\n' "$1"; }
warn() { printf 'WARN  %s\n' "$1"; }
fail() { printf 'FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '      fix: %s\n' "$2"; exit 1; }

effort="ask"
ultracode="ask"
seed=1
while [ $# -gt 0 ]; do
    case "$1" in
        --effort) effort="${2:-}"; shift 2 ;;
        --ultracode) ultracode="${2:-}"; shift 2 ;;
        --no-seed) seed=0; shift ;;
        *) fail "Unknown option $1" "Use --effort default|low|medium|high|xhigh|max, --ultracode on|off, --no-seed" ;;
    esac
done
case "$effort" in ask|default|low|medium|high|xhigh|max) ;; *) fail "Invalid --effort $effort" ;; esac
case "$ultracode" in ask|on|off) ;; *) fail "Invalid --ultracode $ultracode" ;; esac

case "$(uname -s)" in
    Darwin|Linux) ;;
    *) fail "This installer is for macOS and Linux." "On Windows run install.ps1 in PowerShell." ;;
esac

CLAUDE_FOUND="$(type -a -p claude 2>/dev/null | grep -v "$MSRF_NAME" | head -n 1)"
[ -n "$CLAUDE_FOUND" ] || fail "Claude Code was not found on PATH." "Install Claude Code (https://code.claude.com) and open a new terminal."
ok "Claude Code found: $CLAUDE_FOUND"

BIN="$MSRF_HOME/bin"
mkdir -p "$BIN" "$MSRF_TABS_DIR"
cp "$ROOT"/posix/msrf-lib.sh "$ROOT"/posix/msrf-record-session.sh "$ROOT"/posix/msrf-claude-tab.sh "$ROOT"/posix/msrf-profile.sh \
   "$ROOT"/posix/msrf_settings.py "$ROOT"/posix/msrf-settings.js "$BIN/"
chmod +x "$BIN"/*.sh
if [ "$(uname -s)" = "Darwin" ]; then xattr -d com.apple.quarantine "$BIN"/* 2>/dev/null || true; fi
ok "Scripts installed in $BIN"

SETTINGS="$MSRF_CLAUDE_DIR/settings.json"
HOOK_COMMAND="bash \"$BIN/msrf-record-session.sh\""
if [ -f "$SETTINGS" ]; then
    BACKUP="$SETTINGS.msrf-backup-$(date +%Y%m%d-%H%M%S)"
    cp "$SETTINGS" "$BACKUP"
    ok "Backup of the Claude settings: $BACKUP"
fi
if command -v python3 > /dev/null 2>&1 && python3 -c 'import json' > /dev/null 2>&1; then
    python3 "$BIN/msrf_settings.py" "$SETTINGS" "$HOOK_COMMAND" || fail "Could not update $SETTINGS (is it valid JSON?)" "Fix the file and run the installer again."
elif [ "$(uname -s)" = "Darwin" ]; then
    osascript -l JavaScript "$BIN/msrf-settings.js" "$SETTINGS" "$HOOK_COMMAND" > /dev/null || fail "Could not update $SETTINGS (is it valid JSON?)" "Fix the file and run the installer again."
else
    fail "python3 is needed to edit $SETTINGS on Linux." "Install python3 and run the installer again."
fi
ok "Hooks UserPromptSubmit and SessionStart added to $SETTINGS"

PROFILE_LINE="MSRF_BIN=\"$BIN\"; [ -f \"\$MSRF_BIN/msrf-profile.sh\" ] && . \"\$MSRF_BIN/msrf-profile.sh\" # $MSRF_NAME"
for rc in "$HOME/.zshrc" "$HOME/.bashrc"; do
    touch "$rc"
    grep -v "# $MSRF_NAME\$" "$rc" > "$rc.msrf-tmp" || true
    printf '%s\n' "$PROFILE_LINE" >> "$rc.msrf-tmp"
    cat "$rc.msrf-tmp" > "$rc" && rm -f "$rc.msrf-tmp"
    ok "Shell startup file updated: $rc"
done
case "$(basename "${SHELL:-}")" in
    zsh|bash|"") ;;
    *) warn "Your login shell is ${SHELL}. Maestri tabs must run zsh or bash for the fix to load." ;;
esac

ask() {
    local question="$1" options="$2" fallback="$3" answer
    if [ ! -t 0 ]; then printf '%s' "$fallback"; return; fi
    while true; do
        printf '%s [%s] (Enter = %s): ' "$question" "$options" "$fallback" > /dev/tty
        read -r answer < /dev/tty
        answer="$(msrf_lower "$answer")"
        [ -n "$answer" ] || { printf '%s' "$fallback"; return; }
        case "/$options/" in *"/$answer/"*) printf '%s' "$answer"; return ;; esac
    done
}
current_effort="$(msrf_config_value effort)"; current_effort="${current_effort:-default}"
current_ultracode="$(msrf_config_value ultracode)"; current_ultracode="${current_ultracode:-off}"
[ "$effort" = "ask" ] && effort="$(ask 'Effort level for the sessions the fix opens' 'default/low/medium/high/xhigh/max' "$current_effort")"
[ "$ultracode" = "ask" ] && ultracode="$(ask 'Turn ultracode on in those sessions' 'on/off' "$current_ultracode")"
msrf_save_config "$effort" "$ultracode"
ok "Session defaults: effort $effort, ultracode $ultracode (flags typed in a tab always win)"

if [ "$seed" -eq 1 ]; then
    recorded=0
    for file in "$MSRF_CLAUDE_DIR"/sessions/*.json; do
        [ -f "$file" ] || continue
        pid="$(basename "$file" .json)"
        kill -0 "$pid" 2>/dev/null || continue
        session="$(sed -n 's/.*"sessionId":"\([0-9a-f-]\{36\}\)".*/\1/p' "$file" | head -n 1)"
        terminal="$(msrf_process_environment_variable "$pid" MAESTRI_TERMINAL_ID)"
        [ -n "$session" ] && [ -n "$terminal" ] || continue
        transcript="$(msrf_transcript "$session" || true)"
        [ -n "$transcript" ] && msrf_has_prompt "$transcript" || continue
        msrf_set_tab_session "$terminal" "$session"
        msrf_log "seeded $(msrf_lower "$terminal") $session"
        recorded=$((recorded + 1))
    done
    ok "Tabs mapped from the sessions open right now: $recorded"
fi

echo
echo "Installed. Next:"
echo "  1. Send any message in each Maestri tab whose session is not mapped yet (./doctor.sh lists them)."
echo "  2. Quit and reopen Maestri. Tabs reopen one after another on their own sessions."
echo "  3. Check with: ./doctor.sh"
