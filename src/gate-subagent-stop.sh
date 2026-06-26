#!/bin/bash
# SubagentStop hook: verify the WORKER's output when it finishes.
# Teeth are opt-in (marker for this cwd, set by /handout) and self-expiring.
# On failure: print the reason to stderr and exit 2 — Claude Code re-prompts the
# subagent to fix. An attempt cap prevents an unsatisfiable infinite loop.
QL="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAX_ATTEMPTS=3
TTL_MIN=180

INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
[ -z "$CWD" ] && CWD="$PWD"
TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
AGENT=$(echo "$INPUT" | jq -r '.agent_id // "anon"' 2>/dev/null)

KEY=$(printf '%s' "$CWD" | shasum -a 1 | cut -c1-16)
MARKER="$QL/state/active-$KEY"

# Not in a handed-out task -> do nothing.
[ -f "$MARKER" ] || exit 0
# Stale marker (loop forgot to disarm) -> ignore, don't nag.
[ -n "$(find "$MARKER" -mmin +$TTL_MIN 2>/dev/null)" ] && exit 0

CNT="$QL/state/attempts-$AGENT"
N=$(cat "$CNT" 2>/dev/null || echo 0)

RESULT=$(cd "$QL" && python3 verify.py "$TRANSCRIPT" "$CWD" 2>/dev/null)
[ -z "$RESULT" ] && exit 0
PASS=$(echo "$RESULT" | jq -r '.pass' 2>/dev/null)
mkdir -p "$QL/logs"
echo "$RESULT" | jq -r '.warnings[]? | "WARN(worker): " + .' >> "$QL/logs/warnings.log" 2>/dev/null

if [ "$PASS" = "false" ]; then
  if [ "$N" -ge "$MAX_ATTEMPTS" ]; then
    echo "$(date '+%F %T') worker gate gave up after $N attempts ($AGENT)" >> "$QL/logs/warnings.log"
    rm -f "$CNT"; exit 0
  fi
  echo $((N+1)) > "$CNT"
  echo "WORKER QUALITY GATE FAILED — fix each item before finishing:" >&2
  echo "$RESULT" | jq -r '.blocks | to_entries[] | "  \(.key+1). \(.value)"' >&2
  exit 2
fi
rm -f "$CNT"
exit 0
