#!/bin/bash
# Cron entry point for the nightly friction compiler — the flywheel.
#
# This is LLM-POWERED on purpose. It gathers the day's operator messages
# (cheap, programmatic) and then asks a headless `claude -p` run to UNDERSTAND
# them and propose concrete rule deltas. Understanding friction is a semantic
# job; a keyword search can only find patterns you already listed.
#
# Cost: one Claude call per night. That is the point — it buys comprehension.
# It only PROPOSES (writes a markdown file); it never edits your gates.
#
# Enable with:  crontab -e   then add (note the PATH line, cron has a bare PATH):
#   PATH=/usr/local/bin:/usr/bin:/bin:$HOME/.claude/local
#   0 7 * * *  /bin/bash ~/.claude/skills/handout/nightly-compile.sh
QL="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$QL" || exit 1
mkdir -p logs state
DAY=$(date '+%Y-%m-%d')
OUT="logs/proposals-$DAY.md"

CORPUS=$(python3 nightly-compile.py 2>>logs/compile-errors.log)
if [ ! -s "$CORPUS" ]; then
  printf '# Friction proposals — %s\n\nNo correction signals in the last 24h. Clean day.\n' "$DAY" > "$OUT"
  echo "$(date '+%F %T') no signals -> $OUT" >> logs/compile.log
  exit 0
fi

CLAUDE="$(command -v claude || echo "$HOME/.claude/local/claude")"
if [ ! -x "$CLAUDE" ] && ! command -v claude >/dev/null 2>&1; then
  echo "$(date '+%F %T') ERROR: 'claude' CLI not found on PATH" >> logs/compile.log
  exit 1
fi

read -r -d '' PROMPT <<'EOF'
You are auditing ONE day of an operator's own messages to an AI coding agent, to
make a mechanical quality-gate system smarter. The corpus is on stdin; each block
is something the OPERATOR typed (corrections, frustration, redirection), tagged
with timestamp and repo.

Your job — use judgment, do not keyword-match:
1. Identify the recurring friction, INCLUDING novel kinds a regex would miss.
   Infer intent: what did the agent do that the operator is reacting to?
2. Cluster into a few themes, most impactful first.
3. For each theme, propose ONE concrete, machine-enforceable delta the operator
   can paste in to approve — prefer a kill-list line in EXACTLY this format:
       kind::regex::message
   where kind is one of: added_comment | type_in_class | concept | dependency | generic
   …or a new claim phrase for the claim gate, or a decision-ledger / knowledge note
   when no line-level rule fits.
4. Be conservative: only propose rules that would not over-fire on innocent code.

Output a dated markdown proposal. Per theme: a one-line title, 1-2 verbatim
quotes as evidence, why it recurs, and the exact delta to paste. No preamble.
Do NOT edit any files — output the proposal only.
EOF

{
  echo "# Friction proposals — $DAY"
  echo
  cat "$CORPUS" | "$CLAUDE" -p "$PROMPT" 2>>logs/compile-errors.log
} > "$OUT"

echo "$(date '+%F %T') wrote $OUT" >> logs/compile.log
