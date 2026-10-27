#!/usr/bin/env bash
# Runs instead of `claude` inside a Maestri tab and reopens the tab's own session.
. "$(dirname "$0")/msrf-lib.sh"

find_claude() {
    local candidate
    for candidate in $(type -a -p claude 2>/dev/null); do
        case "$candidate" in *"$MSRF_NAME"*) continue ;; esac
        printf '%s' "$candidate"
        return 0
    done
    [ -x "$HOME/.local/bin/claude" ] && { printf '%s' "$HOME/.local/bin/claude"; return 0; }
    [ -x "$HOME/.claude/local/claude" ] && { printf '%s' "$HOME/.claude/local/claude"; return 0; }
    return 1
}

CLAUDE_BIN="$(find_claude)" || { echo "[$MSRF_NAME] claude was not found on PATH."; exit 1; }

with_defaults() {
    local effort ultracode argument has_effort=0 has_settings=0
    for argument in "$@"; do
        [ "$argument" = "--effort" ] && has_effort=1
        [ "$argument" = "--settings" ] && has_settings=1
    done
    effort="$(msrf_config_value effort)"
    ultracode="$(msrf_config_value ultracode)"
    set -- "$@"
    if [ -n "$effort" ] && [ "$effort" != "default" ] && [ "$has_effort" -eq 0 ]; then set -- "$@" --effort "$effort"; fi
    if [ "$ultracode" = "on" ] && [ "$has_settings" -eq 0 ] && [ -f "$MSRF_HOME/session-settings.json" ]; then
        set -- "$@" --settings "$MSRF_HOME/session-settings.json"
    fi
    exec "$CLAUDE_BIN" "$@"
}

for argument in "$@"; do
    if [ "$argument" = "--new-session" ]; then
        remaining=()
        for kept in "$@"; do [ "$kept" = "--new-session" ] || remaining+=("$kept"); done
        with_defaults ${remaining[@]+"${remaining[@]}"}
    fi
done

terminal="$(msrf_lower "${MAESTRI_TERMINAL_ID:-}")"
pass_through=0
[ -n "$terminal" ] || pass_through=1
for argument in "$@"; do
    case "$argument" in -p|--print|-c|--continue|-h|--help|-v|--version) pass_through=1 ;; esac
done
if [ "$pass_through" -eq 0 ] && ! msrf_shell_owned_by_maestri "$PPID"; then pass_through=1; fi
[ "$pass_through" -eq 1 ] && exec "$CLAUDE_BIN" "$@"

# shellcheck disable=SC2034  # read by msrf_decide in msrf-lib.sh
MSRF_TERMINAL="$terminal"
MSRF_AUTO=0
[ "$(msrf_process_age_seconds "$PPID")" -lt "$MSRF_AUTO_START_SECONDS" ] && MSRF_AUTO=1
msrf_decide "$@"
[ -n "$MSRF_MESSAGE" ] && echo "[$MSRF_NAME] $MSRF_MESSAGE"

decided=()
while IFS= read -r line; do decided+=("$line"); done <<EOF
$MSRF_DECISION
EOF
final=()
for line in ${decided[@]+"${decided[@]}"}; do [ -n "$line" ] && final+=("$line"); done

if [ -n "$MSRF_CHOSEN" ] && [ "$MSRF_AUTO" = "1" ]; then
    transcript="$(msrf_transcript "$MSRF_CHOSEN" || true)"
    [ -n "$transcript" ] && msrf_wait_turn "$transcript"
fi
with_defaults ${final[@]+"${final[@]}"}
