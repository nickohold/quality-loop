#!/usr/bin/env bash
# Quality Loop installer.
# Installs the whole self-contained skill into ~/.claude/skills/handout (engine,
# gates, verifier, config, state — all beside SKILL.md), plus the worker agent and
# the /approve-merge command, and idempotently wires the hooks into settings.json.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"
QL="$CLAUDE_HOME/skills/handout"
OLD="$CLAUDE_HOME/quality-loop"   # pre-1.x location, migrated below

echo "Installing Quality Loop into $QL"

command -v jq >/dev/null 2>&1 || { echo "ERROR: jq is required (brew install jq / apt-get install jq)"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "ERROR: python3 is required"; exit 1; }

# 1. Engine + skill (all in the skill folder)
mkdir -p "$QL"/{config,state,decisions,logs}
cp "$REPO"/src/*.py "$REPO"/src/*.sh "$QL"/
cp "$REPO"/skill/handout/SKILL.md "$QL"/
cp "$REPO"/src/config/bans.example.txt "$QL"/config/

# Migrate a previous ~/.claude/quality-loop install: keep the user's data.
if [ -d "$OLD" ]; then
  [ -f "$OLD/config/bans.txt" ] && cp -n "$OLD/config/bans.txt" "$QL/config/bans.txt" 2>/dev/null || true
  cp -n "$OLD"/decisions/* "$QL/decisions/" 2>/dev/null || true
  cp -n "$OLD"/logs/*       "$QL/logs/"      2>/dev/null || true
fi
# Seed bans.txt from the example only if the user has none yet.
[ -f "$QL/config/bans.txt" ] || cp "$REPO"/src/config/bans.example.txt "$QL/config/bans.txt"
chmod +x "$QL"/*.sh "$QL"/*.py

# 2. Agents (builder + adversarial verifier) + command
mkdir -p "$CLAUDE_HOME/commands" "$CLAUDE_HOME/agents"
cp "$REPO"/commands/approve-merge.md "$CLAUDE_HOME/commands/"
cp "$REPO"/agents/handout-worker.md "$CLAUDE_HOME/agents/"
cp "$REPO"/agents/handout-verifier.md "$CLAUDE_HOME/agents/"

# 2b. The dev-loop line: /dev-loop orchestrator + the skills it drives
for s in dev-loop team-review feature-dev-team; do
  mkdir -p "$CLAUDE_HOME/skills/$s"
  cp "$REPO"/skill/"$s"/* "$CLAUDE_HOME/skills/$s/"
done

# 3. Wire hooks into settings.json (idempotent; strips any old quality-loop hooks)
SETTINGS="$CLAUDE_HOME/settings.json"
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
python3 - "$SETTINGS" <<'PY'
import json, sys
p = sys.argv[1]
with open(p) as f:
    s = json.load(f)
h = s.setdefault("hooks", {})

# Drop any hooks pointing at the old quality-loop location.
for event, arr in list(h.items()):
    kept = []
    for grp in arr:
        grp["hooks"] = [hk for hk in grp.get("hooks", []) if "quality-loop/" not in hk.get("command", "")]
        if grp["hooks"]:
            kept.append(grp)
    h[event] = kept

def has(arr, needle):
    return any(needle in hk.get("command", "") for grp in arr for hk in grp.get("hooks", []))

def ensure(event, matcher, command, timeout):
    arr = h.setdefault(event, [])
    if has(arr, command):
        return False
    entry = {"hooks": [{"type": "command", "command": command, "timeout": timeout}]}
    if matcher is not None:
        entry["matcher"] = matcher
    arr.append(entry)
    return True

ensure("PreToolUse", "Bash", "bash ~/.claude/skills/handout/merge-guard.sh", 5)
ensure("UserPromptSubmit", None, "bash ~/.claude/skills/handout/inject-ledger.sh", 5)
ensure("Stop", None, "bash ~/.claude/skills/handout/gate-stop.sh", 20)
ensure("SubagentStop", None, "bash ~/.claude/skills/handout/gate-subagent-stop.sh", 20)

with open(p, "w") as f:
    json.dump(s, f, indent=2)
print("settings.json wired")
PY

# 4. Retire the old location once its data is migrated.
[ -d "$OLD" ] && rm -rf "$OLD" && echo "migrated and removed old $OLD"

echo
echo "Done. Restart Claude Code, then run /handout to put a task through the loop."
echo "Edit your kill-list at: $QL/config/bans.txt"
echo "Enable the nightly compiler (optional): crontab -e  ->  0 7 * * *  /bin/bash $QL/nightly-compile.sh"
