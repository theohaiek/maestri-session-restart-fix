# Changelog

All notable changes to this project are documented here. Versions follow [Semantic Versioning](https://semver.org).

## 1.0.0 - 2026-10-26

First public release, distilled from a fix used on a real 44-tab Maestri workspace on Windows.

- Hooks `UserPromptSubmit` and `SessionStart` (resume, clear, compact) keep a map of Maestri tab to Claude Code
  session. A hook started by a nested `claude -p` is ignored.
- A `claude` wrapper, active only inside Maestri tabs, reopens each tab's own session and repairs the ids Maestri
  passes: cut, blank, stale, or belonging to another tab.
- Tabs that reopen automatically wait in a queue sized by transcript size.
- Session defaults: optional effort level and ultracode, asked at install.
- Install-time seed from the environment of the Claude processes that are open.
- Windows installer, doctor and uninstaller: execution policy, Mark of the Web, OneDrive Documents, PowerShell 5.1
  and 7, npm installs, a native helper with a WMI fallback.
- macOS and Linux installer, doctor and uninstaller: bash 3.2, zsh and bash, python3 or JavaScript for Automation to
  edit the settings.
- Agent install protocol in `CLAUDE.md` and `AGENTS.md`.
