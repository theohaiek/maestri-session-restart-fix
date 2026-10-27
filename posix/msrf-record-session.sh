#!/usr/bin/env bash
# Claude Code hook (UserPromptSubmit and SessionStart): remembers which session runs in which Maestri tab.
# Prints nothing: UserPromptSubmit output would be added to the conversation.
. "$(dirname "$0")/msrf-lib.sh"

main() {
    local terminal payload session event source summary owner
    terminal="$(msrf_lower "${MAESTRI_TERMINAL_ID:-}")"
    [ -n "$terminal" ] || return 0
    payload="$(cat)"
    session="$(printf '%s' "$payload" | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([0-9a-fA-F-]\{36\}\)".*/\1/p' | head -n 1)"
    session="$(msrf_lower "$session")"
    event="$(printf '%s' "$payload" | sed -n 's/.*"hook_event_name"[[:space:]]*:[[:space:]]*"\([A-Za-z]*\)".*/\1/p' | head -n 1)"
    source="$(printf '%s' "$payload" | sed -n 's/.*"source"[[:space:]]*:[[:space:]]*"\([A-Za-z]*\)".*/\1/p' | head -n 1)"
    msrf_is_session_id "$session" || return 0
    summary="$event:$source $terminal $session"
    if [ "$event" = "SessionStart" ]; then
        case "$source" in
            resume|clear|compact) ;;
            *) msrf_log "ignored $summary"; return 0 ;;
        esac
    fi
    owner="$(msrf_hook_owner "$$" || true)"
    if [ -z "$owner" ] || ! msrf_launched_from_tab "$owner"; then
        msrf_log "outside-tab $summary"
        return 0
    fi
    msrf_set_tab_session "$terminal" "$session"
    msrf_log "recorded $summary"
}

main > /dev/null 2>&1 || true
exit 0
