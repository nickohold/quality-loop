---
name: handout
description: Run a handed-out task under the quality loop — arms the gates deterministically, executes the task in an isolated worker agent whose output is mechanically verified (claims have evidence, no banned patterns, no over-build) before it returns, then reports the result at the right altitude. Use when you hand out a task and want the end result guaranteed up to par without policing it yourself.
allowed-tools: Bash(touch *), Bash(mkdir *)
---

!`mkdir -p ~/.claude/quality-loop/state && touch ~/.claude/quality-loop/state/active-$(printf '%s' "$PWD" | shasum -a 1 | cut -c1-16)`

# Handout — the trusted task loop

The gates are now **armed** — the line above ran the moment this skill loaded, so
the marker exists regardless of anything you do next. While it is set, the
SubagentStop verifier checks the worker's output and the Stop verifier checks
your report. Neither depends on you remembering to cooperate.

## Run the loop

### 1. Hand the task to the isolated worker
Spawn the **handout-worker** agent with the full task and the working directory.
It executes in its own context (your main context stays clean) and its output is
gate-checked on SubagentStop — if a claim lacks evidence or the diff trips a ban,
Claude Code sends the worker back to fix it before it can return to you.

For a trivial one-file change you may do it inline instead; the Stop gate still
checks your turn. For anything larger, delegate to the worker.

### 2. Record binding decisions as they are made
When something is settled ("drop X", "park in a branch", "no Y"), persist it so it
cannot be silently reopened:
```bash
python3 ~/.claude/quality-loop/decision_ledger.py add "$PWD" "drop the legacy adapter"
```

### 3. Report at the right altitude
When the worker returns, give the operator one bottom-line sentence first, then a
single evidence line (the command/check that proved it). No thesis — the Stop gate
will bounce a report that buries the answer.

### 4. Disarm
Once the task is delivered and accepted:
```bash
KEY=$(printf '%s' "$PWD" | shasum -a 1 | cut -c1-16)
rm -f ~/.claude/quality-loop/state/active-$KEY
python3 ~/.claude/quality-loop/decision_ledger.py clear "$PWD"
```
(If you forget, the marker self-expires after 3 hours so it never nags.)

## What's enforced, and where
| Stage | Hook | Checks |
|-------|------|--------|
| worker finishes | SubagentStop | claims have evidence, no banned diff, scope sane → exit 2 sends it back |
| your report finishes | Stop | altitude of the report; claims (skipped when delegated) |
| any git merge/push-to-main | PreToolUse | blocked unless `/approve-merge` |
| every turn | UserPromptSubmit | re-injects the binding decision ledger |

The arming is mechanical (this skill's `!` line). The verification is mechanical
(hooks). The only soft steps — delegating and disarming — fail safe: skip
delegation and the Stop gate still checks you; skip disarming and the marker
expires on its own.
