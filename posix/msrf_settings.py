"""Adds or removes the fix's hooks in a Claude Code settings.json (Linux, or macOS with python3)."""
import json
import os
import sys

MARKER = "msrf-record-session.sh"


def update(path, command, remove):
    settings = {}
    if os.path.exists(path):
        with open(path, encoding="utf-8") as handle:
            text = handle.read()
        if text.strip():
            settings = json.loads(text)
    hooks = settings.setdefault("hooks", {})
    for event in ("UserPromptSubmit", "SessionStart"):
        kept = [
            entry for entry in hooks.get(event, [])
            if not any(MARKER in str(hook.get("command", "")) for hook in entry.get("hooks", []))
        ]
        if not remove:
            entry = {"hooks": [{"type": "command", "command": command, "timeout": 15}]}
            if event == "SessionStart":
                entry = {"matcher": "resume|clear|compact", "hooks": entry["hooks"]}
            kept.append(entry)
        if kept:
            hooks[event] = kept
        else:
            hooks.pop(event, None)
    if not hooks:
        settings.pop("hooks", None)
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    with open(path, "w", encoding="utf-8") as handle:
        json.dump(settings, handle, indent=2, ensure_ascii=False)
        handle.write("\n")


if __name__ == "__main__":
    update(sys.argv[1], sys.argv[2], len(sys.argv) > 3 and sys.argv[3] == "--remove")
