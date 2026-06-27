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
instead: the worker agent is instructed to ground every task in its source before
acting. Not everything belongs in a gate.

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
