#!/bin/bash
# SubagentStop hook: verify the worker's output. On failure exit 2 (retry), capped.
QL="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAX_ATTEMPTS=3; TTL_MIN=180
INPUT=$(cat)

CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null); [ -z "$CWD" ] && CWD="$PWD"
TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
AGENT=$(echo "$INPUT" | jq -r '.agent_id // "anon"' 2>/dev/null)
MARKER="$QL/state/active-$(printf '%s' "$CWD" | shasum -a 1 | cut -c1-16)"

[ -f "$MARKER" ] || exit 0
[ -n "$(find "$MARKER" -mmin +$TTL_MIN 2>/dev/null)" ] && exit 0

CNT="$QL/state/attempts-$AGENT"
N=$(cat "$CNT" 2>/dev/null || echo 0)

# Route the adversarial verifier: it emits ql-verdict (not ql-result), so it must
# be checked by the verdict gate, never the builder's claim gate.
if [ "$(cd "$QL" && python3 gate_verdict.py "$TRANSCRIPT" --is-verdict 2>/dev/null)" = "yes" ]; then
  RESULT=$(cd "$QL" && python3 verify.py "$TRANSCRIPT" "$CWD" --role verifier 2>/dev/null)
  [ -z "$RESULT" ] && exit 0
  mkdir -p "$QL/logs"
  echo "$RESULT" | jq -r '.warnings[]? | "WARN(verifier): " + .' >> "$QL/logs/warnings.log" 2>/dev/null
  if [ "$(echo "$RESULT" | jq -r '.pass' 2>/dev/null)" = "false" ]; then
    if [ "$N" -ge "$MAX_ATTEMPTS" ]; then
      echo "$(date '+%F %T') verifier gate gave up after $N attempts ($AGENT)" >> "$QL/logs/warnings.log"
      rm -f "$CNT"; exit 0
    fi
    echo $((N+1)) > "$CNT"
    echo "VERIFIER GATE FAILED — fix each item before finishing:" >&2
    echo "$RESULT" | jq -r '.blocks | to_entries[] | "  \(.key+1). \(.value)"' >&2
    exit 2
  fi
  rm -f "$CNT"
  echo "VERIFIER VERDICT: $(cd "$QL" && python3 gate_verdict.py "$TRANSCRIPT" --verdict 2>/dev/null)" >&2
  exit 0
fi

# Route the team-review presenter: it emits ql-consensus, checked by the consensus gate.
if [ "$(cd "$QL" && python3 gate_consensus.py "$TRANSCRIPT" --is-consensus 2>/dev/null)" = "yes" ]; then
  RESULT=$(cd "$QL" && python3 verify.py "$TRANSCRIPT" "$CWD" --role consensus 2>/dev/null)
  [ -z "$RESULT" ] && exit 0
  mkdir -p "$QL/logs"
  echo "$RESULT" | jq -r '.warnings[]? | "WARN(consensus): " + .' >> "$QL/logs/warnings.log" 2>/dev/null
  if [ "$(echo "$RESULT" | jq -r '.pass' 2>/dev/null)" = "false" ]; then
    if [ "$N" -ge "$MAX_ATTEMPTS" ]; then
      echo "$(date '+%F %T') consensus gate gave up after $N attempts ($AGENT)" >> "$QL/logs/warnings.log"
      rm -f "$CNT"; exit 0
    fi
    echo $((N+1)) > "$CNT"
    echo "CONSENSUS GATE FAILED — fix each item before finishing:" >&2
    echo "$RESULT" | jq -r '.blocks | to_entries[] | "  \(.key+1). \(.value)"' >&2
    exit 2
  fi
  rm -f "$CNT"
  echo "CONSENSUS VERDICT: $(cd "$QL" && python3 gate_consensus.py "$TRANSCRIPT" --verdict 2>/dev/null)" >&2
  exit 0
fi

# A turn that ends by messaging a teammate is mid-conversation (debate rounds,
# confirmer handoff) — non-terminal, never gated, never burns an attempt.
if [ "$(cd "$QL" && python3 -c 'import sys,qllib; print("yes" if any(u["name"]=="SendMessage" for u in qllib.turn_tool_uses(qllib.read_lines(sys.argv[1]))) else "no")' "$TRANSCRIPT" 2>/dev/null)" = "yes" ]; then
  rm -f "$CNT"
  exit 0
fi

# Non-terminal results are not failures: never retry, never burn an attempt.
STATUS=$(cd "$QL" && python3 gate_claims.py "$TRANSCRIPT" --status 2>/dev/null)
if [ "$STATUS" = "working" ] || [ "$STATUS" = "input-required" ]; then
  rm -f "$CNT"
  if [ "$STATUS" = "input-required" ]; then
    Q=$(cd "$QL" && python3 -c 'import sys,gate_claims as g; b=g.parse_block(g.qllib.last_assistant_text(g.qllib.read_lines(sys.argv[1]))) or {}; print(b.get("blocking_question",""))' "$TRANSCRIPT" 2>/dev/null)
    echo "WORKER BLOCKED (input-required): $Q" >&2
  fi
  exit 0
fi

RESULT=$(cd "$QL" && python3 verify.py "$TRANSCRIPT" "$CWD" 2>/dev/null)
[ -z "$RESULT" ] && exit 0
mkdir -p "$QL/logs"
echo "$RESULT" | jq -r '.warnings[]? | "WARN(worker): " + .' >> "$QL/logs/warnings.log" 2>/dev/null

if [ "$(echo "$RESULT" | jq -r '.pass' 2>/dev/null)" = "false" ]; then
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
