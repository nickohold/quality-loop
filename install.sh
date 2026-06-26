#!/usr/bin/env bash
# Quality Loop installer.
# Copies the engine into ~/.claude/quality-loop, installs the /handout skill and
# /approve-merge command, and idempotently wires the three hooks into settings.json.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"
QL="$CLAUDE_HOME/quality-loop"

echo "Installing Quality Loop into $CLAUDE_HOME"

command -v jq >/dev/null 2>&1 || { echo "ERROR: jq is required (brew install jq / apt-get install jq)"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "ERROR: python3 is required"; exit 1; }

# 1. Engine
mkdir -p "$QL"/{config,state,decisions,logs}
cp "$REPO"/src/*.py "$REPO"/src/*.sh "$QL"/
cp "$REPO"/src/config/bans.example.txt "$QL"/config/
[ -f "$QL/config/bans.txt" ] || cp "$REPO"/src/config/bans.example.txt "$QL/config/bans.txt"
chmod +x "$QL"/*.sh "$QL"/*.py

# 2. Skill + command
mkdir -p "$CLAUDE_HOME/skills/handout" "$CLAUDE_HOME/commands"
cp "$REPO"/skill/handout/SKILL.md "$CLAUDE_HOME/skills/handout/"
cp "$REPO"/commands/approve-merge.md "$CLAUDE_HOME/commands/"

# 3. Wire hooks into settings.json (idempotent)
SETTINGS="$CLAUDE_HOME/settings.json"
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
python3 - "$SETTINGS" <<'PY'
import json, sys
p = sys.argv[1]
with open(p) as f:
    s = json.load(f)
h = s.setdefault("hooks", {})

def has(arr, needle):
    return any(needle in (hk.get("command","")) for grp in arr for hk in grp.get("hooks", []))

def ensure(event, matcher, command, timeout):
    arr = h.setdefault(event, [])
    if has(arr, command):
        return False
    entry = {"hooks": [{"type": "command", "command": command, "timeout": timeout}]}
    if matcher is not None:
        entry["matcher"] = matcher
    arr.append(entry)
    return True

changed = False
changed |= ensure("PreToolUse", "Bash", "bash ~/.claude/quality-loop/merge-guard.sh", 5)
changed |= ensure("UserPromptSubmit", None, "bash ~/.claude/quality-loop/inject-ledger.sh", 5)
changed |= ensure("Stop", None, "bash ~/.claude/quality-loop/gate-stop.sh", 20)

with open(p, "w") as f:
    json.dump(s, f, indent=2)
print("settings.json updated" if changed else "settings.json already wired")
PY

echo
echo "Done. Restart Claude Code, then run /handout to put a task through the loop."
echo "Edit your kill-list at: $QL/config/bans.txt"
echo "Enable the nightly compiler (optional): crontab -e  ->  0 7 * * *  /bin/bash $QL/nightly-compile.sh"
