# How it works

## Why Maestri loses the sessions

Maestri (checked in 0.27) has a "resume sessions on relaunch" feature. For each Claude Code tab it keeps two things in
the workspace file:

- `resumeCommand`: on a clean quit, Maestri asks each agent to exit and reads the terminal for the line Claude prints
  on exit, `claude --resume <id>`. This is the "harvest".
- `runningResumeCommand`: the resume command Maestri itself used the last time it opened the tab. After an unclean
  exit (crash, forced update, reboot) there is no harvest, so Maestri falls back to this one.

When the tab opens again, Maestri types the terminal's command (`claude`) merged with whichever of the two it has.
That breaks in practice:

1. **No resume command at all.** A tab where you typed `claude` yourself has no `runningResumeCommand`. After an
   unclean exit it opens a brand new session.
2. **Cut ids.** The harvest reads screen text. In a narrow tab the line wraps and the id comes back as `910` or
   `b454cb40-`, and Claude then fails with `No conversation found`.
3. **Wrong ids.** Any `claude --resume <id>` printed on the screen can be picked up. A tab that ran a tool printing
   other sessions' ids may reopen on someone else's session, which then runs in two tabs at once.
4. **Stale ids.** A compaction or `/clear` creates a new session id. The command Maestri saved still points to the old
   one.

Measured on a 44-tab workspace after one restart: 5 tabs reopened on the right session, 39 opened blank.

## The fix

Nothing in Maestri is changed. The fix adds a reliable source of truth and puts itself where Maestri types `claude`.

### 1. A map of tab to session, written by Claude Code itself

Maestri gives every terminal a stable `MAESTRI_TERMINAL_ID` environment variable. Claude Code runs hooks with the
session id on stdin. Two hooks connect the two:

- `UserPromptSubmit`: each prompt in a tab writes `tabs/<MAESTRI_TERMINAL_ID>.txt = <session id>`.
- `SessionStart` with source `resume`, `clear` or `compact`: the same, so `/resume`, `/clear` and compactions update
  the map before the next prompt.

`SessionStart` with source `startup` is ignored on purpose. A tab that Maestri reopened blank never overwrites the
real session, because a blank session has not received a prompt.

A session belongs to one tab only: writing it for a tab removes it from any other tab.

The hook records only a Claude process typed directly in a Maestri tab. Its parent chain must be at most three
shells, then Maestri. A `claude -p` started by a script or an agent inside a tab has another Claude in its chain, so
it is ignored. The decision is logged in `msrf.log` as `recorded`, `outside-tab` or `ignored`.

The hook prints nothing, because `UserPromptSubmit` output would be added to the conversation. On Windows it takes
about 0.3 s, using a small native helper compiled at install; without the helper it falls back to WMI, at about
0.6 s.

### 2. A `claude` wrapper that only exists inside Maestri tabs

The installer adds one line to the PowerShell profiles (or to `~/.zshrc` and `~/.bashrc`). It defines a `claude`
function only when `MAESTRI_TERMINAL_ID` is set. Everywhere else `claude` is untouched.

The wrapper acts only when its shell belongs to Maestri, that is when the shell's parent is the Maestri process. When
the shell started less than 120 seconds ago, the launch counts as automatic: Maestri is restoring the tab.

| Maestri (or you) typed | Automatic launch | Typed later by hand |
|---|---|---|
| `claude` | tab session | tab session |
| `claude --resume <cut, blank or missing id>` | tab session | as typed |
| `claude --resume <id of another tab>` | tab session | as typed |
| `claude --resume <newer session with prompts, no owner>` | that session | as typed |
| `claude --resume <older session>` | tab session | as typed |
| any of the above, when the session is already open elsewhere | new session | new session |
| `-p`, `--print`, `-c`, `--continue`, `--help`, `--version` | untouched | untouched |
| `claude --new-session` | new session | new session |

Other flags (`--dangerously-skip-permissions`, `--model`, `--effort`) are kept. A session is "open elsewhere" when a
live Claude process has it in `~/.claude/sessions/<pid>.json`. The process start time is checked so that a reused pid
does not count.

### 3. Seeding at install time

At install, the fix lists the Claude processes that are open right now. For each one it takes the session id from
`~/.claude/sessions/<pid>.json` and reads `MAESTRI_TERMINAL_ID` from the process environment:

- Windows: through the process environment block, read for the user's own processes only.
- Linux: from `/proc/<pid>/environ`.
- macOS: through `ps eww`.

So the first restart after the install already works, even for sessions that started before the hooks existed.

### 4. Reopening in a queue

Restoring 40 sessions at the same moment means parsing many transcripts at once; on one machine that was 19.8 GB with
15 GB of free RAM. Automatic launches reserve a turn in a small queue file, waiting 3 s plus 4 s per GB of the
previous transcript. A tab that waits prints `waiting N s`.

### 5. Session defaults

The installer asks for a default effort level and ultracode. The wrapper adds `--effort <level>` and
`--settings <file with {"ultracode": true}>` to the launches it makes, unless you already passed `--effort` or
`--settings`.
