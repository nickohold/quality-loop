#!/usr/bin/env bash
# Quality Loop uninstaller. Removes the hooks from settings.json and deletes the
# engine, skill, and command. Leaves your settings.json otherwise untouched.
set -euo pipefail

CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"
QL="$CLAUDE_HOME/skills/handout"
SETTINGS="$CLAUDE_HOME/settings.json"

if [ -f "$SETTINGS" ]; then
  python3 - "$SETTINGS" <<'PY'
import json, sys
p = sys.argv[1]
with open(p) as f:
    s = json.load(f)
h = s.get("hooks", {})
NEEDLES = ("skills/handout/merge-guard.sh", "skills/handout/inject-ledger.sh", "skills/handout/gate-stop.sh", "skills/handout/gate-subagent-stop.sh",
           "quality-loop/merge-guard.sh", "quality-loop/inject-ledger.sh", "quality-loop/gate-stop.sh", "quality-loop/gate-subagent-stop.sh")
for event, arr in list(h.items()):
    kept = []
    for grp in arr:
        grp["hooks"] = [hk for hk in grp.get("hooks", []) if not any(n in hk.get("command","") for n in NEEDLES)]
        if grp["hooks"]:
            kept.append(grp)
    h[event] = kept
with open(p, "w") as f:
    json.dump(s, f, indent=2)
print("hooks removed from settings.json")
PY
fi

rm -rf "$QL"
rm -rf "$CLAUDE_HOME/quality-loop"   # legacy location, if present
rm -f "$CLAUDE_HOME/commands/approve-merge.md"
rm -f "$CLAUDE_HOME/agents/handout-worker.md"
echo "Quality Loop uninstalled. (Your bans.txt and logs under $QL were removed too.)"
