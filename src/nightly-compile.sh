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
You are auditing ONE day of an operator's own messages to an AI coding agent, to make a mechanical quality-gate system smarter. The corpus is on stdin; each block is something the OPERATOR typed (corrections, frustration, redirection), tagged with timestamp and repo.

Use judgment, do not keyword-match:
1. Identify recurring friction, INCLUDING novel kinds a regex would miss. Infer what the agent did that the operator is reacting to.
2. Cluster into a few themes, most impactful first.
3. For each theme propose ONE concrete, machine-enforceable delta to approve — prefer a kill-list line in EXACTLY this format:
       kind::regex::message
   (kind: added_comment | type_in_class | concept | dependency | generic) — or a new claim phrase, or a decision-ledger/knowledge note when no line rule fits.
4. Be conservative: only rules that won't over-fire on innocent code.

Output a dated markdown proposal. Per theme: a one-line title, 1-2 verbatim quotes, why it recurs, the exact delta to paste. No preamble. Do NOT edit files.
EOF

{
  echo "# Friction proposals — $DAY"
  echo
  cat "$CORPUS" | "$CLAUDE" -p "$PROMPT" 2>>logs/compile-errors.log
} > "$OUT"
echo "$(date '+%F %T') wrote $OUT" >> logs/compile.log
