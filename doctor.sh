#!/usr/bin/env bash
# Checks the installation on macOS or Linux. Exit code 1 when something blocks the fix.
set -u
ROOT="$(cd "$(dirname "$0")" && pwd)"
. "$ROOT/posix/msrf-lib.sh"
failures=0
check() {
    printf '%-5s %s\n' "$1" "$2"
    [ "$1" = "FAIL" ] && failures=$((failures + 1))
    return 0
}

check INFO "$(uname -s) $(uname -r), bash $BASH_VERSION"
CLAUDE_FOUND="$(type -a -p claude 2>/dev/null | grep -v "$MSRF_NAME" | head -n 1)"
if [ -n "$CLAUDE_FOUND" ]; then check OK "Claude Code: $CLAUDE_FOUND"; else check FAIL "Claude Code not found on PATH"; fi

BIN="$MSRF_HOME/bin"
missing=""
for file in msrf-lib.sh msrf-record-session.sh msrf-claude-tab.sh msrf-profile.sh; do [ -f "$BIN/$file" ] || missing="$missing $file"; done
if [ -z "$missing" ]; then check OK "Scripts installed in $BIN"; else check FAIL "Missing in $BIN:$missing"; fi

SETTINGS="$MSRF_CLAUDE_DIR/settings.json"
for event in UserPromptSubmit SessionStart; do
    if [ -f "$SETTINGS" ] && grep -q "\"$event\"" "$SETTINGS" && grep -q 'msrf-record-session.sh' "$SETTINGS"; then
        check OK "$event hook present in $SETTINGS"
    else
        check FAIL "$event hook missing in $SETTINGS"
    fi
done
if [ -f "$SETTINGS" ] && grep -Eq '"disableAllHooks"[[:space:]]*:[[:space:]]*true' "$SETTINGS"; then check FAIL "disableAllHooks is true in $SETTINGS"; fi

for rc in "$HOME/.zshrc" "$HOME/.bashrc"; do
    if [ -f "$rc" ] && grep -q "# $MSRF_NAME\$" "$rc"; then check OK "$rc loads the fix"; else check FAIL "$rc does not load the fix"; fi
done

check INFO "Session defaults: effort $(msrf_config_value effort), ultracode $(msrf_config_value ultracode)"

tabs=0
unmapped=0
for workspace in "$MSRF_MAESTRI_DIR"/workspaces/*/workspace.json; do
    [ -f "$workspace" ] || continue
    for id in $(grep -o '"agentType" *: *"claude_code"[^}]*"id" *: *"[0-9A-Fa-f-]\{36\}"' "$workspace" | sed 's/.*"id" *: *"\([0-9A-Fa-f-]*\)"/\1/'); do
        tabs=$((tabs + 1))
        session="$(msrf_tab_session "$(msrf_lower "$id")" || true)"
        if [ -z "$session" ] || ! msrf_transcript "$session" > /dev/null; then unmapped=$((unmapped + 1)); fi
    done
done
if [ "$tabs" -eq 0 ]; then check WARN "No Claude Code tabs found in $MSRF_MAESTRI_DIR (the count is best effort)"
elif [ "$unmapped" -eq 0 ]; then check OK "All $tabs Claude Code tabs have a session to reopen"
else check WARN "$unmapped of $tabs Claude Code tabs have no session yet (send one message in each, or run ./install.sh again)"; fi

if [ -f "$MSRF_LOG" ]; then
    check INFO "Hook log: $(tail -n 200 "$MSRF_LOG" | grep -c ' recorded ') recordings, $(tail -n 200 "$MSRF_LOG" | grep -c ' error ') errors in the last 200 lines ($MSRF_LOG)"
else
    check INFO "Hook log not created yet (it appears after the first prompt in a Maestri tab)"
fi
[ "$failures" -eq 0 ]
