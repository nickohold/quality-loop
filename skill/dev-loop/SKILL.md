---
name: dev-loop
description: Run one work order through the full automated development line — intake, recon, design, adversarial design review, gated build with adversarial verification, targeted QA, adversarial result review with bounded auto-rework, and a three-line human delivery. Arms the quality-loop gates once for the whole run; every station's output is verified by hooks, not trust, and nothing merges without /approve-merge. Use when handing over a Linear ticket, GitHub issue, spec file, or "next" and wanting a finished, human-approved change back.
allowed-tools: Bash(touch *), Bash(mkdir *), Task, Skill, SendMessage, Read, Write, Grep, Glob, TaskCreate, TaskUpdate, TaskList, TaskGet, AskUserQuestion
argument-hint: <linear-id | github-issue-url | spec-file-path | next>
---

!`mkdir -p ~/.claude/skills/handout/state && touch ~/.claude/skills/handout/state/active-$(printf '%s' "$PWD" | shasum -a 1 | cut -c1-16)`

# Dev Loop — one work order, end to end

Work order: $ARGUMENTS

The gates are **armed** — the line above ran the moment this skill loaded. For the
rest of this run, every subagent that stops is checked mechanically on SubagentStop
(claims, bans, scope, verdicts, review consensus), your own reports are checked on
Stop, and merges are blocked until the operator runs `/approve-merge`. None of that
depends on you or any teammate remembering to cooperate.

You are the lead. You orchestrate, route, and verify — you never edit source.
**You may `Write` only under `.dev-loop/`** (the run's artifacts). Teammates write
code; hooks judge them.

## The artifact ledger

All cross-station state lives on disk, not in your context:

| File | Written at | Contains |
|------|-----------|----------|
| `.dev-loop/task.md` | Station 1 | the normalized work order + acceptance criteria |
| `.dev-loop/stack.md` | Station 1 | stack, exact lint/typecheck/test/build commands, conventions |
| `.dev-loop/spec.md` | Station 3 | the approved design: file plan, interfaces, ownership, reuse map |
| `.dev-loop/qa.md` | Station 6 | failing test → root cause → specific fix, per attempt |

`mkdir -p .dev-loop` first; add it to `.gitignore` if not ignored.

## Station 1 — Intake

Normalize whatever `$ARGUMENTS` is into `.dev-loop/task.md` (goal, constraints,
acceptance criteria, links):

- **Linear ID** → fetch the issue (Linear MCP tools) and any linked docs.
- **GitHub issue URL** → `gh issue view <url> --json title,body,comments`.
- **Spec file path** → read it.
- **`next`** → pull the top item in Ready state from the team's Linear backlog,
  confirm the pick with the operator in one line before proceeding.

Then spawn `repo-preflight` for every repo the task touches; write its findings to
`.dev-loop/stack.md`. It must contain the **exact quality-gate commands** and prove
the test runner actually executes (run it once now — a dead test backend turns
"tests pass" into a lie downstream).

**Size the change.** 1–2 files, no cross-cutting types, clear ask → skip the line:
run the plain `/handout` loop (builder + verifier) and jump straight to Station 8.
Everything larger continues below. State the route in one line.

## Station 2 — Recon

Spawn `flow-mapper` on the flows the task touches. Read-only; its map (including
silent failure points) feeds the architect's briefing. Skip only when the task is
green-field with nothing to map.

## Station 3 — Design

Spawn the architect (`feature-dev:code-architect`) with: the task, the flow map,
`stack.md` conventions, and the requirement that every component gets an exact file
path, real interface signatures, a zero-overlap file-ownership plan, a reuse map,
and testable acceptance criteria. Record its blueprint to `.dev-loop/spec.md`.

## Station 4 — Design review (adversarial, gated)

Run `/team-review` on `.dev-loop/spec.md` — pragmatist vs purist (use
`devils-advocate-developer` as the purist type for a design target). Their
consensus must end with the `ql-consensus` block; the armed hook bounces a lazy or
evidence-free consensus automatically, so you only ever see a gated verdict.

- `ship-as-is` / `cosmetic-only` → present `spec.md` to the operator, get approval,
  continue. **No code before operator approval of the spec.**
- `fix-first` → hand the accepted findings to the architect verbatim; it revises;
  re-review. **Cap: 3 design rounds**, then stop and escalate the open findings.

## Station 5 — Build + inspect (the handout station)

Route by the spec's file plan: `backend-dev` for backend files, `frontend-dev` for
UI, both for mixed — each in an **isolated worktree** (`isolation: "worktree"`)
with its ownership list from `spec.md`. Never more than 3–4 working agents.

Every builder's spawn prompt must contain: its file ownership, the relevant
`spec.md` interfaces and reuse map, the `stack.md` commands, **and the full
contract from `~/.claude/skills/dev-loop/contract.md` pasted verbatim at the end.**
That contract is what the SubagentStop gate parses; a spawn prompt without it
produces an agent that gets bounced with no idea why.

When a builder returns `status: completed`:

1. **Verify by doing.** Run lint/typecheck/the area's tests yourself from
   `stack.md` and read the diff on disk. A green report with a red build is the
   default failure mode — assume it until you've personally seen green.
2. Spawn `handout-verifier` in a fresh context with exactly three things: the task,
   the diff (`git diff HEAD`), and the builder's claims — nothing about how the
   builder reasoned. Its `ql-verdict` is gated: it cannot rubber-stamp or vaguely
   object.
3. Verdict `fail` → hand the findings to a fresh builder turn. **Cap: 2 fix rounds
   per builder**, then escalate.

## Station 6 — QA (targeted, never blind)

From the diff + `spec.md`, select the tests actually impacted by the change and
their direct dependents — never blanket-generate tests, verified to make
regressions worse. Run the targeted set:

- Green → run the full suite ONCE as the final regression check; green → continue.
- Failures → spawn a QA agent (`general-purpose`) to diagnose ROOT CAUSE per
  failing test into `.dev-loop/qa.md`; hand that to the owning builder; re-run.
  **Cap: 4 attempts**, then stop and show the operator the failing tests plus the
  latest diagnosis.

## Station 7 — Result review (adversarial, gated, auto-rework)

Run `/team-review` on the final diff — pragmatist vs purist, off-limits list =
everything the operator already decided (read the decision ledger:
`python3 ~/.claude/skills/handout/decision_ledger.py show "$PWD"`). Same
mechanically-gated consensus.

- `ship-as-is` / `cosmetic-only` → Station 8.
- `fix-first` → the accepted findings (each carrying a gated `path:line`) become
  the new work order: back to Station 5 with the findings as the task, then
  Station 6, then re-review here. Count reworks mechanically:

```bash
REWORK=~/.claude/skills/handout/state/rework-$(printf '%s' "$PWD" | shasum -a 1 | cut -c1-16)
N=$(cat "$REWORK" 2>/dev/null || echo 0); echo $((N+1)) > "$REWORK"
```

**Cap: 2 rework cycles** (`N ≥ 2` → stop, disarm, escalate the open findings to the
operator). Never silently continue past the cap.

## Station 8 — Delivery (human by design)

Run `/pre-merge-review`: all five gates green when YOU run them, then exactly three
lines to the operator — URL, the one thing only a human eye can catch, plain-English
description. Nothing more. The merge stays locked until the operator runs
`/approve-merge` (one-shot token, consumed on use). You never merge.

## Disarm

On delivery, escalation, or abort:

```bash
KEY=$(printf '%s' "$PWD" | shasum -a 1 | cut -c1-16)
rm -f ~/.claude/skills/handout/state/active-$KEY ~/.claude/skills/handout/state/rework-$KEY
python3 ~/.claude/skills/handout/decision_ledger.py clear "$PWD"
```

(If you forget, the marker self-expires after 3 hours.)

## Loop accounting

Keep the operator oriented with one line per station transition: station, round
count vs cap, gate status. Any cap hit → STOP that loop, hand over the open items
verbatim, never quietly lower the bar. Record binding decisions the moment they are
made: `python3 ~/.claude/skills/handout/decision_ledger.py add "$PWD" "<decision>"`.

## What is mechanical vs judgment

Mechanical (hooks, survive your mistakes): arming, claim/ban/scope checks on every
builder, verdict checks on the verifier, consensus checks on both reviews, the
altitude of your own reports, the merge lock, the marker TTL. Judgment (yours):
routing and sizing, briefing quality, verify-by-doing at Station 5, when to
escalate early. The soft steps fail safe — skip one and a gate still catches the
output; the one thing the loop cannot do without you is a good briefing.
