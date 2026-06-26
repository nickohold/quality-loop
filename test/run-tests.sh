#!/usr/bin/env bash
# Self-contained tests for the quality-loop gates. No install required —
# runs the engine in place from src/. Exits non-zero on any failure.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$REPO/src"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"; rm -f "$SRC/state/active-"* "$SRC/state/merge-approved" 2>/dev/null' EXIT
mkdir -p "$SRC/state"
PASS=0; FAIL=0
ok(){ echo "  ok   - $1"; PASS=$((PASS+1)); }
no(){ echo "  FAIL - $1"; FAIL=$((FAIL+1)); }
assert_has(){ echo "$1" | grep -q "$2" && ok "$3" || no "$3"; }
assert_empty(){ [ -z "$1" ] && ok "$2" || no "$2 (got: $1)"; }

# ---------- a BAD turn: question answered with a thesis + unproven claims + banned diff ----------
BAD="$TMP/bad"; mkdir -p "$BAD/src"; ( cd "$BAD"; git init -q; git config user.email t@t.t; git config user.name t
  printf 'export class Foo {\n  run() { return 1 }\n}\n' > src/foo.service.ts; git add src/foo.service.ts; git commit -qm init
  printf 'export class Foo {\n  // increment counter\n  run() { return 1 }\n}\nexport interface Bar { id: string }\n' > src/foo.service.ts
  for i in 1 2 3 4 5; do printf 'a\n' > "f$i"; git add "f$i"; done )
cat > "$TMP/bad.jsonl" <<'J'
{"type":"user","message":{"role":"user","content":"why does the storm happen? just change this one line"}}
{"type":"assistant","message":{"content":[{"type":"text","text":"# Root cause\nhere\n```ts\nx=1\n```\nsrc/foo.service.ts:42\n## Fix\na\nb\nc\nd\ne\nf\ng\nh\ni\nj\nk\nl\nall tests pass and it is merged now"}]}}
J
echo "BAD turn:"
R=$(cd "$SRC" && python3 verify.py "$TMP/bad.jsonl" "$BAD")
assert_has "$R" '"pass": false' "verify reports pass:false"
assert_has "$R" 'tests pass' "claim gate catches unproven 'tests pass'"
assert_has "$R" 'merged' "claim gate catches unproven 'merged'"
assert_has "$R" 'increment counter' "bans gate catches narrating comment"
assert_has "$R" 'interface Bar' "bans gate catches type in service file"
assert_has "$R" 'thesis' "altitude gate catches thesis answer to a question"

# ---------- a GOOD turn: command, evidence ran, clean short reply ----------
GOOD="$TMP/good"; mkdir -p "$GOOD/src"; ( cd "$GOOD"; git init -q; git config user.email t@t.t; git config user.name t
  printf 'export const x = 1\n' > src/ok.ts; git add src/ok.ts; git commit -qm init
  printf 'export const x = 2\n' > src/ok.ts; git add src/ok.ts )
cat > "$TMP/good.jsonl" <<'J'
{"type":"user","message":{"role":"user","content":"fix the off-by-one in ok.ts"}}
{"type":"assistant","message":{"content":[{"type":"text","text":"Working"},{"type":"tool_use","name":"Bash","input":{"command":"npm test -- ok.ts"}}]}}
{"type":"assistant","message":{"content":[{"type":"text","text":"Done. Tests pass."}]}}
J
echo "GOOD turn:"
R=$(cd "$SRC" && python3 verify.py "$TMP/good.jsonl" "$GOOD")
assert_has "$R" '"pass": true' "clean verified turn passes"

# ---------- Stop hook opt-in gating ----------
echo "Stop hook:"
KEY=$(printf '%s' "$BAD" | shasum -a 1 | cut -c1-16)
rm -f "$SRC/state/active-$KEY"
OUT=$(printf '{"cwd":"%s","transcript_path":"%s/bad.jsonl","stop_hook_active":false}' "$BAD" "$TMP" | bash "$SRC/gate-stop.sh")
assert_empty "$OUT" "silent when no marker (no global nag)"
touch "$SRC/state/active-$KEY"
OUT=$(printf '{"cwd":"%s","transcript_path":"%s/bad.jsonl","stop_hook_active":false}' "$BAD" "$TMP" | bash "$SRC/gate-stop.sh")
assert_has "$OUT" '"decision":"block"' "blocks when marker is set"
rm -f "$SRC/state/active-$KEY"

# ---------- merge guard ----------
echo "Merge guard:"
PUSH="git pu""sh ori""gin ma""in"
OUT=$(printf '{"tool_input":{"command":"%s"}}' "$PUSH" | bash "$SRC/merge-guard.sh")
assert_has "$OUT" 'deny' "blocks push-to-main without token"
touch "$SRC/state/merge-approved"
OUT=$(printf '{"tool_input":{"command":"%s"}}' "$PUSH" | bash "$SRC/merge-guard.sh")
assert_empty "$OUT" "allows with one-shot token"
[ -f "$SRC/state/merge-approved" ] && no "token consumed" || ok "token consumed after use"
OUT=$(printf '{"tool_input":{"command":"ls -la"}}' | bash "$SRC/merge-guard.sh")
assert_empty "$OUT" "normal command passes"
OUT=$(printf '{"tool_input":{"command":"git merge-base main HEAD"}}' | bash "$SRC/merge-guard.sh")
assert_empty "$OUT" "git merge-base (read-only) is not blocked"

# ---------- SubagentStop verifier: exit 2 on failure, with marker ----------
echo "SubagentStop verifier:"
KEY=$(printf '%s' "$BAD" | shasum -a 1 | cut -c1-16)
rm -f "$SRC/state/active-$KEY" "$SRC/state/attempts-"*
printf '{"cwd":"%s","transcript_path":"%s/bad.jsonl","agent_id":"t1"}' "$BAD" "$TMP" | bash "$SRC/gate-subagent-stop.sh" 2>/dev/null
[ "$?" -eq 0 ] && ok "silent (exit 0) when no marker" || no "should be silent without marker"
touch "$SRC/state/active-$KEY"
ERR=$(printf '{"cwd":"%s","transcript_path":"%s/bad.jsonl","agent_id":"t1"}' "$BAD" "$TMP" | bash "$SRC/gate-subagent-stop.sh" 2>&1 >/dev/null); RC=$?
[ "$RC" -eq 2 ] && ok "exit 2 forces worker to retry on failure" || no "expected exit 2, got $RC"
assert_has "$ERR" 'tests pass' "failure reason names the unproven claim"
# attempt cap: after MAX_ATTEMPTS, give up (exit 0)
printf '{"cwd":"%s","transcript_path":"%s/bad.jsonl","agent_id":"t1"}' "$BAD" "$TMP" | bash "$SRC/gate-subagent-stop.sh" >/dev/null 2>&1
printf '{"cwd":"%s","transcript_path":"%s/bad.jsonl","agent_id":"t1"}' "$BAD" "$TMP" | bash "$SRC/gate-subagent-stop.sh" >/dev/null 2>&1
printf '{"cwd":"%s","transcript_path":"%s/bad.jsonl","agent_id":"t1"}' "$BAD" "$TMP" | bash "$SRC/gate-subagent-stop.sh" >/dev/null 2>&1; RC=$?
[ "$RC" -eq 0 ] && ok "attempt cap stops the loop (exit 0 after max)" || no "attempt cap failed, got $RC"
rm -f "$SRC/state/active-$KEY" "$SRC/state/attempts-"*

# ---------- claim gate trusts delegated work ----------
echo "Delegation skip:"
cat > "$TMP/deleg.jsonl" <<'J'
{"type":"user","message":{"role":"user","content":"do the migration"}}
{"type":"assistant","message":{"content":[{"type":"text","text":"Delegating."},{"type":"tool_use","name":"Agent","input":{"prompt":"migrate it"}}]}}
{"type":"assistant","message":{"content":[{"type":"text","text":"Done. All tests pass and it is deployed."}]}}
J
R=$(cd "$SRC" && python3 gate_claims.py "$TMP/deleg.jsonl" "$GOOD")
assert_empty "$R" "main thread not blocked for relaying a delegated worker's result"

echo
echo "==== $PASS passed, $FAIL failed ===="
[ "$FAIL" -eq 0 ]
