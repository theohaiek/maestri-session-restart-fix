# shellcheck shell=bash
# Shared functions for macOS and Linux. Compatible with bash 3.2 (the macOS default).

MSRF_NAME="maestri-session-restart-fix"
MSRF_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -z "${MSRF_HOME:-}" ]; then
    if [ "$(basename "$MSRF_LIB_DIR")" = "bin" ]; then MSRF_HOME="$(dirname "$MSRF_LIB_DIR")"
    else MSRF_HOME="${XDG_DATA_HOME:-$HOME/.local/share}/$MSRF_NAME"; fi
fi
MSRF_TABS_DIR="$MSRF_HOME/tabs"
MSRF_LOG="$MSRF_HOME/msrf.log"
MSRF_CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
MSRF_MAESTRI_DIR="${MAESTRI_DATA_DIR:-$HOME/.maestri}"
MSRF_AUTO_START_SECONDS=120

msrf_lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

msrf_log() {
    mkdir -p "$MSRF_HOME" 2>/dev/null || return 0
    if [ -f "$MSRF_LOG" ] && [ "$(wc -c < "$MSRF_LOG")" -gt 524288 ]; then
        tail -n 2000 "$MSRF_LOG" > "$MSRF_LOG.tmp" && mv "$MSRF_LOG.tmp" "$MSRF_LOG"
    fi
    printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" >> "$MSRF_LOG" 2>/dev/null || true
}

msrf_is_session_id() {
    printf '%s' "$1" | grep -Eq '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
}

msrf_tab_session() {
    local file="$MSRF_TABS_DIR/$1.txt" value
    [ -f "$file" ] || return 1
    value="$(msrf_lower "$(tr -d '[:space:]' < "$file")")"
    msrf_is_session_id "$value" || return 1
    printf '%s' "$value"
}

msrf_owner_of_session() {
    local file
    for file in "$MSRF_TABS_DIR"/*.txt; do
        [ -f "$file" ] || continue
        if [ "$(msrf_lower "$(tr -d '[:space:]' < "$file")")" = "$1" ]; then basename "$file" .txt; fi
    done
}

msrf_set_tab_session() {
    local terminal session owner
    terminal="$(msrf_lower "$1")"
    session="$(msrf_lower "$2")"
    mkdir -p "$MSRF_TABS_DIR"
    for owner in $(msrf_owner_of_session "$session"); do
        if [ "$owner" != "$terminal" ]; then
            rm -f "$MSRF_TABS_DIR/$owner.txt"
            msrf_log "moved $session from $owner"
        fi
    done
    printf '%s' "$session" > "$MSRF_TABS_DIR/$terminal.txt.tmp" && mv "$MSRF_TABS_DIR/$terminal.txt.tmp" "$MSRF_TABS_DIR/$terminal.txt"
}

msrf_transcript() {
    msrf_is_session_id "$1" || return 1
    local found
    for found in "$MSRF_CLAUDE_DIR"/projects/*/"$1".jsonl; do
        if [ -f "$found" ]; then printf '%s' "$found"; return 0; fi
    done
    return 1
}

msrf_has_prompt() { [ -f "$1" ] && head -n 300 "$1" | grep -q '"type":"user"'; }

msrf_mtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || echo 0; }

# Process table: real `ps`, or a fake "pid ppid name" file in MSRF_PS_TABLE for tests.
msrf_proc_parent() {
    if [ -n "${MSRF_PS_TABLE:-}" ]; then awk -v id="$1" '$1 == id { print $2 }' "$MSRF_PS_TABLE"; return; fi
    ps -o ppid= -p "$1" 2>/dev/null | tr -d ' '
}

msrf_proc_name() {
    local name
    if [ -n "${MSRF_PS_TABLE:-}" ]; then
        name="$(awk -v id="$1" '$1 == id { print $3 }' "$MSRF_PS_TABLE")"
    else
        name="$(ps -o comm= -p "$1" 2>/dev/null)"
    fi
    name="${name##*/}"
    name="${name#-}"
    msrf_lower "$name"
}

msrf_is_shell() {
    case "$1" in
        bash|sh|zsh|dash|fish|nu|ksh|tcsh|login|powershell|pwsh) return 0 ;;
        *) return 1 ;;
    esac
}

msrf_is_maestri() { case "$1" in maestri*) return 0 ;; *) return 1 ;; esac; }

msrf_launched_from_tab() {
    local parent name hop=0
    parent="$(msrf_proc_parent "$1")"
    while [ "$hop" -lt 4 ]; do
        [ -n "$parent" ] && [ "$parent" != "0" ] || return 1
        name="$(msrf_proc_name "$parent")"
        [ -n "$name" ] || return 1
        if msrf_is_maestri "$name"; then [ "$hop" -gt 0 ]; return; fi
        msrf_is_shell "$name" || return 1
        parent="$(msrf_proc_parent "$parent")"
        hop=$((hop + 1))
    done
    return 1
}

msrf_hook_owner() {
    local candidate name hop=0
    candidate="$(msrf_proc_parent "$1")"
    while [ "$hop" -lt 3 ]; do
        [ -n "$candidate" ] && [ "$candidate" != "0" ] || return 1
        name="$(msrf_proc_name "$candidate")"
        [ -n "$name" ] || return 1
        if ! msrf_is_shell "$name"; then printf '%s' "$candidate"; return 0; fi
        candidate="$(msrf_proc_parent "$candidate")"
        hop=$((hop + 1))
    done
    return 1
}

msrf_shell_owned_by_maestri() {
    local parent name hop=0
    parent="$(msrf_proc_parent "$1")"
    while [ "$hop" -lt 2 ]; do
        [ -n "$parent" ] && [ "$parent" != "0" ] || return 1
        name="$(msrf_proc_name "$parent")"
        msrf_is_maestri "$name" && return 0
        msrf_is_shell "$name" || return 1
        parent="$(msrf_proc_parent "$parent")"
        hop=$((hop + 1))
    done
    return 1
}

msrf_process_age_seconds() {
    local elapsed days=0 hours=0 minutes=0 seconds=0 rest
    elapsed="$(ps -o etime= -p "$1" 2>/dev/null | tr -d ' ')"
    [ -n "$elapsed" ] || { echo 999999; return; }
    case "$elapsed" in *-*) days="${elapsed%%-*}"; elapsed="${elapsed#*-}" ;; esac
    rest="$elapsed"
    seconds="${rest##*:}"; rest="${rest%:*}"
    if [ "$rest" != "$elapsed" ]; then
        minutes="${rest##*:}"
        case "$rest" in *:*) hours="${rest%%:*}" ;; esac
    fi
    echo $(( 10#$days * 86400 + 10#$hours * 3600 + 10#$minutes * 60 + 10#$seconds ))
}

msrf_session_live() {
    local file pid name
    for file in "$MSRF_CLAUDE_DIR"/sessions/*.json; do
        [ -f "$file" ] || continue
        grep -q "\"sessionId\":\"$1\"" "$file" || continue
        pid="$(basename "$file" .json)"
        kill -0 "$pid" 2>/dev/null || continue
        name="$(msrf_proc_name "$pid")"
        case "$name" in claude*|node*|bun*) return 0 ;; esac
    done
    return 1
}

msrf_process_environment_variable() {
    local pid="$1" name="$2"
    if [ -r "/proc/$pid/environ" ]; then
        tr '\0' '\n' < "/proc/$pid/environ" | sed -n "s/^$name=//p" | head -n 1
    else
        ps eww -o command= -p "$pid" 2>/dev/null | tr ' ' '\n' | sed -n "s/^$name=//p" | head -n 1
    fi
}

msrf_config_value() {
    local file="$MSRF_HOME/config" key="$1"
    [ -f "$file" ] || return 0
    sed -n "s/^$key=//p" "$file" | head -n 1
}

msrf_save_config() {
    mkdir -p "$MSRF_HOME"
    printf 'effort=%s\nultracode=%s\n' "$1" "$2" > "$MSRF_HOME/config"
    if [ "$2" = "on" ]; then
        printf '{\n  "ultracode": true\n}\n' > "$MSRF_HOME/session-settings.json"
    else
        rm -f "$MSRF_HOME/session-settings.json"
    fi
}

# Decision. Inputs: MSRF_TERMINAL, MSRF_AUTO (1 or 0) and the claude arguments.
# Output: the arguments to run, one per line, in MSRF_DECISION; message in MSRF_MESSAGE.
msrf_decide() {
    local requested="" has_value=0 resume_index=-1 position=0 argument tab_session="" tab_file="" requested_file="" chosen="" owner already_open=0
    MSRF_MESSAGE=""
    for argument in "$@"; do
        if [ "$resume_index" -lt 0 ] && { [ "$argument" = "--resume" ] || [ "$argument" = "-r" ]; }; then
            resume_index=$position
        elif [ "$resume_index" -ge 0 ] && [ "$position" -eq $((resume_index + 1)) ] && [ "${argument#-}" = "$argument" ]; then
            requested="$(msrf_lower "$argument")"
            has_value=1
        fi
        position=$((position + 1))
    done

    tab_session="$(msrf_tab_session "$MSRF_TERMINAL" || true)"
    if [ -n "$tab_session" ]; then tab_file="$(msrf_transcript "$tab_session" || true)"; fi
    [ -n "$tab_file" ] || tab_session=""
    if [ -n "$requested" ]; then requested_file="$(msrf_transcript "$requested" || true)"; fi

    if [ -n "$requested_file" ]; then
        owner="$(msrf_owner_of_session "$requested" | grep -v "^$MSRF_TERMINAL\$" | head -n 1)"
        if [ "$requested" = "$tab_session" ]; then chosen="$requested"
        elif [ "$MSRF_AUTO" != "1" ]; then chosen="$requested"
        elif [ -n "$owner" ]; then chosen="$tab_session"
        elif [ -n "$tab_session" ] && msrf_has_prompt "$requested_file" && [ "$(msrf_mtime "$requested_file")" -gt "$(msrf_mtime "$tab_file")" ]; then chosen="$requested"
        elif [ -n "$tab_session" ]; then chosen="$tab_session"
        elif msrf_has_prompt "$requested_file"; then chosen="$requested"
        fi
    else
        chosen="$tab_session"
    fi

    if [ -n "$chosen" ] && msrf_session_live "$chosen"; then
        MSRF_MESSAGE="Session $chosen is already open in another process; starting a new session in this tab."
        chosen=""
        already_open=1
    fi

    MSRF_DECISION=""
    MSRF_CHOSEN="$chosen"
    if [ -z "$chosen" ] && [ "$MSRF_AUTO" != "1" ] && [ "$already_open" -eq 0 ]; then
        for argument in "$@"; do MSRF_DECISION="$MSRF_DECISION$argument
"; done
        return 0
    fi
    if [ -n "$chosen" ]; then MSRF_DECISION="--resume
$chosen
"; fi
    position=0
    for argument in "$@"; do
        if [ "$position" -ne "$resume_index" ] && { [ "$has_value" -eq 0 ] || [ "$position" -ne $((resume_index + 1)) ]; }; then
            MSRF_DECISION="$MSRF_DECISION$argument
"
        fi
        position=$((position + 1))
    done
}

msrf_wait_turn() {
    local file="$1" size interval queue="$MSRF_HOME/queue" lock="$MSRF_HOME/queue.lock" now previous turn wait attempt=0
    size="$(wc -c < "$file" | tr -d ' ')"
    interval=$(( 3 + (4 * size + 1073741823) / 1073741824 ))
    while ! mkdir "$lock" 2>/dev/null; do
        attempt=$((attempt + 1))
        [ "$attempt" -lt 100 ] || return 0
        sleep 0.2
    done
    now="$(date +%s)"
    previous="$(cat "$queue" 2>/dev/null || echo 0)"
    turn=$now
    [ "${previous:-0}" -gt "$now" ] && turn=$previous
    echo $((turn + interval)) > "$queue"
    rmdir "$lock"
    wait=$((turn - now))
    if [ "$wait" -gt 0 ]; then
        echo "[$MSRF_NAME] waiting $wait s so the tabs reopen one after another."
        sleep "$wait"
    fi
}
