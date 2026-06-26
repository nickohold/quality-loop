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
assert_has "$R" 'ql-result' "claim gate blocks a turn with no ql-result block"
assert_has "$R" 'increment counter' "bans gate catches narrating comment"
assert_has "$R" 'interface Bar' "bans gate catches type in service file"
assert_has "$R" 'thesis' "altitude gate catches thesis answer to a question"

# ---------- a GOOD turn: command, evidence ran, clean short reply ----------
GOOD="$TMP/good"; mkdir -p "$GOOD/src"; ( cd "$GOOD"; git init -q; git config user.email t@t.t; git config user.name t
  printf 'export const x = 1\n' > src/ok.ts; git add src/ok.ts; git commit -qm init
  printf 'export const x = 2\n' > src/ok.ts; git add src/ok.ts )
GOODFILE="$GOOD/src/ok.ts"
cat > "$TMP/good.jsonl" <<J
{"type":"user","message":{"role":"user","content":"fix the off-by-one in ok.ts"}}
{"type":"assistant","message":{"content":[{"type":"text","text":"Working"},{"type":"tool_use","name":"Bash","input":{"command":"npm test -- ok.ts"}}]}}
{"type":"assistant","message":{"content":[{"type":"text","text":"\`\`\`ql-result\nstatus: completed\nsummary: fixed off-by-one\nclaims:\n  - claim: tests pass\n    evidence:\n      type: command\n      ref: npm test -- ok.ts\n      result: ok\n  - claim: x is now 2\n    evidence:\n      type: file\n      ref: $GOODFILE:1\nfiles_changed:\n  - src/ok.ts\n\`\`\`"}]}}
J
echo "GOOD turn:"
R=$(cd "$SRC" && python3 verify.py "$TMP/good.jsonl" "$GOOD")
assert_has "$R" '"pass": true' "completed turn with real command + file evidence passes"

# ---------- completed claiming a command that never ran -> blocked ----------
echo "Phantom-command turn:"
cat > "$TMP/phantom.jsonl" <<'J'
{"type":"user","message":{"role":"user","content":"fix it"}}
{"type":"assistant","message":{"content":[{"type":"text","text":"```ql-result\nstatus: completed\nsummary: did it\nclaims:\n  - claim: tests pass\n    evidence:\n      type: command\n      ref: pytest -q\n      result: green\nfiles_changed:\n  - src/ok.ts\n```"}]}}
J
R=$(cd "$SRC" && python3 verify.py "$TMP/phantom.jsonl" "$GOOD")
assert_has "$R" 'did NOT run' "completed claiming a command that never ran is blocked"

# ---------- input-required exits clean and never retries ----------
echo "input-required turn:"
cat > "$TMP/inputreq.jsonl" <<'J'
{"type":"user","message":{"role":"user","content":"do the thing"}}
{"type":"assistant","message":{"content":[{"type":"text","text":"```ql-result\nstatus: input-required\nsummary: blocked on a decision\nblocking_question: which database should this target?\nclaims:\nfiles_changed:\n```"}]}}
J
R=$(cd "$SRC" && python3 verify.py "$TMP/inputreq.jsonl" "$GOOD")
assert_has "$R" '"pass": true' "input-required with a blocking_question passes the claim gate"
IKEY=$(printf '%s' "$GOOD" | shasum -a 1 | cut -c1-16)
rm -f "$SRC/state/attempts-ir" ; touch "$SRC/state/active-$IKEY"
printf '{"cwd":"%s","transcript_path":"%s/inputreq.jsonl","agent_id":"ir"}' "$GOOD" "$TMP" | bash "$SRC/gate-subagent-stop.sh" >/dev/null 2>&1; RC=$?
[ "$RC" -eq 0 ] && ok "input-required exits clean (no retry)" || no "expected exit 0, got $RC"
[ ! -f "$SRC/state/attempts-ir" ] && ok "input-required never burns an attempt" || no "attempt counter was written"
rm -f "$SRC/state/active-$IKEY" "$SRC/state/attempts-ir"

# ---------- input-required WITHOUT a blocking_question is blocked ----------
echo "input-required missing question:"
cat > "$TMP/noq.jsonl" <<'J'
{"type":"user","message":{"role":"user","content":"do the thing"}}
{"type":"assistant","message":{"content":[{"type":"text","text":"```ql-result\nstatus: input-required\nsummary: stuck\nblocking_question:\nclaims:\nfiles_changed:\n```"}]}}
J
R=$(cd "$SRC" && python3 gate_claims.py "$TMP/noq.jsonl" "$GOOD")
assert_has "$R" 'blocking_question is empty' "input-required without a question is blocked"

# ---------- failed is not asked for success evidence ----------
echo "failed turn:"
cat > "$TMP/failed.jsonl" <<'J'
{"type":"user","message":{"role":"user","content":"build it"}}
{"type":"assistant","message":{"content":[{"type":"text","text":"```ql-result\nstatus: failed\nsummary: could not build\nclaims:\n  - claim: build fails on missing dep\n    evidence:\n      type: command\n      ref: npm run build\n      result: error TS2307\nfiles_changed:\n```"}]}}
J
R=$(cd "$SRC" && python3 gate_claims.py "$TMP/failed.jsonl" "$GOOD")
assert_empty "$R" "failed turn with failure evidence is not asked to prove success"

# ---------- files_changed mismatch is caught ----------
echo "Undeclared-edit turn:"
cat > "$TMP/undeclared.jsonl" <<'J'
{"type":"user","message":{"role":"user","content":"fix it"}}
{"type":"assistant","message":{"content":[{"type":"text","text":"```ql-result\nstatus: completed\nsummary: done\nclaims:\n  - claim: looked at it\n    evidence:\n      type: file\n      ref: REPLACE:1\nfiles_changed:\n```"}]}}
J
sed -i.bak "s#REPLACE#$GOODFILE#" "$TMP/undeclared.jsonl"
R=$(cd "$SRC" && python3 gate_claims.py "$TMP/undeclared.jsonl" "$GOOD")
assert_has "$R" 'files_changed omits' "edited file missing from files_changed is caught"

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
rm -f "$SRC/state/merge-approved"
OUT=$(printf '{"tool_input":{"command":"git merge feature"}}' | bash "$SRC/merge-guard.sh")
assert_has "$OUT" 'deny' "git merge <branch> is blocked"
OUT=$(printf '{"tool_input":{"command":"git push --force"}}' | bash "$SRC/merge-guard.sh")
assert_has "$OUT" 'deny' "git push --force is blocked"
OUT=$(printf '{"tool_input":{"command":"git push -f origin feature"}}' | bash "$SRC/merge-guard.sh")
assert_has "$OUT" 'deny' "git push -f is blocked"
OUT=$(printf '{"tool_input":{"command":"gh pr merge 12 --squash"}}' | bash "$SRC/merge-guard.sh")
assert_has "$OUT" 'deny' "gh pr merge is blocked"
OUT=$(printf '{"tool_input":{"command":"echo \\"about to merge\\" && git status"}}' | bash "$SRC/merge-guard.sh")
assert_empty "$OUT" "compound read-only command mentioning merge is not blocked"
OUT=$(printf '{"tool_input":{"command":"git log --oneline main"}}' | bash "$SRC/merge-guard.sh")
assert_empty "$OUT" "git log on main is not blocked"
OUT=$(printf '{"tool_input":{"command":"git status && git merge feature"}}' | bash "$SRC/merge-guard.sh")
assert_has "$OUT" 'deny' "merge hidden in a compound command is still blocked"
rm -f "$SRC/state/merge-approved"; touch "$SRC/state/merge-approved"
OUT=$(printf '{"tool_input":{"command":"git merge feature"}}' | bash "$SRC/merge-guard.sh")
assert_empty "$OUT" "token allows the first real block"
[ -f "$SRC/state/merge-approved" ] && no "token consumed on first block" || ok "token consumed on first block"

# ---------- lead's prose Stop report is NOT claim-checked ----------
echo "Lead report exemption:"
LEAD="$TMP/lead"; mkdir -p "$LEAD"; ( cd "$LEAD"; git init -q; git config user.email t@t.t; git config user.name t
  printf 'a\n' > f; git add f; git commit -qm init )
cat > "$TMP/lead.jsonl" <<'J'
{"type":"user","message":{"role":"user","content":"did it land?"}}
{"type":"assistant","message":{"content":[{"type":"text","text":"Yes. The PR is merged and all tests pass."}]}}
J
R=$(cd "$SRC" && python3 verify.py "$TMP/lead.jsonl" "$LEAD" --role lead)
assert_has "$R" '"pass": true' "lead prose report with merged/tests pass and no ql-result block is not blocked"
R=$(cd "$SRC" && python3 verify.py "$TMP/lead.jsonl" "$LEAD")
assert_has "$R" 'ql-result' "same turn as a worker (default role) IS still claim-checked"

# ---------- SubagentStop verifier: exit 2 on failure, with marker ----------
echo "SubagentStop verifier:"
KEY=$(printf '%s' "$BAD" | shasum -a 1 | cut -c1-16)
rm -f "$SRC/state/active-$KEY" "$SRC/state/attempts-"*
printf '{"cwd":"%s","transcript_path":"%s/bad.jsonl","agent_id":"t1"}' "$BAD" "$TMP" | bash "$SRC/gate-subagent-stop.sh" 2>/dev/null
[ "$?" -eq 0 ] && ok "silent (exit 0) when no marker" || no "should be silent without marker"
touch "$SRC/state/active-$KEY"
ERR=$(printf '{"cwd":"%s","transcript_path":"%s/bad.jsonl","agent_id":"t1"}' "$BAD" "$TMP" | bash "$SRC/gate-subagent-stop.sh" 2>&1 >/dev/null); RC=$?
[ "$RC" -eq 2 ] && ok "exit 2 forces worker to retry on failure" || no "expected exit 2, got $RC"
assert_has "$ERR" 'ql-result' "failure reason names the missing ql-result block"
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
