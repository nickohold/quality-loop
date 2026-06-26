#!/bin/bash
# Stop hook for the quality loop.
# TEETH ARE OPT-IN: only hard-blocks when the loop is active for this cwd
# (marker set by the /handout skill). Outside the loop it stays silent.
# Fires at most once per turn-sequence (stop_hook_active guard) to avoid nagging.
QL="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

INPUT=$(cat)

STOP_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null)
[ "$STOP_ACTIVE" = "true" ] && exit 0

CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
[ -z "$CWD" ] && CWD="$PWD"
TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)

# cwd key must match qllib.cwd_key (sha1 of cwd, first 16 hex chars)
KEY=$(printf '%s' "$CWD" | shasum -a 1 | cut -c1-16)
MARKER="$QL/state/active-$KEY"

# Not in a handed-out task -> do nothing (no global nag).
[ -f "$MARKER" ] || exit 0
# Stale marker (loop forgot to disarm) -> ignore so it can't nag forever.
[ -n "$(find "$MARKER" -mmin +180 2>/dev/null)" ] && exit 0

RESULT=$(cd "$QL" && python3 verify.py "$TRANSCRIPT" "$CWD" 2>/dev/null)
[ -z "$RESULT" ] && exit 0

PASS=$(echo "$RESULT" | jq -r '.pass' 2>/dev/null)
mkdir -p "$QL/logs"
echo "$RESULT" | jq -r '.warnings[]? | "WARN: " + .' >> "$QL/logs/warnings.log" 2>/dev/null

if [ "$PASS" = "false" ]; then
  REASON=$(echo "$RESULT" | jq -r '"QUALITY GATE BLOCKED this turn. Fix each item, then finish:\n" + (.blocks | to_entries | map("  \(.key+1). \(.value)") | join("\n")) + (if (.warnings|length)>0 then "\nWarnings (not blocking):\n" + (.warnings | map("  - "+.) | join("\n")) else "" end)')
  echo "{\"decision\":\"block\",\"reason\":$(echo "$REASON" | jq -Rs .)}"
  exit 0
fi
exit 0
