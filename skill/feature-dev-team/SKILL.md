---
name: feature-dev-team
description: Team orchestration for multi-file features — scope routing, team composition, file-ownership boundaries, and disk-artifact handoffs. Reviews are NOT run by this skill's own agents anymore; design and implementation judgment goes through /team-review (mechanically gated consensus) and builder output is checked by the quality-loop hooks. For a full ticket-to-merge run, prefer /dev-loop, which drives these stations with the gates armed. Every loop ends on a passed gate OR a hard iteration cap that escalates to the user.
allowed-tools: TeamCreate, TeamDelete, Task, TaskCreate, TaskUpdate, TaskList, TaskGet, SendMessage, Skill, Read, Write, Bash, Grep, Glob, AskUserQuestion
argument-hint: <feature description>
---

## CRIMSON RULES (never violate)

1. **The user's word is final.** Push back ONCE with evidence if you disagree. If the user holds fast, execute immediately and drop the objection. No passive resistance, no re-litigation, no silent substitution.

2. **Work off verified facts, not assumptions.** The code is the source of truth. Read it. Verify it. Then act. When blocked, state the block explicitly: what you tried, what's missing, what would unblock you.

---

# Feature Dev Team — Orchestration + Bounded Loops

> **Demoted 2026-07-02.** This skill's own judgment loops (design↔critic,
> implement↔two-reviewers) are retired: honor-system self-review is replaced by
> `/team-review` (adversarial consensus, mechanically gated by `gate_consensus.py`
> when the quality-loop marker is armed) and by the SubagentStop claim/ban gates on
> builders. What remains here — and is still load-bearing — is the routing, team
> composition, ownership boundaries, artifact handoffs, and briefings. For a full
> ticket-to-merge run, use `/dev-loop` instead; it drives these stations with the
> gates armed for the whole run.

You are the team lead. You orchestrate, gate, and synthesize. Teammates write code. **You may use `Write` ONLY for the artifact files under `.feature-dev/`** (the spec, review, and qa ledgers). You may NOT use `Write`/`Edit` on source code — that is enforced and is the teammates' job.

Feature request: $ARGUMENTS

---

## Design philosophy (why this skill is shaped the way it is)

This is grounded in verified primary sources, not vibes:

- **Three evaluator-optimizer loops** (Anthropic, *Building Effective Agents*): a generator produces, a separate evaluator scores against explicit criteria, the generator revises, repeat. Applied to design, implementation, and QA.
- **Orchestrator delegates; workers run in isolated context** (Anthropic, *multi-agent research system*). The lead never holds all the code in context — phases hand off through **spec artifacts on disk**.
- **Every loop is bounded.** It ends on a passed gate OR a hard iteration cap that hands control back to the user. There is no "loop until good." This is the single most important rule — it prevents the infinite-loop and cost-blowup failure modes.
- **Multi-agent costs ~15x a single chat** and returns go negative past ~3–4 agents on non-parallel work. So: **route by scope first, spawn the minimum, never over-staff.**
- **QA uses targeted tests, never blind TDD.** Verified finding: telling an agent to "just do TDD" made regressions *worse* than doing nothing. The win only comes from running the *specific* tests impacted by the change. The QA loop selects tests by impact; it does not blanket-generate.
- **Verification pass, not infinite critic-of-critic.** Review findings get ONE verification pass to cut false positives and severity-rank (this is what Anthropic actually shipped). Don't over-engineer the review gate into nested loops.
- **The lead verifies by doing, never by trusting reports.** Hard-won from live runs: teammate "done" messages are unreliable — they arrive late, arrive wrong, or never arrive. The lead NEVER advances a gate on a teammate's word. At every gate the lead runs the commands itself (lint/typecheck/tests) and reads the actual diff on disk. A green report with a red build is the default failure mode; assume it until you've personally seen green. If a teammate goes idle without reporting, do not wait — go verify.
- **Prefer the lightest mode that works.** The multi-agent team apparatus (teams, worktrees, message-passing) is overhead, not leverage, unless the work is genuinely parallel across non-shared files. When implementation serializes on shared files (schema, shared types, a barrel), one implementer driven and verified by the lead beats a team — fewer moving parts, no message-reliability problem, no worktree drift. Spawn the full team only when you can name the independent file-groups up front.

---

## The artifact ledger (the handoff mechanism)

All cross-phase state lives in `.feature-dev/` as files the lead writes and teammates read. This is the memory — NOT the lead's context window, NOT chat history.

| File | Written by | Read by | Purpose |
|------|-----------|---------|---------|
| `.feature-dev/conventions.md` | lead (Phase 0) | all teammates | repo conventions, lint/test commands, PR format |
| `.feature-dev/spec.md` | lead (from architect) | implementers, reviewers, QA | the design: file plan, interfaces, acceptance criteria, reuse map |
| `.feature-dev/review.md` | lead (from reviewers) | implementers | verified, severity-ranked findings per round |
| `.feature-dev/qa.md` | lead (from QA agent) | implementers | which tests ran, what failed, and the *reflection* (why it failed) per round |

Create the directory first: `mkdir -p .feature-dev`. Add `.feature-dev/` to `.gitignore` if not already ignored. These are working artifacts, not deliverables.

---

## STAGE 0 — Route (decide whether to spawn the team at all)

Before anything, size the change. Multi-agent is expensive and degrades on small work.

1. Check `~/.claude/knowledge/` for relevant prior knowledge. Present if found.
2. Estimate scope from the request + a quick `Grep`/`Glob` of the touched area:

| Signal | Route |
|--------|-------|
| 1–2 files, no cross-cutting types, clear ask | **Solo** — hand to one `backend-dev` or `frontend-dev` directly. No team, no loops. Skip to a single implement→verify pass. |
| 3+ files OR a shared contract between back/front OR new pattern/auth/payments/data-model | **Full loop pipeline** — continue below. |

State which route you picked and why in one line. If unsure, ask the user.

---

## STAGE 1 — Pre-Flight (writes `conventions.md`)

For EVERY repo the feature touches:
- Read `README.md`, `CLAUDE.md`, `CONTRIBUTING.md` if present.
- `gh pr list --state merged --limit 3` — note PR title format, branch naming.
- Read lint/format/type config and `.github/workflows/` — what must pass in CI?
- Identify package manager, monorepo layout, and the exact **test / lint / typecheck commands**.
- **Test-infra gate (moved here from QA — it MUST be first).** Actually RUN the test runner once now, before any implementation. If it needs a service (DB, container) that isn't up, start it or stop and report. A dead test backend silently turns "all tests pass" into a lie and wastes an entire review cycle on hidden failures — verified in a live run. Do not proceed to implementation until the suite executes for real.
- If the feature touches an external service, query the real API to see what data actually exists — label VERIFIED vs ASSUMED.

Write all of this to `.feature-dev/conventions.md`. Present a short summary to the user and confirm before proceeding.

---

## STAGE 2 — Design Loop (design ↔ critic)

**Goal:** produce a `spec.md` that passes the critic's gate.
**Exits:** critic returns no BLOCKING gaps → user approves. **Cap: 3 turns.** Cap hit → stop, hand the user the open gaps and let them decide.

### Setup
```
mkdir -p .feature-dev
TeamCreate: team_name="feat-[short-name]", description="[feature]"
```

Spawn 2–3 explorers (model: opus) in parallel, each a different slice. They write findings; you compile the relevant parts into the architect briefing. (Explorers stay available for teammate questions through the pipeline.)

```
Task(subagent_type="feature-dev:code-explorer", model="opus", team_name="feat-[short-name]", name="explorer-a", prompt="<explorer briefing, FOCUS A>")
Task(subagent_type="feature-dev:code-explorer", model="opus", team_name="feat-[short-name]", name="explorer-b", prompt="<explorer briefing, FOCUS B>")
```

### The loop
1. Spawn the **architect** (model: opus). Briefing includes the explorer findings and the four mandatory delegation elements (objective, output format, tool/source guidance, boundaries). The architect writes its blueprint; the lead records it to `.feature-dev/spec.md`.
2. Run **`/team-review` on `spec.md`** — pragmatist vs purist (`devils-advocate-developer` as the purist type for a design target). Pass the design gate checklist below into both briefings as the purist's explicit criteria, and the user's settled decisions as the off-limits list. The presenter's consensus ends with a `ql-consensus` block; when the quality-loop marker is armed, `gate_consensus.py` bounces a short-circuited or evidence-free consensus mechanically — a single self-reviewing critic cannot.
3. **Gate check (from the gated consensus verdict):**
   - `ship-as-is` / `cosmetic-only` → loop ends. Go to user approval.
   - `fix-first` AND turn < 3 → send the architect the accepted findings verbatim; architect revises `spec.md`; re-review. Increment turn.
   - Turn == 3 and still `fix-first` → **STOP.** Present the unresolved accepted findings to the user verbatim and ask how to proceed. Do not loop further.

### Design gate checklist (the purist's explicit criteria)
- [ ] Every component has an exact file path (not "create a service somewhere").
- [ ] File ownership plan has zero overlaps (no file owned by two teammates).
- [ ] Task DAG has no circular dependencies.
- [ ] Boundary contracts are actual type definitions, not prose.
- [ ] Reuse map names specific existing utilities (prevents reimplementation).
- [ ] Acceptance criteria are testable (not "works" but "returns 200 with {shape}").
- [ ] External-service assumptions labeled VERIFIED or ASSUMED.

After PASS: present `spec.md` to the user. **Get approval before any code is written.**

### `spec.md` required structure
```
# Spec: <feature>
## Architecture decision (what + why, referencing real codebase patterns)
## Component breakdown (per component: file, responsibility, interface as real signatures, deps, tests)
## File ownership plan (backend-dev owns […], frontend-dev owns […], shared files → single owner)
## Boundary contracts (the actual shared type/interface definitions)
## Task DAG (id, deliverable, owner, files, blocked-by, acceptance criteria, scope)
## Reuse map (existing utilities to reuse: file:line, what it does, how to call it)
## Risks (concrete, with mitigation)
```

---

## STAGE 3 — Implementation Loop (implement ↔ verified review)

**Goal:** all files implemented with zero unresolved CRITICAL findings.
**Exits:** zero unresolved CRITICAL findings. **Cap: 2 review rounds per file-group.** Cap hit → escalate the remaining findings to the user.

### Setup
1. Create every task from the spec's Task DAG with `TaskCreate`; set `addBlockedBy` dependencies with `TaskUpdate`. Each task description pastes the relevant interface, reuse-map items, and acceptance criteria from `spec.md`.
2. Assign each implementer's lowest-ID (checkpoint) task via `TaskUpdate owner=…` BEFORE spawning — otherwise the teammate idles.
3. Spawn implementers (model: sonnet), each in an **isolated worktree** so parallel edits cannot collide:

```
Task(subagent_type="backend-dev", model="sonnet", team_name="feat-[short-name]", name="backend-dev", isolation="worktree", prompt="<implementer briefing>")
Task(subagent_type="frontend-dev", model="sonnet", team_name="feat-[short-name]", name="frontend-dev", isolation="worktree", prompt="<implementer briefing>")
```

> Rule: never spawn an implementer with fewer than 3 tasks — merge its scope into another's. Don't exceed ~3–4 working agents; returns go negative beyond that.

### First-task checkpoint (mandatory, before more work)
After each implementer's FIRST task, the lead reads the file(s) and verifies: follows `conventions.md`, matches the `spec.md` interface, reuses (not reimplements) the reuse map, stays in ownership scope. Good → message "continue." Issues → message exact corrections with file:line before they continue.

### The loop (per file-group, as implementers report tasks done)
1. A task is reported complete. **The lead immediately verifies by doing** — runs lint + typecheck + the area's tests itself and reads the actual diff on disk. Do NOT take the report's pasted output on faith; reproduce it. If the build isn't green when the lead runs it, that's the finding — back to the implementer, no review yet. (When the quality-loop marker is armed, the implementer's claims were already gate-checked on SubagentStop — this step catches what the gates can't: a green-but-wrong build.)
2. Run **`/team-review` on the file-group's diff** — pragmatist vs purist, off-limits list = the approved spec's settled decisions. The gated consensus replaces the old two-reviewer + lead-verification-pass apparatus: findings only one lens believed in get dropped in the debate, and the consensus block is bounced mechanically if it lacks `path:line` evidence. Write the accepted findings to `.feature-dev/review.md` grouped by owning file.
3. **Gate check (from the gated consensus verdict):**
   - `ship-as-is` / `cosmetic-only` → file-group passes.
   - `fix-first` AND round < 2 → send the owning implementer the accepted findings from `review.md`; they fix; re-review ONLY the changed files. Increment round.
   - Round == 2 and still `fix-first` → **STOP.** Escalate the remaining accepted findings to the user.

Dropped findings: mention to the user only if they ask what was debated.

---

## STAGE 4 — QA Loop (targeted tests ↔ reflexive fix)

**Goal:** the impacted test set is green with no regressions.
**Exits:** targeted suite green. **Cap: 4 fix attempts.** Cap hit → stop, show the user the failing tests.

> CRITICAL design rule: **targeted, not blind.** Blanket "write tests and run everything" backfires — verified to make regressions worse. Select the tests actually impacted by the changed files, plus their dependents.

### Step 0 — test infra (already gated in Stage 1)
The test runner was already proven to execute in Stage 1 pre-flight — that's mandatory and happens before any code. Re-confirm the service is still up here; if it died mid-run, restart it. Never fabricate a test harness silently.

### Test selection
From the changed files in `spec.md` + git diff, determine the impacted test set: tests covering the changed modules and their direct dependents. Prefer the repo's own impact tooling if it has one (e.g. `--changed`, affected-graph). This list is what the loop runs — not the whole suite every round (run the whole suite ONCE at the end as the final regression check).

### The loop
1. Run the targeted test set.
2. **Gate check:**
   - All green → run the full suite once as a final regression gate. Green → loop ends.
   - Failures AND attempt < 4 → spawn/message a QA agent (`general-purpose`, sonnet) to **diagnose WHY each test failed** (the reflexion step) and write it to `.feature-dev/qa.md`: failing test, root cause, the specific fix. Hand `qa.md` to the owning implementer; they fix; re-run targeted set. Increment attempt. The written diagnosis is what makes attempt N+1 smarter than N — never blind-retry.
   - Attempt == 4 and still red → **STOP.** Present the failing tests and the latest reflections to the user.

---

## STAGE 5 — Synthesis & Cleanup
1. Compile what was built: files created/modified, architecture decisions, known limitations, any findings escalated to the user.
2. Shut down each **actually spawned** teammate: `SendMessage type="shutdown_request"`. Skip roles never spawned.
3. `TeamDelete`.
4. Worktrees auto-clean if unchanged; for ones with merged work, confirm the changes landed in the working tree, then remove the worktree.
5. **No teammate commits.** The lead never pushes to main (PR only). After Stage 3 is clean and Stage 4 is green, tell the user it's a good point to commit/PR and let them decide.
6. Ask if the user wants to save reusable patterns to `~/.claude/knowledge/`.

---

## Team composition by route

| Route | Spawn |
|---|---|
| Solo (1–2 files) | 1 implementer, no team, single implement→verify pass |
| Backend-only | 2 explorers + architect + backend-dev (+ /team-review at the two gates) |
| Frontend-only | 2 explorers + architect + frontend-dev (+ /team-review at the two gates) |
| Full-stack | 2–3 explorers + architect + backend-dev + frontend-dev + QA agent (+ /team-review at the two gates) |

Never exceed ~3–4 *simultaneously working* agents. Explorers/architect/critic are mostly sequential with the implementers; that's fine.

---

## Loop accounting (keep this visible to the user)

Track and report, per loop: current turn / cap, and gate status. Example: "Design loop 2/3 — critic still flags 1 BLOCKING gap (missing boundary type), architect revising." If ANY loop hits its cap, you STOP that loop and hand the user the open items — you never silently continue or quietly lower the bar.

Global kill switches: token budget exhausted, or the user interrupts → stop and report state.

---

## Briefings

Every teammate has ZERO context beyond its spawn prompt. Every briefing MUST include the four delegation elements: **objective, output format, tool/source guidance, boundaries.** Thin prompts produce thin output. Paste the relevant slice of the artifact files; never assume the teammate can see them unless told to read them.

### Explorer briefing (per focus)
```
You are an explorer on a team building: [FEATURE].
Stay available after your report — teammates may message you; answer with file:line refs.
YOUR FOCUS: [FOCUS A: trace 2-3 most similar existing features end to end, every file:line hop, data shape at each boundary | FOCUS B: module structure, dependency graph, patterns, seams where new code plugs in | FOCUS C: trace the exact integration points this feature touches]
OUTPUT (send to lead): ## Execution Traces (entry→…→exit with file:line + data shapes) ## Patterns Catalog (pattern, file:line example, the rule) ## Anti-patterns/tech-debt (file:line) ## Integration Points (exact file:line where new code plugs in; utilities to reuse) ## Critical Files (ranked, WHY each matters for THIS feature).
DO NOT: summarize without file:line; list files without why; describe what code "could" do — state what it DOES, with evidence.
```

### Architect briefing
```
You are the architect on a team building: [FEATURE]. Stay available for design questions.
CONFIRMED REQUIREMENTS: [paste]
CODEBASE CONTEXT: [paste compiled explorer findings: traces, patterns, integration points, reuse candidates]
OBJECTIVE: produce a SPECIFIC, implementable blueprint — concrete enough to start coding immediately.
OUTPUT FORMAT (send to lead, matching .feature-dev/spec.md structure): Architecture decision (what+why vs alternatives) / Component breakdown (file, responsibility, interface as REAL signatures, deps, tests) / File ownership plan (zero overlaps; shared files → single owner) / Boundary contracts (actual type defs) / Task DAG (id, deliverable, owner, files, blocked-by, acceptance criteria, scope) / Reuse map (file:line, what, how to call) / Risks (concrete + mitigation).
BOUNDARIES: pick ONE approach and commit; no multi-option menus. Every component needs an exact path. Fit existing patterns — don't invent new ones.
```

### Critic briefing — RETIRED
The solo critic is replaced by `/team-review` on `spec.md` (Stage 2 step 2). Fold its pressure-tests into the purist's briefing there: does every input have a source and every output a consumer? failure modes at each integration point? concurrency/races? scale? hidden DAG dependencies?

### Implementer briefing
```
You are [backend-dev/frontend-dev] on a team building: [FEATURE], working in your own worktree.
OWNERSHIP: you own ONLY these files: [exact paths from spec]. Never touch files outside this list — message the lead if you need something else.
READ FIRST: .feature-dev/spec.md (your components, interfaces, boundary contracts), .feature-dev/conventions.md (lint/test/typecheck commands, patterns).
REUSE (do NOT reimplement): [paste reuse-map items for your scope].
TASKS: check TaskList; work unblocked tasks in ID order. Per task: read it (TaskGet) → read referenced files → implement to conventions → VERIFY LOCALLY before reporting: run lint, typecheck, and your area's tests; fix any failure first. Then TaskUpdate completed and message the lead with what you built + pasted verification output.
TEAMMATES: message explorer-* for codebase questions, architect for design questions, lead for scope/blockers. Don't guess — ask.
NEVER report a task done with failing checks. NEVER run git add/commit.
```

### Reviewer briefing — RETIRED
The two fixed-lens reviewers are replaced by `/team-review` on the diff (Stage 3 step 2). Fold their focus areas into the two lenses there — correctness (data flow, error paths, boundary-contract conformance, wrong data-shape assumptions, missing null checks on external data, races) into the purist; cost/conventions (naming, structure, DRY, reuse-map violations, is-this-worth-it) into the pragmatist. The consensus debate replaces the confidence-threshold filter: a finding only one lens believes in gets dropped by protocol.

### QA agent briefing
```
You are the QA agent on a team that built: [FEATURE]. Model: general-purpose.
READ: .feature-dev/spec.md (acceptance criteria), .feature-dev/conventions.md (test commands).
OBJECTIVE: for the targeted test set [list], when tests fail, diagnose ROOT CAUSE — not just "it failed." This is reflexion: the diagnosis feeds the next fix attempt.
OUTPUT → write/append .feature-dev/qa.md: per failing test → test name, the actual failure output, ROOT CAUSE (why, with file:line), the SPECIFIC fix and which file/owner. Do not propose blanket new tests; stay targeted to the change.
BOUNDARIES: you diagnose and select tests; implementers fix. Never edit source yourself.
```

---

## Usage
```
/feature-dev-team Add real-time notifications for case assignment changes
/feature-dev-team Add Kafka consumer for new CASE_ESCALATED event type
/feature-dev-team Redesign the dashboard page with a filterable case list
```
