---
name: handout
description: Run a handed-out task under the quality loop — grounds the task in its spec, executes via the right agents, then mechanically verifies the result (claims have evidence, no banned patterns, no over-build, on-altitude report) before handing it back. Use when you hand out a task and want the end result guaranteed up to par without policing it yourself.
---

# Handout — the trusted task loop

Goal: hand out a task and be sure the result is up to par. This loop makes the
quality gates **mechanical**, so correctness does not depend on the assistant
remembering the rules under load. The Stop hook (`quality-loop/gate-stop.sh`)
auto-runs the verifier and **blocks the turn** until every gate passes — but only
while this loop's marker is set. That is what gives the gates teeth without
nagging every other session.

## The loop

### 0. Arm the gates
Set the opt-in marker so the Stop verifier and ledger injection turn on for this workspace:
```bash
KEY=$(printf '%s' "$PWD" | shasum -a 1 | cut -c1-16)
touch ~/.claude/quality-loop/state/active-$KEY
```

### 1. Ground the task in its source of truth
- Restate the task in **one sentence**: goal + trigger + expected output.
- If it names a ticket / design doc / specific file, **fetch and read it first**. Do not infer the goal from priors.
- If goal, trigger, or data shape is genuinely ambiguous, ask **one** tight question. Otherwise proceed.

### 2. Record binding decisions as they are made
Whenever something is settled ("drop X", "park in a branch", "no Y"), persist it:
```bash
python3 ~/.claude/quality-loop/decision_ledger.py add "$PWD" "drop the legacy adapter"
```
The ledger is re-injected every turn while the loop is active, so it cannot be
silently reopened or contradicted.

### 3. Execute via the right tool
Prefer specialized agents over generic ones. Build the **smallest** thing that
satisfies the actual ask — no new services, deps, or abstractions unless
required. Cap fan-out.

### 4. Verify before reporting (mechanical, automatic)
When the turn tries to end, the Stop hook runs `verify.py`:
- **claim gate** — every "tests pass / fixed / merged / deployed / DB shows" must have matching tool-evidence this turn, or it blocks.
- **bans gate** — the diff is grepped against `config/bans.txt`.
- **altitude gate** — if a question was asked, the reply must lead with the decision, under ~14 lines, no code/IDs/tables.
- **scope gate** (warn) — small ask + big diff, or runaway agents/processes.

If it blocks, **fix the named items and finish again** — that is the inner loop.
You can dry-run it any time:
```bash
python3 ~/.claude/quality-loop/verify.py <transcript_path> "$PWD"
```

### 5. Report up at the right altitude
One bottom-line answer first. Then a single **evidence line**: what command/check
proved it (test output, the query result, the diff). No thesis.

### 6. Merges stay locked
`merge-guard.sh` blocks `git merge` / push-to-main / `gh pr merge` globally. Only
after an explicit go-ahead does the user run `/approve-merge` (one-shot); then retry.

### 7. Disarm
When the task is delivered and accepted:
```bash
KEY=$(printf '%s' "$PWD" | shasum -a 1 | cut -c1-16)
rm -f ~/.claude/quality-loop/state/active-$KEY
python3 ~/.claude/quality-loop/decision_ledger.py clear "$PWD"
```

## Why this works
Soft corrections do not persist; mechanical checks do. This loop moves each
quality rule into a place a machine checks: claims need evidence, bans are
grepped, decisions are re-injected, altitude is linted, merges are locked. The
nightly compiler proposes new rules from each day's corrections so the system
gets less wrong over time.
