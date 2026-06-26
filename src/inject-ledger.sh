#!/bin/bash
# UserPromptSubmit hook: re-inject the binding decision ledger every turn,
# but ONLY while a handed-out task is active for this cwd (opt-in, no global noise).
QL="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
[ -z "$CWD" ] && CWD="$PWD"
KEY=$(printf '%s' "$CWD" | shasum -a 1 | cut -c1-16)
[ -f "$QL/state/active-$KEY" ] || exit 0

LEDGER=$(cd "$QL" && python3 decision_ledger.py show "$CWD" 2>/dev/null)
[ -z "$LEDGER" ] && exit 0

echo "<system-reminder>"
echo "Binding decisions already made for this task — do NOT reopen, re-architect, or contradict:"
echo "$LEDGER"
echo "</system-reminder>"
exit 0
