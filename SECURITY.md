# Security

## What the fix touches

| What | Where | When |
|---|---|---|
| Its own scripts, tab map, log, queue and config | `%LOCALAPPDATA%\maestri-session-restart-fix` or `~/.local/share/maestri-session-restart-fix` | install, every prompt, every automatic launch |
| Two hook entries | Claude Code `settings.json` (backed up before each change) | install, uninstall |
| One line | PowerShell profiles, or `~/.zshrc` and `~/.bashrc` | install, uninstall |
| Execution policy `RemoteSigned`, current user only | Windows | only with `-SetExecutionPolicy` |

It reads, and never writes:

- Claude Code transcripts: only the file name, the date and whether the first lines contain a prompt;
- `~/.claude/sessions/*.json`, to know which sessions are open;
- Maestri's workspace files, only for the doctor's tab count.

## Reading other processes

To map the tabs that are already open, install and doctor read one environment variable, `MAESTRI_TERMINAL_ID`, from
the user's own Claude Code processes:

- Windows: through the process environment block, with `PROCESS_QUERY_INFORMATION` and `PROCESS_VM_READ` on processes
  of the same user;
- Linux: from `/proc/<pid>/environ`;
- macOS: through `ps eww`.

No other variable is kept, and nothing is sent anywhere.

## No network

The fix makes no network calls.

## Reporting

Open a private security advisory on GitHub (Security tab, "Report a vulnerability").
