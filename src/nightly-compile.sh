#!/bin/bash
# Nightly flywheel: gather the day's operator messages, then let a headless
# `claude -p` understand them and propose rule deltas (it only proposes).
# Enable:  crontab -e   then add:
#   PATH=/usr/local/bin:/usr/bin:/bin:$HOME/.claude/local
#   0 7 * * *  /bin/bash ~/.claude/skills/handout/nightly-compile.sh
QL="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$QL" || exit 1
mkdir -p logs state
DAY=$(date '+%Y-%m-%d')
OUT="logs/proposals-$DAY.md"

CORPUS=$(python3 nightly-compile.py 2>>logs/compile-errors.log)
if [ ! -s "$CORPUS" ]; then
  printf '# Friction proposals — %s\n\nNo correction signals in the last 24h.\n' "$DAY" > "$OUT"
  exit 0
fi

CLAUDE="$(command -v claude || echo "$HOME/.claude/local/claude")"
if [ ! -x "$CLAUDE" ] && ! command -v claude >/dev/null 2>&1; then
  echo "$(date '+%F %T') ERROR: 'claude' CLI not found" >> logs/compile.log
  exit 1
fi

read -r -d '' PROMPT <<'EOF'
You are reviewing ONE day of an operator's own messages to an AI coding agent, to improve a GENERAL, cross-project quality-gate system. The corpus is on stdin; each block is something the OPERATOR typed.

Your bar is HIGH and your default output is NOTHING. Most days produce no proposal — "No systemic proposals today." is a correct and preferred result. Do NOT manufacture suggestions to seem useful; do NOT force one per theme.

Propose a change ONLY if it is ALL of:
- MACRO & AGNOSTIC — it improves the system for ANY project or user. NOT a one-off ban on a specific library, variable name, file, or this repo's stack. (Case-specific bans are the operator's to add by hand — and they're often wrong later: a dependency killed in frustration today may be required tomorrow. Do not propose them.)
- NEW or IMPROVING — it adds a capability the gates lack, or sharpens an existing check. Not a restatement of an in-the-moment frustration.
- HIGH-CONFIDENCE — it will not over-fire on innocent work.

For anything that clears the bar: state the systemic pattern (with 1-2 quotes), why it generalises beyond a single incident, and the concrete improvement — a new/changed gate, a general claim phrase, or an agnostic kill-list KIND (not a specific value). Skip everything project-specific.

Output a short dated markdown note, or just the one line saying nothing cleared the bar. No preamble. Do NOT edit files.
EOF

{
  echo "# Friction proposals — $DAY"
  echo
  cat "$CORPUS" | "$CLAUDE" -p "$PROMPT" 2>>logs/compile-errors.log
} > "$OUT"
echo "$(date '+%F %T') wrote $OUT" >> logs/compile.log
