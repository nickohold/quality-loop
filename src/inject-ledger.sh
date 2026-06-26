#!/bin/bash
# UserPromptSubmit: re-inject the decision ledger while a task is active for this cwd.
QL="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null); [ -z "$CWD" ] && CWD="$PWD"
[ -f "$QL/state/active-$(printf '%s' "$CWD" | shasum -a 1 | cut -c1-16)" ] || exit 0

LEDGER=$(cd "$QL" && python3 decision_ledger.py show "$CWD" 2>/dev/null)
[ -z "$LEDGER" ] && exit 0
echo "<system-reminder>"
echo "Binding decisions for this task — do NOT reopen, re-architect, or contradict:"
echo "$LEDGER"
echo "</system-reminder>"
exit 0
