#!/usr/bin/env bash
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SANDBOX="$(mktemp -d)"
export MSRF_HOME="$SANDBOX/home"
export CLAUDE_CONFIG_DIR="$SANDBOX/claude"
. "$ROOT/posix/msrf-lib.sh"

passed=0
failed=0
expect() {
    if [ "$1" = "$2" ]; then passed=$((passed + 1)); echo "ok   $3"
    else failed=$((failed + 1)); echo "FAIL $3"; echo "     expected: $1"; echo "     actual:   $2"; fi
}

PROJECT="$CLAUDE_CONFIG_DIR/projects/project-a"
mkdir -p "$PROJECT" "$CLAUDE_CONFIG_DIR/sessions"
transcript() {
    if [ "$2" = "prompt" ]; then echo '{"type":"user","message":{"content":"hi"}}' > "$PROJECT/$1.jsonl"
    else echo '{"type":"summary"}' > "$PROJECT/$1.jsonl"; fi
    touch -t "$3" "$PROJECT/$1.jsonl"
}
TAB_SESSION=11111111-1111-1111-1111-111111111111
OTHER_SESSION=22222222-2222-2222-2222-222222222222
OLDER_SESSION=33333333-3333-3333-3333-333333333333
NEWER_SESSION=44444444-4444-4444-4444-444444444444
EMPTY_SESSION=55555555-5555-5555-5555-555555555555
transcript "$TAB_SESSION" prompt 202601010000
transcript "$OTHER_SESSION" prompt 202601010100
transcript "$OLDER_SESSION" prompt 202512010000
transcript "$NEWER_SESSION" prompt 202601020000
transcript "$EMPTY_SESSION" empty 202601030000
TAB=aaaaaaaa-0000-0000-0000-000000000001
OTHER_TAB=aaaaaaaa-0000-0000-0000-000000000002
msrf_set_tab_session "$TAB" "$TAB_SESSION"
msrf_set_tab_session "$OTHER_TAB" "$OTHER_SESSION"

decide() {
    MSRF_TERMINAL="$1"; MSRF_AUTO="$2"; shift 2
    msrf_decide "$@"
    printf '%s' "$MSRF_DECISION" | tr '\n' ' ' | sed 's/ $//'
}
expect "--resume $TAB_SESSION" "$(decide "$TAB" 1)" "auto start without arguments resumes the tab session"
expect "--resume $TAB_SESSION" "$(decide "$TAB" 1 --resume 910)" "cut id is replaced by the tab session"
expect "--resume $TAB_SESSION" "$(decide "$TAB" 1 --resume "$EMPTY_SESSION")" "empty session is replaced by the tab session"
expect "--resume $TAB_SESSION --effort max" "$(decide "$TAB" 1 --resume --effort max)" "resume without value keeps the other arguments"
expect "--resume $TAB_SESSION" "$(decide "$TAB" 1 --resume "$OTHER_SESSION")" "id owned by another tab is refused at auto start"
expect "--resume $TAB_SESSION" "$(decide "$TAB" 1 --resume "$OLDER_SESSION")" "older unmapped session loses to the tab session"
expect "--resume $NEWER_SESSION" "$(decide "$TAB" 1 --resume "$NEWER_SESSION")" "newer unmapped session with prompts wins"
expect "" "$(decide aaaaaaaa-0000-0000-0000-00000000ffff 1 --resume "$EMPTY_SESSION")" "unknown tab with empty session starts a new session"
expect "--resume $OLDER_SESSION" "$(decide "$TAB" 0 --resume "$OLDER_SESSION")" "typed by hand the requested session is honored"
expect "--resume" "$(decide aaaaaaaa-0000-0000-0000-00000000ffff 0 --resume)" "typed by hand picker stays a picker"

msrf_set_tab_session "$OTHER_TAB" "$TAB_SESSION"
expect "" "$(msrf_tab_session "$TAB" || true)" "a session moves to the last tab that used it"
msrf_set_tab_session "$TAB" "$TAB_SESSION"

TABLE="$SANDBOX/ps"
printf '1 0 launchd\n10 1 Maestri\n20 10 -zsh\n30 20 claude\n40 30 sh\n41 40 bash\n' > "$TABLE"
expect "30" "$(MSRF_PS_TABLE="$TABLE" msrf_hook_owner 41)" "hook owner skips the hook runner shells"
MSRF_PS_TABLE="$TABLE" msrf_launched_from_tab 30 && result=yes || result=no
expect "yes" "$result" "claude typed in a Maestri tab is accepted"
printf '10 1 Maestri\n20 10 zsh\n30 20 claude\n50 30 bash\n60 50 claude\n70 60 sh\n71 70 bash\n' > "$TABLE"
expect "60" "$(MSRF_PS_TABLE="$TABLE" msrf_hook_owner 71)" "nested claude owns its own hook"
MSRF_PS_TABLE="$TABLE" msrf_launched_from_tab 60 && result=yes || result=no
expect "no" "$result" "claude started by another claude is refused"
printf '10 1 Maestri\n15 10 login\n20 15 zsh\n30 20 node\n' > "$TABLE"
MSRF_PS_TABLE="$TABLE" msrf_launched_from_tab 30 && result=yes || result=no
expect "yes" "$result" "login shell and npm-installed claude are accepted"

msrf_save_config max on
expect "max" "$(msrf_config_value effort)" "effort default saved"
[ -f "$MSRF_HOME/session-settings.json" ] && result=yes || result=no
expect "yes" "$result" "ultracode settings file written"
msrf_save_config default off
[ -f "$MSRF_HOME/session-settings.json" ] && result=yes || result=no
expect "no" "$result" "ultracode settings file removed"

if command -v python3 > /dev/null 2>&1; then
    SETTINGS="$SANDBOX/settings.json"
    echo '{"model":"opus","hooks":{"UserPromptSubmit":[{"hooks":[{"type":"command","command":"other-hook"}]}]}}' > "$SETTINGS"
    python3 "$ROOT/posix/msrf_settings.py" "$SETTINGS" 'bash "/x/msrf-record-session.sh"'
    python3 "$ROOT/posix/msrf_settings.py" "$SETTINGS" 'bash "/x/msrf-record-session.sh"'
    expect "2" "$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))["hooks"]["UserPromptSubmit"]))' "$SETTINGS")" "install keeps the other hook and adds ours once"
    python3 "$ROOT/posix/msrf_settings.py" "$SETTINGS" "" --remove
    expect "other-hook|False" "$(python3 -c 'import json,sys; s=json.load(open(sys.argv[1])); print(s["hooks"]["UserPromptSubmit"][0]["hooks"][0]["command"] + "|" + str("SessionStart" in s["hooks"]))' "$SETTINGS")" "uninstall keeps the other hook"
fi
if [ "$(uname -s)" = "Darwin" ]; then
    SETTINGS="$SANDBOX/settings-jxa.json"
    echo '{"model":"opus"}' > "$SETTINGS"
    osascript -l JavaScript "$ROOT/posix/msrf-settings.js" "$SETTINGS" 'bash "/x/msrf-record-session.sh"' > /dev/null
    grep -q 'msrf-record-session.sh' "$SETTINGS" && grep -q '"model": "opus"' "$SETTINGS" && result=yes || result=no
    expect "yes" "$result" "JXA settings editor works without python3"
fi

output="$(printf '{"session_id":"%s","hook_event_name":"UserPromptSubmit"}' "$NEWER_SESSION" | MAESTRI_TERMINAL_ID=aaaaaaaa-0000-0000-0000-000000000009 bash "$ROOT/posix/msrf-record-session.sh")"
expect "" "$output" "the hook prints nothing"
grep -Eq '(recorded|outside-tab) UserPromptSubmit: aaaaaaaa-0000-0000-0000-000000000009' "$MSRF_LOG" && result=yes || result=no
expect "yes" "$result" "the hook reads the payload and logs the decision"

for script in "$ROOT"/posix/*.sh "$ROOT"/install.sh "$ROOT"/uninstall.sh "$ROOT"/doctor.sh; do
    bash -n "$script" && result=yes || result=no
    expect "yes" "$result" "bash syntax: $(basename "$script")"
done

rm -rf "$SANDBOX"
echo
echo "$passed passed, $failed failed"
[ "$failed" -eq 0 ]
