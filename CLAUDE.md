# maestri-session-restart-fix: install protocol for agents

Someone sent you this repository and asked you to install it (or to check or remove it). You are the operator:
do every step yourself. The user only answers two questions and restarts Maestri at the end.

## 1. Before anything
- If the repository is not on disk yet, clone it into a stable folder (for example `~/maestri-session-restart-fix`).
- Find the OS. Windows: you use `install.ps1`, `doctor.ps1`, `uninstall.ps1`. macOS or Linux: you use `install.sh`,
  `doctor.sh`, `uninstall.sh`.
- Do not restart, close or kill Maestri, Claude Code or any terminal process. If you run inside a Maestri tab,
  restarting Maestri ends your own conversation; it comes back on its own after the install.

## 2. Ask once, in one message
Ask these two questions together and wait for the answer. Skip a question the user already answered.
1. Default effort for the sessions the fix opens: `default` (keep Claude Code's own default), `low`, `medium`, `high`,
   `xhigh` or `max`.
2. Ultracode `on` or `off`. One line of context: on means every session the fix opens may orchestrate multi-agent
   workflows, which costs noticeably more tokens.

## 3. Install
Windows:
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -Effort <answer> -Ultracode <on|off>
```
macOS or Linux:
```bash
bash ./install.sh --effort <answer> --ultracode <on|off>
```
The flags avoid the interactive prompts. `-ExecutionPolicy Bypass` applies to the installer process only.

## 4. When the installer stops (it prints `FAIL` and a `fix:` line)
| FAIL says | Do this |
|---|---|
| new PowerShell windows use the execution policy Restricted/AllSigned/Undefined | Explain in one line that the profile cannot load under that policy. Ask whether to set `RemoteSigned` for their user only. If yes, rerun with `-SetExecutionPolicy`. |
| Group Policy sets the execution policy | Stop. Tell the user that their administrator controls it. Nothing else can make the fix load. |
| ConstrainedLanguage mode | Stop and tell the user. AppLocker or WDAC blocks the fix. |
| Claude Code was not found on PATH | Ask the user to install Claude Code or to open a new terminal. If `claude` works in Maestri but not for you, find where `claude` lives (`where claude` / `type -a claude`) and tell the user. |
| settings.json is not valid JSON | Show the parse error. Ask before editing it. The installer has not changed anything. |
| python3 is needed on Linux | Ask the user to install python3 (for example `sudo apt install python3`), then rerun. |

The installer only prints `WARN` for things that do not block it, such as a tab using an unsupported shell. Relay
those warnings in one line each.

## 5. Verify
Run the doctor (`powershell -NoProfile -File .\doctor.ps1` or `bash ./doctor.sh`) and read its output.
- Every `FAIL` must be fixed or explained before the restart.
- Tabs listed without a session are tabs whose open session has no prompt yet. They map themselves on their next
  prompt; or the user can send any message in each of them now.
- Another claude wrapper in the profile (`WARN Another claude wrapper ...`): ask the user which one to keep. Two
  wrappers fight each other.

## 6. Hand off
Tell the user, in at most four lines:
1. Installed, with the session defaults they chose.
2. Quit Maestri and open it again. The tabs reopen one after another, and some show `waiting N s` first.
3. After it reopens, ask you (or any agent) to run the doctor again. The line `Open Claude sessions: N; open in the
   tab the fix expects: M` should show M equal to the number of mapped tabs.
4. `claude --new-session` opens a fresh session in a tab.

## Rules
- Never edit Maestri's files (`~/.maestri`). The fix only reads them.
- Never print or copy the content of transcripts, `settings.json` secrets, or the tab map into the chat.
- Do not commit anything in this repository on the user's machine.
- To remove the fix, run the uninstaller. Its `-RemoveData` or `--remove-data` option also deletes the tab map.
