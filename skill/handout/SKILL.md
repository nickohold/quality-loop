---
name: handout
description: Run a handed-out task under the quality loop — arms the gates deterministically, executes the task in an isolated worker agent whose output is mechanically verified (claims have evidence, no banned patterns, no over-build) before it returns, then reports the result at the right altitude. Use when you hand out a task and want the end result guaranteed up to par without policing it yourself.
allowed-tools: Bash(touch *), Bash(mkdir *)
---

!`mkdir -p ~/.claude/skills/handout/state && touch ~/.claude/skills/handout/state/active-$(printf '%s' "$PWD" | shasum -a 1 | cut -c1-16)`

# Handout — the trusted task loop

The gates are now **armed** — the line above ran the moment this skill loaded, so
the marker exists regardless of anything you do next. While it is set, the
SubagentStop verifier checks each subagent's output and the Stop verifier checks
your report. Neither depends on you remembering to cooperate.

This is a two-agent loop: a **builder** makes the change, then a separate
**verifier** — in a fresh context that never saw the builder's reasoning — tries to
break it. Context separation is the point: re-checking work in the same context that
produced it does not catch what that context already talked itself past.

## Run the loop

### 1. Hand the task to the builder
Spawn the **handout-worker** agent with the full task and the working directory.
It executes in its own context (your main context stays clean) and its output is
gate-checked on SubagentStop — if a claim lacks evidence or the diff trips a ban,
Claude Code sends the builder back to fix it before it can return to you.

For a trivial one-file change you may do it inline instead; the Stop gate still
checks your turn. For anything larger, delegate to the builder.

### 2. Hand the result to the adversarial verifier
Once the builder returns `status: completed`, spawn the **handout-verifier** agent
in a fresh context. Give it three things and nothing about how the builder reasoned:
the original task, the diff (`git diff HEAD`), and the builder's claims. Its job is
to re-run those claims itself and try to break the work. It has no Edit/Write tools
— it judges, it does not fix. Its `ql-verdict` is gated on SubagentStop: it cannot
pass without evidence it actually ran, nor fail without a concrete defect.

Then act on the verdict:
- **pass** → proceed to report.
- **fail** → hand the findings to a *fresh* builder turn (re-spawn handout-worker
  with the verifier's findings as the task). Re-verify. Cap this at **2 fix rounds**
  — if it still fails, stop and surface the open findings to the operator rather
  than looping. Re-checking in the same stale context is exactly what this avoids.

Skip the verifier only for the trivial inline case in step 1.

### 3. Record binding decisions as they are made
When something is settled ("drop X", "park in a branch", "no Y"), persist it so it
cannot be silently reopened:
```bash
python3 ~/.claude/skills/handout/decision_ledger.py add "$PWD" "drop the legacy adapter"
```

### 4. Report at the right altitude
When the verifier passes, give the operator one bottom-line sentence first, then a
single evidence line (the command/check that proved it). No thesis — the Stop gate
will bounce a report that buries the answer.

The worker ends its turn with a fenced `ql-result` block carrying `status`
(**completed** = done / **working** = still going / **input-required** = stuck,
needs you / **failed** = tried and couldn't) plus per-claim evidence and
`files_changed`. The SubagentStop gate validates that block, not the prose:
completed claims must cite commands that actually ran; working and input-required
pass clean and are never retried; input-required must carry a blocking question.

### 5. Disarm
Once the task is delivered and accepted:
```bash
KEY=$(printf '%s' "$PWD" | shasum -a 1 | cut -c1-16)
rm -f ~/.claude/skills/handout/state/active-$KEY
python3 ~/.claude/skills/handout/decision_ledger.py clear "$PWD"
```
(If you forget, the marker self-expires after 3 hours so it never nags.)

## What's enforced, and where
| Stage | Hook | Checks |
|-------|------|--------|
| builder finishes | SubagentStop | claims have evidence, no banned diff, scope sane → exit 2 sends it back |
| verifier finishes | SubagentStop | verdict is well-formed: no rubber-stamp (pass needs evidence), no vague fail (fail needs a concrete defect) → exit 2 sends it back |
| your report finishes | Stop | altitude of the report; claims (skipped when delegated) |
| any git merge/push-to-main | PreToolUse | blocked unless `/approve-merge` |
| every turn | UserPromptSubmit | re-injects the binding decision ledger |

The arming is mechanical (this skill's `!` line). The verification is mechanical
(hooks): the builder's claims and the verifier's verdict are both gated before they
reach you. The soft steps — delegating, spawning the verifier, disarming — fail
safe: skip delegation and the Stop gate still checks you; skip disarming and the
marker expires on its own. The one judgment the loop asks of you is to actually
spawn the verifier in a fresh context; everything it then asserts is gated.
