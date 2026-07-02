---
name: team-review
description: Two named review agents — a pragmatist and a purist of correctness — debate a target (PR, design, plan, code) directly via SendMessage until they reach unanimous consensus on a single shared review. Use this whenever the user wants a balanced, adversarially-validated review and explicitly asks for a "team", "two reviewers", "pragmatic vs correct", "adversarial review", or asks you to run reviewers that "discuss with each other" or "reach consensus". Also use when a single reviewer's output would be either too anxious (over-flag) or too lax (under-flag) for the stakes — anything heading to production, anything the user wants to ship with confidence but not over-engineer. Do not use this for trivial diffs (a one-line typo fix), exploratory questions ("what does this code do?"), or when the user explicitly wants a single-perspective lens.
---

# Team Review

A two-agent adversarial review loop. One agent is a pragmatist (real production cost, ship-it lens); the other is a purist (correctness, edge cases, standards). They debate findings directly via SendMessage until they reach unanimous consensus. Only findings BOTH accept survive — no split-the-difference.

## When this is the right tool

The user wants more than one perspective on a non-trivial review target, and wants the perspectives to actually engage with each other (not be presented as separate opinions for the user to reconcile). Typical signals:

- "Get two opinions on this"
- "Pragmatic vs correct review"
- "Run a team review"
- "Have them debate / discuss / reach consensus"
- "Review this and tell me what's worth fixing" — when the user trusts you to filter
- High-stakes PR / design / plan where a single reviewer's lens would over- or under-call

Skip this for trivial diffs, "how does X work" questions, or when the user wants a one-lens read.

## The protocol

### 1. Spawn both agents in the same message, in parallel

Two `Agent` tool calls in one block, with `run_in_background: true` on both. Each gets a `name` (so they can `SendMessage` each other), `subagent_type` chosen for the lens, and a spawn prompt that includes the OTHER agent's name plus the binding protocol.

**Subagent type selection** (pick what fits the stack and the lens):

| Lens | Default | When to swap |
|---|---|---|
| pragmatist (production cost, ship-it) | `backend-dev` for backend code; `frontend-dev` for UI; `general-purpose` if stack-neutral | If a domain-specific dev agent exists (e.g. an iOS dev), prefer it |
| purist (correctness, standards) | `feature-dev:code-reviewer` | `devils-advocate-developer` if the target is a plan/design rather than code |

Each spawn prompt must contain:

- **Their lens** in one sentence
- **What the OTHER agent will push for** (so they can engage, not just produce their own siloed list)
- **The protocol** (next section, copied into both prompts verbatim with names swapped)
- **The off-limits list** (decisions already made by the user — see "Off-limits" below)
- **Their role** (presenter vs confirmer)

### 2. The protocol both agents follow

Copy this into both prompts, swapping `<self>` ↔ `<other>`:

> **Process — BINDING:**
> 1. Read the target. Form your initial findings.
> 2. SendMessage to `<other>` with your findings: `file:line — severity — issue — fix`.
> 3. Receive `<other>`'s findings.
> 4. You MUST exchange ≥3 messages each way. This is a real debate, not a handoff. Defend, withdraw, propose compromise. Specifically:
>    - Round 1: opening findings.
>    - Round 2: respond to each of their findings (agree / push back / compromise).
>    - Round 3+: resolve disagreements. Settle each finding to ACCEPTED (both agree) or DROPPED (no consensus).
> 5. Findings without unanimous consent are DROPPED — no split-the-difference, no "include with caveat".
> 6. **[Presenter only]** When `<other>` sends `consensus reached`, produce the final consolidated review and return it, ENDING with the fenced `ql-consensus` block (format below). When the quality-loop is armed, a hook parses that block mechanically and bounces you back if it is missing, short-circuited (fewer than 3 real exchanges), or carries accepted findings without a resolving `path:line`.
> 6. **[Confirmer only]** When you've reached consensus, SendMessage `<other>` the final agreed list, then return the literal string `consensus reached` and nothing else.
>
> **Hard rules:**
> - Decided & off-limits: <list of items the user has settled and does not want re-litigated>
> - No findings about PR size, commit messages, refactor opportunities outside the diff, or anything not provable from a `file:line` in the target.
> - Plain text output is INVISIBLE to your teammate. Only SendMessage reaches them. Keep messages tight.

### 3. The final output format (presenter returns this)

```
Shared review — <target> (pragmatist + purist consensus)

Accepted findings (both reviewers concur):
1. file:line — SEVERITY — issue — recommended fix
2. ...

Dropped (raised but did not reach consensus):
- file:line — issue — reason dropped

Exchange summary: <one line — how many rounds, who held what line>

Verdict: ship-as-is / fix-first / cosmetic-only
```

Then, as the LAST thing in the message, the machine-readable block (this is what the consensus gate parses — the prose above is for the human):

````
```ql-consensus
verdict: ship-as-is | fix-first | cosmetic-only
rounds: <true number of exchange rounds>
summary: <one line>
accepted:
  - finding: <the defect, one line>
    evidence: <path:line — must exist, line must be real>
dropped:
  - finding: <what was raised>
    reason: <why it did not reach consensus>
```
````

Gate rules (enforced by `gate_consensus.py` on SubagentStop when the quality-loop marker is armed): `verdict` must be one of the three values verbatim; `rounds` must be ≥3 AND the transcript must actually contain ≥3 SendMessage calls — the count is taken from the transcript, not from what you write; every `accepted` entry needs `evidence` as a resolving `path:line`; `fix-first` with an empty `accepted` list is rejected. Empty `accepted:` and `dropped:` sections are valid for a clean `ship-as-is`.

Zero accepted findings is a valid outcome — state it plainly, no padding.

## Off-limits — pass user decisions in

Anything the user has already decided is off the table. Pass these into both agent prompts as a "Hard rules — do not raise; if your teammate raises, kill it together" list. Examples that have come up:

- "Duplication between function A and function B stays as-is — user decision X."
- "PR size is not a finding."
- "The OAuth install flow lives in a separate PR — don't review it here."
- "We're not switching auth methods again."

Without this, the agents will surface settled decisions and waste rounds on them.

## Coordinator (your) role during the run

While the agents debate, you DO NOT inject yourself into their conversation. You only act when:

1. **Both agents have gone idle without one of them returning the final review** → see "Failure mode" below.
2. **They get stuck in a non-terminating ping-pong** (more than ~6 rounds with no convergence) → SendMessage the presenter to force-finalize.
3. **One agent dies / errors** → re-spawn it with the same prompt, telling it to read the existing exchange (via transcript) and pick up.

Notifications you'll see while waiting: `{"type":"idle_notification","from":"<name>","summary":"[to <other>] Round N ..."}`. These are progress signals. Don't reply to them — they're informational. Just keep waiting until consensus.

## Failure mode: consensus reached but no return

**Known issue:** the presenter agent can complete the consensus exchange (you'll see a Round N+1 message summarized as "consensus reached" or "resolution") and then go idle without emitting the final review as its return value.

**Workaround:**

1. Find the presenter's transcript file:
   ```bash
   ls -t /Users/nick/.claude/projects/-<project-encoded>/<session-id>/subagents/agent-a<presenter-name>-*.jsonl | head -1
   ```
2. Extract the last assistant text:
   ```bash
   tail -c 60000 <transcript> | python3 -c "
   import sys, json
   data = sys.stdin.buffer.read().decode('utf-8', errors='ignore')
   for line in reversed(data.split('\n')):
       if not line.strip(): continue
       try:
           obj = json.loads(line)
           msg = obj.get('message', {})
           if msg.get('role') == 'assistant':
               for c in msg.get('content', []):
                   if c.get('type') == 'text':
                       print(c.get('text', ''))
                       sys.exit(0)
       except Exception: continue
   "
   ```
3. Present that output to the user as the consensus review.
4. SendMessage a `shutdown_request` to both agents to clean up:
   ```json
   {"type": "shutdown_request", "request_id": "team-lead-close-<name>", "reason": "review delivered"}
   ```

The review WAS produced; it just didn't terminate cleanly. Don't lose it.

## Why it works

The value isn't two agents producing two lists. It's the consensus filter:

- A finding only one agent cares about gets dropped — that's usually a lens-bias artifact (over-cautious from purist, or under-cautious from pragmatist).
- A finding both agents agree on has survived a real adversarial pass — much higher signal.
- The user sees ONE list, not two, so they don't have to do the reconciliation work themselves.

This trades wall-clock time (the debate adds ~30-90s over a single review) for review quality. Worth it when the stakes warrant it. Not worth it for low-stakes changes.

## Anti-patterns

- **Spawning sequentially** — defeats the debate. Always parallel, both in one message.
- **Using `general-purpose` for both** — the lens difference comes from the subagent_type's built-in personality. Picking specialized types gives sharper, more distinct findings.
- **Skipping the off-limits list** — the agents will burn rounds on settled decisions.
- **Letting them split the difference** — the protocol's "drop if no consensus" rule is the entire point. A "compromise" finding is usually a finding only one reviewer believed in.
- **Injecting yourself into the debate** — the user invoked this skill because they wanted the agents to arbitrate among themselves. If you nudge mid-flight, you've biased the consensus.
