# Troubleshooting

Start with the doctor: `powershell -NoProfile -File .\doctor.ps1` on Windows, `bash ./doctor.sh` on macOS and Linux.
Every `FAIL` line names the problem. This page explains each one.

## A tab still opened a blank session

1. **The tab had no mapped session.** The doctor lists tabs "without a session yet". A tab is mapped on its first
   prompt after the install. The installer also maps the tabs that were open during the install, if their session
   already had a prompt.
2. **The shell did not load the profile.** Open the tab, exit Claude and run `Get-Command claude`. It should say
   `Function`. If it says `Application`:
   - check the execution policy (next section);
   - check that the tab runs PowerShell;
   - check that the profile file the doctor names contains the line with `msrf-profile.ps1`.
   - On macOS and Linux, run `type claude`; it should say `claude is a function`.
3. **The transcript is gone.** Claude Code deletes transcripts older than `cleanupPeriodDays` (30 by default). The
   tab then opens a new session.
4. **Look at the log.** `msrf.log`, next to the tab map, has one line per hook call:
   - `recorded`: the map was updated;
   - `outside-tab`: a Claude that was not typed in a tab, such as `claude -p` from a script;
   - `ignored`: a SessionStart with source `startup`;
   - `error`: an unexpected failure, with its message.

## Windows

| Problem | Cause | Fix |
|---|---|---|
| `execution policy Restricted/AllSigned` | New PowerShell windows refuse scripts, profile included | `install.ps1 -SetExecutionPolicy` (sets `RemoteSigned` for your user only) |
| `Group Policy sets the execution policy` | Policy set by your organization | Ask your administrator; the fix cannot load otherwise |
| `ConstrainedLanguage` | AppLocker or WDAC | Same as above |
| Scripts blocked after downloading the ZIP | Mark of the Web plus `RemoteSigned` | The installer runs `Unblock-File` on the installed copy; run the installer with `-ExecutionPolicy Bypass` as shown in the README |
| Profile not loaded although the line is there | Documents redirected (OneDrive) and an old profile somewhere else | The installer uses the path Windows reports; the doctor prints it |
| Tab uses cmd or Git Bash | Only PowerShell profiles carry the wrapper | Set the tab or Maestri's default shell to PowerShell |
| `Native helper not compiled` warning | `Add-Type` could not compile (antivirus or policy) | Works anyway, with a slower hook (about 0.6 s instead of 0.3 s per prompt) |
| Another claude wrapper found | An older fix or alias in the profile | Keep one; two wrappers each think they own `claude` |

## macOS and Linux

| Problem | Cause | Fix |
|---|---|---|
| `claude` not a function in a tab | The tab runs fish, nushell or another shell | Use zsh or bash in Maestri |
| `python3 is needed` (Linux) | `settings.json` is edited with python3 | Install python3 |
| macOS without python3 | Normal on a fresh Mac | The installer uses JavaScript for Automation (`osascript`) instead |
| Seeding found nothing on macOS | `ps eww` does not show the environment of processes it cannot inspect | Send one message in each tab; the hooks map them |

## Claude Code

| Problem | Cause | Fix |
|---|---|---|
| Hooks never run | `disableAllHooks` is true, or a managed policy blocks user hooks | The doctor reports the first; ask your administrator about the second |
| `settings.json is not valid JSON` | The file was edited by hand | Fix the syntax; the installer did not change anything |
| Hooks installed but nothing recorded | Sessions started before the install may keep the hook set they started with | They load the hooks after their next restart; the install-time seed covers the gap |

## Removing it

Run `uninstall.ps1` (add `-RemoveData` to delete the tab map) or `bash ./uninstall.sh` (add `--remove-data`). It
backs up `settings.json`, removes only this fix's hook entries and profile line, and deletes the installed scripts.
