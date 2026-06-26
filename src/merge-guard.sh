#!/bin/bash
# PreToolUse(Bash): block merge / push-to-main / gh pr merge unless a one-shot token exists.
QL="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$CMD" ] && exit 0
TOKEN="$QL/state/merge-approved"

# Parse the leading git/gh subcommand of each segment, not the whole string.
if python3 "$QL/merge_match.py" "$CMD"; then
  if [ -f "$TOKEN" ]; then
    rm -f "$TOKEN"   # one-shot
    exit 0
  fi
  echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"BLOCKED: merge / push-to-main requires explicit approval. If the user says yes they run /approve-merge, then retry. Never merge on your own initiative."}}'
fi
exit 0
