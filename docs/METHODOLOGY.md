# How the gates were chosen

Quality Loop is the **verify** stage of a development loop (see the
[README](../README.md)) — and a verifier is only worth building where the agent
actually fails. So the gates here are not a generic quality checklist. Each one
targets a specific, recurring way coding agents go wrong, and each exists only
because a prose instruction against that failure does not hold.

## The principle

Coding agents fail in a small number of recognizable ways, and they keep failing
the same ways even when the rule against them is written down and in context the
whole time. **Soft corrections don't persist — the model's generative defaults
beat a standing instruction under load.**

So the method is not "add more rules." It is: take a failure that recurs *despite*
a rule, and move that rule out of prose the model can override into a **mechanical
gate** that runs at the moment the failure would reach the human.

## The failures worth gating

A handful of patterns account for most of the friction between an operator and a
coding agent. Each becomes one check:

| Friction | What the agent does | The gate |
|----------|---------------------|----------|
| **Unverified claims** | Says "tests pass / fixed / done / merged" without running the check | **claims** — scans the turn for evidence behind every claim, blocks if it's missing |
| **Wrong altitude** | Answers a yes/no question with a thesis | **altitude** — a linter on the outgoing reply |
| **Ignored standing instructions** | Regenerates patterns you've banned before | **bans** — greps the actual diff against a durable kill-list |
| **Unauthorized irreversible actions** | Merges or pushes to main you never approved | **merge-guard** — a hard pre-tool block with a one-shot token |
| **Re-litigating settled work** | Reopens or re-architects a decision already made | **decision ledger** — the binding decisions re-injected every turn |
| **Over-engineering** | Turns a one-line ask into a sprawling build | **scope** — warns when a small ask produces a big diff or runaway fan-out |

Every row is the same move: a rule the model kept overriding, turned into a check
it cannot talk past.

One recurring failure deliberately has *no* gate — the **wrong mental model**,
where the agent reasons from priors instead of reading the ticket, doc, or code.
That can't be caught by a diff or a message linter, so it's handled upstream
instead: the builder agent is instructed to ground every task in its source before
acting. Not everything belongs in a gate.

## Why two agents, not one

The mechanical gates above check the *envelope* — that a claim cites evidence, that
no banned pattern landed. They cannot tell you the work is actually correct. For
that you need a second judgment, and the tempting cheap version is to have the same
agent re-check its own output, or to retry it until it passes. The evidence says
that version does not work.

The finding that drove the redesign: the quality gain comes from **context
separation, not repetition**. In a controlled study, an agent reviewing its own
work twice in the same session was no better than reviewing it once — while a
verifier in a *fresh* context that never saw the original reasoning caught
significantly more. Re-reading your own work anchors you into rationalizing it; the
context that produced the bug is the worst context to find it from. Separately, LLMs
reliably over-rate their own output, so an agent grading its own homework is biased
by construction.

So the loop splits the work across two agents in two contexts. A **builder** makes
the change. A separate **adversarial verifier**, spawned fresh with only the task,
the diff, and the builder's claims — never the builder's reasoning — re-runs those
claims itself and tries to break the work. It has no edit tools, so it cannot quietly
fix-and-bless; it can only judge. Its verdict is gated the same way the builder's
claims are: it cannot pass without evidence it re-ran something, and it cannot fail
without naming a concrete defect. On a fail, a *fresh* builder turn gets the
findings — bounded to two rounds, then it escalates to you rather than looping in a
stale context.

Two agents is the whole architecture. The research is just as clear that more is
usually worse: for coding there is little to parallelize and a swarm burns many
times the tokens for no reliable gain. The cheap, separated, adversarial pair is
the part that pays.

## Keep it from nagging

An always-on gate that miscalibrates becomes its own friction. So enforcement is
**opt-in**: the teeth only engage while a task is explicitly being run through
`/handout`. Outside it, the gates are silent.

## Close the loop

A nightly job (optional) reads each day's operator corrections and proposes *new*
gates or sharper claim vocabulary — never case-specific bans, and most days it
proposes nothing. The aim is that a correction you make once can become a durable,
machine-checked rule instead of something the agent is asked to "remember harder."
You review every proposal; it never edits the gates itself.

---

The deliverable is small on purpose. The value isn't lines of code — it's the
method: **find where the agent reliably fails, and put a verifier exactly there.**
