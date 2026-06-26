#!/bin/bash
# PreToolUse(Bash) guard: NEVER merge / push to main without explicit say-so.
# Blocks git merge, push to main/master, force-push, and gh pr merge UNLESS a
# one-shot approval token exists (written by the /approve-merge command).
# This is GLOBAL on purpose: it is a hard, high-blast-radius red line.
QL="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$CMD" ] && exit 0

TOKEN="$QL/state/merge-approved"

is_merge() {
  echo "$1" | grep -Eq 'git[[:space:]]+merge|gh[[:space:]]+pr[[:space:]]+merge|git[[:space:]]+push[[:space:]].*(origin[[:space:]]+)?(main|master)|git[[:space:]]+push[[:space:]]+--force|git[[:space:]]+push[[:space:]]+-f'
}

if is_merge "$CMD"; then
  if [ -f "$TOKEN" ]; then
    rm -f "$TOKEN"   # one-shot: consume the approval
    exit 0
  fi
  echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"BLOCKED: merge / push-to-main requires explicit approval. Ask the user; if they say yes they run /approve-merge (or: touch <quality-loop>/state/merge-approved) and you retry. Never merge on your own initiative."}}'
  exit 0
fi
exit 0
