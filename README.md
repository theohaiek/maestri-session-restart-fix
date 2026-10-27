<h1 align="center"><img src="assets/logo.png" alt="maestri-session-restart-fix" width="200"><br>maestri-session-restart-fix</h1>

<p align="center"><strong>Every Maestri tab reopens on its own Claude Code session, every time Maestri restarts.</strong></p>

<p align="center">
<a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-green.svg" alt="MIT License"></a>
<img src="https://img.shields.io/badge/version-1.0.0-blue" alt="Version 1.0.0">
<a href="https://github.com/theohaiek/maestri-session-restart-fix/actions/workflows/ci.yml"><img src="https://github.com/theohaiek/maestri-session-restart-fix/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
<img src="https://img.shields.io/badge/Windows-tested-0078D4" alt="Windows tested">
<img src="https://img.shields.io/badge/macOS%20%7C%20Linux-CI%20tested-lightgrey" alt="macOS and Linux CI tested">
</p>

<p align="center"><a href="README.pt-BR.md">Leia em portugu&ecirc;s</a></p>

## The problem

You run Claude Code in many Maestri tabs. Maestri closes (update, crash, reboot, or just
quitting) and reopens. Some tabs come back on their session, most come back as a **blank new session**, and a few come
back on **the wrong session** or fail with `No conversation found`. Then you hunt session ids by hand, tab by tab.

Why it happens (details in [docs/how-it-works.md](docs/how-it-works.md)): Maestri only resumes a tab when it has a
`claude --resume <id>` for it. It gets that line by reading the text Claude prints when it exits, and only on a clean
quit. After a crash or an update it falls back to the command it used the last time it opened that tab. So it fails
whenever:

- the tab was opened with plain `claude`;
- Maestri did not quit cleanly;
- the line wrapped in a narrow tab and the id came back cut (`910`, `b454cb40-`);
- the screen showed another session's id.

Measured on one machine: 39 of 44 tabs came back blank after a restart. With the fix, 41 of 41 came back on the right
session (the other 3 never had a session).

## Quick start

**Let your AI agent do it.** Open Claude Code (or any coding agent) and say:

```text
Install https://github.com/theohaiek/maestri-session-restart-fix in my Maestri
```

The agent follows [CLAUDE.md](CLAUDE.md). It asks you two questions (default effort level and ultracode), runs the
checks, installs, maps the sessions that are open right now and tells you when to restart Maestri.

**Or by hand.** Windows (PowerShell):

```powershell
git clone https://github.com/theohaiek/maestri-session-restart-fix
cd maestri-session-restart-fix
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

macOS or Linux:

```bash
git clone https://github.com/theohaiek/maestri-session-restart-fix
cd maestri-session-restart-fix
bash ./install.sh
```

Then quit and reopen Maestri once. Run `doctor.ps1` (Windows) or `./doctor.sh` (macOS, Linux) whenever you want
to see the state.

## What it does

| Piece | What it does |
|---|---|
| Hook (`UserPromptSubmit` and `SessionStart`) | Each time a tab sends a prompt, or resumes, clears or compacts, it writes "tab X runs session Y". A blank session never overwrites the real one, because a blank session has no prompt. |
| `claude` wrapper | Defined in your PowerShell profile (or `~/.zshrc` and `~/.bashrc`), and active only inside Maestri tabs. When Maestri types `claude` or a broken `claude --resume`, the wrapper reopens the tab's own session. |
| Seed at install | Reads `MAESTRI_TERMINAL_ID` from the Claude processes that are open right now, so your first restart already works. |
| Queue | Tabs reopen one after another, waiting 3 s plus 4 s per GB of transcript, so 40 large sessions do not exhaust your RAM at once. |
| Session defaults | Optional effort level and ultracode for every session the fix opens. Flags you type yourself always win. |

How the wrapper decides:

- **The id Maestri passes is cut, blank, or owned by another tab:** the wrapper reopens the tab's session.
- **The id is a newer session with prompts that no other tab owns:** the wrapper uses that id.
- **You typed `claude --resume X` yourself:** the wrapper honours X.
- **The session is already open in another process:** the wrapper never reopens it. A second process would write to the same transcript.
- **`-p`, `--continue`, `--help` and `--version`:** these pass through untouched.
- **A new session in a tab:** run `claude --new-session`.

## Incompatibilities it handles

| Situation | What happens |
|---|---|
| Execution policy `Restricted` or `AllSigned` (Windows default on some machines) | The installer stops and says so. Rerun it with `-SetExecutionPolicy` to set `RemoteSigned` for your user. If Group Policy sets the policy, it tells you to ask your administrator. |
| Files downloaded as ZIP (Mark of the Web) | The installed scripts are unblocked. |
| Documents folder redirected to OneDrive | The profile path comes from Windows, not from a guess. |
| PowerShell 7 instead of Windows PowerShell | Both profiles are set up. Maestri picks `pwsh` when it is installed. |
| Claude Code installed with npm (`claude.cmd`, `node`) instead of the native installer | Supported in the process checks and in the wrapper. |
| `CLAUDE_CONFIG_DIR` or `MAESTRI_DATA_DIR` set | Both are respected. |
| `claude -p` started from inside a tab (scripts, agents) | It does not overwrite the tab's session: the hook only records a Claude typed in the tab's own shell. |
| A tab whose shell is cmd, fish or nushell | The doctor flags it. Use PowerShell, zsh or bash. |
| macOS without python3 | `settings.json` is edited with JavaScript for Automation. |
| Transcripts deleted by Claude Code's cleanup (30 days by default) | The tab opens a new session instead of failing. |
| Existing hooks and settings | They are kept. `settings.json` is backed up before every change. |

The full list is in [docs/troubleshooting.md](docs/troubleshooting.md).

## Requirements

- Maestri with Claude Code tabs. Tested with Maestri 0.27 and Claude Code 2.1.311.
- Windows 10 or 11 with Windows PowerShell 5.1 or PowerShell 7.
- macOS or Linux with bash 3.2 or newer, and tabs running zsh or bash.

## Uninstall

```powershell
powershell -NoProfile -File .\uninstall.ps1            # add -RemoveData to delete the session map
```

```bash
bash ./uninstall.sh                                    # add --remove-data to delete the session map
```

## Privacy and safety

- Everything stays on your machine. There are no network calls.
- The fix writes:
  - its scripts and the tab map (`%LOCALAPPDATA%\maestri-session-restart-fix` or `~/.local/share/maestri-session-restart-fix`);
  - two hook entries in your Claude Code `settings.json`, backed up first;
  - one line in your shell profile.
- Reading other processes' environment happens only for your own Claude processes, during install and doctor, and
  only to get `MAESTRI_TERMINAL_ID`. See [SECURITY.md](SECURITY.md).
- The fix never touches Maestri's files.

## Status

Version 1.0.0. The Windows path was used on a real 44-tab Maestri workspace. The macOS and Linux path runs the same
logic and is tested in CI on macOS and Ubuntu, but it has not yet been run on a real Maestri install on a Mac. Reports
are welcome: open an issue with the output of the doctor.

## License

[MIT](LICENSE)
