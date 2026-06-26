#!/bin/bash
# Stop hook: opt-in (marker set by /handout), fires once per turn-sequence.
QL="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INPUT=$(cat)

[ "$(echo "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null)" = "true" ] && exit 0

CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null); [ -z "$CWD" ] && CWD="$PWD"
TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
MARKER="$QL/state/active-$(printf '%s' "$CWD" | shasum -a 1 | cut -c1-16)"

[ -f "$MARKER" ] || exit 0
[ -n "$(find "$MARKER" -mmin +180 2>/dev/null)" ] && exit 0   # stale marker, don't nag

RESULT=$(cd "$QL" && python3 verify.py "$TRANSCRIPT" "$CWD" 2>/dev/null)
[ -z "$RESULT" ] && exit 0
mkdir -p "$QL/logs"
echo "$RESULT" | jq -r '.warnings[]? | "WARN: " + .' >> "$QL/logs/warnings.log" 2>/dev/null

if [ "$(echo "$RESULT" | jq -r '.pass' 2>/dev/null)" = "false" ]; then
  REASON=$(echo "$RESULT" | jq -r '"QUALITY GATE BLOCKED this turn. Fix each item, then finish:\n" + (.blocks | to_entries | map("  \(.key+1). \(.value)") | join("\n")) + (if (.warnings|length)>0 then "\nWarnings:\n" + (.warnings | map("  - "+.) | join("\n")) else "" end)')
  echo "{\"decision\":\"block\",\"reason\":$(echo "$REASON" | jq -Rs .)}"
fi
exit 0
